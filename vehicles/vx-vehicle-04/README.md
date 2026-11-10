# vx-vehicle-04: every node backend on one vehicle

Seven devices on one gateway, one for each node backend vxedge has, plus a container on a second slice as
the denied-flow sender:

| Device | Backend | Slice | Address | Pinned CPU | Part |
|---|---|---|---|---|---|
| `zone-fl` | `qemu-microvm` | adas | 10.100.0.11 | 4 | `zone/linux/stack/probe-bundle` 0.1.0 |
| `zone-fr` | `cloud-hypervisor` | adas | 10.100.0.12 | 5 | the same bundle |
| `zone-rr` | `libvirt` | adas | 10.100.0.21 | 6 | the same bundle |
| `sensor-rr` | `wasm-capsule` | adas | 10.100.0.14 | 7 | `zone/wasm/app/reflector-capsule` 0.1.0 |
| `ivi1` | `attach` | adas | 10.100.0.13 | none | `./ivi`, the same bundle on plain QEMU |
| `zone-rl` | `container` | infotainment | 10.100.0.31 | none | `agent/probe/app/vxprobe` 0.1.1 |
| `hpc1` | `container` | adas | 10.100.0.50 | none | the same probe, with OTA and the Kuksa databroker |

Every part is published and pinned by digest, except the attach adapter. The adapter pins the bundle it boots
in `ivi/SHA256SUMS` and refuses to start on a mismatch.

## The attach adapter

`./ivi` stands in for a platform that brings its own host stack, as Cuttlefish does for Android Automotive.
Its "stack" is one persistent tap the host prepares once, and plain QEMU/KVM booting the published linux-probe
bundle on it:

```sh
sudo ip tuntap add dev at-ivi1 mode tap user $USER && sudo ip link set at-ivi1 up
```

`start.sh`, `status.sh` and `stop.sh` act on this node only, by the PID QEMU records. The gateway adopts
`at-ivi1` into the slice at `up` and returns it with no master at `down`. The tap stays, because it belongs
to the host.

## Run

```sh
./build.sh                 # once per host: fetches ivi/bundle by digest and checks it
vxedge vehicle up --manifest .
./check-flows.sh           # 13 checks: hpc1 reaches every backend; zone-rl reaches none
vxedge vehicle down --manifest .
./check-leaks.sh
```

Needs KVM, libvirt reachable without sudo, Cloud Hypervisor, `vxcapsule`, Podman and `oras`. `vxedge doctor
--tier 2` checks most of these.

## Pinning

- **CPU per node:** four nodes are pinned, each to its own CPU, one per backend that can pin. Every thread of
  each node's process should be allowed on that CPU only.
- **Backends without pins:** the container nodes carry none. On a host whose rootless Podman has no `cpuset`
  controller, `up` refuses a pinned container device, and vxedge also refuses pins on an `attach` device.
- **Version:** the libvirt node needs a vxedge with vxedge#127 (ACPI for the guest's NIC, `emulatorpin` for
  its threads).

## Limits

- **Attach adapter:** a generic one, not an Android Automotive guest.
- **What pinning shows:** pinning is checked as thread affinity, not as latency. The host has no `isolcpus`, so
  other processes may still run on a pinned CPU.
- **Shared host:** one gateway on a shared host; functional results only.
