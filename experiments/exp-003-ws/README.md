# exp-003

## The package

This folder is the `vxp/1` package `vxedge/exp-003`, version 0.2.1 (`vxp.yaml`). Its catalogue
alias is `exp-003`. `vxp.lock` records the digest of every file it holds.

`main.yaml` holds the experiment and what used to live in
[`scripts/run.sh`](https://github.com/vxedge/vxperiments/blob/v0.2.0/experiments/exp-003-ws/scripts/run.sh) and
[`notebooks/criteria/exp-003.yaml`](https://github.com/vxedge/vxperiments/blob/v0.2.0/notebooks/criteria/exp-003.yaml):

| What | Where it was | Where it is |
|---|---|---|
| Two arms: baseline (OTA server idle) and ota-burst | `ARMS` in `run.sh` | `campaign.arms`, through `ota_clients` |
| A signed store with a random burst artifact | `vxota keygen` once per host, `dd` and `vxota publish` per run | `services.ota.config.publish`, signed afresh at every start |
| The burst: one client downloading the artifact back to back | `vxota-probe fetch --repeat 999999 --interval-s 0`, started by hand | `services.ota.config.fetch`, whose `clients` `ota_clients` binds |
| The probe from node-adas-probe-01 across the adas VLAN at 1000 pps | `ip netns exec … vxprobe send`, the reflector on `vxup0p.101` by hand | `measurements.probe`, through `probe_pps` |
| 5 repetitions, 10 s warmup, then a 60 s probe window | `REPS`, `WARM_S`, `PROBE_S` in `run.sh` | `campaign.repetitions`, `warmup_s`, `duration_s`, and the `repro` profile |
| H4: the burst raises the median p50 by no more than the larger IQR, at least 1 µs, loss at most 1 % | the notebook's verdict | `hypothesis`, `metrics` and `criteria` |

Run it through vxAPI, from inside this folder. vxedged runs the OTA server and client from
`--vxota-bin` and `--vxota-probe-bin` (vxota 0.1.1 or later):

```bash
vxedge campaign plan --profile repro     # the 10 trials; touches nothing
vxedge campaign start --profile repro    # one archive per trial, then H4's verdict
```

The `quick` profile checks the pipeline only and is never reported: one repetition with
`run.sh --quick`'s 2 s and 10 s windows, at 1000 pps and with the 5 MB artifact (`run.sh --quick`
probed at 500 with 1 MB).

The burst client's counters (`deliveries`, `failed_deliveries`) are archived on the OTA service's
entity and reported with the verdict, not judged: the frozen campaigns recorded them on another
entity. The client starts once the server answers, during provisioning, so the burst covers the
whole warmup and measure window, as `run.sh` started it before the warmup.

Verdict parity: the published exp-003 archives (`exp-003.tgz`, `exp-003-repro-2026-08-03.tgz`,
`exp-003-repro-2026-10-30.tgz`) give the notebook's H4 verdict through this package
(`../../scripts/verdict-parity.sh`).

## Before the package

`scripts/run.sh` brought the gateway and the OTA service up, then node-adas-probe-01, put the
reflector's address on the uplink's VLAN by hand, and started the burst client itself for the
ota-burst arm. Its store was signed once per host under `/tmp` with a key kept beside it. The
package does the same through vxAPI, with a store and key made per run in the daemon's runtime
folder (vxedge 0.23.0).

## Structure

| File | `kind` | What it owns |
|---|---|---|
| `vxp.yaml` | — | identity, version, entry point, host requirements |
| `main.yaml` | `experiment` | slices, the probe, the OTA service, parameters, metrics, criteria, campaign |
| `car1.yaml` | `vehicle` | the system under test: one zone, the probe's device and its link |
| `parts.yaml` | `baseline` | which software, by ref + digest |
