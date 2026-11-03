#!/usr/bin/env python3
"""Summarise exp-016's kuksa-perf outputs: per setup, the median of each percentile across
repetitions with its range, then the differences between setups.

    python3 -I summarize.py <run dir>/out

Reads only what kuksa-perf prints ("50% in under 0.132 ms", "Sent:", "Received:"). A run whose
output has no latency distribution, or that received nothing, is listed as failed, never dropped.
"""
import pathlib
import re
import statistics
import sys

PCT = re.compile(r"(\d+)% in under ([\d.]+) ms")
COUNT = re.compile(r"^\s*(Sent|Received|Skipped):\s*(\d+)", re.M)


def parse(path):
    text = path.read_text(errors="replace")
    pct = {int(p): float(v) * 1000 for p, v in PCT.findall(text)}  # microseconds
    counts = {k: int(v) for k, v in COUNT.findall(text)}
    return pct, counts


def main(out):
    runs = {}
    failed = []
    for f in sorted(pathlib.Path(out).glob("*.txt")):
        if f.stem.startswith(("denied", "release")):
            continue
        key, _, rep = f.stem.rpartition("-")
        pct, counts = parse(f)
        # kuksa-perf 0.3.2 against databroker 0.7.1 exits 0 having sent nothing, and prints a
        # distribution of 0.000 ms. A run with no traffic is a failed run, never a fast one.
        if 50 not in pct or not counts.get("Received"):
            failed.append(f.name)
            continue
        runs.setdefault(key, []).append((pct, counts))

    print("median across repetitions, microseconds; [min-max] in brackets")
    print(f"{'run':24} {'n':>2} {'p50':>18} {'p90':>18} {'p99':>18} {'received/sent':>14}")
    med = {}
    for key, rs in runs.items():
        cells = []
        for p in (50, 90, 99):
            vals = [r[0][p] for r in rs if p in r[0]]
            m = statistics.median(vals)
            med[(key, p)] = m
            cells.append(f"{m:7.1f} [{min(vals):.0f}-{max(vals):.0f}]")
        sent = sum(r[1].get("Sent", 0) for r in rs)
        recv = sum(r[1].get("Received", 0) for r in rs)
        ratio = f"{recv}/{sent}" if sent else "-"
        print(f"{key:24} {len(rs):>2} {cells[0]:>18} {cells[1]:>18} {cells[2]:>18} {ratio:>14}")

    print()
    print("differences of the medians, microseconds")
    for op in ("publish", "actuate"):
        for a, b in (("idle", "baseline"), ("loaded", "idle"), ("loaded", "baseline")):
            ka, kb = f"{op}-{a}", f"{op}-{b}"
            if (ka, 50) in med and (kb, 50) in med:
                diffs = "  ".join(f"p{p} {med[(ka, p)] - med[(kb, p)]:+7.1f}" for p in (50, 90, 99))
                print(f"{op:8} {a:>7} - {b:<8} {diffs}")
    if failed:
        print()
        print("runs with no latency distribution:", " ".join(failed))
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1])
