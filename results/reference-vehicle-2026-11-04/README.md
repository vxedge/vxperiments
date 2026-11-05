# The six-zone reference vehicle, 2026-11-04

`vxedge vehicle up` on [`vx-reference-sedan-01`](../../vehicles/vx-reference-sedan-01): six
qemu-microvm guests in four zones plus a central compute node with an OTA service and the Kuksa
signal plane, all from one workspace, on the published `probe-bundle` pinned by digest.
[`transcript.txt`](transcript.txt) is the run and [`vehicle-document.sha256`](vehicle-document.sha256)
pins the workspace documents.

| Check | Result |
|---|---|
| `up` provisions the gateway, six guests, compute, signal plane and OTA service | passed |
| Central compute reaches every guest, 20 of 20 probe replies each, and OTA answers | passed |
| `status` reports the vehicle up after a daemon restart | passed |
| A second `up` changes no process, container, namespace, link, VLAN, queue or vx rule | passed, empty diff |
| `down` leaves no netns, links, VMs, containers or nft rules | passed |

## What this run found

The first runs failed: with six qemu guests on one slice, three of six answered nothing. QEMU gave
every guest the same MAC, `52:54:00:12:34:56`, so the bridge delivered unicast to one guest while ARP
still worked. [vxedge#77](https://github.com/vxedge/vxedge/pull/77) gives each guest a stable MAC
from its node id. This run used a build of that change, merged as `b54ebdc`; the binary reports
`0.5.2` because the version was not yet bumped. `vx-vehicle-03` did not show the fault because it has
one qemu guest.

## What this does not show

- The guests are probes, and nothing was timed.
- Only the container node can send; the guests were probed as targets.
- One slice, so no isolation is shown.
- The probe image and the OTA store are local to the host that ran this.
