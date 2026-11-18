#!/usr/bin/env python3
"""truffle-release-check.py WT [--bin BINDIR] [--install DIR] [--save DIR] [--label L]: the eval-okay tests through the Graal arm (as scripts/truffle-lang-tests.py
selects and runs them, one JVM), twice: plain, and with each frame's son.release checked against the arm's own release
(NIXTRUFFLE_SON_PASSES=--son-release NIXTRUFFLE_CHECK_RELEASE=1).  Prints the arm's release-check line and whether the
outputs of the two runs are byte-identical and how many match .exp.
"""
import glob, os, subprocess, sys, tempfile

wt = os.path.abspath(sys.argv[1])
bindir = os.path.abspath(sys.argv[sys.argv.index("--bin") + 1]) if "--bin" in sys.argv else os.path.join(wt, "build", "bin")
label = sys.argv[sys.argv.index("--label") + 1] if "--label" in sys.argv else ""
testdir = os.path.join(wt, "test")
inst = os.path.abspath(sys.argv[sys.argv.index("--install") + 1]) if "--install" in sys.argv else os.path.join(wt, "graal", "build", "install", "nix-truffle")
truffle = os.path.join(inst, "bin", "nix-truffle")
save = sys.argv[sys.argv.index("--save") + 1] if "--save" in sys.argv else None
names = []
for p in sorted(glob.glob(os.path.join(testdir, "lang", "eval-okay-*.nix"))):
    b = p[:-4]
    if not os.path.exists(b + ".exp") or os.path.exists(b + ".exp-disabled"):
        continue
    if os.path.exists(b + ".flags") or os.path.exists(b + ".postprocess"):
        continue
    names.append(os.path.basename(b))


def run(extra):
    out = tempfile.mkdtemp(prefix="son-check-")
    env = dict(os.environ, TEST_VAR="foo", NIX_STORE_DIR="/nix/store", HOME="/fake-home")
    env.pop("NIX_PATH", None)
    env["JAVA_OPTS"] = env.get("JAVA_OPTS", "") + " -Xss64m"
    env.update(extra)
    p = subprocess.run([truffle, "--bin", bindir, "--out", out] + ["lang/" + n + ".nix" for n in names],
                       cwd=testdir, env=env, capture_output=True, text=True, timeout=1800)
    outs, ok = {}, 0
    for n in names:
        o = os.path.join(out, n + ".out")
        got = open(o, encoding="utf-8", errors="replace").read() if os.path.exists(o) else None
        outs[n] = got
        exp = open(os.path.join(testdir, "lang", n + ".exp"), encoding="utf-8", errors="replace").read()
        if got is not None and got.replace(testdir, "/pwd") == exp:
            ok += 1
    check = [l for l in p.stderr.splitlines() if l.startswith(("release check:", "release calls:", "calls:"))]
    return outs, ok, check


plain, ok0, _ = run({})
checked, ok1, check = run({"NIXTRUFFLE_SON_PASSES": "--son-release", "NIXTRUFFLE_CHECK_RELEASE": "1"})
same = sum(1 for n in names if plain[n] == checked[n])
print(f"{label}eval-okay {len(names)} files: {ok0}/{len(names)} identical to .exp plain, {ok1}/{len(names)} checked; "
      f"outputs byte-identical in {same}/{len(names)}")
for l in check:
    print(f"{label}{l}")
if save:  # the plain run's outputs, and under son/ the checked run's (son.release and arg_forced exported)
    os.makedirs(os.path.join(save, "son"), exist_ok=True)
    for n in names:
        open(os.path.join(save, n + ".out"), "w").write(plain[n] if plain[n] is not None else "<no output>")
        open(os.path.join(save, "son", n + ".out"), "w").write(checked[n] if checked[n] is not None else "<no output>")
