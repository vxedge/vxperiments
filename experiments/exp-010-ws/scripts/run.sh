#!/usr/bin/env bash
# exp-010 campaign runner — H2 real S-NSSAI slicing, snssai arm (vlan arm =
# exp-001's own frozen numbers, per the model's own doc comment — no
# same-day rerun needed).
#
# Run as your normal user (NOT under sudo) from the vxperiments repo root:
#   ./scripts/run.sh [--quick|--repro]
#
# **Do not run this script itself under `sudo`** — unlike run-exp-001.sh
# (pure VLAN/HTB, no podman involved), this campaign brings up the real 5G
# core via podman. Running the whole process as root switches podman to
# root's own separate rootless identity/storage, which never had
# `vx5g-core`/`vx5g-ran` built into it (`podman build` was run as your own
# user) — `podman run vx5g-core` under root then fails trying to resolve
# "vx5g-core" as a short registry name instead of finding the local image.
# Exactly the same trap documented in
# crates/vxedge-core/tests/fiveg_podman.rs's own module comment. Host
# networking (bridge/vlan/route) still needs CAP_NET_ADMIN regardless —
# `gateway::Shell`'s escalated calls shell out to `sudo ip`/`sudo bridge`
# internally, scoped to just those calls, so this script caches a sudo
# credential up front (`sudo -v`) rather than running the whole thing as
# root.
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
# docs/RESULTS.md "TrafficService live end to end").
#
# Two real constraints this script works around, not hacks:
#  1. TrafficUpRequest has no per-call rate/duration override — `bandwidth_mbps`
#     and `duration_s` come from the manifest itself (`experiment.duration_s`,
#     wired 2026-07-17 specifically for this campaign — previously silently
#     fell back to vxprobe/vxtraffic's own 10s CLI default, which would have
#     under-sampled tail percentiles). So the load sweep and the two-phase
#     warmup/probe timing are both done via small manifest variants generated
#     into $RUNTIME, not CLI flags — still fully workspace-driven, just two
#     workspace variants instead of one for the two different phase durations
#     needed (`infotainment-load` must outlive the probe's own shorter window
#     so it's still driving load throughout, exactly like exp-001's own
#     WARMUP_S+PROBE_S+4 duration on vxtraffic vs PROBE_S on vxprobe). Every
#     archive bundles the canonical, unmodified exp-010-ws workspace under
#     workspace/ (its workspace_sha256 stays constant across every
#     rep/load, matching exp-001's own archive convention) — the swept load
#     and phase durations live only in run-env.json's per-point metadata,
#     same place exp-001 already records its own load value.
#  2. TrafficService's spawned `vxprobe send` doesn't expose `--metrics`
#     (live Prometheus) — only its final aggregate JSON is captured. Recorded
#     honestly in run-env.json rather than faking parity with exp-001's live
#     telemetry scrape; the analysis (notebooks/analyze_exp010.py) only reads
#     the aggregate JSON same as analyze_exp001.py does.
#
# Host-confound mitigation (added 2026-07-18, first campaign where it's
# load-bearing rather than polish — see docs/RESULTS.md): pins the cpu
# governor to `performance` for the run's duration (restored on exit) and
# taskset's vxedged + the host-side vxprobe/vxtraffic processes to a
# reserved core range, away from the ~13 containers this campaign's own 5G
# core spins up. Best-effort, not a hard guarantee (podman's own
# containers, including adas-probe's own reflector which runs inside the
# UE pod, are not cpuset-restricted away from the reserved cores) — recorded
# honestly in each archive's own run-env.json `cpu_pinning` field.
set -euo pipefail

QUICK=0; REPRO=0
for arg in "$@"; do case "$arg" in
  --quick) QUICK=1 ;;
  --repro) REPRO=1 ;;
  *) echo "error: unknown argument '$arg' (supported: --quick, --repro)" >&2; exit 1 ;;
esac; done

if [[ $(id -u) -eq 0 ]]; then
  echo "error: do not run this script itself under sudo/as root (see header comment)" >&2
  echo "       — run as your normal user; it caches a sudo credential for the network ops it needs" >&2
  exit 1
fi

# Cache a sudo credential so Shell's internal escalated calls (bridge/vlan/
# route provisioning, entering pod netns) don't block on a password prompt
# partway through a run.
sudo -v

# --- locations (meta-workspace layout: repos side by side) -------------------
# This sandbox, and the meta-workspace it sits in. Resolved from this script's own location, so
# the experiment runs wherever it is unpacked.
SANDBOX="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$SANDBOX/../.." && pwd)"
WS="$(dirname "$REPO_DIR")"

