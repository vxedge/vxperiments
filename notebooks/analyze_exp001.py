#!/usr/bin/env python3
"""exp-001 analysis — ADAS slice isolation under infotainment load (H1).

Reads ONLY results archives (results/exp-001/rep*-load*.zip), per the
experiment-methodology skill: aggregates repetitions per load level as
median with IQR, emits a markdown table + CSV, and states the H1 verdict.

Usage: python3 notebooks/analyze_exp001.py results/exp-001 [--out-dir results/exp-001]
Stdlib only — runs headless anywhere.
"""

import csv
import json
import re
import statistics
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

ARCHIVE_RE = re.compile(r"rep(\d+)-load(\d+)\.zip$")

# H1 acceptance: adas p99 under max load stays within this factor of baseline.
H1_P99_FACTOR = 2.0


def load_runs(results_dir: Path):
    runs = []
    for path in sorted(results_dir.glob("rep*-load*.zip")):
        m = ARCHIVE_RE.search(path.name)
        if not m:
            continue
        with zipfile.ZipFile(path) as z:
            probe = json.loads(z.read("ingest/probe-summary.json"))
            env = json.loads(z.read("ingest/run-env.json"))
            meta = json.loads(z.read("metadata.json"))
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


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    results_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else results_dir

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
        row["loss_pct"] = round(
            statistics.median([r["probe"]["loss_pct"] for r in reps]), 4
        )
        rows.append(row)

    # --- outputs -------------------------------------------------------------
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "exp-001-summary.csv"
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
        "# exp-001 — ADAS slice isolation under infotainment load (H1)",
        "",
        f"- runs: {len(runs)} archives, manifest sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per point, "
        f"warmup {env['warmup_s']} s discarded before probing",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}",
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

    baseline = rows[0]
    peak = rows[-1]
    verdict_lines = ["", "## H1 verdict", ""]
    if baseline["load_mbps"] != 0:
        verdict_lines.append("- no zero-load baseline present: verdict unavailable")
    else:
        ratio = peak["p99_us"] / max(baseline["p99_us"], 0.001)
        held = ratio <= H1_P99_FACTOR and peak["loss_pct"] <= baseline["loss_pct"] + 0.5
        verdict_lines.append(
            f"- adas p99 at max load ({peak['load_mbps']} mbit): {peak['p99_us']} µs = "
            f"{ratio:.2f}x baseline ({baseline['p99_us']} µs); "
            f"threshold {H1_P99_FACTOR}x"
        )
        verdict_lines.append(
            f"- **H1 {'HOLDS' if held else 'DOES NOT HOLD'}** on this host"
            + (" (quick profile — indicative only)" if quick else "")
        )
    lines += verdict_lines

    md_path = out_dir / "exp-001-summary.md"
    md_path.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {csv_path} and {md_path}")


if __name__ == "__main__":
    main()
