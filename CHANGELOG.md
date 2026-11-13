# Changelog

All notable changes to this repo are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/) — see `docs/VERSIONING.md` in the `docs` repo.

Result summaries (`results/*/*.md`,`.csv`) are tracked here, not versioned as releases —
each is reproducible from its manifest + digests per the reproducibility gate
(`.claude/skills/experiment-methodology`), which is a finer-grained provenance mechanism
than a repo tag.

## [Unreleased]

### Added

- exp-014 0.3.0: a ring harness beside the star and the daisy chain. Three `ring-*` devices take
  the shorter way round the chain's path closed back to the backbone (front-left and rear-left
  one hop, front-right two), with three arms and a `ring` criterion: the ring's farthest
  position sits below the chain's farthest by more than the star arms' spread (at least 1 µs),
  and still costs a hop over its front-left. The frozen 2026-08-05 campaign has no ring arms, so
  verdict parity now expects `hops=pass ring=inconclusive` for it.
- `results/exp-014-repro-2026-11-13`: exp-014 0.3.0's live run on vxedge 0.27.0, `repro` profile,
  45 trials. Both criteria pass: each chain hop adds about 60 µs at p50, and the ring's
  front-right sits 60.0 µs below the chain's rear-left.
- `results/exp-010-repro-2026-11-13`: exp-010's first live run as a package, `repro` profile,
  vxedge 0.27.0 with the digest-pinned 5G images. H2 passes: p99 growth from 0 to 600 Mbit/s is
  0.972x against a bound of 1.006x (1.10 times exp-001's 0.914x). All 25 trials are complete, the
  worst loss is 0.0017 %, and the archives' `image_digests` name the three 5G images. The published
  2026-10-30 repro read 1.00x. Absolute p99 is about 300 µs here, about 340 µs there; H2 compares
  growth.

### Removed

- `notebooks/` (`analyze_exp010.py`, `cold_start.py`, `check-exp010.sh`) and its CI step. exp-010
  now runs live, and vxedge judges its H2 from the archives. The files stay at the `v0.2.1` tag,
  and exp-005's and exp-010's links point there.

### Changed

- `results/exp-001/campaign.json` is the `vxarchive/2` record from Zenodo 2026-11-v2
  (`exp-001.tgz`), whose archive digests match the published archives. The `vxarchive/1` digests it
  held cannot be read by vxedge 0.26.0 or later, so exp-010's `--reference-workspace` needs this
  record with the published archives unpacked beside it.
- CI validates the workspaces with vxedge 0.28.0, which reads only `vxp.yaml` packages and
  `vxarchive/2` archives and pins the 5G images by digest.
- exp-005 0.2.2 and exp-010 0.2.1 are locked with vxedge 0.27.0; exp-010 requires it. Its lock now pins the 5G core
  (`ghcr.io/vxedge/parts/gw/5gc/os/open5gs:0.1.0`), RAN (`gw/ran/os/ueransim:0.1.0`, carrying
  the vxprobe 0.2.3 release) and database (`mongo:7`) images by digest, which the 5G path runs
  and an archive records in `image_digests`. Before this, its lock listed no image, because
  vxedged started locally built images by bare name.
- `README.md` and `AGENTS.md` describe the package-only repository: the packages and
  `catalog.yaml`, how to validate, plan, run and judge a package with vxedge, how `results/`
  relates to the Zenodo record (2026-11-v2, mirrored as the vxarchives release
  `archives-2026-11-v2`), verdict parity, the exp-010 notebook exception, and the catalogue
  release. `results/README.md` describes the frozen record as it is now.
- `results/exp-001-measurements-2026-11-09` and `results/done-means-gate-2026-11-10` link the
  runner, notebook and criteria they name at the `v0.2.1` tag. Their accounts are unchanged.
- Package READMEs no longer give the removed runners' commands. The runners, notebooks and
  `retired-6.1` manifests they cite as history link to the `v0.2.1` tag (or `v0.2.0`, for files
  removed before it), and each package's `tools/README.md` points at its criteria and
  `vxedge campaign verdict` / `vxedge results verdict` in place of `notebooks/`. `.vxpignore`,
  which only kept the removed `scripts/` out, is deleted from exp-001, exp-002, exp-005, exp-010
  and exp-014. Each changed package has a new version and lock, with vxedge 0.25.0; criteria and
  experiment documents are unchanged, and all 16 parity datasets still give their published
  verdicts:
  - exp-001 0.2.1 (`sha256:fab4ab23d059…`): the bash-campaign and §6.1-status sections become
    "Before the package", with the plan-equivalence record kept.
  - exp-002 0.2.1 (`sha256:6a5453a17706…`).
  - exp-002b 0.2.1 (`sha256:a379839b730b…`).
  - exp-003 0.2.1 (`sha256:841a01da171a…`).
  - exp-005 0.2.2 (`sha256:798dee378c2c…`): its README states vxedge 0.20.0, as `requires` does,
    and describes the probe as the declared measurement.
  - exp-010 0.2.1 (`sha256:d11665f6f5d6…`): its README states that the package has not run live
    and that `notebooks/analyze_exp010.py` checks H2 until it has; "Sharing it" describes
    `vxedge pkg pack` and the catalogue release.
  - exp-014 0.2.1 (`sha256:9af423c231fc…`).
  - exp-016 0.2.1 (`sha256:4bbb38ed12a4…`): its host preparation points at the published run's
    README.
- Verdict parity reads version 2026-11-v2 of the Zenodo record that holds the raw archives
  ([10.5281/zenodo.24192950](https://doi.org/10.5281/zenodo.24192950)), in place of 2026-11
  (10.5281/zenodo.23810053). Its `SHA256SUMS` is the published one, 25 archives, and the table
  gains `exp-003-repro-2026-11-13`, whose archives a campaign wrote and named (`h4=pass`). All 16
  datasets give their published verdicts with vxedge 0.25.0.
- The parity table and checksums moved from `notebooks/criteria/` to `scripts/parity/`, and the
  parity check compares the engine with the published verdicts.
- CI's `runners` job is now `static` ("scripts + exp-010 notebook"): shellcheck over
  `scripts/*.sh` and `notebooks/*.sh`, a compile of the Python scripts, and
  `notebooks/check-exp010.sh`, which downloads exp-010 and exp-001 from the pinned record, runs
  `notebooks/analyze_exp010.py`, and requires the published `results/exp-010/` summary and its H2
  verdict. exp-010's archives hold probe summaries, not samples, so the verdict engine cannot judge
  them; the notebook stays until exp-010 runs live (`notebooks/README.md`).

### Removed

- The bash campaign runners: `scripts/` in exp-001 (`run.sh`, `run-measurements.sh`), exp-002,
  exp-005, exp-010 and exp-014, each with its vendored `scripts/lib/`; the canonical
  `scripts/lib/` (`check-runners.sh`, `freshness.sh`, `host_pinning.sh`, `results_dir.sh`);
  `scripts/run-smoke.sh` and `scripts/calibrate-exp-010-noise-floor.sh`. Each experiment's
  package campaign replaces them. Package contents and digests are unchanged: `.vxpignore` already
  kept `scripts/` out.
- The analysis notebooks: `analyze_exp001.py`, `analyze_exp002.py`, `analyze_exp002b.py`,
  `analyze_exp003.py`, `analyze_exp005.py`, `analyze_exp014.py`, `analyze_noise_floor.py` and
  `compare_exp001_paths.py`. Each package's `main.yaml` holds its acceptance rule.
  `analyze_exp010.py` and the `cold_start.py` it imports stay.
- `experiments/retired-6.1/`, the §6.1 manifests, and CI's check that vxedge refuses them.

## [0.2.1] - 2026-11-13

Seven experiments join the catalogue as packages: exp-002 (H3, virtual-ECU packaging), exp-002b (H3
decomposed into its mechanisms, with each arm's cost), exp-003 (H4, OTA co-location), exp-010 (H2,
real S-NSSAI slicing against static VLAN mapping), exp-015 (Kuksa use cases), exp-016 (the Kuksa
databroker measured across a slice) and exp-017 (VSS scenarios). exp-002 probes each packaging of
one ECU from the host, one arm up at a time, and its VM arms boot the published probe bundle.
exp-003's OTA service signs a fresh burst artifact at every start, and in the burst arm one client
downloads it back to back. exp-010's probe runs from the ADAS slice's 5G UE, and H2 is judged
against exp-001's frozen campaign. exp-015 and exp-017 are functional suites on vxedge's checks;
their test client is built locally from `experiments/exp-015/tools/kv2`. exp-016 runs kuksa-perf as
check steps whose percentiles vxedge 0.25.0 reads as samples, so its criteria aggregate them across
trials. exp-002b's six arms are all vxedge devices, the three its script booted by hand now set
their machine, NIC transport and vhost-net in a `qemu:` block, and each arm's CPU and memory come
from the daemon's exporter. exp-005 0.2.1 gives its `quick` profile the scripts' 10 s steady window.
The packages need vxedge 0.23.0, and exp-002b and exp-016 need 0.25.0. exp-001 and exp-014 are
unchanged at 0.2.0. No published number changes.

### Added

- `experiments/exp-003-ws` is the `vxp/1` package `vxedge/exp-003` 0.2.0, locked (X9.2). Its
  `main.yaml` holds what `scripts/run.sh` and `notebooks/criteria/exp-003.yaml` held:
  - The two arms (baseline, ota-burst) are `campaign.arms`, with `quick` and `repro` profiles.
  - The OTA service publishes its own store (vxedge 0.23.0): a fresh root key and a 5 MB random
    `burst-artifact`, signed at every start, in place of a store `run.sh` signed once per host
    under `/tmp`.
  - The burst is the service's `fetch` client, which `ota_clients` turns on per arm: one
    `vxota-probe fetch` downloading and verifying the artifact back to back from provisioning to
    teardown, as `run.sh` started it by hand. Its deliveries are archived on the service's entity
    and reported, not judged.
  - The probe is `measurements.probe`, from node-adas-probe-01 across the adas VLAN.
  - H4's rule is typed intent: the burst raises the median p50 by no more than the larger IQR of
    the two arms, at least 1 µs, with loss at most 1 % in either arm. Verdict parity reads the
    package: h4=pass on `exp-003`, `exp-003-repro-2026-08-03` and `exp-003-repro-2026-10-30`.
  - Live, the `quick` and `repro` profiles ran every trial, the burst client delivering throughout
    the burst arm with no failed delivery and no probe loss in either arm.
  - The frozen campaign was measured with a debug-built vxprobe. Rerun on vxedge 0.25.0 with
    release builds of vxprobe 0.2.3 and vxota 0.1.2, H4 holds: 35.30 µs baseline against
    35.33 µs during the burst, +0.03 µs against a 1.41 µs threshold, with no loss. Debug builds and
    a release probe beside a debug OTA client also pass. An earlier release-probe campaign that
    failed H4 was not reproduced. Its run folder was under an indexed home directory, and its
    burst-arm p99 was inflated (388 µs, against 63.5 µs on the rerun). Each
    archive's `metadata.json` now records every tool's build profile.
  - `results/exp-003-repro-2026-11-13` summarises the release rerun. Its ten archives pass
    `vxtelemetry verify` (index, workspace identity and package digest) and give H4 pass offline
    through `vxedge results verdict`. They go in the archive record's next version.
- `experiments/exp-015` is the `vxp/1` package `vxedge/exp-015` 0.2.0, locked (X9.2): the Kuksa
  use cases, a functional suite on vxedge 0.22.0's `checks`. Its `main.yaml` holds what
  `cases-v2.sh`, `lib.sh` and `flags.sh` held:
  - each client call is a step that runs kv2 in a node's namespace, a subscriber or provider a
    background step, and a gone provider's claim is waited out by a step repeated until actuate
    finds no provider;
  - the databroker's restarts and the denied sender's frames are `observe` steps, compared;
  - the flag cases run two throwaway brokers with the v2 client, in place of the v1 CLI;
  - every `PASS` and `FAIL` line is a case of the criterion `kuksa-v2` (50 cases), and every `OBS`
    line an `observe` case.
  The vehicle is vx-vehicle-03 without its OTA service, whose store is built per host, and its
  guest zones boot the published probe bundle 0.1.1 and reflector capsule 0.1.0. Live on a quick
  run, all 50 cases passed and the observations matched `results/kuksa-cases-2026-11-04`. The
  signal-plane lifecycle checks `run.sh` repeated first are not part of the package.
- `experiments/exp-016` is the `vxp/1` package `vxedge/exp-016` 0.2.0, locked (X9.2, X9.15): the
  databroker measured across a slice with kuksa-perf. Its `main.yaml` holds what `run.sh`,
  `build.sh` and `summarize.py` held:
  - each kuksa-perf run is a step of the published kuksa-perf part (`aa6fba0`) in a node's
    namespace, and `tools/perf.awk` adds its counts and percentiles as JSON lines after the run's
    own output;
  - the steps' `samples` (vxedge 0.25.0) read those as series on `checks/<step>`, so the metrics
    are each setup's p50 and p99, and the criteria compare setups across five repetitions:
    `slice-publish` and `slice-actuate` (idle minus baseline beyond the larger spread),
    `load-publish` and `load-actuate` (loaded within the larger spread of idle), `runs` (every
    measured run received updates) and `setup` (the broker unrestarted and refused from `info2`,
    the load reaching `info2`);
  - the load and the CPU load are background steps, and the release 0.3.2 run, the denial from
    `info2` and the issue-233 runs are steps of every trial.
  The hypothesis and criteria are written from the published result, which they reproduce. One
  trial runs the setups in one order, where the script rotated it; host preparation (governor,
  `/dev/cpu_dma_latency`) stays outside the package. The vehicle drops its per-host OTA store and
  boots the published probe bundle and reflector capsule.
- Verdict parity reads exp-016's two frozen runs, `results/broker-slice-main-2026-11-04` and
  `results/broker-slice-2026-11-04`, from their committed kuksa-perf output:
  `scripts/frozen-checks.py` builds their trial archives through the package's own `perf.awk`.
  Both give `runs`, `slice-*` and `load-*` `pass`, with the published differences (+8 and +11 µs
  over the slice, +1 µs under load, on the main run). `setup` is `inconclusive`, because those
  runs recorded it once in their transcripts, not as step output.
- `experiments/exp-017` is the `vxp/1` package `vxedge/exp-017` 0.2.0, locked (X9.2): the VSS
  scenarios, the same way. `scenarios.sh` and `vss61.sh` are its steps and cases (34 judged, the
  rest observed), the throwaway brokers run `on: alone` with their VSS file from `assets/`, and
  `compare.py` is `tools/compare.py`, printing one JSON line. Live on a quick run, all 34 cases
  passed and the observations matched `results/vss-scenarios-2026-11-04`.

- `experiments/exp-002b-ws` is the `vxp/1` package `vxedge/exp-002b` 0.2.0, locked (X9.2, X9.18).
  Its `main.yaml` holds what `scripts/run.sh` and `notebooks/criteria/exp-002b.yaml` held:
  - The six arms (container, microvm-mmio, libvirt-q35, q35-pci, q35-vhost, microvm-pci) are
    `campaign.arms`, with `quick` and `repro` profiles, each brought up alone through `isolate`.
  - The three arms `run.sh` launched QEMU for itself are `qemu-microvm` devices whose `qemu:` block
    (vxedge 0.25.0) sets the machine, the NIC's virtio transport and vhost-net. All five VM arms
    boot the published probe bundle 0.1.2, which declares its reflector and a PCI-capable guest.
  - The probe is `measurements.probe`, `from: host` to the arm's address.
  - The four decompositions (transport, machine, vhost-net, management) are the criteria, unchanged,
    each with its two 1 % loss guards, read one by one: the package declares no hypothesis, as
    the criteria file had none. Verdict parity reads the package: `transport=pass machine=fail
    vhost-net=pass management=pass` on `exp-002b` and `exp-002b-repro-2026-08-05`. `machine` is the
    expected negative, the published "no measurable effect".
  - Each arm's CPU share (`rate` of `vxedge_node_cpu_seconds_total`) and mean RSS (`mean` of
    `vxedge_node_memory_bytes`) are reported, not judged. The frozen archives hold
    `vxtelemetry sample` output instead of those series, so offline they have no value, and the
    published CPU and RSS figures stay the notebook's.
  - Against the frozen runs, the `microvm-mmio` arm now uses virtio-mmio version 2, the
    `libvirt-q35` domain has the host CPU and ACPI, and the governor is not pinned. Vcpus, memory
    and the raw-QEMU arms' flags are as `run.sh` set them.
  - Live, the `quick` profile brought each of the six arms up alone and probed it with no loss, the
    reflector answering in every arm, and each trial's isolated arm had its CPU and memory series
    (`source="netns"` for the container arm, `source="process"` for the VM arms).

- `experiments/exp-002-ws` is the `vxp/1` package `vxedge/exp-002` 0.2.0, locked (X9.2). Its
  `main.yaml` holds what `scripts/run.sh` and `notebooks/analyze_exp002.py` held:
  - The three arms (container, microVM, full VM) are `campaign.arms`, with `quick` and `repro`
    profiles. Each brings its device up alone through `isolate` (vxedge 0.21.0), as `run.sh`
    brought one arm up at a time.
  - The probe is `measurements.probe`, `from: host` to the arm's address, as `run.sh` probed from
    the uplink's VLAN. A VM arm's reflector is its guest's own, which the probe bundle 0.1.1
    declares (`org.vxedge.reflector: udp/9800`), and the probe waits for it to answer.
  - H3's rule is typed intent: some VM arm's median p50 outside the container arm's IQR, at least
    1 µs. `notebooks/criteria/exp-002.yaml` is removed, and verdict parity reads the package.
  - The VM arms pin `ghcr.io/vxedge/parts/zone/linux/stack/probe-bundle` 0.1.1 by digest, in
    place of a locally fetched bundle; `tools/fetch-parts.sh` and `parts/linux-probe.sha256` are
    removed.
  - `vxp.yaml` replaces `exp-002.vxp`, and `.vxpignore` keeps `scripts/` out of the package.

- `experiments/exp-010-ws` is the `vxp/1` package `vxedge/exp-010` 0.2.0, locked (X9.2). Its
  `main.yaml` holds what `scripts/run.sh` and `notebooks/analyze_exp010.py` held:
  - The load sweep, repetitions and windows are `campaign`, with `quick` and `repro` profiles.
  - The probe is `measurements.ctl-rtt` on the `adas` slice's UE. Its address is learned when it
    starts (vxedge 0.20.0), and it replaces the `adas-probe` traffic profile.
  - H2's rule is typed intent: this campaign's median p99 growth from 0 to 600 Mbit/s within
    1.10x of exp-001's. `references.vlan` names exp-001's frozen campaign, which
    `results/exp-001/campaign.json` records, so `campaign start --reference-workspace <this repo>`
    judges it when the campaign finishes.
  - Offline, over the exp-001 2026-10-13 repro archives, it reads 0.94 against 1.01 (exp-001's
    0.91 x 1.10) and passes.
  - The published exp-010 archives hold each point's probe summary only, never samples, so verdict
    parity cannot check H2 from them.
  - The package has not run live: its 5G core and RAN images are not yet published as parts or
    pinned in `vxp.lock`.
  - `vxp.yaml` replaces `exp-010.vxp`, and `.vxpignore` keeps `scripts/` out of the package.

### Changed

- exp-005 0.2.1: its `quick` profile gives the steady window `run.sh --quick`'s 10 s (vxedge
  0.20.0 profile window lengths), and it requires vxedge 0.20.0.
- CI validates the workspaces with vxedge 0.25.0. It moved through 0.19.0 (cross-campaign
  criteria), 0.20.0, 0.21.0, 0.22.0, 0.23.0, 0.24.0 and 0.25.0.

### Removed

- exp-015's `run.sh`, `lib.sh`, `cases-v2.sh` and `flags.sh`, and exp-017's `run.sh`,
  `scenarios.sh`, `vss61.sh` and `compare.py`: the packages replace them.
- exp-003's `scripts/` (its `run.sh` and vendored `lib/`), its legacy `exp-003-ws.vxp`
  descriptor, and `notebooks/criteria/exp-003.yaml`: the package replaces them.
- exp-002b's `scripts/` (its `run.sh` and vendored `lib/`), `tools/fetch-parts.sh`,
  `parts/linux-probe.sha256`, its legacy `exp-002b.vxp` descriptor, and
  `notebooks/criteria/exp-002b.yaml`: the package replaces them.

## [0.2.0] - 2026-11-12

The first catalogue release. Experiments become `vxp/1` packages that vxAPI plans, runs and judges
on its own: exp-001 (H1, slice isolation), exp-005 (cold start) and exp-014 (harness topology). Each
package carries its campaign, parameters, metrics and criteria as typed intent, is locked, and
packs to the same digest every time. The release pushes each to
`ghcr.io/vxedge/experiments/<name>` at version 0.2.0 with build provenance, and `catalog.yaml`
lists them. No published number changes. The other experiments still run through their scripts
until they become packages.

### Changed

- CI validates the workspaces with vxedge 0.18.0.

### Fixed

- exp-014 declares its hypothesis (`topology`), so the catalogue and `PackageService.Inspect` name it.
- The exp-001 and exp-014 packages no longer list the probe's own exporter under
  `telemetry.prometheus.scrape_targets`. Their probe is a vxAPI measurement, whose samples come
  from vxedged's exporter, which the daemon adds to every run. Nothing answered the old target,
  so every trial recorded a gap for the probe node.

### Added

- `experiments/exp-005` is the `vxp/1` package `vxedge/exp-005` 0.2.0, locked (X9.2). Its two
  probe calls per repetition are measure windows (vxedge 0.18.0): `cold`, 3 s at 20 pps the
  instant the zone is up, then `steady`, 60 s at 1000 pps. Its rule is typed intent: the smallest
  cold max / steady p50 across repetitions must be at least 2.0, `cold_start.py`'s threshold on
  every repetition, as the published 20 of 20 found. `.vxpignore` keeps `scripts/` out of the
  package, and the legacy `exp-005.vxp` descriptor is replaced by `vxp.yaml`. The published
  archives hold the cold burst as a summary file only, so verdict parity cannot check this one.
- `catalog.yaml`, generated by `scripts/packages.py` from the `vxp/1` packages. It lists each
  package's id, version, package digest, hypothesis, `ghcr.io/vxedge/experiments/<name>:<version>`
  reference, `exp-NNN` alias and, where one is published, its frozen campaign. CI fails when the
  file is not current, or when a package a release published changed without a new version.
- CI plans each package's campaign for its default and every profile on an unprivileged vxedged,
  so a profile or intent that `campaign start` would refuse fails the pull request.
- A release workflow. A tag `vMAJOR.MINOR.PATCH` packs every package, pushes each to
  `ghcr.io/vxedge/experiments/<name>` at its own version, attests the packed files, and attaches
  them with `SHA256SUMS` and `catalog.yaml` to a GitHub Release whose notes are the tag's changelog
  section. A manual run is a dry run that pushes and publishes nothing.
- `vehicles/vx-vehicle-04` has two microcontroller ECUs on vxedge's `qemu-mcu` backend (0.16.0): `ecu-mcu-frt`
  runs the FreeRTOS firmware `zone/freertos/firmware/probe-mps2` 0.1.0 and is pinned to CPU 8, and `ecu-mcu-zep`
  runs the Zephyr firmware `zone/zephyr/firmware/probe-mps2` 0.1.0, both on QEMU's `mps2-an385` (Cortex-M3) and
  on `adas`. The vehicle again has a node on every backend, ten in all, and `check-flows.sh` has 19 checks.
- `results/all-backends-gate-2026-11-11`: the vxAPI core gate through vxmcp on that vehicle, 10 of 10 on vxedge
  0.17.0 and vxmcp 0.4.3, with 501 checks and 0 failed. On top of the 2026-11-10 gate, both qemu-mcu nodes report
  `armv7m` under `tcg`, the pinned one keeps its threads on its CPU, and `hpc1` reaches both while the
  `infotainment` container reaches neither. Functional only, never timed.

- `experiments/exp-014` is the `vxp/1` package `vxedge/exp-014` 0.2.0, locked (X9.2). Its
  `main.yaml` now holds what `scripts/run.sh` and `notebooks/analyze_exp014.py` held: the six arms
  as `campaign.arms`, each setting a `device` parameter that binds the probe's `from`, the
  repetitions and windows with `quick` and `repro` profiles, the probe as `measurements.probe`
  with `probe_pps`, and the hop rule as `metrics` and `criteria`. It runs with
  `vxedge campaign start --profile repro`. A campaign trial brings up all six devices, where
  `run.sh` brought up one arm at a time; the README says so. `.vxpignore` keeps `scripts/` out of
  the package, and `vxp.yaml` replaces `exp-014.vxp`.

- `results/exp-001/campaign.json` records the frozen exp-001 campaign for vxAPI. It lists each of
  the 25 published archives (Zenodo `exp-001.tgz`), its sha256, and the trial it is, named as the
  exp-001 package's campaign names that point. `vxedge campaign compare <id> exp-001
  --reference-workspace <this repo>` then compares a new campaign with the frozen one, which
  needs vxedge 0.17.0. The record adds no number, and every published number is unchanged.

- `experiments/exp-001-ws` is the `vxp/1` package `vxedge/exp-001` 0.2.0, locked (X9.2). Its
  `main.yaml` now holds what `scripts/run.sh` and `notebooks/analyze_exp001.py` held: the load
  sweep, repetitions and windows as `campaign` with `quick` and `repro` profiles, the probe as
  `measurements.ctl-rtt`, `load_mbps` and `probe_pps` as parameters bound to the fields they set,
  and H1's acceptance rule as `hypothesis`, `metrics` and `criteria`, selected by load. It runs with
  `vxedge campaign start --profile repro`. `.vxpignore` keeps `scripts/` out of the package. The
  legacy `exp-001.vxp` descriptor is replaced by `vxp.yaml`.

- `results/done-means-gate-2026-11-10/`: the vxperiment upgrade's done-means steps 1 to 7 run
  live through `vxmcp` 0.4.1 and vxedge 0.15.1. A signed, locked exp-001 package is pulled by
  digest, and a tampered copy is refused. Bounds are refused at plan time, and a retry returns
  its campaign. Live phases match the archives, and the verdict is typed. The archives are
  fetched and re-hashed, and the campaign is rerun from an archive's package. 94 checks, 0
  failures. Comparing against the published frozen reference through vxAPI came after, with
  vxedge 0.17.0 and `results/exp-001/campaign.json`.

- `scenarios/urban-stop-line/`: the first reference scenario, written for vxedge. It is an
  OpenDRIVE road and an OpenSCENARIO storyboard in which a lead vehicle brakes to a stop line,
  with three storyboard parameters (`EgoTargetSpeed`, `LeadGap`, `LeadDeceleration`) and their
  bounds. `scripts/scenario-proof.sh` vendors it and `vx-reference-sedan-01` into a throwaway
  package, and checks that the package validates, locks and packs to the same digest twice. CI
  runs it.

- `notebooks/criteria/`: the notebooks' acceptance rules for exp-001, 002, 002b, 003 and 014, as
  typed intent (metrics, criteria and guards) that `vxedge results verdict` judges.
  `scripts/verdict-parity.sh` judges every full published dataset that holds samples, 13
  campaigns, and checks each criterion's outcome against the notebook's verdict. CI runs it on
  the archives from the Zenodo record, each checked against `notebooks/criteria/SHA256SUMS`. All
  13 agree. exp-005 and exp-010 are not covered, as their archives hold probe summaries rather
  than samples, and neither are the quick-profile sets.
- `vehicles/vx-vehicle-04`: one vehicle on every node backend (qemu-microvm, cloud-hypervisor, libvirt,
  wasm-capsule, attach, container), with four nodes pinned to their own CPU. Every part is published and
  pinned by digest except `./ivi`, a generic attach adapter that boots the published linux-probe bundle on
  plain QEMU over a tap the host prepares once, plus a FreeRTOS ECU (`zone/freertos/stack/probe-bundle`).
  `check-flows.sh` runs 15 checks.
- `results/all-backends-gate-2026-11-10`: the vxAPI core gate on `vx-vehicle-04`, 10 of 10 on vxedge 0.14.0,
  461 checks, 0 failed. Every backend came up, each pinned node's threads were confined to its CPU, and all 15
  flow checks passed, after `up` and again after a daemon restart.
- `results/exp-001-measurements-2026-11-09`: exp-001 run through vxAPI, with its probe a declared
  `measurements` entry and its load an in-node traffic profile, under run.sh's `--repro` protocol.
  H1 holds (p99 at 600 mbit/s is 0.93x idle), and the path agrees with each run.sh campaign as
  closely as run.sh agrees with itself: 10 to 11 of 15 metric x load pairs, against 8 to 12 between
  run.sh's own campaigns. `experiments/exp-001-ws/scripts/run-measurements.sh` runs it, and
  `notebooks/compare_exp001_paths.py` compares the two paths.

### Changed

- CI validates the workspaces with vxedge 0.17.0.
- Verdict parity judges exp-014's published campaign with the package's own criteria.
  `notebooks/criteria/exp-001.yaml` and `exp-014.yaml` are removed: the packages hold those rules
  now, and nothing reads the copies. The done-means gate's README points at the exp-001 package
  for the criteria it used.
- Verdict parity judges the five exp-001 campaigns with the package's own criteria, not
  `notebooks/criteria/exp-001.yaml`. All 13 datasets still give the notebooks' verdicts.
- CI's workspace validation reads `vxp.yaml` packages as well as legacy `.vxp` descriptors. For a
  package it also checks that the lock matches and that packing twice gives one digest.
- `experiments/exp-001-ws/scripts/run-measurements.sh` runs its copy on `method`, since the package's
  `campaign` replaces it, and no longer adds the probe, which `main.yaml` now declares.
- CI validates every workspace with vxedge 0.16.0 (`ci/vxedge-release.txt`).
- `vx-vehicle-02` and `vx-vehicle-03` run the published vxparts probe (`agent/probe/app/vxprobe` 0.1.1) and
  OTA (`svc/ota/app/vxota` 0.1.1) parts, pinned by digest, and live they pass their flow checks (8/8 and 12/12)
  and vx-vehicle-03's signal checks (5/5). `build.sh` no longer builds `localhost/vxedge/probe:1` or `ota:1`,
  and `vx-vehicle-02/images` is gone; it still builds the OTA store and the guest bundle.
- exp-016 runs the published vxparts parts: `agent/load/app/vxtraffic` 0.1.1 as its load and
  `agent/load/app/kuksa-perf` 0.1.0 (built from its `tools/perf`), both pulled by digest, the probe
  part for its zones, and the vxota part for its OTA service. `build.sh` no longer builds either
  image, and `tools/load` is gone. exp-015's two failure cases use the probe and vxota parts in place
  of `localhost/vxedge/probe:1` and `ota:1`. Recorded results are unchanged; they name the local
  builds they were made with.
- `results/phase-3-gate-2026-11-01`: "What this does not show" names guest kinds generically.
  `vx-vehicle-01`: the header comment no longer lists unbuilt guest images.
- `results/aaos-gate-2026-11-08`: "What this does not show" states what the run is not, without naming later
  stages.
- `vx-reference-sedan-03`: the `aaos` adapter's `attach.yaml` runs `sh start.sh`, `sh status.sh` and
  `sh stop.sh`, so the vehicle comes up when vendored or unpacked from a package, which keeps no execute bit.
- CI's workspace validation runs vxedge 0.6.1 (`ci/vxedge-release.txt`), which computes workspace identities under `vxws/2` and checks each `.vxp` descriptor against its experiment.
- Every experiment's `run-env.json` records `tool_versions` from the binaries that ran: the version each reports and the sha256 of the file. Four runners used to record the commit of a source checkout, which can differ from the build in `target/`. exp-002, exp-002b, exp-005 and exp-014 now name `vxprobe` where they named its repository `vxagents`.
- `scripts/lib/check-runners.sh` fails a runner whose `tool_versions` asks a checkout instead of the binary, or whose `tool_version` does not emit valid JSON.

### Added

- `results/signal-plane-2026-11-03`: the Kuksa signal plane on `vx-vehicle-03`, one VSS signal allowed and denied.
- `vehicles/vx-vehicle-03`: the Kuksa signal plane on `hpc1`, and `check-signals.sh`, which writes and reads one VSS signal with the upstream client pinned by digest.
- `results/all-backends-2026-11-02`: `vx-vehicle-03` from a clean state, and a regression run of the phase-3 gate.
- `vehicles/vx-vehicle-03`: every zone backend in one vehicle, with its build script and checks.
- `vehicles/vx-vehicle-02`: the phase-3 gate vehicle, with its build script and flow, identity and leak checks.
- `results/phase-3-gate-2026-11-01`: the gate run.
- `README.md`: the Zenodo dataset DOI `10.5281/zenodo.23804197` for the raw result archives.
- `results/exp-003-repro-2026-10-30/` and `results/exp-010-repro-2026-10-30/`: summaries of the full H4 and H2 reruns of 2026-10-30, on kernel 7.0.0-42-generic (`repro.kernel` in `docs/FACTS.md`). Both verdicts held. The archives are in Zenodo version 2026-11 (`10.5281/zenodo.23810053`).
- Open-source release preparation: `LICENSE` (Apache-2.0), `NOTICE`, rewritten `README.md`.

### Added
- `scripts/run-smoke.sh` (2026-07-14): every experiment's `--quick` pipeline + analyzer,
  chained, ~4 min, single PASS/FAIL summary; rejects unknown args; hands quick dirs back
  to the invoking user. First two owner-run executions: SMOKE PASS both.
- Frozen-campaign protection (2026-07-14, `scripts/lib/results_dir.sh`): full runs refuse
  a results dir holding archives; `--repro` → `results/<exp>-repro-<date>/`, `--quick` →
  `results/<exp>-quick/`. Root cause: exp-003's original archives were overwritten in
  place by its repro rerun.

### Fixed
- Verdict noise-hardening from the first live smoke runs (2026-07-14):
  `analyze_exp003.py`'s H4 verdict is now one-sided (burst *faster* than baseline is
  session drift, never a violation — the sign-blind check printed a false
  "DOES NOT HOLD"); all three verdict-printing analyzers floor their threshold at the
  10 µs quick-noise band under quick profiles (a +5.2 µs machine-type delta had printed
  "MATTERS", contradicting the full campaigns' headline "no effect" finding). Full
  campaigns keep IQR-based thresholds unchanged. `run-exp-001/003` use
  `ip addr replace` (idempotent) for experiment IPs.
- `exp-002` hardened to isolate one arm at a time (2026-07-13), closing the "known gap" noted
  in 0.1.0: `exp-002.yaml` restructured from one 3-node zone into one zone per arm
  (`z-cont`/`z-microvm`/`z-libvirt`); `run-exp-002.sh` retrofitted with exp-002b's
  `start_arm()`/`stop_arm()` isolation pattern plus every other exp-002b/exp-003 hardening
  lesson (guarded `vxprobe send`, `tool_versions`/`cpu_pinning`, 10s warmup, surfaced `wait`
  exit codes); `analyze_exp002.py` now refuses archives missing `isolation=="single-arm"`,
  reports loss with its lost/sent denominator, and accepts `--out-dir=DIR`. Re-run
  (2026-07-13, 15 archives, zero loss) **superseded the frozen result**: H3 still holds and
  the arm ordering is unchanged, but libvirt's latency dropped measurably (p50 74.5→66.3µs,
  p99 122.8→110.7µs, more than the original's own IQR) once it no longer shared the host
  with idle container/microvm backends — container and microvm themselves barely moved.
  Frozen summary updated in place (`results/exp-002/exp-002-summary.md`).
- `exp-001` second-campaign reproducibility check (2026-07-13): reproducible — 14 of 15
  median/metric pairs within the original run's IQR, H1 verdict unchanged (0.93x original
  vs 0.95x rerun). Recorded separately from the frozen original:
  `results/exp-001/exp-001-repro-check-2026-07-13.md`.
- `exp-003` second-campaign reproducibility check (2026-07-13): 0 of 6 metric/arm pairs
  within the original run's IQR (a uniform ~4-7µs downward shift across both arms,
  same-day) — the weakest of the three reproducibility checks this session, and honestly
  reported as such. The substantive H4 comparison is unaffected (both arms drifted
  together; Δp50 -1.4µs original vs -0.7µs rerun, same order of magnitude/sign — **H4
  still holds**). Reading: within-campaign IQRs bound repetition-to-repetition noise, not
  cross-session host drift, which this host shows even hours apart on the same day; the
  comparative hypotheses are robust to it, absolute µs figures from a single campaign are
  not universal constants. Recorded separately:
  `results/exp-003/exp-003-repro-check-2026-07-13.md`. Also fixed in the same pass:
  `analyze_exp003.py`'s telemetry-completeness caveat was a hardcoded "~50%" claim (only
  true of the pre-`optional_scrape_targets` archives); now computed dynamically per
  campaign from `ingest/ingest-stats.json`'s required/optional scrape counters — confirmed
  the schema fix works (this rerun: 100% required-target completeness both arms).

## [0.1.0] - 2026-07-13

**Phase-1 gate passed**: H1, H3, and H4 all have reproducible numbers. Repos stay
private at this release.

### Added
- `exp-001` (H1, slice isolation): full campaign 2026-07-10, 5 reps x 5 loads, 60k
  samples/point. **H1 HOLDS** — adas p99 0.93x baseline under 600 mbit offered overload,
  zero loss.
- `exp-002` (H3, packaging): full campaign 2026-07-11, 5 reps x 3 arms. **H3 HOLDS** —
  packaging measurably affects RTT (container < libvirt < qemu-microvm).
- `exp-002b` (H3 decomposition): full isolated campaign 2026-07-12, 5 reps x 6 arms.
  Decomposed the exp-002 finding: not machine type, but virtio transport (dominant),
  vhost-net, and management-layer defaults.
- `exp-003` (H4, OTA co-location): full campaign 2026-07-13, 5 reps x 2 arms, zero loss
  both arms. **H4 HOLDS** — adas p50 45.8µs under a sustained OTA delivery burst
  (~355 successful deliveries/rep, zero failures) vs 47.2µs baseline, well within IQR.
  Same adas slice/QoS/probe parameters as exp-001. **This is the phase-1 gate's third and
  final arm — H1, H3, and H4 are all delivered.**
- Analysis notebooks (`analyze_exp001.py`/`analyze_exp002.py`/`analyze_exp002b.py`/
  `analyze_exp003.py`): archive-only, percentile tables + IQR, decomposition/comparison
  verdicts, headless/CI-runnable.
- `scripts/lib/freshness.sh`: shared per-binary staleness check used by all four
  run-exp-*.sh campaign runners (2026-07-13).

### Fixed
- exp-002b's first campaign attempt ran all 6 arms concurrently, causing CPU-contention-
  driven, non-reproducible packet loss (0-37%) hidden by the aggregate median; root-caused
  and fixed by isolating one arm at a time, with `isolation: single-arm` archive
  provenance the analyzer now refuses to proceed without (2026-07-12).
- An 8-angle code review of the exp-002b runner/analyzer found and fixed 10 further
  issues (unguarded `set -e` aborts that could lose an entire campaign on one bad
  measurement, a warmup below the methodology skill's own 10s minimum, missing
  `tool_versions`/`cpu_pinning` metadata, loss reported without its denominator, orphaned/
  silently-swallowed sidecar processes, a cleanup-trap zone-list drift risk, an
  `--out-dir=DIR` parsing gap); the campaign was re-run end-to-end on the hardened script
  and reproduced every conclusion (2026-07-12).
- exp-003's `baseline` archives showed ~50% aggregate telemetry-scrape completeness,
  traced to a manifest scrape target (the OTA burst driver's exporter) with nothing
  listening during that arm by design — not real data loss (the adas-relevant target was
  100% complete every repetition). Explained directly in the analyzer output; no re-run
  needed (2026-07-13).
- `check_fresh()` (duplicated in every run-exp-*.sh) compared any source file in the
  *whole repo* against each individual binary, false-positiving on multi-binary repos
  when only a sibling binary's source changed — hit twice running exp-003. Replaced with
  `scripts/lib/freshness.sh`'s per-crate-dependency-graph check, verified against the
  exact regression that motivated it (2026-07-13).
- Arm-conditional scrape targets: `exp-003.yaml` now declares the OTA burst driver's
  exporter under the new `telemetry.prometheus.optional_scrape_targets` (see `vxedge`'s
  and `vxtelemetry`'s CHANGELOGs) instead of as a required target. Future campaigns will
  show 100% `baseline` completeness instead of the already-frozen, already-explained
  ~50% figure (2026-07-13).

### Known gaps
- `exp-002` still runs its 3 arms concurrently (retrofit to `exp-002b`'s single-arm
  isolation tracked, low priority — its own audit showed zero loss).
- `exp-001`/`exp-003` don't yet have a formal second-campaign reproducibility check
  (`exp-002b` does).
