# vxAPI gate on the Zephyr-zone reference vehicle, 2026-11-05

The 0.5.0 gate's core scenario, run through `vxmcp` as an agent would, on
[`vx-reference-sedan-02`](../../vehicles/vx-reference-sedan-02): five Linux zones and one Zephyr zone
(`fr-steer-actuator`), all pulled from the registry by digest. Every step is an MCP tool call, every
check reads a typed field, and every mutating call went through the human confirmation, answered
`accept` by the harness.

| Gate | Result |
|---|---|
| The agent sequence, 10 consecutive runs, each with a daemon restart | 10 of 10, 291 checks passed, 0 failed, [`core10.txt`](core10.txt) |
| No bridge, tap, namespace, process, container, VM or nft table left after a run | passed after each of the 10 runs |

Each run checks the same seven steps as the [0.5.0 gate](../vxapi-0.5.0-gate-2026-11-04/README.md):
capabilities and plan, `vehicle_up` and its duplicate and conflict refusals, job and child jobs,
typed `vehicle_status` for every node, event continuity, the daemon restart with its typed
refusals, and `vehicle_down` with a leak check.

Built from vxedge `60e67b0` (main, with #77 and #82). The harness is the 0.5.0 gate's `live.py` with
two changes: the vehicle comes from `VEHICLE`, and `VX_CACHE` sets a writable part cache. The three
binaries it needs (`vxedged`, `vxcapsule`, `vxmcp`) are built from the repositories' main.

## What this does not show

- The gate reads each node's state through `vehicle_status`. It does not probe the guests. The
  Zephyr zone's flows were checked separately: 20 of 20 replies in
  [`../zephyr-zone-2026-11-05`](../zephyr-zone-2026-11-05).
- The guests are probes, not ECU applications. qemu-microvm and container backends only. Nothing was
  timed, and the run is not a performance result.
- Only `core` was run. The cancel, libvirt and traffic scenarios of the 0.5.0 gate were not.
- The daemon ran from a debug build.
