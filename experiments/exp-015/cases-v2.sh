#!/usr/bin/env bash
# kuksa.val.v2 cases on a running vx-vehicle-03: subscribers, a signal provider, the CAN feed,
# actuation providers that behave and ones that do not, and denial from another slice. Exits
# non-zero on any failure.
#
# PASS and FAIL lines check what upstream documents or what the case needs to have run. OBS lines
# record what the databroker did where its documentation does not say, so they never fail the run.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

cleanup() { podman rm -f vxt-sub vxt-can vxt-prov vxt-prov2 vxt-sig >/dev/null 2>&1; }
trap cleanup EXIT

echo "kv2: $KV2 $(podman image inspect -f '{{.Id}}' "$KV2" | cut -c1-19)"
echo "can-provider: $CAN"
echo "databroker: $(podman inspect -f '{{.ImageName}}' "$DATABROKER")"
echo "databroker args: $(podman inspect -f '{{.Args}}' "$DATABROKER")"
before=$(broker_state)
echo "databroker state: $before"

healthy() {
    local out
    out=$(kv cabin1 info)
    if [ "$(echo "$out" | verdict info)" = ok ] && [ "$(broker_state)" = "$before" ]; then
        pass "$1: databroker still answers and was not restarted"
    else
        fail "$1: databroker after the case: $(broker_state); info: $out"
    fi
}

h "server info over v2"
out=$(kv cabin1 info); echo "$out" | indent
version=$(echo "$out" | field info version)
if [ "$(echo "$out" | verdict info)" = ok ] && [ "$version" = 0.7.1 ]; then pass "info from cabin1: $version"
else fail "info from cabin1 (version ${version:-none})"; fi

h "publish and get over v2"
out=$(kv cabin1 publish Vehicle.Speed 51.5); echo "$out" | indent
[ "$(echo "$out" | verdict publish)" = ok ] && pass "publish from cabin1" || fail "publish from cabin1"
out=$(kv hpc1 get Vehicle.Speed); echo "$out" | indent
got=$(echo "$out" | field get value)
[ "$got" = 51.5 ] && pass "get from hpc1: $got" || fail "get from hpc1: ${got:-none}"

h "a subscriber sees every published value, in order"
kvbg sub cabin1 subscribe Vehicle.Speed --count 6 --timeout-s 30
until_log sub subscribe open || fail "subscriber did not open"
sleep 0.5
for v in 10 20 30 40 50; do kv hpc1 publish Vehicle.Speed $v >/dev/null; sleep 0.2; done
podman wait vxt-sub >/dev/null
seen=$(podman logs vxt-sub | field update value | tr '\n' ' ')
podman logs vxt-sub | indent
# The first response carries the current value, 51.5.
[ "$seen" = "51.5 10.0 20.0 30.0 40.0 50.0 " ] && pass "subscriber on cabin1 saw: $seen" \
    || fail "subscriber on cabin1 saw: $seen"
podman rm -f vxt-sub >/dev/null

h "a signal provider claims a sensor and publishes on its stream"
kvbg sub hpc1 subscribe Vehicle.Exterior.AirTemperature --count 4 --timeout-s 30
until_log sub subscribe open || fail "subscriber did not open"
out=$(kv cabin1 provide-signal Vehicle.Exterior.AirTemperature --values 18.5,19.5,20.5 --interval-ms 200)
echo "$out" | indent
podman wait vxt-sub >/dev/null
seen=$(podman logs vxt-sub | field update value | tr '\n' ' ')
[ "$(echo "$out" | field published result | sort -u)" = ok ] && pass "provider publishes accepted" \
    || fail "provider publishes: $(echo "$out" | field published errors | tr '\n' ' ')"
case $seen in
    *"18.5 19.5 20.5 ") pass "subscriber on hpc1 saw the provider's values: $seen" ;;
    *) fail "subscriber on hpc1 saw: $seen" ;;
esac
podman rm -f vxt-sub >/dev/null

h "the CAN feed: can-provider replays a dump, a subscriber on hpc1 consumes it"
# can-provider uses kuksa-client 0.6.0: publish over v2 PublishValue, falling back to v1 only if
# v2 is missing. The steering angle has no other writer in this run.
kvbg sub hpc1 subscribe Vehicle.Chassis.SteeringWheel.Angle Vehicle.Speed --count 20 --timeout-s 60
until_log sub subscribe open || fail "subscriber did not open"
podman rm -f vxt-can >/dev/null 2>&1
podman run -d --name vxt-can --network container:vx-cabin1-infra "$CAN" \
    --address "grpc://$BROKER" --dumpfile candump.log --no-infinite >/dev/null
