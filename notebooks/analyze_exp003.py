#!/usr/bin/env python3
"""exp-003 analysis — ADAS slice SLA under OTA co-location (H4).

Reads ONLY results archives (results/exp-003/rep*-<arm>.zip), per the
experiment-methodology skill: aggregates repetitions per arm as median with
IQR, emits a markdown table + CSV, and states the H4 verdict (does the
ota-burst arm's adas p50 exceed baseline's IQR?).

Also reports OTA delivery stats (success/failure counts, delivery latency)
for the ota-burst arm, extracted from vxtelemetry's periodic Prometheus
scrapes of vxota-probe's live exporter (127.0.0.1:9902) — not from a final
JSON summary, since the burst driver is killed at the end of the probe
window rather than exiting on its own.

Usage: python3 notebooks/analyze_exp003.py results/exp-003 [--out-dir DIR]
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

ARCHIVE_RE = re.compile(r"rep(\d+)-(baseline|ota-burst)\.zip$")
ARM_ORDER = ["baseline", "ota-burst"]

# H4 acceptance: ota-burst adas p50 must not exceed baseline's IQR (mirrors
# the exp-002b decomposition verdict pattern: MATTERS vs no measurable effect).


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


def ota_burst_stats(raw_samples: bytes):
    """Extract OTA delivery stats from vxtelemetry's scraped samples.jsonl
    (vxota-probe's live exporter at 127.0.0.1:9902). Counters/gauges are
    monotonic or point-in-time over the window, so the last scrape of each
    series is its final reading. Returns None if no such samples exist
    (baseline arm, or the burst driver never got scraped before teardown)."""
    success = failure = None
    latency = {}
    for line in raw_samples.decode("utf-8", errors="replace").splitlines():
        if not line.strip() or "9902" not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if "9902" not in rec.get("target", ""):
            continue
        metric = rec.get("metric", "")
        labels = rec.get("labels", "")
        value = rec.get("value")
        if metric == "vxota_deployments_total":
            if 'status="success"' in labels:
                success = value
            elif 'status="failure"' in labels:
                failure = value
        elif metric == "vxota_delivery_latency_seconds":
            for q, key in [('quantile="0.5"', "p50"), ('quantile="0.95"', "p95"), ('quantile="0.99"', "p99")]:
                if q in labels:
                    latency[key] = value
    if success is None and failure is None and not latency:
        return None
    return {
        "succeeded": success,
        "failed": failure,
        "delivery_latency_ms": {k: round(v * 1000, 1) for k, v in latency.items()},
    }


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
            names = set(z.namelist())
            ota = None
            samples_name = "ingest/samples.jsonl"
            if samples_name in names:
                try:
                    ota = ota_burst_stats(z.read(samples_name))
                except (ValueError, KeyError):
                    ota = None
            stats_name = "ingest/ingest-stats.json"
            stats = json_lenient(z.read(stats_name)) if stats_name in names else None
            resource_name = "ingest/resource-summary.json"
            resource = None
            if resource_name in names:
                try:
                    resource = json_lenient(z.read(resource_name))
                except (ValueError, KeyError):
                    resource = None
            runs.append(
                {
                    "rep": int(m.group(1)),
                    "arm": m.group(2),
                    "probe": json_lenient(z.read("ingest/probe-summary.json")),
                    "env": json_lenient(z.read("ingest/run-env.json")),
                    "ota": ota,
                    "stats": stats,
                    "resource": resource,
                    "sha": input_sha(json_lenient(z.read("metadata.json"))),
                }
            )
    if not runs:
        sys.exit(f"no rep*-<arm>.zip archives in {results_dir}")
    shas = {r["sha"] for r in runs}
    if len(shas) != 1:
        sys.exit(f"REFUSING: archives span {len(shas)} input checksums — not one experiment")
    quick = any(r["env"].get("quick_profile") for r in runs)

    LOSS_WARN_PCT = 1.0
    anomalies = [
        (r["arm"], r["rep"], r["probe"]["loss_pct"])
        for r in runs
        if r["probe"]["loss_pct"] > LOSS_WARN_PCT
    ]
    unreliable_arms = {a for a, _, _ in anomalies}

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
            "unreliable": arm in unreliable_arms,
        }
        for metric in ("p50", "p95", "p99"):
            med, iqr = quantile_stats([r["probe"]["rtt_us"][metric] for r in reps])
            row[f"{metric}_us"] = round(med, 1)
            row[f"{metric}_iqr_us"] = round(iqr, 1)
        worst = max(reps, key=lambda r: r["probe"]["loss_pct"])
        row["loss_pct_max"] = round(worst["probe"]["loss_pct"], 4)
        row["loss_lost"] = worst["probe"]["lost"]
        row["loss_sent"] = worst["probe"]["sent"]

        ota_reps = [r["ota"] for r in reps if r["ota"]]
        if ota_reps:
            succeeded = [o["succeeded"] for o in ota_reps if o["succeeded"] is not None]
            failed = [o["failed"] for o in ota_reps if o["failed"] is not None]
            p50s = [o["delivery_latency_ms"].get("p50") for o in ota_reps if o["delivery_latency_ms"].get("p50")]
            row["ota_deliveries_succeeded_median"] = round(statistics.median(succeeded), 1) if succeeded else None
            row["ota_deliveries_failed_median"] = round(statistics.median(failed), 1) if failed else None
            row["ota_delivery_p50_ms_median"] = round(statistics.median(p50s), 1) if p50s else None
        else:
            row["ota_deliveries_succeeded_median"] = None
            row["ota_deliveries_failed_median"] = None
            row["ota_delivery_p50_ms_median"] = None

        stats_reps = [r["stats"] for r in reps if r["stats"]]
        if stats_reps:
            def pct(ok_key, fail_key):
                vals = []
                for s in stats_reps:
                    ok, fail = s.get(ok_key, 0), s.get(fail_key, 0)
                    total = ok + fail
                    vals.append(100.0 * ok / total if total else None)
                vals = [v for v in vals if v is not None]
                return round(statistics.median(vals), 1) if vals else None

            row["required_completeness_pct"] = pct("scrapes_ok", "scrapes_failed")
            row["optional_completeness_pct"] = pct("optional_scrapes_ok", "optional_scrapes_failed")
        else:
            row["required_completeness_pct"] = None
            row["optional_completeness_pct"] = None
        rows.append(row)

    by_arm_row = {r["arm"]: r for r in rows}

    # OTA process resource footprint (§12 compute metrics): the ota-server process runs in
    # both arms (idle in baseline, actively serving the burst artifact in ota-burst); the
    # ota-probe fetcher only exists in ota-burst. A (arm, label) pair with zero matched
    # samples across every rep simply never appears here — vxtelemetry::sample only ever
    # writes a label into resource-summary.json if it actually matched a process — which is
    # the expected, not-a-bug shape for ota-probe never showing up under baseline.
    resource_agg = defaultdict(lambda: {"cpu": [], "rss": [], "samples": []})
    for r in runs:
        res = r["resource"] or {}
        for label, node in res.items():
            key = (r["arm"], label)
            resource_agg[key]["cpu"].append(node["cpu_pct_mean"])
            resource_agg[key]["rss"].append(node["rss_mb_mean"])
            resource_agg[key]["samples"].append(node["samples"])
    resource_rows = []
    for arm in [a for a in ARM_ORDER if a in by_arm] + sorted(set(by_arm) - set(ARM_ORDER)):
        for label in sorted({lbl for (a, lbl) in resource_agg if a == arm}):
            vals = resource_agg[(arm, label)]
            resource_rows.append(
                {
                    "arm": arm,
                    "label": label,
                    "reps_matched": len(vals["cpu"]),
                    "cpu_pct_mean": round(statistics.median(vals["cpu"]), 2),
                    "rss_mb_mean": round(statistics.median(vals["rss"]), 1),
                }
            )
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "exp-003-summary.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    if resource_rows:
        with (out_dir / "exp-003-resource.csv").open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(resource_rows[0].keys()))
            w.writeheader()
            w.writerows(resource_rows)

    env = runs[0]["env"]
    profile_note = (
        "QUICK PROFILE — pipeline validation only, NOT reportable" if quick else "full profile"
    )
    lines = [
        "# exp-003 — ADAS slice SLA under OTA co-location (H4)",
        "",
        f"- runs: {len(runs)} archives, input sha256 `{next(iter(shas))[:12]}…`",
        f"- probe: {env['probe_pps']} pps x {env['probe_window_s']} s per arm, "
        f"timeout {env.get('probe_timeout_ms', 'unknown (script default ~1000)')} ms, "
        f"warmup {env['warmup_s']} s discarded, burst artifact {env.get('ota_burst_artifact_mb', '?')} MB",
        f"- host: kernel {env['kernel']}, PREEMPT_RT={env['preempt_rt']}, governor={env['cpu_governor']}",
        f"- caveats: shared-host gateway; {profile_note}; v1 OTA transport binds a plain host "
        "address (no manifest slice/WireGuard yet) — this measures host-level CPU/scheduling "
        "contention between the OTA workload and the adas probe, not gateway-QoS-enforced "
        "network contention"
        + (f"; {_cold}" if (_cold := cold_start_caveat([(r["arm"], r["p50_us"], r["p99_us"]) for r in rows], quick)) else ""),
    ]
    required_by_arm = {r["arm"]: r["required_completeness_pct"] for r in rows}
    optional_by_arm = {r["arm"]: r["optional_completeness_pct"] for r in rows}
    low_required = {a: p for a, p in required_by_arm.items() if p is not None and p < 100.0}
    if low_required:
        lines.append(
            "- ⚠️ telemetry note: required scrape completeness below 100% for "
            f"{', '.join(f'{a} ({p}%)' for a, p in sorted(low_required.items()))} — this IS "
            "real data loss on the adas-relevant target, not the known-absent-optional-"
            "target pattern below; investigate before trusting affected arms' RTT stats."
        )
    if any(p is not None for p in optional_by_arm.values()):
        lines.append(
            "- telemetry note: optional-target (vxota-probe exporter, 127.0.0.1:9902) "
            "completeness by arm: "
            + ", ".join(f"{a} {p}%" for a, p in sorted(optional_by_arm.items()) if p is not None)
            + " — expected to be low/zero in `baseline` (nothing listens there outside "
            "`ota-burst` by design; tracked separately via `optional_scrape_targets` and "
            "does not affect the required-target completeness above)."
        )
    lines += [
        "",
        "| arm | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | max loss % (lost/sent) | ota deliveries ok/fail (median) | ota delivery p50 ms |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        flag = " ⚠️" if r["unreliable"] else ""
        ota_dev = (
            f"{r['ota_deliveries_succeeded_median']}/{r['ota_deliveries_failed_median']}"
            if r["ota_deliveries_succeeded_median"] is not None
            else "n/a"
        )
        ota_lat = r["ota_delivery_p50_ms_median"] if r["ota_delivery_p50_ms_median"] is not None else "n/a"
        lines.append(
            f"| {r['arm']}{flag} | {r['reps']} | {r['min_samples']} "
            f"| {r['p50_us']} ({r['p50_iqr_us']}) | {r['p95_us']} ({r['p95_iqr_us']}) "
            f"| {r['p99_us']} ({r['p99_iqr_us']}) | {r['loss_pct_max']} ({r['loss_lost']}/{r['loss_sent']}) "
            f"| {ota_dev} | {ota_lat} |"
        )

    lines += ["", "## OTA process resource footprint", ""]
    if resource_rows:
        lines += [
            "| arm | process | reps matched | cpu % (mean) | rss MB (mean) |",
            "|---|---|---:|---:|---:|",
        ]
        for rr in resource_rows:
            lines.append(
                f"| {rr['arm']} | {rr['label']} | {rr['reps_matched']}/{by_arm_row[rr['arm']]['reps']} "
                f"| {rr['cpu_pct_mean']} | {rr['rss_mb_mean']} |"
            )
    else:
        lines.append(
            "_n/a — no `ingest/resource-summary.json` in these archives (older campaign, "
            "predating the resource sampler's exp-003 wiring) or no process matched the "
            "cmdline regex in any rep._"
        )

    if anomalies:
        lines += ["", "## ⚠️ Loss anomalies (per-repetition, exceeds "
                  f"{LOSS_WARN_PCT}%) — latency stats for these arms are unreliable", ""]
        for arm, rep, pct in sorted(anomalies):
            lines.append(f"- {arm} rep{rep}: {pct:.2f}% loss")

    lines += ["", "## H4 verdict", ""]
    baseline, burst = by_arm_row.get("baseline"), by_arm_row.get("ota-burst")
    if not baseline or not burst:
        lines.append("- missing arm(s), verdict unavailable")
    elif baseline["unreliable"] or burst["unreliable"]:
        lines.append("- UNRELIABLE — loss anomaly in one or both arms; re-run before drawing a conclusion")
    else:
        delta = round(burst["p50_us"] - baseline["p50_us"], 1)
        # Quick profile: single rep => degenerate IQR; floor at the quick-noise
        # band (10 µs). Full campaigns keep the IQR-based threshold.
        threshold = max(
            baseline["p50_iqr_us"], burst["p50_iqr_us"], 10.0 if quick else 1.0
        )
        # One-sided by construction: H4 claims the burst does not COMPROMISE
        # the SLA, so only burst-slower-than-baseline beyond the threshold is
        # a violation. Burst faster than baseline is session noise (this host
        # drifts several µs between sessions — STATUS risk item), never a fail.
        holds = delta <= threshold
        lines.append(
            f"- adas p50: baseline {baseline['p50_us']} µs vs ota-burst {burst['p50_us']} µs "
            f"(Δ {delta:+} µs, one-sided IQR threshold {threshold} µs)"
        )
        if delta < -threshold:
            lines.append(
                "- note: burst arm measured *faster* than baseline beyond the threshold — "
                "session-level drift, not an OTA effect"
            )
        lines.append(
            f"- **H4 {'HOLDS' if holds else 'DOES NOT HOLD'}** on this host"
            + (" (quick profile — indicative only)" if quick else "")
        )
    if quick:
        lines.append("")
        lines.append("_(quick profile — indicative only, not for publication)_")

    (out_dir / "exp-003-summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    wrote = f"{out_dir}/exp-003-summary.csv and {out_dir}/exp-003-summary.md"
    if resource_rows:
        wrote += f", {out_dir}/exp-003-resource.csv"
    print(f"\nwrote {wrote}")


if __name__ == "__main__":
    main()
