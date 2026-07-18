# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)

- runs: 25 archives, manifest sha256 `d8a988e51543…`
- probe: 1000 pps x 60 s per point, warmup 10 s discarded before probing
- host: kernel 6.17.0-35-generic, PREEMPT_RT=False, governor=powersave, timestamping: userspace-monotonic (SO_TIMESTAMPING follow-up open)
- caveats: shared-host gateway; full profile; TrafficService's spawned vxprobe send does not expose --metrics yet; only the final aggregate probe-summary.json is captured (that is all analyze_exp010.py reads)

## snssai arm

| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5 | 60000 | 262.7 (9.7) | 298.8 (27.3) | 329.2 (41.3) | 0.0 |
| 100 | 5 | 60000 | 279.0 (7.9) | 315.4 (32.4) | 341.8 (51.5) | 0.0 |
| 250 | 5 | 60000 | 281.9 (8.1) | 329.7 (21.1) | 360.4 (34.8) | 0.0 |
| 400 | 5 | 59998 | 302.1 (4.4) | 361.0 (7.8) | 395.5 (15.9) | 0.0 |
| 600 | 5 | 59999 | 282.9 (5.8) | 346.4 (22.3) | 410.9 (62.7) | 0.0 |

## vlan arm (exp-001, frozen — not rerun)

| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |
|---:|---:|---:|---:|
| 0 | 77.3 | 329.2 | 4.26 |
| 100 | 74.5 | 341.8 | 4.59 |
| 250 | 72.1 | 360.4 | 5.00 |
| 400 | 72.0 | 395.5 | 5.49 |
| 600 | 71.7 | 410.9 | 5.73 |

## H2 verdict

- p99 growth baseline->600mbit: vlan 0.93x, snssai 1.25x (tolerance 1.1x of vlan's own ratio)
- **H2 DOES NOT HOLD** on this host

### Root cause (code-verified, not just observed)

`vxedge-core::fiveg::subscriber` hardcodes an identical QCI/5QI=9, ARP priority_level=8, and 1 Gbps AMBR for *every* subscriber and *every* slice — confirmed by inspecting `subscriber.rs`'s rendered MongoDB documents; `render_smf`/`render_upf` in `render.rs` never reference the manifest's `Slice.qos` block at all (`grep` for `qos`/`5qi`/`ambr` across `fiveg/render.rs` returns nothing). The vlan arm's isolation, by contrast, comes from real HTB priority + min/max rate enforcement at the kernel queueing layer (`gateway::provision::apply_slices`). So the two arms are not actually comparing "static VLAN mapping" vs "real S-NSSAI slicing" on equal terms yet — they're comparing "VLAN mapping *with* enforced QoS" vs "S-NSSAI slicing *without* any QoS differentiation" (real separate PDU sessions/signaling, but both slices' traffic still competes undifferentiated for the same gNB/UPF forwarding path). This is a real, previously-undocumented gap distinct from the already-tracked URSP-style `slice_policy` item (that one is about UE-side multi-session routing, not network-side QoS enforcement) — closing it (per-slice 5QI/ARP/AMBR from `Slice.qos`, rendered into each slice's subscriber/SMF/UPF config) is a precondition for a fair H2 test, not evidence against the hypothesis itself.
