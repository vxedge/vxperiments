#!/usr/bin/env bash
# List anything vx-vehicle-04 could leave behind. Exits non-zero if something is there. Only
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
show "qemu" "$(pgrep -af '^[^ ]*qemu-system[^ ]* .*vx\.node=' | cut -c1-60 || true)"
show "cloud-hypervisor" "$(pgrep -af '^[^ ]*cloud-hypervisor ' | cut -c1-60 || true)"
show "vxcapsule" "$(pgrep -a -x vxcapsule | cut -c1-60 || true)"
show "nft" "$(sudo -n nft list tables | grep -E 'vx' || true)"
exit "$leaks"
