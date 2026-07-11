#!/usr/bin/env python3
"""exp-002 analysis — packaging backend vs latency (H3).

Reads ONLY results archives (results/exp-002/rep*-<arm>.zip). Aggregates
repetitions per arm (median + IQR), reports deltas vs the container baseline,
and states the H3 verdict: does packaging measurably affect RTT?

Usage: python3 notebooks/analyze_exp002.py results/exp-002 [--out-dir DIR]
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

ARCHIVE_RE = re.compile(r"rep(\d+)-([a-z]+)\.zip$")
ARM_ORDER = ["container", "microvm", "libvirt"]


def json_lenient(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])


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

    runs = []
    for path in sorted(results_dir.glob("rep*-*.zip")):
        m = ARCHIVE_RE.search(path.name)
        if not m:
            continue
        with zipfile.ZipFile(path) as z:
            runs.append(
                {
                    "rep": int(m.group(1)),
                    "arm": m.group(2),
                    "probe": json_lenient(z.read("ingest/probe-summary.json")),
                    "env": json_lenient(z.read("ingest/run-env.json")),
                    "sha": json_lenient(z.read("metadata.json"))["manifest_sha256"],
                }
            )
    if not runs:
        sys.exit(f"no rep*-<arm>.zip archives in {results_dir}")
    shas = {r["sha"] for r in runs}
    if len(shas) != 1:
        sys.exit(f"REFUSING: archives span {len(shas)} manifest checksums")
    quick = any(r["env"].get("quick_profile") for r in runs)

    by_arm = defaultdict(list)
    for r in runs:
        by_arm[r["arm"]].append(r)

    rows = []
    for arm in [a for a in ARM_ORDER if a in by_arm] + sorted(set(by_arm) - set(ARM_ORDER)):
        reps = by_arm[arm]
        row = {
            "arm": arm,
            "reps": len(reps),
            "min_samples": min(r["probe"]["received"] for r in reps),
        }
        for metric in ("p50", "p95", "p99"):
            med, iqr = quantile_stats([r["probe"]["rtt_us"][metric] for r in reps])
            row[f"{metric}_us"] = round(med, 1)
            row[f"{metric}_iqr_us"] = round(iqr, 1)
        row["loss_pct"] = round(statistics.median([r["probe"]["loss_pct"] for r in reps]), 4)
        rows.append(row)

    baseline = next((r for r in rows if r["arm"] == "container"), rows[0])
    for r in rows:
        r["p50_vs_container"] = round(r["p50_us"] - baseline["p50_us"], 1)
        r["p99_vs_container"] = round(r["p99_us"] - baseline["p99_us"], 1)

    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "exp-002-summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, NOT reportable" if quick else "full profile"
    )
    lines = [
        "# exp-002 — packaging backend vs latency (H3)",
        "",
        f"- runs: {len(runs)} archives, manifest sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per arm, idle topology",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, KVM={env.get('kvm')}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}",
        "",
        "| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | Δp50 vs container | Δp99 vs container | loss % |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['arm']} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['p50_vs_container']:+} "
            f"| {r['p99_vs_container']:+} | {r['loss_pct']} |"
        )

    lines += ["", "## H3 verdict", ""]
    if len(rows) < 2:
        lines.append("- fewer than two arms present: verdict unavailable")
    else:
        # H3 holds if any arm's median p50 sits outside the container arm's IQR.
        distinguishable = [
            r["arm"]
            for r in rows
            if r["arm"] != baseline["arm"]
            and abs(r["p50_us"] - baseline["p50_us"]) > max(baseline["p50_iqr_us"], 1.0)
        ]
        if distinguishable:
            lines.append(
                f"- packaging measurably affects RTT: {', '.join(distinguishable)} differ from "
                f"container beyond its IQR — **H3 HOLDS**"
                + (" (quick profile — indicative only)" if quick else "")
            )
        else:
            lines.append(
                "- no arm distinguishable from container beyond IQR — **H3 DOES NOT HOLD** "
                "at this resolution"
                + (" (quick profile — indicative only)" if quick else "")
            )

    (out_dir / "exp-002-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {out_dir}/exp-002-summary.csv and {out_dir}/exp-002-summary.md")


if __name__ == "__main__":
    main()
