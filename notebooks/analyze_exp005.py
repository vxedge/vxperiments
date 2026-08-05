#!/usr/bin/env python3
"""exp-005 analysis — cold-start / first-packet latency after zone boot.

Reads ONLY results archives (results/exp-005/rep*.zip). Each archive holds two probe summaries
from the SAME repetition's SAME netns: `cold-summary.json` (fired the instant `zone up`
returned, zero warmup, ~60 samples by design) and `probe-summary.json` (a full 60s/1000pps
steady-state window immediately after, that repetition's own baseline). The comparison is
always within a repetition (`cold.max / steady.p50`), never across repetitions or days, so it
stays free of host-state drift.

The cold phase's own sample count is, by design, below the >=10000 samples tail-percentile
support requires -- reusing `cold_start.py`'s own RATIO_MULTIPLE as the "recognizable blowout"
threshold, generalized here across REPETITIONS instead of across ARMS, and applied to the
`max`/`p50` pair the cold phase's small n can actually support rather than a `p99` it cannot.

Usage: python3 notebooks/analyze_exp005.py results/exp-005 [--out-dir DIR]
Stdlib only -- runs headless anywhere.
"""

import json
import re
import statistics
import sys
import zipfile
from pathlib import Path

from cold_start import RATIO_MULTIPLE

ARCHIVE_RE = re.compile(r"rep(\d+)\.zip$")


def json_lenient(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])


