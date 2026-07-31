# TASKS.md — vxedge/vxperiments

## Phase 1 (gate-defining — **PASSED 2026-07-13**: exp-001/exp-002-exp-002b/exp-003 deliver the H1/H3/H4 numbers)

- [x] Repo layout: `experiments/`, `notebooks/`, `results/README.md` (`vehicles/` with the
      phase-3 vehicle manifest)
- [x] `exp-001` — ADAS slice isolation (H1). Full campaign run 2026-07-10 (5 reps x 5 loads,
      60k samples/point, governor=performance): **H1 HOLDS — adas p99 0.93x baseline under
      600 mbit offered overload, zero loss**; load delivery verified (600.0 mbit, 0 errors);
      frozen summary committed (results/exp-001/exp-001-summary.md)
- [x] `exp-002` — virtualization packaging (H3). Full campaign 2026-07-11 (5 reps x 3 arms,
      60k samples/arm), **superseded 2026-07-13 by a re-run under the single-arm isolation
      fix** (see "hardening" item below): current frozen numbers are p50 container 54.3 µs,
      libvirt +12.0, qemu-microvm +59.2 (p99: 89.9 / +20.8 / +69.6), zero loss — **H3 still
      HOLDS**, same ordering (container < libvirt < microvm). The isolation fix moved
      libvirt down measurably (p50 74.5→66.3 µs, p99 122.8→110.7 µs — more than the
      original run's own IQR), while container/microvm barely moved (within ~2µs, close to
      exp-001's rerun's general host-drift noise); consistent with exp-002b's independently
      isolated libvirt-q35 arm (p50 70.3 µs, between the two exp-002 numbers). Reading: the
      original concurrent-arm design's background container+microvm processes measurably
      inflated libvirt's latency specifically — H3's conclusion doesn't change, but the
      libvirt magnitude does, and the isolated number is the one to cite going forward.
      Frozen summary updated in place
- [x] `exp-003` — OTA co-location (H4). Full campaign 2026-07-13 (5 reps x 2 arms, 1000 pps
      x 60s, zero loss both arms): **H4 HOLDS — adas p50 45.8µs under a sustained OTA
      delivery burst vs 47.2µs baseline** (Δ -1.4µs, within IQR; p95/p99 likewise
      near-identical: 67.5 vs 69.6, 80.1 vs 82.0). Burst confirmed real: ~355 successful
      deliveries/rep, zero failures, ~206ms median per-delivery latency for the 5MB
      artifact (~1.7GB transferred per rep's burst arm). Same adas slice/QoS/probe params
      as exp-001, directly comparable to its load=0 and heaviest-load points. Frozen
      summary committed (results/exp-003/exp-003-summary.md). Built from day one with
      every lesson from the exp-002b review (guarded `vxprobe send`, loss w/ denominator,
      `tool_versions`, 10s warmup) — also caught and fixed a real bug in vxota-probe's
      `--repeat` driver mode before the campaign ran (silently skipped re-download after
      the first fetch). Post-campaign audit found `baseline` archives showing ~50%
      aggregate telemetry completeness — root-caused to the OTA burst driver's exporter
      having nothing listening during that arm (a manifest scrape-target gap, not real
      data loss; the adas-relevant target was 100% complete every rep) — explained in the
      analyzer output, no re-run needed. **This closes the phase-1 gate** (H1+H3+H4 all
      delivered).
- [ ] Baseline notebook: parse collect archives → percentile tables + isolation charts + CSV
- [x] `exp-001` reproducibility check (2026-07-13): full second campaign, same manifest
      sha256 (`e51721c1a5a0…`), 25 archives, zero loss. **Reproducible**: 14 of 15
      median/metric pairs land within the original campaign's IQR; the one miss (p99 at the
      `load0` baseline, -6.7µs vs a 4.3µs IQR) reflects a uniform small downward shift
      present at every load point, not a methodology issue, and doesn't move the H1 verdict
      (0.93x original vs 0.95x rerun, both well under the 2.0x threshold). Recorded
      separately from the frozen original: `results/exp-001/exp-001-repro-check-2026-07-13.md`.
