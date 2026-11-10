"""Done-means steps 1 to 7 (VXPERIMENT-UPGRADE.md section 1), driven through vxmcp as an agent
would. Every check branches on a typed field.

  python3 -I donemeans.py <step> [...]     steps: catalogue | plan | campaign | all
"""
import glob, hashlib, json, os, re, shutil, subprocess, sys, time, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gate import (BIN, FAILS, VXP, WORK, agent, check, dump, leaks, log, reason, start_daemon,
                  stop_daemon, watch)
from package import build

PKG = f"{WORK}/pkg"
REGISTRY = os.environ.get("GATE_REGISTRY", "localhost:5000")
INTENT = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "exp-001-intent.yaml")).read()


def cli(*args, cwd=None, ok=True):
    r = subprocess.run([f"{BIN}/vxedge", *args], cwd=cwd, capture_output=True, text=True,
                       env=dict(os.environ, PATH=f"{BIN}:{os.environ['PATH']}", COSIGN_PASSWORD=""))
    if ok and r.returncode:
        raise RuntimeError(f"vxedge {args}: {r.stderr}")
    return r


def packed(folder):
    """Packs `folder` into `<folder>.packed/` and returns (file, digest)."""
    dest = folder.rstrip("/") + ".packed"
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    out = cli("--chdir", folder, "pkg", "pack", "--out", dest).stdout
    f = os.path.join(dest, re.search(r"^packed (.+)$", out, re.M).group(1))
    d = re.search(r"^digest (sha256:[0-9a-f]{64})$", out, re.M).group(1)
    return f, d


def prepare():
    """The author's side, outside the agent: build, pack, sign and push the package; a tampered
    copy pushed beside it; this host's verification record and trust policy."""
    build(VXP, PKG)
    good_file, good = packed(PKG)
    keys = f"{WORK}/keys"
    if not os.path.exists(f"{keys}/cosign.key"):
        os.makedirs(keys, exist_ok=True)
        subprocess.run([f"{BIN}/cosign", "generate-key-pair"], cwd=keys, check=True,
                       env=dict(os.environ, COSIGN_PASSWORD=""), capture_output=True)
    cli("pkg", "sign", "--key", f"{keys}/cosign.key", good_file, cwd=WORK)
    shutil.rmtree(f"{WORK}/cache", ignore_errors=True)
    v = cli("pkg", "verify", "--key", f"{keys}/cosign.pub", "--cache-dir", f"{WORK}/cache",
            good_file, cwd=WORK).stdout
    fp = re.search(r"^signer key:(sha256:[0-9a-f]{64})$", v, re.M).group(1)
    tampered = build(VXP, f"{WORK}/pkg-tampered", intent=INTENT.replace("factor: 2.0", "factor: 20.0"))
    bad_file, bad = packed(tampered)
    shutil.copy(good_file + ".sigstore.json", bad_file + ".sigstore.json")
    r = cli("pkg", "verify", "--key", f"{keys}/cosign.pub", "--cache-dir", f"{WORK}/cache",
            bad_file, cwd=WORK, ok=False)
    check(r.returncode != 0, f"author side: the good signature does not verify the tampered "
                             f"package ({r.stderr.strip()[:120]})")
    repo = REGISTRY + "/vxperiments/exp-001"
    for f in (good_file, bad_file):
        cli("pkg", "push", "--file", f, repo, cwd=WORK)
    policy = f"{WORK}/trust.yaml"
    open(policy, "w").write(f"require_signed: true\nsigners:\n  - {{ kind: key, fingerprint: \"{fp}\" }}\n")
    log(f"  package {good}, tampered {bad}, signer {fp[:19]}")
    return {"good": good, "tampered": bad, "repo": repo, "policy": policy}


def archive_member(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name).decode()


def catalogue(a):
    """Step 1: list the catalogue and inspect each package, typed."""
    log("== step 1: catalogue and inspect")
    ok, lst = a.call("package_list")
    check(ok and isinstance(lst.get("packages", []), list), "package_list answers a typed list")
    folders = sorted({os.path.dirname(p) for p in glob.glob(f"{VXP}/experiments/*/*.vxp")})
    for f in folders + [PKG]:
        ok, info = a.call("package_inspect", {"package": f})
        name = os.path.basename(f)
        check(ok and info.get("id") and info.get("version"),
              f"package_inspect {name}: {info.get('id')} {info.get('version')} {reason(info)}")
        dump(f"inspect-{name}.json", info)
    ok, info = a.call("package_inspect", {"package": PKG})
    params = {p["name"]: p for p in info.get("parameters", [])}
    lm = params.get("load_mbps", {})
    check(info.get("hypothesis", {}).get("id") == "H1", "gate package: hypothesis H1")
    check(lm.get("binds", "").startswith("traffic_profiles[") and lm.get("min") == 0 and lm.get("max") == 1000,
          f"gate package: load_mbps with bounds and binds {lm}")
    check(sorted(m["id"] for m in info.get("metrics", [])) == ["loss_pct", "lost", "p99", "sent"],
          "gate package: four typed metrics")
    check(len(info.get("criteria", [])) == 1 and len(info["criteria"][0].get("group", {}).get("members", [])) == 2,
          "gate package: criterion h1, a group of two comparisons")
    check(sorted(x.get("name") for x in info.get("campaign", {}).get("arms", [])) ==
          ["idle", "saturated"], "gate package: arms idle and saturated")
    check(sorted(x.get("name") for x in info.get("campaign", {}).get("profiles", [])) ==
          ["gate", "quick", "repro"], "gate package: profiles gate, quick and repro")
    check(sorted(info.get("measurements", [{}])[0]) and info.get("entities"),
          f"gate package: measurements and entities typed ({len(info.get('entities', []))} entities)")
    return info


