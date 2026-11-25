#!/usr/bin/env python3
"""Old/new differential runner for the kursive regex reader (see kursive-dense.py for the generator).

  kursive-dense-run.py batch OLD_MLNIX_OPT NEW_MLNIX_OPT BATCHES N SEED WORKDIR
      Each batch: N dense patterns as one module, run through `--re2mlir ... --kursive-to-program ...` by both
      binaries with a cap setting (default, small pool-cap, small set-cap, small step-cap, all three).  stdout and
      stderr compared byte for byte.  Prints one line per batch with the error histogram (ok / invalid / space) read from
      the NEW output's counts.  Exit 1 on any difference; the differing module and outputs are kept in WORKDIR.
  kursive-dense-run.py eval OLD_MLNIX NEW_MLNIX N SEED WORKDIR
      N builtins.match / builtins.split cases from kursive-dense.py, one `mlnix eval --strict --json --expr E` per
      case and binary, exit status, stdout and stderr compared.  Exit 1 on any difference.
"""
import os, random, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util
spec = importlib.util.spec_from_file_location("kd", os.path.join(HERE, "kursive-dense.py"))
kd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kd)

COUNTS = re.compile(rb"@p\d+_counts : memref<5xi32> = dense<\[(\d+), (\d+), (\d+), (\d+), (\d+)\]>")


def caps(rnd, k):
    """Cap settings for batch k: the defaults, then the reader's and the compiler's room made small."""
    kind = k % 5
    if kind == 0:
        return ["--re2mlir", "--kursive-to-program"]
    if kind == 1:
        return ["--re2mlir=pool-cap=%d" % rnd.randint(2, 60), "--kursive-to-program"]
    if kind == 2:
        return ["--re2mlir=set-cap=%d" % rnd.randint(1, 12), "--kursive-to-program"]
    if kind == 3:
        return ["--re2mlir", "--kursive-to-program=step-cap=%d" % rnd.randint(5, 120)]
    return ["--re2mlir=pool-cap=%d set-cap=%d" % (rnd.randint(2, 60), rnd.randint(1, 12)),
            "--kursive-to-program=step-cap=%d" % rnd.randint(5, 120)]


def run_batch(old, new, batches, n, seed, work):
    rnd = random.Random(seed ^ 0x5eed)
    total = bad = 0
    hist = [0, 0, 0]
    os.makedirs(work, exist_ok=True)
    for k in range(batches):
        mod = os.path.join(work, "batch%03d.mlir" % k)
        with open(mod, "w") as f:
            r = random.Random(seed * 1000003 + k)
            f.write("module {\n")
            for i in range(n):
                f.write('  kursive.pattern @p%d "%s"\n' % (i, kd.mlir_bytes(kd.pattern(r))))
            f.write("}\n")
        opts = caps(rnd, k)
        res = {}
        for name, bin_ in (("old", old), ("new", new)):
            p = subprocess.run([bin_, mod] + opts, capture_output=True)
            res[name] = (p.returncode, p.stdout, p.stderr)
        total += n
        same = res["old"] == res["new"]
        counts = COUNTS.findall(res["new"][1])
        h = [0, 0, 0]
        for c in counts:
            h[int(c[4])] += 1
        hist = [a + b for a, b in zip(hist, h)]
        status = "same" if same else "DIFFERENT"
        print("batch %3d %s ok=%d invalid=%d space=%d rc=%s/%s %s" % (
            k, " ".join(opts), h[0], h[1], h[2], res["old"][0], res["new"][0], status), flush=True)
        if not same:
            bad += 1
            with open(os.path.join(work, "batch%03d.old.out" % k), "wb") as f:
                f.write(res["old"][1] + b"\n--- stderr ---\n" + res["old"][2])
            with open(os.path.join(work, "batch%03d.new.out" % k), "wb") as f:
                f.write(res["new"][1] + b"\n--- stderr ---\n" + res["new"][2])
    print("TOTAL patterns=%d batches=%d differing_batches=%d histogram ok/invalid/space=%d/%d/%d" % (
        total, batches, bad, hist[0], hist[1], hist[2]))
    return 1 if bad else 0


def run_eval(old, new, n, seed, work):
    os.makedirs(work, exist_ok=True)
    cases_path = os.path.join(work, "cases.txt")
    subprocess.run([sys.executable, os.path.join(HERE, "kursive-dense.py"), "cases", cases_path, str(n), str(seed)],
                   check=True)
    with open(cases_path, "rb") as f:
        cases = [ln for ln in f.read().split(b"\n") if ln]

    def one(bin_, e):
        p = subprocess.run([bin_, "eval", "--strict", "--json", "--expr", e.decode("utf-8", "surrogateescape")],
                           capture_output=True, timeout=300)
        return (p.returncode, p.stdout, p.stderr)

    def both(e):
        return e, one(old, e), one(new, e)

    diffs = errs = 0
    with ThreadPoolExecutor(8) as ex:
        for e, a, b in ex.map(both, cases):
            if a[0] != 0:
                errs += 1
            if a != b:
                diffs += 1
                if diffs <= 20:
                    print("DIFF", e[:200]); print("  old", a[0], a[1][:200], a[2][:200])
                    print("  new", b[0], b[1][:200], b[2][:200])
    print("%d cases, %d errors on old (compared too), %d differ" % (len(cases), errs, diffs), flush=True)
    return 1 if diffs else 0


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "batch":
        sys.exit(run_batch(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), sys.argv[7]))
    if mode == "eval":
        sys.exit(run_eval(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]))
    sys.exit("mode: batch | eval")
