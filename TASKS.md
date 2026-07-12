# TASKS.md — vxedge/vxperiments

## Phase 1 (gate-defining — **PASSED 2026-07-13**: exp-001/exp-002-exp-002b/exp-003 deliver the H1/H3/H4 numbers)

- [x] Repo layout: `experiments/`, `notebooks/`, `results/README.md` (`vehicles/` with the
      phase-3 vehicle manifest)
- [x] `exp-001` — ADAS slice isolation (H1). Full campaign run 2026-07-10 (5 reps x 5 loads,
      60k samples/point, governor=performance): **H1 HOLDS — adas p99 0.93x baseline under
      600 mbit offered overload, zero loss**; load delivery verified (600.0 mbit, 0 errors);
      frozen summary committed (results/exp-001/exp-001-summary.md)
- [x] `exp-002` — virtualization packaging (H3). Full campaign 2026-07-11 (5 reps x 3 arms,
      60k samples/arm): **H3 HOLDS — packaging measurably affects RTT**: p50 container
      56.0 µs, libvirt +18.5, qemu-microvm +57.9 (p99: 95.0 / +27.8 / +69.2), zero loss;
      microvm (MMIO virtio) consistently slower than libvirt q35 (virtio-pci) — confirmed
      across all reps; frozen summary committed
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
- [ ] Reproducibility check: full second campaign of exp-001 and exp-003, medians within
      first campaign's IQRs *(exp-001's within-campaign consistency already strong: p99
      IQRs 3.9–6.5 µs across 5 fresh up/down cycles per load; exp-002b already has its
      second-campaign check done)*
- [ ] CI: manifest-validation on every PR (`vxedge manifest validate` over experiments/ and
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
- [ ] `exp-002` hardening: retrofit the same single-arm isolation the exp-002b incident
      forced (currently 3 arms run concurrently per rep; the frozen H3 result was clean
      but that was not guaranteed by the runner's design — verify or re-run isolated)
- [ ] `check_fresh()` (shared across run-exp-*.sh) does a whole-repo staleness check
      against each individual binary, which false-positives on multi-binary repos when
      only one binary's source changed (hit twice running exp-003: vxedge-core edits
      flagged the unrelated `vxedge` CLI binary; vxota-probe edits flagged the unrelated
      `vxota` server binary — neither actually depends on the changed file, confirmed by
      `cargo build --workspace` correctly relinking only the binary that did). Low
      priority — the gate errs safe (blocks on stale-looking code, never measures with
      genuinely stale code), the workaround is a documented `touch`; a real fix needs
      per-binary dependency-graph awareness, not just a repo-wide file scan.
- [ ] Manifest schema has no arm-conditional `telemetry.prometheus.scrape_targets` — hit
      by exp-003, whose `baseline` arm has nothing listening on the OTA burst driver's
      exporter port by design, dragging aggregate vxtelemetry completeness to ~50% (fully
      explained, not real data loss; the adas-relevant target was 100% complete). Low
      priority (the analyzer already explains it), but worth fixing before the pattern is
      copied into a future experiment where it could mask a real completeness problem.
- [ ] `exp-010` — H2: identical topology, `mode: vlan` vs `mode: s-nssai` slices compared
- [ ] `exp-011` — real ADAS traffic: CARLA → ROS2 → Autoware through the adas slice
- [ ] `exp-013` — closed-loop control latency under slice contention (world → sensors →
      slices → AD stack → actuation → world), with/without infotainment load
- [ ] `exp-014` — harness topology as variable: star vs daisy-chained zones under identical
      load (per-link `impairments`, BASE-T1 emulation)
- [ ] Determinism-controls ablation: PREEMPT_RT / pinning / VPP on-off matrix

## Phase 3

- [ ] `vehicles/vx-vehicle-01.yaml` — full OEM-representative composition (six zones, QNX +
      AAOS guests, CAN edges, Kuksa signal plane, CARLA world)
- [ ] `exp-004` — freedom from interference (compute counterpart of exp-001): RTOS timing
      cell vs noisy neighbor under KVM static partitioning (rung 0); rerun per hypervisor
      ladder rung (Xen dom0less, QNX Hypervisor — phase 4)
- [ ] `exp-012` — HTB vs TSN (taprio/gPTP) slice isolation comparison on identical topology
- [ ] `exp-020` — V2X: two vehicle instances + RSU node, V2V/V2I flows over a dedicated slice
- [ ] End-to-end vehicle demo experiment referencing vx-vehicle-01
- [ ] Paper dataset freeze: tag manifests + digests used in submitted figures
