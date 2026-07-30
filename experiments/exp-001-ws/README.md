# exp-001 (workspace form)

The §6.0 workspace that replaces `../exp-001.yaml`. Run it from **inside this directory**:

```bash
cd experiments/exp-001-ws
vxedge experiment up          # gateway + zones; does NOT start traffic
vxedge experiment down
```

## Status: structurally equivalent, not yet numerically equivalent

`../exp-001.yaml` stays authoritative until a campaign run reproduces the frozen H1 numbers
through this workspace. Phase-1 results reproduce at the `v0.1.0` tag regardless, so nothing
here can invalidate them.

**Verified**: this workspace and the frozen manifest produce a byte-identical `GatewayPlan` and
`TrafficPlan` — same endpoint names (`vz0`/`vzp0`, `vz1`/`vzp1`), VLANs, slices and addresses.
That matters because `scripts/run-exp-001.sh` addresses `vzp0`/`vzp1` by name; a migration that
renumbered them would keep validating and quietly measure the wrong interface. Checked with:

```bash
cargo run -p vxedge-core --example lower-workspace -- --plan experiments/exp-001.yaml
cargo run -p vxedge-core --example lower-workspace -- --plan experiments/exp-001-ws
```

**Not verified**: p50/p95/p99 equivalence against the frozen campaign. That needs a full run on
a host where the daemon can provision (root, or passwordless sudo for `ip`/`bridge`/`tc`).

## What migrating this found

Three defects in §6.0, none of which the scaffold templates could surface:

- **`backend` was not expressible at all.** These zones are container-backed host processes;
  they lowered to `kind: vm`, defaulted to libvirt, and failed with `MissingBundle`. `backend`
  is the H3 variable, so without this fix exp-002/002b could not have been migrated either.
- **`local/vxprobe:host-process` was rejected** as an unpinned published ref, though it names no
  artifact to pin.
- **`vxedged` sudo-ed even when already root**, which is how the campaign scripts run it.
