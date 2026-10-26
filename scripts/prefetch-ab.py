#!/usr/bin/env python3
"""Cold start, with and without the io_uring replay of a recorded file-access list (Linux).

For each bench workload: one run records the accesses (MLNIX_PREFETCH=record:FILE); then, N rounds of
  drop the page cache; run as is                       (the evaluator waits for the disk one request at a time)
  drop the page cache; run with MLNIX_PREFETCH=replay  (a helper thread feeds the list to io_uring)
Result hashes must be identical on every run.

usage: prefetch-ab.py [--mlnix BIN] [--rounds N]
"""
import argparse, hashlib, os, statistics, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench

ROOT = bench.ROOT
BASE = dict(os.environ, MLNIX_STORE_ROOT="/tmp/mlnix-np-root", MLNIX_STATE_DIR="/tmp/mlnix-np-state")


def drop_caches():
    subprocess.run(["sudo", "-n", "sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches"], check=True)


def run(binary, args, env):
    t0 = time.perf_counter()
    p = subprocess.run([binary] + args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return time.perf_counter() - t0, hashlib.sha256(p.stdout).hexdigest()[:12], p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--rounds", type=int, default=5)
    a = ap.parse_args()
    for name, args in bench.WORKLOADS.items():
        trace = f"/tmp/prefetch-{name}.list"
        _, h0, _ = run(a.mlnix, args, dict(BASE, MLNIX_PREFETCH=f"record:{trace}"))
        n = sum(1 for _ in open(trace))
        base, replay, hashes = [], [], {h0}
        for _ in range(a.rounds):
            drop_caches()
            t, h, _ = run(a.mlnix, args, BASE)
            base.append(t); hashes.add(h)
            drop_caches()
            t, h, _ = run(a.mlnix, args, dict(BASE, MLNIX_PREFETCH=f"replay:{trace}"))
            replay.append(t); hashes.add(h)
        hot = run(a.mlnix, args, BASE)[0]
        mb, mr = statistics.median(base), statistics.median(replay)
        print(f"{name:15s} {n} recorded accesses; {a.rounds} cold rounds")
        print(f"    as is   median {mb:6.2f} s  min {min(base):6.2f}")
        print(f"    replay  median {mr:6.2f} s  min {min(replay):6.2f}   ({100 * (mr / mb - 1):+.1f}% vs as is;  hot, for reference: {hot:.2f} s)")
        print(f"    result hashes: {', '.join(sorted(hashes))}  {'IDENTICAL' if len(hashes) == 1 else 'DIFFER'}")


if __name__ == "__main__":
    main()
