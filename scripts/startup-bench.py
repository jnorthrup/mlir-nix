#!/usr/bin/env python3
"""Startup cost of the two continent back ends, and proof which one ran.

Alternates static / irdl runs of `mlnix instantiate --eval --expr 1` so machine noise
hits both equally; reports the median of wall and user+sys CPU time.
"""
import os, resource, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MLNIX = os.path.join(ROOT, "build", "bin", "mlnix")
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
CMD = [MLNIX, "instantiate", "--eval", "--expr", "builtins.length [1 2 3] + 1"]

def once(mode):
    env = dict(os.environ)
    env["MLNIX_CONTINENTS"] = mode
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    p = subprocess.run(CMD, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    wall = time.perf_counter() - t0
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)
    return wall * 1000, cpu * 1000, p.stdout.decode().strip()

res = {"static": ([], []), "irdl": ([], [])}
outs = {}
for _ in range(N):
    for mode in ("static", "irdl"):
        w, c, o = once(mode)
        res[mode][0].append(w); res[mode][1].append(c); outs[mode] = o
for mode in res:
    print(f"{mode:7s} wall median {statistics.median(res[mode][0]):6.2f} ms   cpu median {statistics.median(res[mode][1]):6.2f} ms   (n={N}, result {outs[mode]!r})")
d = statistics.median(res['irdl'][1]) - statistics.median(res['static'][1])
print(f"irdl - static: {d:+.2f} ms cpu per process")
