#!/usr/bin/env bash
# Verdict parity (X6.2): vxedge's verdict engine must give the notebooks' verdicts on every full
# published dataset whose archives hold samples. Each row of notebooks/criteria/parity.tsv names a
# dataset, the notebook's acceptance rule written as typed intent (a file in notebooks/criteria/, or
# the package that now holds it), how its archive names map to trials, and the outcome the notebook
# reached per criterion.
#
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh           # archives under results/
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh --fetch   # archives from the Zenodo record
#
# --fetch downloads each dataset from the pinned version of the Zenodo record that holds the raw
# archives (10.5281/zenodo.23804197) and checks it against notebooks/criteria/SHA256SUMS first.
#
# A dataset named `results/<folder>` is a run committed here as each step's text output, from
# before its experiment was a package: scripts/frozen-checks.py builds its trial archives with the
# package's own steps, and it is never fetched. exp-016's frozen run is one.
#
# Not covered: exp-005 and exp-010 (their archives hold probe summaries, not samples) and the
# quick-profile sets (a different top load, and the notebooks' 10 µs quick floor).
set -euo pipefail
cd "$(dirname "$0")/.."
vxedge=${VXEDGE:-vxedge}
table=notebooks/criteria/parity.tsv
record=https://zenodo.org/records/23810053/files
archives=results
built=()
cleanup() { rm -rf "${built[@]}"; [ "$archives" = results ] || rm -rf "$archives"; }
trap cleanup EXIT
if [ "${1:-}" = --fetch ]; then
  archives=$(mktemp -d)
fi
failed=0 checked=0
while IFS=$'\t' read -r dataset criteria pattern expected; do
  case $dataset in '' | '#'*) continue ;; esac
  dir=$archives/$dataset
  case $dataset in
    results/*)
      dir=$(mktemp -d)
      built+=("$dir")
      python3 scripts/frozen-checks.py "$dataset" "$criteria" "$dir" >/dev/null </dev/null
      ;;
    *)
      if [ "${1:-}" = --fetch ]; then
        curl -fsSL --retry 3 -o "$archives/$dataset.tgz" "$record/$dataset.tgz?download=1"
        (cd "$archives" && grep " $dataset.tgz\$" "$OLDPWD/notebooks/criteria/SHA256SUMS" | sha256sum -c --quiet -)
        tar -C "$archives" --no-same-owner -xzf "$archives/$dataset.tgz"
      fi
      ;;
  esac
  # A criteria entry with a `/` is a package folder from the repo root; a bare name is a file in
  # notebooks/criteria/.
  case $criteria in */*) experiment=$criteria ;; *) experiment=notebooks/criteria/$criteria ;; esac
  got=$("$vxedge" results verdict --json --experiment "$experiment" \
    --name "$pattern" "$dir" |
    jq -r '[.criteria[] | "\(.id)=\(.outcome)"] | join(" ")')
  checked=$((checked + 1))
  if [ "$got" = "$expected" ]; then
    echo "ok   $dataset: $got"
  else
    echo "FAIL $dataset: engine $got, notebook $expected"
    failed=$((failed + 1))
  fi
done <"$table"
echo "$((checked - failed)) of $checked datasets give the notebooks' verdicts"
[ "$failed" -eq 0 ] && [ "$checked" -gt 0 ]