podman wait vxt-sub >/dev/null
podman logs vxt-can 2>&1 | tail -5 | indent
angles=$(podman logs vxt-sub | python3 -c '
import json, sys
n = 0
for line in sys.stdin:
    d = json.loads(line)
    n += d.get("op") == "update" and d.get("path") == "Vehicle.Chassis.SteeringWheel.Angle" and d.get("value") is not None
print(n)')
updates=$(podman logs vxt-sub | field update result | grep -c ok)
[ "$angles" -gt 0 ] && pass "consumer on hpc1 got $updates updates, $angles of them steering angles from the CAN feed" \
    || fail "consumer on hpc1 got no steering angle ($updates updates)"
podman rm -f vxt-sub vxt-can >/dev/null
healthy "CAN feed"

h "actuation with a provider that answers"
kvbg prov cabin1 provide-actuator Vehicle.Body.Trunk.Rear.IsOpen --mode ok --duration-s 30
until_log prov provide ok || fail "provider did not claim"
out=$(kv hpc1 actuate Vehicle.Body.Trunk.Rear.IsOpen true); echo "$out" | indent
[ "$(echo "$out" | verdict actuate)" = ok ] && pass "actuate from hpc1, provider on cabin1" \
    || fail "actuate from hpc1"
podman logs vxt-prov | field actuation-request value | grep -qx true \
    && pass "provider received the request: true" || fail "provider received no request"

h "a second provider for a claimed actuator"
out=$(kv hpc1 provide-actuator Vehicle.Body.Trunk.Rear.IsOpen --duration-s 5); echo "$out" | indent
code=$(echo "$out" | field provide code)
[ "$code" = ALREADY_EXISTS ] && pass "second claim refused: $code" || fail "second claim: ${code:-none}"
podman rm -f vxt-prov >/dev/null

h "actuation with no provider"
out=$(kv hpc1 actuate Vehicle.Body.Trunk.Rear.IsOpen true); echo "$out" | indent
code=$(echo "$out" | field actuate code)
[ "$code" = UNAVAILABLE ] && pass "no provider: $code" || fail "no provider: ${code:-none}"

# Providers that misbehave. Each case must show the request reached the provider, so a case that
# never ran cannot pass, and the databroker must still answer afterwards.
misbehave() {
    local mode=$1 out code
    h "provider mode $mode"
    kvbg prov cabin1 provide-actuator Vehicle.Body.Trunk.Rear.IsOpen --mode "$mode" --duration-s 40
    until_log prov provide ok || fail "$mode: provider did not claim"
    out=$(kv hpc1 actuate Vehicle.Body.Trunk.Rear.IsOpen true --timeout-s 10); echo "$out" | indent
    podman logs vxt-prov | indent
    podman logs vxt-prov | field actuation-request result | grep -qx ok \
        && pass "$mode: the request reached the provider" || fail "$mode: the request never reached the provider"
    code=$(echo "$out" | field actuate code); [ -n "$code" ] || code=$(echo "$out" | field actuate result)
    obs "$mode: actuate returned ${code:-nothing} after $(echo "$out" | field actuate elapsed_ms) ms"
    healthy "$mode"
    podman rm -f vxt-prov >/dev/null
}
misbehave silent
misbehave slow:3000
misbehave error

h "a provider that drops its stream after one answer"
kvbg prov cabin1 provide-actuator Vehicle.Body.Trunk.Rear.IsOpen --mode exit-after:1 --duration-s 30
until_log prov provide ok || fail "exit-after: provider did not claim"
first=$(kv hpc1 actuate Vehicle.Body.Trunk.Rear.IsOpen true)
until_log prov provide dropped || fail "exit-after: provider did not drop"
sleep 1
second=$(kv hpc1 actuate Vehicle.Body.Trunk.Rear.IsOpen false)
echo "$first" | indent; echo "$second" | indent
[ "$(echo "$first" | verdict actuate)" = ok ] && pass "exit-after: first actuate ok" || fail "exit-after: first actuate"
code=$(echo "$second" | field actuate code)
[ "$code" = UNAVAILABLE ] && pass "exit-after: after the drop: $code" || fail "exit-after: after the drop: ${code:-none}"
podman rm -f vxt-prov >/dev/null
kvbg prov2 cabin1 provide-actuator Vehicle.Body.Trunk.Rear.IsOpen --mode ok --duration-s 10
until_log prov2 provide ok && pass "a new provider claims the released actuator" \
    || fail "the actuator stayed claimed after its provider dropped"
podman rm -f vxt-prov2 >/dev/null
healthy "exit-after"

h "the client's own refusal, on the allowed slice"
out=$(BROKER=10.100.0.50:55556 kv cabin1 --connect-s 3 info); echo "$out" | indent
[ "$(echo "$out" | verdict info)" = refused ] && pass "wrong port from cabin1 reads as refused" \
    || fail "wrong port from cabin1 read as $(echo "$out" | verdict info)"

h "denied over v2: zone-rl on infotainment"
kv cabin1 publish Vehicle.Speed 61.5 >/dev/null
denied() {
    local before after out v
    before=$(rx_packets zone-rl)
    out=$(kv zone-rl --connect-s 5 "$@")
    after=$(rx_packets zone-rl)
    v=$(echo "$out" | verdict "$1")
    echo "$out" | indent
    if [ "$v" = ok ]; then fail "denied zone-rl: $* (crossed the slice)"
    elif [ "$v" != refused ]; then fail "denied zone-rl: $* (read as $v)"
    elif [ $((after - before)) -eq 0 ]; then fail "denied zone-rl: $* (no frames reached the bridge)"
    else pass "denied zone-rl: $* (client refused, $((after - before)) frames reached the bridge)"; fi
}
denied publish Vehicle.Speed 99
denied get Vehicle.Speed
denied subscribe Vehicle.Speed --count 1
out=$(kv cabin1 get Vehicle.Speed); got=$(echo "$out" | field get value)
[ "$got" = 61.5 ] && pass "value after the denied write: $got" || fail "value after the denied write: ${got:-none}"

echo "bridge VLAN membership:"
bridge -j vlan show | python3 -c '
import json, sys
for port in json.load(sys.stdin):
    if port["ifname"] in ("vz-hpc1", "vz-cabin1", "vz-zone-rl"):
        print("  " + port["ifname"], [v["vlan"] for v in port["vlans"]])'
echo "databroker state at the end: $(broker_state)"
exit "$failures"