- [x] `exp-003` reproducibility check (2026-07-13): full second campaign, 10 archives, zero
      loss. **0 of 6 metric/arm pairs land within the original campaign's IQR** (a uniform
      ~4-7µs downward shift across both arms, same-day — the weakest reproducibility check
      of the three run this session). The substantive H4 comparison is unaffected (Δp50
      -1.4µs original vs -0.7µs rerun, same order of magnitude/sign, both within their own
      IQR threshold — **H4 still holds**) because it's a within-campaign relative
      measurement and both arms drifted together. Honest reading: this host's absolute RTT
      baseline drifts several µs across sessions hours apart even same-day — larger than
      any single campaign's own IQR — so within-campaign IQRs bound repetition noise, not
      cross-session drift; the comparative hypotheses (H1/H3/H4) are robust to this, but an
      absolute-µs figure from any one campaign is a property of that session/host, not a
      fixed constant. Not gate-blocking. Recorded separately from the frozen original:
      `results/exp-003/exp-003-repro-check-2026-07-13.md`. Also fixed in the same pass:
      `analyze_exp003.py`'s telemetry-completeness caveat was a hardcoded "~50%" claim
      (true only of the original, pre-`optional_scrape_targets` archives) — now computed
      dynamically per campaign from `ingest/ingest-stats.json`'s required/optional scrape
      counters, confirming the schema fix works (this rerun: 100% required-target
      completeness both arms, optional-target completeness 0%/100% baseline/ota-burst
      exactly as designed).
- [x] Frozen-campaign protection in every runner (2026-07-13): `lib/results_dir.sh` —
      full runs refuse a results dir already holding archives; `--repro` writes to
      `results/<exp>-repro-<date>/`, `--quick` to `results/<exp>-quick/`. Root cause:
      exp-003's original archives were overwritten in place by its repro rerun, losing
      the original manifest digest to a truncated summary prefix (docs/STATUS.md risk
      item). Behavior-tested against the live tree; shellcheck-clean.
- [x] `scripts/run-smoke.sh` (2026-07-14): H* pipeline smoke — every experiment's
      `--quick` mode + analyzer, chained, ~5 min total, single PASS/FAIL summary. Keeps
      the H1/H3/H4 pipelines verifiably alive after any change; full campaigns and
      `--repro` reruns stay deliberate/manual (idle host, methodology skill)
- [x] **CI** (2026-08-01, `.github/workflows/ci.yml` — this repo had none). Two jobs:
      `runners` (no secrets, always runnable) runs `scripts/lib/check-runners.sh` — shellcheck
      *including SC2154* plus each runner's preamble executed under `set -u`; and `workspaces`
      validates every `experiments/*-ws/` through `vxedge manifest validate` and asserts the
      retired §6.1 manifests are still *refused*, so a day when they parse is a day something
      resurrected the old schema.

      The preamble check exists for a real regression: an edit removed the two lines resolving
      `$RESULTS` from `run-exp-001.sh`, `bash -n` passed it, and the campaign died on the first
      run after a sudo prompt and a build. Verified by re-introducing that exact deletion — the
      check fails, `bash -n` still passes.

      `workspaces` needs a `VXEDGE_CROSS_REPO_TOKEN` secret (vxedge is a separate private repo;
      `GITHUB_TOKEN` cannot check it out). Until it is provisioned the job fails at checkout
      rather than skipping — the same choice, for the same reason, as vxmodels'
      `pipeline-regression`. Still open: workspace-validation over experiments/ and
      vehicles/) — phase 2, once the CLI subcommand exists
- [ ] CI: workflow_dispatch pipeline re-running exp-001 end-to-end and diffing distributions
      (§13 on-demand reproduction; needs KVM-capable runner) — phase 2

## Phase 2

