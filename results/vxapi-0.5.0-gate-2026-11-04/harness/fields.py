"""The fields the 0.5.0 gate did not check live, and the 0.5.2 fixes, through vxmcp."""
import json, os, sys, threading, time, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import live
from live import check, log, reason, watch

V03, TRIAL = live.V03, live.E001_TRIAL


def collect_kinds(kinds, seconds, out):
    a = live.agent()
    ok, sc = a.call("events_subscribe", {"kinds": kinds, "duration_secs": seconds})
    out.append((ok, sc))
    a.close()


log("#### fields")
check(live.leaks(), "host clean before start")
live.start_daemon()
a = live.agent()

ok, caps = a.call("host_capabilities")
check(ok and "gpu" in caps, f"host_capabilities carries gpu ({caps.get('gpu')})")
cont = [b for b in caps["backends"] if b["backend"] == "NODE_BACKEND_CONTAINER"][0]
check(cont["available"], f"container backend available where Podman answers ({cont})")
ok, plan = a.call("workspace_plan", {"workspace": V03})
names = {c["name"]: c["passed"] for c in plan["hostChecks"]}
check(names.get("backend container") is True, f"Plan's backend checks come from the same probe {names}")

got = []
t = threading.Thread(target=collect_kinds, args=(["zone"], 30, got))
t.start()
time.sleep(1)
ok, job = a.call("vehicle_up", {"workspace": V03})
end = watch(a, job["id"])
check(end["state"] == "JOB_STATE_SUCCEEDED", f"vehicle_up {end['state']}")
t.join(60)
ok, ev = got[0]
kinds = sorted({e["kind"] for e in ev["events"]})
check(ok and kinds and all(k.startswith("zone.") for k in kinds), f"events kinds=[zone] is a family filter: {kinds}")

ok, p1 = a.call("job_list", {"page_size": 1})
tok = p1.get("nextPageToken", "")
ok2, p2 = a.call("job_list", {"page_size": 1, "page_token": tok})
check(ok and len(p1["jobs"]) == 1 and tok and ok2 and p2["jobs"] and p2["jobs"][0]["id"] != p1["jobs"][0]["id"],
      f"job_list pages: {p1['jobs'][0]['id']} then {p2['jobs'][0]['id'] if p2.get('jobs') else None}")
ok, f = a.call("job_list", {"states": ["succeeded"], "kind": "vehicle.up"})
check(ok and f["jobs"] and all(j["kind"] == "vehicle.up" and j["state"] == "JOB_STATE_SUCCEEDED" for j in f["jobs"]),
      f"job_list filters by state and kind ({len(f.get('jobs', []))} jobs)")

ok, st = a.call("vehicle_status", {"workspace": V03})
nodes = st["nodes"]
bad = [n["spec"]["vxid"] for n in nodes if not (n["spec"]["port"] and n["spec"]["peer"] and n["spec"]["vlan"])]
check(not bad, f"NodeSpec port, peer and vlan set on every node (missing: {bad})")
obs = [int(n["status"]["observedUnixMs"]) for n in nodes]
check(all(o > 0 for o in obs), "observedUnixMs set on every node")
since = [int(n["status"]["sinceUnixMs"]) for n in nodes]
log(f"  sinceUnixMs: {since} (0 means the transition time is unknown)")

ok, svc = a.call("svc_status", {"service_type": "ota", "workspace": V03})
check(ok and svc["state"] == "RESOURCE_STATE_UP" and "hpc1" in svc["detail"],
      f"svc_status with a workspace reports the placed service ({svc.get('state')}: {svc.get('detail')})")

t0 = time.time()
ok, runs = a.call("run_list")
dt = time.time() - t0
check(ok and [r["state"] for r in runs["runs"]] == ["RESOURCE_STATE_UP"], f"run_list UP in {dt:.1f}s")

ok, d = a.call("vehicle_down", {"workspace": V03})
check(watch(a, d["id"])["state"] == "JOB_STATE_SUCCEEDED", "vehicle_down")
check(live.leaks(), "host clean after vx-vehicle-03")

# Traffic needs the source on the host: a full up is refused before any job starts.
ok, j = a.call("experiment_up", {"workspace": TRIAL})
check(watch(a, j["id"])["state"] == "JOB_STATE_SUCCEEDED", "exp-001 full up")
ok, r = a.call("traffic_up", {"workspace": TRIAL})
check(not ok and reason(r) == "ERROR_REASON_ENDPOINT_NOT_ON_HOST",
      f"traffic_up after a full up refused before a job ({reason(r)})")
ok, d = a.call("experiment_down", {"workspace": TRIAL})
check(watch(a, d["id"])["state"] == "JOB_STATE_SUCCEEDED", "exp-001 down")

ok, j = a.call("experiment_up", {"workspace": TRIAL, "stages": ["gateway"]})
check(watch(a, j["id"])["state"] == "JOB_STATE_SUCCEEDED", "exp-001 up --stage gateway")
ok, s = a.call("svc_up", {"service_type": "telemetry", "workspace": TRIAL})
watch(a, s["id"])
ok, t1 = a.call("traffic_up", {"workspace": TRIAL})
check(ok and watch(a, t1["id"])["state"] == "JOB_STATE_SUCCEEDED", "traffic_up on the gateway stage")
time.sleep(5)
ok, c = a.call("telemetry_collect", {"workspace": TRIAL, "out_path": "results/fields-check.zip"})
end = watch(a, c["id"])
art = end.get("artifact") or {}
check(art.get("path", "").endswith("/results/fields-check.zip"), f"Collect honours out_path ({art.get('path')})")
if os.path.exists(art.get("path", "")):
    with zipfile.ZipFile(art["path"]) as z:
        digests = json.loads(z.read("metadata.json")).get("image_digests", {})
    log(f"  image_digests: {digests}")
    check(digests and all(v.startswith("host-process") for k, v in digests.items() if k.startswith("local/")),
          "local/ parts recorded as host processes")
ok, td = a.call("traffic_down", {"workspace": TRIAL})
watch(a, td["id"])
ok, sd = a.call("svc_down", {"service_type": "telemetry"})
watch(a, sd["id"])
ok, d = a.call("experiment_down", {"workspace": TRIAL, "stages": ["gateway"]})
check(watch(a, d["id"])["state"] == "JOB_STATE_SUCCEEDED", "exp-001 down --stage gateway")
a.close()
live.stop_daemon()
check(live.leaks(), "host clean after exp-001")
log(f"#### fields: {len(live.FAILS)} failure(s)")
for f in live.FAILS:
    log("   - " + f)
sys.exit(1 if live.FAILS else 0)
