#!/usr/bin/env bash
# exp-003 campaign runner — ADAS slice SLA under OTA co-location (H4).
#
# Run as root from the vxperiments repo root:
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-003.sh [--quick]
#
# --quick: 1 repetition x 2 arms, short windows — pipeline validation only;
#          sample counts are below tail-percentile support and MUST NOT be
#          reported as results (experiment-methodology skill).
# default: 5 repetitions x 2 arms (baseline, ota-burst), 10s warmup + 60s
#          measured probe window per point (1000 pps => 60k samples).
#
# Arms: baseline (ota service up, idle) vs ota-burst (vxota-probe fetching a
# multi-MB artifact back-to-back, zero interval, for the whole warmup+probe
# window — a worst-case "update in progress right now" scenario). Same
# adas slice/QoS/probe parameters as exp-001, so this campaign's baseline is
# directly comparable to exp-001's load=0 point, and ota-burst to exp-001's
# heaviest infotainment-load point.
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
VXOTA="$WS/vxota/target/debug/vxota"
VXOTA_PROBE="$WS/vxota/target/debug/vxota-probe"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTELEMETRY" "$VXOTA" "$VXOTA_PROBE"; do
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
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"
check_fresh_bin "$WS/vxota" "$VXOTA" "$WS/vxota/crates/vxota"
check_fresh_bin "$WS/vxota" "$VXOTA_PROBE" "$WS/vxota/crates/vxota-probe"

MANIFEST="$REPO_DIR/experiments/exp-003.yaml"
RESULTS="$REPO_DIR/results/exp-003"
RUNTIME=$(mktemp -d /tmp/exp-003.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

# --- OTA store prep (once, idempotent — mirrors vxzones' pre-built bundle
# convention: not part of the per-repetition fresh up/down cycle). The
# private key lives OUTSIDE the store: `vxota serve` publishes the whole
# artifacts_dir over HTTP. -----------------------------------------------
OTA_STORE=/tmp/vxota-exp003-store
OTA_KEY=/tmp/vxota-exp003-root.key
if [[ $QUICK -eq 1 ]]; then BURST_MB=1; else BURST_MB=5; fi
if [[ ! -f "$OTA_KEY" ]]; then
  "$VXOTA" keygen --artifacts-dir "$OTA_STORE" --out-priv "$OTA_KEY" > "$RUNTIME/keygen.out"
fi
dd if=/dev/urandom of="$RUNTIME/burst-artifact.bin" bs=1M count="$BURST_MB" status=none
"$VXOTA" publish --artifacts-dir "$OTA_STORE" --file "$RUNTIME/burst-artifact.bin" \
  --name burst-artifact --signing-key "$OTA_KEY" >/dev/null
OTA_TRUST_ROOT=$(jq -r '.signed.keys | to_entries[0].value.public' "$OTA_STORE/root.json")

if [[ $QUICK -eq 1 ]]; then
  REPS=1; ARMS=(baseline ota-burst); WARM_S=2; PROBE_S=10; PROBE_PPS=500
else
  REPS=5; ARMS=(baseline ota-burst); WARM_S=10; PROBE_S=60; PROBE_PPS=1000
fi
PROBE_TIMEOUT_MS=1000

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  "$VXEDGE" --endpoint "unix://$SOCK" ota down --experiment "$MANIFEST" >/dev/null 2>&1
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=arm $2=rep
  cat <<EOF
{
  "experiment": "exp-003", "hypothesis": "H4",
  "arm": "$1", "repetition": $2,
  "warmup_s": $WARM_S, "probe_window_s": $PROBE_S, "probe_pps": $PROBE_PPS,
  "probe_timeout_ms": $PROBE_TIMEOUT_MS,
  "ota_burst_artifact_mb": $BURST_MB,
  "quick_profile": $QUICK,
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "cpu_pinning": "none",
  "loadavg_at_start": "$(cut -d' ' -f1-3 /proc/loadavg)",
  "timestamping": "userspace-monotonic",
  "tool_versions": {
    "vxedge": "$($VXEDGE --version | awk '{print $2}')",
    "vxprobe": "$($VXPROBE --version | awk '{print $2}')",
    "vxtelemetry": "$($VXTELEMETRY --version | awk '{print $2}')",
    "vxota": "$($VXOTA --version | awk '{print $2}')",
    "vxota_probe": "$($VXOTA_PROBE --version | awk '{print $2}')"
  }
}
EOF
}

