#!/usr/bin/env bash
# exp-001 campaign runner — ADAS slice isolation under infotainment load (H1).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-001.sh [--quick|--repro]
#
# Provisions from the §6.0 workspace (experiments/exp-001-ws). The frozen results in
# results/exp-001/ were produced from the §6.1 manifest and stay authoritative until a
# campaign from the workspace reproduces them — that comparison is the point of --repro.
#
# --repro: full campaign written to results/exp-001-repro-<date>/ — the frozen
#          results/exp-001/ dir is never overwritten in place (lib/results_dir.sh).
#
# --quick: 1 repetition x 2 load levels, short windows — pipeline validation
#          only; sample counts are below tail-percentile support and MUST NOT
#          be reported as results (experiment-methodology skill).
# default: 5 repetitions x 5 load levels, 10 s warmup + 60 s measured probe
#          window per point (1000 pps => 60k samples: p99 well-supported).
#
# Topology per run: vxedge up provisions vxbr0 + shaped trunk (vxup0) + one
# endpoint per node (node-adas-probe-01 on vlan101, node-infot-load-01 on
# vlan103). This script adds experiment IPs:
#   vzp-node-a-c06a 10.101.0.2/24  <-- adas probe source (node-adas-probe-01)
#   vzp-node-i-2921 10.103.0.2/24  <-- infotainment load source (node-infot-load-01)
#   vxup0p.101 10.101.0.1/24  <-- vxprobe reflector (across the bottleneck)
#   vxup0p.103 10.103.0.1/24  <-- load sink address (fire-and-forget)
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
VXPROBE="$WS/vxagents/target/debug/vxprobe"
VXTRAFFIC="$WS/vxagents/target/debug/vxtraffic"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTRAFFIC" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build each repo first" >&2; exit 1; }
done

# Staleness gate: any source file a binary actually depends on (per-crate,
# not whole-repo — see scripts/lib/freshness.sh) newer than the binary means
# someone edited code without rebuilding — refuse rather than measure with
# stale code.
source "$REPO_DIR/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxagents" "$VXTRAFFIC" "$WS/vxagents/crates/vxtraffic"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

# The migration equivalence question this campaign answers: the workspace and the frozen §6.1
# manifest are already known to produce an identical GatewayPlan, and everything downstream of
# provisioning is held byte-identical — same host-side veth-peer addressing, same
# vxprobe/vxtraffic invocations, same sweep — so a rerun tests whether the *numbers* agree too.
#
# `experiment up --stage gateway`, not the full `up`: staging the zones would move the veth
# peers into node netns and change the measurement path. Running the agents inside the zones is
# more faithful and is the direction of travel (TASKS.md), but it is a different measurement and
# needs its own baseline — mixing it into an equivalence check would confound the two. Staging
# is what makes that choice expressible to the daemon rather than a reason to bypass it.
# Everything below runs from the §6.0 workspace: §6.1 manifests stopped being a
# provisioning input on 2026-07-31, and `vxedge up`/`vxtelemetry` both read the
# workspace directory directly. The frozen `../experiments/exp-*.yaml` files are kept as
# provenance for the results already recorded against them, not as inputs.
# Provisioning is the daemon's: `experiment up` runs the stages in dependency order and
# `experiment down` reverses them. What stays in this script is *method* — repetitions, warmup,
# measurement window, collection. Before 2026-08-01 each runner re-implemented the sequence in
# bash, and they drifted: governor pinning was missing from four of five, and exp-001 lost its
# results-dir line to an edit that nothing caught until it ran.
MANIFEST="$REPO_DIR/experiments/exp-001-ws"
source "$REPO_DIR/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-001 "$QUICK" "$REPRO")"
# The cpu governor is *pinned*, not merely recorded. Every campaign before 2026-07-31 only
# wrote `cpu_governor` into results metadata and left whatever the host happened to be on —
# which is how exp-001's first workspace-path rerun came out ~10-20us higher at every load
# point than the frozen campaign: that host had moved from `performance` to `powersave`, and
# nothing in the script noticed. exp-010 already pinned it (scripts/lib/host_pinning.sh);
# this is the same call, so a rerun is comparable to the campaign it is being compared with.
source "$REPO_DIR/scripts/lib/host_pinning.sh"
pin_cpu_governor_performance

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
  restore_cpu_governors
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null 2>&1
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
    # `--stage gateway` on purpose: this campaign measures on the host-side veth peers, so
    # starting the zones would move them into node netns and change the measurement path.
    "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment up --stage gateway >/dev/null

    # Experiment IP wiring (fresh each cycle; interfaces are recreated by up).
    ip addr replace 10.101.0.2/24 dev vzp-node-a-c06a && ip link set vzp-node-a-c06a up
    ip addr replace 10.103.0.2/24 dev vzp-node-i-2921 && ip link set vzp-node-i-2921 up
    ip link add link vxup0p name vxup0p.101 type vlan id 101
    ip link add link vxup0p name vxup0p.103 type vlan id 103
    ip addr replace 10.101.0.1/24 dev vxup0p.101 && ip link set vxup0p.101 up
    ip addr replace 10.103.0.1/24 dev vxup0p.103 && ip link set vxup0p.103 up
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

    "$VXTELEMETRY" ingest --workspace "$MANIFEST" --ingest-dir "$INGEST" \
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

    "$VXTELEMETRY" collect --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   archived $RESULTS/$tag.zip ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"

    ip link del vxup0p.101 2>/dev/null || true
    ip link del vxup0p.103 2>/dev/null || true
    "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null
  done
done

# Hand the results back to the invoking user (analysis runs unprivileged).
if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi

echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp001.py $RESULTS"
