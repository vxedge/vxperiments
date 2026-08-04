#!/usr/bin/env bash
# check-runners.sh — static checks for the campaign runners, runnable locally and in CI.
#
# Why this exists: `bash -n` is a *syntax* check and cannot see an unbound variable. On
# 2026-07-31 an edit to run-exp-001.sh removed the two lines that resolve `$RESULTS`; the script
# passed `bash -n`, was committed, and died at `RESULTS: unbound variable` on the first real run
# — after the operator had already typed a sudo password and waited for a build.
#
# Two checks, both of which would have caught it:
#
#   1. shellcheck including SC2154 (referenced but never assigned), which is off by default at
#      the `warning` severity most projects use.
#   2. Executing each runner's *preamble* — everything up to the daemon launch — under `set -u`
#      with the privileged and freshness-checking parts stubbed, then asserting the variables a
#      campaign cannot run without actually resolved.
#
# The second is the stronger one: it runs the real script, so it catches a variable that is
# assigned in a branch that never executes, which shellcheck cannot know about.
#
# A preamble probe that reaches a runner's own `error: missing $bin — cargo build first`
# (or similar) is not a failure of this check: it means every variable read up to that point
# resolved cleanly under `set -u`, and this job's own contract (`ci.yml`'s `runners` job) is
# "everything checkable without the vxedge binaries" — a fresh checkout has neither those nor
# the other built artifacts some runners also gate on. Only bash's own "unbound variable" (a
# raw `set -u` violation) or anything unrecognized counts as a real failure — found live
# 2026-08-04 when this distinction didn't exist yet and every runner FAILED in CI for
# something no CI checkout can ever have.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR" || exit 1
fail=0

