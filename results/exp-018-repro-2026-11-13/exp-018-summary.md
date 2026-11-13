# exp-018: in-vehicle protocol loads against the ADAS slice (live run, 2026-11-13)

- campaign `c-3ab392dff5b3`, profile `repro`: 20 trials (5 repetitions of four arms), every
  trial complete; the archives' digests match `campaign.json`
- package `vxedge/exp-018` 0.1.0, digest `sha256:ee41902755a2bbc3984b59179fa22a6b6a519cdbd0545d8fd07b0601a46ed6fa`, locked
- probe: 1000 pps device to device on the ADAS slice, a 60 s window after 10 s for the load to start
- tools (release builds): vxedged 0.29.0, vxprobe 0.2.3, vxtelemetry 0.9.0
- images, from the archives' `image_digests`:
  - `ghcr.io/eclipse-kuksa/kuksa-databroker@sha256:529d8c6d3cc223362667672978bcb8f92c4d356b25aedd336e7a2e004d7279bd`
  - `ghcr.io/vxedge/parts/agent/load/app/dds-perf:0.1.0`
  - `ghcr.io/vxedge/parts/agent/load/app/someip-samples:0.1.0`
  - `ghcr.io/vxedge/parts/agent/probe/app/vxprobe:0.2.0`
  - `ghcr.io/vxedge/parts/svc/signal/app/kuksa-can-provider:0.1.0`
- host: kernel 7.0.0-43-generic, PREEMPT_RT=False, CPU governor performance;
  run folder outside the home directory, host lock held for the whole run (no load log was kept)
- caveats: shared-host gateway; the slices carry no QoS, so the VLAN is the only separation; each
  load is its part's traffic at a stated rate, not a swept one. vxedged 0.29.0 named a payload's
  image by tag when recording digests, and these images were pulled by digest, so before the run
  the three load images were tagged locally with their own references; the digests recorded are of
  the images that ran (fixed in vxedge 0.29.1)

## The loads, checked before the campaign

Each loaded baseline was brought up on its own and read from the load devices' interfaces and logs:

| arm | what crossed the infotainment slice |
|---|---|
| `dds` | `ddsperf` subscriber: 1.00 kS/s of 1 KiB samples, 8.19 Mb/s, 0 lost |
| `someip` | the vsomeip client's requests and the service's responses, after multicast service discovery |
| `can` | the CAN provider's datapoint updates to the databroker on `broker`, about 375 KB in 20 s |

## Per arm

ADAS slice, all values in µs: the median over 5 repetitions of each trial's quantile, hinge IQR in
brackets.

| arm | reps | p50 (IQR) | p95 (IQR) | p99 (IQR) | max loss % |
|---|---:|---:|---:|---:|---:|
| `idle` | 5 | 29.6 (0.3) | 36.0 (7.2) | 53.7 (2.8) | 0.0000 |
| `dds` | 5 | 30.1 (0.6) | 36.2 (3.1) | 53.4 (4.2) | 0.0000 |
| `someip` | 5 | 29.8 (0.1) | 39.3 (3.9) | 54.0 (2.8) | 0.0000 |
| `can` | 5 | 30.1 (0.3) | 41.5 (4.4) | 55.7 (1.6) | 0.0000 |

## Verdict: PASS

`campaign verdict` (vxedged 0.29.0). Each loaded arm against `idle`: median p99 within 2x (µs), median
loss within 0.5 points (%).

| criterion | loaded arm | bound | outcome |
|---|---:|---:|---|
| `dds` / `dds-p99` | 53.4 | 107.3 | pass |
| `dds` / `dds-loss` | 0.0 | 0.5 | pass |
| `someip` / `someip-p99` | 54.0 | 107.3 | pass |
| `someip` / `someip-loss` | 0.0 | 0.5 | pass |
| `can` / `can-p99` | 55.7 | 107.3 | pass |
| `can` / `can-loss` | 0.0 | 0.5 | pass |

None of the three protocol loads shows in the ADAS slice at these rates: every loaded arm's median p99
is within 2.0 µs of the idle arm's, inside its IQR, and no probe was lost.
