"""vxedge 0.5.0 live release gates, driven through vxmcp as an agent would (vxedge #54).

Every check branches only on typed fields. Privileged steps (setcap, starting vxedged, the leak
check) go to the `vxpriv` tmux pane, where the owner's sudo is cached.

  python3 -I live.py <scenario> [iterations]
  scenarios: core | cancel | libvirt | traffic | all
"""
import json, os, subprocess, sys, threading, time

S = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, S)
from agent import Agent  # noqa: E402

BIN = os.environ["VX_BIN"]  # vxedged, vxmcp, vxcapsule, vxota, vxtelemetry, vxprobe, vxtraffic
SOCK = "/tmp/vxl.sock"
RT = "/tmp/vxr"
OUT = os.path.join(S, "live")
VXP = os.environ["VXPERIMENTS"]
V03 = f"{VXP}/vehicles/" + os.environ.get("VEHICLE", "vx-reference-sedan-02")  # the vehicle under test
V02 = f"{VXP}/vehicles/vx-vehicle-02"
E002 = f"{VXP}/experiments/exp-002-ws"
E001_TRIAL = os.environ.get("TRIAL", os.path.join(S, "exp-001-trial"))  # exp-001-ws + telemetry-service.yaml
os.makedirs(OUT, exist_ok=True)
LOG = open(os.path.join(OUT, "transcript.txt"), "a")
FAILS = []


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    LOG.write(line + "\n")
    LOG.flush()


