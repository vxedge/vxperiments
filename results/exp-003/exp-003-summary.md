# exp-003 — ADAS slice SLA under OTA co-location (H4)

- runs: 10 archives, manifest sha256 `007ffd65472e…`
- probe: 1000 pps x 60 s per arm, timeout 1000 ms, warmup 10 s discarded, burst artifact 5 MB
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance
- caveats: shared-host gateway; full profile; v1 OTA transport binds a plain host address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling contention between the OTA workload and the adas probe, not gateway-QoS-enforced network contention
- telemetry note: baseline archives show ~50% vxtelemetry scrape completeness by design, not data loss — `telemetry.prometheus.scrape_targets` includes the vxota-probe exporter (127.0.0.1:9902) for both arms, but nothing listens there during baseline (the burst driver only runs in ota-burst). The adas-relevant target (127.0.0.1:9801) is 100% complete in every archive; only the irrelevant, known-absent target's scrapes fail.

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 60000 | 47.2 (1.8) | 69.6 (1.9) | 82.0 (2.9) | 0.0 (0/60000) | n/a | n/a |
| ota-burst | 5 | 60000 | 45.8 (1.3) | 67.5 (2.5) | 80.1 (2.9) | 0.0 (0/60000) | 356.0/0.0 | 206.0 |

## H4 verdict

- adas p50: baseline 47.2 µs vs ota-burst 45.8 µs (Δ -1.4 µs, IQR threshold 1.8 µs)
- **H4 HOLDS** on this host
