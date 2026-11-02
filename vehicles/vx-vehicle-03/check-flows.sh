#!/usr/bin/env bash
# Check the allowed and denied flows of a running vx-vehicle-03. Exits non-zero on any failure.
# Only the container nodes can send, so the other backends are probed as targets. Allowed flows
# run first as the positive control, and a denied flow must show frames reaching the bridge.
set -uo pipefail

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

replies() {
    podman exec "vx-$1-payload" /vxprobe send --target "$2:9800" --pps 20 --duration-s 1 \
        --timeout-ms 500 2>&1 | sed -n 's/.*"received":[[:space:]]*\([0-9]*\).*/\1/p' | head -1
}

fetch() {
    podman exec "vx-$1-payload" /bin/busybox wget -q -T 2 -O - "http://$2:9900/root.json" \
        2>/dev/null | head -c 64
}

rx_packets() {
    ip -s -j link show "vz-$1" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)[0]["stats64"]["rx"]["packets"])'
}

allowed() {
    got=$(replies "$1" "$2")
    if [ "${got:-0}" -gt 0 ]; then pass "allowed $1 -> $3 $2:9800 ($got/20 replies)"
    else fail "allowed $1 -> $3 $2:9800 (no replies)"; fi
}

denied() {
    before=$(rx_packets "$1")
    got=$(replies "$1" "$2")
    after=$(rx_packets "$1")
    sent=$((after - before))
    if [ "${got:-0}" -ne 0 ]; then fail "denied $1 -> $3 $2:9800 ($got replies crossed the slice)"
    elif [ "$sent" -eq 0 ]; then fail "denied $1 -> $3 $2:9800 (no frames reached the bridge)"
    else pass "denied $1 -> $3 $2:9800 (0 replies, $sent frames reached the bridge)"; fi
}

# Guests answer once their kernels are up.
for target in 10.100.0.11 10.100.0.12; do
    for _ in $(seq 40); do
        [ "$(replies hpc1 "$target")" = 20 ] && break
        sleep 0.5
    done
done

allowed hpc1 10.100.0.11 qemu-microvm
allowed hpc1 10.100.0.12 cloud-hypervisor
allowed hpc1 10.100.0.14 wasm-capsule
allowed hpc1 10.100.0.13 container
allowed cabin1 10.100.0.50 compute
if [ -n "$(fetch cabin1 10.100.0.50)" ]; then pass "allowed cabin1 -> ota root.json"
else fail "allowed cabin1 -> ota root.json"; fi

denied zone-rl 10.100.0.11 qemu-microvm
denied zone-rl 10.100.0.12 cloud-hypervisor
denied zone-rl 10.100.0.14 wasm-capsule
denied zone-rl 10.100.0.13 container
denied zone-rl 10.100.0.50 compute
if [ -z "$(fetch zone-rl 10.100.0.50)" ]; then pass "denied zone-rl -> ota root.json"
else fail "denied zone-rl -> ota root.json (fetched across the slice)"; fi

echo "bridge VLAN membership:"
bridge -j vlan show | python3 -c '
import json, sys
for port in json.load(sys.stdin):
    if port["ifname"].startswith("vz-"):
        print("  " + port["ifname"], [v["vlan"] for v in port["vlans"]])'

exit "$failures"
