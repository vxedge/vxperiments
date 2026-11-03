#!/usr/bin/env python3
"""A kuksa.val.v2 test client: one JSON line per event on stdout, nothing else.

Every call goes through the generated kuksa.val.v2 stubs that kuksa-client 0.6.0 ships. The SDK's
high-level VSSClient is not used: its get is kuksa.val.v1, and its publish and subscribe fall back
to v1, so a v1 answer could pass for a v2 one.

A connection that is not ready within --connect-s prints {"result": "refused"}. Every other
outcome is "ok" or "error" with the gRPC status code, so a caller classifies the output and never
the exit code alone.
"""

import argparse
import json
import queue
import sys
import threading
import time

import grpc
from kuksa.val.v2 import types_pb2 as types
from kuksa.val.v2 import val_pb2 as val
from kuksa.val.v2 import val_pb2_grpc as val_grpc

SCALAR = {
    types.DATA_TYPE_STRING: ("string", str),
    types.DATA_TYPE_BOOLEAN: ("bool", lambda s: {"true": True, "false": False}[s.lower()]),
    types.DATA_TYPE_INT8: ("int32", int),
    types.DATA_TYPE_INT16: ("int32", int),
    types.DATA_TYPE_INT32: ("int32", int),
    types.DATA_TYPE_INT64: ("int64", int),
    types.DATA_TYPE_UINT8: ("uint32", int),
    types.DATA_TYPE_UINT16: ("uint32", int),
    types.DATA_TYPE_UINT32: ("uint32", int),
    types.DATA_TYPE_UINT64: ("uint64", int),
    types.DATA_TYPE_FLOAT: ("float", float),
    types.DATA_TYPE_DOUBLE: ("double", float),
}


def emit(**fields):
    fields.setdefault("t", round(time.time(), 6))
    print(json.dumps(fields, sort_keys=True), flush=True)


def rpc_error(op, exc, **extra):
    emit(op=op, result="error", code=exc.code().name, details=exc.details(), **extra)


def value_out(v):
    kind = v.WhichOneof("typed_value")
    if kind is None:
        return None
    got = getattr(v, kind)
    return list(got.values) if kind.endswith("_array") else got


def connect(args):
    channel = grpc.insecure_channel(args.server)
    try:
        grpc.channel_ready_future(channel).result(timeout=args.connect_s)
    except grpc.FutureTimeoutError:
        emit(op="connect", result="refused", server=args.server, waited_s=args.connect_s)
        sys.exit(3)
    return channel, val_grpc.VALStub(channel)


def metadata(stub, path):
    resp = stub.ListMetadata(val.ListMetadataRequest(root=path))
    for m in resp.metadata:
        if m.path == path:
            return m
    raise LookupError(path)


FIELDS = {"string": str, "bool": lambda s: {"true": True, "false": False}[s.lower()],
          "int32": int, "int64": int, "uint32": int, "uint64": int, "float": float, "double": float}


def typed(meta, text, as_type=None):
    """The value as the signal's own type, or as --as names, to send a deliberately wrong one."""
    if as_type:
        return types.Value(**{as_type: FIELDS[as_type](text)})
    if meta.data_type not in SCALAR:
        raise ValueError(f"{meta.path}: {types.DataType.Name(meta.data_type)} is not supported")
    field, conv = SCALAR[meta.data_type]
    return types.Value(**{field: conv(text)})


def cmd_info(args, stub):
    r = stub.GetServerInfo(val.GetServerInfoRequest())
    emit(op="info", result="ok", name=r.name, version=r.version, commit=r.commit_hash)


def cmd_metadata(args, stub):
    m = metadata(stub, args.path)
    emit(op="metadata", result="ok", path=m.path, id=m.id,
         data_type=types.DataType.Name(m.data_type), entry_type=types.EntryType.Name(m.entry_type),
         unit=m.unit, min=value_out(m.min), max=value_out(m.max),
         allowed=value_out(m.allowed_values), deprecation=m.deprecation)


