# exp-001 — ADAS slice isolation under infotainment load (H1)

- runs: 25 archives, input sha256 `ac2496e3f58e…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 7.0.0-38-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 48.4 (4.4) | 68.9 (8.7) | 79.8 (9.3) | 0.0 |
| 100 | 5 | 60000 | 49.3 (1.1) | 69.3 (2.6) | 81.3 (3.0) | 0.0 |
| 250 | 5 | 60000 | 48.5 (2.0) | 68.2 (5.0) | 80.3 (7.6) | 0.0 |
| 400 | 5 | 60000 | 46.3 (4.0) | 66.2 (7.6) | 79.6 (8.7) | 0.0 |
| 600 | 5 | 60000 | 48.4 (2.0) | 65.6 (6.8) | 79.9 (9.6) | 0.0 |

## H1 verdict

- adas p99 at max load (600 mbit): 79.9 µs = 1.00x baseline (79.8 µs); threshold 2.0x
- **H1 HOLDS** on this host
