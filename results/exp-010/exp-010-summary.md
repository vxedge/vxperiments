# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)

- runs: 25 archives, manifest sha256 `aab3effc3749…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=powersave, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile; TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)

## snssai arm

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 265.2 (11.6) | 294.4 (19.7) | 321.0 (21.5) | 0.0 |
| 100 | 5 | 60000 | 272.1 (2.3) | 311.0 (3.8) | 333.8 (3.6) | 0.0 |
| 250 | 5 | 60000 | 288.8 (6.4) | 341.2 (6.7) | 369.2 (5.0) | 0.0 |
| 400 | 5 | 60000 | 267.5 (10.2) | 305.4 (4.6) | 328.4 (5.0) | 0.0 |
| 600 | 5 | 60000 | 265.7 (4.2) | 306.2 (3.3) | 330.0 (2.3) | 0.0 |

## vlan arm (exp-001, frozen — not rerun)

| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |
|---:|---:|---:|---:|
| 0 | 77.3 | 321.0 | 4.15 |
| 100 | 74.5 | 333.8 | 4.48 |
| 250 | 72.1 | 369.2 | 5.12 |
| 400 | 72.0 | 328.4 | 4.56 |
| 600 | 71.7 | 330.0 | 4.60 |

## H2 verdict

- p99 growth baseline->600mbit: vlan 0.93x, snssai 1.03x (tolerance 1.1x of vlan's own ratio)
- **H2 DOES NOT HOLD** on this host