- [x] `exp-002b` — H3 decomposition. Full isolated campaign 2026-07-12 (5 reps x 6 arms,
      60k samples/arm), **reconfirmed by a second independent campaign the same day**
      after an 8-angle code review fixed 10 issues in the runner/analyzer/vxtelemetry
      sampler (unguarded `set -e` aborts, an ingest/sample scrape-window mismatch, a
      warmup below the methodology skill's minimum, missing metadata, orphaned/silently-
      swallowed sidecar failures, blocking calls on the async runtime, a cleanup-trap
      zone-list drift risk, a `--out-dir=DIR` parsing gap — see docs/STATUS.md "Code-review
      hardening + reproducibility confirmation"). Both campaigns independently audited:
      1.8M probes, zero loss, zero warnings, same verdicts each time. The "microvm slower
      than full VM" finding from exp-002 is **not a machine-type effect** — machine
      (q35 vs microvm, transport/vhost fixed) shows NO measurable difference (Δp50
      -0.3µs, within IQR). The real drivers: **virtio transport** (MMIO vs PCI, Δp50
      -26.0µs — dominant), **vhost-net** (Δp50 -9.5µs), and **management layer**
      (libvirt is FASTER than raw QEMU by default, Δp50 -17.3µs, likely libvirt enabling
      vhost/optimized virtio by default). Resource cost: container cheapest (4.3% CPU,
      7.3MB); microvm-mmio most CPU-hungry of all VM arms (~15.0%) despite being the
      "lightweight" option. Frozen summary committed (updated in place by the second
      campaign). *(First campaign attempt was invalidated by a concurrent-VM
      CPU-contention bug, root-caused and fixed — runner now isolates one arm at a time
      with `isolation: single-arm` provenance the analyzer enforces.)*
- [x] `exp-002` hardening (2026-07-13): retrofit the same single-arm isolation the exp-002b
      incident forced — the frozen H3 result was clean but that was luck, not a property of
      the runner's design (all 3 arms ran under one zone, concurrently). `exp-002.yaml` now
      declares one zone per arm (`z-cont`/`z-microvm`/`z-libvirt`, was one `vxzone-front-left-01`
      holding all three nodes); `run-exp-002.sh` gained a `ZONE_OF` map + `start_arm()`/
      `stop_arm()` (mirrors exp-002b's pattern) so exactly one arm's zone is up at a time,
      plus every other exp-002b/exp-003 hardening lesson (`isolation: "single-arm"`
      provenance, guarded `vxprobe send`, `tool_versions`/`cpu_pinning` in `env_metadata()`,
      `WARM_S` 5→10, surfaced `wait` exit codes instead of swallowing them); `analyze_exp002.py`
      now refuses archives missing `isolation=="single-arm"` (matching `analyze_exp002b.py`),
      reports loss with lost/sent denominator instead of a bare median, and accepts both
      `--out-dir DIR` and `--out-dir=DIR`. Manifest re-validated (`vxedge manifest validate`:
      3 zones, was 1); analyzer smoke-tested against synthetic archives including the
      isolation-refusal path. **Re-run done 2026-07-13**: 15 archives, zero loss, H3 still
      holds; libvirt's number moved measurably (see the `exp-002` entry above for the
      numbers and reading) — frozen summary updated in place.
- [x] `check_fresh()` whole-repo false-positive fixed (2026-07-13): extracted
      `scripts/lib/freshness.sh`'s `check_fresh_bin()`, shared by all four run-exp-*.sh
      scripts, which walks each crate's *actual* local path dependencies (parsed from its
      own Cargo.toml, recursively) instead of scanning the whole repo. Verified against
      the exact regression that motivated it: touching `vxota-probe`'s source no longer
      flags the unrelated `vxota` server binary, while still correctly catching real
      staleness. Also closed a smaller, previously-noted gap while consolidating:
      `run-exp-002b.sh`'s `check_fresh` never covered the `vxedge` CLI binary at all
      (only `vxedged`), despite the script calling it throughout — now covered like the
      others. (Deliberately does *not* check `Cargo.lock`'s mtime — cargo touches it on
      most invocations regardless of relevance, which would reintroduce false positives
      more often than it would catch the rare transitive-dependency-bump case it's meant
      to guard.)
