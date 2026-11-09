#!/usr/bin/env bash
# Build what exp-016 needs on this host: vx-vehicle-03's images and files, copied in because a
# workspace may not reach outside itself, then the published vxtraffic and kuksa-perf images.
# Safe to re-run.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
three=$root/vxperiments/vehicles/vx-vehicle-03

VXEDGE_ROOT=$root "$three/build.sh"
for d in bundle ota-store capsule; do [ -d "$here/$d" ] || cp -a "$three/$d" "$here/$d"; done
# The load and kuksa-perf at aa6fba0 are published vxparts parts, built from the Containerfiles in
# tools/ (kuksa-perf) and vxagents v0.1.1 (vxtraffic); pulled by digest.
podman pull -q ghcr.io/vxedge/parts/agent/load/app/vxtraffic@sha256:be310378c1f330969072669fb24a991b26c2a991dc02f23c81056c8fc98f2c3c >/dev/null
podman pull -q ghcr.io/vxedge/parts/agent/load/app/kuksa-perf@sha256:1e894b9d7de05d41059d711871b17ae3023497933ad88f05f29f903000c7ba73 >/dev/null
