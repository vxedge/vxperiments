# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) once the first tag is cut (see
`docs/VERSIONING.md` in the `docs` repo — no `v0.1.0` yet, pre-phase-1-gate).

Result summaries (`results/*/*.md`,`.csv`) are tracked here, not versioned as releases —
each is reproducible from its manifest + digests per the reproducibility gate
(`.claude/skills/experiment-methodology`), which is a finer-grained provenance mechanism
than a repo tag.

## [Unreleased]

### Added
- `exp-001` (H1, slice isolation): full campaign 2026-07-10, 5 reps x 5 loads, 60k
  samples/point. **H1 HOLDS** — adas p99 0.93x baseline under 600 mbit offered overload,
  zero loss.
- `exp-002` (H3, packaging): full campaign 2026-07-11, 5 reps x 3 arms. **H3 HOLDS** —
  packaging measurably affects RTT (container < libvirt < qemu-microvm).
- `exp-002b` (H3 decomposition): full isolated campaign 2026-07-12, 5 reps x 6 arms.
  Decomposed the exp-002 finding: not machine type, but virtio transport (dominant),
  vhost-net, and management-layer defaults.
- Analysis notebooks (`analyze_exp001.py`/`analyze_exp002.py`/`analyze_exp002b.py`):
  archive-only, percentile tables + IQR, decomposition verdicts, headless/CI-runnable.
- `exp-003` (H4, OTA co-location): manifest, runner, and analyzer written 2026-07-12,
  built with every exp-002b-review lesson applied from the start (guarded `vxprobe send`,
  loss with its denominator, `tool_versions`, 10s warmup). Two arms — baseline vs a
  sustained OTA delivery burst — over the same adas slice/QoS/probe parameters as
  exp-001. Manifest validated against the real parser; analyzer validated against
  synthetic archives. Campaign not yet run.

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

### Known gaps
- `exp-002` still runs its 3 arms concurrently (retrofit to `exp-002b`'s single-arm
  isolation tracked, low priority — its own audit showed zero loss).
- `exp-003` (H4) blocked on `vxedge`-side ota service wiring.
