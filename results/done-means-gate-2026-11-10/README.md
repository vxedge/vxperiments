# Done-means gate, 2026-11-10

The vxperiment upgrade's "done means" steps 1 to 7, run live through `vxmcp` as an agent would
(X8.4). Each step is an MCP tool call. Each check reads a typed field: an enum name, an
`ErrorReason`, a digest or a count. Every mutating call went through the human confirmation,
which the harness answered `accept`. The harness extends the 2026-11-04 gate's
([`../vxapi-0.5.0-gate-2026-11-04`](../vxapi-0.5.0-gate-2026-11-04)) and reuses its `agent.py`
unchanged.

**Result: 94 checks passed, 0 failed, and the host was clean after every campaign**
([`live/transcript.txt`](live/transcript.txt)).

## What ran

| What | Pinned as |
|---|---|
| vxedge (`vxedged`, `vxedge`) | 0.15.1 release binaries |
| vxmcp | 0.4.1 release binary |
| vxtelemetry | 0.6.0 release binary |
| vxprobe, vxtraffic | vxagents 0.2.0 release binaries |
| Signing | cosign 3.1.4, with a key pair made for this run, offline |
| Registry | a local OCI registry (`registry:2`) on loopback; nothing was pushed anywhere else |
| Package | `vxperiments/exp-001` 0.1.0, built by [`harness/package.py`](harness/package.py) |

**The package.** No experiment here is migrated to typed intent yet, which is X9.2. The gate uses
a scratch copy of [`experiments/exp-001-ws`](../../experiments/exp-001-ws) built by the harness:
- [`harness/exp-001-intent.yaml`](harness/exp-001-intent.yaml) replaces its `method` block. It
  carries exp-001's hypothesis, its `load_mbps` parameter bound to the infotainment load, the four
  metrics and the H1 criteria from [`notebooks/criteria/exp-001.yaml`](../../notebooks/criteria/exp-001.yaml),
  the probe as a declared measurement, a telemetry service, and the campaign. The campaign is the
  `idle` and `saturated` arms, a five-point load sweep, and the profiles `quick`, `repro` and
  `gate`.
- Its legacy descriptor is replaced by a `vxp/1` one, then the copy is locked.

The `exp-001` workspace itself is unchanged.

**The `gate` profile:** 3 repetitions of 5 points, with a 5 s warmup and a 20 s measure window
per trial, so 15 trials per campaign.

## Steps

| Step | Proof asked | What the gate did | Result |
|---|---|---|---|
| 1 | Typed `PackageInfo` | `package_list`, then `package_inspect` on the seven packages in `experiments/` and on the gate package. The gate package returns its hypothesis, `load_mbps` with bounds 0 to 1000 and its `binds` path, four metrics, criterion `h1` as a group of two comparisons, the two arms, three profiles, the measurement and 9 entities | passed |
| 2 | A tampered package is refused `SIGNATURE_INVALID`, with no host change | The daemon's trust policy requires a signature from one key. The author packed, signed and pushed the package. A tampered copy (H1's factor raised from 2.0 to 20.0) was pushed beside it, with the original signature. `pkg verify` refuses the tampered copy. `package_pull` of the tampered digest is refused `ERROR_REASON_SIGNATURE_INVALID`. `package_list` is unchanged, nothing is cached, and no pull job exists. The signed digest pulls, is listed as locked, and inspects by digest | passed |
| 3 | An out-of-bounds value is refused at plan time; a retried `request_id` returns the same campaign | `campaign_plan` by path and by digest: 25 trials, no problems. With `gate`: 15. A copy whose sweep adds 1200 is refused `ERROR_REASON_PARAMETER_INVALID` at plan time, naming `campaign.sweep.load_mbps[5]`. `campaign_start` of that copy is refused before the human is asked, and no campaign is recorded. A started campaign retried with its `request_id` returns the same job. Another `request_id` is refused `ERROR_REASON_BUSY`, naming the running campaign | passed |
| 4 | Phase markers match archive windows exactly | Both campaigns were followed with `campaign_watch` in 1 s windows, and the original's 15 archives checked against it. Each archive records provision, warmup, measure, cooldown and teardown in order, for its own trial. Every phase seen live is in that archive, in the same order, seen 0.5 to 1.5 s after its marker. A phase shorter than the window, usually cooldown, can pass unseen | passed |
| 5 | A typed verdict per criterion, with sample counts | `result_verdict`: `VERDICT_OUTCOME_PASS`, equal to the one `campaign_get` recorded. `h1-p99` and `h1-loss` both pass, with 3 trial values behind each read | passed |
| 6 | `Compare` reproduces the exp-001 repro-versus-frozen check | `result_compare`, rerun against the original: 20 metric and point pairs, 3 trials a side, both verdicts pass. The frozen reference could not be named; see below | partly |
| 7 | Fetch the archive, re-hash it, rerun from the archive alone | `result_list` names the 15 archives. `result_fetch` downloads each one, which re-hashes to its digest. `vxtelemetry verify` re-hashes each to its own workspace identity and package digest. The package inside one archive packs to the digest that ran. A second campaign started from that package alone, with the same checks as step 3, and ran 15 of 15 trials | passed |