echo "== shellcheck (with SC2154) =="
if command -v shellcheck >/dev/null; then
  # SC1091: sourced libs are resolved at runtime, not by the linter.
  # SC2034: an unused loop variable in a wait loop is not worth failing a campaign over.
  shellcheck -S warning -e SC1091 -e SC2034 -i SC2154 scripts/*.sh scripts/lib/*.sh || fail=1
  shellcheck -S warning -e SC1091 -e SC2034 scripts/*.sh scripts/lib/*.sh || fail=1
else
  echo "  shellcheck not installed — skipping (CI installs it)"
fi

echo "== runner preambles resolve their variables =="
# Repo-level runners and sandboxed ones (experiments/<id>-ws/scripts/run.sh). A sandbox's
# runner resolves its own location, so the probe is written *beside* it — writing it elsewhere
# would test a script that thinks it lives somewhere it does not, which is how the first
# version of this check reported a false failure on the first converted sandbox.
for f in scripts/run-exp-*.sh experiments/*/scripts/run.sh; do
  [[ -f "$f" ]] || continue
  case "$f" in
    experiments/*) name="$(basename "$(dirname "$(dirname "$f")")")" ;;
    *) name="$(basename "$f" .sh)" ;;
  esac
  # Cut at the daemon launch: everything before it is setup, everything after needs a daemon.
  cut="$(grep -n '"\$VXEDGED" --listen' "$f" | head -1 | cut -d: -f1)"
  if [[ -z "$cut" ]]; then
    printf '  %-16s no daemon launch found — cannot check\n' "$name"
    continue
  fi

  probe="$(dirname "$f")/.check-preamble.sh"
  {
    # Stubs, so the preamble runs unprivileged and without built binaries. Each replaces a
    # *precondition*, never a variable the script is supposed to compute — the point is to
    # check the script's own arithmetic, not to supply it.
    #
    # `id` is stubbed only for the runners that *require* root. run-exp-010 refuses to be run
    # as root (it caches a sudo credential instead), so pretending to be root there would test
    # the opposite of what it does.
    if ! grep -q 'do not run this script itself under sudo' "$f"; then
      echo 'id() { echo 0; }'
    fi
    echo 'sudo() { :; }'
    echo 'tee() { cat >/dev/null; }'
    # The freshness library re-defines check_fresh_bin, so the source line is replaced rather
    # than the function stubbed — a stub defined before the source would simply be overwritten,
    # which is how the first version of this check reported five false failures.
    head -n "$((cut - 1))" "$f" \
      | grep -v '^set -euo' \
      | sed 's|^source .*freshness\.sh"$|check_fresh_bin() { :; }|'
    echo 'set -u'
    # The two a campaign cannot run without: where results go, and what it provisions from.
    echo 'echo "RESULTS=${RESULTS:?unset} INPUT=${MANIFEST:-${CANONICAL_WS:?neither MANIFEST nor CANONICAL_WS set}}"'
  } > "$probe"

  out="$(bash "$probe" --quick 2>&1)"
  rm -f "$probe"
  if grep -q '^RESULTS=' <<<"$out"; then
    printf '  %-16s ok  %s\n' "$name" "$(grep -o 'RESULTS=.*' <<<"$out" | head -1)"
  elif grep -qE ': line [0-9]+: [A-Za-z_][A-Za-z0-9_]*: unbound variable' <<<"$out"; then
    # The exact bug class this check exists to catch (see the file header) — bash's own
    # message for a `set -u` violation, distinct from any of the runner's own `error: ...`
    # precondition messages below.
    printf '  %-16s FAILED\n%s\n' "$name" "$out"
    fail=1
  elif grep -q '^error: ' <<<"$out"; then
    # A controlled exit from one of the runner's own precondition gates (missing binary,
    # missing guest bundle, etc.) — every runner's is `echo "error: ..." >&2; exit 1`, never
    # a bare `exit`. If any variable read before this point were unbound, `set -u` would have
    # crashed first with its own "unbound variable" message instead, caught above — so
    # reaching a *named* precondition failure means everything up to it resolved cleanly.
    # This is expected, not a bug: this job's own contract (`ci.yml`'s `runners` job) is
    # "everything checkable without the vxedge binaries," and a fresh checkout has neither
    # the binaries nor the built artifacts (guest bundles, etc.) some runners also need.
    printf '  %-16s ok  (stopped at a real precondition this job does not build: %s)\n' \
      "$name" "$(grep -o 'error:.*' <<<"$out" | head -1)"
  else
    printf '  %-16s FAILED\n%s\n' "$name" "$out"
    fail=1
  fi
done

# Each sandbox vendors scripts/lib/*.sh so it is zip-portable — the owner decision of
# 2026-08-01, with the host concerns moving into vxedge core/API later. Vendoring means five
# copies, and five copies drift: that is exactly how four of five runners ended up without
# governor pinning. scripts/lib/ stays the canonical copy and this asserts the vendored ones
# are byte-identical to it, so drift is a failed check rather than a campaign that quietly
# measured under a different governor.
echo "== vendored libs match the canonical copy =="
for vendored in experiments/*/scripts/lib/*.sh; do
  [[ -f "$vendored" ]] || continue
  canonical="scripts/lib/$(basename "$vendored")"
  if [[ ! -f "$canonical" ]]; then
    printf '  %-46s no canonical copy at %s\n' "$vendored" "$canonical"
    fail=1
  elif cmp -s "$vendored" "$canonical"; then
    printf '  %-46s ok\n' "$vendored"
  else
    printf '  %-46s DRIFTED from %s\n' "$vendored" "$canonical"
    diff -u "$canonical" "$vendored" | head -20
    fail=1
  fi
done

echo "== analysis notebooks compile =="
for nb in notebooks/*.py; do
  if python3 -m py_compile "$nb" 2>/dev/null; then
    printf '  %-28s ok\n' "$(basename "$nb")"
  else
    printf '  %-28s FAILED\n' "$(basename "$nb")"
    python3 -m py_compile "$nb"
    fail=1
  fi
done
find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true

exit "$fail"
