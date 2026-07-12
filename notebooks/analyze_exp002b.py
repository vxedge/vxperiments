#!/usr/bin/env python3
"""exp-002b analysis — H3 decomposition + per-arm resource cost.

Reads ONLY results archives (results/exp-002b/rep*-<arm>.zip). Aggregates
repetitions per arm (median + IQR) for latency and resource cost, then states
four pairwise decomposition verdicts:

  transport  = microvm-pci   vs microvm-mmio   (MMIO vs PCI, same machine)
  machine    = q35-pci       vs microvm-pci    (q35 vs microvm, same transport)
  vhost      = q35-vhost     vs q35-pci        (vhost-net on/off)
  management = libvirt-q35   vs q35-pci        (libvirt vs raw QEMU, same config)

Usage: python3 notebooks/analyze_exp002b.py results/exp-002b [--out-dir DIR]
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

ARCHIVE_RE = re.compile(r"rep(\d+)-([a-z0-9-]+)\.zip$")
ARM_ORDER = ["container", "microvm-mmio", "libvirt-q35", "q35-pci", "q35-vhost", "microvm-pci"]

# (label, arm_a, arm_b, question)
DECOMP = [
    ("transport (MMIO vs PCI)", "microvm-pci", "microvm-mmio", "does virtio transport matter?"),
    ("machine (q35 vs microvm)", "q35-pci", "microvm-pci", "does machine type matter, transport fixed?"),
    ("vhost-net (on vs off)", "q35-vhost", "q35-pci", "does vhost-net offload matter?"),
    ("management (libvirt vs raw QEMU)", "libvirt-q35", "q35-pci", "does libvirt add overhead vs raw QEMU?"),
]


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
            names = set(z.namelist())
            resource = None
            res_name = "ingest/resource-summary.json"
            if res_name in names:
                try:
                    resource = json_lenient(z.read(res_name))
                except (ValueError, KeyError):
                    resource = None
            runs.append(
                {
                    "rep": int(m.group(1)),
                    "arm": m.group(2),
                    "probe": json_lenient(z.read("ingest/probe-summary.json")),
                    "env": json_lenient(z.read("ingest/run-env.json")),
                    "resource": resource,
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

        cpu_vals, rss_vals = [], []
        for r in reps:
            res = r["resource"] or {}
            node = res.get("node")
            if node:
                cpu_vals.append(node["cpu_pct_mean"])
                rss_vals.append(node["rss_mb_mean"])
        row["cpu_pct_mean"] = round(statistics.median(cpu_vals), 2) if cpu_vals else None
        row["rss_mb_mean"] = round(statistics.median(rss_vals), 1) if rss_vals else None
        rows.append(row)

    by_arm_row = {r["arm"]: r for r in rows}

    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "exp-002b-summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, NOT reportable" if quick else "full profile"
    )
    lines = [
        "# exp-002b — H3 decomposition + resource cost",
        "",
        f"- runs: {len(runs)} archives, manifest sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per arm, idle topology",
        f"- host: kernel {env['kernel']}, KVM={env.get('kvm')}, governor={env['cpu_governor']}",
        f"- caveats: shared-host gateway; {profile_note}; resource sampling requires the arm's "
        "process to be matched by cmdline regex — 'cpu/rss: n/a' means no sample matched",
        "",
        "| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % | cpu % (mean) | rss MB (mean) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        cpu = r["cpu_pct_mean"] if r["cpu_pct_mean"] is not None else "n/a"
        rss = r["rss_mb_mean"] if r["rss_mb_mean"] is not None else "n/a"
        lines.append(
            f"| {r['arm']} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['loss_pct']} | {cpu} | {rss} |"
        )

    lines += ["", "## Decomposition verdicts", ""]
    for label, arm_a, arm_b, question in DECOMP:
        a, b = by_arm_row.get(arm_a), by_arm_row.get(arm_b)
        if not a or not b:
            lines.append(f"- **{label}**: missing arm(s), skipped ({question})")
            continue
        delta = round(a["p50_us"] - b["p50_us"], 1)
        threshold = max(a["p50_iqr_us"], b["p50_iqr_us"], 1.0)
        holds = abs(delta) > threshold
        verdict = (
            f"MATTERS (Δp50 {delta:+} µs, exceeds IQR {threshold} µs)"
            if holds
            else f"no measurable effect (Δp50 {delta:+} µs, within IQR {threshold} µs)"
        )
        lines.append(f"- **{label}** ({arm_a} vs {arm_b}): {verdict}")
    if quick:
        lines.append("")
        lines.append("_(quick profile — indicative only, not for publication)_")

    (out_dir / "exp-002b-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {out_dir}/exp-002b-summary.csv and {out_dir}/exp-002b-summary.md")


if __name__ == "__main__":
    main()
