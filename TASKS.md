# TASKS.md — vxedge/vxperiments

## Phase 1 (gate-defining: exp-001 produces the H1/H3/H4 numbers)

- [ ] Repo layout: `experiments/`, `vehicles/`, `notebooks/`, `results/README.md`
- [ ] `exp-001` — ADAS slice isolation (H1): adas vs infotainment slices, synthetic load
      sweep, per-slice p50/p95/p99 targets (§16 worked example as starting point)
- [ ] `exp-002` — virtualization packaging (H3): same flow measured across libvirt VM vs
      container vs qemu-microvm node backends
- [ ] `exp-003` — OTA co-location (H4): OTA burst during ADAS load, SLA delta *(needs vxota v1)*
- [ ] Baseline notebook: parse collect archives → percentile tables + isolation charts + CSV
- [ ] Reproducibility check: rerun exp-001 twice, diff result distributions

## Phase 2

- [ ] `exp-010` — H2: identical topology, `mode: vlan` vs `mode: s-nssai` slices compared
- [ ] `exp-011` — real ADAS traffic: CARLA → ROS2 → Autoware through the adas slice
- [ ] Determinism-controls ablation: PREEMPT_RT / pinning / VPP on-off matrix

## Phase 3

- [ ] `vehicles/vx-vehicle-01.yaml` — full OEM-representative composition (six zones, QNX +
      AAOS guests, CAN edges, Kuksa signal plane, CARLA world)
- [ ] `exp-012` — HTB vs TSN (taprio/gPTP) slice isolation comparison on identical topology
- [ ] End-to-end vehicle demo experiment referencing vx-vehicle-01
- [ ] Paper dataset freeze: tag manifests + digests used in submitted figures
