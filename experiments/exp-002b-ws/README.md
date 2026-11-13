# exp-002b

## The package

This folder is the `vxp/1` package `vxedge/exp-002b`, version 0.2.1 (`vxp.yaml`). Its catalogue
alias is `exp-002b`. `vxp.lock` records the digest of every file it holds and the guest bundle it
pins.

exp-002 shows *that* packaging costs latency. exp-002b separates the effect into its mechanisms,
one per pair of arms, and records what each arm costs the host:

| Decomposition | Arms | What differs |
|---|---|---|
| transport | `microvm-pci` vs `microvm-mmio` | virtio PCI vs MMIO, on the microvm machine |
| machine | `q35-pci` vs `microvm-pci` | q35 vs microvm, with a virtio-pci NIC |
| vhost-net | `q35-vhost` vs `q35-pci` | vhost-net on vs off, on q35 with virtio-pci |
| management | `libvirt-q35` vs `q35-pci` | libvirt vs raw QEMU, on q35 with virtio-pci |

`main.yaml` holds the experiment and what used to live in
[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.0/experiments/exp-002b-ws/scripts/run.sh) and
[`notebooks/criteria/exp-002b.yaml`](https://github.com/vxedge/vxperiments/blob/v0.2.0/notebooks/criteria/exp-002b.yaml):

| What | Where it was | Where it is |
|---|---|---|
| Six arms, one up at a time | `ARMS`, `DEVICE_OF`, `zone up --vxid` in `run.sh` | `campaign.arms`, through `arm_device`, which binds `isolate` |
| Three arms on QEMU flags the runner chose | `launch_qemu` in `run.sh`, on taps the gateway made | each device's `qemu:` block in `vehicle.yaml` (vxedge 0.25.0) |
| The probe from the host to each arm at 1000 pps | `vxprobe send` from the host on `vxup0p.101` | `measurements.probe` (`from: host`), through `arm_target` and `probe_pps` |
| Waiting for a VM arm's reflector | `wait_reflector` in `run.sh` | the measurement, which waits for its reflector to answer |
| Each arm's CPU and memory | `vxtelemetry sample` on a command-line match | `cpu_<arm>` and `rss_<arm>`, read from the daemon's exporter |
| 5 repetitions, 10 s warmup, then a 60 s probe window | `REPS`, `WARM_S`, `PROBE_S` in `run.sh` | `campaign.repetitions`, `warmup_s`, `duration_s`, and the `repro` profile |
| The four decompositions and their 1 % loss guards | `exp-002b.yaml` | `metrics` and `criteria` |

The five VM arms boot the published guest bundle `zone/linux/stack/probe-bundle` 0.1.2, pinned by
digest in `parts.yaml`. Its part declares the UDP reflector its guest runs on port 9800, so the
measurement aims at it and starts nothing in the guest, and that its kernel drives a virtio-net on
PCI, which the three `transport: pci` arms need. Run it through vxAPI, from inside this folder:

```bash
vxedge campaign plan --profile repro     # the 30 trials; touches nothing
vxedge campaign start --profile repro    # one archive per trial, then the verdict
```

The `quick` profile checks the pipeline only and is never reported: one repetition with
`run.sh --quick`'s 2 s and 10 s windows, at 1000 pps (`run.sh --quick` probed at 500).

The host needs KVM for the VM arms and `/dev/vhost-net` open to vxedged's user for `q35-vhost`
(the `kvm` group on most hosts). The libvirt arm needs vxedged's user in the `libvirt` group, with
the part cache readable by libvirt's qemu user (see `ARCHITECTURE.md` §9).

### The verdict

Each decomposition passes when the two arms' median p50s differ by more than the larger of their
IQRs, at least 1 µs, and is inconclusive when either arm lost more than 1 % of its probes in any
repetition. Each criterion tests one mechanism:

- `transport`: virtio PCI moves the median RTT against MMIO, on the microvm machine;
- `machine`: q35 moves it against microvm, with a virtio-pci NIC;
- `vhost-net`: vhost-net on moves it against off, on q35 with virtio-pci;
- `management`: libvirt moves it against raw QEMU, on q35 with virtio-pci.

The package declares no hypothesis: it decomposes exp-002's H3, and its criteria are read one by
one, not as one claim. `machine` is the expected negative. On the published campaigns q35 and
microvm differ by less than their IQR, "no measurable effect" as published, so its outcome is
`fail`, and the campaign's overall outcome is `fail` with it.

Verdict parity: the published exp-002b archives (`exp-002b.tgz`,
`exp-002b-repro-2026-08-05.tgz`) give `transport=pass machine=fail vhost-net=pass
management=pass` through this package, the notebook's verdicts (`../../scripts/verdict-parity.sh`).

### Cost per arm

`cpu_<arm>` is the share of one CPU the arm's node used over the probe window (`rate` of
`vxedge_node_cpu_seconds_total`), and `rss_<arm>` its mean resident memory (`mean` of
`vxedge_node_memory_bytes`). The daemon's exporter reads a VM arm's QEMU process and, for the
container arm, the processes in its namespace: the reflector. They are reported, not judged. A
metric names one entity, so there is a pair per arm, and in a trial only the isolated arm's pair
has a value.

The frozen archives cannot give these: they carry `resource-samples.jsonl` from `vxtelemetry
sample`, and the exporter series did not exist yet, so offline both are empty for every trial.
The published CPU and RSS figures stay the notebook's, from those samples.

### What differs from the frozen campaigns

Every VM arm still has 1 vCPU and 128 MiB, and the four raw-QEMU arms run `-cpu host` under KVM
on the machine and NIC `run.sh` gave them (`q35`, `microvm,pcie=on` with ACPI, `virtio-net-pci`,
`vhost=on`). Three things are not as they were:

- **`microvm-mmio` speaks virtio-mmio version 2.** vxedge passes
  `-global virtio-mmio.force-legacy=false` since 0.6.0; the frozen runs used QEMU's default, the
  legacy transport. This is the transport decomposition's MMIO side.
- **`libvirt-q35` has the host CPU and ACPI.** The domain carries `<cpu mode='host-passthrough'/>`
  (since vxedge 0.6.1) and `<features><acpi/><apic/></features>` (since 0.13.0); the frozen domain
  had libvirt's default CPU model and neither feature.
- **The CPU governor is not pinned.** `run.sh` set `performance` for the campaign; the package
  leaves host preparation to the host.

A rerun is a new campaign, compared with the frozen one, not a reproduction of it.

## Before the package

`scripts/run.sh` brought the gateway up, put `10.101.0.1/24` on the uplink's VLAN by hand, then
brought each arm up alone and probed it from the host. Three arms (`q35-pci`, `q35-vhost`,
`microvm-pci`) were declared but never brought up by vxedge: the runner launched QEMU itself on
their taps with each arm's machine, transport and vhost flags. vxedge 0.25.0's `qemu:` block made
those three ordinary devices, so the package brings every arm up the same way.

## Structure

| File | `kind` | What it owns |
|---|---|---|
| `vxp.yaml` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the test: slice + QoS, the probe, the arms, the cost metrics, the decompositions |
| `vehicle.yaml` | `vehicle` | the system under test: six packagings of one ECU, their QEMU options and addresses |
| `parts.yaml` | `baseline` | the identical payload every arm carries |

Device ids are the frozen manifest's node ids so the two forms stay diffable, and so the
recorded results keep naming the same things.
