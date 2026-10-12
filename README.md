# vxperiments

Experiment manifests, campaign runners, analysis scripts and frozen results for the vxedge testbed.

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-lightgrey.svg)](LICENSE-DOCS)
[![CI](https://github.com/vxedge/vxperiments/actions/workflows/ci.yml/badge.svg)](https://github.com/vxedge/vxperiments/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/tag/vxedge/vxperiments?label=release)](https://github.com/vxedge/vxperiments/tags)

vxedge is an open, all-software testbed for mapping 5G network slices onto zonal and central software-defined-vehicle (SDV) E/E architectures on a single machine. Every published number ships with the manifest and image digests that produced it.

Every experiment is a self-contained workspace folder with its manifests, campaign runner and results. Each hypothesis gets its own experiment, and every number can be reproduced from its archive.

## Results index

| Experiment | Hypothesis | Verdict | Summary |
|---|---|---|---|
| `exp-001` | **H1**: VLAN + tc queue-tree reservations keep ADAS p99 near baseline under infotainment load | **Holds**: p99 0.91× baseline at 600 mbit | [`results/exp-001/`](results/exp-001/exp-001-summary.md) |
| `exp-002` → `exp-002b` | **H3**: virtual-ECU packaging affects zone-to-compute latency | **Holds**: virtio transport dominant (Δp50 −26.0 µs) | [`results/exp-002b/`](results/exp-002b/exp-002b-summary.md) |
| `exp-003` | **H4**: co-located OTA does not compromise the ADAS slice | **Holds**: Δp50 −0.3 µs, inside IQR | [`results/exp-003/`](results/exp-003/exp-003-summary.md) |
| `exp-010` | **H2**: real S-NSSAI slicing vs static VLAN mapping | **Holds**: p99 growth 0.95× vs 0.91× | [`results/exp-010/`](results/exp-010/exp-010-summary.md) |
| `exp-005` | Cold-start / first-packet latency after zone boot | Effect confirmed in 20 of 20 reps | [`experiments/exp-005/`](experiments/exp-005/) |
| `exp-014` | Wiring-harness topology: star vs daisy chain | Effect holds | [`experiments/exp-014/`](experiments/exp-014/) |

The summaries in `results/` are the primary record. Every number published from them is
registered in [`docs/FACTS.md`](https://github.com/vxedge/docs/blob/main/FACTS.md), the one file the
website and the READMEs quote; [`docs/RESULTS.md`](https://github.com/vxedge/docs/blob/main/RESULTS.md)
explains them and their caveats. Each frozen summary records the sha256 of the manifest that produced it. Superseded campaigns
are kept alongside the current ones and are never deleted.

## Layout

| Path | What |
|---|---|
| `experiments/<id>/` | One workspace per experiment: `main.yaml`, `vehicle.yaml`, `parts.yaml`, a `.vxp` marker, `scripts/run.sh`, and its own README |
| `vehicles/` | Shared vehicle manifests |
| `notebooks/` | One analysis script per experiment (`analyze_expNNN.py`) |
| `results/` | Frozen summaries (`*-summary.md` / `.csv`) and reproducibility checks |
| `scripts/` | Campaign runners and shared helpers (CPU governor, core pinning, frozen-results protection) |

## Reproduce an experiment

It needs the `vxedge`, `vxagents` and `vxtelemetry` binaries built side by side
([`docs/GETTING-STARTED.md`](https://github.com/vxedge/docs/blob/main/GETTING-STARTED.md)), and
CAP_NET_ADMIN, because the runner provisions real network namespaces, bridges and qdiscs.

```bash
cd experiments/exp-001-ws
sudo -E env "PATH=$PATH" ./scripts/run.sh --quick     # ~1 min pipeline check
sudo -E env "PATH=$PATH" ./scripts/run.sh --repro     # full campaign
python3 ../../notebooks/analyze_exp001.py results/<campaign-dir>
```

Host requirements for each experiment tier are in
[`docs/TESTBED-SETUP.md`](https://github.com/vxedge/docs/blob/main/TESTBED-SETUP.md).

## Links

- Site: <https://vxedge.dev>
- Architecture: [`docs/ARCHITECTURE.md`](https://github.com/vxedge/docs/blob/main/ARCHITECTURE.md)
- Results: [`docs/RESULTS.md`](https://github.com/vxedge/docs/blob/main/RESULTS.md) · Roadmap: [`docs/ROADMAP.md`](https://github.com/vxedge/docs/blob/main/ROADMAP.md)
- Contributing: [CONTRIBUTING](https://github.com/vxedge/.github/blob/main/CONTRIBUTING.md) · Security: [SECURITY](https://github.com/vxedge/.github/blob/main/SECURITY.md)
- License: Apache-2.0 ([`LICENSE`](LICENSE)) for code; CC BY 4.0 ([`LICENSE-DOCS`](LICENSE-DOCS)) for docs, results, figures and models
