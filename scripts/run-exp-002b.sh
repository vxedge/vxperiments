#!/usr/bin/env bash
# exp-002b campaign runner — H3 decomposition + per-arm resource cost.
#   sudo -E env "PATH=$PATH" ./scripts/run-exp-002b.sh [--quick|--repro]
# --repro: full campaign to results/exp-002b-repro-<date>/ — the frozen
#          results/exp-002b/ dir is never overwritten in place (lib/results_dir.sh).
# Arms (identical payload/kernel/1vCPU/128MiB):
#   container      platform netns backend (baseline)
#   microvm-mmio   platform qemu-microvm backend (virtio-mmio)
#   libvirt-q35    platform libvirt backend (virtio-pci, managed)
#   q35-pci        runner QEMU: -M q35 + virtio-net-pci
#   q35-vhost      runner QEMU: -M q35 + virtio-net-pci + vhost=on
#   microvm-pci    runner QEMU: -M microvm,pcie=on + virtio-net-pci
# Decomposition: transport = microvm-pci vs microvm-mmio; machine = q35-pci vs
# microvm-pci; vhost = q35-vhost vs q35-pci; management = libvirt-q35 vs q35-pci.
set -euo pipefail

QUICK=0; REPRO=0
for arg in "$@"; do case "$arg" in
  --quick) QUICK=1 ;;
  --repro) REPRO=1 ;;
  *) echo "error: unknown argument '$arg' (supported: --quick, --repro)" >&2; exit 1 ;;
