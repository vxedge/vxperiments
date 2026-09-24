# exp-014 — harness topology as a variable: star vs daisy-chained zones

Does a **star** wiring harness (every zone gets its own direct run to the backbone) hold flat
latency regardless of physical position, while a **daisy chain** (zones wired in series)
accumulates delay/jitter with hop count? Six devices, three positions, two wirings each — the
only declared variable across the six arms is which harness each position is wired with
(`vehicle.yaml`'s per-link `impairments`/`harness`), so the campaign runner probes each
sequentially on an otherwise idle topology.

```bash
cd experiments/exp-014
sudo -E env "PATH=$PATH" ./scripts/run.sh --quick   # pipeline validation
sudo -E env "PATH=$PATH" ./scripts/run.sh --repro   # the campaign
python3 ../../notebooks/analyze_exp014.py results/exp-014-repro-<date>
```

## This is a sandbox

Everything the experiment needs is in this folder: its documents, its campaign
(`scripts/run.sh`), its identical payload (`local/vxprobe:host-process` — no image or bundle to
fetch), and its results. One thing still reaches outside: `scripts/lib/*.sh` (frozen-results
protection, CPU governor pinning, binary freshness) are shared across every experiment;
`../../scripts/lib/` stays canonical and `../../scripts/lib/check-runners.sh` fails on drift.

## Design

Three physical positions (`front-left`, `front-right`, `rear-left` — the fixed zonal
vocabulary, not invented names), each wired two ways:

- **Star**: every position gets its own direct run to the backbone — hop count is always one,
  regardless of physical position. This is the property under test, held identical across the
  three star arms, and it doubles as this campaign's noise floor (see the analyzer's verdict
  section): "no accumulation" is exactly what star means, so a separate zero-stimulus
  calibration pass isn't needed the way exp-010's borderline effect required one.
- **Chain**: front-left is nearest the backbone (1 hop), front-right is next (2 hops), rear-left
  is farthest (3 hops) — a plausible single wiring path around the vehicle. Delay/jitter
  accumulate with hop count.

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
total harness length — the number the analyzer's harness-reduction accounting reports.

## Measurement locality — why this experiment is built differently from exp-001/exp-002

Every device here is genuinely zoned up (`zone up --vxid <device>`) and probed via
`ip netns exec vx-<device> vxprobe send ...`, rather than addressed as a host-side veth peer in
the script's own (default) network namespace the way exp-001/exp-002 do it.

This was found necessary while authoring this experiment, not chosen for style: a disposable
network-namespace repro of exp-001/exp-002's addressing pattern (prober and reflector both in
the same default netns) showed Linux's `local` routing table resolving the destination to
`dev lo` and delivering the traffic via loopback — `tcpdump` on the bridge access port captured
**zero packets**, and RTT was sub-millisecond against a 200ms netem. Putting the prober inside
the device's own netns and the reflector in the host's default netns puts them in different FIB
domains, so there is no shortcut available. `notebooks/analyze_exp014.py` refuses any archive
whose `run-env.json` doesn't record `measurement_locality: cross-netns...`, so a future edit
that reintroduces the same-netns pattern fails loudly at analysis time rather than silently
producing numbers that never crossed the harness under test.

**What this does and doesn't establish about exp-001/exp-002 themselves**: the mechanism is
verified in isolation; whether their literal campaigns hit it on a real run — and therefore
whether H1/H3's frozen numbers measured the shaped bridge path or loopback delivery — is
deliberately left open rather than asserted here. Tracked in `vxperiments/TASKS.md` (exp-001's
"Faithful measurement" item) and `docs/ROADMAP.md` ("Do not lose these").

## Layout

| Path | `kind` | What it owns |
|---|---|---|
| `exp-014.vxp` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the one shared slice, method, telemetry |
| `vehicle.yaml` | `vehicle` | the six devices, their addresses, and the star/chain harness comparison |
| `parts.yaml` | `baseline` | the identical probe payload every arm carries |
| `scripts/run.sh` | — | the campaign: zone up/probe/zone down per arm, sequentially |
| `scripts/lib/` | — | vendored: `freshness.sh`, `host_pinning.sh`, `results_dir.sh` |
| `results/` | — | archives, one per (repetition, arm) |

Every YAML file declares its `kind` and `id`, and nothing references anything by path.
