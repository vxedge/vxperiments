#!/usr/bin/env bash
# exp-001 through vxAPI: the probe is a declared `measurements` entry run by MeasurementService, and
# the load is `traffic_profiles.infotainment-load` run by TrafficService inside its node. Same
# protocol as run.sh --repro: 5 repetitions of loads 0, 100, 250, 400 and 600 mbit/s, 10 s of load
# before a 60 s probe window at 1000 pps, the gateway and zones brought up and down per point.
#
#   VXEDGE_BUILD=<dir with vxedge, vxedged> VXAGENTS_BUILD=<dir with vxprobe, vxtraffic> \
#     ./scripts/run-measurements.sh <out-dir>
#
# Needs vxedged with cap_net_admin and cap_sys_admin (setcap, see the vxedge README) and the
# `performance` CPU governor set beforehand, as run.sh sets it. Writes one vxprobe summary per point
# (`rep<r>-load<l>.summary.json`) and a transcript. ../../notebooks/compare_exp001_paths.py compares
# them with run.sh's archives.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
bin=${VXEDGE_BUILD:?set VXEDGE_BUILD}; agents=${VXAGENTS_BUILD:?set VXAGENTS_BUILD}
O=${1:?out dir}; mkdir -p "$O"; O=$(cd "$O" && pwd)
REPS=${REPS:-5}; read -r -a LOADS <<< "${LOADS:-0 100 250 400 600}"; WARMUP_S=10; PROBE_S=60
RUN=${RUN:-/run/user/$(id -u)/exp-001m}; W=$RUN/ws; E=unix://$RUN/d.sock; V="$bin/vxedge --endpoint $E"
exec >> "$O/transcript.txt" 2>&1
echo "== exp-001 through measurements $(date -Is) reps=$REPS loads=(${LOADS[*]}) kernel=$(uname -r) governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
rm -rf "$RUN"; mkdir -p "$W"
cp -a "$here/main.yaml" "$here/vehicle.yaml" "$here/parts.yaml" "$here/exp-001.vxp" "$here/parts" "$here/assets" "$W/"
python3 - "$W/main.yaml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("method:\n  duration_s: 60", "method:\n  duration_s: 74   # the load's window: warmup + probe + 4, as run.sh")
s += "\nmeasurements:\n  ctl-rtt: { kind: rtt-probe, from: node-adas-probe-01, to: internet, slice: adas, rate_pps: 1000 }\n"
open(p, "w").write(s)
PY
"$bin/vxedged" --listen "$E" --runtime-dir "$RUN/rt" --vxprobe-bin "$agents/vxprobe" --vxtraffic-bin "$agents/vxtraffic" >> "$O/vxedged.log" 2>&1 &
D=$!
trap 'kill $D 2>/dev/null' EXIT
for _ in $(seq 50); do [ -S "$RUN/d.sock" ] && break; sleep 0.1; done
cd "$W" || exit 1
for rep in $(seq 1 "$REPS"); do for load in "${LOADS[@]}"; do
  tag=rep$rep-load$load
  sed -i -E "s/^(    bandwidth_mbps: )[0-9]+/\1$([ "$load" = 0 ] && echo 400 || echo "$load")/" main.yaml
  $V experiment up --unlocked --stage gateway --stage zones > /dev/null || echo "$tag: up failed"
  [ "$load" != 0 ] && { $V traffic up --manifest . > /dev/null || echo "$tag: traffic up failed"; }
  sleep $WARMUP_S
  $V measure start --duration-s $PROBE_S > /dev/null || echo "$tag: measure start failed"
  for _ in $(seq 90); do $V measure status 2>/dev/null | grep -q running || break; sleep 1; done
  cp "$RUN/rt/measure-ctl-rtt.summary.json" "$O/$tag.summary.json"
  info=$(curl -s 127.0.0.1:9469/metrics | grep vxedge_slice_sent_bytes_total | grep infotainment | awk '{print $2}')
  $V measure stop > /dev/null; [ "$load" != 0 ] && $V traffic down --manifest . > /dev/null
  $V experiment down --stage zones --stage gateway > /dev/null
  echo "$tag: infotainment slice sent ${info:-?} bytes"
done; done
echo "== done $(date -Is)"
