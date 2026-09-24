#!/usr/bin/env bash
# exp-014 campaign runner — harness topology as a variable: star vs daisy-chained zones.
#
# Run as root from the vxperiments repo root:
#   cd experiments/exp-014 && sudo -E env "PATH=$PATH" ./scripts/run.sh [--quick|--repro]
#
# Six devices, one slice, no packaging variance and no competing traffic profile: the only
# declared variable across the six arms is which harness each position is wired with
# (vehicle.yaml's per-link `impairments`/`harness`), so the arms are probed sequentially on an
# otherwise idle topology — matching exp-002's own "the variable is the only thing that differs"
# design, one arm's zone up at a time.
#
# Unlike exp-001/exp-002, every device here is genuinely zoned up (`zone up --vxid <device>`)
# and probed via `ip netns exec vx-<device> ...`, rather than addressed as a host-side veth peer
# in the default namespace. This is deliberate, not stylistic: authoring this experiment found
# that Linux's local routing table delivers traffic between two addresses configured in the
# *same* netns via loopback, bypassing the bridge/netem path entirely (confirmed with a
# disposable-netns repro — `ip route get` resolved to `dev lo`, and tcpdump on the access port
# saw nothing). Putting the prober in the device's own netns and the reflector in the host's
# default netns puts them in different FIB domains, so there is no shortcut to take. See
# `docs/ROADMAP.md` ("Do not lose these") for the finding and its open follow-up against
# exp-001/exp-002 themselves.
#
# --repro: full campaign written to results/exp-014-repro-<date>/ — a first successful campaign
#          becomes results/exp-014/ and is never overwritten in place (lib/results_dir.sh).
#
# --quick: 1 repetition, short windows — pipeline validation only; sample counts are below
#          tail-percentile support and MUST NOT be reported as results.
# default: 5 repetitions x 6 arms, 60 s x 1000 pps per measurement.
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

# Provisioning is the daemon's: `experiment up --stage gateway` provisions the bridge, the one
# shared slice's VLAN/HTB, and one access port per device (with its impairment, if the link
# declares one). `zone up --vxid <device>` (below, per arm) is what then moves that device's
# access-port peer into its own dedicated netns and assigns the address vehicle.yaml declares on
# it. What stays in this script is method: repetitions, warmup, measurement window, collection.
MANIFEST="$SANDBOX"
source "$SANDBOX/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-014 "$QUICK" "$REPRO")"
source "$SANDBOX/scripts/lib/host_pinning.sh"
pin_cpu_governor_performance
RUNTIME=$(mktemp -d /tmp/exp-014.XXXXXX)
SOCK="$RUNTIME/vxedge.sock"

# The six arms, in the order this campaign reports them: three star positions (uniform,
# always-one-hop by design) then three chain positions (accumulating 1/2/3 hops). Device id
# doubles as arm label here (unlike H3's node-cont-01 etc.), so no separate arm->device map is
# needed; `zone up --vxid star-fl` and `ip netns exec vx-star-fl` both key off it directly.
ARMS=(star-fl star-fr star-rl chain-fl chain-fr chain-rl)
declare -A ARM_ADDR=(
  [star-fl]=10.114.0.11  [star-fr]=10.114.0.12  [star-rl]=10.114.0.13
  [chain-fl]=10.114.0.21 [chain-fr]=10.114.0.22 [chain-rl]=10.114.0.23
)
declare -A ARM_HOP=( [star-fl]=1 [star-fr]=1 [star-rl]=1 [chain-fl]=1 [chain-fr]=2 [chain-rl]=3 )
REFLECTOR_ADDR=10.114.0.1

# Every declared value an archive records comes from reading vehicle.yaml back, not from a
# second copy in this script that could silently drift from it — the same trap
# `services.telemetry.config` restating scrape targets already fell into once
# (vxedge/TASKS.md), fixed there by reading the source instead of duplicating it. A link's block
# spans from its own `- id:` line to the next one; `awk` collects it, `sed` pulls one field.
link_block() { # $1=link-id -> that link's YAML lines
  awk -v want="$1" '
    /^  - id: / { grab = ($3 == want) ? 1 : 0 }
    grab { print }
  ' "$MANIFEST/vehicle.yaml"
}
link_field() { # $1=link-id $2=field-name
  local block
  block="$(link_block "$1")"
  [[ -n "$block" ]] || { echo "error: no link '$1' in vehicle.yaml" >&2; return 1; }
  sed -n "s/.*\b$2: \([^,}]*\).*/\1/p" <<<"$block" | head -1 | tr -d ' '
}

# WARM_S=10 meets the experiment-methodology skill's minimum
# (max(10% of PROBE_S, 10s) = 10s at PROBE_S=60).
if [[ $QUICK -eq 1 ]]; then
  REPS=1; WARM_S=2; PROBE_S=10; PROBE_PPS=500; PROBE_TIMEOUT_MS=1000
