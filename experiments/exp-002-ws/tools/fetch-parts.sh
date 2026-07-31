#!/usr/bin/env bash
# fetch-parts.sh — populate this sandbox's parts/ and verify them.
#
# The guest bundle is 19 MB of kernel + initramfs, so it is fetched rather than committed: five
# sandboxes vendoring it would be 95 MB of binary in git. What *is* committed is the digest it
# must have (parts/linux-probe.sha256), so a fetched part is verified rather than trusted.
#
# Today the source is the sibling vxzones checkout. When the bundle is published as a vxparts
# loadable this script fetches the digest-pinned ref instead and parts.yaml stops being local —
# that is a promotion, not a rewrite (see parts/README.md).
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${VXZONES_BUNDLE:-$WS/../../../vxzones/images/linux-probe/bundle}"
DEST="$WS/parts/linux-probe"

[[ -d "$SRC" ]] || {
  echo "error: no bundle at $SRC" >&2
  echo "  build it:  cd vxzones && ./scripts/build-guest-bundle.sh" >&2
  echo "  or point at one: VXZONES_BUNDLE=/path/to/bundle $0" >&2
  exit 1
}

mkdir -p "$DEST"
cp "$SRC/vmlinuz" "$SRC/initrd.img" "$SRC/meta.json" "$DEST/"

# Verify against the digests this experiment recorded, not against the ones that came with the
# copy — a bundle that ships its own expected hashes proves nothing about which bundle it is.
expected="$WS/parts/linux-probe.sha256"
if [[ -f "$expected" ]]; then
  (cd "$DEST" && sha256sum -c "$expected")
  echo "== parts verified against the recorded digests"
else
  echo "== no recorded digests yet — writing them from this bundle:"
  (cd "$DEST" && sha256sum vmlinuz initrd.img | tee "$expected")
  echo "   commit parts/linux-probe.sha256 so future fetches are verified"
fi
