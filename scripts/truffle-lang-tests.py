#!/usr/bin/env python3
"""The language suite's eval-okay tests through the Graal arm: nix-truffle evaluates mlnix's son-form export on the JVM.

Same comparison as run-lang-tests.py's eval-okay category (stdout against <name>.exp, the test directory written /pwd),
for the tests that take no flags and no postprocessing.  One JVM evaluates them all.

  (cd graal && ./gradlew installDist)         # first: build graal/ (its wrapper is TrikeShed's, copied)
  python3 scripts/truffle-lang-tests.py [--filter S] [-v]
"""
import argparse, collections, glob, os, re, subprocess, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(ROOT, "test")
TRUFFLE = os.path.join(ROOT, "graal", "build", "install", "nix-truffle", "bin", "nix-truffle")

ap = argparse.ArgumentParser()
ap.add_argument("--filter", default="")
ap.add_argument("-v", "--verbose", action="store_true")
args = ap.parse_args()

names, skipped = [], []
for p in sorted(glob.glob(os.path.join(TESTDIR, "lang", "eval-okay-*.nix"))):
    n = os.path.basename(p)[:-4]
    if args.filter not in n:
        continue
    b = p[:-4]
    if not os.path.exists(b + ".exp") or os.path.exists(b + ".exp-disabled"):
        continue
    if os.path.exists(b + ".flags") or os.path.exists(b + ".postprocess"):
        skipped.append(n)
        continue
    names.append(n)

out = tempfile.mkdtemp(prefix="truffle-lang-")
env = dict(os.environ, TEST_VAR="foo", NIX_STORE_DIR="/nix/store", HOME="/fake-home")  # as run-lang-tests.py
env.pop("NIX_PATH", None)
env["JAVA_OPTS"] = env.get("JAVA_OPTS", "") + " -Xss64m"
subprocess.run([TRUFFLE, "--bin", os.path.join(ROOT, "build", "bin"), "--out", out] + ["lang/" + n + ".nix" for n in names],
               cwd=TESTDIR, env=env, stderr=subprocess.DEVNULL, timeout=1800)

why = collections.Counter()
ok = 0
for n in names:
    exp = open(os.path.join(TESTDIR, "lang", n + ".exp"), encoding="utf-8", errors="replace").read()
    o = os.path.join(out, n + ".out")
    if os.path.exists(o):
        got = open(o, encoding="utf-8", errors="replace").read().replace(TESTDIR, "/pwd")
        if got == exp:
            ok += 1
            if args.verbose: print("PASS", n)
            continue
        why["different output"] += 1
        if args.verbose: print("FAIL", n, "different output")
    else:
        e = open(os.path.join(out, n + ".err"), encoding="utf-8", errors="replace").read().strip() if os.path.exists(os.path.join(out, n + ".err")) else "no result"
        key = re.sub(r"'[^']*'", "'…'", e.split("\n")[0])[:90]
        why[key] += 1
        if args.verbose: print("FAIL", n, e.split("\n")[0][:200])
print(f"eval-okay through nix-truffle: {ok}/{len(names)} identical to .exp ({len(skipped)} tests with flags or postprocessing not run)")
for k, v in why.most_common():
    print(f"  {v:4d}  {k}")
