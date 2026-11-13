#!/usr/bin/env bash
# exp-010's H2 verdict, rechecked from the published archives with notebooks/analyze_exp010.py.
#
#   notebooks/check-exp010.sh
#
# Downloads exp-010 (the snssai arm) and exp-001 (the frozen vlan arm it is judged against) from
# the pinned version of the Zenodo record, checks each against scripts/parity/SHA256SUMS, runs the
# notebook, and requires its summary to match results/exp-010/ byte for byte. The vxedge verdict
# engine cannot judge these archives: they hold probe summaries, not samples (see README.md here).
set -euo pipefail
cd "$(dirname "$0")/.."
record=https://zenodo.org/records/24192950/files
sums=$PWD/scripts/parity/SHA256SUMS
work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT
for dataset in exp-010 exp-001; do
  curl -fsSL --retry 3 -o "$work/$dataset.tgz" "$record/$dataset.tgz?download=1"
  (cd "$work" && grep " $dataset.tgz\$" "$sums" | sha256sum -c --quiet -)
  tar -C "$work" --no-same-owner -xzf "$work/$dataset.tgz"
done
PYTHONDONTWRITEBYTECODE=1 python3 notebooks/analyze_exp010.py "$work/exp-010" --baseline "$work/exp-001" --out-dir "$work/out" >/dev/null
for f in exp-010-summary.md exp-010-summary.csv; do
  diff -u "results/exp-010/$f" "$work/out/$f"
done
grep -F -- '- **H2 HOLDS**' "$work/out/exp-010-summary.md"
echo "exp-010: the notebook reproduces the published summary and its H2 verdict"
