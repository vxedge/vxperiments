# vxAPI gate on vxedge 0.34.2: every node backend, beside a second vehicle, 2026-11-19

The vxAPI core gate, run through `vxmcp` as an agent would, on [`vx-vehicle-04`](../../vehicles/vx-vehicle-04). The
vehicle has one node on each of vxedge's seven node backends. Since the [2026-11-11 run](../all-backends-gate-2026-11-11),
a host runs several vehicles at once, each in a slot of its own, and `vxmcp` 0.7.0 reads and clears them as a
fleet. This run checks both: [`vx-vehicle-02`](../../vehicles/vx-vehicle-02) comes up beside vx-vehicle-04, the
fleet view reads the two runs, and one confirmed call takes both down. Every step is an MCP tool call, every check
reads a typed field or what the kernel reports, and every mutating call went through the human confirmation,
answered `accept` by the harness.

## Result

**Core: 3 of 3 runs, 190 checks passed, 0 failed** ([`core3.txt`](core3.txt)). **Traffic: 12 checks passed, 0
failed** ([`traffic.txt`](traffic.txt)).

Each core run covers the gate of the 2026-11-11 run: host capabilities and plan, `vehicle_up` as a job (with
duplicate and competing calls), status with typed payloads, the event stream, a daemon restart with state
recovered, and a clean host. After `up` and again after the restart:

| Check | Result, every run |
|---|---|
| All seven backends up: container, qemu-microvm, cloud-hypervisor, libvirt, wasm-capsule, attach, qemu-mcu | passed |
| `ecu-mcu-frt` and `ecu-mcu-zep` report `arch: armv7m`, `acceleration: tcg` | passed |
| `zone-fl` (qemu-microvm), `zone-fr` (cloud-hypervisor), `zone-rr` (libvirt), `sensor-rr` (wasm-capsule) and `ecu-mcu-frt` (qemu-mcu): all of each node's threads may run only on its pinned CPU, 4 to 8 | passed |
| The attach node's tap `at-ivi1` adopted into the slice bridge | passed |
| `check-flows.sh`, 19 checks: `hpc1` reaches every `adas` node 20/20, OTA answers, the `infotainment` container reaches none | passed |

New in this run, every run:

| Check | Result, every run |
|---|---|
| Another workspace's `up` while this one's runs is refused `BUSY`; another vehicle's status, with no run of its own, is `NO_ACTIVE_RUN` | passed |
| vx-vehicle-02 comes up in slot 1 beside vx-vehicle-04 in slot 0 | passed |
| `run_status` with no ids reads both runs `UP`, with no error, and vx-vehicle-04's 10 typed nodes | passed |
| `run_status` by id reads the named run `UP`, and an unknown id as an entry of its own with `RUN_MISMATCH` and no status | passed |
| `vehicle_down` by `run_id` takes vx-vehicle-02 down and leaves vx-vehicle-04's run alone | passed |
| After the restart, vx-vehicle-02 up again, then `run_down` with `all`: the confirmation names both runs, cancelling it is refused `NOT_CANCELLABLE`, it succeeds with one `vehicle.down` child per run, and `run_list` is empty | passed |
| The attach tap is back with no master, and the host is clean | passed |

In `core3.txt`, `error ERROR_REASON_UNSPECIFIED` on a `run_status` line is how `vxmcp` writes a run with no error.

The traffic run brings up a copy of [`exp-001-ws`](../../experiments/exp-001-ws) with every stage, its zones
included, and starts its telemetry service and its traffic. Since vxedge 0.32.0 the far side of the traffic runs
in the run's own uplink namespace, so the load crosses the bridge and the shaped uplink while the zones are up.
The run checks that a retried `traffic_up` with the same `request_id` returns the same job, that the profile
moves from running to finished, and that the collected archive matches the digest its job reports. It also checks
that `vxtelemetry verify` passes on the archive: index, workspace identity and package digest.

## What ran

