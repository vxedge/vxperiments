#!/usr/bin/env bash
# exp-015: the whole run, as recorded in results/. Every signal-plane check from
# results/signal-plane-2026-11-03, then the kuksa.val.v2 cases in cases-v2.sh, on vx-vehicle-03.
#
#   VXEDGE_BUILD=<dir with vxedge, vxedged, vxcapsule> ./run.sh
#
# Needs a sudo timestamp for `setcap` and `nft list` (sudo -n; podman never runs under sudo), the
# images from ../../vehicles/vx-vehicle-03/build.sh, and localhost/vxperiments/kv2:1 from
# tools/kv2. RUN must stay short: a Unix socket path has a length limit.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ws=$(cd "$here/../../vehicles/vx-vehicle-03" && pwd)
bin=${VXEDGE_BUILD:?set VXEDGE_BUILD}
RUN=${RUN:-/run/user/$(id -u)/vx15}
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
# Pull first, so no case or timed run includes a download.
for img in ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd \
    ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:871649f14576871ca048ed5f4ff2c109656d748877d8ddb8609c67091c9f9c33 \
    ghcr.io/eclipse-kuksa/kuksa-can-provider/can-provider@sha256:41f5abffe30be4dd0bf6d82f28ca149d327e2d6de8619b562a12035a30da0c8e; do
    podman pull -q "$img" >/dev/null || { echo "pull failed: $img"; exit 1; }
done
exec > "$RUN/transcript.txt" 2>&1
sudo -n setcap cap_net_admin,cap_sys_admin+ep "$bin/vxedged" || { echo "setcap failed: no sudo timestamp"; exit 1; }
echo "vxedge $(git -C "$bin/../.." rev-parse --short HEAD 2>/dev/null || echo unknown), vxperiments $(git rev-parse --short HEAD)"
sha256sum vehicle.yaml parts.yaml
podman images --no-trunc --format '{{.Repository}}:{{.Tag}} {{.Digest}}' | grep -E 'localhost/(vxedge|vxperiments)|ghcr.io/vxedge/parts'

h "databroker flags"; "$here/flags.sh"
h ./check-leaks.sh "(clean state)"; ./check-leaks.sh; echo "exit $?"
start
h vxedge vehicle up --manifest .; $V vehicle up --manifest .; echo "exit $?"
h vxedge vehicle status --manifest .; $V vehicle status --manifest .; echo "exit $?"
h "databroker stays running"; sleep 2; podman inspect -f 'running={{.State.Running}} restarts={{.RestartCount}}' vx-hpc1-kuksa-databroker
h ./check-flows.sh; ./check-flows.sh; echo "exit $?"
h ./check-signals.sh "(kuksa.val.v1 CLI)"; ./check-signals.sh; echo "exit $?"
h "$here/cases-v2.sh"; "$here/cases-v2.sh"; echo "exit $?"
h "databroker log"; podman logs vx-hpc1-kuksa-databroker > "$RUN/databroker.log" 2>&1; wc -l < "$RUN/databroker.log"
bash ./snapshot.sh > "$RUN/snap1.txt" 2>&1
h vxedge vehicle up --manifest . "(second)"; $V vehicle up --manifest .; echo "exit $?"
bash ./snapshot.sh > "$RUN/snap2.txt" 2>&1
h "diff of identities before and after the second up"; diff "$RUN/snap1.txt" "$RUN/snap2.txt"; echo "exit $? ($(wc -l < "$RUN/snap1.txt") lines compared)"
wrong() {
    h "wrong vehicle ($1)"
    for verb in status up down; do
        $V vehicle $verb --manifest ../vx-vehicle-01 2>&1 | sed -E 's/.*message: "//; s/"$//; s/ \(workspace [^)]*\)//g' | cut -c1-140
        echo "$verb exit ${PIPESTATUS[0]}"
    done
    bash ./snapshot.sh > "$RUN/snap3.txt" 2>&1; diff "$RUN/snap2.txt" "$RUN/snap3.txt"; echo "unchanged: exit $?"
}
wrong "daemon running"
h "restart vxedged"; stop; start
wrong "after restart"
h vxedge vehicle status --manifest . "(after restart)"; $V vehicle status --manifest .; echo "exit $?"
h vxedge vehicle down --manifest .; $V vehicle down --manifest .; echo "exit $?"
h vxedge vehicle down --manifest . "(again)"; $V vehicle down --manifest . | tail -1; echo "exit ${PIPESTATUS[0]}"
h ./check-leaks.sh; ./check-leaks.sh; echo "exit $?"

