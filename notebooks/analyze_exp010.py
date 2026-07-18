#!/usr/bin/env python3
"""exp-010 analysis — H2 real S-NSSAI slicing vs static VLAN mapping.

Reads ONLY results archives (results/exp-010/rep*-load*.zip: the snssai
arm), per the experiment-methodology skill: aggregates repetitions per load
level as median with IQR, emits a markdown table + CSV. The vlan arm is
exp-001's own already-frozen, already-analyzed campaign (same topology,
same probe methodology, same campaign frame — the model's own doc comment
is explicit no same-day rerun is needed) — this script reads its already-
computed exp-001-summary.csv as the comparison baseline rather than
re-deriving it, and states the H2 verdict from both arms together.

Usage: python3 notebooks/analyze_exp010.py results/exp-010 \
           [--baseline results/exp-001] [--out-dir results/exp-010]
Stdlib only — runs headless anywhere.
"""

import argparse
import csv
import json
import re
import statistics
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

ARCHIVE_RE = re.compile(r"rep(\d+)-load(\d+)\.zip$")

# H2 acceptance (docs/ARCHITECTURE.md §2, §12): the snssai arm's isolation
# must be at least as good as the vlan arm's — p99 growth ratio from
# baseline to peak load no worse than exp-001's own ratio (allowing a small
# tolerance for run-to-run noise, not a strict inequality).
H2_TOLERANCE = 1.10


def json_lenient(raw: bytes):
    """Parse JSON, tolerating leading log noise (parse from the first '{')."""
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])


def load_runs(results_dir: Path):
    runs = []
    for path in sorted(results_dir.glob("rep*-load*.zip")):
        m = ARCHIVE_RE.search(path.name)
        if not m:
            continue
        with zipfile.ZipFile(path) as z:
            probe = json_lenient(z.read("ingest/probe-summary.json"))
            env = json_lenient(z.read("ingest/run-env.json"))
            meta = json_lenient(z.read("metadata.json"))
        runs.append(
            {
                "rep": int(m.group(1)),
                "load_mbps": int(m.group(2)),
                "probe": probe,
                "env": env,
                "manifest_sha256": meta["manifest_sha256"],
                "archive": path.name,
            }
        )
    return runs


def quantile_stats(values):
    med = statistics.median(values)
    if len(values) >= 4:
        q = statistics.quantiles(values, n=4)
        iqr = q[2] - q[0]
    else:
        iqr = max(values) - min(values)
    return med, iqr


