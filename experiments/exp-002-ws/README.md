# exp-002

## The package

This folder is the `vxp/1` package `vxedge/exp-002`, version 0.2.1 (`vxp.yaml`). Its catalogue
alias is `exp-002`. `vxp.lock` records the digest of every file it holds and the guest bundle it
pins.

`main.yaml` holds the experiment and what used to live in
[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.1/experiments/exp-002-ws/scripts/run.sh) and
[`notebooks/analyze_exp002.py`](https://github.com/vxedge/vxperiments/blob/v0.2.1/notebooks/analyze_exp002.py):

| What | Where it was | Where it is |
|---|---|---|
| Three arms: container, microVM, full VM, one up at a time | `ARMS`, `DEVICE_OF`, `zone up --vxid` in `run.sh` | `campaign.arms`, through `arm_device`, which binds `isolate` |
| The probe from the host to each arm at 1000 pps | `vxprobe send` from the host on `vxup0p.101` | `measurements.probe` (`from: host`), through `arm_target` and `probe_pps` |
| Waiting for a VM arm's reflector | `wait_reflector` in `run.sh` | the measurement, which waits for its reflector to answer |
| 5 repetitions, 10 s warmup, then a 60 s probe window | `REPS`, `WARM_S`, `PROBE_S` in `run.sh` | `campaign.repetitions`, `warmup_s`, `duration_s`, and the `repro` profile |
| H3: some arm's median p50 outside the container arm's IQR, at least 1 µs | the notebook's verdict | `hypothesis`, `metrics` and `criteria` |

The VM arms boot the published guest bundle `zone/linux/stack/probe-bundle` 0.1.1, pinned by
digest in `parts.yaml`. Its part declares the UDP reflector its guest runs on port 9800, so the
measurement aims at it and starts nothing in the guest (vxedge 0.21.0). Run it through vxAPI, from
inside this folder:

```bash
vxedge campaign plan --profile repro     # the 15 trials; touches nothing
vxedge campaign start --profile repro    # one archive per trial, then H3's verdict
```

The `quick` profile checks the pipeline only and is never reported: one repetition with
`run.sh --quick`'s 2 s and 10 s windows, at 1000 pps (`run.sh --quick` probed at 500).

The host needs KVM for the VM arms, and the libvirt arm needs vxedged's user in the `libvirt`
group, with the part cache readable by libvirt's qemu user (see `ARCHITECTURE.md` §9).

Verdict parity: the published exp-002 archives (`exp-002.tgz`, `exp-002-repro-2026-08-05.tgz`)
give the notebook's H3 verdict through this package (`../../scripts/verdict-parity.sh`).

## Before the package

[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.1/experiments/exp-002-ws/scripts/run.sh)
was the bash runner the campaign replaced; vxperiments 0.2.1 is the last release that has it. It brought
the gateway up, put `10.101.0.1/24` on the uplink's VLAN by hand, then brought each arm's device up
alone and probed it from the host. The package does the same through vxAPI.

The workspace form needed two schema changes and two fixes before this:

- **Endpoint addresses.** The three arms share one VLAN and one subnet; the *address* is what
  tells them apart. Endpoints take an object form, `{ node: node-cont-01, port: eth0, ip:
  10.101.0.11/24 }`.
- **Interface names stopped being positional.** Names are derived from the device id
  (`vz-node-c-32cc` for `node-cont-01`), so order decides nothing.
- **A VM's guest bundle resolves through `deployed_on`**, not by function id equals device id.
- **One device up at a time.** `zone up --vxid` took a device id, which `run.sh` used to hold
  one arm up at a time. The package does it with `isolate`.

## Structure

| File | `kind` | What it owns |
|---|---|---|
| `vxp.yaml` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | the test: slice + QoS, the probe, the arms, H3 and its criteria |
| `vehicle.yaml` | `vehicle` | the system under test: three packagings of one ECU, and their addresses |
| `parts.yaml` | `baseline` | the identical payload each arm carries |

Device ids are the frozen manifest's node ids so the two forms stay diffable, and so the
recorded results keep naming the same things.
