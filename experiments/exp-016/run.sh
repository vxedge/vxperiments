#!/usr/bin/env bash
# exp-016: kuksa-perf against the databroker on hpc1, in three setups, on this folder's vehicle.
#
#   VXEDGE_BUILD=<dir with vxedge, vxedged, vxcapsule> ./run.sh
#
# Setups, all with the broker on hpc1 (adas):
#   baseline  kuksa-perf in hpc1's own network namespace, no load. Never touches the bridge.
#   idle      kuksa-perf in cabin1, on the broker's slice, no load
#   loaded    as idle, with vxtraffic sending from zone-rl to info2 on infotainment
#   cpu       as idle, with two busy loops in a container with no network: CPU load without traffic,
#             so loaded minus cpu is the traffic's share and cpu minus idle the CPU's
# The CPU governor is pinned to performance and /dev/cpu_dma_latency held at 2 us for the whole
# run, both released at the end: under powersave, a busy host answered faster than an idle one,
# which measured CPU wake-up, not the slice, and the governor pin alone did not stop deep sleep.
# The order rotates every repetition. Each run crosses the slice both ways (kuksa-perf's sender and
# receiver share one process), so a number here is never a one-way latency.
#
# Needs a sudo timestamp for `setcap` and `nft list` (sudo -n; podman never runs under sudo) and
# ./build.sh's images. Refuses to start while any other vxedged runs: this is a measurement.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${VXEDGE_BUILD:?set VXEDGE_BUILD}
RUN=${RUN:-/run/user/$(id -u)/vx16}
REPS=${REPS:-5}
DURATION=${DURATION:-30}
SKIP=${SKIP:-5}
LOAD_MBPS=${LOAD_MBPS:-600}
PERF_RELEASE=ghcr.io/eclipse-kuksa/kuksa-databroker-perf@sha256:74ad5bb003e2f541cf9862ba63cecf66cd93badb514f1c6c8b68bcaac29ffd93
PERF_MAIN=${PERF_MAIN:-localhost/vxperiments/kuksa-perf:aa6fba0}
# Publish runs use PERF: the build of aa6fba0 unless set, because 0.3.2 cannot publish to 0.7.1.
PERF=${PERF:-$PERF_MAIN}
LOAD=localhost/vxperiments/vxtraffic:1
BROKER_HOST=10.100.0.50
E=unix://$RUN/d.sock
V="$bin/vxedge --endpoint $E"
D=

if pgrep -x vxedged >/dev/null; then
    echo "another vxedged is running: $(pgrep -a -x vxedged | cut -c1-120)"
    exit 1
fi
# A fresh out/ each run, so no earlier run's output is summarised with this one.
rm -rf "${RUN:?}/out"
mkdir -p "$RUN/out"
start() {
    rm -f "$RUN/d.sock"
    VXEDGE_CAPSULE_BIN=$bin/vxcapsule "$bin/vxedged" --listen "$E" --runtime-dir "$RUN/rt" >>"$RUN/d.log" 2>&1 &
    D=$!
    for _ in $(seq 50); do [ -S "$RUN/d.sock" ] && break; sleep 0.1; done
}
stop() { [ -n "$D" ] && kill "$D" && wait "$D" 2>/dev/null; D=; }
h() { echo; echo "\$ $*"; }
ifstat() { ip -s -j link show "vz-$1" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['stats64']['$2']['packets'])"; }
. "$here/../../scripts/lib/host_pinning.sh"
# Holds /dev/cpu_dma_latency at LATENCY_US for the whole run, so no CPU enters an idle state that
# takes longer to leave; shallow states stay allowed. The hold lasts while the file is open.
LATENCY_US=${LATENCY_US:-2}
HOLD=
hold_cpu_latency() {
    sudo -n python3 -I -c 'import os, signal, struct, sys
f = os.open("/dev/cpu_dma_latency", os.O_WRONLY)
os.write(f, struct.pack("i", int(sys.argv[1])))
signal.pause()' "$LATENCY_US" &
    HOLD=$!
    sleep 1
    kill -0 "$HOLD" 2>/dev/null || { echo "cpu latency hold failed"; HOLD=; return 1; }
}
release_cpu_latency() { [ -n "$HOLD" ] && kill "$HOLD" 2>/dev/null && wait "$HOLD" 2>/dev/null; HOLD=; }
# Keeps this terminal's sudo timestamp fresh, so the restore at the end never waits on a password.
KEEP=
cleanup() {
    podman rm -f -t 0 vxt-load vxt-perf vxt-cpu >/dev/null 2>&1
    release_cpu_latency
    restore_cpu_governors
    echo "cpu governors after the run:$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c | tr -s ' ')"
    [ -n "$KEEP" ] && kill "$KEEP" 2>/dev/null
}
trap cleanup EXIT

