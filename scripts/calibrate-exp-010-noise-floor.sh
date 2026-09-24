#!/usr/bin/env bash
# calibrate-exp-010-noise-floor.sh — characterizes session-to-session
# measurement noise with zero experimental stimulus, before spending more
# engineering effort chasing a specific data point as a "real" effect.
#
# Not a hypothesis test. Runs adas-probe ALONE (no infotainment-load, no
# HTB contention at all) repeatedly, with a full vxedge up -> probe ->
# vxedge down cycle between every repetition — the same cold-start
# conditions the real campaign uses — purely to answer: how much does p99
# move session to session with nothing intentionally varied? That's the
# floor any specific load-level's deviation needs to clear before it's
# worth calling a real effect rather than noise (docs/RESULTS.md, "H2's
# real campaign" entry — the 250mbit point in the qos-fix rerun stood out
# against a background this script did not yet exist to characterize).
#
# Run as your normal user (NOT under sudo), same reasons as run-exp-010.sh.
#   ./scripts/calibrate-exp-010-noise-floor.sh [--reps N]
set -euo pipefail

REPS=15
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reps) REPS="$2"; shift 2 ;;
    *) echo "error: unknown argument '$1' (supported: --reps N)" >&2; exit 1 ;;
  esac
done

if [[ $(id -u) -eq 0 ]]; then
  echo "error: do not run this script itself under sudo/as root (see run-exp-010.sh's own header comment for why)" >&2
  exit 1
fi

sudo -v

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(dirname "$REPO_DIR")"
source "$REPO_DIR/scripts/lib/host_pinning.sh"
pin_cpu_governor_performance
reserve_measurement_cores

VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/release/vxprobe"
VXTRAFFIC="$WS/vxagents/target/release/vxtraffic"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTRAFFIC"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build (--release for vxagents) each repo first" >&2; exit 1; }
done

source "$REPO_DIR/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxagents" "$VXTRAFFIC" "$WS/vxagents/crates/vxtraffic"

CANONICAL_MANIFEST="$REPO_DIR/experiments/retired-6.1/exp-010.yaml"
RESULTS="$REPO_DIR/results/exp-010-noise-floor-$(date +%Y-%m-%d)"
mkdir -p "$RESULTS"
RUNTIME=$(mktemp -d /tmp/exp-010-noisefloor.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"
PROBE_S=60
WARMUP_S=10

PROBE_MANIFEST="$RUNTIME/exp-010-calibration.yaml"
sed -e "s/duration_s: 60/duration_s: $PROBE_S/" "$CANONICAL_MANIFEST" > "$PROBE_MANIFEST"

cleanup() {
  set +e
  "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$PROBE_MANIFEST" >/dev/null 2>&1
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$PROBE_MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  restore_cpu_governors
}
trap cleanup EXIT

echo "== noise-floor calibration: $REPS reps, adas-probe alone, full vxedge up/down between each =="
echo "== NOT a hypothesis test — characterizes session-to-session variance only =="

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" \
  --vxprobe-bin "$VXPROBE" --vxtraffic-bin "$VXTRAFFIC" \
  &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
for i in $(seq 1 30); do [[ -S "$SOCK" ]] && break; sleep 0.5; done
[[ -S "$SOCK" ]] || { echo "error: vxedged never started" >&2; cat "$RUNTIME/vxedged.log" >&2; exit 1; }
pin_if_alive "$DAEMON_PID"

for rep in $(seq 1 "$REPS"); do
  echo "-- rep$rep: vxedge up"
  "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$PROBE_MANIFEST"

  echo "   warmup ${WARMUP_S}s (idle — no load profile at all)"
  sleep "$WARMUP_S"

  echo "   starting adas-probe (1000pps, ${PROBE_S}s)"
  "$VXEDGE" --endpoint "unix://$SOCK" traffic up --manifest "$PROBE_MANIFEST" --profile adas-probe
  pin_if_alive "$(cat "$RUNTIME/traffic-adas-probe-send.pid" 2>/dev/null || true)"

  echo "   waiting ${PROBE_S}s"
  sleep "$((PROBE_S + 3))"

  cp "$RUNTIME/traffic-adas-probe-send.log" "$RESULTS/rep${rep}.json"
  p99=$(jq -r '.rtt_us.p99 // "?"' "$RESULTS/rep${rep}.json" 2>/dev/null || echo '?')
  echo "   rep$rep p99=${p99}us"

  "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$PROBE_MANIFEST" >/dev/null
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$PROBE_MANIFEST" >/dev/null
done

echo "== calibration complete: $REPS runs in $RESULTS =="
echo "== analyze: python3 notebooks/analyze_noise_floor.py $RESULTS =="
