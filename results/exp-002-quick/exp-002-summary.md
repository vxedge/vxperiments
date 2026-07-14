# exp-002 — packaging backend vs latency (H3)

- runs: 3 archives, manifest sha256 `a8aa539dc04a…`
- probe: 500 pps x 10 s per arm, idle topology
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, KVM=True, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; QUICK PROFILE — pipeline validation only, NOT reportable

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | Δp50 vs container | Δp99 vs container | max loss % (lost/sent) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 1 | 5000 | 57.7 (0.0) | 87.1 (0.0) | 109.3 (0.0) | +0.0 | +0.0 | 0.0 (0/5000) |
| microvm | 1 | 5000 | 124.3 (0.0) | 155.5 (0.0) | 181.2 (0.0) | +66.6 | +71.9 | 0.0 (0/5000) |
| libvirt | 1 | 5000 | 76.5 (0.0) | 112.2 (0.0) | 138.0 (0.0) | +18.8 | +28.7 | 0.0 (0/5000) |

## H3 verdict

- packaging measurably affects RTT: microvm, libvirt differ from container beyond its IQR — **H3 HOLDS** (quick profile — indicative only)
