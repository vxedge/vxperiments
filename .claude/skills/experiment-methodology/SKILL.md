---
name: experiment-methodology
description: Statistical and methodological rigor for vxedge experiments — use when designing experiment manifests, running measurement campaigns, writing analysis notebooks, or reporting latency/jitter/loss numbers. The difference between numbers and publishable evidence.
---

# Experiment methodology — numbers OEMs and reviewers trust

A measurement that can't defend itself at review is noise. Every experiment follows this
discipline (ARCHITECTURE §12 is the spec; this is the practice).

## Design

- **One hypothesis per experiment** (exp-001→H1, exp-002→H3, exp-010→H2 …). If a manifest
  tests two things, split it.
- **Change one variable across arms**; topology, images, durations identical between
  compared runs. Comparisons across different topologies are invalid by construction.
- Load sweeps cover: idle baseline → nominal → saturation → overload. The interesting slice
  behavior lives at the knee; find it, don't just bracket it.
- Duration per point ≥ 60 s of steady state, sized so the tail percentile has support:
  **p99 needs ≥ 10 000 samples** to mean anything; state the sample count next to every
  percentile.

## Execution

- **Warmup is discarded**: first 10% of each run (or 10 s, whichever is larger) never enters
  the statistics.
- **≥ 5 repetitions per configuration**, fresh `up`/`down` cycle each time (this also
  regression-tests idempotency). Report median across repetitions with IQR or 95% CI —
  never a single run, never a bare mean for latency.
- Record in results metadata, every run: manifest SHA-256, tool versions, kernel + flavour
  (PREEMPT_RT or not), CPU pinning/isolcpus, governor, load average before start, and the
  timestamping method (userspace vs kernel). Missing metadata = invalid run.
- The host does nothing else during a run. If completeness (vxtelemetry) < 100%, the run is
  flagged and excluded unless the gap is explained.

## Analysis

- **Notebooks read archives only** (`results/<exp>.zip`) — never live systems, never loose
  files. Regenerating every figure from archives must work headlessly (CI-runnable).
- Report distributions, not points: p50/p95/p99 + IQR; CDFs or box plots over bar charts
  for latency. Jitter = stated definition (we use RTT stddev; say so in the caption).
- Loss is reported with its denominator (lost/sent), and the probe timeout that defines it.
- Negative/odd results are reported, not hidden — a slice configuration that *fails* to
  isolate is a finding.
- Every figure caption states: configuration, repetitions, sample count, and the caveats
  that apply (shared-host gateway, non-RT kernel, userspace timestamps).

## Reproducibility gate (before any number leaves the repo)

Rerun the exact configuration from its archive's manifest on the same host: medians within
the original run's IQR ⇒ reproducible. That check is exp-001's "run twice, diff
distributions" task — apply it to every experiment thereafter.
