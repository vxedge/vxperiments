#!/usr/bin/env bash
# exp-005 campaign runner — cold-start / first-packet latency after zone boot.
#
# Run as root from the vxperiments repo root:
#   cd experiments/exp-005 && sudo -E env "PATH=$PATH" ./scripts/run.sh [--quick|--repro]
#
# One device, one slice, no offered load, no comparison arm: the only thing that varies across
# a repetition is elapsed time since `zone up` returned. Every repetition runs TWO probe calls
# back to back, on the same freshly-provisioned netns:
#
#   1. "cold" — fired the instant `zone up` returns, zero warmup (deliberately: the warmup IS
#      the measurement here), small (~60 samples at COLD_PPS over COLD_S) so a slow first
#      packet dominates its own `max`/`p50` instead of being averaged into invisibility the way
#      exp-001/002/003's much larger first-arm windows did (see `../../notebooks/cold_start.py`
#      for that history — this experiment exists to measure deliberately what those only
#      noticed by accident).
#   2. "steady" — immediately after, on the same now-ARP-resolved, now-stable netns: a full
#      STEADY_S / STEADY_PPS window with real tail-percentile support, this repetition's own
#      baseline. Comparing cold against steady from the SAME repetition (not a cross-repetition
#      or cross-day average) is what keeps the comparison free of host-state drift.
#
# Like exp-014, the device is genuinely zoned up (`zone up --vxid node-cold-probe-01`) and
# probed via `ip netns exec vx-node-cold-probe-01 ...` — prober in the device's own netns,
# reflector in the host's default netns, different FIB domains, no same-netns loopback shortcut
# for the kernel to take (docs/ROADMAP.md).
#
# --repro: full campaign written to results/exp-005-repro-<date>/ — a first successful campaign
#          becomes results/exp-005/ and is never overwritten in place (lib/results_dir.sh).
#
# --quick: 2 repetitions, short steady window — pipeline validation only; the cold phase's own
#          sample count is ALWAYS below tail-percentile support, quick or not (see above) — its
#          `p99` must never be reported regardless of profile.
# default: 20 repetitions x (cold burst + 60 s / 1000 pps steady window).
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

# This sandbox, and the meta-workspace it sits in. Resolved from this script's own location, so
# the experiment runs wherever it is unpacked.
SANDBOX="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$SANDBOX/../.." && pwd)"
WS="$(dirname "$REPO_DIR")"
VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/debug/vxprobe"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build each repo first" >&2; exit 1; }
done

source "$SANDBOX/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