cd "$here"
# Pull first, so no case or timed run includes a download.
for img in ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd "$PERF_RELEASE"; do
    podman pull -q "$img" >/dev/null || { echo "pull failed: $img"; exit 1; }
done
exec > "$RUN/transcript.txt" 2>&1
sudo -n setcap cap_net_admin,cap_sys_admin+ep "$bin/vxedged" || { echo "setcap failed: no sudo timestamp"; exit 1; }
( while sleep 60; do sudo -n -v; done ) >/dev/null 2>&1 &
KEEP=$!
pin_cpu_governor_performance
govs=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c | tr -s ' ')
echo "cpu governors during the run:$govs"
echo "cpu idle states: $(for d in /sys/devices/system/cpu/cpu0/cpuidle/state*; do printf '%s(%sus) ' "$(cat $d/name)" "$(cat $d/latency)"; done)"
[ "$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u)" = performance ] || { echo "governor not pinned"; exit 1; }
hold_cpu_latency || exit 1
echo "cpu latency held at ${LATENCY_US} us for the run (pid $HOLD): idle states slower to leave are not entered"
echo "vxedge $(git -C "$bin/../.." rev-parse --short HEAD 2>/dev/null || echo unknown), vxperiments $(git rev-parse --short HEAD)"
sha256sum vehicle.yaml parts.yaml data/*.json
echo "kuksa-perf, publish runs: $PERF $(podman image inspect -f '{{.Id}}' "$PERF" | cut -c1-19)"
echo "kuksa-perf release, recorded only: $PERF_RELEASE"
echo "kuksa-perf, actuate runs: $PERF_MAIN $(podman image inspect -f '{{.Id}}' "$PERF_MAIN" | cut -c1-19)"
echo "load: $LOAD $(podman image inspect -f '{{.Id}}' "$LOAD" | cut -c1-19), $LOAD_MBPS mbit/s"
echo "reps $REPS, duration ${DURATION}s, skip ${SKIP}s"
podman images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | grep -E 'localhost/(vxedge|vxperiments)'

h ../../vehicles/vx-vehicle-03/check-leaks.sh "(clean state)"; ../../vehicles/vx-vehicle-03/check-leaks.sh; echo "exit $?"
start
h vxedge vehicle up --manifest .; $V vehicle up --manifest .; rc=$?; echo "exit $rc"
# Nothing below measures anything without the vehicle: stop here, after taking it down.
if [ "$rc" -ne 0 ]; then
    $V vehicle down --manifest . >/dev/null 2>&1; stop
    echo "EXP-016-ABORTED: vehicle up failed"; exit 1
fi
h vxedge vehicle status --manifest .; $V vehicle status --manifest .; echo "exit $?"
h "databroker stays running"; sleep 2
podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}} image={{.ImageName}} args={{.Args}}' vx-hpc1-kuksa-databroker

# Time all CPUs spent in idle states with an exit latency of 10 us or more, in ms. Governor
# pinning does not stop these sleeps, so each run records how much of it the CPUs spent there.
deep_idle_ms() {
    python3 -c '
import glob
t = 0
for s in glob.glob("/sys/devices/system/cpu/cpu*/cpuidle/state*"):
    if int(open(s + "/latency").read()) >= 10:
        t += int(open(s + "/time").read())
print(t // 1000)'
}

# perf <node> <image> <out> <args...>: one kuksa-perf run in a node's namespace.
perf() {
    local node=$1 image=$2 out=$3
    shift 3
    podman rm -f -t 0 vxt-perf >/dev/null 2>&1
    local idle0
    idle0=$(deep_idle_ms)
    timeout $((DURATION + 60)) podman run --rm --name vxt-perf --network "container:vx-$node-infra" \
        -v "$here/data:/data:ro" "$image" --api kuksa.val.v2 --host "http://$BROKER_HOST" --port 55555 \
        --duration "$DURATION" --skip-seconds "$SKIP" "$@" >"$RUN/out/$out.txt" 2>&1
    local rc=$?
    echo "deep idle: $(( $(deep_idle_ms) - idle0 )) ms across all CPUs" >>"$RUN/out/$out.txt"
    echo "exit $rc $out: $(grep -E '50% in under|Received:|deep idle' "$RUN/out/$out.txt" | tr -s ' ' | tr '\n' ' ')"
    # The databroker releases a finished run's claims on its own sweep, about a second later; a
    # run started sooner finds its signals still claimed and sends nothing.
    sleep 3
}

