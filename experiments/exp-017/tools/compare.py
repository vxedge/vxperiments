#!/usr/bin/env python3
"""Compare the signals a databroker lists with the VSS file it was given.

    python3 -I compare.py <vss.json> <kv2 list output>

Prints one JSON line: the leaf count in the file, the count the broker lists, every path in one and
not the other, every path whose entry or data type differs, and `result`: `same` or `differ`
(`no-list` when the output holds no list). Exits non-zero unless they are the same.
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


def main():
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
        print(json.dumps({"op": "compare", "result": "no-list"}), flush=True)
        return 2
    missing = sorted(set(vss) - set(listed))
    extra = sorted(set(listed) - set(vss))
    typed = []
    for p in sorted(set(vss) & set(listed)):
        want_e = "ENTRY_TYPE_" + vss[p]["type"].upper()
        dt = vss[p]["datatype"]
        base = dt.rstrip("[]")
        want_t = "DATA_TYPE_" + TYPES.get(base, base.upper()) + ("_ARRAY" if dt.endswith("[]") else "")
        if listed[p] != (want_e, want_t):
            typed.append(f"{p}: file {want_e} {want_t}, broker {listed[p][0]} {listed[p][1]}")
    same = not (missing or extra or typed)
    print(json.dumps({
        "op": "compare", "result": "same" if same else "differ", "leaves": len(vss),
        "listed": len(listed), "missing": missing, "extra": extra, "typed": typed,
    }, sort_keys=True), flush=True)
    return 0 if same else 1


if __name__ == "__main__":
    sys.exit(main())
