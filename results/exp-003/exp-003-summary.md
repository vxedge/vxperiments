# exp-003 — ADAS slice SLA under OTA co-location (H4)

- runs: 10 archives, input sha256 `1efebdef615f…`
- probe: 1000 pps x 60 s per arm, timeout 1000 ms, warmup 10 s discarded, burst artifact 5 MB
- host: kernel 7.0.0-28-generic, PREEMPT_RT=False, governor=performance
- caveats: shared-host gateway; full profile; v1 OTA transport binds a plain host address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling contention between the OTA workload and the adas probe, not gateway-QoS-enforced network contention
- telemetry note: optional-target (vxota-probe exporter, 127.0.0.1:9902) completeness by arm: baseline 0.0%, ota-burst 100.0% — expected to be low/zero in `baseline` (nothing listens there outside `ota-burst` by design; tracked separately via `optional_scrape_targets` and does not affect the required-target completeness above).

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 60000 | 52.2 (6.0) | 80.7 (4.9) | 97.7 (5.6) | 0.0 (0/60000) | n/a | n/a |
| ota-burst | 5 | 60000 | 51.9 (1.7) | 79.9 (6.3) | 93.1 (5.5) | 0.0 (0/60000) | 361.0/0.0 | 204.0 |

## H4 verdict

- adas p50: baseline 52.2 µs vs ota-burst 51.9 µs (Δ -0.3 µs, one-sided IQR threshold 6.0 µs)
- **H4 HOLDS** on this host
