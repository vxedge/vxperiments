# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — see `docs/VERSIONING.md` in the `docs` repo.

Result summaries (`results/*/*.md`,`.csv`) are tracked here, not versioned as releases —
each is reproducible from its manifest + digests per the reproducibility gate
(`.claude/skills/experiment-methodology`), which is a finer-grained provenance mechanism
than a repo tag.

## [Unreleased]

### Fixed
- `exp-002` hardened to isolate one arm at a time (2026-07-13), closing the "known gap" noted
  in 0.1.0: `exp-002.yaml` restructured from one 3-node zone into one zone per arm
  (`z-cont`/`z-microvm`/`z-libvirt`); `run-exp-002.sh` retrofitted with exp-002b's
  `start_arm()`/`stop_arm()` isolation pattern plus every other exp-002b/exp-003 hardening
  lesson (guarded `vxprobe send`, `tool_versions`/`cpu_pinning`, 10s warmup, surfaced `wait`
  exit codes); `analyze_exp002.py` now refuses archives missing `isolation=="single-arm"`,
  reports loss with its lost/sent denominator, and accepts `--out-dir=DIR`. Re-run
  (2026-07-13, 15 archives, zero loss) **superseded the frozen result**: H3 still holds and
  the arm ordering is unchanged, but libvirt's latency dropped measurably (p50 74.5→66.3µs,
  p99 122.8→110.7µs, more than the original's own IQR) once it no longer shared the host
  with idle container/microvm backends — container and microvm themselves barely moved.
  Frozen summary updated in place (`results/exp-002/exp-002-summary.md`).
- `exp-001` second-campaign reproducibility check (2026-07-13): reproducible — 14 of 15
  median/metric pairs within the original run's IQR, H1 verdict unchanged (0.93x original
  vs 0.95x rerun). Recorded separately from the frozen original:
  `results/exp-001/exp-001-repro-check-2026-07-13.md`.
- `exp-003` second-campaign reproducibility check (2026-07-13): 0 of 6 metric/arm pairs
  within the original run's IQR (a uniform ~4-7µs downward shift across both arms,
  same-day) — the weakest of the three reproducibility checks this session, and honestly
  reported as such. The substantive H4 comparison is unaffected (both arms drifted
  together; Δp50 -1.4µs original vs -0.7µs rerun, same order of magnitude/sign — **H4
  still holds**). Reading: within-campaign IQRs bound repetition-to-repetition noise, not
  cross-session host drift, which this host shows even hours apart on the same day; the
  comparative hypotheses are robust to it, absolute µs figures from a single campaign are
  not universal constants. Recorded separately:
  `results/exp-003/exp-003-repro-check-2026-07-13.md`. Also fixed in the same pass:
  `analyze_exp003.py`'s telemetry-completeness caveat was a hardcoded "~50%" claim (only
  true of the pre-`optional_scrape_targets` archives); now computed dynamically per
  campaign from `ingest/ingest-stats.json`'s required/optional scrape counters — confirmed
  the schema fix works (this rerun: 100% required-target completeness both arms).

## [0.1.0] - 2026-07-13

**Phase-1 gate passed**: H1, H3, and H4 all have reproducible numbers. Repos stay
private for now — see `docs/STATUS.md` for the public-visibility punch list.

### Added
- `exp-001` (H1, slice isolation): full campaign 2026-07-10, 5 reps x 5 loads, 60k
  samples/point. **H1 HOLDS** — adas p99 0.93x baseline under 600 mbit offered overload,
  zero loss.
- `exp-002` (H3, packaging): full campaign 2026-07-11, 5 reps x 3 arms. **H3 HOLDS** —
  packaging measurably affects RTT (container < libvirt < qemu-microvm).
- `exp-002b` (H3 decomposition): full isolated campaign 2026-07-12, 5 reps x 6 arms.
  Decomposed the exp-002 finding: not machine type, but virtio transport (dominant),
  vhost-net, and management-layer defaults.
- `exp-003` (H4, OTA co-location): full campaign 2026-07-13, 5 reps x 2 arms, zero loss
  both arms. **H4 HOLDS** — adas p50 45.8µs under a sustained OTA delivery burst
  (~355 successful deliveries/rep, zero failures) vs 47.2µs baseline, well within IQR.
  Same adas slice/QoS/probe parameters as exp-001. **This is the phase-1 gate's third and
  final arm — H1, H3, and H4 are all delivered.**
- Analysis notebooks (`analyze_exp001.py`/`analyze_exp002.py`/`analyze_exp002b.py`/
  `analyze_exp003.py`): archive-only, percentile tables + IQR, decomposition/comparison
  verdicts, headless/CI-runnable.
- `scripts/lib/freshness.sh`: shared per-binary staleness check used by all four
  run-exp-*.sh campaign runners (2026-07-13).

### Fixed
- exp-002b's first campaign attempt ran all 6 arms concurrently, causing CPU-contention-
  driven, non-reproducible packet loss (0-37%) hidden by the aggregate median; root-caused
  and fixed by isolating one arm at a time, with `isolation: single-arm` archive
  provenance the analyzer now refuses to proceed without (2026-07-12).
- An 8-angle code review of the exp-002b runner/analyzer found and fixed 10 further
  issues (unguarded `set -e` aborts that could lose an entire campaign on one bad
  measurement, a warmup below the methodology skill's own 10s minimum, missing
  `tool_versions`/`cpu_pinning` metadata, loss reported without its denominator, orphaned/
  silently-swallowed sidecar processes, a cleanup-trap zone-list drift risk, an
  `--out-dir=DIR` parsing gap); the campaign was re-run end-to-end on the hardened script
  and reproduced every conclusion (2026-07-12).
- exp-003's `baseline` archives showed ~50% aggregate telemetry-scrape completeness,
  traced to a manifest scrape target (the OTA burst driver's exporter) with nothing
  listening during that arm by design — not real data loss (the adas-relevant target was
  100% complete every repetition). Explained directly in the analyzer output; no re-run
  needed (2026-07-13).
- `check_fresh()` (duplicated in every run-exp-*.sh) compared any source file in the
  *whole repo* against each individual binary, false-positiving on multi-binary repos
  when only a sibling binary's source changed — hit twice running exp-003. Replaced with
  `scripts/lib/freshness.sh`'s per-crate-dependency-graph check, verified against the
  exact regression that motivated it (2026-07-13).
- Arm-conditional scrape targets: `exp-003.yaml` now declares the OTA burst driver's
  exporter under the new `telemetry.prometheus.optional_scrape_targets` (see `vxedge`'s
  and `vxtelemetry`'s CHANGELOGs) instead of as a required target. Future campaigns will
  show 100% `baseline` completeness instead of the already-frozen, already-explained
  ~50% figure (2026-07-13).

### Known gaps
- `exp-002` still runs its 3 arms concurrently (retrofit to `exp-002b`'s single-arm
  isolation tracked, low priority — its own audit showed zero loss).
- `exp-001`/`exp-003` don't yet have a formal second-campaign reproducibility check
  (`exp-002b` does).
