# exp-001 — ADAS slice isolation under infotainment load (H1)

- runs: 25 archives, input sha256 `ac2496e3f58e…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 7.0.0-38-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 55.9 (2.3) | 70.9 (7.0) | 85.6 (4.2) | 0.0 |
| 100 | 5 | 60000 | 49.2 (0.7) | 69.6 (3.2) | 85.1 (2.4) | 0.0 |
| 250 | 5 | 60000 | 49.4 (3.1) | 68.6 (4.7) | 80.0 (8.8) | 0.0 |
| 400 | 5 | 60000 | 46.2 (2.6) | 65.0 (9.4) | 77.2 (10.9) | 0.0 |
| 600 | 5 | 60000 | 48.4 (3.3) | 65.0 (6.3) | 80.1 (7.1) | 0.0 |

## H1 verdict

- adas p99 at max load (600 mbit): 80.1 µs = 0.94x baseline (85.6 µs); threshold 2.0x
- **H1 HOLDS** on this host
