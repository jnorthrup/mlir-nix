#!/usr/bin/env python3
"""Run upstream Nix's language test suite (tests/functional/lang) against mlnix.

Mirrors tests/functional/lang.sh: parse-okay/parse-fail/eval-okay/eval-fail.
Semantic pass  = right exit status and (for *-okay) identical stdout.
Exact pass     = additionally identical stderr (error messages, traces).

usage: run-lang-tests.py [--mlnix PATH] [--verbose] [--filter SUBSTR] [--show-diff] [--save DIR]

--save DIR keeps what every case printed (NAME.out, NAME.err, NAME.rc), so two builds can be compared
byte for byte: run once per build into two directories and `diff -r` them.
"""
import argparse, os, subprocess, sys, tempfile, shutil, glob, difflib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(ROOT, "test")

def run(cmd, stdin=None, env=None):
    try:
        p = subprocess.run(cmd, cwd=TESTDIR, input=stdin, capture_output=True, env=env, timeout=60)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"

def postprocess(name, outprefix):
    pp = os.path.join(TESTDIR, "lang", name + ".postprocess")
    if os.path.exists(pp):
        subprocess.run(["bash", pp, outprefix], cwd=TESTDIR)

def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--verbose", "-v", action="store_true")
    ap.add_argument("--filter", default="")
    ap.add_argument("--show-diff", action="store_true")
    ap.add_argument("--save", metavar="DIR")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="mlnix-lang-")
    if args.save:
        os.makedirs(args.save, exist_ok=True)

    def keep(name, rc, out, err):
        if not args.save:
            return
        for ext, text in ((".out", out), (".err", err), (".rc", f"{rc}\n")):
            with open(os.path.join(args.save, name + ext), "w", encoding="utf-8", errors="replace") as f:
                f.write(text)
    mlnix = os.path.abspath(args.mlnix)
    pwd = TESTDIR
    env = dict(os.environ)
    env.update({"TEST_VAR": "foo", "NIX_REMOTE": "dummy://", "NIX_STORE_DIR": "/nix/store",
                # Physical location of the (chroot) store; HOME is faked below.
                "MLNIX_STORE_ROOT": os.path.join(tmp, "root"), "MLNIX_STATE_DIR": os.path.join(tmp, "state")})
    env.pop("NIX_PATH", None)
    instantiate = [mlnix, "instantiate"]

    results = {}  # category -> [semantic_pass, exact_pass, total, failures]
    def record(cat, name, sem, exact, detail):
        r = results.setdefault(cat, [0, 0, 0, []])
        r[2] += 1
        if sem: r[0] += 1
        if exact: r[1] += 1
        if not sem: r[3].append((name, detail))
        if args.verbose:
            print(f"{'PASS' if sem else 'FAIL'}{'' if exact or not sem else ' (stderr differs)'} {cat} {name}")

    def names(prefix):
        return sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(TESTDIR, "lang", prefix + "*.nix"))
                      if args.filter in os.path.basename(p))

    for name in names("parse-fail-"):
        src = open(os.path.join(TESTDIR, "lang", name + ".nix"), "rb").read()
        rc, out, err = run(instantiate + ["--parse", "-"], stdin=src, env=env)
        keep(name, rc, out, err)
        open(os.path.join(tmp, name + ".err"), "w").write(err)
        postprocess(name, os.path.join(tmp, name))
        err = read(os.path.join(tmp, name + ".err"))
        exp = read(os.path.join(TESTDIR, "lang", name + ".err.exp"))
        record("parse-fail", name, rc == 1, rc == 1 and exp is not None and err == exp, err if rc != 1 else "")

    for name in names("parse-okay-"):
        src = open(os.path.join(TESTDIR, "lang", name + ".nix"), "rb").read()
        rc, out, err = run(instantiate + ["--parse", "-"], stdin=src, env=env)
        keep(name, rc, out, err)
        out = out.replace(pwd, "/pwd")
        exp = read(os.path.join(TESTDIR, "lang", name + ".exp"))
        sem = rc == 0 and out == exp
        detail = err if rc != 0 else "".join(difflib.unified_diff((exp or "").splitlines(True), out.splitlines(True), "expected", "got"))
        record("parse-okay", name, sem, sem, detail)

    for name in names("eval-fail-"):
        flagsf = os.path.join(TESTDIR, "lang", name + ".flags")
        if os.path.exists(flagsf):
            flags = open(flagsf).read().split("#")[0].split()
        else:
            flags = ["--eval", "--strict", "--show-trace"]
        rc, out, err = run(instantiate + flags + ["lang/" + name + ".nix"], env=env)
        err = err.replace(pwd, "/pwd")
        keep(name, rc, out, err)
        open(os.path.join(tmp, name + ".err"), "w").write(err)
        postprocess(name, os.path.join(tmp, name))
        err = read(os.path.join(tmp, name + ".err"))
        exp = read(os.path.join(TESTDIR, "lang", name + ".err.exp"))
        record("eval-fail", name, rc == 1, rc == 1 and err == exp, (out + err) if rc != 1 else "")

    e2 = dict(env)
    e2.update({"NIX_PATH": "lang/dir3:lang/dir4", "HOME": "/fake-home"})
    for name in names("eval-okay-"):
        base = os.path.join(TESTDIR, "lang", name)
        if os.path.exists(base + ".exp.xml"):
            rc, out, err = run(instantiate + ["--eval", "--xml", "--no-location", "--strict", "lang/" + name + ".nix"], env=e2)
            keep(name, rc, out, err)
            exp = read(base + ".exp.xml")
            sem = rc == 0 and out == exp
            detail = err if rc != 0 else "".join(difflib.unified_diff((exp or "").splitlines(True), out.splitlines(True), "expected", "got"))
            record("eval-okay", name, sem, sem, detail)
            continue
        if os.path.exists(base + ".exp-disabled"):
            continue
        flags = []
        if os.path.exists(base + ".flags"):
            flags = open(base + ".flags").readline().split()
        rc, out, err = run(instantiate + flags + ["--eval", "--strict", "lang/" + name + ".nix"], env=e2)
        out = out.replace(pwd, "/pwd")
        err = err.replace(pwd, "/pwd")
        keep(name, rc, out, err)
        open(os.path.join(tmp, name + ".out"), "w").write(out)
        open(os.path.join(tmp, name + ".err"), "w").write(err)
        postprocess(name, os.path.join(tmp, name))
        out = read(os.path.join(tmp, name + ".out"))
        err = read(os.path.join(tmp, name + ".err"))
        exp = read(base + ".exp")
        experr = read(base + ".err.exp") or ""
        sem = rc == 0 and out == exp
        detail = err if rc != 0 else "".join(difflib.unified_diff((exp or "").splitlines(True), (out or "").splitlines(True), "expected", "got"))
        record("eval-okay", name, sem, sem and err == experr, detail)

    shutil.rmtree(tmp, ignore_errors=True)
    tot_s = tot_e = tot = 0
    for cat, (s, e, t, fails) in results.items():
        print(f"{cat:12s} semantic {s:4d}/{t:<4d}  exact {e:4d}/{t}")
        tot_s += s; tot_e += e; tot += t
        for (n, d) in fails:
            print(f"   FAIL {n}")
            if args.show_diff and d:
                print("      " + d.strip().replace("\n", "\n      ")[:1500])
    print(f"{'TOTAL':12s} semantic {tot_s:4d}/{tot:<4d}  exact {tot_e:4d}/{tot}")
    return 0 if tot_s == tot else 1

if __name__ == "__main__":
    sys.exit(main())
