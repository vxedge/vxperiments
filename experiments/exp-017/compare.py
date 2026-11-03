#!/usr/bin/env python3
"""Compare the signals a databroker lists with the VSS file it was given.

    python3 -I compare.py <vss.json> <kv2 list output>

Prints the leaf count in the file, the count the broker lists, and every path or type that
differs. Exits non-zero if they differ.
"""
import json
import sys

TYPES = {"boolean": "BOOLEAN"}


def leaves(node, prefix=""):
    for key, value in node.items():
        path = f"{prefix}.{key}" if prefix else key
        if "children" in value:
            yield from leaves(value["children"], path)
        else:
            yield path, value


vss = dict(leaves(json.load(open(sys.argv[1]))))
listed = None
for line in open(sys.argv[2]):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("op") == "list" and d.get("result") == "ok":
        listed = {p: (e, t) for p, e, t in d["signals"]}
if listed is None:
    print("no list output")
    sys.exit(2)
print(f"file: {len(vss)} leaves, broker: {len(listed)} signals")
missing = sorted(set(vss) - set(listed))
extra = sorted(set(listed) - set(vss))
typed = []
for p in sorted(set(vss) & set(listed)):
    want_e = "ENTRY_TYPE_" + vss[p]["type"].upper()
    dt = vss[p]["datatype"]
    want_t = "DATA_TYPE_" + (TYPES.get(dt.rstrip("[]"), dt.rstrip("[]").upper())) + ("_ARRAY" if dt.endswith("[]") else "")
    if listed[p] != (want_e, want_t):
        typed.append(f"{p}: file {want_e} {want_t}, broker {listed[p][0]} {listed[p][1]}")
for name, rows in (("in the file, not listed", missing), ("listed, not in the file", extra), ("type differs", typed)):
    print(f"{name}: {len(rows)}")
    for r in rows:
        print("  " + r)
sys.exit(1 if missing or extra or typed else 0)
