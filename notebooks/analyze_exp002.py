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

from cold_start import caveat as cold_start_caveat
from pathlib import Path

ARCHIVE_RE = re.compile(r"rep(\d+)-([a-z]+)\.zip$")
ARM_ORDER = ["container", "microvm", "libvirt"]


def json_lenient(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])
def input_sha(meta):
    """Checksum of what the run provisioned from.

    Archives written before 2026-07-31 carry `manifest_sha256` (a hash of the §6.1 manifest);
    later ones carry `workspace_sha256` (a hash of every file of the §6.0 workspace). Both
    answer the same question — did every repetition run from the same input — so analysis
    accepts either and refuses only when an archive carries neither.
    """
    for key in ("workspace_sha256", "manifest_sha256"):
        if key in meta:
            return meta[key]
    raise SystemExit("archive metadata.json has no workspace_sha256 or manifest_sha256")


def quantile_stats(values):
    med = statistics.median(values)
    if len(values) >= 4:
        q = statistics.quantiles(values, n=4)
        iqr = q[2] - q[0]
    else:
        iqr = max(values) - min(values)
    return med, iqr


def parse_out_dir(args, default):
    """Accept both `--out-dir DIR` and `--out-dir=DIR`."""
    out_dir = default
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--out-dir":
            if i + 1 >= len(args):
                sys.exit("error: --out-dir needs a value")
            out_dir = Path(args[i + 1])
            i += 2
        elif arg.startswith("--out-dir="):
            out_dir = Path(arg.split("=", 1)[1])
            i += 1
        else:
            sys.exit(f"error: unrecognized argument: {arg}\n\n{__doc__}")
    return out_dir


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    results_dir = Path(sys.argv[1])
    out_dir = parse_out_dir(sys.argv[2:], results_dir)

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
                    "sha": input_sha(json_lenient(z.read("metadata.json"))),
                }
            )
    if not runs:
        sys.exit(f"no rep*-<arm>.zip archives in {results_dir}")
    shas = {r["sha"] for r in runs}
    if len(shas) != 1:
        sys.exit(f"REFUSING: archives span {len(shas)} input checksums")

    # Isolation provenance (2026-07-13 methodology fix, retrofit of the same
    # fix already applied to exp-002b — see that runner's header): a pre-fix
    # exp-002 runner grouped all three packaging backends under one zone, so
    # `zone up` always started all three concurrently even though only one
    # was being measured — the same class of unpinned-concurrent-guest CPU
    # contention that invalidated exp-002b's first campaign. Archives without
    # isolation=="single-arm" predate the fix and are refused outright rather
    # than silently analyzed, even though exp-002's original frozen result
    # happened to show zero loss (luck, not a property of the design).
    not_isolated = sorted({r["arm"] for r in runs if r["env"].get("isolation") != "single-arm"})
    if not_isolated:
        sys.exit(
            "REFUSING: archives for arm(s) "
            f"{not_isolated} lack isolation=='single-arm' — these predate the "
            "concurrent-VM contention fix (2026-07-13) and are not comparable. "
            "Re-run the campaign with the current scripts/run-exp-002.sh."
        )
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
        worst = max(reps, key=lambda r: r["probe"]["loss_pct"])
        row["loss_pct_max"] = round(worst["probe"]["loss_pct"], 4)
        row["loss_lost"] = worst["probe"]["lost"]
        row["loss_sent"] = worst["probe"]["sent"]
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
        f"- runs: {len(runs)} archives, input sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per arm, idle topology",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, KVM={env.get('kvm')}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}"
        + (f"; {_cold}" if (_cold := cold_start_caveat([(r['arm'], r["p50_us"], r["p99_us"]) for r in rows], quick)) else ""),
        "",
        "| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | Δp50 vs container | Δp99 vs container | max loss % (lost/sent) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['arm']} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['p50_vs_container']:+} "
            f"| {r['p99_vs_container']:+} | {r['loss_pct_max']} ({r['loss_lost']}/{r['loss_sent']}) |"
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
            # Quick profile: single rep => degenerate IQR; floor at the quick-noise
            # band (10 µs: session drift 4-7 µs + single-rep scatter) so verdicts
            # don't flip on noise. Full campaigns keep the IQR-based threshold.
            and abs(r["p50_us"] - baseline["p50_us"])
            > max(baseline["p50_iqr_us"], 10.0 if quick else 1.0)
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
