#!/usr/bin/env bash
# exp-017: VSS scenarios on vx-vehicle-03's databroker (bundled VSS 6.0), then VSS 6.1 test-side.
#
#   VXEDGE_BUILD=<dir with vxedge, vxedged, vxcapsule> ./run.sh
#
# Needs a sudo timestamp for `setcap` (sudo -n; podman never runs under sudo), vx-vehicle-03's
# images, and localhost/vxperiments/kv2:1 from ../exp-015/tools/kv2.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ws=$(cd "$here/../../vehicles/vx-vehicle-03" && pwd)
bin=${VXEDGE_BUILD:?set VXEDGE_BUILD}
RUN=${RUN:-/run/user/$(id -u)/vx17}
export RUN
E=unix://$RUN/d.sock
V="$bin/vxedge --endpoint $E"
D=

mkdir -p "$RUN"
start() {
    rm -f "$RUN/d.sock"
    VXEDGE_CAPSULE_BIN=$bin/vxcapsule "$bin/vxedged" --listen "$E" --runtime-dir "$RUN/rt" >>"$RUN/d.log" 2>&1 &
    D=$!
    for _ in $(seq 50); do [ -S "$RUN/d.sock" ] && break; sleep 0.1; done
}
stop() { [ -n "$D" ] && kill "$D" && wait "$D" 2>/dev/null; D=; }
h() { echo; echo "\$ $*"; }

cd "$ws"
exec > >(tee "$RUN/transcript.txt") 2>&1
sudo -n setcap cap_net_admin,cap_sys_admin+ep "$bin/vxedged" || { echo "setcap failed: no sudo timestamp"; exit 1; }
echo "vxedge $(git -C "$bin/../.." rev-parse --short HEAD 2>/dev/null || echo unknown), vxperiments $(git rev-parse --short HEAD)"
sha256sum vehicle.yaml parts.yaml
h ./check-leaks.sh "(clean state)"; ./check-leaks.sh; echo "exit $?"
start
h vxedge vehicle up --manifest .; $V vehicle up --manifest .; echo "exit $?"
h "databroker stays running"; sleep 2; podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}}' vx-hpc1-kuksa-databroker
h "$here/scenarios.sh"; "$here/scenarios.sh"; echo "exit $?"
h vxedge vehicle down --manifest .; $V vehicle down --manifest .; echo "exit $?"
stop
h ./check-leaks.sh; ./check-leaks.sh; echo "exit $?"
h "$here/vss61.sh"; "$here/vss61.sh"; echo "exit $?"
h ./check-leaks.sh "(after the test-side brokers)"; ./check-leaks.sh; echo "exit $?"
echo EXP-017-FINISHED
