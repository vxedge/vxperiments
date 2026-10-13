# exp-001 — reproducibility check on kernel 7.0.0-38 (2026-10-13)

Two full `--repro` campaigns, same host, same input sha256 `ac2496e3f58e…`, kernel
7.0.0-38-generic (the frozen campaign in `results/exp-001/` ran on 7.0.0-28-generic with input
sha256 `2666fbf561ae…`, the tree at commit `3cc9b2f`). Summaries: `../exp-001-repro-2026-10-13/`
(run 1) and this directory (run 2). Neither replaces the frozen results.

What changed in the workspace between the two input shas: `host_pinning.sh` tolerates a failing
`taskset` (86dbe4d) and comment-only edits (86dbe4d, 575da9e). Topology, sweep, probes and
shaping are unchanged.

**H1 verdict:** holds in both. p99 at 600 mbit ÷ idle: frozen 0.91x, run 1 0.94x, run 2 1.00x
(threshold 2.0x). Loss 0.0 % everywhere; at least 60 000 samples per point.

## Gate: new median within the reference run's IQR (15 metric x load pairs)

| comparison | within | outside the reference IQR |
|---|---:|---|
| run 1 vs frozen | 9 / 15 | p50@0 +6.0, p50@400 -4.4, p95@400 -7.3, p99@400 -8.0, p50@600 -3.0, p95@600 -4.2 |
| run 2 vs frozen | 8 / 15 | p50@0 -1.5, p99@0 -9.8, p50@400 -4.3, p95@400 -6.1, p99@400 -5.6, p50@600 -3.0, p95@600 -3.6 |
| run 2 vs run 1 | 12 / 15 | p50@0 -7.5, p99@0 -5.8, p99@100 -3.8 |

(Δ in µs, new minus reference.)

## Reading

On kernel -38 the host agrees with itself (12 of 15). Both runs read 3-8 µs below the frozen run
at 400 and 600 mbit, in the same pairs. The H1 verdict does not depend on it. The cause was not
isolated; the kernel change (-28 to -38) is the leading suspect and was not tested. The frozen
numbers stay authoritative for the published figures: they match their recorded input sha
exactly. Raw archives are not committed (see `results/README.md`).