echo "== exp-003 campaign: reps=$REPS arms=(${ARMS[*]}) warmup=${WARM_S}s window=${PROBE_S}s pps=$PROBE_PPS burst=${BURST_MB}MB"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME/daemon" --vxota-bin "$VXOTA" \
  &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1
VXEDGE_C=("$VXEDGE" --endpoint "unix://$SOCK")

for rep in $(seq 1 "$REPS"); do
  for arm in "${ARMS[@]}"; do
    tag="rep${rep}-${arm}"
    echo "-- $tag: gateway + ota service up"
    "${VXEDGE_C[@]}" up --manifest "$MANIFEST" >/dev/null

    ip addr add 10.101.0.2/24 dev vzp0 && ip link set vzp0 up
    ip link add link vxup0p name vxup0p.101 type vlan id 101
    ip addr add 10.101.0.1/24 dev vxup0p.101 && ip link set vxup0p.101 up
    ip link set vxup0p up

    "${VXEDGE_C[@]}" ota up --experiment "$MANIFEST" >/dev/null

    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$arm" "$rep" > "$INGEST/run-env.json"

    "$VXPROBE" reflect --listen 10.101.0.1:9800 &>/dev/null & PIDS+=($!)
    sleep 0.5

    if [[ "$arm" == "ota-burst" ]]; then
      # Runs for the whole warmup+probe window, killed at the end like the
      # reflector above — not time-bounded itself (vxota-probe has no
      # --duration-s), so a large --repeat plus explicit teardown is the
      # same pattern exp-001 uses for its interfering-load generator.
      # Its own final JSON summary won't survive being killed mid-loop;
      # the manifest's telemetry.prometheus.scrape_targets already lists
      # its live exporter (127.0.0.1:9902), so vxtelemetry's periodic
      # scrapes are the source of truth for ota-burst delivery stats.
      "$VXOTA_PROBE" fetch --server "http://127.0.0.1:9900" --target burst-artifact \
        --trust-root "$OTA_TRUST_ROOT" --out "$RUNTIME/burst-dl-$tag.bin" \
        --repeat 999999 --interval-s 0 --timeout-s 10 --metrics 127.0.0.1:9902 \
        &>/dev/null & PIDS+=($!)
    fi

    echo "   warmup ${WARM_S}s ($arm)"
    sleep "$WARM_S"

    "$VXTELEMETRY" ingest --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & TEL_PID=$!

    echo "   probing ${PROBE_S}s @ ${PROBE_PPS}pps on adas slice ($arm)"
    if ! "$VXPROBE" send --target 10.101.0.1:9800 --pps "$PROBE_PPS" \
      --duration-s "$PROBE_S" --timeout-ms "$PROBE_TIMEOUT_MS" --metrics 127.0.0.1:9801 \
      2>/dev/null > "$INGEST/probe-summary.json"; then
      echo "   $tag: WARNING vxprobe reported zero received probes — measurement failed" >&2
    fi

    wait "$TEL_PID" || echo "   $tag: WARNING vxtelemetry ingest exited non-zero — archive may be incomplete" >&2
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
    PIDS=()

    "$VXTELEMETRY" collect --manifest "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   archived $RESULTS/$tag.zip ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"

    "${VXEDGE_C[@]}" ota down --experiment "$MANIFEST" >/dev/null
    ip link del vxup0p.101 2>/dev/null || true
    "${VXEDGE_C[@]}" down --manifest "$MANIFEST" >/dev/null
  done
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi

echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp003.py $RESULTS"
