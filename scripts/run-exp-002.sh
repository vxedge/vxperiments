#!/usr/bin/env bash
# exp-002 campaign runner — packaging backend vs latency (H3).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-002.sh [--quick]
#
# --quick: 1 repetition, short windows — pipeline/backend validation only
#          (also the first privileged exercise of the microvm/libvirt backends).
# default: 5 repetitions x 3 arms, 60 s x 1000 pps per measurement.
#
# Topology per repetition: `vxedge up` provisions the gateway; `vxedge zone up`
# starts all three nodes under their backends. The probe SENDER sits on the
# uplink side (vxup0p.101 = 10.101.0.1/24) and measures each node's reflector
# sequentially: container payload is exec'd into its netns by this script;
# VM payloads autostart from the guest bundle.
set -euo pipefail

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

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
[[ -f "$BUNDLE/vmlinuz" && -f "$BUNDLE/initrd.img" ]] || {
  echo "error: guest bundle missing — cd $WS/vxzones && ./scripts/build-guest-bundle.sh" >&2
  exit 1
}

source "$REPO_DIR/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

MANIFEST="$REPO_DIR/experiments/exp-002.yaml"
RESULTS="$REPO_DIR/results/exp-002"
RUNTIME=$(mktemp -d /tmp/exp-002.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"
ZONE="vxzone-front-left-01"

# arm name -> reflector address
declare -A ARM_ADDR=(
  [container]="10.101.0.11" [microvm]="10.101.0.12" [libvirt]="10.101.0.13"
)
ARMS=(container microvm libvirt)

if [[ $QUICK -eq 1 ]]; then
  REPS=1; WARM_S=2; PROBE_S=10; PROBE_PPS=500
else
  REPS=5; WARM_S=5; PROBE_S=60; PROBE_PPS=1000
fi

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$ZONE" >/dev/null 2>&1
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
  "quick_profile": $QUICK,
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "kvm": $([[ -e /dev/kvm ]] && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "loadavg_at_start": "$(cut -d' ' -f1-3 /proc/loadavg)",
  "timestamping": "userspace-monotonic (SO_TIMESTAMPING follow-up open)",
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

echo "== exp-002: reps=$REPS arms=(${ARMS[*]}) window=${PROBE_S}s pps=$PROBE_PPS"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1

for rep in $(seq 1 "$REPS"); do
  echo "-- rep $rep: gateway + zone up"
  "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$MANIFEST" >/dev/null
  ip link add link vxup0p name vxup0p.101 type vlan id 101
  ip addr add 10.101.0.1/24 dev vxup0p.101
  ip link set vxup0p up && ip link set vxup0p.101 up

  "$VXEDGE" --endpoint "unix://$SOCK" zone up --vxid "$ZONE" >/dev/null
  # Container payload: exec the identical reflector into the node's netns.
  ip netns exec vx-node-cont-01 "$VXPROBE" reflect --listen 0.0.0.0:9800 &>/dev/null &
  PIDS+=($!)

  for arm in "${ARMS[@]}"; do
    addr="${ARM_ADDR[$arm]}"
    tag="rep${rep}-${arm}"
    echo "   $tag: waiting for reflector at $addr"
    wait_reflector "$addr"
    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$arm" "$rep" > "$INGEST/run-env.json"
    sleep "$WARM_S"

    "$VXTELEMETRY" ingest --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & TEL_PID=$!
    echo "   $tag: probing ${PROBE_S}s @ ${PROBE_PPS}pps"
    "$VXPROBE" send --target "$addr:9800" --pps "$PROBE_PPS" \
      --duration-s "$PROBE_S" --metrics 127.0.0.1:9801 \
      2>/dev/null > "$INGEST/probe-summary.json"
    wait "$TEL_PID" 2>/dev/null || true

    "$VXTELEMETRY" collect --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   $tag: archived ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"
  done

  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  PIDS=()
  "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$ZONE" >/dev/null
  ip link del vxup0p.101 2>/dev/null || true
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi
echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp002.py $RESULTS"
