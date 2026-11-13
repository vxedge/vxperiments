#!/usr/bin/env bash
# Verdict parity (X6.2): vxedge's verdict engine, judging each package's criteria, must give the
# published verdict on every full published dataset whose archives hold samples. Each row of
# scripts/parity/parity.tsv names a dataset, the package whose criteria judge it, how its archive
# names map to trials, and the published outcome per criterion.
#
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh           # archives under results/
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh --fetch   # archives from the Zenodo record
#
# --fetch downloads each dataset from the pinned version of the Zenodo record that holds the raw
# archives (10.5281/zenodo.23804197; version 2026-11-v2, 10.5281/zenodo.24192950) and checks it
# against scripts/parity/SHA256SUMS, that version's published SHA256SUMS, first.
#
# A dataset named `results/<folder>` is a run committed here as each step's text output, from
# before its experiment was a package: scripts/frozen-checks.py builds its trial archives with the
# package's own steps, and it is never fetched. exp-016's frozen run is one.
#
# A `--name` pattern of `-` means a campaign wrote the archives and they name their own trials.
#
# Not covered: exp-005's and exp-010's frozen sets (their archives hold probe summaries, not
# samples; exp-010's H2 is judged from its live repro, results/exp-010-repro-2026-11-13) and the
# quick-profile sets (a
# different top load and a pipeline check only, never reported).
set -euo pipefail
cd "$(dirname "$0")/.."
vxedge=${VXEDGE:-vxedge}
table=scripts/parity/parity.tsv
sums=$PWD/scripts/parity/SHA256SUMS
record=https://zenodo.org/records/24192950/files
archives=results
built=()
cleanup() { rm -rf "${built[@]}"; [ "$archives" = results ] || rm -rf "${archives:?}"; }
trap cleanup EXIT
if [ "${1:-}" = --fetch ]; then
  archives=$(mktemp -d)
fi
failed=0 checked=0
while IFS=$'\t' read -r dataset experiment pattern expected; do
  case $dataset in '' | '#'*) continue ;; esac
  dir=$archives/$dataset
  case $dataset in
    results/*)
      dir=$(mktemp -d)
      built+=("$dir")
      python3 scripts/frozen-checks.py "$dataset" "$experiment" "$dir" >/dev/null </dev/null
      ;;
    *)
      if [ "${1:-}" = --fetch ]; then
        curl -fsSL --retry 3 -o "$archives/$dataset.tgz" "$record/$dataset.tgz?download=1"
        (cd "$archives" && grep " $dataset.tgz\$" "$sums" | sha256sum -c --quiet -)
        tar -C "$archives" --no-same-owner -xzf "$archives/$dataset.tgz"
      fi
      ;;
  esac
  name=()
  [ "$pattern" = - ] || name=(--name "$pattern")
  got=$("$vxedge" results verdict --json --experiment "$experiment" "${name[@]}" "$dir" |
    jq -r '[.criteria[] | "\(.id)=\(.outcome)"] | join(" ")')
  checked=$((checked + 1))
  if [ "$got" = "$expected" ]; then
    echo "ok   $dataset: $got"
  else
    echo "FAIL $dataset: engine $got, published $expected"
    failed=$((failed + 1))
  fi
done <"$table"
echo "$((checked - failed)) of $checked datasets give their published verdicts"
[ "$failed" -eq 0 ] && [ "$checked" -gt 0 ]
