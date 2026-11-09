#!/usr/bin/env bash
# Build what this vehicle needs on this host: the OTA store and the guest bundle. The vehicle pulls
# its probe payload and OTA service from vxparts. Needs the vxota checkout beside vxperiments and
# the x86_64 musl Rust target (vxota signs the store). Safe to re-run.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
target=x86_64-unknown-linux-musl

(cd "$root/vxota" && cargo build --release --target "$target" -p vxota)
vxota=$root/vxota/target/$target/release/vxota

context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT

store=$here/ota-store
key=$here/.ota-root.key
if [ ! -f "$store/root.json" ]; then
    mkdir -p "$store"
    "$vxota" keygen --artifacts-dir "$store" --out-priv "$key"
    head -c 1048576 /dev/zero >"$context/gate-artifact.bin"
    "$vxota" publish --artifacts-dir "$store" --file "$context/gate-artifact.bin" \
        --name gate-artifact --signing-key "$key"
fi

if [ ! -f "$here/bundle/vmlinuz" ]; then
    if [ -f "$root/vxperiments/vehicles/vx-vehicle-01/bundle/vmlinuz" ]; then
        cp -a "$root/vxperiments/vehicles/vx-vehicle-01/bundle" "$here/bundle"
    else
        "$root/vxparts/parts/zone/linux/stack/probe-bundle/build.sh" "$here/bundle"
    fi
fi
