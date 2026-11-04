# vxAPI 0.5.0 release gate, 2026-11-04

The live gate for `vxedge` 0.5.0 ([vxedge#54](https://github.com/vxedge/vxedge/issues/54)), run
through `vxmcp` as an agent would: every step is an MCP tool call, every check reads a typed field
(an enum name, an `ErrorReason`, an id), and every mutating call went through the human
confirmation, answered `accept` by the harness. Run on merged `main`: vxedge `4728e21`, vxmcp
`5ca0c89`, vxperiments `main` of the day.

| Gate | Workspace | Result |
|---|---|---|
| The agent sequence, 10 consecutive runs, each with a daemon restart | [`vx-vehicle-03`](../../vehicles/vx-vehicle-03) | 10 of 10, 271 checks passed, [`core10.txt`](core10.txt) |
| Typed status on all five backends | `vx-vehicle-03` (container, qemu-microvm, cloud-hypervisor, wasm-capsule), [`exp-002-ws`](../../experiments/exp-002-ws) (libvirt) | passed, [`libvirt.txt`](libvirt.txt) |
| No bridge, tap, namespace, process, container, VM or nft table left after a run | every run | passed after each one |
| Cancel during `up`, then `down` | `vx-vehicle-03` | passed, [`cancel.txt`](cancel.txt) |
| Traffic from running to finished, then the archive and its digest | `exp-001-ws` plus a telemetry service | passed, [`traffic.txt`](traffic.txt) |

Each core run checks, in order:

1. `host_capabilities` reports all five backends available, and `workspace_plan` is valid with every
   host check passed.
2. `vehicle_up` returns a job. The same call again returns that job; the same vehicle with other
   stages is refused `ERROR_REASON_BUSY`; another workspace is refused
   `ERROR_REASON_WRONG_WORKSPACE`.
3. The job succeeds, its child jobs all succeed, and it carries the run id `run_list` reports.
4. `vehicle_status`: every node `RESOURCE_STATE_UP`, with a typed backend and payload. Another
   vehicle's status is refused.
5. A second agent follows events in 2-second windows, resuming each from `lastId`: no
   `EVENTS_LOST`, contiguous ids, and `run.up` with its run id.
6. The daemon is restarted. The run is still listed and every node still up; the old job id answers
   `ERROR_REASON_JOB_UNKNOWN`, the old event cursor `ERROR_REASON_EVENTS_LOST`, and a stale run id
   `ERROR_REASON_RUN_MISMATCH`.
7. `vehicle_down`: cancelling it is refused `ERROR_REASON_NOT_CANCELLABLE`, it succeeds, `run_list`
   is empty, and `check-leaks.sh` finds nothing.

## Found and fixed during the gate

- A `vehicle up` with other stages, sent while a full `up` ran, was handed the running job instead of
  `BUSY`. Fixed in [vxedge#70](https://github.com/vxedge/vxedge/pull/70) before the runs above.
- A daemon stopped in the middle of `up` left a half-built vehicle. A new daemon listed the run, and
  `vehicle_down` converged it with nothing left behind: the behaviour the gate asks for.

## Follow-up: vxedge 0.5.1

After the gate, the run state of a half-built vehicle was found to read `RESOURCE_STATE_UP`: a
daemon stopped in the middle of `up` left the run listed as up. vxedge 0.5.1
([vxedge#73](https://github.com/vxedge/vxedge/pull/73)) makes it the workspace's rollup. On
`06b789b`'s daemon, [`halfbuilt-0.5.1.txt`](halfbuilt-0.5.1.txt): `STAGING` while `up` runs, `UP`
after it, and `DEGRADED` with the daemon stopped during the zone, compute and signal-plane stages,
each converged by a second `up`; [`core3-0.5.1.txt`](core3-0.5.1.txt): three more core runs, now
also checking the run reads `UP` before and after a restart.

## Follow-up: vxedge 0.5.2

The fields the gate had not checked live, and the 0.5.2 fixes, on `4626e0e`'s daemon through
`vxmcp` 0.2.1 ([`fields-0.5.2.txt`](fields-0.5.2.txt)): `job_list` paging and its state and kind
filters, `events_subscribe` with a kind family, `NodeSpec` port, peer and VLAN, `observed_unix_ms`,
`svc_status` with a workspace, `Collect.out_path`, `HostCapabilities.gpu` and the container backend
from the preflight's own Podman check, `traffic_up` refused with
`ERROR_REASON_ENDPOINT_NOT_ON_HOST` after a full `up`, and `local/` parts recorded as host processes
by `vxtelemetry` 0.2.1. `vehicle status` and `run_list` took 1.6 s, down from 6.0 s. The half-built
run check and three core runs pass again on that build
([`halfbuilt-0.5.2.txt`](halfbuilt-0.5.2.txt), [`core3-0.5.2.txt`](core3-0.5.2.txt)).

## What this does not show

- `exp-001-ws` traffic runs with the gateway stage only, as its campaign does: a full `up` moves the
  source's veth peer into the node's namespace (`experiments/exp-001-ws/scripts/run.sh`).
- No workspace declares a telemetry service, so the traffic run used a scratch copy of `exp-001-ws`
  with [`harness/telemetry-service.yaml`](harness/telemetry-service.yaml) appended to `main.yaml`.
  The exp-001 campaign workspace is unchanged.
- In the 0.5.0 runs the archive's `image_digests` marked the two `local/...:host-process` parts
  unresolved; `vxtelemetry` 0.2.1 records them as host processes.
- Every part of `vx-vehicle-03` is local, so payload digests are empty by contract; published-part
  digests are not exercised here.
- Guests are probes, and nothing was timed.

## Reproduce

[`harness/`](harness) holds the driver. `live.py` sends privileged steps (`setcap`, starting
`vxedged`, the leak check) to a tmux pane named `vxpriv` where `sudo` is cached, and talks to
`vxmcp` over stdio.

```bash
export VX_BIN=/path/to/bin VXPERIMENTS=/path/to/vxperiments   # the seven binaries, built from the commits above
python3 -I harness/live.py core 10
python3 -I harness/live.py cancel
python3 -I harness/live.py libvirt
python3 -I harness/halfbuilt.py      # run from harness/, needs live.py beside it
python3 -I harness/fields.py
TRIAL=/path/to/exp-001-ws-copy python3 -I harness/live.py traffic
```
