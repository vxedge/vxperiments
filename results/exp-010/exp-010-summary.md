# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)

- runs: 25 archives, manifest sha256 `aab3effc3749…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile; TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)

## snssai arm

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 269.6 (6.8) | 310.5 (10.9) | 345.3 (16.9) | 0.0 |
| 100 | 5 | 60000 | 256.9 (4.2) | 303.4 (4.5) | 331.0 (10.2) | 0.0 |
| 250 | 5 | 60000 | 266.5 (5.2) | 319.2 (4.1) | 352.0 (13.1) | 0.0 |
| 400 | 5 | 59999 | 267.0 (8.8) | 304.1 (12.8) | 330.5 (24.6) | 0.0 |
| 600 | 5 | 59999 | 267.3 (3.1) | 306.4 (6.0) | 345.9 (14.2) | 0.0 |

## vlan arm (exp-001, frozen — not rerun)

| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |
|---:|---:|---:|---:|
| 0 | 77.3 | 345.3 | 4.47 |
| 100 | 74.5 | 331.0 | 4.44 |
| 250 | 72.1 | 352.0 | 4.88 |
| 400 | 72.0 | 330.5 | 4.59 |
| 600 | 71.7 | 345.9 | 4.82 |

## H2 verdict

- p99 growth baseline->600mbit: vlan 0.93x, snssai 1.00x (tolerance 1.1x of vlan's own ratio)
- **H2 HOLDS** on this host
