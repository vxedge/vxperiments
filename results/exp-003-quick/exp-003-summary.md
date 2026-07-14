# exp-003 — ADAS slice SLA under OTA co-location (H4)

- runs: 2 archives, manifest sha256 `5dc4c2a6b860…`
- probe: 500 pps x 10 s per arm, timeout 1000 ms, warmup 2 s discarded, burst artifact 1 MB
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance
- caveats: shared-host gateway; QUICK PROFILE — pipeline validation only, NOT reportable; v1 OTA transport binds a plain host address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling contention between the OTA workload and the adas probe, not gateway-QoS-enforced network contention
- telemetry note: optional-target (vxota-probe exporter, 127.0.0.1:9902) completeness by arm: baseline 0.0%, ota-burst 100.0% — expected to be low/zero in `baseline` (nothing listens there outside `ota-burst` by design; tracked separately via `optional_scrape_targets` and does not affect the required-target completeness above).

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1 | 5000 | 50.8 (0.0) | 74.4 (0.0) | 88.9 (0.0) | 0.0 (0/5000) | n/a | n/a |
| ota-burst | 1 | 5000 | 46.9 (0.0) | 76.0 (0.0) | 92.4 (0.0) | 0.0 (0/5000) | 100.0/0.0 | 119.0 |

## H4 verdict

- adas p50: baseline 50.8 µs vs ota-burst 46.9 µs (Δ -3.9 µs, IQR threshold 1.0 µs)
- **H4 DOES NOT HOLD** on this host (quick profile — indicative only)

_(quick profile — indicative only, not for publication)_
