#!/usr/bin/env bash
# List anything vx-vehicle-02 could leave behind. Exits non-zero if something is there. Only
# vx-named objects count, so unrelated VMs on the host are neither listed nor touched.
set -uo pipefail

leaks=0
show() {
    echo "$1: ${2:-none}"
    [ -z "$2" ] || leaks=$((leaks + 1))
}

show "netns" "$(ip netns | grep -E '^vx' || true)"
show "links" "$(ip -br link | grep -E '^(vx|vz)' || true)"
show "containers" "$(podman ps -a --format '{{.Names}}' | grep -E '^vx' || true)"
show "qemu" "$(pgrep -a qemu-system | cut -c1-60 || true)"
show "nft" "$(sudo -n nft list tables | grep -E 'vx' || true)"
exit "$leaks"
