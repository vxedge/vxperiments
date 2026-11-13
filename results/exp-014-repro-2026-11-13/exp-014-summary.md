# exp-014: harness topology, star vs daisy chain vs ring (live repro, 2026-11-13)

- campaign `c-0ddc6578a79a`, profile `repro`: 45 trials (5 repetitions of nine arms), every
  trial complete; the archives' digests match `campaign.json`
- package `vxedge/exp-014` 0.3.0, digest `sha256:e3431064f03ec19606714985b55c7e18c744207298aad1d38c68f47b6d0c2730`, locked
- probe: 1000 pps for a 60 s window after 10 s, from inside the arm's device
- tools (release builds): vxedged 0.27.0, vxprobe 0.2.3, vxtelemetry 0.8.0
- host: kernel 7.0.0-43-generic, PREEMPT_RT=False, CPU governor performance;
  run folder outside the home directory, host lock held for the whole run (no load log was kept)
- caveats: shared-host gateway; one flat bridge, so each device's access port carries the
  cumulative netem impairment of its path (`vehicle.yaml`'s fidelity note); one hop is a stated
  30 µs / 5 µs assumption, not a datasheet value

## Per arm

All values in µs: the median over 5 repetitions of each trial's quantile, hinge IQR in brackets.

| arm | hops | reps | p50 (IQR) | p95 (IQR) | p99 (IQR) | max loss % |
|---|---:|---:|---:|---:|---:|---:|
| `star-fl` | 1 | 5 | 118.5 (0.4) | 127.7 (1.6) | 139.0 (4.4) | 0.0034 |
| `star-fr` | 1 | 5 | 118.7 (0.5) | 128.6 (1.4) | 139.8 (3.7) | 0.0034 |
| `star-rl` | 1 | 5 | 118.8 (0.7) | 128.3 (1.0) | 138.5 (2.2) | 0.0067 |
| `chain-fl` | 1 | 5 | 118.3 (0.8) | 127.4 (1.1) | 138.1 (4.4) | 0.0034 |
| `chain-fr` | 2 | 5 | 179.5 (1.4) | 195.1 (2.0) | 205.1 (3.0) | 0.0017 |
| `chain-rl` | 3 | 5 | 240.1 (0.8) | 262.0 (1.2) | 271.1 (1.8) | 0.0017 |
| `ring-fl` | 1 | 5 | 118.7 (1.7) | 128.4 (3.4) | 141.1 (4.2) | 0.0034 |
| `ring-fr` | 2 | 5 | 180.1 (0.9) | 195.5 (2.4) | 205.6 (6.0) | 0.0034 |
| `ring-rl` | 1 | 5 | 118.8 (2.2) | 129.3 (2.8) | 139.9 (6.6) | 0.0050 |

## Verdict: PASS

`campaign verdict` (vxedged 0.27.0). Each rule's threshold is the star arms' p50 spread, at least
1 µs; the star arms here spread by under 1 µs, so the threshold is 1 µs.

| criterion | difference (µs) | threshold (µs) | outcome |
|---|---:|---:|---|
| `hops` / `fr-over-fl` | 61.1 | 1.0 | pass |
| `hops` / `rl-over-fr` | 60.7 | 1.0 | pass |
| `ring` / `chain-rl-over-ring-fr` | 60.0 | 1.0 | pass |
| `ring` / `ring-fr-over-ring-fl` | 61.4 | 1.0 | pass |

Each chain hop adds about 60 µs at p50: the round trip crosses each 30 µs hop delay twice. The ring bounds its
farthest position at two hops: front-right reads as the chain's two-hop position, and rear-left,
three hops on the chain, reads as one. The `hops` rule gives its published verdict again; the
`ring` rule is new in 0.3.0.

Harness length (from `vehicle.yaml`): star 12.0 m, chain 4.5 m, ring 6.0 m.
