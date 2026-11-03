#!/usr/bin/env bash
# exp-016: kuksa-perf against the databroker on hpc1, in three setups, on this folder's vehicle.
#
#   VXEDGE_BUILD=<dir with vxedge, vxedged, vxcapsule> ./run.sh
#
# Setups, all with the broker on hpc1 (adas):
#   baseline  kuksa-perf in hpc1's own network namespace, no load. Never touches the bridge.
#   idle      kuksa-perf in cabin1, on the broker's slice, no load
#   loaded    as idle, with vxtraffic sending from zone-rl to info2 on infotainment
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
PERF=${PERF:-ghcr.io/eclipse-kuksa/kuksa-databroker-perf@sha256:74ad5bb003e2f541cf9862ba63cecf66cd93badb514f1c6c8b68bcaac29ffd93}
PERF_MAIN=${PERF_MAIN:-localhost/vxperiments/kuksa-perf:aa6fba0}
LOAD=localhost/vxperiments/vxtraffic:1
BROKER_HOST=10.100.0.50
E=unix://$RUN/d.sock
V="$bin/vxedge --endpoint $E"
D=

if pgrep -x vxedged >/dev/null; then
    echo "another vxedged is running: $(pgrep -a -x vxedged | cut -c1-120)"
    exit 1
fi
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
cleanup() { podman rm -f vxt-load vxt-perf >/dev/null 2>&1; }
trap cleanup EXIT

cd "$here"
# Pull first, so no case or timed run includes a download.
for img in ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd "$PERF"; do
    podman pull -q "$img" >/dev/null || { echo "pull failed: $img"; exit 1; }
done
exec > "$RUN/transcript.txt" 2>&1
sudo -n setcap cap_net_admin,cap_sys_admin+ep "$bin/vxedged" || { echo "setcap failed: no sudo timestamp"; exit 1; }
echo "vxedge $(git -C "$bin/../.." rev-parse --short HEAD 2>/dev/null || echo unknown), vxperiments $(git rev-parse --short HEAD)"
sha256sum vehicle.yaml parts.yaml data/*.json
echo "kuksa-perf, publish runs: $PERF"
echo "kuksa-perf, actuate runs: $PERF_MAIN $(podman image inspect -f '{{.Id}}' "$PERF_MAIN" | cut -c1-19)"
echo "load: $LOAD $(podman image inspect -f '{{.Id}}' "$LOAD" | cut -c1-19), $LOAD_MBPS mbit/s"
echo "reps $REPS, duration ${DURATION}s, skip ${SKIP}s"
podman images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | grep -E 'localhost/(vxedge|vxperiments)'

h ../../vehicles/vx-vehicle-03/check-leaks.sh "(clean state)"; ../../vehicles/vx-vehicle-03/check-leaks.sh; echo "exit $?"
start
h vxedge vehicle up --manifest .; $V vehicle up --manifest .; echo "exit $?"
h vxedge vehicle status --manifest .; $V vehicle status --manifest .; echo "exit $?"
h "databroker stays running"; sleep 2
podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}} image={{.ImageName}} args={{.Args}}' vx-hpc1-kuksa-databroker

# perf <node> <image> <out> <args...>: one kuksa-perf run in a node's namespace.
perf() {
    local node=$1 image=$2 out=$3
    shift 3
    podman rm -f vxt-perf >/dev/null 2>&1
    timeout $((DURATION + 60)) podman run --rm --name vxt-perf --network "container:vx-$node-infra" \
        -v "$here/data:/data:ro" "$image" --api kuksa.val.v2 --host "http://$BROKER_HOST" --port 55555 \
        --duration "$DURATION" --skip-seconds "$SKIP" "$@" >"$RUN/out/$out.txt" 2>&1
    echo "exit $? $out: $(grep -E '50% in under|Received:' "$RUN/out/$out.txt" | tr -s ' ' | tr '\n' ' ')"
}

h "the broker is not reachable from infotainment"
before=$(ifstat info2 rx)
DURATION=3 SKIP=0 perf info2 "$PERF" denied-info2 --test-data-file /data/publish-1.json
echo "frames from info2 reaching the bridge: $(( $(ifstat info2 rx) - before ))"
grep -iE 'error|fail|refused|connect' "$RUN/out/denied-info2.txt" | head -3

load_on() {
    podman rm -f vxt-load >/dev/null 2>&1
    podman run -d --name vxt-load --network container:vx-zone-rl-infra "$LOAD" \
        --target 10.100.0.32:9999 --bandwidth-mbps "$LOAD_MBPS" --duration-s $((DURATION + 30)) >/dev/null
    sleep 2
}
load_off() { podman rm -f vxt-load >/dev/null 2>&1; }

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
    esac
}
orders=("baseline idle loaded" "idle loaded baseline" "loaded baseline idle")
for op in publish actuate; do
    h "$op, three setups, $REPS repetitions"
    for rep in $(seq "$REPS"); do
        for name in ${orders[$(((rep - 1) % 3))]}; do setup "$name" "$op" "$rep"; done
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
h "summary"; python3 -I "$here/summarize.py" "$RUN/out"
echo EXP-016-FINISHED
