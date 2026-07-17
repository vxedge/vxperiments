#!/usr/bin/env bash
# exp-010 campaign runner — H2 real S-NSSAI slicing, snssai arm (vlan arm =
# exp-001's own frozen numbers, per the model's own doc comment — no
# same-day rerun needed).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-010.sh [--quick|--repro]
#
# --repro/--quick: same meaning as run-exp-001.sh (lib/results_dir.sh).
# default: 5 repetitions x 5 load levels, 10s warmup + 60s measured probe
#          window per point (1000 pps => 60k samples: p99 well-supported) —
#          identical campaign frame to exp-001, per the sysml model.
#
# Unlike run-exp-001.sh, this script does NOT hand-assemble any network
# config (no raw `ip addr`/`ip link add ... type vlan`) — the engineering
# bar this campaign was explicitly built to: `vxedge up` provisions the
# real 5G core + UE pods, `vxedge traffic up --profile <id>` drives real
# `vxprobe`/`vxtraffic` processes against the UE's live PDU-session address
# (crates/vxedge-core/src/traffic/, live-verified end to end 2026-07-17,
# docs/STATUS.md "TrafficService live end to end").
#
# Two real constraints this script works around, not hacks:
#  1. TrafficUpRequest has no per-call rate/duration override — `bandwidth_mbps`
#     and `duration_s` come from the manifest itself (`experiment.duration_s`,
#     wired 2026-07-17 specifically for this campaign — previously silently
#     fell back to vxprobe/vxtraffic's own 10s CLI default, which would have
#     under-sampled tail percentiles). So the load sweep and the two-phase
#     warmup/probe timing are both done via small manifest variants generated
#     into $RUNTIME, not CLI flags — still fully manifest-driven, just two
#     manifests instead of one for the two different phase durations needed
#     (`infotainment-load` must outlive the probe's own shorter window so it's
#     still driving load throughout, exactly like exp-001's own
#     WARMUP_S+PROBE_S+4 duration on vxtraffic vs PROBE_S on vxprobe). Every
#     archive's bundled manifest.yaml is still the canonical, unmodified
#     experiment-defining exp-010.yaml (its sha256 stays constant across every
#     rep/load, matching exp-001's own archive convention) — the swept load
#     and phase durations live only in run-env.json's per-point metadata,
#     same place exp-001 already records its own load value.
#  2. TrafficService's spawned `vxprobe send` doesn't expose `--metrics`
#     (live Prometheus) — only its final aggregate JSON is captured. Recorded
#     honestly in run-env.json rather than faking parity with exp-001's live
#     telemetry scrape; the analysis (notebooks/analyze_exp010.py) only reads
#     the aggregate JSON same as analyze_exp001.py does.
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

# --- locations (meta-workspace layout: repos side by side) -------------------
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(dirname "$REPO_DIR")"
VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/release/vxprobe"
VXTRAFFIC="$WS/vxagents/target/release/vxtraffic"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTRAFFIC" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build (--release for vxagents) each repo first" >&2; exit 1; }
done

source "$REPO_DIR/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxagents" "$VXTRAFFIC" "$WS/vxagents/crates/vxtraffic"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

