# exp-014 — harness topology as a variable: star vs daisy chain vs ring

Does a **star** wiring harness (every zone gets its own direct run to the backbone) hold flat
latency regardless of physical position, while a **daisy chain** (zones wired in series)
accumulates delay/jitter with hop count? And does closing the chain into a **ring** cut its
farthest position from three hops to two? Nine devices, three positions, three wirings each — the
only declared variable across the nine arms is which harness each position is wired with
(`vehicle.yaml`'s per-link `impairments`/`harness`), so the campaign probes each
sequentially on an otherwise idle topology.

## The package

This folder is the `vxp/1` package `vxedge/exp-014`, version 0.3.0 (`vxp.yaml`). Its catalogue
alias is `exp-014`. `vxp.lock` records the digest of every file it holds.

`main.yaml` holds the experiment and what used to live in
[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.1/experiments/exp-014/scripts/run.sh) and
[`notebooks/analyze_exp014.py`](https://github.com/vxedge/vxperiments/blob/v0.2.1/notebooks/analyze_exp014.py):

| What | Where it was | Where it is |
|---|---|---|
| The arms, one per device (six in `run.sh`, nine now) | `ARMS` in `run.sh` | `campaign.arms`, each setting the `device` parameter, which binds `measurements[probe].from` |
| 5 repetitions, 10 s, then a 60 s probe window | `REPS`, `WARM_S`, `PROBE_S` in `run.sh` | `campaign.repetitions`, `warmup_s`, `duration_s`, and the `repro` profile |
| The probe at 1000 pps, inside the arm's device | `vxprobe send` under `ip netns exec` | `measurements.probe`, through the `probe_pps` parameter |
| The hop rule: each chain hop raises the median p50 by more than the star arms' spread, at least 1 µs | the notebook's verdict | `metrics` and `criteria` |
| The ring arms and the `ring` rule (0.3.0) | none: new with the package | `ring-*` devices and links, `campaign.arms`, the `ring` criterion |

Its criteria give the notebook's verdict, `hops=pass` with the same values, on the published
campaign (`../../scripts/verdict-parity.sh`, run by CI). That campaign has no ring arms, so `ring` is
inconclusive on it.

Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan --profile repro          # the 45 trials, checked; touches nothing
vxedge campaign start --profile repro         # one archive per trial, then the verdict
```

The `quick` profile checks the pipeline only and is never reported: one repetition of the nine
arms with `run.sh --quick`'s 2 s and 10 s windows. Unlike `run.sh --quick`, it keeps 1000 pps,
because a profile changes only repetitions and windows.

**One difference from `run.sh`:** a campaign trial brings up the whole vehicle, so all nine
devices are up during every arm, idle except the one probed. `run.sh` brought up one arm's device
at a time. The probe still runs inside the probed device's own network namespace and crosses its
link, so the hop it measures is the same.

Everything the experiment needs is in this folder: its documents, its identical payload
(`local/vxprobe:host-process`, no image or bundle to fetch), and the `results/` its campaigns write.

## Design

Three physical positions (`front-left`, `front-right`, `rear-left` — the fixed zonal
vocabulary, not invented names), each wired three ways:

- **Star**: every position gets its own direct run to the backbone — hop count is always one,
  regardless of physical position. This is the property under test, held identical across the
  three star arms, and it doubles as this campaign's noise floor (the `hops`
  criterion reads it): "no accumulation" is exactly what star means, so a separate zero-stimulus
  calibration pass isn't needed the way exp-010's borderline effect required one.
- **Chain**: front-left is nearest the backbone (1 hop), front-right is next (2 hops), rear-left
  is farthest (3 hops) — a plausible single wiring path around the vehicle. Delay/jitter
  accumulate with hop count.
- **Ring** (0.3.0): the chain's path closed back to the backbone, so each position takes the
  shorter way round. Front-left and rear-left are one hop each; front-right, opposite the
  backbone, is two. The `ring` criterion checks that the ring's farthest position sits below the
  chain's farthest by more than the star arms' spread, and still costs a hop over front-left.

Base unit is one 100BASE-T1 hop: 30µs delay / 5µs jitter, a round, **stated assumption**
covering PHY encode/decode plus modest store-and-forward for a short automotive frame —
propagation itself is ~5ns/m and negligible at these lengths, so it is not what this number
stands in for, and it is not a datasheet constant. The interesting result is whether
latency/jitter grow with hop count as this model predicts, not the absolute figure.

**Fidelity note** (testbed-quality: known gaps are stated where users will see them): `apply`
provisions one flat bridge — there is no backend that forwards through an intermediate switch
device — so a `chain-*` device's own access port carries the *cumulative* impairment a packet
from that position would accrue crossing every upstream segment, rather than three separate
links each forwarding through the last. `harness.length_m` on the same link records only its
own *local* segment, so summing it across the three chain links reconstructs the topology's real
total harness length — the number the notebook's harness-reduction accounting reported. The
ring's closing segment, rear-left back to the backbone, has no device link of its own, so
`seg-ring-rl` records both segments it touches (3.0 m) and the three ring links still sum to the
ring's total length.

## Measurement locality — why this experiment is built differently from exp-001/exp-002

Every device here is genuinely zoned up and probed from inside its own network namespace: the
probe is a declared measurement that vxedged runs in the arm's device, towards a reflector the
daemon places across the slice. The bash runner that produced the published campaign did the same
by hand (`zone up --vxid <device>`, then `ip netns exec vx-<device> vxprobe send ...`), rather than
addressing the device as a host-side veth peer in the script's own (default) network namespace,
the way exp-001/exp-002's runners did then.

This was found necessary while authoring this experiment, not chosen for style: a disposable
network-namespace repro of exp-001/exp-002's addressing pattern (prober and reflector both in
the same default netns) showed Linux's `local` routing table resolving the destination to
`dev lo` and delivering the traffic via loopback — `tcpdump` on the bridge access port captured
**zero packets**, and RTT was sub-millisecond against a 200ms netem. Putting the prober inside
the device's own netns and the reflector in the host's default netns puts them in different FIB
domains, so there is no shortcut available. The notebook that judged the published campaign
refused any archive whose `run-env.json` did not record `measurement_locality: cross-netns...`, so
an edit that reintroduced the same-netns pattern failed at analysis time rather than silently
producing numbers that never crossed the harness under test.

**What this does and doesn't establish about exp-001/exp-002 themselves**: the mechanism is
verified in isolation; whether their literal campaigns hit it on a real run — and therefore
whether H1/H3's frozen numbers measured the shaped bridge path or loopback delivery — is
deliberately left open rather than asserted here.

## Layout

| Path | `kind` | What it owns |
|---|---|---|
| `vxp.yaml`, `vxp.lock` | — | the package: identity, version, requirements, and the digest of every file |
| `main.yaml` | `experiment` | the one shared slice, telemetry, the probe, parameters, metrics, criteria and campaign |
| `vehicle.yaml` | `vehicle` | the nine devices, their addresses, and the star, chain and ring harness comparison |
| `parts.yaml` | `baseline` | the identical probe payload every arm carries |
| `results/` | — | a campaign's archives, one per trial |

Every YAML file declares its `kind` and `id`, and nothing references anything by path.