else
  REPS=5; WARM_S=10; PROBE_S=60; PROBE_PPS=1000; PROBE_TIMEOUT_MS=1000
fi

cleanup() {
  set +e
  restore_cpu_governors
  [[ -n "${TEL_PID:-}" ]] && kill "$TEL_PID" 2>/dev/null
  [[ -n "${REFLECTOR_PID:-}" ]] && kill "$REFLECTOR_PID" 2>/dev/null
  for arm in "${ARMS[@]}"; do
    "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$arm" >/dev/null 2>&1
  done
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null
}
trap cleanup EXIT

env_metadata() { # $1=arm $2=rep -> json on stdout
  local link="seg-$1"
  cat <<EOF
{
  "experiment": "exp-014", "hypothesis": "harness-topology",
  "arm": "$1", "topology": "${1%%-*}", "position": "${1##*-}", "hop": ${ARM_HOP[$1]},
  "repetition": $2,
  "declared_impairment": {
    "rate_mbps": $(link_field "$link" rate_mbps),
    "delay_us": $(link_field "$link" delay_us),
    "jitter_us": $(link_field "$link" jitter_us),
    "loss_pct": $(link_field "$link" loss_pct)
  },
  "declared_harness": {
    "medium": "$(link_field "$link" medium)",
    "length_m": $(link_field "$link" length_m),
    "weight_g": $(link_field "$link" weight_g)
  },
  "warmup_s": $WARM_S, "probe_window_s": $PROBE_S, "probe_pps": $PROBE_PPS,
  "probe_timeout_ms": $PROBE_TIMEOUT_MS,
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
  "isolation": "single-arm",
  "measurement_locality": "cross-netns (prober in the zone's own netns via ip netns exec, reflector in the host default netns) -- see docs/ROADMAP.md for why this differs from exp-001/exp-002"
}
EOF
}

echo "== exp-014: reps=$REPS arms=(${ARMS[*]}) window=${PROBE_S}s pps=$PROBE_PPS [isolated: one arm at a time]"
mkdir -p "$RESULTS"

"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!
sleep 1

for rep in $(seq 1 "$REPS"); do
  echo "-- rep $rep: gateway up"
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment up --stage gateway >/dev/null

  # The reflector: the one thing that stays in the host's default netns, representing the
  # backbone/central destination every arm's ECU is trying to reach. Its address lives on the
  # uplink's own VLAN subinterface (fresh each cycle; interfaces are recreated by `up`).
  ip link add link vxup0p name vxup0p.101 type vlan id 101
  ip addr replace "$REFLECTOR_ADDR/24" dev vxup0p.101 && ip link set vxup0p.101 up
  ip link set vxup0p up

  "$VXPROBE" reflect --listen "$REFLECTOR_ADDR:9800" &>/dev/null &
  REFLECTOR_PID=$!
  sleep 0.5

  for arm in "${ARMS[@]}"; do
    addr="${ARM_ADDR[$arm]}"
    tag="rep${rep}-${arm}"
    ns="vx-$arm"
    echo "   $tag: probing (isolated, hop=${ARM_HOP[$arm]})"
    # Moves this device's access-port peer into $ns, renames it eth0, and assigns the address
    # vehicle.yaml declares on it -- no manual `ip addr` needed here, unlike the reflector above.
    "$VXEDGE" --endpoint "unix://$SOCK" zone up --vxid "$arm" >/dev/null

    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$arm" "$rep" > "$INGEST/run-env.json"
    sleep "$WARM_S"

    # Both run inside $ns: vxprobe's --metrics port is per-netns loopback, and vxtelemetry has
    # to scrape it from the same one it was actually opened in.
    ip netns exec "$ns" "$VXTELEMETRY" ingest --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & TEL_PID=$!
    if ! ip netns exec "$ns" "$VXPROBE" send --target "$REFLECTOR_ADDR:9800" --pps "$PROBE_PPS" \
      --duration-s "$PROBE_S" --timeout-ms "$PROBE_TIMEOUT_MS" --metrics 127.0.0.1:9801 \
      2>/dev/null > "$INGEST/probe-summary.json"; then
      echo "   $tag: WARNING vxprobe reported zero received probes — measurement failed" >&2
    fi
    wait "$TEL_PID" || echo "   $tag: WARNING vxtelemetry ingest exited non-zero — archive may be incomplete" >&2

    "$VXTELEMETRY" collect --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   $tag: archived ($(jq -r '.rtt_us.p99' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p99)"

    "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$arm" >/dev/null
    sleep 1  # let the port fully release before the next arm claims it (matches exp-002)
  done

  kill "$REFLECTOR_PID" 2>/dev/null || true
  ip link del vxup0p.101 2>/dev/null || true
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$MANIFEST" experiment down --stage gateway >/dev/null
done

if [[ -n "${SUDO_UID:-}" ]]; then
  chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
fi
echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp014.py $RESULTS"
