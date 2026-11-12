# exp-016: the databroker measured across a slice

How much a slice adds to the Kuksa databroker's own publish-to-subscriber time, and how much
competing load on another slice adds to that. Measured with Kuksa's own tool,
[kuksa-perf](https://github.com/eclipse-kuksa/kuksa-perf), against kuksa-databroker 0.7.1 on `hpc1`.

## The package

This folder is the `vxp/1` package `vxedge/exp-016`, version 0.2.0 (`vxp.yaml`). Its catalogue
alias is `exp-016`. `main.yaml`'s `checks` (vxedge 0.25.0) run each kuksa-perf run as a step in a
node's namespace, and its `samples` read the run's percentiles as series that the metrics and
criteria aggregate, so no script drives it.

| What | Where it was | Where it is |
|---|---|---|
| The vehicle | `vehicle.yaml` with the OTA service, a bundle and capsule built per host by `build.sh` | `vehicle.yaml` without the OTA service; `parts.yaml` pins the published probe bundle 0.1.1 and reflector capsule 0.1.0 |
| A kuksa-perf run in a node's namespace | `perf` in `run.sh` (`podman run --network container:vx-<node>-infra`) | a `checks.steps` step of the tool `perf`, `on` the node |
| The run's percentiles and counts | `summarize.py` over each run's text | [`tools/perf.awk`](tools/perf.awk) prints them as JSON lines after the run's own output; `samples` reads them as `kuksa_perf_latency_us` (by `quantile`) and `kuksa_perf_received` on `checks/<step>` |
| The load and the CPU load | `load_on`, `cpu_on` | background steps of the tools `load` (vxtraffic on `zone-rl`) and `busy` (`on: alone`), stopped after the run |
| A run that received nothing | listed as failed by `summarize.py` | no percentiles from `perf.awk`, and a failed case of the criterion `runs` |
| The broker refused from `info2`, the load's reach, the broker's restarts | the transcript's lines | `observe: port` and `observe: member` steps, compared in cases of the criterion `setup` |
| Five repetitions | a loop inside one vehicle `up` | `campaign.repetitions: 5`, each trial on a vehicle of its own |
| The results | `summary.txt`, read by hand | criteria: `slice-publish`, `slice-actuate`, `load-publish`, `load-actuate` |

Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan
vxedge campaign start      # five trials; each archive holds every step's output
vxedge results verdict --experiment . results/<campaign>
```

The host needs KVM for the two VM zones. Before a run whose numbers matter, prepare the host as
the published run did: pin the CPU governor to `performance` and hold `/dev/cpu_dma_latency` at
2 us for the whole campaign (`scripts/lib/host_pinning.sh`), and keep other workloads off it. The
package sets no host state; without that preparation the numbers measure CPU wake-up, not the
slice (see below).

## Criteria

A trial's value for each setup is its run's p50, from `samples`. The spread between repetitions
is a setup's range, max minus min, as the published tables give it, and a criterion needs at
least three repetitions, so a `quick` trial is `inconclusive` on them.

| Criterion | Holds when |
|---|---|
| `runs` | every measured run received updates |
| `slice-publish`, `slice-actuate` | the median idle p50 minus the median baseline p50 exceeds the larger of the two setups' spreads |
| `load-publish`, `load-actuate` | the median loaded p50 is within the larger of the loaded and idle spreads of the median idle p50 |
| `setup` | the broker ran and did not restart, refused kuksa-perf from `info2` though its frames reached the bridge, and the load reached `info2` |

The hypothesis and criteria were written from the published result below, which they reproduce;
they were not declared before it. Verdict parity (`scripts/verdict-parity.sh`) builds trial
archives from the frozen runs' committed output with [`scripts/frozen-checks.py`](../../scripts/frozen-checks.py),
through the package's own `perf.awk`, and judges them with this package. Both frozen runs give
`runs`, `slice-*` and `load-*` `pass`, with the published differences (publish +8 and actuate
+11 µs over the slice, +1 µs under load, on the main run). `setup` is `inconclusive` there: those
runs recorded the broker's state, the denial and the load's reach once, in their transcripts, not
as step output, and nothing is invented for them.

What changed from the script:

- One trial runs the setups in one order, baseline, idle, loaded, cpu, for publish then actuate.
  The script rotated the order every repetition, inside one vehicle `up`; a package trial has one
  order, and each repetition gets a vehicle of its own.
- The issue-233 runs repeat with every trial, five times rather than three.
- The released kuksa-perf 0.3.2 and the denied run from `info2` also run in every trial.
- The deep-idle time each run recorded came from the host; the package does not read it.

## Setups

The broker is on `hpc1`, on `adas`. kuksa-perf keeps its sender and receiver in one process, and the
broker is reachable only on its own device's slice, so it cannot run between two zones. The setups
move that one process instead:

| Setup | Where kuksa-perf runs | Competing load |
|---|---|---|
| baseline | `hpc1`'s own network namespace | none |
| idle | `cabin1`, on `adas` | none |
| loaded | `cabin1`, on `adas` | vxtraffic, 600 mbit/s from `zone-rl` to `info2` on `infotainment` |
| cpu | `cabin1`, on `adas` | two busy loops in a container with no network: CPU load, no traffic |

The result is the differences between the setups, not one number. `cpu` separates the two things the
loaded setup changes: loaded minus cpu is the traffic's share, cpu minus idle the CPU's. A baseline
run never touches the bridge. In the other setups, every update crosses the slice twice, to the broker
and back to the subscriber, so a number here is never a one-way latency.

[`vehicle.yaml`](vehicle.yaml) is `vx-vehicle-03` plus one container device, `info2`, so the load
has two ends on a slice the broker is not on. `diff ../../vehicles/vx-vehicle-03/vehicle.yaml
vehicle.yaml` shows nothing else changes. Each trial checks the load reaches `info2`, records what
reached the `adas` ports in the same window, and checks the broker is not reachable from `info2`.

## Pinned

| What | Image |
|---|---|
| databroker 0.7.1 | `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd` |
| kuksa-perf at `aa6fba0`, every measured run | `ghcr.io/vxedge/parts/agent/load/app/kuksa-perf:0.1.0@sha256:1e894b9d7de05d41059d711871b17ae3023497933ad88f05f29f903000c7ba73`, the vxparts part built by [`tools/perf`](tools/perf/Containerfile): upstream `main` of 2025-07-28, `--locked`. Runs before it was published used a local build of the same file |
| kuksa-perf 0.3.2, recorded only | `ghcr.io/eclipse-kuksa/kuksa-databroker-perf@sha256:74ad5bb003e2f541cf9862ba63cecf66cd93badb514f1c6c8b68bcaac29ffd93` |
| vxtraffic, the load | `ghcr.io/vxedge/parts/agent/load/app/vxtraffic:0.1.1@sha256:be310378c1f330969072669fb24a991b26c2a991dc02f23c81056c8fc98f2c3c`, the vxparts part (vxagents v0.1.1). Runs before it was published used a local build |

kuksa-perf 0.3.2, from December 2024, is the latest release and a pre-release, and it cannot measure
databroker 0.7.1 over `kuksa.val.v2`. Its v2 provider publishes without claiming its signals first,
0.7.1 aborts that stream (`ABORTED: Provider has not claimed yet the signals`), and 0.3.2 ignores the
error, exits 0 having sent nothing and prints a latency distribution of 0.000 ms. Each trial
records one such attempt (`release-0.3.2`, its counts read by `release-summary`) and leaves it out
of the results; a measured run that received nothing fails `runs`. Every measured run uses a build
of upstream commit `aa6fba0`, whose provider claims its signals first and which adds `--operation actuate`. Its Cargo version still reads 0.3.2, so results
name the commit. Its README starts the broker with `--enable-databroker-v1`, which 0.7.0 removed;
this run passes `--api kuksa.val.v2` and nothing else from that README.

The test data in [`data/`](data) is generated by [`make-data.py`](data/make-data.py) from the VSS 6.0
metadata the broker ships, and every path is checked against it. Upstream's `data_group_10.json`
names two signals VSS 6.0 does not have (`Vehicle.Cabin.Seat.Row1.PassengerSide.Heating` and
`.Massage`), so it is not used.

The published runs pinned the CPU governor to `performance` for the whole run, and restored it
after. A first run under `powersave` found the loaded setup faster than the idle one (p50 88 µs
against 233 µs): busy CPUs stayed at a high clock and out of sleep states, so it measured CPU
wake-up, not the slice. That run is not a result. The package sets no host state, so this is the
host's preparation before a campaign.

## Timing method

kuksa-perf takes a monotonic timestamp (tokio `Instant`) just before its provider sends an update,
and another when its subscriber receives it, in the same process, and records the difference in an
HDR histogram. For actuate, the timestamps are at the `BatchActuate` call and at the provider's
receipt. Clocks never cross a host or namespace boundary. Each run lasts 30 s with the first 5 s
skipped, five repetitions per setup, one per trial, in the order baseline, idle, loaded, cpu (the
published runs rotated it every repetition), with 3 s between runs so the broker has released the
last run's claims.

## Limits

- One shared host: the broker, kuksa-perf, the load generator and the bridge share its CPUs. The
  `cpu` setup separates CPU load from traffic. The governor pin does not stop CPU sleep states, so
  the published runs also held `/dev/cpu_dma_latency` at 2 us, which keeps CPUs out of any state
  slower to leave, and recorded each run's deep-idle time to show the hold worked: 0 ms in every
  run. Both are the host's preparation for a package run.
- Timestamps are in userspace, so scheduling delay on either side is inside every number.
- The numbers belong to this host and this vehicle. kuksa-perf's README sample, a p50 near 0.2 ms on
  other hardware, is not a result here.
- Signals are unauthenticated (`--insecure`). Slice isolation is their only protection.

## Issue 233 data

[kuksa-databroker#233](https://github.com/eclipse-kuksa/kuksa-databroker/issues/233) asks whether
routing an actuation costs more as providers and their actuator ids grow. The last steps of each
trial measure actuate on the broker's device, released 0.7.1 image, no code change, for 1 or 16
providers with 1 to 240 boolean actuator ids. It is black-box data from outside the broker, not a
benchmark of any patch.
