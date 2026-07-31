# exp-002 (workspace form)

The §6.0 workspace that replaces `../exp-002.yaml` (H3: virtual-ECU packaging vs
zone-to-gateway latency). Run it from **inside this directory**:

```bash
cd experiments/exp-002-ws
vxedge experiment up          # gateway + zones; does NOT start traffic
vxedge experiment down
```

## Status: structurally equivalent, not yet numerically equivalent

`../exp-002.yaml` stays authoritative until a campaign run reproduces the frozen H3 numbers
through this workspace. Phase-1 results reproduce at the `v0.1.0` tag regardless.

**Verified** — this workspace and the frozen manifest produce identical gateway, node, traffic
and 5G plans:

```bash
# One planning path, so there is nothing left to diff: validating the workspace runs the same
# cross-file checks and model invariants `up` runs.
vxedge manifest validate --manifest experiments/exp-002-ws --json
```

The plan-equivalence check that signed this migration off used `plan-diff`, which compared the
§6.0 and §6.1 planning paths. Both the example and §6.1's planning path are gone (2026-07-31),
so the result is recorded here rather than re-runnable: **IDENTICAL** — same interface names,
vlans, slices, addresses, bundles and backends.

**Not verified**: p50/p95/p99 equivalence against the frozen campaign, which needs a full run on
a provisioning-capable host (root, or passwordless sudo for `ip`/`bridge`/`tc`, plus KVM).

## What migrating this needed

exp-002 was the experiment §6.0 could not express, and it took two schema changes and two
fixes to get here:

- **Endpoint addresses.** The three arms share one VLAN and one subnet; the *address* is what
  tells them apart, and it is how the probe reaches each arm separately. §6.0's endpoints were
  bare strings with nowhere to put one. They now take an object form —
  `{ node: node-cont-01, port: eth0, ip: 10.101.0.11/24 }` — alongside the bare form, which
  stays right whenever no fixed address is needed.
- **Interface names stopped being positional.** `vz0`/`vz1`/`vz2` were assigned in traversal
  order, and exp-002 declares its arms `cont, microvm, libvirt` while §6.0 sorts them to
  `cont, libvirt, microvm` — so two arms swapped interfaces between the two schema paths, and
  the campaign would have measured libvirt while reporting microvm. Names are now derived from
  the device id (`vz-node-c-32cc` for `node-cont-01`), so order decides nothing.
- **A VM's guest bundle was unreachable.** The zone planner looked up a device's software by
  *function id equals device id*, which is true in §6.1 and false here — so every libvirt and
  qemu-microvm arm planned as a VM with no bundle to boot. It now resolves through
  `deployed_on`, which is what the function layer is for.
- **`zone up` could not select one arm.** A zone is a *region*, and all three arms sit in
  `front-left`, so region-only selection could start only all three at once — the concurrent
  guest CPU contention that invalidated exp-002b's first campaign. `zone up --vxid` now accepts
  a device id as well, which is what `scripts/run-exp-002.sh` uses to hold one arm up at a time.

## Structure

| File | `kind` | What it owns |
|---|---|---|
| `exp-002.vxp` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the test: slice + QoS, method, telemetry, results |
| `vehicle.yaml` | `vehicle` | the system under test: three packagings of one ECU, and their addresses |
| `parts.yaml` | `baseline` | the identical payload each arm carries |

Device ids are the frozen manifest's node ids so the two forms stay diffable, and so the
recorded results keep naming the same things.
