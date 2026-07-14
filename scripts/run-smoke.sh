#!/usr/bin/env bash
# run-smoke.sh — H* pipeline smoke: every experiment's --quick mode, in sequence.
#
# Purpose: after any code change, verify in ~5 minutes that the full measurement
# pipeline behind each frozen hypothesis (H1/H3/H4) still runs end to end —
# provision, probe, collect, analyze. Quick numbers are pipeline validation
# ONLY (never reportable); full campaigns and --repro reruns stay deliberate
# and manual (idle host, 35+ min each — experiment-methodology skill).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-smoke.sh
#
# Exit: 0 iff every runner and its analyzer succeeded. A missing prerequisite
# (unbuilt binary, absent guest bundle) is a FAIL, not a skip — the smoke's
# job is "everything green", and the runners' own error messages say the fix.
set -uo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "error: needs root (the runners provision real gateways) — sudo -E env \"PATH=\$PATH\" $0" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 1

declare -a RESULTS=()
FAILED=0

step() {
  local name="$1"; shift
  local t0 t1
  t0=$(date +%s)
  echo
  echo "=== smoke: $name"
  if "$@"; then
    t1=$(date +%s)
    RESULTS+=("PASS  $name  ($((t1 - t0))s)")
  else
    t1=$(date +%s)
    RESULTS+=("FAIL  $name  ($((t1 - t0))s)")
    FAILED=1
  fi
}

step "exp-001 quick (H1 pipeline)" ./scripts/run-exp-001.sh --quick
step "exp-001 analyze"             python3 notebooks/analyze_exp001.py results/exp-001-quick
step "exp-002 quick (H3 pipeline)" ./scripts/run-exp-002.sh --quick
step "exp-002 analyze"             python3 notebooks/analyze_exp002.py results/exp-002-quick
step "exp-002b quick (H3 decomposition pipeline)" ./scripts/run-exp-002b.sh --quick
step "exp-002b analyze"            python3 notebooks/analyze_exp002b.py results/exp-002b-quick
step "exp-003 quick (H4 pipeline)" ./scripts/run-exp-003.sh --quick
step "exp-003 analyze"             python3 notebooks/analyze_exp003.py results/exp-003-quick

# The runners chown their archives back to the invoking user, but the
# analyzers above ran as root and re-created summary files root-owned —
# hand the whole quick dirs back so unprivileged re-analysis works.
if [[ -n "${SUDO_UID:-}" ]]; then
  for d in results/*-quick; do
    [[ -d "$d" ]] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$d"
  done
fi

echo
echo "=== smoke summary"
for r in "${RESULTS[@]}"; do echo "  $r"; done
if [[ $FAILED -eq 0 ]]; then
  echo "SMOKE PASS — all H* pipelines run end to end (quick profiles: NOT reportable numbers)"
else
  echo "SMOKE FAIL — see the first failing step's output above"
fi
exit $FAILED
