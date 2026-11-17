#!/usr/bin/env python3
"""kif-lean-kernels.py EXPORT DUMP [--controls] [--times]

Runs the Lean toolchain's kernels that read lean4export's format on the theorem `mlnix-kif --chase --lean` wrote: nanoda_bin
(an independent checker; its config permits no axiom), and con-leche and con-ron (--verified, the mode their soundness
theorems are about; one thread).  Each must accept the theorem.  With --controls each must also reject three copies with one
proof broken (kif-lean-check.py --mutate: a premise, a binding, a statement).  One line per run: the checker, the file, its
verdict, and with --times its wall time and peak RSS; then the checker's last line of output.  Exits 1 when a verdict is not
the one expected.  The checkers come from PATH (elan's toolchain bin: Lean 4.36 ships all three).
"""
import os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "kif-lean-check.py")


def run(cmd):
    t = time.time()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.read().decode("utf-8", "replace")
    _, status, ru = os.wait4(p.pid, 0)
    p.returncode = os.waitstatus_to_exitcode(status)
    lines = [l for l in out.splitlines() if l.strip()]
    return p.returncode, time.time() - t, ru.ru_maxrss / 1024.0, (lines[-1] if lines else "")[:160]


def kernels(export, dump, tmp):
    cfg = os.path.join(tmp, os.path.basename(export) + ".nanoda.json")
    subprocess.run([sys.executable, CHECK, export, dump, "--nanoda-config", cfg], stdout=subprocess.DEVNULL, check=False)
    return [("nanoda_bin", ["nanoda_bin", cfg]), ("con-leche", ["con-leche", "--verified", "--jobs=1", export]),
            ("con-ron", ["con-ron", "--verified", "--jobs=1", export])]


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    export, dump = argv[1], argv[2]
    times = "--times" in argv
    tmp = tempfile.mkdtemp(prefix="kif-lean-")
    files = [("certificate", export, True)]
    if "--controls" in argv:
        for kind in ("premise", "binding", "statement"):
            bad = os.path.join(tmp, kind + ".ndjson")
            what = subprocess.run([sys.executable, CHECK, export, dump, "--mutate", kind, bad], capture_output=True, text=True)
            if what.returncode:
                print(f"control {kind}: {what.stdout}{what.stderr}")
                return 1
            print(f"control {kind}: {what.stdout.strip()}")
            files.append((kind, bad, False))
    wrong = 0
    for label, path, good in files:
        for name, cmd in kernels(path, dump, tmp):
            rc, secs, mb, last = run(cmd)
            verdict = "accepted" if rc == 0 else "rejected"
            if (rc == 0) != good:
                wrong += 1
                verdict += " (WRONG)"
            cost = f" {secs:6.2f} s {mb:6.0f} MB" if times else ""
            print(f"{name:10} {label:11} {verdict}{cost} | {last}")
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
