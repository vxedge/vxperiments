# Zephyr zone ECU in the six-zone reference vehicle, 2026-11-05

[`vx-reference-sedan-02`](../../vehicles/vx-reference-sedan-02) is the six-zone reference vehicle with
one zone, `fr-steer-actuator`, running a Zephyr v4.5.0 image instead of Linux. The other five zones run
the Linux `probe-bundle`. Both bundles are pulled from the registry by digest; the Zephyr one is
`ghcr.io/vxedge/parts/zone/zephyr/stack/probe-bundle:0.1.0` at
`sha256:a50f0cb58ed9b041217cc9cdaba7555089d6c73545fcdebe90ecba250fdfe135`.
[`transcript.txt`](transcript.txt) is the run and [`vehicle-document.sha256`](vehicle-document.sha256)
pins the vehicle document.

| Check | Result |
|---|---|
| `up` pulls both bundles by digest and provisions gateway, six guests, compute, signal plane, OTA | passed |
| Central compute reaches every guest, 20 of 20 probe replies each, the Zephyr zone included | passed |
| A second `up` changes no process, container, namespace, link, VLAN, queue or vx rule | passed, empty diff |
| `down` leaves no netns, links, VMs, containers or nft rules | passed |

## What this does not show

- The Zephyr image is a probe (UDP echo on :9800), not an ECU application, and it runs without an MMU.
- qemu-microvm only. Nothing was timed, and one slice means no isolation is shown.
- Only the container node sends; the guests were probed as targets.
- The probe image used for the compute node is local to the host that ran this.

## What it needed

Zephyr's virtio-mmio driver needs the non-legacy transport, which vxedge did not request. The
`-global virtio-mmio.force-legacy=false` flag is in a vxedge change run here from a branch build.
