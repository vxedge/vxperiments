# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)

- runs: 25 archives, input sha256 `df49cf7622b4…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 7.0.0-42-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile; TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)

## snssai arm

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 270.1 (5.8) | 312.8 (7.4) | 339.7 (11.5) | 0.0 |
| 100 | 5 | 60000 | 260.2 (5.8) | 311.0 (2.4) | 339.7 (1.4) | 0.0 |
| 250 | 5 | 60000 | 269.3 (4.7) | 324.1 (4.2) | 356.1 (7.2) | 0.0 |
| 400 | 5 | 59997 | 267.5 (2.3) | 312.1 (0.9) | 341.2 (1.9) | 0.0033 |
| 600 | 5 | 59998 | 268.8 (3.5) | 311.8 (2.2) | 339.2 (2.7) | 0.0 |

## vlan arm (exp-001, frozen — not rerun)

| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |
|---:|---:|---:|---:|
| 0 | 89.6 | 339.7 | 3.79 |
| 100 | 87.5 | 339.7 | 3.88 |
| 250 | 84.5 | 356.1 | 4.21 |
| 400 | 85.2 | 341.2 | 4.00 |
| 600 | 81.9 | 339.2 | 4.14 |

## H2 verdict

- p99 growth baseline->600mbit: vlan 0.91x, snssai 1.00x (tolerance 1.1x of vlan's own ratio)
- **H2 HOLDS** on this host
