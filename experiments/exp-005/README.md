# exp-005 — cold-start / first-packet latency after zone boot

Three earlier campaigns (exp-001, exp-002, exp-003) each showed their first-measured arm with
a p99 three to five times the others' and a normal p50 — a blown tail with a normal median,
what cold start looks like and not what a regression looks like
(`../../notebooks/cold_start.py` has the full account). None of those experiments were built to
measure the phenomenon, only to notice it as an incidental artifact their own warmup mostly
absorbed. This one measures it deliberately.

```bash
cd experiments/exp-005
sudo -E env "PATH=$PATH" ./scripts/run.sh --quick   # pipeline validation
sudo -E env "PATH=$PATH" ./scripts/run.sh --repro   # the campaign
python3 ../../notebooks/analyze_exp005.py results/exp-005-repro-<date>
```

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
`n`. The repetition axis (20 repetitions by default) is what carries statistical weight:
`analyze_exp005.py` reports the *distribution* of `(cold.max / steady.p50)` across repetitions,
not any single repetition's own percentiles.

## Measurement locality

Like exp-014 (and exp-001/exp-003 after `docs/ROADMAP.md` #28's fix), the device is genuinely
zoned up (`zone up --vxid node-cold-probe-01`) and probed via
`ip netns exec vx-node-cold-probe-01 vxprobe send ...` — prober in the device's own netns,
reflector in the host's default netns. Different FIB domains, so there is no same-netns
loopback shortcut for the kernel to take.

## Layout

| Path | `kind` | What it owns |
|---|---|---|
| `exp-005.vxp` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the one slice, method, telemetry |
| `vehicle.yaml` | `vehicle` | the single device and its address |
| `parts.yaml` | `baseline` | the vxprobe payload the device carries |
| `scripts/run.sh` | — | the campaign: zone up, cold burst, steady window, zone down |
| `scripts/lib/` | — | vendored: `freshness.sh`, `host_pinning.sh`, `results_dir.sh` |
| `results/` | — | archives, one per repetition |

Every YAML file declares its `kind` and `id`, and nothing references anything by path.
