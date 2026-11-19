"""Drives vxmcp the way an agent does: modern 2026-07-28 requests over stdio, typed results only,
and a confirming human simulated by answering each form elicitation with `accept`."""
import json, os, subprocess

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {"elicitation": {"form": {}}},
    "clientCapabilities": {"elicitation": {"form": {}}},
}


class Agent:
    def __init__(self, vxmcp, endpoint, log):
        env = dict(os.environ, VXEDGE_ENDPOINT=endpoint)
        self.p = subprocess.Popen([vxmcp], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, env=env)
        self.n = 0
        self.log = log
        self.asked = []

    def _rpc(self, method, params):
        self.n += 1
        params = dict(params, _meta=META)
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method,
                                       "params": params}) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def call(self, name, args=None, confirm=True):
        """Returns (ok, structured). ok is False for a tool error; raises on a JSON-RPC error."""
        args = args or {}
        r = self._rpc("tools/call", {"name": name, "arguments": args})
        if "error" in r:
            raise RuntimeError(f"{name}: JSON-RPC error {r['error']}")
        res = r["result"]
        if res.get("resultType") == "input_required" or "inputRequests" in res:
            reqs = res.get("inputRequests", {})
            q = json.dumps(reqs)[:400]
            self.asked.append((name, q))
            self.log(f"   ? {name} asked the human: {q[:200]}")
            if not confirm:
                return False, {"declined": True}
            r = self._rpc("tools/call", {
                "name": name, "arguments": args,
                "requestState": res.get("requestState"),
                "inputResponses": {k: {"action": "accept"} for k in reqs},
            })
            if "error" in r:
                raise RuntimeError(f"{name}: JSON-RPC error {r['error']}")
            res = r["result"]
        sc = res.get("structuredContent")
        if sc is None:
            sc = {"_raw": res}
        return (not res.get("isError", False)), sc

    def close(self):
        self.p.terminate()
