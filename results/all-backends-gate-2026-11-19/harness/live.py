"""The vxAPI core gate on a vehicle with every node backend, driven through vxmcp as an agent would.

The 2026-11-11 harness (results/all-backends-gate-2026-11-11), brought up to several runs per host
(vxedge 0.31.0 and later) and the fleet view (0.33.0, vxmcp 0.7.0): after `up` and again after a daemon
restart, every backend is present, the flow checks pass, each pinned node's threads may run only on its
pinned CPU, and each qemu-mcu node reports `armv7m` under `tcg`. A second vehicle comes up in a slot of
its own, `run_status` reads both runs, and `run_down` with `all` takes both down as one job. After it,
the attach node's interface is back with no master. `traffic` runs exp-001's traffic with its zones up.
Every check branches only on typed fields or on what the kernel reports.

No step needs sudo here: `vxedged` holds `cap_net_admin,cap_sys_admin` as file capabilities, set
beforehand by an administrator, who also creates the attach node's tap. Where a `vxhost` lock tool is
installed, the harness first checks that this session holds the host.

  python3 -I live.py <scenario> [iterations]
  scenarios: core | cancel | libvirt | traffic | all
"""
import glob, json, os, re, shutil, subprocess, sys, threading, time

S = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, S)
from agent import Agent  # noqa: E402

BIN = os.environ["VX_BIN"]  # vxedged, vxmcp, vxcapsule, vxota, vxtelemetry, vxprobe, vxtraffic
RT = f"/tmp/vxr-{os.getpid()}"  # fresh per invocation: a stale runtime dir's run records would be restored
SOCK = f"{RT}/vxl.sock"
os.makedirs(RT)
LOCK = os.environ.get("VXHOST_SESSION", "REMOTE-VXPERIMENT")
OUT = os.path.join(S, "live")
VXP = os.environ["VXPERIMENTS"]
V03 = f"{VXP}/vehicles/" + os.environ.get("VEHICLE", "vx-vehicle-04")  # the vehicle under test
OTHER = os.environ.get("OTHER_VXPERIMENTS", VXP)  # where the second workspaces live, when the vehicle is elsewhere
V02 = f"{OTHER}/vehicles/vx-vehicle-02"
E002 = f"{OTHER}/experiments/exp-002-ws"
E001_TRIAL = os.environ.get("TRIAL", "")  # a copy of exp-001-ws, which declares its telemetry service
os.makedirs(OUT, exist_ok=True)
LOG = open(os.path.join(OUT, "transcript.txt"), "a")
FAILS = []

# vx-vehicle-04's pinned nodes and the process that is each one, found from what the backend leaves.
PINNED = {"zone-fl": 4, "zone-fr": 5, "zone-rr": 6, "sensor-rr": 7, "ecu-mcu-frt": 8}
MCU = ("ecu-mcu-frt", "ecu-mcu-zep")
ATTACH_IF = "at-ivi1"
BACKENDS = {"NODE_BACKEND_CONTAINER", "NODE_BACKEND_QEMU_MICROVM", "NODE_BACKEND_CLOUD_HYPERVISOR",
            "NODE_BACKEND_LIBVIRT", "NODE_BACKEND_WASM_CAPSULE", "NODE_BACKEND_ATTACH", "NODE_BACKEND_QEMU_MCU"}


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


# ---- host ----

def sh(cmd, timeout=600):
    """Runs `cmd` in bash; returns (rc, output)."""
    p = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout + p.stderr


def start_daemon():
    env = (f"VXEDGE_CAPSULE_BIN={BIN}/vxcapsule PATH={BIN}:$PATH")
    # The daemon's exporter on a free loopback port: its fixed default may be taken on a shared host, and
    # without it a workspace whose telemetry declares no targets of its own has nothing to scrape.
    args = f"--listen unix://{SOCK} --runtime-dir {RT} --metrics-listen 127.0.0.1:0"
    if os.environ.get("VX_CACHE"):  # a writable part cache, where the default one is not
        args += f" --cache-dir {os.environ['VX_CACHE']}"
    for flag, b in (("vxota", "vxota"), ("vxtelemetry", "vxtelemetry"), ("vxprobe", "vxprobe"), ("vxtraffic", "vxtraffic")):
        if os.path.exists(f"{BIN}/{b}"):
            args += f" --{flag}-bin {BIN}/{b}"
    sh(f"rm -f {SOCK}; env {env} setsid {BIN}/vxedged {args} >> {OUT}/vxedged.log 2>&1 < /dev/null & "
       f"echo $! > {OUT}/vxedged.pid")
    for _ in range(60):
        if os.path.exists(SOCK):
            time.sleep(0.5)
            return
        time.sleep(0.5)
    raise RuntimeError("vxedged did not come up")


