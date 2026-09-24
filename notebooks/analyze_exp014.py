#!/usr/bin/env python3
"""exp-014 analysis — harness topology as a variable: star vs daisy-chained zones.

Reads ONLY results archives (results/exp-014/rep*-<arm>.zip). Aggregates repetitions per arm
(median + IQR), reports the star arms' own spread as this campaign's noise floor (a star
topology has no hop to accumulate, by design — see vehicle.yaml), and states the verdict: does
the chain arm's latency/jitter grow with hop count beyond that floor? Also reconstructs each
topology's total harness length/weight from the six archives' own declared_harness fields
(never from vehicle.yaml directly — notebooks read archives only).

Usage: python3 notebooks/analyze_exp014.py results/exp-014 [--out-dir DIR]
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

ARCHIVE_RE = re.compile(r"rep(\d+)-([a-z]+-[a-z]+)\.zip$")
ARM_ORDER = ["star-fl", "star-fr", "star-rl", "chain-fl", "chain-fr", "chain-rl"]


def json_lenient(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])


def input_sha(meta):
    """Checksum of what the run provisioned from — see analyze_exp002.py's own note."""
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

    not_isolated = sorted({r["arm"] for r in runs if r["env"].get("isolation") != "single-arm"})
    if not_isolated:
        sys.exit(
            f"REFUSING: archives for arm(s) {not_isolated} lack isolation=='single-arm'"
        )
    not_cross_netns = sorted(
        {
            r["arm"]
            for r in runs
            if not str(r["env"].get("measurement_locality", "")).startswith("cross-netns")
        }
    )
    if not_cross_netns:
        sys.exit(
            f"REFUSING: archives for arm(s) {not_cross_netns} do not record cross-netns "
            "measurement -- these may have been probed with sender and reflector in the same "
            "network namespace, which a disposable-netns check found delivers via loopback "
            "without ever crossing the harness under test (docs/ROADMAP.md). Re-run with the "
            "current scripts/run.sh."
        )
    quick = any(r["env"].get("quick_profile") for r in runs)

    by_arm = defaultdict(list)
    for r in runs:
        by_arm[r["arm"]].append(r)

    rows = []
    for arm in [a for a in ARM_ORDER if a in by_arm] + sorted(set(by_arm) - set(ARM_ORDER)):
        reps = by_arm[arm]
        env0 = reps[0]["env"]
        row = {
            "arm": arm,
            "topology": env0.get("topology", arm.split("-")[0]),
            "hop": env0.get("hop"),
            "reps": len(reps),
            "min_samples": min(r["probe"]["received"] for r in reps),
            "declared_delay_us": env0["declared_impairment"]["delay_us"],
            "declared_length_m": env0["declared_harness"]["length_m"],
            "declared_weight_g": env0["declared_harness"]["weight_g"],
        }
        for metric in ("p50", "p95", "p99"):
            med, iqr = quantile_stats([r["probe"]["rtt_us"][metric] for r in reps])
            row[f"{metric}_us"] = round(med, 1)
            row[f"{metric}_iqr_us"] = round(iqr, 1)
        # vxprobe reports jitter as RTT standard deviation (`rtt_us.stddev`).
        row["jitter_us"] = round(
            statistics.median([r["probe"]["rtt_us"]["stddev"] for r in reps]), 1
        )
        worst = max(reps, key=lambda r: r["probe"]["loss_pct"])
        row["loss_pct_max"] = round(worst["probe"]["loss_pct"], 4)
        row["loss_lost"] = worst["probe"]["lost"]
        row["loss_sent"] = worst["probe"]["sent"]
        rows.append(row)

    star_rows = [r for r in rows if r["topology"] == "star"]
    chain_rows = sorted(
        [r for r in rows if r["topology"] == "chain"], key=lambda r: r["hop"] or 0
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "exp-014-summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, NOT reportable" if quick else "full profile"
    )
    cold_groups = [(r["arm"], r["p50_us"], r["p99_us"]) for r in rows]
    lines = [
        "# exp-014 — harness topology as a variable: star vs daisy-chained zones",
        "",
        f"- runs: {len(runs)} archives, input sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per arm, idle topology, "
        "one arm zoned up at a time",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, "
        f"governor={env['cpu_governor']}, timestamping: {env['timestamping']}",
        f"- caveats: shared-host gateway; {profile_note}; declared impairment values are stated "
        "assumptions (one 100BASE-T1 hop ~= 30us delay/5us jitter), not datasheet constants — "
        "see vehicle.yaml"
        + (f"; {_cold}" if (_cold := cold_start_caveat(cold_groups, quick)) else ""),
        "",
        "| arm | hop | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) "
        "| jitter µs | max loss % (lost/sent) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            f"| {r['arm']} | {r['hop']} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['jitter_us']} "
            f"| {r['loss_pct_max']} ({r['loss_lost']}/{r['loss_sent']}) |"
        )

    lines += ["", "## Harness-reduction accounting (declared, not measured)", ""]
    star_len = sum(r["declared_length_m"] for r in star_rows)
    star_wt = sum(r["declared_weight_g"] for r in star_rows)
    chain_len = sum(r["declared_length_m"] for r in chain_rows)
    chain_wt = sum(r["declared_weight_g"] for r in chain_rows)
    if star_len and chain_len:
        len_pct = round(100 * (1 - chain_len / star_len), 1)
        wt_pct = round(100 * (1 - chain_wt / star_wt), 1) if star_wt else None
        lines.append(
            f"- star topology: {star_len:g} m, {star_wt:g} g total harness "
            f"({len(star_rows)} home-run segments)"
        )
        lines.append(
            f"- chain topology: {chain_len:g} m, {chain_wt:g} g total harness "
            f"({len(chain_rows)} chain segments)"
        )
        lines.append(
            f"- **{len_pct}% less harness length** ({wt_pct}% less weight) for the chain "
            "topology at these three positions — illustrative for a 3-node comparison, not a "
            "validated whole-vehicle harness-mass claim"
        )
    else:
        lines.append("- one topology missing from these archives: accounting unavailable")

    lines += ["", "## Verdict: does latency/jitter grow with hop count?", ""]
    if len(star_rows) < 2 or len(chain_rows) < 2:
        lines.append("- fewer than two arms in one topology: verdict unavailable")
    else:
        # The star arms' own spread is this campaign's noise floor for "no accumulation" — no
        # separate zero-stimulus calibration pass is needed, since that is exactly what star
        # means by design (see vehicle.yaml).
        star_p50s = [r["p50_us"] for r in star_rows]
        noise_floor = max(star_p50s) - min(star_p50s)
        floor = max(noise_floor, 10.0 if quick else 1.0)
        deltas = [
            round(chain_rows[i]["p50_us"] - chain_rows[i - 1]["p50_us"], 1)
            for i in range(1, len(chain_rows))
        ]
        monotonic = all(d > 0 for d in deltas)
        beyond_floor = all(d > floor for d in deltas)
        lines.append(
            f"- star arms' p50 spread (noise floor for this campaign): {round(noise_floor, 1)} µs"
        )
        lines.append(
            f"- chain arms' successive p50 deltas by hop: {deltas} µs (threshold: >{round(floor, 1)} µs)"
        )
        if monotonic and beyond_floor:
            lines.append(
                "- chain p50 grows monotonically with hop count, beyond the star arms' own "
                "spread — **HARNESS-TOPOLOGY EFFECT HOLDS**"
                + (" (quick profile — indicative only)" if quick else "")
            )
        elif monotonic:
            lines.append(
                "- chain p50 grows monotonically with hop count, but not beyond the star arms' "
                "own spread — growth present but not distinguishable from noise at this "
                "resolution"
                + (" (quick profile — indicative only)" if quick else "")
            )
        else:
            lines.append(
                "- chain p50 does not grow monotonically with hop count — "
                "**HARNESS-TOPOLOGY EFFECT DOES NOT HOLD** at this resolution"
                + (" (quick profile — indicative only)" if quick else "")
            )

    (out_dir / "exp-014-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwrote {out_dir}/exp-014-summary.csv and {out_dir}/exp-014-summary.md")


if __name__ == "__main__":
    main()
