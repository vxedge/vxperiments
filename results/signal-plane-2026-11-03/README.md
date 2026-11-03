# Signal plane on vx-vehicle-03, 2026-11-03

The Kuksa databroker running as a stage of `vxedge vehicle up`, on
[`vx-vehicle-03`](../../vehicles/vx-vehicle-03): one VSS signal written and read through a real
client, allowed from `adas` and denied from `infotainment`. Run from a clean state on merged `main`:
vxedge `f667411`, vxperiments `a2a23de`. [`transcript.txt`](transcript.txt) is the whole run, and
[`vehicle-document.sha256`](vehicle-document.sha256) pins the workspace documents.

Databroker under test:
`ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:9ace2824719ba7c05929f0af4827d9b25fa5ca7b2e0d58d0acff95885c649d6d`

Client, used by the test only:
`ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:a886f52e1fc1ef3fbebd482d19511065c1932c36db216b43b76403be59886c2e`

| Check | Result |
|---|---|
| `up` provisions every component, the signal plane in its own stage after compute | passed |
| `status` reports `kuksa-databroker` as `signal_plane`, observed, including after a daemon restart | passed |
| Flows to all four backends, allowed and denied | passed |
| `Vehicle.Speed` written and read from `cabin1` on `adas` | passed, `42.50 km/h` |
| Write and read from `zone-rl` on `infotainment` | refused |
| Read from `cabin1` after the denied write | still `42.50 km/h` |
| Second `up` | databroker running, empty diff |
| `up`, `status` and `down` of another vehicle, before and after a restart | refused, nothing changed |
| `vehicle down` twice | both succeeded |
| `down` after a failed `up` | nothing left behind |
| A databroker that exits right after starting | job failed naming `kuksa-databroker`, `down` left nothing behind |
| `experiment up` on the same vehicle | databroker started with the same flags, `experiment down` left nothing behind |

## How the denial is shown

The client exits 0 on a failed connection, so `check-signals.sh` never reads its exit code. It
classifies the output: success needs `[publish] OK`, or `[get] OK` with the value, and a refusal
needs the client's own connection error. Anything else fails both checks, so a broken client cannot
pass as either. A denied attempt must also show the sender's frames reaching its bridge port, and
the transcript prints the VLAN membership: the sender is on 101, the databroker's device on 100. The
denial comes from that VLAN separation, not from the client or the databroker.

## The flags

Measured on the pinned image, in throwaway containers, at the start of the transcript. `--address`
and `--port` are honoured: the client reaches the declared port and gets a transport error on the
default one. `--insecure` does not change what connects: without it the databroker still accepts
plain clients and logs a warning. It makes that mode explicit.

## What this does not show

- Signals are unauthenticated. Slice isolation is their only protection.
- One signal was written by a test client. No feeder, CAN mapping or plant model ran, and no
  application consumed it.
- `libvirt` was not part of the run.
- Nothing was timed, so this is a provisioning result, not a measurement.
- The images other than the databroker and client, the bundle and the capsule are local to this
  host.