| Item | Value |
|---|---|
| vxedge | 0.34.2 release, x86_64, tarball sha256 `4bd9ed65ec968b93…`, with `vxedged` holding `cap_net_admin,cap_sys_admin` |
| vxmcp | 0.7.0 release, tarball sha256 `9f479f63a43d0743…`. Built against the vxedge 0.33.0 API; 0.34.x changed no RPC or message |
| vxtelemetry | 0.11.0 release, tarball sha256 `e4e6de9bf31d1db1…` |
| vxprobe, vxtraffic | vxagents 0.2.3 release, tarball sha256 `d416481e1e898d5c…` |
| vxota | 0.1.2 release, tarball sha256 `fea31e4e40538e92…` |
| Vehicles | `vehicles/vx-vehicle-04`, documents and attach adapter pinned in [`vehicle-document.sha256`](vehicle-document.sha256); `vehicles/vx-vehicle-02`, pinned in [`vehicle-02-document.sha256`](vehicle-02-document.sha256) |
| Harness | [`harness/`](harness): the 2026-11-11 harness, brought up to slots and the fleet tools |

Every tarball was checked against its release's `SHA256SUMS`. Run as `VX_CACHE=<writable part cache>
VX_BIN=<the binaries above> VXPERIMENTS=<this checkout> VEHICLE=vx-vehicle-04 python3 -I live.py core 3`, then
`TRIAL=<a scratch copy of exp-001-ws> … python3 -I live.py traffic`. Paths in the logs are shortened. The harness
here differs from the one that ran only in its docstring, and in that it checks a host lock only where a lock
tool is installed.

### vx-vehicle-04 now needs vxedge 0.34.2

The attach adapter boots its guest with `vx.node=ivi1` on the kernel line. vxedge reads a guest that carries that
marker but no slot as belonging to no run, so foreign to every run, and refused any second vehicle's `up` while
vx-vehicle-04 was up. An adapter had no way to learn its slot. vxedge 0.34.2
([vxedge#212](https://github.com/vxedge/vxedge/pull/212)) passes it to the adapter as `VX_SLOT`. The adapter's
`ivi/start.sh` now adds `vx.slot=$VX_SLOT` and refuses to start without it.

## Attempts before the recorded runs

Three one-run shakedowns and two traffic attempts came first. None is part of the result, and each fault was fixed
before the recorded runs:

1. **Shakedown on vxedge 0.34.1, first try:** the gate user could not write the shared part cache, so the
   qemu-mcu firmware could not be fetched. vx-vehicle-02 had not been built. Then the harness stopped on an empty
   run id and left vx-vehicle-04's run up; that run was brought down by hand and the host checked clean. The gate
   now uses its own part cache, and the harness takes every run down on any exit.
2. **Shakedown on 0.34.1, second try:** every vx-vehicle-04 check passed except one. The pin check could not find
   the cloud-hypervisor node, whose command line names only its API socket; it now matches the socket. The second
   vehicle was refused by the slotless attach guest above, which vxedge 0.34.2 fixes.
3. **Shakedown on 0.34.2:** all passed but `run_status`'s no-error check, which read `ERROR_REASON_UNSPECIFIED`
   as an error. Fixed in the harness.
4. **Traffic, first try:** the telemetry service stopped at once, with no target to scrape. exp-001 declares
   none of its own and relies on the daemon's exporter. The exporter had not started, because another service on
   the host held its default port. The harness now starts `vxedged` with `--metrics-listen 127.0.0.1:0`.
5. **Traffic, second try:** everything passed except the archive check, which looked for `workspace/main.yaml`;
   the archive has kept the workspace under `package/` since vxtelemetry moved to `vxarchive/2`. The check now
   reads `package/` and runs `vxtelemetry verify`.

## Host checks

Before and after every run, the harness found no leftover network namespaces, links, containers, VMs, capsules or
uplink namespaces. nftables needs root, so an administrator listed the tables separately, after the three core
runs and the first traffic attempt: no `vx` table. The last two traffic attempts, the recorded one included,
were checked by the non-root checks only.

## What this does not show

- **Fleet:** two vehicles on one host, with lifecycle calls one at a time. Concurrent `up` across slots is refused
  by design and was checked as such, not raced.
- **MCU ECUs:** QEMU's `mps2-an385` model under TCG, not MCU silicon. Their replies are functional evidence,
  never timing.
- **Attach:** the attach node is a generic adapter (the linux-probe bundle on plain QEMU over a prepared tap),
  not Android Automotive.
- **Pinning:** checked as thread affinity, not as latency. Container nodes are not pinned.
- **Traffic:** one short profile, checked for its lifecycle and archive, not for its numbers.
- **Host:** one shared development host. Functional results only, never timed.