# --- host-confound mitigation, not a mechanism change -------------------------
# Found live 2026-07-18: this campaign's own governor was left on `powersave`
# (previous scripts only ever *recorded* cpu_governor, never set it), and
# nothing pinned the measurement-critical processes away from the ~13
# containers this campaign's own 5G core spins up on the same host. Neither
# is new debt — see scripts/lib/host_pinning.sh's own header for why it just
# never mattered enough to fix before. Shared with
# scripts/calibrate-exp-010-noise-floor.sh so both use the identical
# mitigation, not two copies that can drift apart.
source "$SANDBOX/scripts/lib/host_pinning.sh"
pin_cpu_governor_performance
reserve_measurement_cores
VXEDGED="$WS/vxedge/target/debug/vxedged"
VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/release/vxprobe"
VXTRAFFIC="$WS/vxagents/target/release/vxtraffic"
VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTRAFFIC" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin — cargo build (--release for vxagents) each repo first" >&2; exit 1; }
done

source "$SANDBOX/scripts/lib/freshness.sh"
check_fresh_bin "$WS/vxedge" "$VXEDGED" "$WS/vxedge/crates/vxedged" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxedge" "$VXEDGE" "$WS/vxedge/crates/vxedge-cli" "$WS/vxedge/proto"
check_fresh_bin "$WS/vxagents" "$VXPROBE" "$WS/vxagents/crates/vxprobe"
check_fresh_bin "$WS/vxagents" "$VXTRAFFIC" "$WS/vxagents/crates/vxtraffic"
check_fresh_bin "$WS/vxtelemetry" "$VXTELEMETRY" "$WS/vxtelemetry"

# Native rtnetlink port (2026-08-04, docs/ROADMAP.md): bridge/veth/VLAN/address/route
# creation now happens in vxedged's own in-process syscalls, so the daemon process itself
# needs CAP_NET_ADMIN for `experiment up --stage gateway` to succeed -- setcap genuinely works
# for this portion (no child process involved, so the fork+exec capability-propagation problem
# that still blocks it for tc/nft/wg below doesn't apply here; docs/TESTBED-SETUP.md corrected
# 2026-08-05). Has to be redone after every rebuild, which is why this lives here rather than
# being a one-time host setup step -- the freshness checks above just confirmed this is the
# binary about to run, so capping it now caps the right one. Found live 2026-08-05: without
# this, `experiment up` fails instantly with "insufficient privileges for netlink operation
# `ensure_bridge`" -- the `sudo -v` cached above already covers the password prompt this needs.
sudo setcap cap_net_admin+ep "$VXEDGED"

# The §6.0 workspace is the input now: §6.1 manifests stopped being a provisioning input on
# 2026-07-31. The frozen `../experiments/retired-6.1/exp-010.yaml` stays as provenance for the results
# already recorded against it.
CANONICAL_WS="$SANDBOX"
source "$SANDBOX/scripts/lib/results_dir.sh"
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
  "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$CANONICAL_WS" >/dev/null 2>&1
  "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$CANONICAL_WS" experiment down --stage gateway >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  echo "== restoring original cpu governor(s) =="
  restore_cpu_governors
}
trap cleanup EXIT

