# vxAPI gate on the reference sedan with an AAOS zone, 2026-11-08

The core gate, run through `vxmcp` as an agent would, on
[`vx-reference-sedan-03`](../../vehicles/vx-reference-sedan-03). That is `vx-reference-sedan-02` plus a cockpit
zone: an Android Automotive 26Q2 guest on its own Cuttlefish host stack (`ivi-aaos`, `backend: attach`), and the
cockpit gateway ECU that serves its Vehicle HAL from the vehicle's signals (`ivi-gw`: vxvhal and the Kuksa
databroker). Image ladder rung `aaos-26q2-x86_64-cf` (`docs/ARCHITECTURE.md` §9). Every step is an MCP tool
call, every check reads a typed field, and every mutating call went through the human confirmation, answered
`accept` by the harness.

| Gate | Result |
|---|---|
| The agent sequence, 10 consecutive runs, each with a daemon restart | 10 of 10, 451 checks passed, 0 failed, [`core10.txt`](core10.txt) |
| The guest reads the vehicle's signals through CarService, over the slice, before and after the restart | 20 of 20 readings matched |
| `down` stops the guest and gives Cuttlefish's tap back to `cvd-ebr` with the alias cleared | 10 of 10 |
| No bridge, tap, namespace, process, container, VM or nft table left after a run | passed after each of the 10 runs |

Each run checks the seven steps of the [0.5.0 gate](../vxapi-0.5.0-gate-2026-11-04/README.md): capabilities
and plan; `vehicle_up` and its duplicate and conflict refusals; job and child jobs; typed `vehicle_status`
for every node; event continuity; the daemon restart with its typed refusals; `vehicle_down` with a leak
check. It adds the Vehicle HAL check, run once after `up` and once after the restart:

1. Wait for `sys.boot_completed=1` over `adb`.
2. Publish a speed and a gear to Kuksa on `ivi-gw`. Both are distinct for each run and each half, from
   33.6 km/h to 67.8 km/h, cycling park, drive and neutral.
3. Read `PERF_VEHICLE_SPEED` and `GEAR_SELECTION` through `cmd car_service get-property-value` and compare:
   speed within 0.01 m/s of the published km/h divided by 3.6, and the matching gear.
4. Check the path: inside `ivi-gw`, an established connection from the guest (`192.168.98.3`) to
   `192.168.98.1:9300`, and nothing listening on 9300 on the host.
5. Check that no diagnostic container is left in `ivi-gw`'s namespace.

After `down`, the harness also checks that `cvd_status` reports the guest stopped and that `cvd-etap-01` is
back on `cvd-ebr` with no `vxedge:` alias.

## What ran

| Item | Value |
|---|---|
| vxedge | 0.9.1 release, x86_64, sha256 `a452a6b66ec237015386b3f918cf4789bb677560b69e36e42adeb926a6314a6b`: `vxedged`, `vxcapsule` |
| vxmcp | 0.2.4 release |
| vxperiments | `90e7268`; the documents and adapter as run in [`vehicle-document.sha256`](vehicle-document.sha256) |
| `ivi-gw` payload | `ghcr.io/vxedge/parts/svc/signal/app/vxvhal:0.1.1@sha256:41ee94eaa596c59dafc3e934fe3014b0ee8af3084ac1fb4a94d02644b92c744e` |
| Kuksa | databroker 0.7.1, pinned by digest, on `ivi-gw` |
| AAOS | AOSP Cuttlefish `aosp_cf_x86_64_auto-userdebug` build `16644040`, checked against `aaos/SHA256SUMS` at each start |
| Host stack | `cuttlefish-base` 1.57.13, the build's own host package; its host Vehicle HAL server replaced by a stub |

All binaries are release builds; the 2026-11-05 gate ran a debug daemon.

## What the gate found before it passed

The first runs on 0.9.0 failed. Both causes were vxedge bugs, fixed in 0.9.1
([vxedge #103](https://github.com/vxedge/vxedge/pull/103)):

- **`down` stopped the attach zone first.** Stopping Cuttlefish kills the guest without closing its
  connections. vxvhal's socket stayed open to the dead guest and kept `ivi-gw`'s namespace, and its gateway
  port, alive past `down`'s 5 s wait: the port was still there 39 s after `down` started. With vxvhal stopped
  first, the connection closed cleanly and `down` succeeded. Attach zones now stop last.
- **Another workspace's `up` got a timing-dependent refusal.** While a run's gateway was still being built,
  the refusal was `ERROR_REASON_FOREIGN_WORKLOAD` or a later check's reason, not
  `ERROR_REASON_WRONG_WORKSPACE`. Preflight now also reads the lifecycle job in flight.

Two more fixes came from the same runs:

- vxvhal 0.1.0 ignored SIGTERM as a container's PID 1; 0.1.1 stops on it.
- vxmcp 0.2.3 could not render the `attach` backend and failed `host_capabilities` against a 0.9.0 daemon;
  0.2.4 follows vxedge 0.9.0.

## The harness

`harness/` is the [2026-11-05 gate's](../zephyr-gate-2026-11-05/README.md) harness with these changes:

- `VXMCP` names the vxmcp binary.
- `VXEDGE_AAOS_HOME` names the AAOS build and reaches the daemon.
- `E002` names the other workspace for the conflict check; it needs its fetched `parts/linux-probe`.
- It adds the Vehicle HAL check (`vhal`), the guest-stopped check and the tap check.

Reverse gear is not cycled, because the Kuksa CLI reads a leading `-` as an option; vxvhal's tests cover the
mapping. Run it with `VX_BIN` (holding `vxedged`, `vxcapsule`, `vxmcp`), `VXEDGE_AAOS_HOME`, `VXPERIMENTS`,
`E002`, `VEHICLE=vx-reference-sedan-03` and `VX_CACHE`: `python3 -I live.py core 10`. Paths in
`core10.txt` are shortened to `<vxperiments>`, `$VXEDGE_AAOS_HOME` and `~`.

## What this does not show

- **Not the production platform.** This is rung 1 of the ladder: the AAOS framework and the production
  Vehicle HAL path, on x86_64 under Cuttlefish. It is not the production instruction set, hypervisor or
  hardware. Those are the later rungs (`aaos-26q2-arm64-cf`, `aaos-on-qnx-hyp`, `aaos-hil`).
- **Only read properties.** The Vehicle HAL check reads two properties. No write path (`SetValues` is
  refused by vxvhal 0.1) and no HMI ran.
- **Probes, not ECU applications.** The other zone guests are probes, and their flows were not probed here;
  see [`../aaos-zone-2026-11-08`](../aaos-zone-2026-11-08) for `check-flows.sh` on this vehicle.
- **Not timed.** Nothing was timed, and the run is not a performance result.
- **Only `core` was run.** The cancel, libvirt and traffic scenarios were not run.
- **One AAOS instance per host:** Cuttlefish's first tap and port 9300.
