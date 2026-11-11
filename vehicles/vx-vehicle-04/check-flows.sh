#!/usr/bin/env bash
# Check the allowed and denied flows of a running vx-vehicle-04: central compute reaches a node of every backend,
# the FreeRTOS ECU and both qemu-mcu ECUs on `adas`, and the container on `infotainment` reaches none of them.
# Exits non-zero on any failure. Only the container nodes can send, so the other backends are probed as
# targets. A denied flow must show frames reaching the bridge, so the silence means the slice held, not that
# nothing was sent.
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
    got=$(replies hpc1 "$1")
    if [ "${got:-0}" = 20 ]; then pass "allowed hpc1 -> $2 $1:9800 ($got/20 replies)"
    else fail "allowed hpc1 -> $2 $1:9800 (${got:-0}/20 replies)"; fi
}

denied() {
    before=$(rx_packets zone-rl)
    got=$(replies zone-rl "$1")
    after=$(rx_packets zone-rl)
    sent=$((after - before))
    if [ "${got:-0}" -ne 0 ]; then fail "denied zone-rl -> $2 $1:9800 ($got replies crossed the slice)"
    elif [ "$sent" -eq 0 ]; then fail "denied zone-rl -> $2 $1:9800 (no frames reached the bridge)"
    else pass "denied zone-rl -> $2 $1:9800 (0 replies, $sent frames reached the bridge)"; fi
}

targets="10.100.0.11:qemu-microvm 10.100.0.12:cloud-hypervisor 10.100.0.21:libvirt 10.100.0.14:wasm-capsule 10.100.0.13:attach 10.100.0.15:freertos 10.100.0.16:qemu-mcu-freertos 10.100.0.17:qemu-mcu-zephyr"

# Guests answer once their kernels are up: allow each a minute.
for t in $targets; do
    for _ in $(seq 120); do
        [ "$(replies hpc1 "${t%%:*}")" = 20 ] && break
        sleep 0.5
    done
done

for t in $targets; do allowed "${t%%:*}" "${t#*:}"; done
if [ -n "$(fetch hpc1 127.0.0.1)" ]; then pass "OTA root.json served on hpc1:9900"
else fail "OTA root.json not served"; fi

for t in $targets; do denied "${t%%:*}" "${t#*:}"; done
denied 10.100.0.50 container
if [ -z "$(fetch zone-rl 10.100.0.50)" ]; then pass "denied zone-rl -> ota root.json"
else fail "denied zone-rl -> ota root.json (fetched across the slice)"; fi

exit "$failures"
