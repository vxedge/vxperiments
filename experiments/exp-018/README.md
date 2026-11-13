# exp-018 — in-vehicle protocol loads against the ADAS slice

Does real in-vehicle protocol traffic on the infotainment slice show in the ADAS slice's
latency? Each arm runs one protocol stack, as its part ships, between two infotainment devices:

| Arm | What runs on the infotainment slice | Part |
|---|---|---|
| `idle` | nothing: the unloaded reference | none |
| `dds` | Cyclone DDS `ddsperf`: 1 KiB samples at 1 kHz, reliable, publisher to subscriber | `agent/load/app/dds-perf:0.1.0` |
| `someip` | vsomeip: a client requesting every 10 ms from a service, with service discovery | `agent/load/app/someip-samples:0.1.0` |
| `can` | Eclipse Kuksa's CAN provider replaying a recorded vehicle trace into the databroker | `svc/signal/app/kuksa-can-provider:0.1.0` |

A probe measures the ADAS slice at 1000 pps, device to device. The probe and the loads cross the
same in-vehicle bridge and share the host's CPU. Neither crosses the shaped uplink, so this is not
exp-001's uplink question, and the slices carry no QoS: the only separation is the VLAN.

## The package

This folder is the `vxp/1` package `vxedge/exp-018`, version 0.1.0 (`vxp.yaml`). It needs vxedge
0.29.0 or later, which runs the baseline the experiment names and lets a parameter bind it, and
starts a container part with its baseline's `run` (`ARCHITECTURE.md` §6.0.2 and §6.0.3).

- `vehicle.yaml`: five container devices on two slices, and the Kuksa databroker on `broker`.
- `parts.yaml`, `parts-dds.yaml`, `parts-someip.yaml`, `parts-can.yaml`: one baseline per arm.
  They differ only in what `load-a` and `load-b` run; a load device with a `local/…` part runs
  no payload.
- `main.yaml`: the `load` parameter binds `baseline`, so each arm is a baseline over the
  unchanged vehicle. The criteria judge each loaded arm against `idle` with exp-001's bound:
  median p99 within 2x and median loss within 0.5 points.

Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan --profile repro          # the 20 trials, checked; touches nothing
vxedge campaign start --profile repro         # one archive per trial, then the verdict
```

`quick` checks the pipeline only and is never reported.

## What each arm measures

Each load is the protocol's traffic as its part ships it, at the stated rate, not a swept rate:
the arms answer whether that traffic shows in the other slice, not how much load breaks it. The
loads report no numbers of their own here; the probe is the measurement. DDS discovers its peer
from a fixed unicast list (`CYCLONEDDS_URI`), so the `dds` arm does not depend on multicast.
SOME/IP service discovery is multicast: each side adds a `224.0.0.0/4` route, which is what its
`NET_ADMIN` capability is for.
