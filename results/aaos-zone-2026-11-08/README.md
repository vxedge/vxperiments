# AAOS zone in the reference sedan, 2026-11-08

`vx-reference-sedan-03` is `vx-reference-sedan-02` plus a cockpit zone: an Android Automotive 26Q2 guest
(`ivi-aaos`, `backend: attach`) and the cockpit gateway ECU (`ivi-gw`) that serves its Vehicle HAL from the
vehicle's signals. Image ladder rung `aaos-26q2-x86_64-cf` (`docs/ARCHITECTURE.md` §9): the AAOS framework and the
production Vehicle HAL path over a slice, on x86_64. Not the production instruction set, hypervisor or hardware.

## Result

- `vehicle up` succeeded: gateway, 8 zones, compute, the Kuksa signal plane on `ivi-gw`, the OTA service. The
  attach node started last of the zones (8 of 8), after `ivi-gw` (5 of 8).
- The gateway adopted Cuttlefish's Ethernet tap `cvd-etap-01` as the slice port: master `vxbr0`, the slice
  VLAN untagged, alias `vxedge:adopted-from=cvd-ebr`.
- AAOS booted on its own Cuttlefish host stack: `sys.boot_completed=1`, `ro.build.version.sdk=37`.
- Across the slice: values published to Kuksa on `ivi-gw` (`Vehicle.Speed` 72.0,
  `Vehicle.Powertrain.Transmission.SelectedGear` 126) read in AAOS through CarService as
  `PERF_VEHICLE_SPEED` 20.0 m/s and `GEAR_SELECTION` `GEAR_PARK`. Inside `ivi-gw`, `192.168.98.1:9300` held an
  established connection from `192.168.98.3`, the guest; nothing on the host listened on 9300.
- `check-flows.sh` passed for the six probe zones and the OTA service.
- A second `up` succeeded in 22 s without starting the guest again.
- `vehicle down` stopped the guest and gave `cvd-etap-01` back to `cvd-ebr`, alias cleared. Its first run reported
  `ivi-gw`'s port still present 5 s after its namespace was removed; a second `down` succeeded and
  `check-leaks.sh` found nothing. Diagnostic containers had joined that namespace during the run.

## What ran

| Item | Value |
|---|---|
| vxedge | `main` plus the attach backend (vxedge PR "attach backend"), release build |
| AAOS | AOSP Cuttlefish `aosp_cf_x86_64_auto-userdebug` build `16644040`; images checked against `aaos/SHA256SUMS` at start |
| Host stack | `cuttlefish-base` 1.57.13, the build's own host package; its host Vehicle HAL server replaced by a stub |
| `ivi-gw` payload | `localhost/vxedge/vxvhal:1`, vxvhal `20ba563` static musl build; the published part replaces it |
| Kuksa | databroker 0.7.1, pinned by digest, on `ivi-gw` |

## Limits

- `vbmeta*.img` are not pinned: Cuttlefish regenerates them at each launch.
- One AAOS instance per host: Cuttlefish's first tap and port 9300.
- Checks were run by hand. The 10-of-10 gate on vxedge 0.9.1 is [`../aaos-gate-2026-11-08`](../aaos-gate-2026-11-08);
  the first `down`'s failure here was a vxedge bug, fixed in 0.9.1 (attach zones stop last).

## Files

`transcript.txt` (the `up`), `vehicle-document.sha256` (the documents and the adapter as run).