def cmd_list(args, stub):
    resp = stub.ListMetadata(val.ListMetadataRequest(root=args.root))
    rows = sorted((m.path, types.EntryType.Name(m.entry_type), types.DataType.Name(m.data_type))
                  for m in resp.metadata)
    emit(op="list", result="ok", root=args.root, count=len(rows), signals=rows)


def cmd_get(args, stub):
    r = stub.GetValue(val.GetValueRequest(signal_id=types.SignalID(path=args.path)))
    has = r.HasField("data_point") and r.data_point.HasField("value")
    emit(op="get", result="ok", path=args.path, value=value_out(r.data_point.value) if has else None)


def cmd_publish(args, stub):
    v = typed(metadata(stub, args.path), args.value, args.as_type)
    stub.PublishValue(val.PublishValueRequest(signal_id=types.SignalID(path=args.path),
                                              data_point=types.Datapoint(value=v)))
    emit(op="publish", result="ok", path=args.path, value=value_out(v))


def cmd_actuate(args, stub):
    v = typed(metadata(stub, args.path), args.value, args.as_type)
    start = time.monotonic()
    try:
        stub.Actuate(val.ActuateRequest(signal_id=types.SignalID(path=args.path), value=v),
                     timeout=args.timeout_s)
    except grpc.RpcError as exc:
        rpc_error("actuate", exc, path=args.path, elapsed_ms=round((time.monotonic() - start) * 1e3, 3))
        return
    emit(op="actuate", result="ok", path=args.path, value=value_out(v),
         elapsed_ms=round((time.monotonic() - start) * 1e3, 3))


def cmd_subscribe(args, stub):
    req = val.SubscribeRequest(signal_paths=args.paths)
    stream = stub.Subscribe(req, timeout=args.timeout_s)
    emit(op="subscribe", result="open", paths=args.paths)
    seen = 0
    try:
        for resp in stream:
            for path, dp in resp.entries.items():
                emit(op="update", result="ok", path=path,
                     value=value_out(dp.value) if dp.HasField("value") else None)
            seen += 1
            if args.count and seen >= args.count:
                stream.cancel()
                break
    except grpc.RpcError as exc:
        if exc.code() != grpc.StatusCode.CANCELLED:
            rpc_error("subscribe", exc, responses=seen)
            return
    emit(op="subscribe", result="done", responses=seen)


def cmd_provide_actuator(args, stub):
    """Claim actuators, then answer the databroker's actuation requests as --mode says.

    ok: answer at once. slow:MS: answer after MS. silent: never answer. error: answer with
    ERROR_CODE_INVALID_ARGUMENT. exit-after:N: answer N requests, then drop the stream.
    """
    mode, _, arg = args.mode.partition(":")
    outbox = queue.Queue()
    outbox.put(val.OpenProviderStreamRequest(provide_actuation_request=val.ProvideActuationRequest(
        actuator_identifiers=[types.SignalID(path=p) for p in args.paths])))
    stop = object()

    def requests():
        while True:
            item = outbox.get()
            if item is stop:
                return
            yield item

    stream = stub.OpenProviderStream(requests())
    timer = threading.Timer(args.duration_s, lambda: (outbox.put(stop), stream.cancel()))
    timer.daemon = True
    timer.start()
    answered = 0
    try:
        for resp in stream:
            kind = resp.WhichOneof("action")
            if kind == "provide_actuation_response":
                emit(op="provide", result="ok", paths=args.paths, mode=args.mode)
                continue
            if kind != "batch_actuate_stream_request":
                emit(op="provider-message", result="ok", kind=kind)
                continue
            for req in resp.batch_actuate_stream_request.actuate_requests:
                sid = req.signal_id
                emit(op="actuation-request", result="ok",
                     signal=sid.path or sid.id, value=value_out(req.value))
                if mode == "silent":
                    continue
                if mode == "slow":
                    time.sleep(int(arg) / 1e3)
                code = types.ERROR_CODE_INVALID_ARGUMENT if mode == "error" else types.ERROR_CODE_OK
                outbox.put(val.OpenProviderStreamRequest(
                    batch_actuate_stream_response=val.BatchActuateStreamResponse(
                        signal_id=sid, error=types.Error(code=code, message=mode))))
                answered += 1
                emit(op="actuation-answer", result="ok", code=types.ErrorCode.Name(code))
            if mode == "exit-after" and answered >= int(arg):
                emit(op="provide", result="dropped", answered=answered)
                outbox.put(stop)
                stream.cancel()
                return
    except grpc.RpcError as exc:
        if exc.code() != grpc.StatusCode.CANCELLED:
            rpc_error("provide", exc, answered=answered)
            return
    emit(op="provide", result="done", answered=answered)


