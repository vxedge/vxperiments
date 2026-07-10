#!/usr/bin/env bash
# exp-001 campaign runner — ADAS slice isolation under infotainment load (H1).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-001.sh [--quick]
#
# --quick: 1 repetition x 2 load levels, short windows — pipeline validation
#          only; sample counts are below tail-percentile support and MUST NOT
#          be reported as results (experiment-methodology skill).
# default: 5 repetitions x 5 load levels, 10 s warmup + 60 s measured probe
#          window per point (1000 pps => 60k samples: p99 well-supported).
#
# Topology per run: vxedge up provisions vxbr0 + shaped trunk (vxup0) +
# endpoints vz0(vlan101)/vz1(vlan103). This script adds experiment IPs:
#   vzp0 10.101.0.2/24  <-- adas probe source
#   vzp1 10.103.0.2/24  <-- infotainment load source
#   vxup0p.101 10.101.0.1/24  <-- vxprobe reflector (across the bottleneck)
#   vxup0p.103 10.103.0.1/24  <-- load sink address (fire-and-forget)
set -euo pipefail

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

if [[ $(id -u) -ne 0 ]]; then
  echo "error: needs root (CAP_NET_ADMIN) — sudo -E env \"PATH=\$PATH\" $0" >&2
  exit 1
fi

# --- locations (meta-workspace layout: repos side by side) -------------------
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(dirname "$REPO_DIR")"
VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/debug/vxprobe"
VXTRAFFIC="$WS/vxagents/target/debug/vxtraffic"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTRAFFIC" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build each repo first" >&2; exit 1; }
done

# Staleness gate: a binary older than its repo's latest commit means someone
# forgot to rebuild — refuse rather than measure with stale code.
check_fresh() { # $1=repo dir, $2=binary
  local head_ts bin_ts
  head_ts=$(git -C "$1" log -1 --format=%ct 2>/dev/null || echo 0)
  bin_ts=$(stat -c %Y "$2")
  if (( bin_ts < head_ts )); then
    echo "error: $2 is older than the latest commit in $1 — rebuild (as your user, not root):" >&2
    echo "       cd $1 && cargo build --workspace" >&2
    exit 1
  fi
}
check_fresh "$WS/vxedge" "$VXEDGED"
check_fresh "$WS/vxedge" "$VXEDGE"
check_fresh "$WS/vxagents" "$VXPROBE"
check_fresh "$WS/vxagents" "$VXTRAFFIC"
check_fresh "$WS/vxtelemetry" "$VXTELEMETRY"

MANIFEST="$REPO_DIR/experiments/exp-001.yaml"
RESULTS="$REPO_DIR/results/exp-001"
RUNTIME=$(mktemp -d /tmp/exp-001.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

# --- campaign profile ---------------------------------------------------------
if [[ $QUICK -eq 1 ]]; then
  REPS=1; LOADS_MBPS=(0 400); WARMUP_S=3; PROBE_S=12; PROBE_PPS=500
else
  REPS=5; LOADS_MBPS=(0 100 250 400 600); WARMUP_S=10; PROBE_S=60; PROBE_PPS=1000
fi

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null; ip link del vxup0p.103 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=load $2=rep -> json on stdout
  cat <<EOF
{
  "experiment": "exp-001", "hypothesis": "H1",
  "load_mbps": $1, "repetition": $2,
  "warmup_s": $WARMUP_S, "probe_window_s": $PROBE_S, "probe_pps": $PROBE_PPS,
  "quick_profile": $QUICK,
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "loadavg_at_start": "$(cut -d' ' -f1-3 /proc/loadavg)",
  "timestamping": "userspace-monotonic (SO_TIMESTAMPING follow-up open)",
  "tool_versions": {
    "vxedge": "$($VXEDGE --version | awk '{print $2}')",
    "vxprobe": "$($VXPROBE --version | awk '{print $2}')",
    "vxtraffic": "$($VXTRAFFIC --version | awk '{print $2}')",
    "vxtelemetry": "$($VXTELEMETRY --version | awk '{print $2}')"
  }
}
EOF
}

echo "== exp-001 campaign: reps=$REPS loads=(${LOADS_MBPS[*]}) warmup=${WARMUP_S}s window=${PROBE_S}s pps=$PROBE_PPS"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1

for rep in $(seq 1 "$REPS"); do
  for load in "${LOADS_MBPS[@]}"; do
    tag="rep${rep}-load${load}"
    echo "-- $tag: gateway up"
    "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$MANIFEST" >/dev/null

    # Experiment IP wiring (fresh each cycle; interfaces are recreated by up).
    ip addr add 10.101.0.2/24 dev vzp0 && ip link set vzp0 up
    ip addr add 10.103.0.2/24 dev vzp1 && ip link set vzp1 up
    ip link add link vxup0p name vxup0p.101 type vlan id 101
    ip link add link vxup0p name vxup0p.103 type vlan id 103
    ip addr add 10.101.0.1/24 dev vxup0p.101 && ip link set vxup0p.101 up
    ip addr add 10.103.0.1/24 dev vxup0p.103 && ip link set vxup0p.103 up
    ip link set vxup0p up

    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$load" "$rep" > "$INGEST/run-env.json"

    "$VXPROBE" reflect --listen 10.101.0.1:9800 &>/dev/null & PIDS+=($!)
    sleep 0.5

    if [[ "$load" -gt 0 ]]; then
      "$VXTRAFFIC" --target 10.103.0.1:9900 --bandwidth-mbps "$load" \
        --duration-s $((WARMUP_S + PROBE_S + 4)) > "$INGEST/traffic-summary.json" & PIDS+=($!)
      TRAFFIC_PID=$!
    fi
    echo "   warmup ${WARMUP_S}s under load=${load}mbit"
    sleep "$WARMUP_S"

    "$VXTELEMETRY" ingest --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & PIDS+=($!)
    TEL_PID=$!

    echo "   probing ${PROBE_S}s @ ${PROBE_PPS}pps on adas slice"
    "$VXPROBE" send --target 10.101.0.1:9800 --pps "$PROBE_PPS" \
      --duration-s "$PROBE_S" --metrics 127.0.0.1:9801 \
      > "$INGEST/probe-summary.json"

    wait "$TEL_PID" 2>/dev/null || true
    [[ "$load" -gt 0 ]] && wait "$TRAFFIC_PID" 2>/dev/null || true
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    PIDS=()

    "$VXTELEMETRY" collect --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   archived $RESULTS/$tag.zip ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"

    ip link del vxup0p.101 2>/dev/null || true
    ip link del vxup0p.103 2>/dev/null || true
    "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null
  done
done

echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp001.py $RESULTS"
