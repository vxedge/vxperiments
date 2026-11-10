"""Shared plumbing for the done-means gate (X8.4), from the 2026-11-04 gate's live.py: a
privileged pane for setcap, the daemon and the leak check, and agents that talk to vxmcp only."""
import json, os, subprocess, sys, time

S = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, S)
from agent import Agent  # noqa: E402

BIN = os.environ["VX_BIN"]          # vxedged, vxedge, vxmcp, vxtelemetry, vxprobe, vxtraffic
WORK = os.environ["GATE_WORK"]      # scratch: socket, runtime and cache folders, packages
PANE = os.environ.get("VX_PANE", "vxpriv")
VXP = os.environ["VXPERIMENTS"]
SOCK = f"{WORK}/d.sock"
OUT = os.path.join(S, "..", "live")
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


_seq = [0]


def priv(cmd, timeout=600):
    """Runs `cmd` in the privileged pane; returns (rc, output)."""
    _seq[0] += 1
    tag = f"{WORK}/priv-{os.getpid()}-{_seq[0]}"
    subprocess.run(["tmux", "send-keys", "-t", PANE,
                    f"( {cmd} ) > {tag}.out 2>&1; echo $? > {tag}.rc", "Enter"], check=True)
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(tag + ".rc") and open(tag + ".rc").read().strip():
            return int(open(tag + ".rc").read().strip()), open(tag + ".out").read()
        time.sleep(0.5)
    raise RuntimeError(f"priv timed out: {cmd}")


def start_daemon(trust_policy=None):
    rc, out = priv(f"sudo -n setcap cap_net_admin,cap_sys_admin+ep {BIN}/vxedged")
    if rc:
        raise RuntimeError(f"setcap failed: {out}")
    extra = f" --trust-policy {trust_policy}" if trust_policy else ""
    args = (f"--listen unix://{SOCK} --runtime-dir {WORK}/rt --cache-dir {WORK}/cache "
            f"--vxtelemetry-bin {BIN}/vxtelemetry --vxprobe-bin {BIN}/vxprobe "
            f"--vxtraffic-bin {BIN}/vxtraffic{extra}")
    priv(f"rm -f {SOCK}; env PATH={BIN}:$PATH {BIN}/vxedged {args} >> {WORK}/vxedged.log 2>&1 & "
         f"echo $! > {WORK}/vxedged.pid")
    for _ in range(60):
        if os.path.exists(SOCK):
            time.sleep(0.5)
            return
        time.sleep(0.5)
    raise RuntimeError("vxedged did not come up")


def stop_daemon():
    pid = open(f"{WORK}/vxedged.pid").read().strip()
    priv(f"kill {pid}; while kill -0 {pid} 2>/dev/null; do sleep 0.2; done")


def leaks():
    rc, out = priv(f"{VXP}/vehicles/vx-vehicle-03/check-leaks.sh")
    log("  leak check: " + " | ".join(out.strip().splitlines()))
    return rc == 0


def agent():
    return Agent(f"{BIN}/vxmcp", f"unix://{SOCK}", log)


def reason(sc):
    if not isinstance(sc, dict):
        return f"UNTYPED:{sc!r:.80}"
    err = sc.get("error")
    return err.get("reason", "") if isinstance(err, dict) else ""


def watch(a, job_id, limit=3600):
    end = time.time() + limit
    while time.time() < end:
        ok, w = a.call("job_watch", {"id": job_id, "timeout_secs": 300})
        if not ok:
            return {"state": "WATCH_ERROR", "error": json.dumps(w)}
        if w["end"] in ("terminal", "stream_ended"):
            return w["job"]
    return {"state": "TIMEOUT"}


def dump(name, obj):
    with open(os.path.join(OUT, name), "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
