# exp-001 through vxAPI measurements (2026-11-09)

X3.4 of the vxperiment upgrade: exp-001 (H1, ADAS slice isolation under infotainment load) run
with no hand-built networking. The probe is a declared `measurements` entry that
`MeasurementService` runs inside `node-adas-probe-01`. The load is
`traffic_profiles.infotainment-load`, which `TrafficService` runs inside `node-infot-load-01`. The
daemon places the far side of the uplink for both. Nothing here uses `ip netns exec` or creates a
VLAN subinterface by hand. The question is whether this path measures what
[`run.sh`](../../experiments/exp-001-ws/scripts/run.sh) measures.

## Protocol

[`run-measurements.sh`](../../experiments/exp-001-ws/scripts/run-measurements.sh) follows run.sh's
`--repro` protocol:
- 5 repetitions of loads 0, 100, 250, 400 and 600 mbit/s, with the gateway and zones brought up and
  down per point.
- 10 s of load before a 60 s probe window at 1000 pps.
- The CPU governor set to `performance`.

For each point, the infotainment slice's sent bytes on the uplink confirm the load ran. 100 mbit/s
moved about 929 MB over the load's 74 s, and 250 mbit/s about 2.32 GB. 400 and 600 mbit/s both moved
about 3.59 GB, because the slice's 400 mbit/s ceiling caps them.

## What ran

| What | Pinned as |
|---|---|
| vxedge | `main` at `042ce73` (vxedge#121 measurements, #122 in-node traffic), release build of `vxedged` and `vxedge` |
| vxprobe, vxtraffic | vxagents `main` at `81546f7`, debug builds, as run.sh uses; sha256 `3b38a127c460a10a…`, `474e6870b8e6d7f1…` |
| Workspace | `experiments/exp-001-ws` at `90af35e`: `main.yaml` `06974051b789c9b0…`, `vehicle.yaml` `88b21967ed41a286…`, `parts.yaml` `84c5987f848f889a…`, `exp-001.vxp` `2f113e5f7f6cbad9…` (sha256), plus the `measurements` block and the load window `run-measurements.sh` adds |
| Parts | `local/vxprobe:host-process`, `local/vxtraffic:host-process`: the zones are host processes in their own network namespaces |
| Host | Linux 7.0.0-43-generic, not PREEMPT_RT, governor `performance`, userspace timestamps |

The per-point vxprobe summaries are in [`points/`](points/). Regenerate everything below with:

```bash
python3 notebooks/compare_exp001_paths.py results/exp-001-measurements-2026-11-09/points \
    frozen=results/exp-001 oct-run1=results/exp-001-repro-2026-10-13 \
    oct-run2=results/exp-001-repro-2026-10-13-run2
```

The run.sh archives are not committed (see [`../README.md`](../README.md)), so the reference columns
regenerate only where those archives are.

## Result

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 55.6 (7.7) | 68.2 (2.0) | 85.6 (5.1) | 0.0 |
| 100 | 5 | 60000 | 50.9 (1.1) | 72.8 (4.9) | 87.7 (6.6) | 0.0 |
| 250 | 5 | 60000 | 48.5 (2.4) | 68.7 (1.3) | 80.8 (3.5) | 0.0 |
| 400 | 5 | 60000 | 48.9 (2.7) | 68.3 (2.5) | 80.5 (2.7) | 0.0 |
| 600 | 5 | 60000 | 47.7 (2.5) | 69.8 (5.2) | 79.4 (6.6) | 0.0 |

**H1: p99 at 600 mbit / p99 idle = 0.93x (threshold 2.0x): holds.** Loss was 0 everywhere, with 60 000 samples per point.

## Against run.sh

The gate is the one the exp-001 repro checks use: the new median lies within the reference median
plus or minus the reference IQR, over 15 metric × load pairs. The stricter Q1..Q3 form is shown too.
The run.sh rows are the yardstick: they show how closely run.sh agrees with itself on this host.

| comparison | within median ± IQR | within Q1..Q3 | outside median ± IQR (µs, new minus reference) |
|---|---:|---:|---|
| measurements vs frozen | 10 / 15 | 6 / 15 | p50@0 +5.8, p50@400 -1.7, p95@400 -4.0, p99@400 -4.7, p50@600 -3.7 |
| measurements vs oct-run1 | 11 / 15 | 9 / 15 | p50@100 +1.7, p95@100 +3.3, p99@100 +2.6, p50@400 +2.8 |
| measurements vs oct-run2 | 11 / 15 | 10 / 15 | p50@0 +7.2, p50@100 +1.5, p95@100 +3.5, p99@100 +6.4 |
| run.sh oct-run1 vs frozen | 9 / 15 | 2 / 15 | p50@0 +6.0, p50@400 -4.4, p95@400 -7.2, p99@400 -8.0, p50@600 -3.0, p95@600 -4.2 |
| run.sh oct-run2 vs frozen | 8 / 15 | 1 / 15 | p50@0 -1.5, p99@0 -9.8, p50@400 -4.3, p95@400 -6.1, p99@400 -5.6, p50@600 -3.0, p95@600 -3.6 |
| run.sh oct-run2 vs oct-run1 | 12 / 15 | 12 / 15 | p50@0 -7.5, p99@0 -5.8, p99@100 -3.8 |


The measurements path agrees with each run.sh campaign about as well as run.sh agrees with itself:
- Against the two October reruns it scores 11 of 15, where those two score 12 against each other.
- Against the frozen campaign it scores 10 of 15, where the October reruns score 8 and 9.

The pairs outside the band are the same kind run.sh shows between its own runs:
- The idle p50 moves between about 48 and 56 µs from run to run. October run 1 read 55.9 µs, and
  this run 55.6 µs.
- At 400 and 600 mbit/s, the medians read a few µs below the frozen campaign, as both October reruns
  do.

## What this does not show

- **Not the same kernel as the references.** The frozen campaign ran on 7.0.0-28 and the October
  reruns on 7.0.0-38; this ran on 7.0.0-43. A run.sh campaign on this kernel was not repeated, so
  kernel drift and the path change are not separated. The October notes name the kernel as the
  leading suspect for their own shift.
- **A shared development host.** Other workloads were stopped for the run, and load averages stayed
  below 0.7, but the host is not isolated: no core pinning or IRQ isolation, and userspace
  timestamps.
- **Probe scrapes differ.** run.sh scrapes the probe across the slice every 5 s. Here vxedged reads
  it inside the node's namespace, and no telemetry service ran, so these points have probe
  summaries, not archives.
- **Only H1's topology.** Two container-backed zones, one to `internet` each. Node-to-node and capsule
  ends were checked for correctness elsewhere, not for timing equivalence.
