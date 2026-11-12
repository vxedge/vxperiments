#!/usr/bin/env python3
"""Trial archives from a frozen run whose step output is committed as text, for verdict parity.

    scripts/frozen-checks.py <results folder> <package folder> <out dir>

A run made before its experiment was a package kept each tool run's output as
`out/<step>-<repetition>.txt` (a run made once, before the repetitions, has no repetition and
belongs to the first). This writes one `vxarchive/2` archive per repetition, `rep<n>.zip`, holding
each output as the log stream of the package step of the same id, line by line as the package's
step would print it:
- a step of a tool whose entrypoint runs the package's `.awk` program prints its text, then what
  that program prints over it, so the lines come from the program the package itself runs;
- a step that runs that program over an earlier step's output (`/vx/checks/<step>.log`) prints
  what it prints over that step's text;
- the `vx.step` line carries the exit code the run's transcript gives (`exit <code> <name>:`).

The archives record no phases, so a metric reads the whole archive. Nothing is invented: a step
the frozen run did not make is missing from its trial, and a case or metric reading it is
`inconclusive`. Needs `awk` and `zstd`.
"""
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

import yaml

STAMP = (1980, 1, 1, 0, 0, 0)


def awk_program(tool):
    for arg in tool.get("entrypoint") or []:
        for path in re.findall(r"/\S+\.awk", str(arg)):
            return path
    return None


def main(results, package, out):
    results, package, out = Path(results), Path(package), Path(out)
    doc = yaml.safe_load((package / "main.yaml").read_text())
    tools = doc["checks"]["tools"]
    steps = [s for s in doc["checks"]["steps"] if s.get("id") and s.get("tool")]

    def program(step):
        """The package file the step's awk program is mounted from, if its tool runs one."""
        inside = awk_program(tools[step["tool"]])
        return package / step["files"][inside] if inside else None

    exits = {}
    transcript = results / "transcript.txt"
    if transcript.is_file():
        for m in re.finditer(r"^exit (\d+) (\S+):", transcript.read_text(), re.M):
            exits[m.group(2)] = int(m.group(1))

    trials = {}
    for f in sorted((results / "out").glob("*.txt")):
        stem, rep = f.stem, 1
        head, _, tail = stem.rpartition("-")
        if head and tail.isdigit():
            stem, rep = head, int(tail)
        trials.setdefault(rep, {})[stem] = f

    out.mkdir(parents=True, exist_ok=True)
    for rep, runs in sorted(trials.items()):
        members = {}
        for s in steps:
            sid = s["id"]
            if sid in runs:
                text_of = runs[sid]
                lines = text_of.read_text(errors="replace").splitlines()
                prog = program(s)
                if prog:
                    lines += awk(prog, text_of)
                exit_code = exits.get(text_of.stem)
            else:
                # A step that reads an earlier step's output with the awk program.
                read = [a for a in s.get("args", []) if str(a).startswith("/vx/checks/")]
                prog = program(s)
                earlier = Path(read[0]).stem if read else None
                if not (prog and earlier in runs):
                    continue
                lines = awk(prog, runs[earlier])
                exit_code = 0
            if exit_code is not None:
                lines.append(json.dumps({"op": "vx.step", "exit": exit_code, "frozen": True}))
            records = "".join(
                json.dumps({"record": "log", "ts_ns": i, "entity": f"checks/{sid}",
                            "stream": "output", "line": line}) + "\n"
                for i, line in enumerate(lines)
            )
            members[f"logs/checks/{sid}.jsonl.zst"] = subprocess.run(
                ["zstd", "-q", "-19", "-c"], input=records.encode(), capture_output=True, check=True
            ).stdout
        metadata = {
            "archive": "vxarchive/2",
            "experiment_id": doc["id"],
            "frozen_from": str(results / "out"),
            "trial": {"trial_id": f"r{rep}-defaults", "repetition": rep, "arm": None,
                      "parameters": {}},
        }
        path = out / f"rep{rep}.zip"
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
            z.writestr(zipfile.ZipInfo("metadata.json", STAMP), json.dumps(metadata, indent=2))
            for name in sorted(members):
                z.writestr(zipfile.ZipInfo(name, STAMP), members[name])
        print(f"{path}: {len(members)} steps")


def awk(program, text_file):
    return subprocess.run(
        ["awk", "-f", str(program), str(text_file)], capture_output=True, text=True, check=True
    ).stdout.splitlines()


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
