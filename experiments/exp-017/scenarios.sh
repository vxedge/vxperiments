#!/usr/bin/env bash
# SDV scenarios on the VSS 6.0 metadata bundled in the databroker, on a running vx-vehicle-03.
# Each scenario is a function on cabin1 (sensor feed or actuator provider) and a consumer on hpc1,
# both on adas. Exits non-zero on any failure.
#
# PASS and FAIL check what kuksa.val.v2 documents: INVALID_ARGUMENT for a value of the wrong type,
# outside min/max, not in the allowed list, or an actuation of a non-actuator. OBS lines record
# what it does where the documentation does not say.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../exp-015/lib.sh"

cleanup() { podman rm -f vxt-sub vxt-prov >/dev/null 2>&1; }
trap cleanup EXIT

echo "kv2: $KV2 $(podman image inspect -f '{{.Id}}' "$KV2" | cut -c1-19)"
echo "databroker: $(podman inspect -f '{{.ImageName}}' "$DATABROKER")"
echo "metadata: $(podman inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DATABROKER" | grep METADATA)"

expect_meta() {
    local path=$1 want=$2 out got
    out=$(kv cabin1 metadata "$path")
    got=$(echo "$out" | python3 -c 'import json,sys
d=json.loads(sys.stdin.readlines()[-1]); print(d.get("entry_type","?"), d.get("data_type","?"), d.get("unit") or "-", d.get("min"), d.get("max"), d.get("allowed"))')
    [ "$got" = "$want" ] && pass "metadata $path: $got" || fail "metadata $path: $got, want $want"
}
publish_ok() {
    local out
    out=$(kv cabin1 publish "$1" "$2"); echo "$out" | indent
    [ "$(echo "$out" | verdict publish)" = ok ] && pass "publish $1 = $2" || fail "publish $1 = $2"
}
get_is() {
    local got
    got=$(kv hpc1 get "$1" | field get value)
    [ "$got" = "$2" ] && pass "hpc1 reads $1 = $got" || fail "hpc1 reads $1 = ${got:-none}, want $2"
}
# rejected <op> <path> <value> [kv2 options]: documented INVALID_ARGUMENT.
rejected() {
    local op=$1 path=$2 value=$3 out code
    shift 3
    out=$(kv hpc1 "$op" "$path" "$value" "$@"); echo "$out" | indent
    code=$(echo "$out" | field "$op" code)
    [ "$code" = INVALID_ARGUMENT ] && pass "$op $path = $value $*: $code" || fail "$op $path = $value $*: ${code:-accepted}"
}
observe() {
    local op=$1 path=$2 value=$3 out
    shift 3
    out=$(kv cabin1 "$op" "$path" "$value" "$@")
    obs "$op $path = $value $*: $(echo "$out" | field "$op" result) $(echo "$out" | field "$op" code)"
}
# provider_on <paths...>: an actuator provider on cabin1 until provider_off.
provider_on() {
    kvbg prov cabin1 provide-actuator "$@" --mode ok --duration-s 60
    until_log prov provide ok || fail "provider for $* did not claim"
}
provider_off() { podman rm -f vxt-prov >/dev/null; }
# The databroker may name the signal by id in its request, so count requests, not paths.
actuated() {
    local out before
    before=$(podman logs vxt-prov | field actuation-request result | grep -c ok)
    out=$(kv hpc1 actuate "$1" "$2"); echo "$out" | indent
    sleep 0.2
    if [ "$(echo "$out" | verdict actuate)" = ok ] &&
        [ "$(podman logs vxt-prov | field actuation-request result | grep -c ok)" -gt "$before" ]; then
        pass "actuate $1 = $2 reached the provider"
    else
        fail "actuate $1 = $2"
    fi
}

h "ADAS: speed, ABS and cruise control"
expect_meta Vehicle.Speed "ENTRY_TYPE_SENSOR DATA_TYPE_FLOAT km/h None None None"
kvbg sub hpc1 subscribe Vehicle.Speed Vehicle.ADAS.ABS.IsEngaged --count 3 --timeout-s 20
until_log sub subscribe open || fail "subscriber did not open"
publish_ok Vehicle.Speed 88.5
publish_ok Vehicle.ADAS.ABS.IsEngaged true
podman wait vxt-sub >/dev/null
seen=$(podman logs vxt-sub | python3 -c 'import json,sys
print(" ".join(f"{d[\"path\"].split(\".\")[-1]}={d[\"value\"]}" for d in map(json.loads, sys.stdin) if d["op"] == "update"))')
case $seen in *"Speed=88.5"*"IsEngaged=True"*) pass "consumer on hpc1 saw: $seen" ;; *) fail "consumer on hpc1 saw: $seen" ;; esac
podman rm -f vxt-sub >/dev/null
provider_on Vehicle.ADAS.CruiseControl.SpeedSet Vehicle.ADAS.CruiseControl.IsActive
actuated Vehicle.ADAS.CruiseControl.SpeedSet 100
actuated Vehicle.ADAS.CruiseControl.IsActive true
provider_off
rejected actuate Vehicle.Speed 50
rejected publish Vehicle.Speed fast --as string