**Rerun against the original:** 20 of 20 pairs within the original's IQR. p99 per point, rerun
median against original median (original IQR):

| Point | Rerun µs | Original µs | Original IQR µs |
|---|---:|---:|---:|
| idle | 64.4 | 63.7 | 12.7 |
| load 100 | 62.1 | 64.8 | 5.7 |
| load 250 | 61.7 | 60.2 | 7.9 |
| load 400 | 56.2 | 58.0 | 6.0 |
| saturated | 57.0 | 57.3 | 6.6 |

Loss was 0, and every trial of the original sent 20 000 probes. A dry run of the same harness an hour earlier, on
builds of the fixes below, landed 16 of 20: four p99 points fell outside IQRs of 1 to 8 µs. Three
20 s repetitions do not support an IQR claim either way. That claim is the methodology gate's:
exp-001's `repro` profile, 10 of 10 runs, on a quiet host with the `performance` governor. It is
still to run.

## Found and fixed during the gate

- **A retried `campaign_start` was refused while its campaign ran.** `CampaignService.Start`,
  retried with the same `request_id`, answered `ERROR_REASON_BUSY`. A retry with another profile
  resumed the earlier campaign under the new one. Fixed in
  [vxedge#143](https://github.com/vxedge/vxedge/pull/143) and released as vxedge 0.15.1.
- **A pulled package could not be planned or run through `vxmcp`.** `campaign_plan` and
  `campaign_start` took a path only, so a package pulled by digest could not be used. There was
  also no tool for `ResultService.Fetch`, so an agent that shares no filesystem with `vxedged`
  could not re-hash or rerun a result. Both fixed in
  [vxmcp#34](https://github.com/vxedge/vxmcp/pull/34) and released as vxmcp 0.4.1.

## What this does not show

- **Step 1 on migrated experiments.** The seven current descriptors are legacy: they inspect with
  an id and a version and no typed intent. The typed intent comes from the gate package, until
  X9.2 migrates them.
- **Step 6 against the published reference.** `ResultService.Compare` compares two campaigns this
  daemon recorded. The frozen exp-001 campaign is a set of `vxarchive/1` archives on Zenodo with
  no campaign record, so it cannot be named through vxAPI. `vxedge results compare` does compare
  against it offline; see [`../../notebooks/criteria`](../../notebooks/criteria) and
  `scripts/verdict-parity.sh`. How vxAPI should name a frozen reference was open at this run.
  Since vxedge 0.17.0, `ResultService.Compare` takes `reference_workspace`, and
  `results/exp-001/campaign.json` records the frozen campaign for it (see
  [`../../experiments/exp-001-ws`](../../experiments/exp-001-ws)).
- **Parameter overrides per call.** `CampaignService` takes a profile, not a value for each
  parameter. Values are changed in the package (arms, sweep, profiles), and bounds are checked at
  plan time, as step 3 shows.
- **The tampered package was refused by the trust policy before anything was fetched.** The
  check that fetched bytes hash to the digest, for a registry that serves other bytes, is not
  exercised here. vxedge's tests cover it for `PackageService.Import`, not for `Pull`.
- **Steps 8 to 10:** `vxmeter` (X10), the air-gapped run (X7, its own proof) and scenarios (X11)
  are outside this gate.
- **Nothing here is a timed result.** The parts are host processes.

## Files

- [`harness/`](harness):
  - `agent.py`: the 2026-11-04 agent, unchanged.
  - `gate.py`: the privileged pane, the daemon and the leak check.
  - `package.py`: builds the gate package.
  - `exp-001-intent.yaml`: what the gate package adds.
  - `donemeans.py`: the steps.
- [`live/`](live):
  - `transcript.txt`: the run.
  - The typed answers it checked: inspections, plans, both campaigns, their live phase
    observations, the verdict and the comparison.
  - Host paths are written as `$GATE_WORK`, `$VXPERIMENTS` and `$VX_BIN`.

## Reproduce

`gate.py` sends privileged steps (`setcap` on `vxedged`, starting it, the leak check) to a tmux
pane where `sudo` is cached. It needs a registry on `localhost:5000`. Keep `VX_BIN` and
`GATE_WORK` off `nosuid` mounts, where file capabilities do not apply.

```bash
podman run -d --rm --name gate-registry -p 127.0.0.1:5000:5000 docker.io/library/registry:2
export VX_BIN=/path/to/bin            # vxedged, vxedge, vxmcp, vxtelemetry, vxprobe, vxtraffic, cosign
export GATE_WORK=/path/to/scratch VX_PANE=vxpriv VXPERIMENTS=/path/to/vxperiments
python3 -I harness/donemeans.py       # or: catalogue pull plan campaign
```
