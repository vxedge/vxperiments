#!/usr/bin/env bash
# Build what this vehicle needs on this host: two local images, the OTA store, the guest bundle.
# Needs the vxagents and vxota checkouts beside vxperiments, the x86_64 musl Rust target, Podman
# and a static busybox. Safe to re-run.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=${VXEDGE_ROOT:-$(cd "$here/../../.." && pwd)}
target=x86_64-unknown-linux-musl

(cd "$root/vxagents" && cargo build --release --target "$target" -p vxprobe)
(cd "$root/vxota" && cargo build --release --target "$target" -p vxota)
vxprobe=$root/vxagents/target/$target/release/vxprobe
vxota=$root/vxota/target/$target/release/vxota

busybox=$(command -v busybox)
file -L "$busybox" | grep -q 'statically linked' || {
    echo "build.sh: $busybox is not static; install busybox-static" >&2
    exit 1
}

context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT
cp "$vxprobe" "$context/vxprobe"
cp "$vxota" "$context/vxota"
cp -L "$busybox" "$context/busybox"
podman build -q -t localhost/vxedge/probe:1 -f "$here/images/probe.Containerfile" "$context"
podman build -q -t localhost/vxedge/ota:1 -f "$here/images/ota.Containerfile" "$context"

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
