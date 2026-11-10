#!/bin/sh
# Boot the linux-probe guest on QEMU/KVM over the host's prepared tap, after checking the bundle against
# SHA256SUMS. Only reached when status reports the guest down.
set -eu
sha256sum --quiet -c SHA256SUMS
ip link show "$VX_INTERFACE" >/dev/null 2>&1 || {
    echo "start.sh: no interface $VX_INTERFACE; prepare it once: sudo ip tuntap add dev $VX_INTERFACE mode tap user $(id -un) && sudo ip link set $VX_INTERFACE up" >&2
    exit 1
}
run=$VX_RUNTIME_DIR/attach-$VX_NODE
mkdir -p "$run"
rm -f "$run/qemu.pid"
exec qemu-system-x86_64 -M microvm,acpi=off -enable-kvm -cpu host -m 128m -smp 1 -nodefaults \
    -global virtio-mmio.force-legacy=false -no-user-config -nographic -monitor none \
    -serial "file:$run/serial.log" -kernel bundle/vmlinuz -initrd bundle/initrd.img \
    -append "console=ttyS0 reboot=t panic=-1 quiet vx.ip=$VX_IP vx.node=$VX_NODE" \
    -netdev "tap,id=n0,ifname=$VX_INTERFACE,script=no,downscript=no,vnet_hdr=off" \
    -device virtio-net-device,netdev=n0,mac=52:54:00:a7:00:13 \
    -daemonize -pidfile "$run/qemu.pid"