def plan(a, digest):
    """Step 3, plan side: the package plans clean, by path and by digest; an out-of-bounds value
    is refused at plan time, before any question, and nothing is recorded."""
    log("== step 3: plan, bounds")
    for ref in (PKG, digest):
        ok, p = a.call("campaign_plan", {"workspace": ref})
        check(ok and not p.get("problems") and len(p.get("trials", [])) == 25,
              f"campaign_plan {'by path' if ref == PKG else ref[:19]}: 25 trials, no problems "
              f"({len(p.get('trials', []))}, {[x.get('reason') for x in p.get('problems', [])]})")
    ok, q = a.call("campaign_plan", {"workspace": digest, "profile": "gate"})
    check(ok and not q.get("problems") and len(q.get("trials", [])) == 15,
          f"campaign_plan gate profile: 15 trials ({len(q.get('trials', []))})")
    dump("plan-gate.json", q)
    bad = build(VXP, f"{WORK}/pkg-oob", intent=INTENT.replace("[0, 100, 250, 400, 600]",
                                                             "[0, 100, 250, 400, 600, 1200]"))
    ok, b = a.call("campaign_plan", {"workspace": bad})
    probs = [(x.get("reason"), x.get("detail")) for x in b.get("problems", [])]
    check(ok and ("ERROR_REASON_PARAMETER_INVALID",
                  "experiment `exp-001`, `campaign.sweep.load_mbps[5]`: 1200 is outside [0, 1000]")
          in probs, f"out-of-bounds sweep value refused at plan time: {probs}")
    dump("plan-oob.json", b)
    asked = len(a.asked)
    ok, s = a.call("campaign_start", {"workspace": bad, "request_id": "oob-1"})
    check(not ok and reason(s).startswith("ERROR_REASON_") and len(a.asked) == asked,
          f"campaign_start of it refused before any question ({reason(s)})")
    ok, lst = a.call("campaign_list")
    check(ok and not lst.get("campaigns"), "no campaign recorded")


def pull(a, registry):
    """Step 2: pull by digest under a policy that requires signatures; a tampered package is
    refused SIGNATURE_INVALID with nothing fetched."""
    log("== step 2: pull, signature, plan")
    good, bad = registry["good"], registry["tampered"]
    ok, before = a.call("package_list")
    ok, r = a.call("package_pull", {"reference": f"{registry['repo']}@{bad}"})
    check(not ok and reason(r) == "ERROR_REASON_SIGNATURE_INVALID",
          f"tampered {bad[:19]} refused ({reason(r)})")
    ok, after = a.call("package_list")
    check(after == before and not os.path.exists(f"{WORK}/cache/packages/{bad[7:]}.vxp"),
          "nothing fetched or cached for it")
    ok, jobs = a.call("job_list", {})
    check(ok and not [j for j in jobs.get("jobs", []) if j.get("kind") == "package.pull"],
          "no pull job created")
    ok, job = a.call("package_pull", {"reference": f"{registry['repo']}@{good}",
                                      "request_id": "pull-good"})
    end = watch(a, job["id"]) if ok else {"state": json.dumps(job)}
    art = end.get("artifact") or {}
    check(end.get("state") == "JOB_STATE_SUCCEEDED" and art.get("sha256") == good[7:],
          f"signed {good[:19]} pulled {end.get('state')} {art.get('path')}")
    ok, lst = a.call("package_list")
    cached = [p for p in lst.get("packages", []) if p.get("digest") == good]
    check(len(cached) == 1 and cached[0].get("hasLock"), f"package_list holds it, locked {cached}")
    ok, info = a.call("package_inspect", {"package": good})
    check(ok and info.get("locked") and info.get("digest") == good,
          f"package_inspect by digest: locked {info.get('locked')}")


