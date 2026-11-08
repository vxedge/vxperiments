# vx-reference-sedan-03

`vx-reference-sedan-02` plus a cockpit zone, as a production cockpit domain joins a vehicle: an Android
Automotive 26Q2 infotainment guest on its own host stack, and the cockpit gateway ECU that serves its Vehicle HAL
from the vehicle's signals (`docs/ARCHITECTURE.md` §9, image ladder rung `aaos-26q2-x86_64-cf`).

| Device | Zone | Role | Backend | Address | Runs |
|---|---|---|---|---|---|
| `fl-safety-ecu` | front-left | ecu | qemu-microvm | 10.120.0.11/24 | probe guest |
| `fl-camera-sensor` | front-left | sensor | qemu-microvm | 10.120.0.12/24 | probe guest |
| `fr-body-ecu` | front-right | ecu | qemu-microvm | 10.120.0.21/24 | probe guest |
| `fr-steer-actuator` | front-right | actuator | qemu-microvm | 10.120.0.22/24 | Zephyr probe guest |
| `rl-radar-sensor` | rear-left | sensor | qemu-microvm | 10.120.0.31/24 | probe guest |
| `rr-brake-actuator` | rear-right | actuator | qemu-microvm | 10.120.0.41/24 | probe guest |
| `hpc-ad-01` | central-hpc | hpc | container | 10.120.0.50/24 | probe payload, OTA on :9900 |
| `ivi-gw` | cockpit | ecu | container | 10.120.0.60/24, 192.168.98.1/24 | vxvhal on :9300, Kuksa databroker on :55555 |
| `ivi-aaos` | cockpit | ecu | attach | 192.168.98.3/24 (set by the guest) | AAOS 26Q2 on Cuttlefish |

All devices share one slice. The AAOS guest sets its own address and dials its Vehicle HAL at
`192.168.98.1:9300`, so `ivi-gw` carries that address beside its vehicle one and the Vehicle HAL path is slice
traffic. `ivi-aaos` starts after every other zone node, so the guest never boots before the server it dials.

## Run it

Needs, on the host: vxedge with the attach backend; `cuttlefish-base` 1.57.13 or later and membership of
`cvdnetwork`; the AAOS build from `vxparts` `zone/aaos/stack/cuttlefish-auto` (its `build.sh`), about 3 GB plus
about 20 GB of sparse disk images per instance. Start `vxedged` with `VXEDGE_AAOS_HOME` set to that build.

```bash
vxedge vehicle up --manifest .            # boots AAOS inside the zones stage: minutes
./check-flows.sh                          # central compute reaches the six probe zones, OTA answers
vxedge vehicle down --manifest .
./check-leaks.sh
```

The AAOS read: publish to Kuksa inside `ivi-gw` (`podman run --network container:vx-ivi-gw-infra` with the
Kuksa CLI) and read `cmd car_service get-property-value PERF_VEHICLE_SPEED` over `adb`.
`results/aaos-zone-2026-11-08` is the first run.

## The adapter

`aaos/` is the attach node's part: `attach.yaml` names the interface Cuttlefish creates (`cvd-etap-01`) and its
start, status and stop scripts. `start.sh` checks the build against `aaos/SHA256SUMS` before launching, so the
package digest covers which AAOS ran, and replaces Cuttlefish's host Vehicle HAL server with a stub, since the
vehicle serves it. `stop.sh` stops this instance only.

## Limits

- `vbmeta*.img` are not pinned: Cuttlefish regenerates them at each launch.
- One AAOS instance per host: Cuttlefish's first tap and port 9300.
- x86_64: not the production instruction set, hypervisor or hardware; those are the later rungs of the ladder.
- The probe guests are probes, as in `vx-reference-sedan-02`.