h "failed up: a foreign container holds the service's name"
podman create --name vx-hpc1-ota-01 ghcr.io/vxedge/parts/agent/probe/app/vxprobe@sha256:b3f22650146dcae004589d311fcd8f231bd2e058f8cb50a7d2a766519210fd6d >/dev/null
$V vehicle up --manifest . | tail -3; echo "exit ${PIPESTATUS[0]}"
podman rm -f vx-hpc1-ota-01 >/dev/null
h vxedge vehicle down --manifest . "(after the failed up)"; $V vehicle down --manifest . | tail -2; echo "exit ${PIPESTATUS[0]}"
h ./check-leaks.sh; ./check-leaks.sh; echo "exit $?"

h "a databroker that exits straight after starting fails the job"
BAD=$RUN/bad; rm -rf "$BAD"; mkdir -p "$BAD"; cp -a vehicle.yaml parts.yaml bundle ota-store capsule "$BAD/"
sed -i 's#url: ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:[0-9a-f]*#url: ghcr.io/vxedge/parts/svc/ota/app/vxota@sha256:38dc26f33a08dc0af3085e86caa07eb697559200d52c12e3730a7cd2e78e213d#' "$BAD/vehicle.yaml"
grep -q 'url: ghcr.io/vxedge/parts/svc/ota/app/vxota@sha256:38dc26f33a08dc0af3085e86caa07eb697559200d52c12e3730a7cd2e78e213d' "$BAD/vehicle.yaml" && echo "bad image in place" || echo "BAD IMAGE NOT IN PLACE"
$V vehicle up --manifest "$BAD" | tail -2 | cut -c1-160; echo "exit ${PIPESTATUS[0]}"
$V vehicle status --manifest "$BAD" 2>&1 | grep -E 'kuksa|^vehicle' | cut -c1-110
$V vehicle down --manifest "$BAD" | tail -1; echo "exit ${PIPESTATUS[0]}"
h ./check-leaks.sh; ./check-leaks.sh; echo "exit $?"

h "experiment up with a declared signal plane"
X=$RUN/exp; rm -rf "$X"; mkdir -p "$X"; cp -a vehicle.yaml parts.yaml bundle ota-store capsule "$X/"
printf 'id: exp-signal-plane\nversion: 0.1.0\nentry: main.yaml\n' > "$X/exp-signal-plane.vxp"
cat > "$X/main.yaml" <<'Y'
kind: experiment
id: exp-signal-plane
vehicles: [vx-vehicle-03]
baseline: bl-vx-vehicle-03
network:
  slices:
    - { id: adas, mode: vlan, vlan: 100 }
    - { id: infotainment, mode: vlan, vlan: 101 }
Y
(cd "$X" && $V experiment up | tail -2; echo "exit ${PIPESTATUS[0]}")
(cd "$X" && $V experiment status 2>&1 | grep -E "kuksa|experiment|^exp" | cut -c1-110)
podman inspect -f 'member running={{.State.Running}} args={{.Args}}' vx-hpc1-kuksa-databroker
(cd "$X" && $V experiment down | tail -1; echo "exit ${PIPESTATUS[0]}")
h ./check-leaks.sh; ./check-leaks.sh; echo "exit $?"
stop
h "full ruleset, vx lines only"; echo "vx lines: $(sudo -n nft list ruleset | grep -c vx)"
h "audit log, by rpc"
python3 -c "
import json, collections
c = collections.Counter(json.loads(l)['rpc'] for l in open('$RUN/rt/audit.jsonl'))
for k, v in sorted(c.items()): print(f'{v:3} {k}')"
echo EXP-015-FINISHED
