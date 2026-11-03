#!/usr/bin/env bash
# What the databroker's flags do, on the pinned image, in throwaway rootless containers named
# vxt-flags. Measured, not assumed: --insecure once read as required, and it is not.
set -uo pipefail
B=ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd
C=ghcr.io/eclipse-kuksa/kuksa-databroker-cli@sha256:871649f14576871ca048ed5f4ff2c109656d748877d8ddb8609c67091c9f9c33
echo "databroker: $B"; echo "client: $C"
cli() {
    echo "  client -> $1: $(timeout 25 script -qec "podman run --rm -t -e TERM=xterm --network container:vxt-flags $C --server http://$1 get Vehicle.Speed" /dev/null </dev/null 2>&1 |
        sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' | tail -n +2 | tr '\n' ' ')"
}
t() {
    podman rm -f vxt-flags >/dev/null 2>&1
    podman run -d --name vxt-flags "$B" "$@" >/dev/null 2>&1
    sleep 3
    echo; echo "args: ${*:-(none)}"
    podman logs vxt-flags 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Starting Kuksa|Listening on|TLS is not enabled\.' |
        sed -E 's/^[^ ]+ +//; s/^ *//' | cut -c1-100 | sed 's/^/  /'
}
t --insecure --address 127.0.0.1 --port 55556; cli 127.0.0.1:55556; cli 127.0.0.1:55555
t --address 127.0.0.1 --port 55556; cli 127.0.0.1:55556
podman rm -f vxt-flags >/dev/null 2>&1
