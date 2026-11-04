# The databroker measured across a slice, 2026-11-04

[`exp-016`](../../experiments/exp-016) with kuksa-databroker 0.7.1 on `hpc1` of
[`vx-vehicle-03-load`](../../experiments/exp-016/vehicle.yaml). **This is the branch run, before the
merge:** vxedge `4626e0e`, vxperiments `933146f`, from 16:47 to 17:19 UTC. The run from merged `main`
will be the published one.

[`transcript.txt`](transcript.txt) is the whole run, [`out/`](out) holds each kuksa-perf run's
output, and [`summary.txt`](summary.txt) is `summarize.py` over `out/`, the same table the
transcript ends with.

| What | Pinned |
|---|---|
| databroker 0.7.1, under test | `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd` |
| kuksa-perf, every measured run | upstream commit `aa6fba0`, built by [`tools/perf`](../../experiments/exp-016/tools/perf/Containerfile) |
| kuksa-perf 0.3.2, recorded only | `ghcr.io/eclipse-kuksa/kuksa-databroker-perf@sha256:74ad5bb003e2f541cf9862ba63cecf66cd93badb514f1c6c8b68bcaac29ffd93` |

## Timing method and limits

kuksa-perf timestamps each update in one process, with a monotonic clock, when its provider sends
it and when its subscriber (for actuate, its provider) receives it. Outside the baseline, every
update crosses the slice twice, to the broker and back, so no number here is a one-way latency.
Each run lasts 30 s with the first 5 s skipped. Five repetitions per setup, in an order that rotates.

The broker, kuksa-perf, the load and the bridge share one host's CPUs. The governor was pinned to
`performance` and `/dev/cpu_dma_latency` held at 2 us for the whole run; every run spent 0 ms in a
deep idle state. Other workloads on the host were paused for the window. Timestamps are in
userspace, so scheduling delay is inside every number. An actuate run has 250 samples, so its p99
rests on two or three of them and moves by tens of microseconds between repetitions.

## Checks

| Check | Result |
|---|---|
| Vehicle `up`, the 2 s stay-running check, `down`, no leaks after | passed |
| kuksa-perf 0.3.2 against 0.7.1 over `kuksa.val.v2` | sent 0, received 0, printed 0.000 ms, exit 0: recorded, not a result |
| The broker from `info2`, on `infotainment` | client error `No route to host`, 3 frames reached the bridge |
| The load, 7 s | `zone-rl` sent 438,461 frames, `info2` received 441,648, `hpc1` and `cabin1` 0 |
| Runs that received nothing | none |

## Results

Median across repetitions, microseconds, [min-max] in brackets.

| Setup | publish p50 | publish p99 | actuate p50 | actuate p99 |
|---|---|---|---|---|
| baseline | 57 [57-58] | 88 [86-89] | 116 [113-119] | 155 [150-208] |
| idle | 66 [64-69] | 98 [96-102] | 128 [126-132] | 207 [165-244] |
| cpu | 70 [68-71] | 90 [87-92] | 130 [125-131] | 184 [161-193] |
| loaded | 67 [65-69] | 87 [84-97] | 130 [127-133] | 161 [153-200] |

- **The slice, idle minus baseline:** publish +9 p50, +10 p99; actuate +12 p50.
- **Competing load on another slice, loaded minus idle:** +1 and +2 p50, inside the spread between
  repetitions. No effect is visible at this resolution.
- **CPU load without traffic, cpu minus idle:** +4 and +2 p50, also inside the spread.
- The first run's loaded-faster-than-idle result (p50 88 against 233 us under `powersave`) does
  not appear with deep idle held off, which supports it having measured CPU wake-up.

## Issue 233 data

Actuate on the broker's own device, released 0.7.1 image, three repetitions each.

| Providers × actuator ids | p50 | p90 | p99 |
|---|---|---|---|
| 1 × 1 | 118 [115-119] | 133 [132-134] | 161 [158-167] |
| 1 × 240 | 678 [665-681] | 797 [778-801] | 863 [860-926] |
| 16 × 1 | 125 [123-133] | 182 [174-192] | 251 [243-261] |
| 16 × 15 | 116 [114-130] | 140 [137-155] | 176 [159-185] |

The same 240 ids took about six times longer through one provider than spread over sixteen. This
is black-box data from outside the broker: it does not show where the time goes, and a batch of 240
ids to one provider is also one larger message.

## Not in this run

The governor restore at the end prompted for sudo after the terminal's timestamp had expired, and
left 15 CPUs on `performance` until they were restored by hand. It ran after every measurement.
`run.sh` now keeps the timestamp fresh for the whole run and logs the governors after the restore.
