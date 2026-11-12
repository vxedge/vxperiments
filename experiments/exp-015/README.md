# exp-015: Kuksa use cases on vx-vehicle-03

What the signal plane does with real providers and subscribers: kuksa-databroker 0.7.1 as
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03)'s signal plane, with `kuksa.val.v2` subscribers, a
signal provider, a CAN feed replayed from a dump, actuation providers that answer and ones that do
not, and denial from another slice.

## The package

This folder is the `vxp/1` package `vxedge/exp-015`, version 0.2.0 (`vxp.yaml`). Its catalogue
alias is `exp-015`. It is a functional suite, not a measurement: `main.yaml`'s `checks` (vxedge
0.22.0) run each case as a step and judge what the client prints, so no script drives it.

| What | Where it was | Where it is |
|---|---|---|
| The vehicle | `../../vehicles/vx-vehicle-03`, with a bundle and capsule built per host | `vehicle.yaml`, the same document without its OTA service; `parts.yaml` pins the published probe bundle 0.1.1 and reflector capsule 0.1.0 |
| Each client call, in a node's namespace | `kv`, `kvbg` in `lib.sh` (`podman run --network container:vx-<node>-infra`) | a `checks.steps` tool step `on` the node, `background` for a subscriber or provider |
| Waiting for a client's line | `until_log` | a background step's `ready` |
| Waiting for a gone provider's claim to clear | `drop_provider`'s loop | a step repeated `until` actuate finds no provider |
| The databroker not restarted | `broker_state` | `observe: member` steps, compared |
| Frames from a denied sender reaching its port | `rx_packets` | `observe: port` steps, compared |
| `PASS`, `FAIL` and `OBS` lines | `cases-v2.sh` | `checks.cases`; `OBS` lines are `observe` cases |
| What `--insecure` changes | `flags.sh`, with the v1 CLI | two throwaway brokers (`on: alone`) and the v2 client `with` each |
| 47 checks, one verdict | the transcript's lines | the criterion `kuksa-v2` over 50 cases |

Run it through vxAPI, from inside this folder, after building the client once:

```bash
podman build -t localhost/vxperiments/kv2:1 tools/kv2
vxedge campaign plan
vxedge campaign start      # one trial; its archive holds every step's output, then the verdict
vxedge results verdict --experiment . results/<campaign>   # each case, and what was observed
```

The host needs KVM for the two VM zones. The client is local to the host that builds it: kv2 is
not a published part yet, so `localhost/vxperiments/kv2:1` is what the package names.

The signal-plane checks `run.sh` repeated before the cases, from
[`results/signal-plane-2026-11-03`](../../results/signal-plane-2026-11-03) (the vehicle's own
`up`, `status`, idempotent second `up`, a wrong vehicle refused, a daemon restart, a failed `up`
cleaned up, a databroker that exits, an experiment `up` with the signal plane, the v1 CLI), test
the daemon's lifecycle rather than the databroker's use cases. They are not part of this package;
their published run stays in `results/`.

## Pinned

| What | Image |
|---|---|
| databroker 0.7.1, under test | `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd` |
| can-provider 0.5.1, the CAN feed | `ghcr.io/eclipse-kuksa/kuksa-can-provider/can-provider@sha256:41f5abffe30be4dd0bf6d82f28ca149d327e2d6de8619b562a12035a30da0c8e` |
| kv2, the v2 test client | built from [`tools/kv2`](tools/kv2): `python:3.12-slim` by digest, `kuksa-client==0.6.0` and its dependencies by hash |

kv2 calls the generated `kuksa.val.v2` stubs that kuksa-client 0.6.0
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
other outcome is `ok` or a gRPC status code. The cases read output, never exit codes: a case that
expects `ok` fails on anything else, and a denial expects `refused` exactly. A denial also needs the
sender's frames to reach its bridge port (the port's received count rises across the call), and a
final read showing the value unchanged.

The judged cases check what upstream documents (`UNAVAILABLE` with no provider, `ALREADY_EXISTS`
for a second claim) or that a case really ran. `observe` cases record what the databroker did where
its documentation does not say, such as a provider that never answers, and are never judged. A
misbehaving-provider case passes only if its request reached the provider and the databroker still
answers, unrestarted, afterwards. A case whose step did not run is `inconclusive`, never a pass.

## What this does not show

- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.
- `libvirt` is not part of the run.
- Nothing is timed. `elapsed_ms` and `elapsed_s` in an `observe` case are wall clocks, to tell a
  timeout from an answer, not measurements.
- The CAN feed is a recorded dump replayed by can-provider. No SocketCAN, plant model or vehicle
  application is involved.
- kv2 is local to the host that builds it.