env_metadata() { # $1=load $2=rep $3=position-in-sequence $4=full-sequence -> json on stdout
  cat <<EOF
{
  "experiment": "exp-010", "hypothesis": "H2", "slice_mode": "snssai",
  "load_mbps": $1, "repetition": $2,
  "position_in_rep_sequence": $3, "rep_load_sequence": "$4",
  "warmup_s": $WARMUP_S, "probe_window_s": $PROBE_S,
  "load_phase_duration_s": $((WARMUP_S + PROBE_S + 4)),
  "probe_pps": 1000, "quick_profile": $QUICK,
  "prometheus_live_metrics": false,
  "prometheus_live_metrics_note": "TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)",
  "kernel": "$(uname -r)",
  "preempt_rt": $(uname -v | grep -qi preempt_rt && echo true || echo false),
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)",
  "cpu_pinning": "vxedged + host-side vxprobe/vxtraffic: $(cpu_pinning_description). adas-probe's own reflector runs inside the UE pod, not pinned",
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
pin_if_alive "$DAEMON_PID"

for rep in $(seq 1 "$REPS"); do
  # Randomize load order per repetition — every prior campaign script in
  # this project (exp-001 through the pre-randomization exp-010) runs loads
  # in the same fixed sequence every rep, so a position-correlated host
  # effect (podman/mongo cache warmth, thermal ramp after N consecutive pod
  # boots, systemd housekeeping) would look identical to a load-correlated
  # one. Shuffling breaks that confound apart: if an anomaly follows a
  # specific load value regardless of when it runs, it's the mechanism; if
  # it follows a fixed position in the sequence regardless of load, it's
  # the host. docs/RESULTS.md's "H2's real campaign" entry is the finding
  # that made this worth doing — a reproducible bump at 250mbit that didn't
  # fit a monotonic-under-load story.
  mapfile -t REP_LOADS < <(printf '%s\n' "${LOADS_MBPS[@]}" | shuf)
  echo "-- rep$rep load order (randomized): ${REP_LOADS[*]}"
  position=0
  for load in "${REP_LOADS[@]}"; do
    position=$((position + 1))
    tag="rep${rep}-load${load}"
    echo "-- $tag: vxedge up (gateway + real 5G core + both UE pods)"

    # Two manifest variants: same everything except experiment.duration_s
    # (and the swept bandwidth_mbps on the load variant) — see the header
    # comment for why TrafficUpRequest can't just take these as call params.
    # Two workspace variants: copies of the canonical one with `method.duration_s` (and the
    # swept `bandwidth_mbps` on the load variant) patched in `main.yaml`. A workspace is a
    # folder, so the variant is a folder — the vehicle and baseline are copied unchanged, which
    # is what keeps the topology identical across the sweep.
    LOAD_WS="$RUNTIME/exp-010-load-$tag"
    PROBE_WS="$RUNTIME/exp-010-probe-$tag"
    for variant in "$LOAD_WS" "$PROBE_WS"; do
      rm -rf "$variant"; cp -r "$CANONICAL_WS" "$variant"; rm -rf "$variant/results"
    done
    sed -i -e "s/bandwidth_mbps: 400 /bandwidth_mbps: $load /" \
           -e "s/duration_s: 60/duration_s: $((WARMUP_S + PROBE_S + 4))/" \
           "$LOAD_WS/main.yaml"
    sed -i -e "s/duration_s: 60/duration_s: $PROBE_S/" "$PROBE_WS/main.yaml"

    # Gateway only: this campaign drives its own traffic profiles per point, and exp-010's
    # nodes are UE pods the 5G stage brings up rather than zones.
    "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$PROBE_WS" experiment up --stage gateway

    INGEST="$RUNTIME/ingest-$tag"
    mkdir -p "$INGEST"
    env_metadata "$load" "$rep" "$position" "${REP_LOADS[*]}" > "$INGEST/run-env.json"

    if [[ "$load" -gt 0 ]]; then
      echo "   starting infotainment-load @ ${load}mbit (runs $((WARMUP_S + PROBE_S + 4))s)"
      "$VXEDGE" --endpoint "unix://$SOCK" traffic up --manifest "$LOAD_WS" \
        --profile infotainment-load
      pin_if_alive "$(cat "$RUNTIME/traffic-infotainment-load-load.pid" 2>/dev/null || true)"
    fi
    echo "   warmup ${WARMUP_S}s under load=${load}mbit"
    sleep "$WARMUP_S"

    echo "   starting adas-probe (1000pps, ${PROBE_S}s — blocks until the UE's PDU session + reflector are confirmed ready)"
    "$VXEDGE" --endpoint "unix://$SOCK" traffic up --manifest "$PROBE_WS" \
      --profile adas-probe
    pin_if_alive "$(cat "$RUNTIME/traffic-adas-probe-send.pid" 2>/dev/null || true)"

    echo "   waiting ${PROBE_S}s for the probe window to finish"
    sleep "$((PROBE_S + 3))"

    cp "$RUNTIME/traffic-adas-probe-send.log" "$INGEST/probe-summary.json"
    if [[ "$load" -gt 0 ]]; then
      cp "$RUNTIME/traffic-infotainment-load-load.log" "$INGEST/traffic-summary.json"
    fi

    "$VXEDGE" --endpoint "unix://$SOCK" traffic down --manifest "$PROBE_WS"
    "$VXEDGE" --endpoint "unix://$SOCK" --chdir "$PROBE_WS" experiment down --stage gateway

    # --record-image: content-addressed identities of the images this
    # campaign actually ran (§13 reproducibility) land in each archive's
    # metadata.json. These names mirror FiveGLifecycleConfig::default() +
    # fiveg's mongo pin — the runner knows its images; vxtelemetry
    # deliberately doesn't guess (see its collect --help).
    "$VXTELEMETRY" collect --workspace "$CANONICAL_WS" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" \
      --record-image vx5g-core --record-image vx5g-ran \
      --record-image docker.io/library/mongo:7 >/dev/null
    p99=$(jq -r '.rtt_us.p99 // "?"' "$INGEST/probe-summary.json" 2>/dev/null || echo '?')
    loss=$(jq -r '.loss_pct // "?"' "$INGEST/probe-summary.json" 2>/dev/null || echo '?')
    echo "   archived $RESULTS/$tag.zip (p99=${p99}us loss=${loss}%)"
  done
done

echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp010.py $RESULTS --baseline results/exp-001"
