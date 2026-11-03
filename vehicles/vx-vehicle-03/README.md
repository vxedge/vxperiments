# vx-vehicle-03

Every zone backend in one vehicle: six zones on qemu-microvm, cloud-hypervisor, wasm-capsule and
container, with central compute, an OTA service and the Kuksa signal plane placed on a slice.

| Device | Zone | Backend | Slice | Address | Runs |
|---|---|---|---|---|---|
| `zone-fl` | front-left | qemu-microvm | adas | 10.100.0.11/24 | guest bundle, probe reflector |
| `zone-fr` | front-right | cloud-hypervisor | adas | 10.100.0.12/24 | guest bundle, probe reflector |
| `cabin1` | cabin | container | adas | 10.100.0.13/24 | probe image |
| `sensor-rr` | rear-right | wasm-capsule | adas | 10.100.0.14/24 | reflector capsule |
| `zone-rl` | rear-left | container | infotainment | 10.100.0.31/24 | probe image |
| `hpc1` | central | container (CPU only) | adas | 10.100.0.50/24 | probe image, OTA server on :9900 |

`adas` and `infotainment` share one /24 on purpose, as in `vx-vehicle-02`.

## Run it

```bash
./build.sh                                # once per host: images, OTA store, bundle, capsule
vxedge vehicle up --manifest .
vxedge vehicle status --manifest .
./check-flows.sh                          # allowed flows first, then denied ones
./check-signals.sh                        # one VSS signal, allowed then denied
./snapshot.sh                             # diff before and after a second `up`
vxedge vehicle down --manifest .
./check-leaks.sh
```

Needs what `vx-vehicle-02` needs, plus `cloud-hypervisor` on `PATH` and `vxcapsule` beside `vxedged`
or named by `VXEDGE_CAPSULE_BIN`. The run in
[`results/all-backends-2026-11-02`](../../results/all-backends-2026-11-02) is the evidence.

## Limits

- `vxedged`'s runtime dir must be short: a Unix socket path has a length limit, and a Cloud
  Hypervisor node's API socket lives there. `up` reports the path when it is too long.
- Only the container nodes can send, so the VM and capsule nodes are probed as targets.
- The signal plane run is in
  [`results/signal-plane-2026-11-03`](../../results/signal-plane-2026-11-03).
- `libvirt` is left out: its boot adds nothing the two other VM backends do not show here.
- The databroker runs with `--insecure`, so signals are unauthenticated and slice isolation is their
  only protection.
- This is `vx-vehicle-02`'s kind of evidence: probes, one Linux bridge, nothing timed.