def cmd_provide_signal(args, stub):
    """Claim one sensor and publish --values on the provider stream, one per --interval-ms."""
    meta = metadata(stub, args.path)
    outbox = queue.Queue()
    outbox.put(val.OpenProviderStreamRequest(provide_signal_request=val.ProvideSignalRequest(
        signals_sample_intervals={meta.id: types.SampleInterval(interval_ms=args.interval_ms)})))
    stop = object()

    def requests():
        while True:
            item = outbox.get()
            if item is stop:
                return
            yield item

    stream = stub.OpenProviderStream(requests())
    published = 0
    values = args.values.split(",")
    try:
        for resp in stream:
            kind = resp.WhichOneof("action")
            if kind == "provide_signal_response":
                emit(op="provide-signal", result="ok", path=args.path, id=meta.id)
                for i, text in enumerate(values):
                    outbox.put(val.OpenProviderStreamRequest(publish_values_request=val.PublishValuesRequest(
                        request_id=i + 1, data_points={meta.id: types.Datapoint(value=typed(meta, text))})))
                    time.sleep(args.interval_ms / 1e3)
            elif kind == "publish_values_response":
                r = resp.publish_values_response
                errors = {k: types.ErrorCode.Name(v.code) for k, v in r.status.items()}
                emit(op="published", result="ok" if not errors else "error",
                     request_id=r.request_id, errors=errors)
                published += 1
            else:
                emit(op="provider-message", result="ok", kind=kind)
            if published >= len(values):
                break
    except grpc.RpcError as exc:
        rpc_error("provide-signal", exc, published=published)
        return
    finally:
        outbox.put(stop)
    emit(op="provide-signal", result="done", published=published)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--server", default="127.0.0.1:55555")
    p.add_argument("--connect-s", type=float, default=5.0)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info")
    for name in ("metadata", "get"):
        sub.add_parser(name).add_argument("path")
    sub.add_parser("list").add_argument("root", nargs="?", default="Vehicle")
    for name in ("publish", "actuate"):
        s = sub.add_parser(name)
        s.add_argument("path")
        s.add_argument("value")
        s.add_argument("--timeout-s", type=float, default=10.0)
        s.add_argument("--as", dest="as_type", choices=sorted(FIELDS))
    s = sub.add_parser("subscribe")
    s.add_argument("paths", nargs="+")
    s.add_argument("--count", type=int, default=0)
    s.add_argument("--timeout-s", type=float, default=30.0)
    s = sub.add_parser("provide-actuator")
    s.add_argument("paths", nargs="+")
    s.add_argument("--mode", default="ok")
    s.add_argument("--duration-s", type=float, default=30.0)
    s = sub.add_parser("provide-signal")
    s.add_argument("path")
    s.add_argument("--values", required=True)
    s.add_argument("--interval-ms", type=int, default=100)
    args = p.parse_args()

    _, stub = connect(args)
    handler = globals()["cmd_" + args.cmd.replace("-", "_")]
    try:
        handler(args, stub)
    except grpc.RpcError as exc:
        rpc_error(args.cmd, exc)
        sys.exit(2)
    except (LookupError, ValueError, KeyError) as exc:
        emit(op=args.cmd, result="error", code="CLIENT", details=str(exc))
        sys.exit(2)


if __name__ == "__main__":
    main()
