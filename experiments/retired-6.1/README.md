# Retired §6.1 manifests — provenance only

These five documents are the experiment manifests the frozen results in `../../results/` were
produced from. They are **not inputs**: §6.1 stopped being a provisioning input on 2026-07-31
and its schema was deleted from `vxedge-core`, so nothing can read them. Pointing a tool at one
reports what the document is and where to go instead.

They live here, one directory down from the workspaces that replaced them, so that
`experiments/` holds only things that run. Each has a successor:

| Retired | Replaced by |
|---|---|
| `exp-001.yaml` | `../exp-001-ws/` |
| `exp-002.yaml` | `../exp-002-ws/` |
| `exp-002b.yaml` | `../exp-002b-ws/` |
| `exp-003.yaml` | `../exp-003-ws/` |
| `exp-010.yaml` | `../exp-010-ws/` |

Every successor was verified to produce plans identical to the manifest it replaced — same
interface names, vlans, slices, addresses, bundles and backends. Each workspace's README
records that check.

To read one of these against the schema it was written to, use the **`v0.1.0` tag**, where
`vxedge-core::manifest` still exists. That tag is also where phase-1 reproducibility is
anchored, so it is the right place to go for anything historical rather than this directory
plus a mental model of a deleted parser.