- [x] Arm-conditional scrape targets fixed (2026-07-13): manifest schema gained
      `telemetry.prometheus.optional_scrape_targets` (vxedge-core, docs/ARCHITECTURE.md
      §6); `vxtelemetry` tracks their failures in separate counters that never lower
      `completeness_pct()`. `exp-003.yaml` now declares the OTA burst driver's exporter
      there instead of as a required target — future exp-003 campaigns will show 100%
      completeness on `baseline` archives instead of the ~50% figure the already-frozen
      2026-07-13 campaign shows (that figure remains correctly explained in
      `results/exp-003/exp-003-summary.md`, not re-run just for this).
- [x] `exp-010` — H2: identical topology, `mode: vlan` vs `mode: s-nssai` slices compared.
      **Campaign complete, real numbers in hand (2026-07-18): H2 DOES NOT HOLD as measured,
      root cause identified.** Modeled model-first
      (`vxmodels/models/experiments/exp-010-h2-real-slicing.sysml`,
      `Exp010RealSlicingComparison`); the model's own doc comment is explicit the vlan arm
      of this comparison is exp-001 itself (identical mechanism, already-frozen numbers, no
      same-day rerun) — this campaign covers only the snssai arm.
      `experiments/exp-010.yaml` hand-derived from the model (diffed field-by-field against
      `exp-001.yaml` in its own header comment); `scripts/run-exp-010.sh` drives everything
      through real vxAPI RPCs (`vxedge up`, `vxedge traffic up --profile`), no raw `ip`
      anywhere — the engineering bar this campaign was built to clear. Found and fixed two
      real bugs getting there: (1) `TrafficService`'s `profile_up` never passed
      `--duration-s`/`--payload-bytes` to the spawned probes, silently undershooting the 60s
      measured window (`vxedge/TASKS.md` has the account); (2) the script itself initially
      ran the whole process under `sudo`, which switches podman to root's own separate
      identity/storage — never had `vx5g-core`/`vx5g-ran` built into it, broke image
      resolution on the very first live attempt. Fixed: run as a normal user, `Shell`'s own
      `escalate: true` already sudo-wraps just the `ip`/`bridge`/`tc` calls that need it
      (matches `verify_traffic_service.sh`'s already-proven pattern and the warning already
      in `fiveg_podman.rs`'s own module comment — this was a live-caught instance of exactly
      that documented trap). `notebooks/analyze_exp010.py` built alongside
      `analyze_exp001.py`'s own shape, plus a `--baseline results/exp-001` comparison + H2
      verdict.
      **Real campaign** (25 archives, 5 reps x 5 loads, 60s window/1000pps, 60k
      samples/point, zero loss every point): adas p99 grows 329.2us (0mbit) -> 410.9us
      (600mbit) in the snssai arm (1.25x) vs 77.3us -> 71.7us (0.93x, essentially flat) in
      the vlan arm (exp-001) — **H2 does not hold on this host**. Root-caused by code
      inspection, not left as a data mystery: `fiveg::subscriber` hardcodes an identical
      QCI/5QI=9, ARP priority_level=8, and 1 Gbps AMBR for every subscriber/slice;
      `render_smf`/`render_upf` never reference the manifest's `Slice.qos` block at all — the
      vlan arm's isolation comes from real HTB priority+rate enforcement the snssai arm has
      no equivalent of, so this is an unequal comparison, not evidence against the
      hypothesis. Gap tracked and **closed same day**: `vxedge/TASKS.md`'s "Per-slice
      downlink QoS enforcement for s-nssai slices" — the obvious-looking fix (render
      `Slice.qos` into subscriber 5QI/ARP/AMBR) was checked empirically before writing it
      (a hand-patched 20mbit AMBR had zero measured effect — Open5GS's software UPF
      records it but doesn't enforce it here), so the real fix is kernel-level HTB
      (`gateway::provision::apply_fiveg_slice_qos`, the same proven mechanism
      `apply_slices` already uses for the vlan arm) instead. `experiments/exp-010.yaml`
      now declares `qos` on both slices (copied verbatim from `exp-001.yaml`) to opt in.
      Live-verified: `tc` output confirms the tree installs exactly as designed; a
      600mbit offered load capped to ~395mbit received with zero packet loss, adas-probe
      held p50 276.5µs/p99 340.5µs throughout — a single unpowered rep, not yet a
      campaign. **Full evidence record for the pre-fix result**:
      `vxmodels/models/requirements/verification.sysml`'s `Exp010RealSlicingVerification`
      (`verify h2`), `results/exp-010-no-qos-2026-07-18/exp-010-summary.md` — preserved as
      the honest record of what that campaign measured (moved aside so the corrected
      rerun could become the canonical `results/exp-010/`, matching `exp-002`'s own
      retrofit precedent).
      **Full 5×5 rerun with the qos fix in place (2026-07-18): still formally borderline
      (snssai 1.03x growth vs a 1.023x threshold — a 0.007 margin), but qualitatively a
      different result from the pre-fix campaign** — non-monotonic (321→334→369→328→330µs
      across loads, not a clean climb), with a specific, reproducible bump at 250mbit
      (tight IQR of 5.0µs across all 5 reps) that doesn't fit a "degrades under increasing
      contention" story. `analyze_exp010.py`'s hardcoded root-cause text (written for the
      pre-fix campaign) was printing unconditionally regardless of what actually changed —
      removed; root-cause explanations belong in the boards, per-campaign, not baked into
      a script.
      **Host-confound investment, not another patch aimed at the number**: rather than
      keep tuning the verdict threshold, closed real, previously-tracked-but-never-fixed
      testbed gaps — this campaign's own governor was left on `powersave` (nobody ever
      set it; every prior script only recorded it), and nothing pinned the
      measurement-critical processes away from the ~13 containers this campaign's own 5G
      core spins up. `scripts/lib/host_pinning.sh` (new, shared) sets `performance`
      governor for the run's duration and taskset's `vxedged`+the host-side
      `vxprobe`/`vxtraffic` processes to reserved cores — best-effort, honestly recorded
      per-archive, not oversold as full isolation. `run-exp-010.sh` also now randomizes
      load order per repetition (every prior campaign in this project used a fixed
      sequence, so a position-correlated host effect would be indistinguishable from a
      load-correlated one — exactly the ambiguity the 250mbit bump raised) and records the
      applied order + position for direct analysis. New
      `scripts/calibrate-exp-010-noise-floor.sh` + `notebooks/analyze_noise_floor.py`:
      adas-probe alone, full rebuild between reps, characterizes session-to-session
      variance with zero stimulus — not a hypothesis test, the background any future data
      point needs to clear before being called a real effect.
      **H2 HOLDS — real, final verdict (2026-07-18).** Noise-floor calibration ran first
      (15 reps, zero stimulus): p99 median 338.9µs, IQR 14.3µs, range 316.7–355.3µs (spread
      38.7µs) — the background any campaign point needs to clear. Then the full 5×5
      campaign, now with governor pinning + cpu affinity + randomized load order: adas p99
      growth baseline→600mbit is **1.00x** (345.3µs → 345.9µs, essentially flat) vs vlan's
      own 0.93x — comfortably inside the 1.10x tolerance. **H2 HOLDS.**
      The 250mbit elevation (median 352.0µs, still the highest of the five points) persists,
      but randomization proves it's load-correlated, not position-correlated: it ran at
      every one of the five possible sequence positions across the five reps (position 3,
      5, 4, 1, 2 respectively — recorded in each run's own `run-env.json`) and stayed
      elevated regardless of when it ran. Its magnitude shrunk substantially though —
      inside the noise floor's observed range, with a tighter IQR (13.1µs) than the noise
      floor itself (14.3µs) — a real but small effect, not the dominant signal it looked
      like before the host-confound work landed.
      Full evidence trail preserved, not just the final answer: `results/exp-010-no-qos-
      2026-07-18/` (pre-HTB-fix, DOES NOT HOLD, root cause identified), `results/exp-010-
      qos-fix-unmitigated-2026-07-18/` (HTB fix landed, still formally borderline DOES NOT
      HOLD by a 0.007 margin), `results/exp-010-noise-floor-2026-07-18/` (calibration),
      `results/exp-010/` (this final HOLDS campaign, now canonical).
      `vxmodels/models/requirements/verification.sysml`'s `Exp010RealSlicingVerification`
      updated with the full trajectory (`verify h2`).
- [ ] `exp-011` — real ADAS traffic: CARLA → ROS2 → Autoware through the adas slice. The
      other, still-open half of phase 2's gate (`docs/TASKS.md`) — H2's vlan-vs-s-nssai
      half HOLDS (2026-07-18). **Re-scoped 2026-07-26** (`docs/TASKS.md` Track P/D): blocked
      on `vxparts` (renamed/merged from `vxzones`+`vxcompute`) landing Autoware/ROS2 + CARLA
      server + carla-ros-bridge as real published parts, plus the `ARCHITECTURE.md` §6
      schema gaining a structured `parts:` list (Track D dimension 1) so this experiment's
      manifest can reference them — same zero-code blocker as before, now with a named
      dependency chain instead of an open-ended "vxcompute needs code"
- [ ] `exp-013` — closed-loop control latency under slice contention (world → sensors →
      slices → AD stack → actuation → world), with/without infotainment load
- [ ] `exp-014` — harness topology as variable: star vs daisy-chained zones under identical
      load (per-link `impairments`, BASE-T1 emulation)
- [ ] Determinism-controls ablation: PREEMPT_RT / pinning / VPP on-off matrix

## Workspace migration (decided 2026-07-30 — §6.0 becomes the only authored schema)

Every experiment here is currently a hand-written §6.1 manifest driven by a campaign script that
does its own provisioning (`vxedge up --manifest`, then `vxprobe`/`vxtraffic` as raw binaries,
then `vxedge down`). §6.1 is being retired as an authoring surface, so each experiment becomes a
**workspace folder** run by `vxedge experiment up` from inside that folder.

**This migration is the real test of §6.0.** The acceptance criterion is not "it validates" — it
is **numerical equivalence with the frozen result**. If workspace-form `exp-001` does not
reproduce the recorded H1 numbers, the workspace model is wrong and we find out here rather than
in phase 3. Migrate as *parallel copies*; the frozen manifests keep working until equivalence is
proven, and phase-1 reproducibility stays anchored at the `v0.1.0` tag regardless.

Blocked on `vxedge/TASKS.md` section 0 items (1)–(3) landing first.

- [x] **`exp-001` → workspace form** (2026-07-30, `experiments/exp-001-ws/`) — **structurally
      equivalent**: both forms produce a byte-identical `GatewayPlan` and `TrafficPlan` (same
      endpoint names, vlans, slices, addresses). That is the check
      that matters rather than a YAML diff — the forms legitimately differ in ids and defaults
      while planning identically, and `run-exp-001.sh` addresses `vzp0`/`vzp1` by name, so a
      renumbering would keep validating and quietly measure the wrong interface. Locked in by a
      regression test in `vxedge-core`.

      Found three §6.0 defects the scaffold templates could never surface: `backend` was not
      expressible at all (these zones are container-backed host processes, so they lowered to
      `kind: vm`, defaulted to libvirt and failed with `MissingBundle` — and `backend` is H3's
      variable, so exp-002 was blocked too); `local/vxprobe:host-process` was rejected as an
      unpinned published ref though it names no artifact; and `vxedged` sudo-ed even when
      already root, which is how the campaign scripts run it. All fixed in `vxedge`.
  - [ ] **Numerical equivalence** — `./scripts/run-exp-001.sh --repro` now provisions from the
        workspace (the only form there is since 2026-07-31) and holds everything downstream
        identical, so the only variable is which form the gateway came from. Until p50/p95/p99
        agree with the frozen campaign, the recorded `results/exp-001/` stays authoritative.
        This is part of docs/TASKS.md item 7 and needs a provisioning-capable host.
  - [ ] **Faithful measurement: run the agents inside the zones** — the direction of travel, and
        the reason `--workspace` deliberately does *not* use `vxedge experiment up`. The frozen
        campaign treats the host-side veth peers as if they were the ECUs;
        `experiment up` actually brings the zones up, which moves those peers into node netns and
        renames them `eth0`. Running vxprobe/vxtraffic inside the zone netns measures the path an
        ECU really takes — across the zone boundary — instead of a host process pretending to be
        one. **This is a different measurement and needs its own baseline**, so it must not be
        mixed into the equivalence check above: do that first, then re-baseline here.
        Touches `run-exp-001.sh` (agents via `ip netns exec vx-<node-id>`), and the same change
        applies to exp-003. Blocked on nothing.
- [x] **`exp-003` → workspace form** (2026-07-30, `experiments/exp-003-ws/`).
- [x] **`exp-010` → workspace form** (2026-07-30, `experiments/exp-010-ws/`) — the only
      `mode: s-nssai` coverage there is; its `FiveGPlan` matches the frozen manifest's session
      for session (SUPIs, UE subnets, tun devices).
- [x] **`exp-002`/`exp-002b` → workspace form** (2026-07-31, `experiments/exp-002-ws/`,
      `exp-002b-ws/`) — both produce plans identical to the manifests they replace: same
      interface names, vlans, slices, addresses, bundles and backends, across all three and all
      six arms.

      They were blocked on three §6.0 gaps, all closed in `vxedge` first (see that repo's
      TASKS.md): link endpoints had nowhere to put the address that is the *only* thing telling
      exp-002's arms apart; interface names were positional, so the two schema paths ordered the
      arms differently and would have measured libvirt while reporting microvm; and a part's
      kind was derived from the device's backend, so a mis-pointed H3 arm was unrepresentable
      rather than rejected. Migrating them also found a VM's guest bundle to be unreachable in
      §6.0 at all (the zone planner looked software up by the wrong id), and `zone up --vxid`
      unable to select a single arm — the isolation contract exp-002b's first campaign was
      invalidated for lacking.

      Device ids are the frozen manifests' node ids, so the two forms stay diffable and the
      recorded results keep naming the same things. Each workspace's README records what its
      migration needed.
- [ ] **Campaign scripts shrink to method.** Sweeps, repetitions, warmup and collection stay —
      that is the experiment design and belongs here. Provisioning moves to `experiment up`.
- [ ] **Author `exp-011` as a workspace now**, declaring `requires: {gpu: tier2}` in its `.vxp`.
      It validates, commits, and refuses to start until a Tier 2 host exists — so the workspace
      is ready the day the GPU decision resolves and blocks nothing in the meantime.
- [x] **Runners read workspaces** (2026-07-31) — every `run-exp-*.sh` provisions from the
      `-ws` directory and passes it to `vxtelemetry --workspace`; §6.1 manifests stopped being a
      provisioning input, and pointing a tool at one now says so and names the fix. exp-010's
      per-point sweep copies the workspace and patches `main.yaml` rather than sed-ing one file.
      Interface names in the runners changed once, deliberately, from positional `vz0`/`vzp0` to
      id-derived (`ARCHITECTURE.md` §6.0.5).
- [ ] Retire the hand-authored §6.1 manifests. They are already unrunnable; they stay in
      `experiments/` as provenance for the results recorded against them, and go when nothing
      cites them.

## Found by the 2026-07-31 workspace campaign

- [ ] **The first measured arm's tail is biased high under `--quick`, in every campaign.**
      Three quick runs, three inflated first-arm p99s with medians unaffected:

      | campaign | first arm | its p99 | later arms | its p50 |
      |---|---|---:|---:|---:|
      | exp-001 | load0 | 301.6 | 82.2 | normal |
      | exp-002 | container | 441.1 (frozen: 89.9) | 181 / 127 | 57.7 (frozen 54.3) |
      | exp-003 | baseline | 297.0 | 86.1 | 49.5 |

      Positional, not arm-specific — exp-003's first arm is `baseline`, not a container. A few
      very slow packets at the start of the first probe (page faults, ARP, veth/netns warm-up,
      CPU frequency ramp before the pinned governor settles) barely move a median over 5000
      samples but dominate the top 50. The full profiles do **not** show it: frozen container
      p99 is 89.9 and exp-001 `--repro` load-0 p99 was 85.1, so the 10 s warmup absorbs it and
      the quick profile's 2–3 s does not.

      So a quick run is not merely under-sampled — its first arm's tail is *biased*. The
      experiment-methodology skill already rules quick numbers unreportable; this is why, and it
      is worth stating because the next person to eyeball a quick p99 will think something
      broke. **Not silently fixed**: lengthening the quick warmup changes what the profile
      measures, and the honest options (a throwaway priming probe before the measured window, a
      longer warmup, or just a louder caveat) are a methodology decision, not a script tweak.

- [x] **CPU governor is pinned, not just recorded** — `run-exp-001/002/002b/003.sh` now call
      `pin_cpu_governor_performance` from `scripts/lib/host_pinning.sh` and restore it in their
      cleanup traps, as `run-exp-010.sh` already did. Every earlier campaign only *wrote*
      `cpu_governor` into results metadata and ran on whatever the host happened to be set to.
      That is how the first workspace-path rerun of exp-001 came out 10–20 µs higher at every
      load point: the host had moved to `powersave` since July, and nothing noticed.

- [ ] **exp-001's frozen directory holds the *repro-check* archives, not the original
      campaign's.** `results/exp-001/exp-001-summary.md` records the 2026-07-10 campaign
      (load-0 p99 **77.3 µs**, the figure `PUBLICATION.md` and `STATUS.md` cite), but the `.zip`s
      beside it are the 2026-07-13 second-campaign check (**70.6 µs**), whose own summary is
      committed as `exp-001-repro-check-2026-07-13.md`. Both records are correct and internally
      consistent; they describe different runs, and the original's archives were overwritten in
      place before `lib/results_dir.sh` existed to prevent exactly that.

      Consequence: `python3 notebooks/analyze_exp001.py results/exp-001` silently reports the
      *repro* numbers and **rewrites `exp-001-summary.md` with them** — the frozen record is one
      stray analysis run away from being replaced. Two things to decide: whether the published
      H1 baseline should be restated from surviving archives, and whether the analyzer should
      refuse to overwrite a summary whose recorded run doesn't match the archives it just read.
      Do not "fix" the summary by regenerating it: that would silently restate a published
      number.

- [ ] **exp-001 workspace-path equivalence is still open, and this run does not settle it.**
      2026-07-31 (workspace, kernel 7.0.0-28, powersave) gives load-0 p99 85.1 µs / load-600
      77.6 µs against the repro check's 70.6 / 67.0. Two host variables moved — governor and
      kernel — so the difference is not attributable to the schema path. The governor half is
      fixed above; the kernel cannot be un-upgraded, so a strict comparison against July's
      numbers is no longer available on this host. What the run *did* establish: the workspace
      path provisions and measures end to end, 25/25 archives, zero loss at every load level,
      and H1 holds at 0.91x (threshold 2.0x).

## Phase 3

- [ ] `vehicles/vx-vehicle-01.yaml` — full OEM-representative composition (six zones, QNX +
      AAOS guests, CAN edges, Kuksa signal plane, CARLA world)
- [ ] `exp-004` — freedom from interference (compute counterpart of exp-001): RTOS timing
      cell vs noisy neighbor under KVM static partitioning (rung 0); rerun per hypervisor
      ladder rung (Xen dom0less, QNX Hypervisor — phase 4)
- [ ] `exp-012` — HTB vs TSN (taprio/gPTP) slice isolation comparison on identical topology
- [ ] `exp-020` — V2X: two vehicle instances + RSU node, V2V/V2I flows over a dedicated slice.
      Candidate traffic source for V2V specifically (not a required dependency, not
      actionable until phase-2 completes and CARLA's single-vehicle closed loop lands):
      Waymax (https://github.com/waymo-research/waymax) — JAX-based, GPU-light multi-agent
      simulator, cheaper than N full CARLA instances for N simulated vehicles. Mirrored in
      `docs/TASKS.md` phase 3's V2X groundwork item
- [ ] End-to-end vehicle demo experiment referencing vx-vehicle-01
- [ ] Paper dataset freeze: tag manifests + digests used in submitted figures
