#!/usr/bin/env bash
# Check a running vx-reference-sedan-01: central compute reaches every zone device, and the OTA
# service answers. Exits non-zero on any failure. Only the container node can send, so the six
# VM devices are probed as targets once their kernels are up.
set -uo pipefail

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

replies() {
    podman exec vx-hpc-ad-01-payload /vxprobe send --target "$1:9800" --pps 20 --duration-s 1 \
        --timeout-ms 500 2>&1 | sed -n 's/.*"received":[[:space:]]*\([0-9]*\).*/\1/p' | head -1
}

declare -A zone=(
    [10.120.0.11]=fl-safety-ecu [10.120.0.12]=fl-camera-sensor
    [10.120.0.21]=fr-body-ecu [10.120.0.22]=fr-steer-actuator
    [10.120.0.31]=rl-radar-sensor [10.120.0.41]=rr-brake-actuator
)

for ip in "${!zone[@]}"; do
    for _ in $(seq 120); do
        [ "$(replies "$ip")" = 20 ] && break
        sleep 0.5
    done
    got=$(replies "$ip")
    if [ "${got:-0}" = 20 ]; then pass "hpc-ad-01 -> ${zone[$ip]} $ip:9800 ($got/20 replies)"
    else fail "hpc-ad-01 -> ${zone[$ip]} $ip:9800 (no replies)"; fi
done

root=$(podman exec vx-hpc-ad-01-payload /bin/busybox wget -q -T 2 -O - \
    "http://127.0.0.1:9900/root.json" 2>/dev/null | head -c 64)
if [ -n "$root" ]; then pass "OTA root.json served on hpc-ad-01:9900"
else fail "OTA root.json not served"; fi

exit "$failures"
