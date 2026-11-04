#!/usr/bin/env python3
"""Write exp-016's kuksa-perf test data from the VSS 6.0 metadata the databroker ships.

    python3 -I make-data.py vss_release_6.0.json

vss_release_6.0.json is the file in the pinned databroker image, also at
https://github.com/eclipse-kuksa/kuksa-databroker/blob/0.7.1/data/vss-core/vss_release_6.0.json.
Every path is checked against it, so a signal missing from 6.0 fails here, not in a run.
"""
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
vss = json.load(open(sys.argv[1]))


def leaves(node, prefix=""):
    for key, value in node.items():
        path = f"{prefix}.{key}" if prefix else key
        if "children" in value:
            yield from leaves(value["children"], path)
        else:
            yield path, value.get("type"), value.get("datatype")


signals = {p: (t, dt) for p, t, dt in leaves(vss)}
SENSORS = ["Vehicle.Speed"]
for p in SENSORS:
    assert signals[p][0] == "sensor", p
BOOL_ACTUATORS = sorted(p for p, (t, dt) in signals.items() if t == "actuator" and dt == "boolean")


def write(name, groups, cycle_ms=10):
    doc = {"groups": [{"group_name": f"Group {i + 1}", "cycle_time_ms": cycle_ms,
                       "signals": [{"path": p} for p in g]} for i, g in enumerate(groups)]}
    (here / name).write_text(json.dumps(doc, indent=2) + "\n")
    print(name, len(groups), "groups,", sum(map(len, groups)), "signals")


write("publish-1.json", [SENSORS[:1]])
# Issue 233's axis: providers (groups) by actuator ids per provider. kuksa-perf sends each group's
# ids as one BatchActuate every cycle (100 ms here), so 240 ids are 2,400 actuations a second
# however they are split: 10 batches of 240, or 160 batches of 15.
for groups, per in ((1, 1), (1, 240), (16, 1), (16, 15)):
    ids = BOOL_ACTUATORS[: groups * per]
    write(f"actuate-g{groups}-k{per}.json", [ids[i * per:(i + 1) * per] for i in range(groups)], cycle_ms=100)
