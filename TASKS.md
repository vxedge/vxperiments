# TASKS.md — vxedge/vxperiments

## Phase 1 (gate-defining: exp-001 produces the H1/H3/H4 numbers)

- [x] Repo layout: `experiments/`, `notebooks/`, `results/README.md` (`vehicles/` with the
      phase-3 vehicle manifest)
- [ ] `exp-001` — ADAS slice isolation (H1) *(kit done 2026-07-10: manifest validated via
      vxedged, campaign runner with methodology discipline, archive-only analyzer verified
      on synthetic archives; REMAINING: privileged campaign run on the dev host + frozen
      summary + reproducibility check)*
- [ ] `exp-002` — virtualization packaging (H3): same flow measured across libvirt VM vs
      container vs qemu-microvm node backends
- [ ] `exp-003` — OTA co-location (H4): OTA burst during ADAS load, SLA delta *(needs vxota v1)*
- [ ] Baseline notebook: parse collect archives → percentile tables + isolation charts + CSV
- [ ] Reproducibility check: rerun exp-001 twice, diff result distributions
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
- [ ] `exp-012` — HTB vs TSN (taprio/gPTP) slice isolation comparison on identical topology
- [ ] `exp-020` — V2X: two vehicle instances + RSU node, V2V/V2I flows over a dedicated slice
- [ ] End-to-end vehicle demo experiment referencing vx-vehicle-01
- [ ] Paper dataset freeze: tag manifests + digests used in submitted figures
