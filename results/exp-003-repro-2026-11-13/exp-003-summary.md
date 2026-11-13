# exp-003 — ADAS slice SLA under OTA co-location (H4), release-build rerun

- campaign: `c-5fcd0cf21abf`, profile `repro`, package `sha256:11820fd244ff…` (`vxedge/exp-003` 0.2.0, locked)
- runs: 10 archives (`vxarchive/2`), each listed with its sha256 in `campaign.json`
- tools: vxedged 0.25.0 (release), vxprobe 0.2.3 (release), vxota 0.1.2 (release), vxota-probe 0.1.2 (release), vxtelemetry 0.7.1
- probe: 1000 pps, 60 s per trial, 10 s warmup discarded; burst artifact 5 MB, one client back to back
- host: kernel 7.0.0-43-generic, PREEMPT_RT=False, governor=performance; run folder outside the home directory
- per-trial values are the probe's last summary in the trial window; arm values are the median across repetitions with the hinge IQR in brackets, as vxedged judges them

| arm | reps | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % | ota deliveries ok/fail (median) |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 35.30 (1.41) | 46.72 (2.94) | 61.60 (1.06) | 0.00 | n/a |
| ota-burst | 5 | 35.33 (0.53) | 48.38 (2.90) | 63.45 (2.00) | 0.00 | 837/0 |

## H4 verdict

- adas p50: burst raises the median by +0.03 µs against a threshold of 1.41 µs (the larger arm IQR, at least 1.00 µs); loss 0 in both arms
- **H4 HOLDS** on this host (pass)
- the frozen `exp-003` campaign used a debug-built vxprobe; this rerun uses release builds of the probe and the OTA tools
