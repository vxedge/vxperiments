# vx-vehicle-02

The phase-3 gate vehicle: one workspace brings up a gateway, three zones on two backends, a
central compute node and a service placed on a slice.

| Device | Zone | Backend | Slice | Address | Runs |
|---|---|---|---|---|---|
| `zone-fl` | front-left | qemu-microvm | adas | 10.100.0.11/24 | guest bundle, probe reflector |
| `zone-fr` | front-right | container | adas | 10.100.0.12/24 | probe image |
| `zone-rl` | rear-left | container | infotainment | 10.100.0.31/24 | probe image |
| `hpc1` | central | container (CPU only) | adas | 10.100.0.50/24 | probe image, OTA server on :9900 |

`adas` and `infotainment` share one /24 on purpose. A flow between them fails on the VLAN, not on
a missing route, so the failure is evidence about the slice.

## Run it

```bash
./build.sh                                # once per host: images, OTA store, guest bundle
vxedge vehicle up --manifest .
vxedge vehicle status --manifest .
./check-flows.sh                          # allowed flows first, then denied ones
./snapshot.sh                             # diff before and after a second `up`
vxedge vehicle down --manifest .
./check-leaks.sh
```

The gate run of this vehicle is in [`results/phase-3-gate-2026-11-01`](../../results/phase-3-gate-2026-11-01).

`vxedged` needs `cap_net_admin,cap_sys_admin`, a cached sudo credential for `tc` and `nft`, and the
user's Podman socket. `snapshot.sh` and `check-leaks.sh` read nftables through `sudo -n`.

## Limits

- The images and the OTA store are local and per host, so a run reproduces for its author. The gate
  evidence records the image digests.
- The guest only reflects probes, so traffic to `zone-fl` starts elsewhere.
- `zone-rl` is alone on `infotainment`, so that slice has no allowed flow of its own. Its denied
  flows show frames reaching the bridge port, which is what makes the silence meaningful.
- `vehicle down` takes about 15 s per container, because Podman waits out the stop timeout.
- The `v0.2.0` CLI cannot read this workspace: `services` on a vehicle and `localhost/` refs are
  newer. Use a build of `main`.
