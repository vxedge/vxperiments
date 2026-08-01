# tools/ — analysis and helpers for this experiment

`fetch-parts.sh` populates `parts/` with the guest bundle the VM arms boot and verifies it
against the digests recorded in `parts/linux-probe.sha256`. Run it once before the first
campaign; it is idempotent.

`scripts/run.sh` runs the campaign; this directory is for everything around it. Shared analysis
lives in the repo's `notebooks/`; what belongs here is what only this experiment needs.
