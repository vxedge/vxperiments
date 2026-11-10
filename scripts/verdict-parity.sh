#!/usr/bin/env bash
# Verdict parity (X6.2): vxedge's verdict engine must give the notebooks' verdicts on every full
# published dataset whose archives hold samples. Each row of notebooks/criteria/parity.tsv names a
# dataset, the notebook's acceptance rule written as typed intent, how its archive names map to
# trials, and the outcome the notebook reached per criterion.
#
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh           # archives under results/
#   VXEDGE=/path/to/vxedge scripts/verdict-parity.sh --fetch   # archives from the Zenodo record
#
# --fetch downloads each dataset from the pinned version of the Zenodo record that holds the raw
# archives (10.5281/zenodo.23804197) and checks it against notebooks/criteria/SHA256SUMS first.
#
# Not covered: exp-005 and exp-010 (their archives hold probe summaries, not samples) and the
# quick-profile sets (a different top load, and the notebooks' 10 µs quick floor).
set -euo pipefail
cd "$(dirname "$0")/.."
vxedge=${VXEDGE:-vxedge}
table=notebooks/criteria/parity.tsv
record=https://zenodo.org/records/23810053/files
archives=results
if [ "${1:-}" = --fetch ]; then
  archives=$(mktemp -d)
  trap 'rm -rf "$archives"' EXIT
fi
failed=0 checked=0
while IFS=$'\t' read -r dataset criteria pattern expected; do
  case $dataset in '' | '#'*) continue ;; esac
  if [ "${1:-}" = --fetch ]; then
    curl -fsSL --retry 3 -o "$archives/$dataset.tgz" "$record/$dataset.tgz?download=1"
    (cd "$archives" && grep " $dataset.tgz\$" "$OLDPWD/notebooks/criteria/SHA256SUMS" | sha256sum -c --quiet -)
    tar -C "$archives" --no-same-owner -xzf "$archives/$dataset.tgz"
  fi
  got=$("$vxedge" results verdict --json --experiment "notebooks/criteria/$criteria" \
    --name "$pattern" "$archives/$dataset" |
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
