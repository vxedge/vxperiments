#!/usr/bin/env bash
# Build what this vehicle needs on this host: vx-vehicle-02's probe and OTA images and OTA store,
# copied in because a workspace may not reach outside itself. The guest bundle is not built: it is
# the published, digest-pinned probe-bundle in parts.yaml. Safe to re-run.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
two=$root/vxperiments/vehicles/vx-vehicle-02

VXEDGE_ROOT=$root "$two/build.sh"
[ -d "$here/ota-store" ] || cp -a "$two/ota-store" "$here/ota-store"
