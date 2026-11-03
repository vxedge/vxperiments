#!/usr/bin/env bash
# Build what exp-016 needs on this host: vx-vehicle-03's images and files, copied in because a
# workspace may not reach outside itself, the vxtraffic load image and kuksa-perf at aa6fba0.
# Safe to re-run.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
three=$root/vxperiments/vehicles/vx-vehicle-03
target=x86_64-unknown-linux-musl

VXEDGE_ROOT=$root "$three/build.sh"
for d in bundle ota-store capsule; do [ -d "$here/$d" ] || cp -a "$three/$d" "$here/$d"; done
# A private target dir, so the vxagents checkout's own target/ is not touched.
cargo_target=${CARGO_TARGET_DIR:-$here/.target}
cargo build --locked --release --manifest-path "$root/vxagents/Cargo.toml" --target "$target" \
    -p vxtraffic --target-dir "$cargo_target"
cp "$cargo_target/$target/release/vxtraffic" "$here/tools/load/vxtraffic"
podman build -q -t localhost/vxperiments/vxtraffic:1 "$here/tools/load"
rm -f "$here/tools/load/vxtraffic"
podman build -t localhost/vxperiments/kuksa-perf:aa6fba0 "$here/tools/perf"
