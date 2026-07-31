# exp-002b (workspace form)

The §6.0 workspace that replaces `../exp-002b.yaml` (H3 decomposition: machine type, virtio
transport, vhost, management layer, plus per-arm resource cost). Run it from **inside this
directory**:

```bash
cd experiments/exp-002b-ws
vxedge experiment up
vxedge experiment down
```

## Status: structurally equivalent, not yet numerically equivalent

`../exp-002b.yaml` stays authoritative until a campaign run reproduces the frozen numbers
through this workspace.

**Verified** — identical gateway, node, traffic and 5G plans across all six arms:

```bash
# One planning path, so there is nothing left to diff: validating the workspace runs the same
# cross-file checks and model invariants `up` runs.
vxedge manifest validate --manifest experiments/exp-002b-ws --json
```

The plan-equivalence check that signed this migration off used `plan-diff`, which compared the
§6.0 and §6.1 planning paths. Both the example and §6.1's planning path are gone (2026-07-31),
so the result is recorded here rather than re-runnable: **IDENTICAL** — same interface names,
vlans, slices, addresses, bundles and backends.

## The three arms nobody brings up

`node-q35-pci-01`, `node-q35-vhost-01` and `node-mvm-pci-01` are declared here but never
`zone up`'d. Their *taps* are the point: the gateway creates them, and
`scripts/run-exp-002b.sh` launches QEMU on them with each arm's exact machine/transport/vhost
flags — the only way to vary one mechanism at a time. The runner names those taps, and it can
now do so safely: interface names are derived from the device id rather than from position, so
`node-q35-pci-01` is `vz-node-q-691e` no matter what else the experiment declares. Under the
old positional naming they were `vz3`/`vz4`/`vz5` and adding any device ahead of them in
traversal order would have silently pointed the runner at a different arm.

To look a name up rather than recompute it, `vxedge zone list` prints `port=` and `peer=` for
every device.

## Structure

| File | `kind` | What it owns |
|---|---|---|
| `exp-002b.vxp` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the test: slice + QoS, method, telemetry, results |
| `vehicle.yaml` | `vehicle` | six packagings of one ECU, and their addresses |
| `parts.yaml` | `baseline` | the identical payload every arm carries |

See `../exp-002-ws/README.md` for what migrating this pair of experiments needed from §6.0.
