#!/usr/bin/env bash
# Build what this vehicle still needs on this host: the OTA store, copied from vx-vehicle-02 (whose
# build.sh makes it), because a workspace may not reach outside itself. The guest bundles, the probe
# payload and the OTA image are published parts pinned in parts.yaml and vehicle.yaml. Safe to re-run.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
two=$root/vxperiments/vehicles/vx-vehicle-02

VXEDGE_ROOT=$root "$two/build.sh"
[ -d "$here/ota-store" ] || cp -a "$two/ota-store" "$here/ota-store"