def check(cond, what):
    log(("  PASS " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)
    return cond


# ---- privileged pane ----

_seq = [0]


def priv(cmd, timeout=600):
    """Runs `cmd` in the vxpriv pane; returns (rc, output)."""
    _seq[0] += 1
    tag = f"p{os.getpid()}-{_seq[0]}"
    out, rc = os.path.join(OUT, tag + ".out"), os.path.join(OUT, tag + ".rc")
    subprocess.run(["tmux", "send-keys", "-t", "vxpriv",
                    f"( {cmd} ) > {out} 2>&1; echo $? > {rc}", "Enter"], check=True)
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(rc) and open(rc).read().strip():
            return int(open(rc).read().strip()), open(out).read()
        time.sleep(0.5)
    raise RuntimeError(f"priv timed out: {cmd}")


def start_daemon():
    env = (f"VXEDGE_CAPSULE_BIN={BIN}/vxcapsule PATH={BIN}:$PATH")
    args = f"--listen unix://{SOCK} --runtime-dir {RT}"
    if os.environ.get("VX_CACHE"):  # a writable part cache, where the default one is not
        args += f" --cache-dir {os.environ['VX_CACHE']}"
    for flag, b in (("vxota", "vxota"), ("vxtelemetry", "vxtelemetry"), ("vxprobe", "vxprobe"), ("vxtraffic", "vxtraffic")):
        if os.path.exists(f"{BIN}/{b}"):
            args += f" --{flag}-bin {BIN}/{b}"
    priv(f"rm -f {SOCK}; env {env} {BIN}/vxedged {args} >> {OUT}/vxedged.log 2>&1 & "
         f"echo $! > {OUT}/vxedged.pid")
    for _ in range(60):
        if os.path.exists(SOCK):
            time.sleep(0.5)
            return
        time.sleep(0.5)
    raise RuntimeError("vxedged did not come up")


def stop_daemon():
    pid = open(f"{OUT}/vxedged.pid").read().strip()
    priv(f"kill {pid}; while kill -0 {pid} 2>/dev/null; do sleep 0.2; done")


def leaks():
    rc, out = priv(f"cd {V03} && ./check-leaks.sh")
    log("  leak check: " + " | ".join(out.strip().splitlines()))
    return rc == 0


# ---- agent helpers ----

def agent():
    return Agent(f"{BIN}/vxmcp", f"unix://{SOCK}", log)


def reason(sc):
    if not isinstance(sc, dict):
        log(f"  (untyped response: {sc!r:.300})")
        return f"UNTYPED:{sc!r:.80}"
    err = sc.get("error")
    return err.get("reason", "") if isinstance(err, dict) else ""


def watch(a, job_id, limit=1200):
    end = time.time() + limit
    while time.time() < end:
        ok, w = a.call("job_watch", {"id": job_id, "timeout_secs": 300})
        if not ok:
            return {"state": "WATCH_ERROR", "error": json.dumps(w)}
        if w["end"] in ("terminal", "stream_ended"):
            return w["job"]
    return {"state": "TIMEOUT"}


class EventTail(threading.Thread):
    """A second agent following events in 2s windows, resuming each from the last `lastId`."""

    def __init__(self):
        super().__init__(daemon=True)
        self.a, self.events, self.cursor, self.errors = agent(), [], "", []
        self.stop = threading.Event()

    def run(self):
        while not self.stop.is_set():
            args = {"duration_secs": 2}
            if self.cursor:
                args["after_id"] = self.cursor
            ok, sc = self.a.call("events_subscribe", args)
            if not ok:
                self.errors.append(reason(sc))
                return
            self.events += sc["events"]
            self.cursor = sc.get("lastId", self.cursor)

    def finish(self):
        self.stop.set()
        self.join(10)
        self.a.close()


def seqs_contiguous(events):
    """evt-<boot>-<seq>: one boot, no gap, no repeat."""
    ids = [e["id"] for e in events]
    boots = {i.rsplit("-", 1)[0] for i in ids}
    nums = [int(i.rsplit("-", 1)[1], 16) for i in ids]  # evt-<boot>-<seq:08x>
    return len(boots) <= 1 and nums == list(range(nums[0], nums[0] + len(nums))) if nums else True


# ---- scenarios ----

def core(i, restart=True):
    log(f"== core {i}: {os.path.basename(V03)} through vxmcp")
    a = agent()
    ok, caps = a.call("host_capabilities")
    avail = {b["backend"]: b["available"] for b in caps["backends"]}
    check(all(avail.values()), f"host_capabilities: every backend available {avail}")
    ok, plan = a.call("workspace_plan", {"workspace": V03})
    failed = [c["name"] for c in plan.get("hostChecks", []) if not c["passed"]]
    check(ok and plan.get("valid") and not failed, f"workspace_plan: valid, every check passed (failed: {failed}, problems: {plan.get('problems')})")

    tail = EventTail()
    tail.start()
    time.sleep(1)
    ok, job = a.call("vehicle_up", {"workspace": V03})
    check(ok and job["state"] in ("JOB_STATE_PENDING", "JOB_STATE_RUNNING"), "vehicle_up returns a job")
    jid = job["id"]
    ok, dup = a.call("vehicle_up", {"workspace": V03})
    check(ok and dup["id"] == jid, f"duplicate vehicle_up returns the running job ({dup.get('id')})")
    ok, other = a.call("vehicle_up", {"workspace": V03, "stages": ["gateway"]})
    check(not ok and reason(other) == "ERROR_REASON_BUSY", f"competing vehicle_up (other stages) refused BUSY ({reason(other)})")
    ok, other = a.call("experiment_up", {"workspace": E002})
    check(not ok and reason(other) == "ERROR_REASON_WRONG_WORKSPACE",
          f"another workspace's up refused while a run is up ({reason(other)})")
    end = watch(a, jid)
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"vehicle_up job {end['state']} {end.get('error', '')}")
    ok, kids = a.call("job_list", {"parent_job_id": jid})
    states = {j["kind"]: j["state"] for j in kids.get("jobs", [])}
    check(ok and states and all(s == "JOB_STATE_SUCCEEDED" for s in states.values()),
          f"child jobs all succeeded {states}")
    check(end.get("runId", "") != "", f"job carries run_id {end.get('runId')}")

    ok, runs = a.call("run_list")
    run_ids = [r["id"] for r in runs.get("runs", [])]
    check(ok and run_ids == [end.get("runId")], f"run_list holds the one run {run_ids}")
    states = [r["state"] for r in runs.get("runs", [])]
    check(states == ["RESOURCE_STATE_UP"], f"run_list reads the run UP once up succeeded {states}")

    ok, st = a.call("vehicle_status", {"workspace": V03})
    nodes = st.get("nodes", []) if ok else []
    bad = [(n.get("spec", {}).get("vxid"), n.get("status", {}).get("state")) for n in nodes
           if n.get("status", {}).get("state") != "RESOURCE_STATE_UP"]
    backends = sorted({n.get("spec", {}).get("backend", "") for n in nodes})
    check(ok and nodes and not bad, f"vehicle_status: every node UP (not: {bad}) backends {backends}")
    # Contract: `digest` is the sha256 of a published part and empty for a local one; every
    # part of vx-vehicle-03 is local, so kind and reference are what each node must carry.
    nopay = [n["spec"]["vxid"] for n in nodes
             if (n["spec"].get("payload") or {}).get("kind", "PAYLOAD_KIND_UNSPECIFIED")
             == "PAYLOAD_KIND_UNSPECIFIED"
             or (not n["spec"]["payload"].get("reference")
                 and n["spec"]["payload"]["kind"] != "PAYLOAD_KIND_HOST_PROCESS")]
    check(not nopay, f"vehicle_status: every node has a typed payload (missing: {nopay})")
    log("  payloads: " + "; ".join(f"{n['spec']['vxid']}={n['spec']['payload']['kind']}:"
                                   f"{n['spec']['payload']['reference']}" for n in nodes))

    ok, wrong = a.call("vehicle_status", {"workspace": V02})
    check(not ok and reason(wrong) in ("ERROR_REASON_WRONG_WORKSPACE", "ERROR_REASON_FOREIGN_WORKLOAD"),
          f"another vehicle's status refused ({reason(wrong)})")

    time.sleep(3)
    tail.finish()
    kinds = [e["kind"] for e in tail.events]
    check(not tail.errors, f"event tail resumed with no EVENTS_LOST ({tail.errors})")
    check("run.up" in kinds, "events include run.up")
    check(seqs_contiguous(tail.events), f"event ids contiguous across {len(tail.events)} events")
    check(all(e.get("runId") for e in tail.events if e["kind"] == "run.up"), "run.up carries run_id")
    cursor = tail.events[0]["id"] if tail.events else ""

    if restart:
        stop_daemon()
        start_daemon()
        a.close()
        a = agent()
        ok, runs2 = a.call("run_list")
        check(ok and [r["id"] for r in runs2["runs"]] == run_ids, "after restart: run still listed")
        check([r["state"] for r in runs2["runs"]] == ["RESOURCE_STATE_UP"], "after restart: run still UP")
        ok, st2 = a.call("vehicle_status", {"workspace": V03})
        bad2 = [n.get("spec", {}).get("vxid") for n in st2.get("nodes", [])
                if n.get("status", {}).get("state") != "RESOURCE_STATE_UP"]
        check(ok and not bad2, f"after restart: every node still UP (not: {bad2})")
        ok, gone = a.call("job_get", {"id": jid})
        check(not ok and reason(gone) == "ERROR_REASON_JOB_UNKNOWN", f"after restart: old job id JOB_UNKNOWN ({reason(gone)})")
        if cursor:
            ok, lost = a.call("events_subscribe", {"after_id": cursor, "duration_secs": 1})
            check(not ok and reason(lost) == "ERROR_REASON_EVENTS_LOST", f"after restart: old cursor EVENTS_LOST ({reason(lost)})")
        ok, zl = a.call("zone_list", {"run_id": "run-stale"})
        check(not ok and reason(zl) == "ERROR_REASON_RUN_MISMATCH", f"stale run_id refused ({reason(zl)})")

    ok, down = a.call("vehicle_down", {"workspace": V03})
    check(ok, "vehicle_down returns a job")
    ok, nc = a.call("job_cancel", {"id": down["id"]})
    check(not ok and reason(nc) == "ERROR_REASON_NOT_CANCELLABLE", f"cancelling a down refused ({reason(nc)})")
    end = watch(a, down["id"])
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"vehicle_down job {end['state']} {end.get('error', '')}")
    ok, runs3 = a.call("run_list")
    check(ok and runs3["runs"] == [], "run_list empty after down")
    a.close()
    check(leaks(), "host clean after down")
    return backends


