# exp-001 — ADAS slice isolation under infotainment load (H1)

- runs: 25 archives, input sha256 `2666fbf561ae…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 7.0.0-28-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 49.9 (0.8) | 71.4 (6.7) | 89.6 (6.4) | 0.0 |
| 100 | 5 | 60000 | 51.1 (3.0) | 72.0 (6.1) | 87.5 (7.0) | 0.0 |
| 250 | 5 | 60000 | 49.8 (1.9) | 70.1 (3.3) | 84.5 (4.7) | 0.0 |
| 400 | 5 | 60000 | 50.6 (1.3) | 72.3 (3.1) | 85.2 (4.2) | 0.0 |
| 600 | 5 | 60000 | 51.4 (1.8) | 69.2 (2.8) | 81.9 (5.0) | 0.0 |

## H1 verdict

- adas p99 at max load (600 mbit): 81.9 µs = 0.91x baseline (89.6 µs); threshold 2.0x
- **H1 HOLDS** on this host
