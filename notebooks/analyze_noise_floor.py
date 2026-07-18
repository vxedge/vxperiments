#!/usr/bin/env python3
"""Noise-floor calibration analysis — NOT a hypothesis test.

Reads the JSON files scripts/calibrate-exp-010-noise-floor.sh writes
(rep<N>.json, each a raw vxprobe send summary) and reports descriptive
statistics for session-to-session variance with zero experimental
stimulus: adas-probe run alone, full vxedge up/down between every
repetition. This is the background any specific campaign data point's
deviation needs to clear before being called a real effect rather than
noise.

Usage: python3 notebooks/analyze_noise_floor.py results/exp-010-noise-floor-<date>
Stdlib only — runs headless anywhere.
"""

import json
import statistics
import sys
from pathlib import Path


def json_lenient(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    return json.loads(text[start:])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    results_dir = Path(sys.argv[1])
    runs = []
    for path in sorted(results_dir.glob("rep*.json")):
        data = json_lenient(path.read_bytes())
        runs.append({"path": path.name, **data})
    if not runs:
        sys.exit(f"no rep*.json files in {results_dir}")

    print(f"# Noise-floor calibration — {len(runs)} runs, {results_dir}")
    print()
    print("NOT a hypothesis test — this characterizes session-to-session")
    print("measurement variance with zero experimental stimulus.")
    print()
    print("| rep | p50 (us) | p95 (us) | p99 (us) | loss % |")
    print("|---:|---:|---:|---:|---:|")
    for i, r in enumerate(runs, 1):
        rtt = r["rtt_us"]
        print(f"| {i} | {rtt['p50']:.1f} | {rtt['p95']:.1f} | {rtt['p99']:.1f} | {r['loss_pct']} |")

    for metric in ("p50", "p95", "p99"):
        values = [r["rtt_us"][metric] for r in runs]
        med = statistics.median(values)
        lo, hi = min(values), max(values)
        stdev = statistics.stdev(values) if len(values) > 1 else 0.0
        if len(values) >= 4:
            q = statistics.quantiles(values, n=4)
            iqr = q[2] - q[0]
        else:
            iqr = hi - lo
        print()
        print(f"## {metric} across {len(runs)} reps")
        print(f"- median: {med:.1f} us, IQR: {iqr:.1f} us, stddev: {stdev:.1f} us")
        print(f"- range: {lo:.1f} - {hi:.1f} us (spread of {hi - lo:.1f} us)")
        print(
            f"- any single campaign point deviating from a baseline by less than "
            f"~{iqr:.0f}-{hi - lo:.0f} us is not distinguishable from this noise floor"
        )


if __name__ == "__main__":
    main()
