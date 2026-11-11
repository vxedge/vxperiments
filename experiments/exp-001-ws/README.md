# exp-001: ADAS slice isolation under infotainment load (H1)

## The package

This folder is the `vxp/1` package `vxedge/exp-001`, version 0.2.0 (`vxp.yaml`). Its catalogue
alias is `exp-001`. `vxp.lock` records the digest of every file it holds, and `pkg pack` gives the
same package digest each time.

`main.yaml` holds the experiment and everything that used to live in `scripts/run.sh` and
`../../notebooks/analyze_exp001.py`:

| What | Where it was | Where it is |
|---|---|---|
| Load sweep 0, 100, 250, 400, 600 Mbit/s | `LOADS_MBPS` in `run.sh` | `campaign.sweep`, through the `load_mbps` parameter, which binds `traffic_profiles[infotainment-load].bandwidth_mbps` |
| 5 repetitions, 10 s of load, then a 60 s probe window | `REPS`, `WARMUP_S`, `PROBE_S` in `run.sh` | `campaign.repetitions`, `warmup_s`, `duration_s`, and the `repro` profile |
| The probe at 1000 pps, inside `node-adas-probe-01` | `vxprobe send` under `ip netns exec` | `measurements.ctl-rtt`, through the `probe_pps` parameter |
| H1: p99 at 600 Mbit/s within 2x of idle, loss within 0.5 points | `H1_P99_FACTOR` and the loss check in the notebook | `hypothesis`, `metrics` and `criteria` |

Its criteria give the notebook's verdict, `h1=pass` with the same values, on all five published
exp-001 campaigns (`../../scripts/verdict-parity.sh`, run by CI).

Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan --profile repro          # the 25 trials, checked; touches nothing
vxedge campaign start --profile repro         # one archive per trial, then the verdict
```

The `quick` profile checks the pipeline only and is never reported. It runs one repetition of the
five loads with `run.sh --quick`'s 3 s and 12 s windows. Unlike `run.sh --quick`, it keeps all five
loads and 1000 pps, because a profile changes only repetitions and windows.

Nothing here is fetched: both parts are host processes (`local/vxprobe:host-process`,
`local/vxtraffic:host-process`), and `vehicle.yaml` is this experiment's own, not a copy of a
reference vehicle.

### Compared with the frozen campaign

`../../results/exp-001/campaign.json` records the frozen exp-001 campaign: each of its 25
archives, the trial it is, and its sha256. A trial's id is the one this package's campaign gives
the same point: `r<n>-defaults` at 0 Mbit/s, which is `load_mbps`'s default, and
`r<n>-load_mbps=<load>` at the other loads. The archives are the published ones, from the Zenodo
record that `../../scripts/verdict-parity.sh --fetch` reads (`exp-001.tgz`), unpacked into
`../../results/exp-001/`. Then a new campaign is compared with the frozen one through vxAPI:

```bash
vxedge campaign compare <campaign id> exp-001 --reference-workspace <this repo>
```

vxedged reads each archive the record names from that folder and refuses one whose sha256
differs (`ERROR_REASON_CHECKSUM_MISMATCH`). This needs vxedge 0.17.0 or later.

## The bash campaign

`scripts/` holds the campaign runners that came before the package's campaign. `.vxpignore` keeps
them out of the package. `scripts/lib/` is vendored; `../../scripts/lib/` stays the canonical copy,
and CI asserts the two are byte-identical.

```bash
cd experiments/exp-001-ws
sudo -E env "PATH=$PATH" ./scripts/run.sh --quick        # pipeline validation, NOT reportable
sudo -E env "PATH=$PATH" ./scripts/run.sh --repro        # the campaign
```

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
