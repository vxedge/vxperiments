# vxAPI gate on a vehicle with every node backend, 2026-11-10

The vxAPI core gate, run through `vxmcp` as an agent would, on [`vx-vehicle-04`](../../vehicles/vx-vehicle-04).
That vehicle has one node on each node backend vxedge has, plus a FreeRTOS ECU, all on one gateway with two
slices. Every step is an MCP tool call, every check reads a typed field or what the kernel reports, and every
mutating call went through the human confirmation, answered `accept` by the harness.

## Result

**10 of 10 runs, 461 checks passed, 0 failed** ([`core10.txt`](core10.txt)).

Each run covers the core gate: host capabilities and plan, `vehicle_up` as a job (with duplicate and competing
calls), status with typed payloads, the event stream, a daemon restart with state recovered, `vehicle_down`,
and a clean host. On top of that, after `up` and again after the restart:

| Check | Result, every run |
|---|---|
| All six backends up: container, qemu-microvm, cloud-hypervisor, libvirt, wasm-capsule, attach | passed |
| `zone-fl` (qemu-microvm) pinned to CPU 4: all 4 of its threads may run only there | passed |
| `zone-fr` (cloud-hypervisor) pinned to CPU 5: all 8 threads | passed |
| `zone-rr` (libvirt) pinned to CPU 6: all 6 QEMU threads, including emulator, I/O and vhost | passed |
| `sensor-rr` (wasm-capsule) pinned to CPU 7: both threads | passed |
| The attach node's tap `at-ivi1` adopted into the slice bridge | passed |
| `check-flows.sh`, 15 checks | passed |

Of the 15 flow checks:
- `hpc1` reaches every node on `adas` with 20/20 replies: the qemu-microvm, cloud-hypervisor, libvirt,
  wasm-capsule and attach nodes, and the FreeRTOS ECU.
- OTA answers.
- The container on `infotainment` reaches none of them; for each denied flow its frames reached the bridge,
  but no reply crossed the slice.

After `down`, the attach tap is back with no master. `vehicle_down` took about 18 s for all eight nodes, with
vxedge 0.14.0's 2 s stop timeout for container payloads.

## What ran

| Item | Value |
|---|---|
| vxedge | 0.14.0 release, x86_64, tarball sha256 `c797a8aa…`, with `vxedged` holding `cap_net_admin,cap_sys_admin` |
| vxmcp | 0.2.6 release |
| Vehicle | `vehicles/vx-vehicle-04`, documents and attach adapter pinned in [`vehicle-document.sha256`](vehicle-document.sha256) |
| Parts | All pinned by digest in `parts.yaml`: `probe-bundle` 0.1.0, `freertos/probe-bundle` 0.1.0, `reflector-capsule` 0.1.0, `vxprobe` 0.1.1, `vxota`, `gate-store`, the Kuksa databroker 0.7.1. The attach adapter's bundle is pinned in `ivi/SHA256SUMS` |
| Harness | [`harness/`](harness): the Zephyr gate's harness, extended with the backend, pinning, attach and 15-flow checks |

Run as `VXPRIV=<sudo pane> VX_CACHE=/tmp/vxcache VX_BIN=<vxedge 0.14.0> VXPERIMENTS=<this checkout>
OTHER_VXPERIMENTS=<a checkout with exp-002-ws's parts fetched> VEHICLE=vx-vehicle-04 python3 -I live.py core
10`. Paths in `core10.txt` are shortened.

## What this does not show

- **Attach:** the attach node is a generic adapter (the linux-probe bundle on plain QEMU over a prepared tap),
  not Android Automotive.
- **Pinning:** checked as thread affinity, not as latency. The host has no `isolcpus`, so other processes may
  still run on a pinned CPU. Container nodes are not pinned, because this host's rootless Podman has no
  `cpuset` controller, which vxedge refuses up front.
- **Guests:** every guest is a probe reflector; the FreeRTOS ECU runs on an x86 microVM, not MCU silicon.
- **Host:** one gateway on a shared development host. Functional results only, never timed.
