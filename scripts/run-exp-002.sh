#!/usr/bin/env bash
# exp-002 campaign runner — packaging backend vs latency (H3).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-002.sh [--quick|--repro]
#
# --repro: full campaign written to results/exp-002-repro-<date>/ — the frozen
#          results/exp-002/ dir is never overwritten in place (lib/results_dir.sh).
#
# --quick: 1 repetition, short windows — pipeline/backend validation only
#          (also the first privileged exercise of the microvm/libvirt backends).
# default: 5 repetitions x 3 arms, 60 s x 1000 pps per measurement.
#
# Isolation contract (methodology fix, 2026-07-13 — retrofit of the exp-002b
# fix, see that runner's header): exactly ONE arm's zone is up at a time.
# exp-002's original manifest grouped all three packaging backends under one
# zone, so `zone up` always started all three concurrently even though only
# one was being measured — the same class of unpinned-concurrent-guest CPU
# contention that invalidated exp-002b's first campaign. exp-002's own frozen
# result happened to show zero loss, but that was luck, not a property of the
# design. exp-002.yaml now declares one zone per arm (z-cont/z-microvm/z-libvirt)
# so each arm can be brought up and torn down independently.
set -euo pipefail

QUICK=0; REPRO=0
for arg in "$@"; do case "$arg" in
  --quick) QUICK=1 ;;
  --repro) REPRO=1 ;;
  *) echo "error: unknown argument '$arg' (supported: --quick, --repro)" >&2; exit 1 ;;
esac; done

if [[ $(id -u) -ne 0 ]]; then
  echo "error: needs root (CAP_NET_ADMIN) — sudo -E env \"PATH=\$PATH\" $0" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(dirname "$REPO_DIR")"
VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/debug/vxprobe"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
BUNDLE="$WS/vxzones/images/linux-probe/bundle"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build each repo first" >&2; exit 1; }
done
[[ -f "$BUNDLE/vmlinuz" && -f "$BUNDLE/initrd.img" && -f "$BUNDLE/meta.json" ]] || {
  echo "error: bundle incomplete (need vmlinuz, initrd.img, meta.json) — vxzones/scripts/build-guest-bundle.sh" >&2
  exit 1
}

source "$REPO_DIR/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

