# exp-003 — ADAS slice SLA under OTA co-location (H4)

- runs: 10 archives, manifest sha256 `5dc4c2a6b860…`
- probe: 1000 pps x 60 s per arm, timeout 1000 ms, warmup 10 s discarded, burst artifact 5 MB
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=performance
- caveats: shared-host gateway; full profile; v1 OTA transport binds a plain host address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling contention between the OTA workload and the adas probe, not gateway-QoS-enforced network contention
- telemetry note: optional-target (vxota-probe exporter, 127.0.0.1:9902) completeness by arm: baseline 0.0%, ota-burst 100.0% — expected to be low/zero in `baseline` (nothing listens there outside `ota-burst` by design; tracked separately via `optional_scrape_targets` and does not affect the required-target completeness above).

| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 60000 | 42.4 (2.8) | 63.0 (4.4) | 78.1 (7.9) | 0.0 (0/60000) | n/a | n/a |
| ota-burst | 5 | 60000 | 41.7 (1.2) | 60.6 (3.3) | 75.4 (4.9) | 0.0 (0/60000) | 354.0/0.0 | 205.0 |

## H4 verdict

- adas p50: baseline 42.4 µs vs ota-burst 41.7 µs (Δ -0.7 µs, IQR threshold 2.8 µs)
- **H4 HOLDS** on this host

## Reproducibility check vs the original 2026-07-13 campaign (`exp-003-summary.md`)

Gate (experiment-methodology skill): rerun on the same host — medians within the original
run's IQR ⇒ reproducible. Manifest sha differs (`5dc4c2a6b860…` vs the original's
`007ffd65472e…`) because the manifest itself changed between the two runs (the
`optional_scrape_targets` schema fix, landed the same day) — not a rerun of an identical
config, but the same experiment design and parameters otherwise.

| arm | metric | original median (IQR) | rerun median | Δ | within original IQR? |
|---|---|---:|---:|---:|:---:|
| baseline | p50 | 47.2 (1.8) | 42.4 | -4.8 | **no** |
| baseline | p95 | 69.6 (1.9) | 63.0 | -6.6 | **no** |
| baseline | p99 | 82.0 (2.9) | 78.1 | -3.9 | **no** |
| ota-burst | p50 | 45.8 (1.3) | 41.7 | -4.1 | **no** |
| ota-burst | p95 | 67.5 (2.5) | 60.6 | -6.9 | **no** |
| ota-burst | p99 | 80.1 (2.9) | 75.4 | -4.7 | **no** |

**0 of 6 metric/arm pairs pass the strict absolute-value IQR gate** — a notably wider miss
than exp-001's rerun (14/15 passed) and exp-002's (container/microvm mostly held). Worth
being direct about: this is the weakest of the three reproducibility checks by that
measure, and it happened *same-day* (original campaign and this rerun were both run on
2026-07-13, hours apart, not across days) — so it isn't obviously explained by long-run
thermal/scheduler drift the way a multi-day gap might be.

What is NOT in question: the shift is close to uniform across both arms (baseline -4.8µs
p50, ota-burst -4.1µs p50 — nearly identical) and in the same direction seen in every other
rerun this session (exp-001, exp-002 also ran measurably faster on their second pass). The
**substantive H4 comparison is unaffected**: it's a within-campaign relative measurement
(burst vs baseline, both measured under the same host state), and Δp50 stayed the same
order of magnitude and sign (-1.4µs original vs -0.7µs rerun, both comfortably inside their
own IQR threshold) — **H4 still holds, with the same conclusion**.

**Honest framing**: this host's absolute RTT baseline drifts by several µs across sessions
run hours apart on the same day — larger than any individual campaign's own IQR suggests.
Within-campaign IQRs measure repetition-to-repetition noise, not session-to-session drift;
they should not be read as bounds on absolute latency across time. The three hypotheses
(H1/H3/H4) are all *comparative* claims (slice A vs slice B, arm vs arm, burst vs
baseline) measured within one campaign, which is exactly why they hold up here despite the
absolute numbers moving — but this is a real caveat for anyone citing an absolute µs figure
from these results as a fixed property of the testbed rather than of one session on one
host. Not gate-blocking (H4's own conclusion is intact), but worth recording plainly rather
than only reporting the metric that happened to look cleanest.

Raw archives for this rerun are not committed (per repo convention); this file and its
`.csv` are the retained record.