def stop_daemon():
    pid = open(f"{OUT}/vxedged.pid").read().strip()
    sh(f"kill {pid}; while kill -0 {pid} 2>/dev/null; do sleep 0.2; done")


def leaks():
    """vx-vehicle-04's leak check, plus the slots' uplink namespaces (`vxh<s>`). Its nft line needs
    sudo, which this harness does not hold, so nft is checked by the owner's script after the run."""
    rc, out = sh(f"cd {V03} && ./check-leaks.sh")
    lines = [l for l in out.strip().splitlines() if not l.startswith("nft:")]
    vxh = sh("ip netns list | grep -E '^vxh' || true")[1].strip()
    log("  leak check: " + " | ".join(lines) + f" | vxh netns: {vxh or 'none'} | nft: by the owner's script")
    return rc == 0 and not vxh


# ---- vx-vehicle-04's own checks ----

def node_pid(node, slot="0"):
    """The process that is `node` in slot `slot`, found by scanning /proc: the guest's `vx.node=` and
    `vx.slot=` words (qemu-microvm, qemu-mcu), libvirt's `guest=vx<s>-<node>`, cloud-hypervisor's API
    socket `vx<s>-<node>.ch.sock`, or vxcapsule's `--node`."""
    found = []
    for d in glob.glob("/proc/[0-9]*"):
        try:
            argv = open(f"{d}/cmdline", "rb").read().decode(errors="replace").split("\0")
        except OSError:
            continue
        exe = os.path.basename(argv[0]) if argv else ""
        words = " ".join(argv)
        if exe.startswith("qemu-system") and f"guest=vx{slot}-{node}," in words + ",":
            found.append(int(d[6:]))
        elif exe == "cloud-hypervisor" and re.search(rf"/vx{slot}-{re.escape(node)}\.ch\.sock(\s|$)", words):
            found.append(int(d[6:]))  # its kernel line reaches the VMM over the API; the socket names it
        elif exe.startswith("qemu-system") and (
                re.search(rf"vx\.node={re.escape(node)}(\s|,|$)", words)
                and re.search(rf"vx\.slot={slot}(\s|,|$)", words)):
            found.append(int(d[6:]))
        elif exe == "vxcapsule" and argv[1:] and "--node" in argv and argv[argv.index("--node") + 1:][:1] == [node]:
            found.append(int(d[6:]))
    if len(found) != 1:
        log(f"  ({node}: {len(found)} matching processes {found})")
    return found[0] if len(found) == 1 else None


def thread_cpus(pid):
    """Every thread of `pid` and the CPUs it may run on (`Cpus_allowed_list`)."""
    found = {}
    for st in glob.glob(f"/proc/{pid}/task/*/status"):
        try:
            text = open(st).read()
        except OSError:
            continue
        name = next((l.split(None, 1)[1].strip() for l in text.splitlines() if l.startswith("Name:")), "?")
        cpus = next((l.split(None, 1)[1].strip() for l in text.splitlines() if l.startswith("Cpus_allowed_list:")), "?")
        found.setdefault(cpus, []).append(name)
    return found


def link_master(name):
    out = subprocess.run(["ip", "-j", "link", "show", name], capture_output=True, text=True).stdout
    try:
        return json.loads(out)[0].get("master")
    except (ValueError, IndexError):
        return "missing"


def platform(when, backends, nodes):
    check(BACKENDS <= set(backends), f"[{when}] every backend is up: {sorted(set(backends))}")
    for node in MCU:
        # NodeStatus carries arch and acceleration beside status and spec, not inside them.
        st = next((n for n in nodes if n.get("spec", {}).get("vxid") == node), {})
        check(st.get("arch") == "armv7m" and st.get("acceleration") == "tcg",
              f"[{when}] {node}: qemu-mcu reports arch {st.get('arch')!r}, acceleration {st.get('acceleration')!r}")
    for node, cpu in PINNED.items():
        pid = node_pid(node)
        cpus = thread_cpus(pid) if pid else {}
        threads = sum(len(v) for v in cpus.values())
        check(pid is not None and set(cpus) == {str(cpu)},
              f"[{when}] {node}: all {threads} threads may run only on CPU {cpu} "
              f"({ {k: len(v) for k, v in cpus.items()} })")
    master = link_master(ATTACH_IF)
    check(master not in (None, "missing"), f"[{when}] attach interface {ATTACH_IF} adopted (master {master})")
    p = subprocess.run([f"{V03}/check-flows.sh"], capture_output=True, text=True, timeout=900)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if l.startswith(("PASS", "FAIL"))]
    log(f"  [{when}] flows: " + " | ".join(lines))
    check(p.returncode == 0 and len(lines) == 19 and all(l.startswith("PASS") for l in lines),
          f"[{when}] check-flows.sh: {len(lines)} checks, rc={p.returncode}")


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

