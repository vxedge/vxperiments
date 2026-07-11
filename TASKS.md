# TASKS.md — vxedge/vxperiments

## Phase 1 (gate-defining: exp-001 produces the H1/H3/H4 numbers)

- [x] Repo layout: `experiments/`, `notebooks/`, `results/README.md` (`vehicles/` with the
      phase-3 vehicle manifest)
- [x] `exp-001` — ADAS slice isolation (H1). Full campaign run 2026-07-10 (5 reps x 5 loads,
      60k samples/point, governor=performance): **H1 HOLDS — adas p99 0.93x baseline under
      600 mbit offered overload, zero loss**; load delivery verified (600.0 mbit, 0 errors);
      frozen summary committed (results/exp-001/exp-001-summary.md)
- [ ] `exp-002` — virtualization packaging (H3) *(kit done 2026-07-11: manifest validated,
      3-arm runner + analyzer pushed; REMAINING: privileged campaign — --quick first, it is
      also the first live exercise of the microvm/libvirt backends)*
- [ ] `exp-003` — OTA co-location (H4): OTA burst during ADAS load, SLA delta *(needs vxota v1)*
- [ ] Baseline notebook: parse collect archives → percentile tables + isolation charts + CSV
- [ ] Reproducibility check: full second campaign of exp-001, medians within first
      campaign's IQRs *(within-campaign consistency already strong: p99 IQRs 3.9–6.5 µs
      across 5 fresh up/down cycles per load)*
- [ ] CI: manifest-validation on every PR (`vxedge manifest validate` over experiments/ and
      vehicles/) — phase 2, once the CLI subcommand exists
- [ ] CI: workflow_dispatch pipeline re-running exp-001 end-to-end and diffing distributions
      (§13 on-demand reproduction; needs KVM-capable runner) — phase 2

## Phase 2

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
