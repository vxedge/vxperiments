#!/usr/bin/env bash
# Print the notes of a vxperiments release: that version's CHANGELOG.md section, then the packages
# it publishes and how to check them. Fails if the section is missing or empty, so a release
# cannot ship without one.
#
#   scripts/release-notes.sh v0.2.0
set -euo pipefail

cd "$(dirname "$0")/.."
ref=${1:?usage: release-notes.sh <tag>}
version=${ref#v}

section=$(awk -v v="[$version]" '
    index($0, "## " v) == 1 { found = 1; next }
    /^## \[/ { found = 0 }
    found' CHANGELOG.md)

if ! grep -q '[^[:space:]]' <<<"$section"; then
    echo "release-notes: CHANGELOG.md has no section for $version" >&2
    exit 1
fi

printf '%s\n\n---\n\n' "$section"
cat <<'NOTES'
Packages in this release (`catalog.yaml`):

NOTES
python3 - <<'PY'
import yaml
for p in yaml.safe_load(open("catalog.yaml"))["packages"]:
    print(f"- `{p['registry']}`: {p['title']}, `{p['digest']}`")
PY
cat <<'NOTES'

Each packed `.vxp` is attached with `SHA256SUMS`, and its package digest is the sha256 of the file.
Pull one by digest with `vxedge pkg pull`, and check its provenance with
`vxedge pkg verify --repo vxedge/vxperiments` or `gh attestation verify`.
NOTES
