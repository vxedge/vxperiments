# vxAPI gate on a vehicle with every node backend, including qemu-mcu, 2026-11-11

The vxAPI core gate, run through `vxmcp` as an agent would, on [`vx-vehicle-04`](../../vehicles/vx-vehicle-04).
The vehicle now has one node on each of vxedge's seven node backends. It adds two microcontroller ECUs on
`qemu-mcu`: FreeRTOS and Zephyr firmware on QEMU's `mps2-an385` (Cortex-M3). Every step is an MCP tool call,
every check reads a typed field or what the kernel reports, and every mutating call went through the human
confirmation, answered `accept` by the harness.

## Result

**10 of 10 runs, 501 checks passed, 0 failed** ([`core10.txt`](core10.txt)).

Each run covers the core gate: host capabilities and plan, `vehicle_up` as a job (with duplicate and competing
calls), status with typed payloads, the event stream, a daemon restart with state recovered, `vehicle_down`,
and a clean host. On top of that, after `up` and again after the restart:

| Check | Result, every run |
|---|---|
| All seven backends up: container, qemu-microvm, cloud-hypervisor, libvirt, wasm-capsule, attach, qemu-mcu | passed |
| `ecu-mcu-frt` and `ecu-mcu-zep` report `arch: armv7m`, `acceleration: tcg` in `NodeStatus` | passed |
| `zone-fl` (qemu-microvm) pinned to CPU 4: all of its threads may run only there | passed |
| `zone-fr` (cloud-hypervisor) pinned to CPU 5 | passed |
| `zone-rr` (libvirt) pinned to CPU 6, including emulator, I/O and vhost threads | passed |
| `sensor-rr` (wasm-capsule) pinned to CPU 7 | passed |
| `ecu-mcu-frt` (qemu-mcu) pinned to CPU 8: all 3 QEMU threads | passed |
| The attach node's tap `at-ivi1` adopted into the slice bridge | passed |
| `check-flows.sh`, 19 checks | passed |

Of the 19 flow checks:
- `hpc1` reaches every node on `adas` with 20/20 replies: the qemu-microvm, cloud-hypervisor, libvirt,
  wasm-capsule and attach nodes, the FreeRTOS microVM ECU, and both qemu-mcu ECUs.
- OTA answers.
- The container on `infotainment` reaches none of them. For each denied flow, its frames reached the bridge
  but no reply crossed the slice.

## What ran

| Item | Value |
|---|---|
| vxedge | 0.17.0 release, x86_64, tarball sha256 `bcbd4b8d…`, with `vxedged` holding `cap_net_admin,cap_sys_admin` |
| vxmcp | 0.4.3 release |
| Vehicle | `vehicles/vx-vehicle-04`, documents and attach adapter pinned in [`vehicle-document.sha256`](vehicle-document.sha256) |
| Parts | All pinned by digest in `parts.yaml`. New: `zone/freertos/firmware/probe-mps2` 0.1.0 and `zone/zephyr/firmware/probe-mps2` 0.1.0. The rest as in the [2026-11-10 run](../all-backends-gate-2026-11-10) |
| Harness | [`harness/`](harness): the 2026-11-10 harness, extended with the qemu-mcu backend, its `arch` and `acceleration` check, a fifth pinned node and the 19-flow check |

Run as `VXPRIV=<sudo pane> VX_CACHE=/tmp/vxcache VX_BIN=<vxedge 0.17.0 and vxmcp 0.4.3> VXPERIMENTS=<this checkout>
VEHICLE=vx-vehicle-04 python3 -I live.py core 10`. Paths in `core10.txt` are shortened.

An earlier attempt was stopped after two runs. The harness read `arch` from inside `NodeStatus.status`, but it
sits beside `status`. Every other check had passed in both runs. The vehicle was brought down and the host
checked clean, and the 10 runs above were made with the corrected harness.

## What this does not show

- **MCU ECUs:** QEMU's `mps2-an385` model under TCG, not MCU silicon. Their replies are functional evidence,
  never timing.
- **Attach:** the attach node is a generic adapter (the linux-probe bundle on plain QEMU over a prepared tap),
  not Android Automotive.
- **Pinning:** checked as thread affinity, not as latency. The host has no `isolcpus`, so other processes may
  still run on a pinned CPU. Container nodes are not pinned, because this host's rootless Podman has no
  `cpuset` controller, which vxedge refuses up front.
- **Guests:** every guest is a probe reflector.
- **Host:** one gateway on a shared development host. Functional results only, never timed.