# Provisioning is the daemon's: `experiment up --stage gateway` provisions the bridge and the
# one slice's VLAN/HTB; `zone up --vxid node-cold-probe-01` (below, per repetition) is the
# moment under test — it moves the access-port peer into the device's own netns and assigns the
# address vehicle.yaml declares on it. What stays in this script is method.
MANIFEST="$SANDBOX"
source "$SANDBOX/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-005 "$QUICK" "$REPRO")"
source "$SANDBOX/scripts/lib/host_pinning.sh"
pin_cpu_governor_performance
RUNTIME=$(mktemp -d /tmp/exp-005.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

DEVICE=node-cold-probe-01
DEVICE_ADDR=10.115.0.2
REFLECTOR_ADDR=10.115.0.1

# COLD_TIMEOUT_MS is deliberately generous: a slow first packet is exactly the phenomenon under
# study, and a timeout tight enough to count it as lost instead of slow would hide it.
if [[ $QUICK -eq 1 ]]; then
  REPS=2; STEADY_S=10; STEADY_PPS=500
else
  REPS=20; STEADY_S=60; STEADY_PPS=1000
fi
COLD_S=3; COLD_PPS=20; COLD_TIMEOUT_MS=2000
STEADY_TIMEOUT_MS=1000

cleanup() {
  set +e
  restore_cpu_governors
  [[ -n "${TEL_PID:-}" ]] && kill "$TEL_PID" 2>/dev/null
  [[ -n "${REFLECTOR_PID:-}" ]] && kill "$REFLECTOR_PID" 2>/dev/null
  "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$DEVICE" >/dev/null 2>&1
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=rep -> json on stdout
  cat <<EOF
{
  "experiment": "exp-005", "hypothesis": "cold-start-first-packet-latency",
  "repetition": $1,
  "cold_probe_pps": $COLD_PPS, "cold_probe_duration_s": $COLD_S,
  "cold_probe_timeout_ms": $COLD_TIMEOUT_MS, "cold_probe_warmup_s": 0,
  "steady_window_s": $STEADY_S, "steady_probe_pps": $STEADY_PPS,
  "steady_probe_timeout_ms": $STEADY_TIMEOUT_MS,
  "quick_profile": $QUICK,
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "cpu_pinning": "none",
  "tool_versions": {
    "vxedge": "$(git -C "$WS/vxedge" rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "vxagents": "$(git -C "$WS/vxagents" rev-parse --short HEAD 2>/dev/null || echo unknown)",
    "vxtelemetry": "$(git -C "$WS/vxtelemetry" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  },
  "loadavg_at_start": "$(cut -d' ' -f1-3 /proc/loadavg)",
  "timestamping": "userspace-monotonic (SO_TIMESTAMPING follow-up open)",
  "isolation": "single-device, no offered load",
  "measurement_locality": "cross-netns (prober in the device's own netns via ip netns exec, reflector in the host default netns) -- see docs/ROADMAP.md"
}
EOF
}

echo "== exp-005: reps=$REPS cold=(${COLD_PPS}pps x ${COLD_S}s) steady=(${STEADY_PPS}pps x ${STEADY_S}s)"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1

for rep in $(seq 1 "$REPS"); do
  tag="rep${rep}"
  echo "-- $tag: gateway up"
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment up --stage gateway >/dev/null

  # The reflector: the backbone-side destination the device is trying to reach, on the uplink's
  # own VLAN subinterface (fresh each cycle; interfaces are recreated by `up`) — exactly
  # exp-014's own pattern, one device instead of six.
  ip link add link vxup0p name vxup0p.101 type vlan id 101
  ip addr replace "$REFLECTOR_ADDR/24" dev vxup0p.101 && ip link set vxup0p.101 up
  ip link set vxup0p up

  "$VXPROBE" reflect --listen "$REFLECTOR_ADDR:9800" &>/dev/null &
  REFLECTOR_PID=$!
  sleep 0.5

  INGEST="$RUNTIME/ingest-$tag"
  mkdir -p "$INGEST"
  env_metadata "$rep" > "$INGEST/run-env.json"

  # The moment under test: `zone up` returns, and the cold probe fires immediately after —
  # no sleep, no warmup, on purpose.
  ns="vx-$DEVICE"
  echo "   $tag: zone up (t0)"
  "$VXEDGE" --endpoint "unix://$SOCK" zone up --vxid "$DEVICE" >/dev/null

  echo "   $tag: cold burst (0s warmup, n~$((COLD_PPS * COLD_S)))"
  if ! ip netns exec "$ns" "$VXPROBE" send --target "$REFLECTOR_ADDR:9800" --pps "$COLD_PPS" \
    --duration-s "$COLD_S" --timeout-ms "$COLD_TIMEOUT_MS" \
    2>/dev/null > "$INGEST/cold-summary.json"; then
    echo "   $tag: WARNING cold-phase vxprobe reported zero received probes" >&2
  fi

  echo "   $tag: steady window (${STEADY_S}s)"
  ip netns exec "$ns" "$VXTELEMETRY" ingest --workspace "$MANIFEST" --ingest-dir "$INGEST" \
    --interval-s 5 --duration-s "$STEADY_S" &>/dev/null & TEL_PID=$!
  if ! ip netns exec "$ns" "$VXPROBE" send --target "$REFLECTOR_ADDR:9800" --pps "$STEADY_PPS" \
    --duration-s "$STEADY_S" --timeout-ms "$STEADY_TIMEOUT_MS" --metrics 127.0.0.1:9801 \
    2>/dev/null > "$INGEST/probe-summary.json"; then
    echo "   $tag: WARNING steady-phase vxprobe reported zero received probes — measurement failed" >&2
  fi
  wait "$TEL_PID" || echo "   $tag: WARNING vxtelemetry ingest exited non-zero — archive may be incomplete" >&2

  "$VXTELEMETRY" collect --workspace "$MANIFEST" --ingest-dir "$INGEST" \
    --out "$RESULTS/$tag.zip" >/dev/null
  cold_max=$(jq -r '.rtt_us.max' "$INGEST/cold-summary.json" 2>/dev/null || echo '?')
  steady_p50=$(jq -r '.rtt_us.p50' "$INGEST/probe-summary.json" 2>/dev/null || echo '?')
  echo "   $tag: archived (cold max ${cold_max}us vs steady p50 ${steady_p50}us)"

  "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$DEVICE" >/dev/null
  kill "$REFLECTOR_PID" 2>/dev/null || true
  ip link del vxup0p.101 2>/dev/null || true
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null
  sleep 1  # let the port fully release before the next repetition's fresh zone up
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi
echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp005.py $RESULTS"
