# vxperiments

The vxedge experiment catalogue: one `vxp/1` package per experiment, the frozen summaries of every
published campaign, and the checks that tie each published verdict to its package.

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Docs: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-lightgrey.svg)](LICENSE-DOCS)
[![CI](https://github.com/vxedge/vxperiments/actions/workflows/ci.yml/badge.svg)](https://github.com/vxedge/vxperiments/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/tag/vxedge/vxperiments?label=release)](https://github.com/vxedge/vxperiments/tags)

vxedge is an open, all-software testbed for mapping 5G network slices onto zonal and central software-defined-vehicle (SDV) E/E architectures on a single machine. Every published number ships with the manifest and image digests that produced it.

Each experiment is a self-contained package folder: its documents, its campaign and profiles, its
metrics and its acceptance criteria. vxedge runs the campaign and judges the criteria. Each
hypothesis gets its own experiment.

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
explains them and their caveats. Each frozen summary records the sha256 of the input that produced
it. Superseded campaigns are kept alongside the current ones and are never deleted.

The raw per-run archives are a dataset on Zenodo,
[10.5281/zenodo.23804197](https://doi.org/10.5281/zenodo.23804197) (all versions). The current
version, 2026-11-v2, is [10.5281/zenodo.24192950](https://doi.org/10.5281/zenodo.24192950), and the
GitHub release
[`archives-2026-11-v2`](https://github.com/vxedge/vxarchives/releases/tag/archives-2026-11-v2) of
vxedge/vxarchives mirrors it file for file. The summaries stay in git.

## Packages

| Alias | Folder | What |
|---|---|---|
| `exp-001` | [`experiments/exp-001-ws`](experiments/exp-001-ws) | H1: ADAS slice isolation under infotainment load |
| `exp-002` | [`experiments/exp-002-ws`](experiments/exp-002-ws) | H3: container, microVM and full-VM packagings of one ECU |
| `exp-002b` | [`experiments/exp-002b-ws`](experiments/exp-002b-ws) | H3 decomposed into machine, transport, vhost-net and management, with each arm's cost |
| `exp-003` | [`experiments/exp-003-ws`](experiments/exp-003-ws) | H4: the ADAS slice under a co-located OTA burst |
| `exp-005` | [`experiments/exp-005`](experiments/exp-005) | Cold-start first-packet latency after zone boot |
| `exp-010` | [`experiments/exp-010-ws`](experiments/exp-010-ws) | H2: S-NSSAI slicing against exp-001's static VLAN mapping |
| `exp-014` | [`experiments/exp-014`](experiments/exp-014) | Wiring-harness topology: star against daisy chain |
| `exp-015` | [`experiments/exp-015`](experiments/exp-015) | Kuksa use cases on a vehicle's signal plane, a functional suite |
| `exp-016` | [`experiments/exp-016`](experiments/exp-016) | The Kuksa databroker measured across a slice |
| `exp-017` | [`experiments/exp-017`](experiments/exp-017) | VSS scenarios on the signal plane, a functional suite |

[`catalog.yaml`](catalog.yaml) lists each package's id, version, package digest, hypothesis,
registry reference and frozen campaign. Each package's README says what it measures, what its
criteria are, and how it relates to the published results.

## Layout

| Path | What |
|---|---|
| `experiments/<folder>/` | One `vxp/1` package: `vxp.yaml` (id, version, entry, requirements), `vxp.lock` (the digest of every file, and the parts and images it pins), `main.yaml` (the experiment: typed intent, metrics, criteria, the campaign and its profiles), `vehicle.yaml`, `parts.yaml`, and a README. Every file in the folder counts toward the package digest |
| `catalog.yaml` | Generated by `scripts/packages.py` from the packages. CI fails when it is not current |
| `results/` | Frozen summaries, frozen campaign records (`<exp>/campaign.json`) and gate runs ([`results/README.md`](results/README.md)) |
| `scripts/` | `packages.py` (the catalogue), `verdict-parity.sh` with its table and checksums in `parity/`, `frozen-checks.py`, `scenario-proof.sh` and `release-notes.sh` |
| `vehicles/` | Shared and reference vehicles, used by the gate runs in `results/`; a package can vendor one with `vxedge pkg vendor` |
| `scenarios/` | The reference scenario `urban-stop-line` |
| `ci/` | `vxedge-release.txt`: the vxedge release that CI and the release workflow run |

## Use a package

Install vxedge ([`docs/GETTING-STARTED.md`](https://github.com/vxedge/docs/blob/main/GETTING-STARTED.md));
each `vxp.yaml` names the oldest release it needs under `requires`. These checks are offline, with
no daemon:

```bash
cd experiments/exp-001-ws
vxedge experiment validate      # every cross-file check and model invariant
vxedge pkg validate             # those, plus packable files and a vxp.lock that matches
vxedge pkg inspect              # the descriptor, the lock and the package digest
```

A campaign runs through vxAPI, against a vxedged. Planning touches nothing; running provisions
real network namespaces, bridges and qdiscs, so vxedged needs CAP_NET_ADMIN. Host requirements per
tier are in [`docs/TESTBED-SETUP.md`](https://github.com/vxedge/docs/blob/main/TESTBED-SETUP.md), and
`vxedge doctor` checks a host against them.

```bash
vxedge campaign plan --profile repro          # the trials, checked
vxedge campaign start --profile repro         # one archive per trial, then the verdict
vxedge campaign status <campaign id>
vxedge campaign verdict <campaign id>
```

`repro` is the published protocol. `quick` checks the pipeline only, and its numbers are never
reported. A campaign writes its archives, `campaign.json` and `verdict.json` under
`results/<campaign id>/` in the package folder. An experiment that reads a frozen campaign, such as
exp-010 (H2 against exp-001), takes `--reference-workspace <this repo>`. The same option compares a
new campaign with a frozen one:

```bash
vxedge campaign compare <campaign id> exp-001 --reference-workspace ../..
```

Archives can be judged offline too, with no daemon:

```bash
vxedge results verdict --experiment experiments/exp-001-ws <archives or folders of .zip>
```

Archives written before campaigns named their trials take `--name`, such as
`'rep{repetition}-load{load_mbps}'`.

## Re-judge the published verdicts

```bash
VXEDGE=/path/to/vxedge scripts/verdict-parity.sh --fetch
```

This downloads each dataset in [`scripts/parity/parity.tsv`](scripts/parity/parity.tsv) from Zenodo
version 2026-11-v2, checks it against [`scripts/parity/SHA256SUMS`](scripts/parity/SHA256SUMS), that
version's published checksums, and judges it with the criteria of the package the table names. It
needs `curl`, `jq`, and `python3` with PyYAML. Every dataset must give its published verdict, and
all 16 do. exp-005's and exp-010's archives hold probe summaries, not samples, so they are not in
the table. exp-010 has run live as a package since: its 2026-11-13 repro, judged by
`vxedge campaign verdict`, is [`results/exp-010-repro-2026-11-13`](results/exp-010-repro-2026-11-13/exp-010-summary.md).

## Checks and releases

Every pull request runs the pinned vxedge release in [`ci/vxedge-release.txt`](ci/vxedge-release.txt),
after checking the archive's sha256 against that file and its build provenance against the vxedge
release workflow. CI then:
- validates every package, checks its lock, and packs it twice to compare the digests;
- plans each package's campaign for its default and every profile on an unprivileged vxedged;
- checks that `catalog.yaml` is current, and that no package a release published changed without
  a new version;
- runs verdict parity, the scenario proof and the exp-010 notebook check.

A tag `vMAJOR.MINOR.PATCH` publishes a catalogue release. Each package is packed and pushed to
`ghcr.io/vxedge/experiments/<name>`, tagged with its own version from `vxp.yaml`, and attested.
The packed files, `SHA256SUMS` and `catalog.yaml` are attached to a GitHub Release, whose notes are
the tag's `CHANGELOG.md` section. The repository's tag versions the catalogue; each package keeps
its own version. `catalog.yaml` on `main` can list versions no release has pushed yet; a release's
own `catalog.yaml` lists what it pushed.

A released package is pulled by the package digest its release's `catalog.yaml` records:

```bash
vxedge pkg pull ghcr.io/vxedge/experiments/exp-001@sha256:<digest> --into exp-001
```

## Links

- Site: <https://vxedge.dev>
- Architecture: [`docs/ARCHITECTURE.md`](https://github.com/vxedge/docs/blob/main/ARCHITECTURE.md)
- Results: [`docs/RESULTS.md`](https://github.com/vxedge/docs/blob/main/RESULTS.md) · Roadmap: [`docs/ROADMAP.md`](https://github.com/vxedge/docs/blob/main/ROADMAP.md)
- Contributing: [CONTRIBUTING](https://github.com/vxedge/.github/blob/main/CONTRIBUTING.md) · Security: [SECURITY](https://github.com/vxedge/.github/blob/main/SECURITY.md)
- License: Apache-2.0 ([`LICENSE`](LICENSE)) for code; CC BY 4.0 ([`LICENSE-DOCS`](LICENSE-DOCS)) for docs, results, figures and models