CANONICAL_MANIFEST="$REPO_DIR/experiments/exp-010.yaml"
source "$REPO_DIR/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-010 "$QUICK" "$REPRO")"
RUNTIME=$(mktemp -d /tmp/exp-010.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

# --- campaign profile ---------------------------------------------------------
if [[ $QUICK -eq 1 ]]; then
  REPS=1; LOADS_MBPS=(0 400); WARMUP_S=3; PROBE_S=12
else
  REPS=5; LOADS_MBPS=(0 100 250 400 600); WARMUP_S=10; PROBE_S=60
fi

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$CANONICAL_MANIFEST" >/dev/null 2>&1
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$CANONICAL_MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=load $2=rep -> json on stdout
  cat <<EOF
{
  "experiment": "exp-010", "hypothesis": "H2", "slice_mode": "snssai",
  "load_mbps": $1, "repetition": $2,
  "warmup_s": $WARMUP_S, "probe_window_s": $PROBE_S,
  "load_phase_duration_s": $((WARMUP_S + PROBE_S + 4)),
  "probe_pps": 1000, "quick_profile": $QUICK,
  "prometheus_live_metrics": false,
  "prometheus_live_metrics_note": "TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)",
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

echo "== exp-010 campaign (snssai arm): reps=$REPS loads=(${LOADS_MBPS[*]}) warmup=${WARMUP_S}s window=${PROBE_S}s pps=1000"
echo "== vlan-arm baseline: exp-001's own frozen results (results/exp-001/) — not rerun here"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" \
  --vxprobe-bin "$VXPROBE" --vxtraffic-bin "$VXTRAFFIC" \
  &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
for i in $(seq 1 30); do [[ -S "$SOCK" ]] && break; sleep 0.5; done
[[ -S "$SOCK" ]] || { echo "error: vxedged never started" >&2; cat "$RUNTIME/vxedged.log" >&2; exit 1; }

for rep in $(seq 1 "$REPS"); do
  for load in "${LOADS_MBPS[@]}"; do
    tag="rep${rep}-load${load}"
    echo "-- $tag: vxedge up (gateway + real 5G core + both UE pods)"

    # Two manifest variants: same everything except experiment.duration_s
    # (and the swept bandwidth_mbps on the load variant) — see the header
    # comment for why TrafficUpRequest can't just take these as call params.
    LOAD_MANIFEST="$RUNTIME/exp-010-load-$tag.yaml"
    PROBE_MANIFEST="$RUNTIME/exp-010-probe-$tag.yaml"
    sed -e "s/bandwidth_mbps: 400 /bandwidth_mbps: $load /" \
        -e "s/duration_s: 60/duration_s: $((WARMUP_S + PROBE_S + 4))/" \
        "$CANONICAL_MANIFEST" > "$LOAD_MANIFEST"
    sed -e "s/duration_s: 60/duration_s: $PROBE_S/" \
        "$CANONICAL_MANIFEST" > "$PROBE_MANIFEST"

    "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$PROBE_MANIFEST"

    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$load" "$rep" > "$INGEST/run-env.json"

    if [[ "$load" -gt 0 ]]; then
      echo "   starting infotainment-load @ ${load}mbit (runs $((WARMUP_S + PROBE_S + 4))s)"
      "$VXEDGE" --endpoint "unix://$SOCK" traffic up --manifest "$LOAD_MANIFEST" \
        --profile infotainment-load
    fi
    echo "   warmup ${WARMUP_S}s under load=${load}mbit"
    sleep "$WARMUP_S"

    echo "   starting adas-probe (1000pps, ${PROBE_S}s — blocks until the UE's PDU session + reflector are confirmed ready)"
    "$VXEDGE" --endpoint "unix://$SOCK" traffic up --manifest "$PROBE_MANIFEST" \
      --profile adas-probe

    echo "   waiting ${PROBE_S}s for the probe window to finish"
    sleep "$((PROBE_S + 3))"

    cp "$RUNTIME/traffic-adas-probe-send.log" "$INGEST/probe-summary.json"
    if [[ "$load" -gt 0 ]]; then
      cp "$RUNTIME/traffic-infotainment-load-load.log" "$INGEST/traffic-summary.json"
    fi

    "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$PROBE_MANIFEST"
    "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$PROBE_MANIFEST"

    "$VXTELEMETRY" collect --manifest "$CANONICAL_MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    p99=$(jq -r '.rtt_us.p99 // "?"' "$INGEST/probe-summary.json" 2>/dev/null || echo '?')
    loss=$(jq -r '.loss_pct // "?"' "$INGEST/probe-summary.json" 2>/dev/null || echo '?')
    echo "   archived $RESULTS/$tag.zip (p99=${p99}us loss=${loss}%)"
  done
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi

echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp010.py $RESULTS --baseline results/exp-001"