h "Body: doors, locks and windows"
expect_meta Vehicle.Cabin.Door.Row1.DriverSide.Window.Position "ENTRY_TYPE_ACTUATOR DATA_TYPE_UINT8 percent 0 100 None"
provider_on Vehicle.Cabin.Door.Row1.DriverSide.Window.Position Vehicle.Cabin.Door.Row1.DriverSide.IsLocked
actuated Vehicle.Cabin.Door.Row1.DriverSide.Window.Position 50
actuated Vehicle.Cabin.Door.Row1.DriverSide.IsLocked true
rejected actuate Vehicle.Cabin.Door.Row1.DriverSide.Window.Position 101
provider_off
observe publish Vehicle.Cabin.Door.Row1.DriverSide.IsOpen true

h "EV: state of charge and charging"
expect_meta Vehicle.Powertrain.TractionBattery.StateOfCharge.Current "ENTRY_TYPE_SENSOR DATA_TYPE_FLOAT percent 0.0 100.0 None"
publish_ok Vehicle.Powertrain.TractionBattery.StateOfCharge.Current 80.5
publish_ok Vehicle.Powertrain.TractionBattery.Charging.IsCharging true
rejected publish Vehicle.Powertrain.TractionBattery.StateOfCharge.Current 150
get_is Vehicle.Powertrain.TractionBattery.StateOfCharge.Current 80.5
provider_on Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit
actuated Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit 90
rejected actuate Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit 120
provider_off

h "Cabin: HVAC"
expect_meta Vehicle.Cabin.HVAC.Station.Row1.Driver.AirDistribution "ENTRY_TYPE_ACTUATOR DATA_TYPE_STRING - None None ['UP', 'MIDDLE', 'DOWN']"
provider_on Vehicle.Cabin.HVAC.Station.Row1.Driver.Temperature Vehicle.Cabin.HVAC.Station.Row1.Driver.AirDistribution
actuated Vehicle.Cabin.HVAC.Station.Row1.Driver.Temperature 21.5
actuated Vehicle.Cabin.HVAC.Station.Row1.Driver.AirDistribution MIDDLE
rejected actuate Vehicle.Cabin.HVAC.Station.Row1.Driver.AirDistribution SIDEWAYS
provider_off

h "where the documentation does not say"
observe publish Vehicle.VehicleIdentification.VIN TESTVIN0000000001
observe publish Vehicle.Speed 1.5 --as double
observe publish Vehicle.Powertrain.Transmission.CurrentGear 3 --as int64
out=$(kv cabin1 list Vehicle)
obs "signals the databroker lists under Vehicle: $(echo "$out" | field list count)"
for p in Vehicle.Powertrain.FuelSystem.AfterRefuelingFuelEconomy Vehicle.Powertrain.FuelSystem.CumulativeFuelEconomy; do
    obs "$p: $(kv cabin1 metadata "$p" | python3 -c 'import json,sys; d=json.loads(sys.stdin.readlines()[-1]); print(d["result"], d.get("code", ""))')"
done
exit "$failures"
