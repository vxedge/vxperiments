#!/usr/bin/env bash
# Build what this vehicle needs on this host: vx-vehicle-02's OTA store and guest bundle,
# copied in because a workspace may not reach outside itself, plus the reflector capsule. Safe to
# re-run. Needs what vx-vehicle-02's build.sh needs, and rustup's wasm32-wasip2 target.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
two=$root/vxperiments/vehicles/vx-vehicle-02

VXEDGE_ROOT=$root "$two/build.sh"
[ -d "$here/bundle" ] || cp -a "$two/bundle" "$here/bundle"
[ -d "$here/ota-store" ] || cp -a "$two/ota-store" "$here/ota-store"
"$root/vxparts/parts/zone/wasm/app/reflector-capsule/build.sh" "$here/capsule"
