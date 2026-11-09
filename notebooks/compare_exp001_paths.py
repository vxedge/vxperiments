#!/usr/bin/env python3
"""Compare exp-001 run through vxAPI measurements with run.sh campaigns.

    python3 notebooks/compare_exp001_paths.py results/exp-001-measurements-2026-11-09/points \\
        frozen=results/exp-001 oct-run1=results/exp-001-repro-2026-10-13 \\
        oct-run2=results/exp-001-repro-2026-10-13-run2

The first argument holds one vxprobe summary per point (`rep<r>-load<l>.summary.json`); each
`name=dir` is a reference holding run.sh's archives (`rep*-load*.zip`) or such summaries. Per load
and metric (p50, p95, p99): the median across repetitions and the IQR, as analyze_exp001.py
computes them (`statistics.quantiles(n=4)`). The gate counts the 15 metric x load pairs whose
median falls within the reference median plus or minus the reference IQR, the band the exp-001
repro checks used, and also within the reference's Q1..Q3, the stricter form. Stdlib only.
"""
import json
import re
import statistics
import sys
import zipfile
from pathlib import Path

METRICS = ("p50", "p95", "p99")


def runs(d):
    out = {}
    for z in sorted(Path(d).glob("rep*-load*.zip")):
        load = int(re.search(r"load(\d+)", z.name).group(1))
        out.setdefault(load, []).append(json.loads(zipfile.ZipFile(z).read("ingest/probe-summary.json")))
    for f in sorted(Path(d).glob("rep*-load*.summary.json")):
        load = int(re.search(r"load(\d+)", f.name).group(1))
        out.setdefault(load, []).append(json.loads(f.read_text()))
    return out


def stats(values):
    q = statistics.quantiles(values, n=4)
    return statistics.median(values), q[0], q[2]


def table(r):
    lines = ["| load (mbit) | reps | min samples | p50 µs (IQR) | p95 µs (IQR) | p99 µs (IQR) | loss % |",
             "|---:|---:|---:|---:|---:|---:|---:|"]
    for load in sorted(r):
        reps = r[load]
        cells = []
        for m in METRICS:
            med, q1, q3 = stats([x["rtt_us"][m] for x in reps])
            cells.append(f"{med:.1f} ({q3 - q1:.1f})")
        sent = sum(x["sent"] for x in reps)
        lost = sum(x["lost"] for x in reps)
        lines.append(f"| {load} | {len(reps)} | {min(x['received'] for x in reps)} | " + " | ".join(cells)
                     + f" | {100 * lost / max(sent, 1):.1f} |")
    return "\n".join(lines)


def gate(new, ref):
    band = strict = 0
    outside = []
    for load in sorted(new):
        for m in METRICS:
            med = statistics.median([x["rtt_us"][m] for x in new[load]])
            rmed, q1, q3 = stats([x["rtt_us"][m] for x in ref[load]])
            if abs(med - rmed) <= q3 - q1:
                band += 1
            else:
                outside.append(f"{m}@{load} {med - rmed:+.1f}")
            strict += q1 <= med <= q3
    return band, strict, outside


def main():
    new = runs(sys.argv[1])
    refs = {k: runs(v) for k, v in (a.split("=", 1) for a in sys.argv[2:])}
    print(table(new))
    if 0 in new and 600 in new:
        ratio = statistics.median([x["rtt_us"]["p99"] for x in new[600]]) / statistics.median(
            [x["rtt_us"]["p99"] for x in new[0]])
        print(f"\nH1: p99 at 600 mbit / p99 idle = {ratio:.2f}x (threshold 2.0x): "
              + ("holds" if ratio <= 2.0 else "does not hold"))
    pairs = [(f"measurements vs {k}", new, v) for k, v in refs.items()]
    names = list(refs)
    pairs += [(f"run.sh {a} vs {b}", refs[a], refs[b]) for i, a in enumerate(names) for b in names[:i]]
    print("\n| comparison | within median ± IQR | within Q1..Q3 | outside median ± IQR (µs, new minus reference) |")
    print("|---|---:|---:|---|")
    for name, a, b in pairs:
        band, strict, outside = gate(a, b)
        print(f"| {name} | {band} / 15 | {strict} / 15 | {', '.join(outside) or 'none'} |")


if __name__ == "__main__":
    main()
