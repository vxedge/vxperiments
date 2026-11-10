#!/usr/bin/env bash
# Fetch what this vehicle needs that `vehicle up` does not pull itself: the attach adapter's guest bundle, the
# published linux-probe bundle by digest, checked against ivi/SHA256SUMS. Needs oras. Safe to re-run.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ref=ghcr.io/vxedge/parts/zone/linux/stack/probe-bundle@sha256:33c9c8d8625bd5c6d1f4d3d0c561fdaa930e057fcd1fb24fb3badb402f25429d
if ! (cd "$here/ivi" && sha256sum --quiet -c SHA256SUMS 2>/dev/null); then
    mkdir -p "$here/ivi/bundle"
    (cd "$here/ivi/bundle" && oras pull "$ref" >/dev/null)
    (cd "$here/ivi" && sha256sum --quiet -c SHA256SUMS)
fi
echo "vx-vehicle-04: ivi/bundle verified"
