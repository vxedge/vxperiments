# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)

- runs: 25 archives, input sha256 `4fa24418b7a1…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 7.0.0-28-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile; TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)

## snssai arm

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 269.3 (7.3) | 305.2 (11.5) | 335.1 (14.1) | 0.0 |
| 100 | 5 | 60000 | 254.1 (3.6) | 299.5 (2.6) | 324.1 (6.9) | 0.0 |
| 250 | 5 | 59999 | 261.6 (4.0) | 313.1 (4.7) | 336.6 (12.7) | 0.0 |
| 400 | 5 | 59994 | 260.9 (1.9) | 294.7 (7.4) | 318.7 (23.0) | 0.0 |
| 600 | 5 | 59998 | 260.7 (4.7) | 293.4 (5.9) | 317.2 (10.8) | 0.0 |

## vlan arm (exp-001, frozen — not rerun)

| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |
|---:|---:|---:|---:|
| 0 | 89.6 | 335.1 | 3.74 |
| 100 | 87.5 | 324.1 | 3.70 |
| 250 | 84.5 | 336.6 | 3.98 |
| 400 | 85.2 | 318.7 | 3.74 |
| 600 | 81.9 | 317.2 | 3.87 |

## H2 verdict

- p99 growth baseline->600mbit: vlan 0.91x, snssai 0.95x (tolerance 1.1x of vlan's own ratio)
- **H2 HOLDS** on this host
