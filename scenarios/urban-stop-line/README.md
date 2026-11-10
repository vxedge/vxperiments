# urban-stop-line

A reference scenario (decision X-8): the ego drives toward a stop line behind a lead vehicle,
which brakes to a stop at it. It is small and deterministic, and it has three storyboard
parameters a campaign can turn.

| File | What |
|---|---|
| `scenario.yaml` | `kind: road` (`straight-200m`) and `kind: scenario` (`urban-stop-line`): simulator `esmini`, a 10 ms synchronous clock, seed 42, `Ego` as the vehicle under test, and the parameters with units and bounds |
| `assets/straight-200m.xodr` | ASAM OpenDRIVE 1.6: a straight 200 m two-lane road with a stop line at 150 m |
| `assets/urban-stop-line.xosc` | ASAM OpenSCENARIO 1.2: `Ego` and `Lead`, `Lead` braking at `LeadDeceleration` from 120 m |

| Parameter | Unit | Bounds | Storyboard default |
|---|---|---|---|
| `EgoTargetSpeed` | m/s | 0 to 22.2 | 13.9 |
| `LeadGap` | m | 10 to 80 | 30 |
| `LeadDeceleration` | m/s2 | 1 to 8 | 3 |

**Use it.** Vendor it into a package with `vxedge pkg vendor <path to this folder>`, which copies
both documents and both files and records their digests in `vxp.lock`. Then:
- name it in the experiment with `scenario: urban-stop-line`;
- set `actors.Ego.vehicle` to a vehicle of that package;
- list `esmini` in the descriptor's `requires.simulator`.

An experiment parameter turns a storyboard parameter with `binds: scenario.parameters.<name>`.

[`scripts/scenario-proof.sh`](../../scripts/scenario-proof.sh) does exactly that with
`vx-reference-sedan-01`. It shows that the package validates, locks and packs to the same
digest twice. CI runs it. Running the scenario in a simulator is the simulator work that follows.
Needs vxedge 0.15.0 or later.