def cancel():
    log("== cancel during up")
    a = agent()
    ok, job = a.call("vehicle_up", {"workspace": V03})
    time.sleep(4)
    ok, c = a.call("job_cancel", {"id": job["id"]})
    check(ok, f"job_cancel accepted ({c.get('state')})")
    end = watch(a, job["id"])
    check(end["state"] == "JOB_STATE_CANCELLED", f"cancelled up ends {end['state']}")
    ok, down = a.call("vehicle_down", {"workspace": V03})
    if not ok and reason(down) == "ERROR_REASON_NO_ACTIVE_RUN":
        log("  (nothing was recorded active; down not needed)")
    else:
        end = watch(a, down["id"])
        check(end["state"] == "JOB_STATE_SUCCEEDED", f"down after cancel {end['state']}")
    a.close()
    check(leaks(), "host clean after cancel and down")


def libvirt():
    log("== libvirt typed status on exp-002-ws")
    a = agent()
    ok, job = a.call("experiment_up", {"workspace": E002})
    end = watch(a, job["id"]) if ok else {"state": json.dumps(job)}
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-002 up {end['state']} {end.get('error', '')}")
    ok, zl = a.call("zone_list")
    nodes = [(n["spec"]["backend"], n["status"]["state"]) for n in zl.get("nodes", [])] if ok else []
    log(f"  zone nodes: {nodes}")
    ok2, st = a.call("experiment_status", {"workspace": E002})
    blob = json.dumps(st)
    check(("NODE_BACKEND_LIBVIRT", "RESOURCE_STATE_UP") in nodes,
          "a libvirt node reported UP with a typed backend")
    ok, down = a.call("experiment_down", {"workspace": E002})
    end = watch(a, down["id"])
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-002 down {end['state']}")
    a.close()
    check(leaks(), "host clean after exp-002")