esac; done
[[ $(id -u) -eq 0 ]] || { echo "error: needs root — sudo -E env \"PATH=\$PATH\" $0" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"; WS="$(dirname "$REPO_DIR")"
VXEDGED="$WS/vxedge/target/debug/vxedged"; VXEDGE="$WS/vxedge/target/debug/vxedge"
VXPROBE="$WS/vxagents/target/debug/vxprobe"; VXTELEMETRY="$WS/vxtelemetry/target/debug/vxtelemetry"
BUNDLE="$WS/vxzones/images/linux-probe/bundle"
for bin in "$VXEDGED" "$VXEDGE" "$VXPROBE" "$VXTELEMETRY"; do
  [[ -x "$bin" ]] || { echo "error: missing $bin" >&2; exit 1; }
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
MANIFEST="$REPO_DIR/experiments/exp-002b-ws"
source "$REPO_DIR/scripts/lib/results_dir.sh"
RESULTS="$(resolve_results_dir "$REPO_DIR" exp-002b "$QUICK" "$REPRO")"
RUNTIME=$(mktemp -d /tmp/exp-002b.XXXXXX); SOCK="$RUNTIME/vxedge.sock"

# arm -> addr | tap (for runner-QEMU arms) | resource-match regex
ARMS=(container microvm-mmio libvirt-q35 q35-pci q35-vhost microvm-pci)
declare -A ADDR=( [container]=10.101.0.11 [microvm-mmio]=10.101.0.12 [libvirt-q35]=10.101.0.13
                  [q35-pci]=10.101.0.14 [q35-vhost]=10.101.0.15 [microvm-pci]=10.101.0.16 )
# Host interface names are derived from the device id (vxedge-core
# gateway::ifnames): `vz-<id>` for the bridge access port, `vzp-<id>` for the
# veth peer, shortened to a readable head plus a hash of the whole id when the
# id does not fit the kernel's 15-byte limit. They are a pure function of the
# device id, so they are stable across runs, reorderings and added devices —
# which is what makes it safe for this script to name them at all. They
# replaced positional `vz0`/`vz1` names on 2026-07-31. To look one up rather
# than recompute it: `vxedge zone list` prints `port=` and `peer=` per device.
declare -A TAP=( [q35-pci]=vz-node-q-691e     # node-q35-pci-01
                 [q35-vhost]=vz-node-q-19a2   # node-q35-vhost-01
                 [microvm-pci]=vz-node-m-ee41 # node-mvm-pci-01
               )
# Match strings verified against actual cmdlines produced by
# vxedge-core::zones::backend: microvm/libvirt carry "vx.node=<node-id>" in
# their kernel -append (NOT the "vx-<node-id>" runtime/pidfile name — those
# differ), so match on the raw node id substring, which is also a substring
# of the runtime name (pidfile/domain name) as a fallback.
declare -A MATCH=(
  [container]="node=vxprobe reflect"
  [microvm-mmio]="node=qemu-system.*node-mvm-mmio-01"
  [libvirt-q35]="node=qemu-system.*node-libvirt-01"
  [q35-pci]="node=qemu-system.*ifname=vz-node-q-691e"
  [q35-vhost]="node=qemu-system.*ifname=vz-node-q-19a2"
  [microvm-pci]="node=qemu-system.*ifname=vz-node-m-ee41"
)

# WARM_S=10 meets the experiment-methodology skill's minimum
# (max(10% of PROBE_S, 10s) = 10s at PROBE_S=60); the quick profile is
# explicitly "not reportable" (pipeline validation only) so it stays short.
if [[ $QUICK -eq 1 ]]; then REPS=1; WARM_S=2; PROBE_S=10; PROBE_PPS=500; PROBE_TIMEOUT_MS=1000
else REPS=5; WARM_S=10; PROBE_S=60; PROBE_PPS=1000; PROBE_TIMEOUT_MS=1000; fi

PIDS=()
cleanup() {
  set +e
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  [[ -n "${TEL_PID:-}" ]] && kill "$TEL_PID" 2>/dev/null
  [[ -n "${SAMP_PID:-}" ]] && kill "$SAMP_PID" 2>/dev/null
  for f in "$RUNTIME"/qemu-*.pid; do [[ -f "$f" ]] && kill "$(cat "$f")" 2>/dev/null; done
  for z in "${DEVICE_OF[@]:-}"; do
    "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "$z" >/dev/null 2>&1
  done
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null 2>&1
  [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null
  ip link del vxup0p.101 2>/dev/null
}
trap cleanup EXIT

launch_qemu() { # $1=arm  — runner-managed QEMU with the arm's exact flags
  local arm="$1" tap="${TAP[$1]}" addr="${ADDR[$1]}"
  local pidfile="$RUNTIME/qemu-$arm.pid" serial="$RUNTIME/qemu-$arm.serial.log"
  local machine="q35" netdev="tap,id=n0,ifname=$tap,script=no,downscript=no"
  local device="virtio-net-pci,netdev=n0"
  # microvm's PCIe root complex is only instantiated when ACPI is enabled
  # (verified on QEMU 8.2.2: acpi=off + pcie=on -> "No 'PCI' bus found for
  # device 'virtio-net-pci'"; default ACPI + pcie=on attaches cleanly) — so
  # this arm keeps ACPI on, unlike the other microvm arm (microvm-mmio,
  # platform-managed, needs no PCI bus and stays ACPI-off for fast boot).
  [[ "$arm" == "microvm-pci" ]] && machine="microvm,pcie=on"
  [[ "$arm" == "q35-vhost"   ]] && netdev="$netdev,vhost=on"
  qemu-system-x86_64 -M "$machine" -enable-kvm -cpu host -m 128m -smp 1 \
    -nodefaults -no-user-config -nographic -monitor none -serial "file:$serial" \
    -kernel "$BUNDLE/vmlinuz" -initrd "$BUNDLE/initrd.img" \
    -append "console=ttyS0 reboot=t panic=-1 quiet vx.ip=$addr/24 vx.node=$arm" \
    -netdev "$netdev" -device "$device" -pidfile "$pidfile" -daemonize
}

env_metadata() { # $1=arm $2=rep
  cat <<EOF
{ "experiment": "exp-002b", "hypothesis": "H3-decomposition",
  "arm": "$1", "repetition": $2,
  "warmup_s": $WARM_S, "probe_window_s": $PROBE_S, "probe_pps": $PROBE_PPS,
  "probe_timeout_ms": $PROBE_TIMEOUT_MS,
  "quick_profile": $QUICK, "kernel": "$(uname -r)",
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
  "timestamping": "userspace-monotonic",
  "isolation": "single-arm",
  "bundle_meta": $(cat "$BUNDLE/meta.json") }
EOF
}

wait_reflector() {
  for _ in $(seq 1 30); do
    "$VXPROBE" send --target "$1:9800" --pps 10 --duration-s 1 --timeout-ms 300 \
      2>/dev/null | grep -q '"received": *[1-9]' && return 0
    sleep 1
  done
  echo "error: reflector at $1 never answered (serial logs in $RUNTIME)" >&2; return 1
}

# Isolation contract (methodology fix, 2026-07-12): exactly ONE guest/container
# node runs at a time. An earlier version brought all six arms up for the
# whole repetition; unpinned concurrent QEMU guests contended for host CPU
# and produced 0-37% packet loss that varied wildly rep-to-rep on the same
# arm — a measurement artifact, not a packaging effect (see run-env "isolation"
# field, added below, for provenance on any archive predating this fix).
# One arm up at a time, addressed by device id (see run-exp-002.sh).
declare -A DEVICE_OF=( [container]=node-cont-01 [microvm-mmio]=node-mvm-mmio-01 [libvirt-q35]=node-libvirt-01 )

start_arm() {
  local arm="$1"
  if [[ -n "${DEVICE_OF[$arm]:-}" ]]; then
    "$VXEDGE" --endpoint "unix://$SOCK" zone up --vxid "${DEVICE_OF[$arm]}" >/dev/null
    if [[ "$arm" == "container" ]]; then
      ip netns exec vx-node-cont-01 "$VXPROBE" reflect --listen 0.0.0.0:9800 &>/dev/null &
      PIDS+=($!)
    fi
  else
    launch_qemu "$arm"
  fi
}

stop_arm() {
  local arm="$1"
  if [[ -n "${DEVICE_OF[$arm]:-}" ]]; then
    if [[ "$arm" == "container" ]]; then
      for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; PIDS=()
    fi
    "$VXEDGE" --endpoint "unix://$SOCK" zone down --vxid "${DEVICE_OF[$arm]}" >/dev/null
  else
    local f="$RUNTIME/qemu-$arm.pid"
    if [[ -f "$f" ]]; then
      local qpid; qpid="$(cat "$f")"
      kill "$qpid" 2>/dev/null || true
      # Wait for the process to actually exit before the next repetition
      # relaunches on the same tap interface and pidfile path.
      for _ in $(seq 1 50); do
        kill -0 "$qpid" 2>/dev/null || break
        sleep 0.1
      done
      rm -f "$f"
    fi
  fi
  sleep 1  # let the port fully release before the next arm claims it
}

echo "== exp-002b: reps=$REPS arms=(${ARMS[*]}) window=${PROBE_S}s pps=$PROBE_PPS [isolated: one arm at a time]"
mkdir -p "$RESULTS"
"$VXEDGED" --listen "unix://$SOCK" --runtime-dir "$RUNTIME" &> "$RUNTIME/vxedged.log" &
DAEMON_PID=$!; sleep 1

for rep in $(seq 1 "$REPS"); do
  echo "-- rep $rep: gateway up"
  "$VXEDGE" --endpoint "unix://$SOCK" up --manifest "$MANIFEST" >/dev/null
  ip link add link vxup0p name vxup0p.101 type vlan id 101
  ip addr add 10.101.0.1/24 dev vxup0p.101
  ip link set vxup0p up && ip link set vxup0p.101 up

  for arm in "${ARMS[@]}"; do
    addr="${ADDR[$arm]}"; tag="rep${rep}-${arm}"
    echo "   $tag: starting (isolated)"
    start_arm "$arm"
    echo "   $tag: waiting for reflector at $addr"
    wait_reflector "$addr"
    INGEST="$RUNTIME/ingest-$tag"; mkdir -p "$INGEST"
    env_metadata "$arm" "$rep" > "$INGEST/run-env.json"
    sleep "$WARM_S"

    "$VXTELEMETRY" ingest --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --interval-s 5 --duration-s "$PROBE_S" &>/dev/null & TEL_PID=$!
    "$VXTELEMETRY" sample --match "${MATCH[$arm]}" --out-dir "$INGEST" \
      --interval-ms 500 --duration-s "$PROBE_S" &>/dev/null & SAMP_PID=$!
    echo "   $tag: probing ${PROBE_S}s @ ${PROBE_PPS}pps (+resource sampling)"
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
    wait "$SAMP_PID" || echo "   $tag: WARNING vxtelemetry sample exited non-zero — archive may be incomplete" >&2

    "$VXTELEMETRY" collect --workspace "$MANIFEST" --ingest-dir "$INGEST" \
      --out "$RESULTS/$tag.zip" >/dev/null
    echo "   $tag: archived ($(jq -r '.rtt_us.p50' "$INGEST/probe-summary.json" 2>/dev/null || echo '?') us p50)"
    stop_arm "$arm"
  done

  ip link del vxup0p.101 2>/dev/null || true
  "$VXEDGE" --endpoint "unix://$SOCK" down --manifest "$MANIFEST" >/dev/null
done

[[ -n "${SUDO_UID:-}" ]] && chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$RESULTS"
echo "== campaign complete: $(ls "$RESULTS"/*.zip | wc -l) archives in $RESULTS"
echo "== analyze: python3 notebooks/analyze_exp002b.py $RESULTS"
