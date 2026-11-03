#!/usr/bin/env bash
# Write and read one VSS signal on a running vx-vehicle-03, with the upstream client pinned by
# digest. Exits non-zero on any failure.
#
# The client exits 0 on a failed connection, so nothing here reads its exit code. Every attempt is
# classified from its output: `ok` needs `[publish] OK`, or `[get] OK` with the value; `refused`
# needs the client's own connection error, which a denied publish reports from its metadata lookup. Anything else is `unclear`, which fails both the allowed
# and the denied check, so a broken client cannot pass as either.
set -uo pipefail

CLIENT=ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:871649f14576871ca048ed5f4ff2c109656d748877d8ddb8609c67091c9f9c33
BROKER=10.100.0.50:55555
VALUE=42.5
SHOWN=42.50

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# Run the client inside a node's namespace. It needs a terminal, even for a one-shot command.
client() {
    local node=$1
    shift
    timeout 40 script -qec "podman run --rm -t -e TERM=xterm --network container:vx-$node-infra \
        $CLIENT --server http://$BROKER $*" /dev/null </dev/null 2>&1 |
        sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g'
}

classify() {
    case $1 in
        *"[publish]  OK"* | *"[get]  OK"*"Vehicle.Speed: $SHOWN"*) echo ok ;;
        *"Error"*"Failed to connect"*"transport error"*) echo refused ;;
        *) echo unclear ;;
    esac
}

rx_packets() {
    ip -s -j link show "vz-$1" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)[0]["stats64"]["rx"]["packets"])'
}

allowed() {
    out=$(client "$1" "$2")
    verdict=$(classify "$out")
    echo "$out" | sed 's/^/      /'
    if [ "$verdict" = ok ]; then pass "allowed $1: $2"
    else fail "allowed $1: $2 (read as $verdict)"; fi
}

denied() {
    before=$(rx_packets "$1")
    out=$(client "$1" "$2")
    after=$(rx_packets "$1")
    verdict=$(classify "$out")
    sent=$((after - before))
    echo "$out" | sed 's/^/      /'
    if [ "$verdict" = ok ]; then fail "denied $1: $2 (crossed the slice)"
    elif [ "$verdict" != refused ]; then fail "denied $1: $2 (read as $verdict)"
    elif [ "$sent" -eq 0 ]; then fail "denied $1: $2 (no frames reached the bridge)"
    else pass "denied $1: $2 (client refused, $sent frames reached the bridge)"; fi
}

echo "client: $CLIENT"
echo "databroker args: $(podman inspect -f '{{.Args}}' vx-hpc1-kuksa-databroker)"
echo "databroker image: $(podman inspect -f '{{.ImageName}}' vx-hpc1-kuksa-databroker)"

allowed cabin1 "publish Vehicle.Speed $VALUE"
allowed cabin1 "get Vehicle.Speed"
denied zone-rl "publish Vehicle.Speed 99"
denied zone-rl "get Vehicle.Speed"

# Still the value cabin1 wrote: the denied write changed nothing.
allowed cabin1 "get Vehicle.Speed"

echo "bridge VLAN membership:"
bridge -j vlan show | python3 -c '
import json, sys
for port in json.load(sys.stdin):
    if port["ifname"] in ("vz-hpc1", "vz-cabin1", "vz-zone-rl"):
        print("  " + port["ifname"], [v["vlan"] for v in port["vlans"]])'

exit "$failures"
