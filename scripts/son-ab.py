#!/usr/bin/env python3
"""The sea of nodes, eager against demand: interleaved A/B on the real workloads and on generated shapes.

Modeled on TrikeShed's shape benches (../TrikeShed/src/commonBench/kotlin/borg): the same work down
two paths with the whole path priced, parameters swept, and the answer checked inside the bench (a run
that fails, or answers differently, stops the table; it is never averaged in).
  eager   the default: every lambda body is minted to MLIR when its file is lowered
  demand  MLNIX_DEFER=1: a lambda body is minted on its first call, from the retained AST

Acceptance, stated before the numbers: demand pays when it beats eager in wall time on both real
workloads (nixos-toplevel, nixpkgs-73), with identical result hashes and a lower peak footprint.  The
shapes say where it stops paying (the fraction of lambdas ever called, the calls per lambda); they do
not change that verdict.  Numbers go in the commit message whatever they are.

Runs alternate A,B,A,B so load from other processes hits both; wall and CPU are medians, the footprint
is the median "peak memory footprint" of /usr/bin/time (RSS where there is no such line).

usage: son-ab.py [--mlnix BIN] [--runs N] [--real] [--shapes]    (default: both)
"""
import argparse, hashlib, os, re, resource, shutil, statistics, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench  # noqa: E402

ROOT = bench.ROOT
ARMS = {"eager": {}, "demand": {"MLNIX_DEFER": "1"}}
TIME = ["/usr/bin/time", "-l"] if sys.platform == "darwin" else ["/usr/bin/time", "-v"]


def footprint_mb(err):
    m = re.search(r"(\d+)\s+peak memory footprint", err)  # macOS, bytes
    if m:
        return int(m.group(1)) / 1e6
    m = re.search(r"Maximum resident set size \(kbytes\): (\d+)", err)  # Linux
    return int(m.group(1)) / 1e3 if m else float("nan")


def run(binary, args, extra):
    env = dict(os.environ)
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    env.update(extra)
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    p = subprocess.run(TIME + [binary] + args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    wall = time.perf_counter() - t0
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)
    err = p.stderr.decode(errors="replace")
    if p.returncode != 0:
        sys.exit(f"FAILED rc={p.returncode} with {extra or 'defaults'}:\n" + "\n".join(err.splitlines()[:8]))
    return wall, cpu, footprint_mb(err), hashlib.sha256(p.stdout).hexdigest()[:12]


def table(label, binary, args, runs):
    res = {k: ([], [], [], set()) for k in ARMS}
    for _ in range(runs):
        for k, env in ARMS.items():
            w, c, f, h = run(binary, args, env)
            res[k][0].append(w); res[k][1].append(c); res[k][2].append(f); res[k][3].add(h)
    print(f"== {label}  ({runs} interleaved runs each)")
    for k in ARMS:
        w, c, f, h = res[k]
        print(f"  {k:7s} wall med {statistics.median(w):6.3f}s min {min(w):6.3f}s   cpu med {statistics.median(c):6.3f}s   "
              f"footprint {statistics.median(f):7.0f} MB   hash {','.join(sorted(h))}")
    d = lambda i: statistics.median(res["demand"][i]) / statistics.median(res["eager"][i]) - 1
    same = res["eager"][3] == res["demand"][3] and len(res["eager"][3]) == 1
    print(f"  demand vs eager: wall {d(0):+.1%}   cpu {d(1):+.1%}   footprint {d(2):+.1%}   hashes {'IDENTICAL' if same else 'DIFFER'}")
    if not same:
        sys.exit("the answers differ: nothing below this line means anything")


# --- generated shapes: a file of `lambdas` pattern lambdas, `called` of them applied `calls` times ---

def lcg(seed=0x9E3779B97F4A7C15):
    """TrikeShed's generator (LexicalShapeBench, GraphShapeBench): the same corpus on every host."""
    while True:
        seed = (seed * 6364136223846793005 + 1442695040888963407) & (2**64 - 1)
        yield (seed >> 11) / 2**53


ENTRIES = [  # one attribute of a body each; together they cover select, list, if, let, with, interpolation, nested lambda
    "a + b",
    "[ a b (a + 1) ]",
    "builtins.length [ a b ] + a",
    "if a == 0 then b else a",
    "{ inner = a; other = [ b ]; }",
    "\"s${toString a}\"",
    "builtins.map (x: x + a) [ b 1 2 ]",
    "let t = a * 2; in t + b",
    "with { z = a; }; z + b",
]


def shape_file(path, lambdas, entries, called, calls):
    u = lcg()
    chosen = [i for i in range(lambdas) if next(u) < called]
    body = " ".join(f"x{i} = {ENTRIES[i % len(ENTRIES)]};" for i in range(entries))
    out = ["let"]
    out += [f"  f{i} = {{ a, b ? 1, ... }}: {{ {body} }};" for i in range(lambdas)]
    one = "(f { a = 1; }).x0" if calls == 1 else \
        f"builtins.foldl' (t: i: t + (f {{ a = i; }}).x0) 0 (builtins.genList (i: i) {calls})"
    out.append("in")
    out.append(f"builtins.foldl' (s: f: s + {one}) 0 [ {' '.join(f'f{i}' for i in chosen)} ]" if chosen else "0")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")
    return len(chosen)


SHAPES = [  # (label, lambdas, entries per body, fraction called, calls per called lambda)
    ("20000 lambdas, 0% called", 20000, 12, 0.00, 1),
    ("20000 lambdas, 1% called", 20000, 12, 0.01, 1),
    ("20000 lambdas, 10% called", 20000, 12, 0.10, 1),
    ("20000 lambdas, 50% called", 20000, 12, 0.50, 1),
    ("20000 lambdas, 100% called", 20000, 12, 1.00, 1),
    ("hot: 50 lambdas, all called 50000 times", 50, 3, 1.00, 50000),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--shapes", action="store_true")
    a = ap.parse_args()
    both = not (a.real or a.shapes)
    if a.real or both:
        for name, args in bench.WORKLOADS.items():
            table(name, a.mlnix, args, a.runs)
    if a.shapes or both:
        tmp = tempfile.mkdtemp(prefix="son-shapes-")
        try:
            for label, lambdas, entries, called, calls in SHAPES:
                path = os.path.join(tmp, "shape.nix")
                n = shape_file(path, lambdas, entries, called, calls)
                table(f"{label} ({n} applied)", a.mlnix, ["instantiate", "--eval", "--strict", path], a.runs)
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
