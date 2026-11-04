# The databroker measured across a slice, from main, 2026-11-04

[`exp-016`](../../experiments/exp-016) with kuksa-databroker 0.7.1 on `hpc1` of
[`vx-vehicle-03-load`](../../experiments/exp-016/vehicle.yaml). **This is the published run, from
merged `main`:** vxedge `6eff42d`, vxperiments `31284a9`, from 22:31 to 23:03 UTC. The branch run
before the merge, [`broker-slice-2026-11-04`](../broker-slice-2026-11-04), gave the same results to
within a few microseconds.

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
rests on two or three of them and moves by tens of microseconds between repetitions. Signals are
unauthenticated (`--insecure`).

## Checks

| Check | Result |
|---|---|
| Vehicle `up`, the 2 s stay-running check, `down`, no leaks after | passed |
| kuksa-perf 0.3.2 against 0.7.1 over `kuksa.val.v2` | sent 0, received 0, printed 0.000 ms, exit 0: recorded, not a result |
| The broker from `info2`, on `infotainment` | client error `No route to host`, 3 frames reached the bridge |
| The load, 7 s | `zone-rl` sent 438,503 frames, `info2` received 441,578, `hpc1` 0, `cabin1` 1 |
| Runs that received nothing | none |

## Results

Median across repetitions, microseconds, [min-max] in brackets.

| Setup | publish p50 | publish p99 | actuate p50 | actuate p99 |
|---|---|---|---|---|
| baseline | 58 [55-59] | 87 [84-89] | 116 [113-119] | 158 [150-172] |
| idle | 66 [65-67] | 97 [93-99] | 127 [123-130] | 188 [157-243] |
| cpu | 70 [68-74] | 88 [87-98] | 133 [125-139] | 185 [184-191] |
| loaded | 67 [64-68] | 89 [83-99] | 128 [121-134] | 158 [151-195] |

- **The slice, idle minus baseline:** publish +8 p50, +10 p99; actuate +11 p50.
- **Competing load on another slice, loaded minus idle:** +1 p50 for both, inside the spread
  between repetitions. No effect is visible at this resolution.
- **CPU load without traffic, cpu minus idle:** +4 and +6 p50, at the edge of the spread.

## Issue 233 data

Actuate on the broker's own device, released 0.7.1 image, three repetitions each.

| Providers × actuator ids | p50 | p90 | p99 |
|---|---|---|---|
| 1 × 1 | 118 [118-122] | 137 [136-137] | 164 [158-166] |
| 1 × 240 | 694 [691-703] | 812 [806-825] | 901 [894-956] |
| 16 × 1 | 128 [123-133] | 187 [181-191] | 256 [254-257] |
| 16 × 15 | 130 [128-132] | 157 [155-162] | 193 [182-202] |

The same 240 ids took about five times longer through one provider than spread over sixteen. This
is black-box data from outside the broker: it does not show where the time goes, and a batch of 240
ids to one provider is also one larger message.
