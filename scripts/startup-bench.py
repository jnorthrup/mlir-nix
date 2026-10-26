#!/usr/bin/env python3
"""Process start-up cost of two mlnix binaries (interleaved runs).

usage: startup-bench.py BIN_A BIN_B [N]
Runs `mlnix instantiate --eval --expr ...` alternately and reports the median wall
and CPU (user+sys) time of each, so machine noise hits both equally.
"""
import os, resource, statistics, subprocess, sys, time

A, B = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 60
ARGS = ["instantiate", "--eval", "--expr", "builtins.length [1 2 3] + 1"]


def once(binary):
    env = dict(os.environ)
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    p = subprocess.run([binary] + ARGS, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    wall = time.perf_counter() - t0
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    return wall * 1000, ((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)) * 1000, p.stdout.decode().strip()


res = {A: ([], []), B: ([], [])}
out = {}
for _ in range(N):
    for b in (A, B):
        w, c, o = once(b)
        res[b][0].append(w); res[b][1].append(c); out[b] = o
for b in (A, B):
    print(f"{os.path.relpath(b, os.path.expanduser('~/work')):40s} wall med {statistics.median(res[b][0]):6.2f} ms   cpu med {statistics.median(res[b][1]):6.2f} ms   (n={N}, result {out[b]!r})")
print(f"B - A: {statistics.median(res[B][1]) - statistics.median(res[A][1]):+.2f} ms cpu per process")