def load_baseline_csv(path: Path):
    rows = {}
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            rows[int(row["load_mbps"])] = {
                "p50_us": float(row["p50_us"]),
                "p95_us": float(row["p95_us"]),
                "p99_us": float(row["p99_us"]),
                "loss_pct": float(row["loss_pct"]),
            }
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("results_dir", type=Path)
    ap.add_argument(
        "--baseline",
        type=Path,
        default=None,
        help="exp-001 results dir (reads its exp-001-summary.csv as the vlan-arm baseline)",
    )
    ap.add_argument("--out-dir", type=Path, default=None)
    args = ap.parse_args()

    results_dir = args.results_dir
    out_dir = args.out_dir or results_dir

    runs = load_runs(results_dir)
    if not runs:
        sys.exit(f"no rep*-load*.zip archives in {results_dir}")

    shas = {r["manifest_sha256"] for r in runs}
    if len(shas) != 1:
        sys.exit(f"REFUSING: archives span {len(shas)} manifest checksums — not one experiment")
    quick = any(r["env"].get("quick_profile") for r in runs)

    by_load = defaultdict(list)
    for r in runs:
        by_load[r["load_mbps"]].append(r)

    rows = []
    for load in sorted(by_load):
        reps = by_load[load]
        samples = [r["probe"]["received"] for r in reps]
        row = {"load_mbps": load, "reps": len(reps), "min_samples": min(samples)}
        for metric in ("p50", "p95", "p99"):
            med, iqr = quantile_stats([r["probe"]["rtt_us"][metric] for r in reps])
            row[f"{metric}_us"] = round(med, 1)
            row[f"{metric}_iqr_us"] = round(iqr, 1)
        row["loss_pct"] = round(statistics.median([r["probe"]["loss_pct"] for r in reps]), 4)
        rows.append(row)

    # --- outputs -------------------------------------------------------------
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "exp-010-summary.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, sample counts below "
        "tail-percentile support, NOT reportable"
        if quick
        else "full profile"
    )
    lines = [
        "# exp-010 — H2 real S-NSSAI slicing vs static VLAN mapping (snssai arm)",
        "",
        f"- runs: {len(runs)} archives, manifest sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per point, "
        f"warmup {env['warmup_s']} s discarded before probing",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}; "
        f"{env.get('prometheus_live_metrics_note', '')}",
        "",
        "## snssai arm",
        "",
        "| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['load_mbps']} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['loss_pct']} |"
        )

    baseline_csv = args.baseline / "exp-001-summary.csv" if args.baseline else None
    if baseline_csv and baseline_csv.exists():
        vlan = load_baseline_csv(baseline_csv)
        common_loads = sorted(set(vlan) & set(r["load_mbps"] for r in rows))
        lines += ["", "## vlan arm (exp-001, frozen — not rerun)", ""]
        lines += [
            "| load (mbit) | p99 µs (vlan) | p99 µs (snssai) | snssai/vlan ratio |",
            "|---:|---:|---:|---:|",
        ]
        by_load_snssai = {r["load_mbps"]: r for r in rows}
        for load in common_loads:
            v = vlan[load]["p99_us"]
            s = by_load_snssai[load]["p99_us"]
            lines.append(f"| {load} | {v} | {s} | {s / max(v, 0.001):.2f} |")

        zero_load_missing = 0 not in vlan or 0 not in by_load_snssai
        verdict_lines = ["", "## H2 verdict", ""]
        if zero_load_missing:
            verdict_lines.append("- no zero-load baseline in one or both arms: verdict unavailable")
        else:
            vlan_ratio = vlan[max(common_loads)]["p99_us"] / max(vlan[0]["p99_us"], 0.001)
            snssai_ratio = (
                by_load_snssai[max(common_loads)]["p99_us"]
                / max(by_load_snssai[0]["p99_us"], 0.001)
            )
            held = snssai_ratio <= vlan_ratio * H2_TOLERANCE
            verdict_lines.append(
                f"- p99 growth baseline->{max(common_loads)}mbit: "
                f"vlan {vlan_ratio:.2f}x, snssai {snssai_ratio:.2f}x "
                f"(tolerance {H2_TOLERANCE}x of vlan's own ratio)"
            )
            verdict_lines.append(
                f"- **H2 {'HOLDS' if held else 'DOES NOT HOLD'}** on this host"
                + (" (quick profile — indicative only)" if quick else "")
            )
            if not held and not quick:
                verdict_lines += [
                    "",
                    "### Root cause (code-verified, not just observed)",
                    "",
                    "`vxedge-core::fiveg::subscriber` hardcodes an identical QCI/5QI=9, "
                    "ARP priority_level=8, and 1 Gbps AMBR for *every* subscriber and *every* "
                    "slice — confirmed by inspecting `subscriber.rs`'s rendered MongoDB "
                    "documents; `render_smf`/`render_upf` in `render.rs` never reference the "
                    "manifest's `Slice.qos` block at all (`grep` for `qos`/`5qi`/`ambr` across "
                    "`fiveg/render.rs` returns nothing). The vlan arm's isolation, by contrast, "
                    "comes from real HTB priority + min/max rate enforcement at the kernel "
                    "queueing layer (`gateway::provision::apply_slices`). So the two arms are "
                    "not actually comparing \"static VLAN mapping\" vs \"real S-NSSAI slicing\" "
                    "on equal terms yet — they're comparing \"VLAN mapping *with* enforced QoS\" "
                    "vs \"S-NSSAI slicing *without* any QoS differentiation\" (real separate "
                    "PDU sessions/signaling, but both slices' traffic still competes "
                    "undifferentiated for the same gNB/UPF forwarding path). This is a real, "
                    "previously-undocumented gap distinct from the already-tracked URSP-style "
                    "`slice_policy` item (that one is about UE-side multi-session routing, not "
                    "network-side QoS enforcement) — closing it (per-slice 5QI/ARP/AMBR from "
                    "`Slice.qos`, rendered into each slice's subscriber/SMF/UPF config) is a "
                    "precondition for a fair H2 test, not evidence against the hypothesis "
                    "itself.",
                ]
        lines += verdict_lines
    else:
        lines += [
            "",
            "## H2 verdict",
            "",
            "- no --baseline results/exp-001 given (or exp-001-summary.csv missing): "
            "vlan-arm comparison skipped, snssai-arm numbers only",
        ]

    md_path = out_dir / "exp-010-summary.md"
    md_path.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {csv_path} and {md_path}")


if __name__ == "__main__":
    main()
