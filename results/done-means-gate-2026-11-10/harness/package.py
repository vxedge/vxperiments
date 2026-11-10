"""Builds the gate package: a scratch copy of experiments/exp-001-ws whose `method` block is
replaced by exp-001-intent.yaml, its legacy descriptor replaced by a `vxp/1` one, and locked.
`VX_BIN=<dir> python3 -I package.py <vxperiments> <dest>`."""
import os, re, shutil, subprocess, sys

S = os.path.dirname(os.path.abspath(__file__))


def build(vxp, dest, intent=None):
    src = os.path.join(vxp, "experiments", "exp-001-ws")
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    for name in ("main.yaml", "vehicle.yaml", "parts.yaml", "parts", "assets"):
        p = os.path.join(src, name)
        (shutil.copytree if os.path.isdir(p) else shutil.copy2)(p, os.path.join(dest, name))
    main = os.path.join(dest, "main.yaml")
    text = open(main).read()
    text, n = re.subn(r"\nmethod:\n(  .*\n)+", "\n", text)
    assert n == 1, "exp-001-ws/main.yaml has no method block"
    text += "\n" + (intent or open(os.path.join(S, "exp-001-intent.yaml")).read())
    open(main, "w").write(text)
    open(os.path.join(dest, "vxp.yaml"), "w").write(
        "# Gate package (X8.4): exp-001 as a vxp/1 package. Not published.\n"
        "schema: vxp/1\nid: vxperiments/exp-001\nversion: 0.1.0\nentry: main.yaml\n"
        "title: ADAS slice isolation under infotainment load (H1)\nrequires:\n  gpu: none\n")
    subprocess.run([os.path.join(os.environ["VX_BIN"], "vxedge"), "--chdir", dest, "pkg", "lock"],
                   check=True, stdout=subprocess.DEVNULL)
    return dest


if __name__ == "__main__":
    print(build(sys.argv[1], sys.argv[2]))