def campaign(a, ref, profile, rid, label):
    """Steps 3 (retry) and 4 (follow phases live). Returns the campaign id and what was seen."""
    log(f"== steps 3-4: campaign {label}, profile {profile}, request_id {rid}")
    args = {"workspace": ref, "profile": profile, "request_id": rid, "caller": "done-means-gate"}
    ok, job = a.call("campaign_start", args)
    check(ok and job.get("id"), f"campaign_start returns a job {job.get('id')} {reason(job)}")
    ok2, job2 = a.call("campaign_start", args)
    check(ok2 and job2.get("id") == job.get("id"),
          f"retried request_id returns the same job ({job2.get('id')} {reason(job2)})")
    other = dict(args, request_id=rid + "-other")
    asked = len(a.asked)
    ok3, busy = a.call("campaign_start", other)
    ok, lst = a.call("campaign_list")
    cid = next((c["campaignId"] for c in lst.get("campaigns", []) if c.get("jobId") == job.get("id")), "")
    meta = (busy.get("error") or {}).get("metadata", {}) if isinstance(busy, dict) else {}
    check(not ok3 and reason(busy) == "ERROR_REASON_BUSY" and meta.get("active_campaign") == cid
          and meta.get("retry_after_ms"),
          f"another campaign refused BUSY naming {meta.get('active_campaign')} ({reason(busy)})")
    seen, last, status = [], {}, {}
    while True:
        ok, w = a.call("campaign_watch", {"campaign_id": cid, "timeout_secs": 1})
        if not ok:
            check(False, f"campaign_watch {reason(w)}")
            break
        status = w.get("status") or status
        for t in status.get("trials", []):
            key = (t.get("state"), t.get("phase"))
            if last.get(t["id"]) != key:
                last[t["id"]] = key
                seen.append((int(time.time() * 1000), t["id"], t.get("state"), t.get("phase")))
                log(f"   {t['id']}: {t.get('state')} {t.get('phase')}")
        if w["end"] == "finished":
            break
    dump(f"watch-{label}.json", seen)
    ok, st = a.call("campaign_get", {"campaign_id": cid})
    dump(f"campaign-{label}.json", st)
    states = sorted({t["state"] for t in st.get("trials", [])})
    check(st.get("state") == "CAMPAIGN_STATE_SUCCEEDED", f"campaign {cid} {st.get('state')} {states}")
    check(all(t.get("archive") and t.get("sha256") for t in st.get("trials", [])),
          "every trial has an archive and its sha256")
    return cid, st, seen