h "the released kuksa-perf, 0.3.2, against databroker 0.7.1 over kuksa.val.v2"
# Recorded, not used for results: its v2 provider publishes without claiming the signals, which
# 0.7.1 aborts, and it exits 0 having sent nothing.
DURATION=5 SKIP=0 perf hpc1 "$PERF_RELEASE" release-0.3.2 --test-data-file /data/publish-1.json
grep -E 'Sent:|Received:|50% in under' "$RUN/out/release-0.3.2.txt" | tr -s ' ' | sed 's/^/  /'

h "the broker is not reachable from infotainment"
before=$(ifstat info2 rx)
DURATION=3 SKIP=0 perf info2 "$PERF" denied-info2 --test-data-file /data/publish-1.json
echo "frames from info2 reaching the bridge: $(( $(ifstat info2 rx) - before ))"
grep -iE 'error|fail|refused|connect' "$RUN/out/denied-info2.txt" | head -3

load_on() {
    podman rm -f -t 0 vxt-load >/dev/null 2>&1
    podman run -d --name vxt-load --network container:vx-zone-rl-infra "$LOAD" \
        --target 10.100.0.32:9999 --bandwidth-mbps "$LOAD_MBPS" --duration-s $((DURATION + 30)) >/dev/null
    sleep 2
}
load_off() { podman rm -f -t 0 vxt-load >/dev/null 2>&1; }
cpu_on() {
    podman rm -f -t 0 vxt-cpu >/dev/null 2>&1
    podman run -d --init --name vxt-cpu --network none --entrypoint sh "$PERF_MAIN" \
        -c 'yes >/dev/null & yes >/dev/null & wait' >/dev/null
    sleep 2
    [ "$(podman inspect -f '{{.State.Running}}' vxt-cpu)" = true ] || echo "CPU LOAD NOT RUNNING"
}
cpu_off() { podman rm -f -t 0 vxt-cpu >/dev/null 2>&1; }

# The load reaches info2 and stays on infotainment: delivered frames counted at info2's port, and
# what reached the adas ports in the same window.
h "load check"
for p in zone-rl info2 hpc1 cabin1; do eval "b_${p//-/_}_rx=$(ifstat $p rx) b_${p//-/_}_tx=$(ifstat $p tx)"; done
load_on; sleep 5
for p in zone-rl info2 hpc1 cabin1; do eval "a_${p//-/_}_rx=$(ifstat $p rx) a_${p//-/_}_tx=$(ifstat $p tx)"; done
load_off
echo "in 7 s: zone-rl sent $((a_zone_rl_rx - b_zone_rl_rx)), info2 received $((a_info2_tx - b_info2_tx)), hpc1 received $((a_hpc1_tx - b_hpc1_tx)), cabin1 received $((a_cabin1_tx - b_cabin1_tx)) frames"

setup() {
    local name=$1 op=$2 rep=$3 image data
    case $op in
        publish) image=$PERF data=(--test-data-file /data/publish-1.json) ;;
        actuate) image=$PERF_MAIN data=(--operation actuate --test-data-file /data/actuate-g1-k1.json) ;;
    esac
    case $name in
        baseline) perf hpc1 "$image" "$op-baseline-$rep" "${data[@]}" ;;
        idle) perf cabin1 "$image" "$op-idle-$rep" "${data[@]}" ;;
        loaded) load_on; perf cabin1 "$image" "$op-loaded-$rep" "${data[@]}"; load_off ;;
        cpu) cpu_on; perf cabin1 "$image" "$op-cpu-$rep" "${data[@]}"; cpu_off ;;
    esac
}
orders=("baseline idle loaded cpu" "idle loaded cpu baseline" "loaded cpu baseline idle" "cpu baseline idle loaded")
for op in publish actuate; do
    h "$op, three setups, $REPS repetitions"
    for rep in $(seq "$REPS"); do
        for name in ${orders[$(((rep - 1) % 4))]}; do setup "$name" "$op" "$rep"; done
    done
done

h "issue 233 data: actuate on the broker's device, providers by actuator ids"
for f in g1-k1 g1-k240 g16-k1 g16-k15; do
    for rep in 1 2 3; do perf hpc1 "$PERF_MAIN" "scale-$f-$rep" --operation actuate --test-data-file "/data/actuate-$f.json"; done
done

h "databroker after the runs"
podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}}' vx-hpc1-kuksa-databroker
podman logs vx-hpc1-kuksa-databroker > "$RUN/databroker.log" 2>&1; grep -ciE 'error|warn' "$RUN/databroker.log"
h vxedge vehicle down --manifest .; $V vehicle down --manifest .; echo "exit $?"
stop
h ../../vehicles/vx-vehicle-03/check-leaks.sh; ../../vehicles/vx-vehicle-03/check-leaks.sh; echo "exit $?"
h "summary"; python3 -I "$here/summarize.py" "$RUN/out"; rc=$?
echo EXP-016-FINISHED
exit $rc