def input_sha(meta):
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
    for path in sorted(results_dir.glob("rep*.zip")):
        m = ARCHIVE_RE.search(path.name)
        if not m:
            continue
        with zipfile.ZipFile(path) as z:
            runs.append(
                {
                    "rep": int(m.group(1)),
                    "cold": json_lenient(z.read("ingest/cold-summary.json")),
                    "steady": json_lenient(z.read("ingest/probe-summary.json")),
                    "env": json_lenient(z.read("ingest/run-env.json")),
                    "sha": input_sha(json_lenient(z.read("metadata.json"))),
                }
            )
    if not runs:
        sys.exit(f"no rep*.zip archives in {results_dir}")
    runs.sort(key=lambda r: r["rep"])

    shas = {r["sha"] for r in runs}
    if len(shas) != 1:
        sys.exit(f"REFUSING: archives span {len(shas)} input checksums")

    not_cross_netns = [
        r["rep"]
        for r in runs
        if not str(r["env"].get("measurement_locality", "")).startswith("cross-netns")
    ]
    if not_cross_netns:
        sys.exit(
            f"REFUSING: repetition(s) {not_cross_netns} do not record cross-netns measurement "
            "-- these may have been probed with sender and reflector in the same network "
            "namespace, which delivers via loopback without ever crossing the access port "
            "(docs/TASKS.md #28). Re-run with the current scripts/run.sh."
        )
    if any(r["steady"]["received"] == 0 for r in runs):
        sys.exit("REFUSING: at least one repetition's steady window received zero probes")

    quick = any(r["env"].get("quick_profile") for r in runs)

    rows = []
    for r in runs:
        cold, steady = r["cold"], r["steady"]
        steady_p50 = steady["rtt_us"]["p50"]
        row = {
            "rep": r["rep"],
            "cold_n": cold["received"],
            "cold_p50_us": round(cold["rtt_us"]["p50"], 1),
            "cold_max_us": round(cold["rtt_us"]["max"], 1),
            "steady_n": steady["received"],
            "steady_p50_us": round(steady_p50, 1),
            "steady_p99_us": round(steady["rtt_us"]["p99"], 1),
            "ratio_max": round(cold["rtt_us"]["max"] / steady_p50, 2) if steady_p50 else None,
            "ratio_p50": round(cold["rtt_us"]["p50"] / steady_p50, 2) if steady_p50 else None,
        }
        rows.append(row)

    out_dir.mkdir(parents=True, exist_ok=True)
    import csv

    with (out_dir / "exp-005-summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, NOT reportable" if quick else "full profile"
    )
    min_cold_n = min(r["cold_n"] for r in rows)
    ratio_maxes = [r["ratio_max"] for r in rows if r["ratio_max"] is not None]
    ratio_p50s = [r["ratio_p50"] for r in rows if r["ratio_p50"] is not None]
    med_ratio_max, iqr_ratio_max = quantile_stats(ratio_maxes)
    med_ratio_p50, iqr_ratio_p50 = quantile_stats(ratio_p50s)
    blown = [r["rep"] for r in rows if (r["ratio_max"] or 0) >= RATIO_MULTIPLE]

    lines = [
        "# exp-005 — cold-start / first-packet latency after zone boot",
        "",
        f"- repetitions: {len(runs)}, input sha256 `{next(iter(shas))[:12]}…`",
        f"- cold phase: {env['cold_probe_pps']} pps x {env['cold_probe_duration_s']} s, "
        f"zero warmup, fired immediately after `zone up` — n={min_cold_n} min "
        "(BELOW tail-percentile support by design; only p50/max reported, never p99)",
        f"- steady phase: {env['steady_probe_pps']} pps x {env['steady_window_s']} s, "
        "same netns, immediately after the cold phase — this repetition's own baseline "
        "(real tail-percentile support)",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}; single-host clock "
        "(no cross-host sync needed — cold and steady phases share one netns/one clock)",
        "",
        "| rep | cold n | cold p50 µs | cold max µs | steady n | steady p50 µs "
        "| steady p99 µs | max/p50 ratio | p50/p50 ratio |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['rep']} | {r['cold_n']} | {r['cold_p50_us']} | {r['cold_max_us']} "
            f"| {r['steady_n']} | {r['steady_p50_us']} | {r['steady_p99_us']} "
            f"| {r['ratio_max']} | {r['ratio_p50']} |"
        )

    lines += ["", "## Verdict: does a fresh zone boot show a first-packet latency cost?", ""]
    lines.append(
        f"- cold `max`/steady `p50` ratio across repetitions: median {round(med_ratio_max, 2)} "
        f"(IQR {round(iqr_ratio_max, 2)})"
    )
    lines.append(
        f"- cold `p50`/steady `p50` ratio across repetitions: median {round(med_ratio_p50, 2)} "
        f"(IQR {round(iqr_ratio_p50, 2)}) — sanity check: a value near 1.0 would mean the cold "
        "phase's own *typical* packet is unaffected, with any effect confined to a few slow "
        "packets pulling `max` up rather than a shifted median. "
        + (
            f"**Not the case here**: {round(med_ratio_p50, 2)}x is well above 1.0, so the "
            "elevation isn't confined to a tail of unlucky packets — the whole ~3 s cold "
            "window runs measurably slower, consistent with the transient (ARP, page "
            "faults, CPU frequency ramp) persisting across most of the burst rather than "
            "resolving after the very first packet"
            if med_ratio_p50 >= 1.5
            else f"That's roughly what's observed here ({round(med_ratio_p50, 2)}x) — the "
            "effect looks concentrated in a handful of slow packets, not the whole burst"
        )
    )
    lines.append(
        f"- repetitions with cold `max` >= {RATIO_MULTIPLE}x steady `p50` "
        f"(cold_start.py's own blowout threshold): {len(blown)}/{len(rows)} {blown}"
    )
    if len(blown) == 0:
        lines.append(
            "- **NO COLD-START EFFECT DETECTED** at this threshold — negative result, reported "
            "as found, not hidden"
            + (" (quick profile — indicative only)" if quick else "")
        )
    elif len(blown) == len(rows):
        lines.append(
            "- **COLD-START EFFECT HOLDS ON EVERY REPETITION** — a fresh zone boot reliably "
            "costs its first few packets a multiple of steady-state latency"
            + (" (quick profile — indicative only)" if quick else "")
        )
    else:
        lines.append(
            f"- **COLD-START EFFECT PRESENT BUT INTERMITTENT** ({len(blown)}/{len(rows)} "
            "repetitions) — not a reliable per-boot cost at this sample size"
            + (" (quick profile — indicative only)" if quick else "")
        )

    (out_dir / "exp-005-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {out_dir}/exp-005-summary.csv and {out_dir}/exp-005-summary.md")


if __name__ == "__main__":
    main()
