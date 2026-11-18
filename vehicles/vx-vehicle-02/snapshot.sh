#!/usr/bin/env bash
# Print what `vehicle up` must not change: process and container identities, namespaces, links
# and rules. Run it before and after a second `up` and diff. Only vx tables are read. Rule handles
# and counters are dropped, because `up` re-installs the anti-spoof rule by design and a rule's
# identity is its text.
set -uo pipefail

# The run's instance slot (vxedge ARCHITECTURE.md §6.0.5): every host name carries it. Set VX_SLOT
# for a vehicle run in a slot other than 0.
S="${VX_SLOT:-0}"

echo "# qemu"; pgrep -a qemu-system | awk '{print $1}'
echo "# containers"
podman ps --filter name=^vx$S- --format '{{.Names}} {{.ID}} {{.Pid}}' | sort
echo "# namespaces"
for c in $(podman ps --filter name=-infra --format '{{.Names}}' | grep "^vx$S-" | sort); do
    pid=$(podman inspect -f '{{.State.Pid}}' "$c")
    echo "$c $(readlink "/proc/$pid/ns/net")"
done
echo "# links"
ip -o link | grep -E ': (vx|v[zpi][0-9a-z]-)' | awk '{print $1, $2}'
echo "# vlans"; bridge vlan show | grep -E '^(vx|v[zpi][0-9a-z]-)|^ +[0-9]'
echo "# tc"
for dev in $(ip -o link | grep -oE "v[zpi]$S-[^:@]+|vxbr$S" | sort -u); do
    echo "$dev"; tc class show dev "$dev"; tc qdisc show dev "$dev"
done
echo "# nft"
sudo -n nft list tables | grep vx | while read -r _ family name; do
    sudo -n nft list table "$family" "$name"
done | sed -E 's/ # handle [0-9]+//; s/counter packets [0-9]+ bytes [0-9]+/counter/'
