# All backends in one vehicle, 2026-11-02

`vxedge vehicle up` on [`vx-vehicle-03`](../../vehicles/vx-vehicle-03): six zones on qemu-microvm,
cloud-hypervisor, wasm-capsule and container, with central compute and an OTA service placed on a
slice, all from one workspace. Run from a clean state on merged `main`: vxedge `208548c`,
vxperiments `43505c3`. [`transcript.txt`](transcript.txt) is the whole run, and
[`vehicle-document.sha256`](vehicle-document.sha256) pins the workspace documents.

| Check | Result |
|---|---|
| `up` provisions every component from one workspace | passed |
| `status` reports each component as observed, including after a daemon restart | passed |
| Allowed flows to a target on every backend, and OTA over HTTP | passed |
| Denied flows from `infotainment` to every backend, with frames seen reaching the bridge | passed |
| A second `up` changes no guest, container, namespace, link, VLAN, queue or vx rule | passed, empty diff |
| `up`, `status` and `down` of another vehicle refused, before and after a restart | passed, nothing changed |
| `down` leaves no netns, links, VMs, capsules, containers or nft rules | passed |
| `down` after a failed `up` leaves nothing | passed |
| Every step on the job stream, every mutating RPC in the audit log | passed |

## What this does not show

- The guests are probes, and nothing was timed. This shows the backends provision and isolate
  together. It says nothing about how they compare.
- Only the container nodes can send, so the VM and capsule nodes were probed as targets.
- `libvirt` was not part of the run.
- The images, the bundle and the capsule are local to this host.
