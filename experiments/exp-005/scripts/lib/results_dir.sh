#!/usr/bin/env bash
# results_dir.sh — frozen-campaign protection, shared by every run-exp-*.sh.
#
# Why: superseded-campaign archives used to be overwritten in place — exp-003's
# original archives were lost to its repro-check rerun, leaving only a truncated
# manifest digest in the frozen summary (risk register item, 2026-07-13).
# Rule now: the first full campaign owns results/<exp>/; every later full run is
# a reproducibility check and writes to a date-suffixed sibling; --quick pipeline
# validation writes to its own disposable dir. A dir holding archives is never
# silently overwritten.
#
# Usage:
#   source "$(dirname "$0")/lib/results_dir.sh"
#   RESULTS="$(resolve_results_dir "$REPO_DIR" exp-003 "$QUICK" "$REPRO")"
resolve_results_dir() {
  local repo_dir="$1" exp="$2" quick="${3:-0}" repro="${4:-0}"
  local frozen="$repo_dir/results/$exp"

  if [[ "$quick" == "1" && "$repro" == "1" ]]; then
    echo "error: --quick and --repro are mutually exclusive (a reproducibility check must be a full campaign)" >&2
    return 1
  fi

  if [[ "$quick" == "1" ]]; then
    # Disposable pipeline-validation dir; overwriting previous quick runs is fine.
    echo "$repo_dir/results/$exp-quick"
    return 0
  fi

  if [[ "$repro" == "1" ]]; then
    local d n=2
    d="$repo_dir/results/$exp-repro-$(date +%Y-%m-%d)"
    while compgen -G "$d/*.zip" >/dev/null; do
      d="$repo_dir/results/$exp-repro-$(date +%Y-%m-%d)-run$n"
      n=$((n + 1))
    done
    echo "$d"
    return 0
  fi

  if compgen -G "$frozen/*.zip" >/dev/null; then
    echo "error: $frozen already holds a campaign's archives — refusing to overwrite in place." >&2
    echo "  - reproducibility check: rerun with --repro (writes results/$exp-repro-$(date +%Y-%m-%d)/)" >&2
    echo "  - intentional supersede: move the frozen dir aside first, so the superseded archives keep their provenance" >&2
    return 1
  fi
  echo "$frozen"
}