def second_up(a, when):
    """Brings vx-vehicle-02 up beside the vehicle under test; returns its run id."""
    ok, job = a.call("vehicle_up", {"workspace": V02})
    end = watch(a, job["id"]) if ok else {"state": json.dumps(job)}
    rid = end.get("runId", "")
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"[{when}] second vehicle up {end['state']} {end.get('error', '')}")
    ok, runs = a.call("run_list")
    slots = {r["id"]: r.get("instance") for r in runs.get("runs", [])} if ok else {}
    check(len(slots) == 2 and slots.get(rid) not in (None, "", "0") and len(set(slots.values())) == 2,
          f"[{when}] second vehicle in a slot of its own {slots}")
    return rid

def fleet_view(a, run0, run1, nodes):
    """The fleet view reads both runs, by default and by name; the second goes down by run_id."""
    ok, rs = a.call("run_status", {})
    entries = rs.get("runs", []) if ok else []
    got = {e.get("run", {}).get("id"): e for e in entries}
    check(ok and set(got) == {run0, run1}, f"run_status reads both runs {sorted(map(str, got))}")
    for rid in (run0, run1):
        e = got.get(rid, {})
        state = (e.get("status") or {}).get("state")
        check(state == "RESOURCE_STATE_UP" and e.get("errorReason") in (None, "", "ERROR_REASON_UNSPECIFIED"),
              f"run_status: {rid} rollup {state}, error {e.get('errorReason')}")
    check(len(got.get(run0, {}).get("nodes", [])) == len(nodes),
          f"run_status: {run0} carries its {len(nodes)} typed nodes ({len(got.get(run0, {}).get('nodes', []))})")
    ok, rs = a.call("run_status", {"run_ids": [run1, "run-stale"]})
    e = {x.get("run", {}).get("id"): x for x in rs.get("runs", [])} if ok else {}
    check(ok and (e.get(run1, {}).get("status") or {}).get("state") == "RESOURCE_STATE_UP"
          and e.get("run-stale", {}).get("errorReason") == "ERROR_REASON_RUN_MISMATCH"
          and not e.get("run-stale", {}).get("status"),
          f"run_status by name: {run1} UP, run-stale an entry with RUN_MISMATCH "
          f"({e.get('run-stale', {}).get('errorReason')})")
    ok, d = a.call("vehicle_down", {"workspace": V02, "run_id": run1})
    end1 = watch(a, d["id"]) if ok else {"state": json.dumps(d)}
    check(end1["state"] == "JOB_STATE_SUCCEEDED", f"vehicle_down of {run1} by run_id {end1['state']} {end1.get('error', '')}")
    ok, runs1 = a.call("run_list")
    check(ok and [r["id"] for r in runs1.get("runs", [])] == [run0], "run_list holds this run alone again")

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
    # Runs coexist, but their `up` and `down` do not overlap: another workspace's `up` waits its turn.
    ok, other = a.call("experiment_up", {"workspace": E002})
    check(not ok and reason(other) == "ERROR_REASON_BUSY",
          f"another workspace's up refused BUSY while this up runs ({reason(other)})")
    if ok:  # it started a run of its own: take it down, so the host stays as the gate expects
        watch(a, other["id"])
        ok2, d = a.call("experiment_down", {"workspace": E002})
        if ok2:
            watch(a, d["id"])
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
    # Contract: `digest` is the sha256 of a published part and empty for a local one (vx-vehicle-04's
    # attach adapter), so kind and reference are what each node must carry.
    nopay = [n["spec"]["vxid"] for n in nodes
             if (n["spec"].get("payload") or {}).get("kind", "PAYLOAD_KIND_UNSPECIFIED")
             == "PAYLOAD_KIND_UNSPECIFIED"
             or (not n["spec"]["payload"].get("reference")
                 and n["spec"]["payload"]["kind"] != "PAYLOAD_KIND_HOST_PROCESS")]
    check(not nopay, f"vehicle_status: every node has a typed payload (missing: {nopay})")
    log("  payloads: " + "; ".join(f"{n['spec']['vxid']}={n['spec']['payload']['kind']}:"
                                   f"{n['spec']['payload']['reference']}" for n in nodes))
    platform("up", backends, nodes)

    # Another vehicle has no run: its status answers so, and never reads this run.
    ok, other = a.call("vehicle_status", {"workspace": V02})
    check(not ok and reason(other) == "ERROR_REASON_NO_ACTIVE_RUN",
          f"another vehicle's status: no run ({reason(other)})")

    # A second vehicle comes up in a slot of its own; the fleet view reads both runs.
    run0 = end.get("runId")
    run1 = second_up(a, "first")
    if run1:
        fleet_view(a, run0, run1, nodes)
    else:
        log("  [first] no second run: fleet-view checks skipped")

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
        platform("restart", sorted({n.get("spec", {}).get("backend", "") for n in st2.get("nodes", [])}),
                 st2.get("nodes", []))
        ok, gone = a.call("job_get", {"id": jid})
        check(not ok and reason(gone) == "ERROR_REASON_JOB_UNKNOWN", f"after restart: old job id JOB_UNKNOWN ({reason(gone)})")
        if cursor:
            ok, lost = a.call("events_subscribe", {"after_id": cursor, "duration_secs": 1})
            check(not ok and reason(lost) == "ERROR_REASON_EVENTS_LOST", f"after restart: old cursor EVENTS_LOST ({reason(lost)})")
        ok, zl = a.call("zone_list", {"run_id": "run-stale"})
        check(not ok and reason(zl) == "ERROR_REASON_RUN_MISMATCH", f"stale run_id refused ({reason(zl)})")

    # Both vehicles up again, then cleared as one job.
    run1 = second_up(a, "again")
    asked = len(a.asked)
    ok, down = a.call("run_down", {"all": True})
    check(ok and down.get("kind") == "run.down", f"run_down all returns a run.down job ({down.get('kind')})")
    question = a.asked[asked][1] if len(a.asked) > asked else ""
    check(run0 in question and run1 in question, "run_down asked the human, naming both runs up")
    ok, nc = a.call("job_cancel", {"id": down["id"]})
    check(not ok and reason(nc) == "ERROR_REASON_NOT_CANCELLABLE", f"cancelling a down refused ({reason(nc)})")
    end = watch(a, down["id"])
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"run_down job {end['state']} {end.get('error', '')}")
    ok, kids = a.call("job_list", {"parent_job_id": down["id"]})
    kids = kids.get("jobs", []) if ok else []
    by_run = {j.get("runId"): (j["kind"], j["state"]) for j in kids}
    check(by_run == {run0: ("vehicle.down", "JOB_STATE_SUCCEEDED"), run1: ("vehicle.down", "JOB_STATE_SUCCEEDED")},
          f"run_down: one vehicle.down child per run, each succeeded {by_run}")
    ok, runs3 = a.call("run_list")
    check(ok and runs3["runs"] == [], "run_list empty after down")
    a.close()
    check(link_master(ATTACH_IF) is None, f"attach interface {ATTACH_IF} returned with no master after down")
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
    log("== traffic and collection on a copy of exp-001-ws, its zones up")
    a = agent()
    # A full up: since vxedge 0.32.0 the traffic's far side runs in the run's own uplink namespace,
    # so traffic crosses the bridge and the shaped uplink with the zones up.
    ok, job = a.call("experiment_up", {"workspace": E001_TRIAL})
    end = watch(a, job["id"]) if ok else {"state": json.dumps(job)}
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-001 up {end['state']} {end.get('error', '')}")
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
        check("package/main.yaml" in names and meta, "archive holds the package and its metadata")
        rc, out = sh(f"{BIN}/vxtelemetry verify {art['path']}")
        check(rc == 0, f"vxtelemetry verify: {out.strip().splitlines()[-1] if out.strip() else rc}")
        log(f"  archive at {art['path']}")
    ok, d = a.call("svc_down", {"service_type": "telemetry"})
    if ok:
        watch(a, d["id"])
    ok, down = a.call("experiment_down", {"workspace": E001_TRIAL})
    end = watch(a, down["id"])
    check(end["state"] == "JOB_STATE_SUCCEEDED", f"exp-001 down {end['state']}")
    a.close()
    check(leaks(), "host clean after exp-001")


def main():
    scen = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    log(f"#### {scen} x{n}")
    if shutil.which("vxhost"):
        rc, out = sh(f"vxhost check {LOCK}")
        if rc != 0:
            sys.exit(f"host lock: {out.strip()}")
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
    finally:  # whatever happened, no run outlives the gate
        rc, out = sh(f"{BIN}/vxedge --endpoint unix://{SOCK} runs down --all", timeout=900)
        log(f"teardown: runs down --all rc={rc} {out.strip().splitlines()[-1] if out.strip() else ''}")
        stop_daemon()
    log(f"#### {scen}: {len(FAILS)} failure(s)")
    for f in FAILS:
        log("   - " + f)
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