def phases(st, seen):
    """Step 4: what was followed live is what each archive recorded, in order and in time."""
    log("== step 4: live phases against archive windows")
    worst = 0
    for t in st.get("trials", []):
        recs = [json.loads(l) for l in archive_member(t["archive"], "phases.jsonl").splitlines() if l]
        names = [r["phase"] for r in recs]
        ts = {r["phase"]: r["ts_ns"] // 1_000_000 for r in recs}
        check(names == ["provision", "warmup", "measure", "cooldown", "teardown"]
              and all(r["trial"] == t["id"] for r in recs)
              and [r["ts_ns"] for r in recs] == sorted(r["ts_ns"] for r in recs),
              f"{t['id']}: archive phases in order {names}")
        live = [(ms, ph) for ms, tid, state, ph in seen if tid == t["id"] and ph]
        order = []
        for _, ph in live:
            if not order or order[-1] != ph:
                order.append(ph)
        lag = [ms - ts[ph] for ms, ph in live if ph in ts and (ms, ph) == next(
            (x for x in live if x[1] == ph), None)]
        worst = max([worst] + lag)
        check(set(order) <= set(names) and order == [n for n in names if n in order]
              and all(0 <= d <= 3000 for d in lag),
              f"{t['id']}: followed {order}, each seen {min(lag, default=0)}-{max(lag, default=0)} ms "
              f"after its marker")
    log(f"  worst lag between a marker and seeing it live: {worst} ms (1 s watch windows)")


def verdict(a, cid, st):
    """Step 5: a typed verdict per criterion, with the trials and values behind each read."""
    log("== step 5: typed verdict")
    ok, v = a.call("result_verdict", {"campaign_id": cid})
    dump(f"verdict-{cid}.json", v)
    outcomes = ("VERDICT_OUTCOME_PASS", "VERDICT_OUTCOME_FAIL", "VERDICT_OUTCOME_INCONCLUSIVE")
    check(ok and v.get("outcome") in outcomes and v.get("outcome") == st.get("verdict"),
          f"result_verdict {v.get('outcome')} equals the recorded {st.get('verdict')}")
    for c in v.get("criteria", []):
        for m in c.get("members", [c]):
            reads = m.get("reads", [])
            counts = [len(r.get("values", [])) for r in reads]
            check(m.get("outcome") in outcomes and counts and all(n == 3 for n in counts),
                  f"criterion {m.get('id')}: {m.get('outcome')}, {counts} trial values per read")
    return v


def rerun(a, cid, st, good):
    """Steps 6 and 7: fetch every archive, re-hash it to its own identity, rerun the campaign
    from one archive's package alone, and compare the rerun with the original."""
    log("== step 7: fetch, re-hash, rerun from the archive")
    ok, lst = a.call("result_list", {"campaign_id": cid})
    listed = sorted(r["digest"] for r in lst.get("results", []))
    want = sorted("sha256:" + t["sha256"].removeprefix("sha256:") for t in st["trials"])
    check(ok and listed == want, f"result_list names the campaign's {len(want)} archives")
    out = f"{WORK}/fetched-{cid}"
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    fetched = []
    for d in listed:
        ok, f = a.call("result_fetch", {"digest": d, "out_path": f"{out}/{d[7:19]}.zip"})
        path = f.get("path", "")
        h = "sha256:" + hashlib.sha256(open(path, "rb").read()).hexdigest() if ok else ""
        v = json.loads(subprocess.run([f"{BIN}/vxtelemetry", "verify", path], capture_output=True,
                                      text=True).stdout or "{}") if ok else {}
        good_id = (v.get("ok") and v.get("recorded") == v.get("computed")
                   and v.get("package_digest", {}).get("computed") == good)
        check(ok and f.get("digest") == d and h == d and good_id,
              f"{d[:19]}: fetched, re-hashed {h == d}, workspace identity {v.get('ok')}, "
              f"package digest {v.get('package_digest', {}).get('computed', '')[:19]}")
        fetched.append(path)
    src = f"{WORK}/from-archive"
    shutil.rmtree(src, ignore_errors=True)
    with zipfile.ZipFile(fetched[0]) as z:
        for n in z.namelist():
            if n.startswith("package/") and not n.endswith("/"):
                dest = os.path.join(src, n[len("package/"):])
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                open(dest, "wb").write(z.read(n))
    _, d = packed(src)
    check(d == good, f"the package inside the archive packs to the package that ran ({d[:19]})")
    cid2, st2, _ = campaign(a, src, "gate", f"rerun-{int(time.time())}", "rerun")
    check(leaks(), "host clean after the rerun")
    log("== step 6: compare the rerun with the original")
    ok, c = a.call("result_compare", {"campaign_id": cid2, "reference_campaign_id": cid})
    dump("compare-rerun-original.json", c)
    ms = c.get("metrics", [])
    check(ok and ms and all(m.get("count") == 3 and m.get("referenceCount") == 3 for m in ms),
          f"result_compare: {len(ms)} metric x point pairs, 3 trials a side; "
          f"outcome {c.get('outcome')} against {c.get('referenceOutcome')}")
    for m in ms:
        log(f"   {m['metric']:8} {m['point']:16} median {m.get('median', 0):.6g} ref "
            f"{m.get('referenceMedian', 0):.6g} IQR {m.get('referenceIqr', 0):.3g} "
            f"within {m.get('withinReferenceIqr', False)}")
    log(f"  within the original's IQR: {c.get('within', 0)} of {len(ms)} (measured, not gated: "
        f"a timing claim needs the methodology gate)")
    return cid2, c


def main():
    steps = sys.argv[1:] or ["all"]
    want = lambda s: s in steps or "all" in steps  # noqa: E731
    log(f"#### done-means {steps}")
    for b in ("vxedged", "vxedge", "vxmcp", "vxtelemetry", "vxprobe", "vxtraffic"):
        h = hashlib.sha256(open(f"{BIN}/{b}", "rb").read()).hexdigest()
        v = subprocess.run([f"{BIN}/{b}", "--version"], capture_output=True, text=True).stdout.strip()
        log(f"  {b}: {v or '(no --version)'} sha256 {h[:16]}")
    registry = prepare()
    check(leaks(), "host clean before start")
    start_daemon(trust_policy=registry["policy"])
    try:
        a = agent()
        if want("catalogue"):
            catalogue(a)
        if want("pull"):
            pull(a, registry)
        if want("plan"):
            plan(a, registry["good"])
        if want("campaign"):
            cid, st, seen = campaign(a, registry["good"], "gate", f"gate-{int(time.time())}", "original")
            check(leaks(), "host clean after the campaign")
            phases(st, seen)
            verdict(a, cid, st)
            rerun(a, cid, st, registry["good"])
        a.close()
    finally:
        stop_daemon()
    check(leaks(), "host clean after")
    log(f"#### {len(FAILS)} failure(s)")
    for f in FAILS:
        log("   - " + f)
    sys.exit(1 if FAILS else 0)



if __name__ == "__main__":
    main()