# Everything below runs from the §6.0 workspace: §6.1 manifests stopped being a
# provisioning input on 2026-07-31, and `vxedge up`/`vxtelemetry` both read the
# workspace directory directly. The frozen `../experiments/exp-*.yaml` files are kept as
# provenance for the results already recorded against them, not as inputs.
MANIFEST="$REPO_DIR/experiments/exp-002-ws"
source "$REPO_DIR/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-002 "$QUICK" "$REPRO")"
RUNTIME=$(mktemp -d /tmp/exp-002.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

ARMS=(container microvm libvirt)
declare -A ARM_ADDR=( [container]=10.101.0.11 [microvm]=10.101.0.12 [libvirt]=10.101.0.13 )
# One arm up at a time, addressed by device id. `zone up --vxid` takes a zone
# (a region) or a single device; the three arms are three packagings of one
# region, so the device id is what selects exactly one of them.
declare -A DEVICE_OF=( [container]=node-cont-01 [microvm]=node-microvm-01 [libvirt]=node-libvirt-01 )

# WARM_S=10 meets the experiment-methodology skill's minimum
# (max(10% of PROBE_S, 10s) = 10s at PROBE_S=60); bumped from 5 (matches the
# exp-002b/exp-003 fix — see those runners for the same change).
if [[ $QUICK -eq 1 ]]; then
  REPS=1; WARM_S=2; PROBE_S=10; PROBE_PPS=500; PROBE_TIMEOUT_MS=1000
else
  REPS=5; WARM_S=10; PROBE_S=60; PROBE_PPS=1000; PROBE_TIMEOUT_MS=1000
fi

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  [[ -n "${TEL_PID:-}" ]] && kill "$TEL_PID" 2>/dev/null
  for z in "${DEVICE_OF[@]:-}"; do
    "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$z" >/dev/null 2>&1
  done
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=arm $2=rep
  cat <<EOF
{
  "experiment": "exp-002", "hypothesis": "H3",
  "arm": "$1", "repetition": $2,
  "warmup_s": $WARM_S, "probe_window_s": $PROBE_S, "probe_pps": $PROBE_PPS,
  "probe_timeout_ms": $PROBE_TIMEOUT_MS,
  "quick_profile": $QUICK,
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "kvm": $([[ -e /dev/kvm ]] && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "cpu_pinning": "none",
  "tool_versions": {
    "vxedge": "$(git -C "$WS/vxedge" rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "vxagents": "$(git -C "$WS/vxagents" rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "vxtelemetry": "$(git -C "$WS/vxtelemetry" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  },
  "loadavg_at_start": "$(cut -d' ' -f1-3 /proc/loadavg)",
  "timestamping": "userspace-monotonic (SO_TIMESTAMPING follow-up open)",
  "isolation": "single-arm",
  "bundle_meta": $(cat "$BUNDLE/meta.json")
}
EOF
}

wait_reflector() { # $1=addr — poll until the reflector answers (VM boot etc.)
  for _ in $(seq 1 30); do
    if "$VXPROBE" send --target "$1:9800" --pps 10 --duration-s 1 --timeout-ms 300 \
         2>/dev/null | grep -q '"received": *[1-9]'; then
      return 0
    fi
    sleep 1
  done
  echo "error: reflector at $1:9800 never answered" >&2
  return 1
}

start_arm() {
  local arm="$1"
  "$VXEDGE" --endpoint "unix://$SOCK" zone up --vxid "${DEVICE_OF[$arm]}" >/dev/null
  if [[ "$arm" == "container" ]]; then
    ip netns exec vx-node-cont-01 "$VXPROBE" reflect --listen 0.0.0.0:9800 &>/dev/null &
    PIDS+=($!)
  fi
}

stop_arm() {
  local arm="$1"
  if [[ "$arm" == "container" ]]; then
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    PIDS=()
  fi
  "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "${DEVICE_OF[$arm]}" >/dev/null
  sleep 1  # let the port fully release before the next arm claims it
}

echo "== exp-002: reps=$REPS arms=(${ARMS[*]}) window=${PROBE_S}s pps=$PROBE_PPS [isolated: one arm at a time]"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1

for rep in $(seq 1 "$REPS"); do
  echo "-- rep $rep: gateway up"
  "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$MANIFEST" >/dev/null
  ip link add link vxup0p name vxup0p.101 type vlan id 101
  ip addr add 10.101.0.1/24 dev vxup0p.101
  ip link set vxup0p up && ip link set vxup0p.101 up

  for arm in "${ARMS[@]}"; do
    addr="${ARM_ADDR[$arm]}"
    tag="rep${rep}-${arm}"
    echo "   $tag: starting (isolated)"
    start_arm "$arm"
    echo "   $tag: waiting for reflector at $addr"
    wait_reflector "$addr"
    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$arm" "$rep" > "$INGEST/run-env.json"
    sleep "$WARM_S"

    "$VXTELEMETRY" ingest --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & TEL_PID=$!
    echo "   $tag: probing ${PROBE_S}s @ ${PROBE_PPS}pps"
    # A zero-received measurement makes vxprobe exit 1 by design (it's a
    # failed measurement, not a script error) — guard so one bad rep doesn't
    # abort the whole campaign under set -e; the analyzer's loss-anomaly
    # check already flags/refuses on exactly this condition downstream.
    if ! "$VXPROBE" send --target "$addr:9800" --pps "$PROBE_PPS" \
      --duration-s "$PROBE_S" --timeout-ms "$PROBE_TIMEOUT_MS" --metrics 127.0.0.1:9801 \
      2>/dev/null > "$INGEST/probe-summary.json"; then
      echo "   $tag: WARNING vxprobe reported zero received probes — measurement failed" >&2
    fi
    wait "$TEL_PID" || echo "   $tag: WARNING vxtelemetry ingest exited non-zero — archive may be incomplete" >&2

    "$VXTELEMETRY" collect --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   $tag: archived ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"
    stop_arm "$arm"
  done

  ip link del vxup0p.101 2>/dev/null || true
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi
echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp002.py $RESULTS"
