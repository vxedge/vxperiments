# exp-005 — cold-start / first-packet latency after zone boot

Three earlier campaigns (exp-001, exp-002, exp-003) each showed their first-measured arm with
a p99 three to five times the others' and a normal p50 — a blown tail with a normal median,
what cold start looks like and not what a regression looks like
([`notebooks/cold_start.py`](https://github.com/vxedge/vxperiments/blob/v0.2.1/notebooks/cold_start.py) has the full account). None of those experiments were built to
measure the phenomenon, only to notice it as an incidental artifact their own warmup mostly
absorbed. This one measures it deliberately. Its campaign runs through vxAPI
([The package](#the-package)).

## Design

One device, one slice, no offered load, no comparison arm: the only thing that varies across a
repetition is elapsed time since `zone up` returned. Every repetition runs **two probe calls
back to back**, on the same freshly-provisioned netns:

1. **Cold** — fired the instant `zone up` returns, zero warmup. This is deliberate, not an
   oversight: the warmup *is* the measurement here. The window is small (~60 samples at 20 pps
   over 3 s) so a slow first packet dominates its own `max`/`p50` instead of being averaged
   into invisibility, which is exactly what happened in exp-001/002/003's much larger
   first-arm windows — `cold_start.py`'s own account of why a 10 s warmup absorbs the effect
   that a 2-3 s one does not.
2. **Steady** — immediately after, on the same now-ARP-resolved, now-stable netns: a full
   60 s / 1000 pps window with real tail-percentile support (60 000 samples), this
   repetition's own baseline.

Comparing cold against steady **from the same repetition**, never across repetitions or days,
is what keeps the comparison free of host-state drift — the same self-referential logic
`cold_start.py` uses across arms, applied here across the two phases of one repetition instead.

**Sample-count caveat, stated because it matters** (testbed-quality: known gaps are stated
where users will see them): the cold phase's own `p99` must never be reported — ~60 samples is
two orders of magnitude below the ≥10 000 tail-percentile support the methodology skill
requires. Its `max` and `p50` are the reportable per-repetition figures, always stated next to
`n`. The repetition axis (20 repetitions by default) is what carries statistical weight: the
criterion reads `(cold.max / steady.p50)` per repetition and judges it across all repetitions,
not any single repetition's own percentiles.

## The package

This folder is the `vxp/1` package `vxedge/exp-005`, version 0.2.2 (`vxp.yaml`). Its catalogue
alias is `exp-005`. `vxp.lock` records the digest of every file it holds. It needs vxedge 0.20.0
or later, for measure windows and profile window lengths.

`main.yaml` holds the experiment and what used to live in
[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.1/experiments/exp-005/scripts/run.sh) and
[`notebooks/analyze_exp005.py`](https://github.com/vxedge/vxperiments/blob/v0.2.1/notebooks/analyze_exp005.py):

| What | Where it was | Where it is |
|---|---|---|
| The cold burst: 3 s at 20 pps the instant the zone is up, no warmup | `COLD_S`, `COLD_PPS`, `WARM_S=0` in `run.sh` | `campaign.windows[cold]`, which sets the `probe_pps` parameter to 20, and `campaign.warmup_s: 0` |
| The steady window: 60 s at 1000 pps on the same zone | `STEADY_S`, `STEADY_PPS` in `run.sh` | `campaign.windows[steady]` |
| 20 repetitions | `REPS` in `run.sh` | `campaign.repetitions`, and the `repro` profile |
| The probe, inside the device | `vxprobe send` under `ip netns exec` | `measurements.probe`, through `probe_pps` (`measurements[probe].rate_pps`) |
| Cold max and p50, steady p50 and p99, and their ratios | the notebook's per-repetition table | `metrics`, each reading its window; `ratio_max` and `ratio_p50` divide within one repetition |
| The rule: cold max at least 2x steady p50 (`cold_start.py`'s `RATIO_MULTIPLE`), on every repetition | the notebook's verdict | `criteria`: the smallest `ratio_max` across repetitions is at least 2.0 |

The published campaign confirms the effect on 20 of 20 repetitions, which this criterion reads as
`cold-start=pass`. Verdict parity cannot check it against the published archives: those
`run.sh` archives hold the cold burst only as a summary file, never as samples, so the engine has
nothing to read for the cold window. A campaign of this package records both windows.

Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan --profile repro          # the 20 trials, each a cold and a steady window
vxedge campaign start --profile repro         # one archive per trial, then the verdict
```

The `quick` profile checks the pipeline only and is never reported: two repetitions with
`run.sh --quick`'s 10 s steady window. Unlike `run.sh --quick`, it keeps the steady window at
1000 pps, because a profile changes window lengths, not what a window sets.

**Differences from `run.sh`:**
- Each window starts the probe afresh, so the steady window's figures are its own, as `run.sh`'s
  second `vxprobe send` was.
- The cold window's values are the last samples the telemetry service took inside it, every 1 s.
  `run.sh` read the burst's own end-of-run summary instead.
- The probe's timeout is vxprobe's default in both windows. `run.sh` gave the cold burst 2000 ms
  and the steady window 1000 ms, and a measurement has no timeout field yet.

## Measurement locality

Like exp-014, the device is genuinely zoned up and probed from inside its own network namespace:
the probe is a declared measurement that vxedged runs in `node-cold-probe-01`, towards a reflector
the daemon places across the slice. The bash runner that produced the published campaign did the
same by hand (`zone up --vxid node-cold-probe-01`, then
`ip netns exec vx-node-cold-probe-01 vxprobe send ...`, with the reflector in the host's default
netns). Prober and reflector sit in different FIB domains, so there is no same-netns loopback
shortcut for the kernel to take.

## Layout

| Path | `kind` | What it owns |
|---|---|---|
| `vxp.yaml`, `vxp.lock` | — | the package: identity, version, entry point, requirements, and the digest of every file |
| `main.yaml` | `experiment` | the one slice, the measurement, the telemetry service, metrics, criteria and the campaign's windows |
| `vehicle.yaml` | `vehicle` | the single device and its address |
| `parts.yaml` | `baseline` | the vxprobe payload the device carries |
| `results/` | — | a campaign's archives, one per trial |

Every YAML file declares its `kind` and `id`, and nothing references anything by path.
