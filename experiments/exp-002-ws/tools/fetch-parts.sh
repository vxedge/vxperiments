#!/usr/bin/env bash
# fetch-parts.sh — populate this sandbox's parts/ and verify them.
#
# The guest bundle is 19 MB of kernel + initramfs, so it is fetched rather than committed: five
# sandboxes vendoring it would be 95 MB of binary in git. What *is* committed is the digest it
# must have (parts/linux-probe.sha256), so a fetched part is verified rather than trusted.
#
# The bundle *is* published as a vxparts loadable now (`ghcr.io/vxedge/parts/zone/linux/
# stack/probe-bundle:0.1.0`, 2026-07-28) — but this still fetches from the sibling vxparts
# checkout's own locally-built copy, not a real `oras pull` of that published ref. Genuine
# registry-fetch (parts.yaml stops being local, verified against the digest-pinned ref
# instead of a local path) is a separate, larger promotion — docs/ROADMAP.md tracks it
# as a still-open gap (no registry-fetch mechanism exists anywhere in this platform yet,
# not just here) — not done as a side effect of this path redirect. This redirect exists
# because vxzones (this script's original source) was archived 2026-08-04, migrated into
# vxparts; a fresh clone no longer has vxzones at all.
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${VXPARTS_BUNDLE:-$WS/../../../vxparts/parts/zone/linux/stack/probe-bundle/bundle}"
DEST="$WS/parts/linux-probe"

[[ -d "$SRC" ]] || {
  echo "error: no bundle at $SRC" >&2
  echo "  build it:  cd vxparts && ./parts/zone/linux/stack/probe-bundle/build.sh" >&2
  echo "  or point at one: VXPARTS_BUNDLE=/path/to/bundle $0" >&2
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
