#!/usr/bin/env bash
# Print what `vehicle up` must not change: process and container identities, namespaces, links
# and rules. Run it before and after a second `up` and diff. Only vx tables are read. Rule handles
# and counters are dropped, because `up` re-installs the anti-spoof rule by design and a rule's
# identity is its text.
set -uo pipefail

echo "# guests"
pgrep -af '^[^ ]*qemu-system[^ ]* .*vx\.node=' | awk '{print $1}'
pgrep -f '^[^ ]*cloud-hypervisor '
pgrep -x vxcapsule
echo "# containers"
podman ps --filter name=^vx- --format '{{.Names}} {{.ID}} {{.Pid}}' | sort
echo "# namespaces"
ip netns | grep -E '^vx'
for c in $(podman ps --filter name=-infra --format '{{.Names}}' | grep '^vx-' | sort); do
    pid=$(podman inspect -f '{{.State.Pid}}' "$c")
    echo "$c $(readlink "/proc/$pid/ns/net")"
done
echo "# links"
ip -o link | grep -E ': (vx|vz)' | awk '{print $1, $2}'
echo "# vlans"; bridge vlan show | grep -E '^(vx|vz)|^ +[0-9]'
echo "# tc"
for dev in $(ip -o link | grep -oE 'vz-[^:@]+|vxbr0' | sort -u); do
    echo "$dev"; tc class show dev "$dev"; tc qdisc show dev "$dev"
done
echo "# nft"
sudo -n nft list tables | grep vx | while read -r _ family name; do
    sudo -n nft list table "$family" "$name"
done | sed -E 's/ # handle [0-9]+//; s/counter packets [0-9]+ bytes [0-9]+/counter/'
