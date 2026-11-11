# vx-vehicle-04: every node backend on one vehicle

Ten devices on one gateway: one for each node backend vxedge has, a FreeRTOS ECU on a microVM, a second
microcontroller ECU, and a container on a second slice as the denied-flow sender:

| Device | Backend | Slice | Address | Pinned CPU | Part |
|---|---|---|---|---|---|
| `zone-fl` | `qemu-microvm` | adas | 10.100.0.11 | 4 | `zone/linux/stack/probe-bundle` 0.1.0 |
| `zone-fr` | `cloud-hypervisor` | adas | 10.100.0.12 | 5 | the same bundle |
| `zone-rr` | `libvirt` | adas | 10.100.0.21 | 6 | the same bundle |
| `sensor-rr` | `wasm-capsule` | adas | 10.100.0.14 | 7 | `zone/wasm/app/reflector-capsule` 0.1.0 |
| `ivi1` | `attach` | adas | 10.100.0.13 | none | `./ivi`, the same bundle on plain QEMU |
| `ecu-rtos` | `qemu-microvm` | adas | 10.100.0.15 | none | `zone/freertos/stack/probe-bundle` 0.1.0 (FreeRTOS) |
| `ecu-mcu-frt` | `qemu-mcu` | adas | 10.100.0.16 | 8 | `zone/freertos/firmware/probe-mps2` 0.1.0 (FreeRTOS, Cortex-M3) |
| `ecu-mcu-zep` | `qemu-mcu` | adas | 10.100.0.17 | none | `zone/zephyr/firmware/probe-mps2` 0.1.0 (Zephyr, Cortex-M3) |
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
./check-flows.sh           # 19 checks: hpc1 reaches every node on adas; zone-rl reaches none
vxedge vehicle down --manifest .
./check-leaks.sh
```

Needs KVM, libvirt reachable without sudo, Cloud Hypervisor, `qemu-system-arm`, `vxcapsule`, Podman and `oras`.
`vxedge doctor --tier 2` checks most of these.

## Pinning

- **CPU per node:** five nodes are pinned, each to its own CPU, one per backend that can pin. Every thread of
  each node's process should be allowed on that CPU only.
- **Backends without pins:** the container nodes carry none. On a host whose rootless Podman has no `cpuset`
  controller, `up` refuses a pinned container device, and vxedge also refuses pins on an `attach` device.
- **Version:** needs vxedge 0.16.0 or later for the `qemu-mcu` ECUs. The libvirt node needs ACPI for its NIC
  and `emulatorpin` for its threads (0.13.0).

## Gate

10 of 10 on vxedge 0.17.0 with both qemu-mcu ECUs, 501 checks, 0 failed:
[`results/all-backends-gate-2026-11-11`](../../results/all-backends-gate-2026-11-11). Before them, 10 of 10 on vxedge
0.14.0, 461 checks: [`results/all-backends-gate-2026-11-10`](../../results/all-backends-gate-2026-11-10).

## Limits

- **Attach adapter:** a generic one, not an Android Automotive guest.
- **MCU ECUs:** QEMU's `mps2-an385` model under TCG, not MCU silicon. Their results are functional only.
- **What pinning shows:** pinning is checked as thread affinity, not as latency. The host has no `isolcpus`, so
  other processes may still run on a pinned CPU.
- **Shared host:** one gateway on a shared host; functional results only.
