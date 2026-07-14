# exp-001 — ADAS slice isolation under infotainment load (H1)

- runs: 2 archives, manifest sha256 `e51721c1a5a0…`
- probe: 500 pps x 12 s per point, warmup 3 s discarded before probing
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; QUICK PROFILE — pipeline validation only, sample counts below tail-percentile support, NOT reportable

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 6000 | 50.6 (0.0) | 73.9 (0.0) | 91.9 (0.0) | 0.0 |
| 400 | 1 | 6000 | 47.9 (0.0) | 69.0 (0.0) | 82.8 (0.0) | 0.0 |

## H1 verdict

- adas p99 at max load (400 mbit): 82.8 µs = 0.90x baseline (91.9 µs); threshold 2.0x
- **H1 HOLDS** on this host (quick profile — indicative only)
