# AGENTS.md — vxedge/vxperiments

Manifest-driven experiment definitions, vehicle manifests, analysis notebooks, and results.
Master spec: `../docs/ARCHITECTURE.md` §6 (schemas — match them EXACTLY; the CLI has no other
validation source), §12 (methodology/metrics), §13 (reproducibility).

## What lands here

- `experiments/exp-*.yaml` — experiment manifests (schema §6.1). The `services:` blocks here
  are the **authoritative runtime descriptors** (image + config) for each experiment.
- `vehicles/vx-vehicle-*.yaml` — vehicle manifests (schema §6.2), referenced by experiments.
- `notebooks/` — Python analysis (percentile tables, isolation charts, CSV export).
- `results/` — conventions only; actual archives follow `results_prefix` and are not
  committed (large artifacts go to the registry/S3 per §13).

## Rules

- Manifests are versioned and authoritative; every results archive must be reproducible from
  its manifest + image digests + CLI version recorded in metadata.
- **Re-freezing a result updates `docs/FACTS.md` in the same change set.** That file is the
  registry every published number is quoted from (website, READMEs, `RESULTS.md`); a summary that
  moved without its registry row leaves the public numbers stale. The website's figure build
  refuses to draw a CSV that disagrees with `FACTS.md`.
- One experiment = one hypothesis focus. Name/describe accordingly (e.g. exp-001 → H1).
- Python for notebooks (§15); charts/CSVs must regenerate headlessly (CI-runnable) so paper
  figures are reproducible.

## Project skills

AI/contributor skills in `.claude/skills/`: **testbed-quality** (OEM-adoption bar) and
**experiment-methodology** (statistical rigor: repetitions, warmup, tail-percentile support,
archive-only analysis). Every experiment and notebook follows both.
