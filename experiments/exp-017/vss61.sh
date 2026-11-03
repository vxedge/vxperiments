#!/usr/bin/env bash
# VSS 6.1 against kuksa-databroker 0.7.1, test-side: throwaway rootless brokers named vxt-vss60 and
# vxt-vss61, no vehicle. 0.7.1 bundles VSS 6.0 and 5.1 only, and the signal plane's config carries
# `listen` alone, so 6.1 cannot reach the vehicle's broker without a vxedge change.
#
# PASS and FAIL check that each broker loads its file, lists every signal in it with the file's
# types, and that 6.1's added and removed signals behave as added and removed. OBS lines record the
# rest. Exits non-zero on any failure.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../exp-015/lib.sh"
RUN=${RUN:-/run/user/$(id -u)/vx17}
B=ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd
VSS61_URL=https://github.com/COVESA/vehicle_signal_specification/releases/download/v6.1/vss.json
VSS61_SHA=bef9ad501b38edd60e7b903cb39ba5b8f0864a984595b3e901d6efa3f06bdb70
VSS60_URL=https://raw.githubusercontent.com/eclipse-kuksa/kuksa-databroker/0.7.1/data/vss-core/vss_release_6.0.json
VSS60_SHA=de12e86c96585124140adde847951d0006295a944d6e5fbc338fe0c1babd90d4
VSS60_RELEASE_URL=https://github.com/COVESA/vehicle_signal_specification/releases/download/v6.0/vss.json
VSS60_RELEASE_SHA=b77785180dbe7fc674e4965ab9c1c58dcc97433867cf4abf4e3f78c013550e78

cleanup() { podman rm -f vxt-vss60 vxt-vss61 vxt-can >/dev/null 2>&1; }
trap cleanup EXIT
mkdir -p "$RUN"

fetch() {
    curl -sfL "$1" -o "$RUN/$2" && echo "$3  $RUN/$2" | sha256sum -c --quiet && echo "$2: $3" \
        || { fail "fetch $2 from $1"; exit 1; }
}
h "files"
fetch "$VSS61_URL" vss-6.1.json "$VSS61_SHA"
fetch "$VSS60_URL" vss-6.0-bundled.json "$VSS60_SHA"
fetch "$VSS60_RELEASE_URL" vss-6.0-release.json "$VSS60_RELEASE_SHA"

# kvb <broker> <kv2 args...>: kv2 in a throwaway broker's namespace.
kvb() {
    local b=$1
    shift
    timeout 60 podman run --rm --network "container:$b" "$KV2" --server 127.0.0.1:55555 "$@" 2>&1
}
broker() {
    local name=$1
    shift
    podman rm -f "$name" >/dev/null 2>&1
    podman run -d --name "$name" "$@" >/dev/null
    sleep 2
    if [ "$(podman inspect -f '{{.State.Running}}' "$name")" = true ]; then pass "$name running after 2 s"
    else fail "$name exited: $(podman logs "$name" 2>&1 | tail -3)"; fi
    podman logs "$name" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'metadata|warn|error' | cut -c1-140 | indent
}

h "control: the bundled 6.0 file"
broker vxt-vss60 "$B" --insecure
kvb vxt-vss60 list Vehicle > "$RUN/list-6.0.txt"
python3 -I "$here/compare.py" "$RUN/vss-6.0-bundled.json" "$RUN/list-6.0.txt" | indent
[ "${PIPESTATUS[0]}" -eq 0 ] && pass "6.0 broker lists the bundled file exactly" || fail "6.0 broker and the bundled file differ"
h "the bundled 6.0 file against the COVESA v6.0 release"
python3 -I "$here/compare.py" "$RUN/vss-6.0-release.json" "$RUN/list-6.0.txt" | indent
obs "bundled 6.0 against the v6.0 release: exit ${PIPESTATUS[0]} (non-zero means they differ, listed above)"

h "VSS 6.1, mounted as a separate file"
broker vxt-vss61 -v "$RUN/vss-6.1.json:/vss/vss-6.1.json:ro" "$B" --insecure --vss /vss/vss-6.1.json
kvb vxt-vss61 list Vehicle > "$RUN/list-6.1.txt"
python3 -I "$here/compare.py" "$RUN/vss-6.1.json" "$RUN/list-6.1.txt" | indent
[ "${PIPESTATUS[0]}" -eq 0 ] && pass "6.1 broker lists the 6.1 file exactly" || fail "6.1 broker and the 6.1 file differ"

h "6.1: added and removed signals"
out=$(kvb vxt-vss61 publish Vehicle.Cabin.AirQuality.CO2 650); echo "$out" | indent
[ "$(echo "$out" | verdict publish)" = ok ] && pass "added in 6.1: publish Vehicle.Cabin.AirQuality.CO2" \
    || fail "added in 6.1: publish Vehicle.Cabin.AirQuality.CO2"
out=$(kvb vxt-vss61 get Vehicle.Powertrain.ElectricMotor.Power); echo "$out" | indent
code=$(echo "$out" | field get code)
[ "$code" = NOT_FOUND ] && pass "removed in 6.1: Vehicle.Powertrain.ElectricMotor.Power is $code" \
    || fail "removed in 6.1: Vehicle.Powertrain.ElectricMotor.Power is ${code:-found}"
out=$(kvb vxt-vss61 metadata Vehicle.Powertrain.ElectricMotor.Front.Power); echo "$out" | indent
[ "$(echo "$out" | verdict metadata)" = ok ] && pass "its 6.1 instance, ElectricMotor.Front.Power, exists" \
    || fail "ElectricMotor.Front.Power"

h "6.1's new enum key"
# Vehicle.Exterior.PrecipitationType is uint8 with an `enum` map of 0..5 and no min, max or allowed.
kvb vxt-vss61 metadata Vehicle.Exterior.PrecipitationType | indent
for v in 2 200; do
    out=$(kvb vxt-vss61 publish Vehicle.Exterior.PrecipitationType $v)
    obs "publish Vehicle.Exterior.PrecipitationType = $v (enum 0..5): $(echo "$out" | field publish result) $(echo "$out" | field publish code)"
done

h "can-provider 0.5.1's newest mapping, vss_6.0, against the 6.1 broker"
podman run -d --name vxt-can --network container:vxt-vss61 "$CAN" \
    --address grpc://127.0.0.1:55555 --dumpfile candump.log --no-infinite >/dev/null
sleep 15
podman logs vxt-can 2>&1 | grep -iE 'error|warn|not found|ElectricMotor' | sort | uniq -c | sort -rn | head -10 | indent
for p in Vehicle.Speed Vehicle.Powertrain.ElectricMotor.Front.Power; do
    obs "after the replay, $p = $(kvb vxt-vss61 get $p | field get value)"
done
exit "$failures"
