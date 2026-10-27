#!/usr/bin/env python3
"""Interleaved A/B benchmark of two environment settings of the same mlnix binary.

usage: ab.py [--runs N] [--workload NAME]... A_ENV B_ENV
  A_ENV / B_ENV are ';'-separated KEY=VAL lists ("-" for none), e.g.
     ab.py MLNIX_PIPELINE=nix-prims "MLNIX_PIPELINE=nix-prims,cse"

Runs alternate A,B,A,B,... so load from other processes hits both equally; reports
the median of wall and CPU (user+sys) time, min wall, the RSS of each run (this child's own, via wait4) and the result hash
(identical hashes = identical answers).
"""
import argparse, hashlib, os, statistics, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import WORKLOADS, ROOT  # noqa: E402


def parse_env(s):
    return {} if s == "-" else dict(kv.split("=", 1) for kv in s.split(";"))


def run(binary, args, extra):
    env = dict(os.environ)
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    env.update(extra)
    t0 = time.perf_counter()
    p = subprocess.Popen([binary] + args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    assert p.stdout is not None
    out = p.stdout.read()
    p.stdout.close()
    # wait4 returns THIS child's usage.  getrusage(RUSAGE_CHILDREN).ru_maxrss is a running maximum over every child
    # waited for so far, so the second arm of a pair could never print less than the first.
    _, status, ru = os.wait4(p.pid, 0)
    wall = time.perf_counter() - t0
    p.returncode = os.waitstatus_to_exitcode(status)
    cpu = ru.ru_utime + ru.ru_stime
    rss = ru.ru_maxrss * (1 if sys.platform == "darwin" else 1024) / 1e9  # bytes on macOS, KiB on Linux
    return wall, cpu, rss, hashlib.sha256(out).hexdigest()[:12]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--mlnix-b", help="binary for B (default: same as --mlnix)")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--workload", action="append")
    ap.add_argument("a")
    ap.add_argument("b")
    a = ap.parse_args()
    envs = {"A": parse_env(a.a), "B": parse_env(a.b)}
    bins = {"A": a.mlnix, "B": a.mlnix_b or a.mlnix}
    for name in a.workload or list(WORKLOADS):
        res = {k: ([], [], [], set()) for k in envs}
        for _ in range(a.runs):
            for k in envs:
                w, c, rss, h = run(bins[k], WORKLOADS[name], envs[k])
                res[k][0].append(w); res[k][1].append(c); res[k][2].append(rss); res[k][3].add(h)
        print(f"== {name}  ({a.runs} interleaved runs each)")
        for k in envs:
            w, c, rss, h = res[k]
            print(f"  {k} {os.path.relpath(bins[k], os.path.expanduser('~/work'))[:34]:34s} wall med {statistics.median(w):6.3f}s min {min(w):6.3f}s   cpu med {statistics.median(c):6.3f}s   rss med {statistics.median(rss):5.3f}GB max {max(rss):5.3f}GB   hash {','.join(sorted(h))}")
        dw = statistics.median(res['B'][0]) / statistics.median(res['A'][0]) - 1
        dc = statistics.median(res['B'][1]) / statistics.median(res['A'][1]) - 1
        dr = statistics.median(res['B'][2]) / statistics.median(res['A'][2]) - 1
        print(f"  B vs A: wall {dw:+.1%}   cpu {dc:+.1%}   rss {dr:+.1%}")


main()
