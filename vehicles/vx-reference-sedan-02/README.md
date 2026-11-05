# vx-reference-sedan-01

The six-zone reference vehicle of `PROVISIONING.md` §4: four corner zones with an ECU plus a sensor
or actuator, and central compute, with an OTA service and the Kuksa signal plane placed on it.

| Device | Zone | Role | Backend | Address | Runs |
|---|---|---|---|---|---|
| `fl-safety-ecu` | front-left | ecu | qemu-microvm | 10.120.0.11/24 | probe guest |
| `fl-camera-sensor` | front-left | sensor | qemu-microvm | 10.120.0.12/24 | probe guest |
| `fr-body-ecu` | front-right | ecu | qemu-microvm | 10.120.0.21/24 | probe guest |
| `fr-steer-actuator` | front-right | actuator | qemu-microvm | 10.120.0.22/24 | probe guest |
| `rl-radar-sensor` | rear-left | sensor | qemu-microvm | 10.120.0.31/24 | probe guest |
| `rr-brake-actuator` | rear-right | actuator | qemu-microvm | 10.120.0.41/24 | probe guest |
| `hpc-ad-01` | central-hpc | hpc | container | 10.120.0.50/24 | probe image, OTA on :9900, Kuksa databroker |

All devices share one slice and one /24, so every device can reach every other.

## Run it

```bash
./build.sh                                # once per host: probe and OTA images, OTA store
vxedge vehicle up --manifest .
vxedge vehicle status --manifest .
./check-flows.sh                          # central compute reaches all six zones, OTA answers
./snapshot.sh                             # diff before and after a second `up`
vxedge vehicle down --manifest .
./check-leaks.sh
```

Needs what `vx-vehicle-02` needs. The guest bundle is the published `zone/linux/stack/probe-bundle`
pinned by digest in `parts.yaml`, fetched into the daemon's cache on first `up`. The run in
[`results/reference-vehicle-2026-11-04`](../../results/reference-vehicle-2026-11-04) is the evidence.

## Limits

- The guests are probes. The roles are structural claims, and the RTOS images they imply (a safety
  ECU, a camera sensor) replace the probe one zone at a time as real parts are published.
- Only the container node can send, so the six guests are probed as targets.
- Nothing is timed, and there is one slice, so no isolation is shown here; `vx-vehicle-03` shows that.
- This is a provisioning result, not a measurement.
