# exp-002 — packaging backend vs latency (H3)

- runs: 15 archives, manifest sha256 `a8aa539dc04a…`
- probe: 1000 pps x 60 s per arm, idle topology
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, KVM=True, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | Δp50 vs container | Δp99 vs container | max loss % (lost/sent) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 5 | 60000 | 54.3 (2.1) | 76.6 (9.0) | 89.9 (8.2) | +0.0 | +0.0 | 0.0 (0/60000) |
| microvm | 5 | 60000 | 113.5 (2.9) | 142.5 (5.9) | 159.5 (5.6) | +59.2 | +69.6 | 0.0 (0/60000) |
| libvirt | 5 | 60000 | 66.3 (4.7) | 92.2 (13.5) | 110.7 (12.9) | +12.0 | +20.8 | 0.0 (0/60000) |

## H3 verdict

- packaging measurably affects RTT: microvm, libvirt differ from container beyond its IQR — **H3 HOLDS**
