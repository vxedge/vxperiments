# exp-010: H2, real S-NSSAI slicing against static VLAN mapping (live repro, 2026-11-13)

- campaign `c-43df99570994`, profile `repro`: 25 trials (5 repetitions of five loads), every
  trial complete; the archives' digests match `campaign.json`
- package `vxedge/exp-010` 0.2.1, digest `sha256:a377ff65c14ef732ec37ae70d33e27cf02aa535d47e35fdb0a42144753102ff1`, locked
- probe: 1000 pps for a 60 s window after 10 s of load, the UE end on the `adas` slice
- tools (release builds): vxedged 0.27.0, vxprobe 0.2.3, vxtraffic 0.2.3, vxtelemetry 0.8.0
- 5G images, from the archives' `image_digests`:
  - `docker.io/library/mongo:7@sha256:8bb4442761a63a8dda452744082cdac9644b429807eb977b42324a63cef59ca4`
  - `ghcr.io/vxedge/parts/gw/5gc/os/open5gs:0.1.0@sha256:dfad2271a85c7147669ed5a98cc4c61b113a915d95050ddbcfe25bdea55ac97d`
  - `ghcr.io/vxedge/parts/gw/ran/os/ueransim:0.1.0@sha256:39393bb1982f57f4c3b14ff743baea810868b089d7ceda633b85026817fe066a`
- host: kernel 7.0.0-43-generic, PREEMPT_RT=False, CPU governor performance;
  run folder outside the home directory, host lock held for the whole run (no load log was kept)
- caveats: shared-host gateway; the 5G core and RAN are Open5GS and UERANSIM in Podman pods on
  the same host

## snssai arm

All values in µs. Each value is the median over the 5 repetitions of that trial's quantile; the
IQR, in brackets, is the hinge IQR.

| load (Mbit/s) | reps | min sent | p50 (IQR) | p95 (IQR) | p99 (IQR) | max loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 59816 | 246.0 (8.1) | 275.5 (7.2) | 299.5 (9.5) | 0.0000 |
| 100 | 5 | 59790 | 237.3 (6.0) | 279.3 (5.4) | 303.6 (6.4) | 0.0000 |
| 250 | 5 | 59796 | 239.5 (7.6) | 293.6 (3.5) | 320.3 (5.8) | 0.0000 |
| 400 | 5 | 59798 | 240.3 (4.5) | 271.4 (3.8) | 291.3 (5.2) | 0.0000 |
| 600 | 5 | 59795 | 240.1 (5.7) | 273.2 (2.7) | 291.1 (4.7) | 0.0017 |

## H2 verdict: PASS

`campaign verdict` (vxedged 0.27.0) judges `h2`: the median p99 at 600 Mbit/s over the median
p99 at 0 Mbit/s, against 1.10 times the same ratio in exp-001's frozen VLAN campaign (Zenodo
2026-11-v2, `exp-001.tgz`).

| | p99 at 0 Mbit/s | p99 at 600 Mbit/s | growth |
|---|---:|---:|---:|
| snssai (this run) | 299.5 | 291.1 | 0.972x |
| vlan (exp-001, frozen) | 89.6 | 81.9 | 0.914x |

0.972 <= 1.006 (1.10 x 0.914): **H2 holds**. The published 2026-10-30
repro read 1.00x against the same bound. Absolute p99 here is about 300 µs, against about 340 µs in
that run, which used locally built images and the bash runner. This run does not establish the
cause of the difference; H2 compares growth, not the absolute level.
