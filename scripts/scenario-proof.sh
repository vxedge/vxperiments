#!/usr/bin/env bash
# Scenario proof (X11): a package that carries the reference scenario validates, locks, and packs
# to the same digest twice. The scenario and its vehicle are vendored from this checkout, as a
# package author would, into a throwaway package.
#
#   VXEDGE=/path/to/vxedge scripts/scenario-proof.sh
set -euo pipefail
cd "$(dirname "$0")/.."
vxedge=${VXEDGE:-vxedge}
repo=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$vxedge" pkg new proof --path "$work" >/dev/null
pkg=$work/proof
cd "$pkg"
"$vxedge" pkg vendor "$repo/vehicles/vx-reference-sedan-01" --replace >/dev/null || true
"$vxedge" pkg vendor "$repo/scenarios/urban-stop-line" >/dev/null || true
cat >main.yaml <<'YAML'
kind: experiment
id: proof
vehicles: [vx-reference-sedan-01]
baseline: bl-vx-reference-sedan-01
scenario: urban-stop-line
network:
  slices:
    - { id: adas, mode: vlan, vlan: 101, qos: { min_rate_mbps: 100, priority: 1 } }
parameters:
  speed: { type: number, unit: m/s, default: 13.9, min: 5, max: 20,
           binds: scenario.parameters.EgoTargetSpeed }
method: { duration_s: 10, repetitions: 1, warmup_s: 0 }
results: { artifact_dir: results/ }
YAML
sed -i 's/^  gpu: none$/  gpu: none\n  vxedge: ">=0.15.0"\n  simulator: [esmini]/' vxp.yaml
echo "== validate"
"$vxedge" experiment validate
"$vxedge" pkg lock >/dev/null
"$vxedge" pkg validate
echo "== pack twice"
mkdir -p "$work/a" "$work/b"
a=$("$vxedge" pkg pack --out "$work/a" | sed -n 's/^digest //p')
b=$("$vxedge" pkg pack --out "$work/b" | sed -n 's/^digest //p')
echo "first  $a"
echo "second $b"
[ -n "$a" ] && [ "$a" = "$b" ]
cmp "$work/a"/*.vxp "$work/b"/*.vxp
echo "== the scenario's files are in the package"
for f in assets/straight-200m.xodr assets/urban-stop-line.xosc; do
  cmp "$f" "$repo/scenarios/urban-stop-line/$f"
  grep -q "$f" vxp.lock
done
echo "scenario proof: ok"
