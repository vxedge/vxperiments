# exp-001 (workspace form)

The §6.0 workspace that replaces `../retired-6.1/exp-001.yaml`. Run it from **inside this directory**:

```bash
cd experiments/exp-001-ws
vxedge experiment up          # gateway + zones; does NOT start traffic
vxedge experiment down
```

## Status: structurally equivalent, not yet numerically equivalent

`../retired-6.1/exp-001.yaml` stays authoritative until a campaign run reproduces the frozen H1 numbers
through this workspace. Phase-1 results reproduce at the `v0.1.0` tag regardless, so nothing
here can invalidate them.

**Verified**: this workspace and the frozen manifest produce a byte-identical `GatewayPlan` and
`TrafficPlan` — same endpoint names, VLANs, slices and addresses. That matters because
`scripts/run-exp-001.sh` addresses the veth peers by name; a migration that moved them would
keep validating and quietly measure the wrong interface. Checked with:

```bash
# One planning path, so there is nothing left to diff: validating the workspace runs the same
# cross-file checks and model invariants `up` runs.
vxedge manifest validate --manifest experiments/exp-001-ws --json
```

The plan-equivalence check that signed this migration off used `plan-diff`, which compared the
§6.0 and §6.1 planning paths. Both the example and §6.1's planning path are gone (2026-07-31),
so the result is recorded here rather than re-runnable: **IDENTICAL** — same interface names,
vlans, slices, addresses, bundles and backends.

Those names changed once, on 2026-07-31: positional `vz0`/`vzp0` became `vz-node-a-c06a`/
`vzp-node-a-c06a`, derived from the device id so that adding or reordering a device can no
longer renumber anything. Both forms moved together, so this workspace stayed identical to the
manifest across the change.

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
