# Phase-3 gate, 2026-11-01

`vxedge vehicle up` on [`vx-vehicle-02`](../../vehicles/vx-vehicle-02): a gateway, three zones on
qemu-microvm and container, a CPU-only central compute node, and an OTA service placed on a slice,
all from one workspace. Run from a clean state on merged `main`: vxedge `879cd74`, vxperiments
`590f03a`. [`transcript.txt`](transcript.txt) is the whole run, and
[`vehicle-document.sha256`](vehicle-document.sha256) pins the workspace documents.

| Check | Result |
|---|---|
| `up` provisions every component from one workspace | passed |
| `status` reports each component as observed, including after a daemon restart | passed |
| Allowed flows, probe and OTA over HTTP | passed |
| Denied flows from `infotainment` to `adas`, with frames seen reaching the bridge | passed |
| A second `up` changes no process, container, namespace, link, VLAN, queue or vx rule | passed, empty diff |
| `up`, `status` and `down` of another vehicle refused, before and after a restart | passed, nothing changed |
| `down` leaves no netns, links, VMs, containers or nft rules | passed |
| `down` after a failed `up` leaves nothing | passed |
| Every step on the job stream, every mutating RPC in the audit log | passed |

## Regression

[`regression-2026-11-02.txt`](regression-2026-11-02.txt) is the same run on vxedge `208548c`, after
the Cloud Hypervisor and capsule work and with the `vxprobe` fix in the probe image. Every check
still holds.

## What this does not show

- The guests are probes. No QNX, Android Automotive or application workload ran, and the compute
  node runs a probe and the OTA server, not Autoware.
- Slice isolation here comes from VLAN membership on one Linux bridge on one shared host. Nothing
  was timed, so this is a provisioning result, not a measurement.
- `zone-rl` is alone on `infotainment`, so that slice has no allowed flow of its own.
- The images are local to this host. Their digests in the transcript identify them for this run,
  and reproducing it elsewhere means running `build.sh`, which gives different digests.
- `transcript.txt` shows `vehicle down` taking a stage per node, about 15 s for each container.
- The failed `up` was forced by a foreign container holding the service's name, and the transcript
  prints the first line of that error only.