def traffic():
    log("== traffic and collection on exp-001 trial copy")
    a = agent()
    # Gateway stage only, as exp-001's campaign runs it: a full up moves the source's veth peer
    # into the node netns (experiments/exp-001-ws/scripts/run.sh).
    ok, job = a.call("experiment_up", {"workspace": E001_TRIAL, "stages": ["gateway"]})
    end = watch(a, job["id"]) if ok else {"state": json.dumps(job)}
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-001 up --stage gateway {end['state']} {end.get('error', '')}")
    ok, s = a.call("svc_up", {"service_type": "telemetry", "workspace": E001_TRIAL})
    if ok:
        end = watch(a, s["id"])
        check(end["state"] == "JOB_STATE_SUCCEEDED", f"telemetry svc_up {end['state']} {end.get('error', '')}")
    else:
        check(False, f"telemetry svc_up refused {s}")
    rid = f"trial-{int(time.time())}"
    ok, t1 = a.call("traffic_up", {"workspace": E001_TRIAL, "request_id": rid})
    ok2, t2 = a.call("traffic_up", {"workspace": E001_TRIAL, "request_id": rid})
    check(ok and ok2 and t1["id"] == t2["id"], "traffic_up retry with the same request_id returns the same job")
    tj = watch(a, t1["id"])
    check(tj["state"] == "JOB_STATE_SUCCEEDED", f"traffic_up job {tj['state']} {tj.get('error', '')}")
    seen = set()
    for _ in range(120):
        ok, ts = a.call("traffic_status", {"workspace": E001_TRIAL})
        st = {p["id"]: p["state"] for p in ts.get("profiles", [])}
        seen |= set(st.values())
        if st and all(v != "TRAFFIC_PROFILE_STATE_RUNNING" for v in st.values()):
            break
        time.sleep(5)
    log(f"  traffic states seen: {sorted(map(str, seen))}; last {ts}")
    check("TRAFFIC_PROFILE_STATE_RUNNING" in seen and "TRAFFIC_PROFILE_STATE_FINISHED" in seen,
          "traffic_status moved from running to finished")
    ok, c = a.call("telemetry_collect", {"workspace": E001_TRIAL})
    end = watch(a, c["id"]) if ok else {"state": json.dumps(c)}
    art = end.get("artifact") or {}
    check(end["state"] == "JOB_STATE_SUCCEEDED" and art.get("path"), f"collect {end['state']} artifact {art}")
    if art.get("path") and os.path.exists(art["path"]):
        import hashlib
        h = hashlib.sha256(open(art["path"], "rb").read()).hexdigest()
        check(h == art.get("sha256"), "archive sha256 matches Job.artifact")
        import zipfile
        with zipfile.ZipFile(art["path"]) as z:
            meta = json.loads(z.read("metadata.json"))
            names = z.namelist()
        log(f"  archive members {names}; metadata keys {sorted(meta)}")
        check("workspace/main.yaml" in names and meta, "archive holds the workspace and its metadata")
        log(f"  archive at {art['path']}")
    ok, d = a.call("svc_down", {"service_type": "telemetry"})
    if ok:
        watch(a, d["id"])
    ok, down = a.call("experiment_down", {"workspace": E001_TRIAL, "stages": ["gateway"]})
    end = watch(a, down["id"])
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-001 down {end['state']}")
    a.close()
    check(leaks(), "host clean after exp-001")


def main():
    scen = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    log(f"#### {scen} x{n}")
    check(leaks(), "host clean before start")
    start_daemon()
    try:
        if scen in ("core", "all"):
            seen = set()
            for i in range(1, n + 1):
                seen |= set(core(i))
            log(f"backends covered by core: {sorted(seen)}")
        if scen in ("cancel", "all"):
            cancel()
        if scen in ("libvirt", "all"):
            libvirt()
        if scen in ("traffic", "all"):
            traffic()
    finally:
        stop_daemon()
    log(f"#### {scen}: {len(FAILS)} failure(s)")
    for f in FAILS:
        log("   - " + f)
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
