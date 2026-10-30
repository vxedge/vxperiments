# exp-003 — ADAS slice SLA under OTA co-location (H4)

- runs: 10 archives, input sha256 `432e00413bfe…`
- probe: 1000 pps x 60 s per arm, timeout 1000 ms, warmup 10 s discarded, burst artifact 5 MB
- host: kernel 7.0.0-42-generic, PREEMPT_RT=False, governor=performance
- caveats: shared-host gateway; full profile; v1 OTA transport binds a plain host address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling contention between the OTA workload and the adas probe, not gateway-QoS-enforced network contention
- telemetry note: optional-target (vxota-probe exporter, 127.0.0.1:9902) completeness by arm: baseline 0.0%, ota-burst 100.0% — expected to be low/zero in `baseline` (nothing listens there outside `ota-burst` by design; tracked separately via `optional_scrape_targets` and does not affect the required-target completeness above).

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 60000 | 56.2 (0.3) | 79.1 (0.9) | 91.4 (0.8) | 0.0 (0/60000) | n/a | n/a |
| ota-burst | 5 | 60000 | 54.6 (1.9) | 76.9 (1.5) | 88.7 (1.2) | 0.0 (0/60000) | 376.0/0.0 | 167.0 |

## OTA process resource footprint

| arm | process | reps matched | cpu % (mean) | rss MB (mean) |
|---|---|---:|---:|---:|
| baseline | ota-server | 5/5 | 0.0 | 9.9 |
| ota-burst | ota-probe | 5/5 | 69.5 | 24.3 |
| ota-burst | ota-server | 5/5 | 3.72 | 11.1 |

## H4 verdict

- adas p50: baseline 56.2 µs vs ota-burst 54.6 µs (Δ -1.6 µs, one-sided IQR threshold 1.9 µs)
- **H4 HOLDS** on this host
