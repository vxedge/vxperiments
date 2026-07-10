# exp-001 — ADAS slice isolation under infotainment load (H1)

- runs: 25 archives, manifest sha256 `e51721c1a5a0…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 47.4 (5.5) | 62.5 (4.9) | 77.3 (4.3) | 0.0 |
| 100 | 5 | 60000 | 42.9 (2.6) | 61.2 (3.0) | 74.5 (3.9) | 0.0 |
| 250 | 5 | 60000 | 42.6 (2.7) | 60.7 (6.2) | 72.1 (6.5) | 0.0 |
| 400 | 5 | 60000 | 43.4 (2.0) | 60.4 (3.6) | 72.0 (4.9) | 0.0 |
| 600 | 5 | 60000 | 42.9 (1.4) | 59.5 (4.1) | 71.7 (5.2) | 0.0 |

## H1 verdict

- adas p99 at max load (600 mbit): 71.7 µs = 0.93x baseline (77.3 µs); threshold 2.0x
- **H1 HOLDS** on this host
