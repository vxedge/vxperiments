# exp-002 — packaging backend vs latency (H3)

- runs: 15 archives, manifest sha256 `3ae0c23e843f…`
- probe: 1000 pps x 60 s per arm, idle topology
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, KVM=True, governor=performance, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | Δp50 vs container | Δp99 vs container | loss % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| container | 5 | 60000 | 56.0 (0.8) | 80.8 (1.3) | 95.0 (2.7) | +0.0 | +0.0 | 0.0 |
| microvm | 5 | 60000 | 113.9 (1.1) | 144.5 (1.3) | 164.2 (2.0) | +57.9 | +69.2 | 0.0 |
| libvirt | 5 | 60000 | 74.5 (2.7) | 105.6 (2.7) | 122.8 (2.5) | +18.5 | +27.8 | 0.0 |

## H3 verdict

- packaging measurably affects RTT: microvm, libvirt differ from container beyond its IQR — **H3 HOLDS**
