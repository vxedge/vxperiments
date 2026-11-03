# exp-015: Kuksa use cases on vx-vehicle-03

What the signal plane does with real providers and subscribers, on
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03) with kuksa-databroker 0.7.1. It repeats every check
in [`results/signal-plane-2026-11-03`](../../results/signal-plane-2026-11-03), then adds
`kuksa.val.v2` cases: subscribers, a signal provider, a CAN feed replayed from a dump, actuation
providers that answer and ones that do not, and denial from another slice.

```bash
podman build -t localhost/vxperiments/kv2:1 tools/kv2
../../vehicles/vx-vehicle-03/build.sh
VXEDGE_BUILD=<vxedge>/target/debug ./run.sh     # needs a sudo timestamp, see run.sh
```

## Pinned

| What | Image |
|---|---|
| databroker 0.7.1, under test | `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd` |
| databroker CLI 0.7.1, v1 checks only | `ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:871649f14576871ca048ed5f4ff2c109656d748877d8ddb8609c67091c9f9c33` |
| can-provider 0.5.1, the CAN feed | `ghcr.io/eclipse-kuksa/kuksa-can-provider/can-provider@sha256:41f5abffe30be4dd0bf6d82f28ca149d327e2d6de8619b562a12035a30da0c8e` |
| kv2, the v2 test client | built from [`tools/kv2`](tools/kv2): `python:3.12-slim` by digest, `kuksa-client==0.6.0` and its dependencies by hash |

The databroker CLI speaks `kuksa.val.v1` and `sdv.databroker.v1`, and v1 is deprecated, so it stays
for the existing checks only. kv2 calls the generated `kuksa.val.v2` stubs that kuksa-client 0.6.0
ships, not the SDK's `VSSClient`: that client's `get` is v1, and its publish and subscribe fall back
to v1, so a v1 answer could pass for a v2 one. kuksa-client 0.6.0 and the databroker 0.7.1 build
from the same kuksa-proto commit, `28bf76a`.

can-provider is not pure v2. Through kuksa-client 0.6.0 it publishes over v2 `PublishValue` and
falls back to v1 if v2 is missing, its subscriptions try v2 first, and its `get` is v1 only.

## How a result is read

Every client runs test-side in a node's network namespace, so only container nodes host one: the
broker is on `hpc1` (`adas`), the allowed clients on `cabin1` and `hpc1`, the denied one on
`zone-rl` (`infotainment`).

kv2 prints one JSON line per event. A connection that is not ready in time prints `refused`; every
other outcome is `ok` or a gRPC status code. The scripts classify output, never exit codes, and
anything that is neither `ok` nor `refused` fails both the allowed and the denied checks. A denial
also needs the sender's frames to reach its bridge port, disjoint VLANs in the transcript, and a
final read showing the value unchanged.

`PASS` and `FAIL` lines check what upstream documents (`UNAVAILABLE` with no provider,
`ALREADY_EXISTS` for a second claim) or that a case really ran. `OBS` lines record what the
databroker did where its documentation does not say, such as a provider that never answers. A
misbehaving-provider case passes only if its request reached the provider and the databroker still
answers, unrestarted, afterwards.

## What this does not show

- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.
- `libvirt` is not part of the run.
- Nothing is timed. `elapsed_ms` in an `OBS` line is the client's wall clock for one call, to tell a
  timeout from an answer, not a measurement.
- The CAN feed is a recorded dump replayed by can-provider. No SocketCAN, plant model or vehicle
  application is involved.
- kv2 and the vx-vehicle-03 images are local to the host that builds them.
