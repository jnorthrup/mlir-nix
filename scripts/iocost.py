#!/usr/bin/env python3
"""What does I/O cost on the critical path? (Linux)

For each bench workload: one run with a cold page cache (dropped first), then N hot runs; the
difference is what the evaluator waits for the disk.  Then a census of the file syscalls of one
run (strace -c), which bounds what batching them could save.

usage: iocost.py [--mlnix BIN] [--runs N] [--no-strace]
needs: passwordless sudo (drop_caches), strace
"""
import argparse, hashlib, os, re, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench  # WORKLOADS

ROOT = bench.ROOT
ENV = dict(os.environ, MLNIX_STORE_ROOT="/tmp/mlnix-np-root", MLNIX_STATE_DIR="/tmp/mlnix-np-state")


def drop_caches():
    subprocess.run(["sudo", "-n", "sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches"], check=True)


def run(binary, args):
    t0 = time.perf_counter()
    p = subprocess.run([binary] + args, cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return time.perf_counter() - t0, hashlib.sha256(p.stdout).hexdigest()[:12], p.returncode


def census(binary, args):
    out = "/tmp/iocost-strace.txt"
    subprocess.run(["strace", "-f", "-c", "-o", out, binary] + args, cwd=ROOT, env=ENV,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    calls = {}
    for line in open(out):
        m = re.match(r"\s*[\d.]+\s+[\d.]+\s+\d+\s+(\d+)\s+(?:\d+\s+)?(\w+)\s*$", line)
        if m:
            calls[m.group(2)] = int(m.group(1))
    return calls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--no-strace", action="store_true")
    a = ap.parse_args()
    for name, args in bench.WORKLOADS.items():
        drop_caches()
        cold, h, rc = run(a.mlnix, args)
        hot = [run(a.mlnix, args)[0] for _ in range(a.runs)]
        print(f"{name:15s} cold {cold:6.2f} s   hot min {min(hot):6.2f} s   waiting for the disk {cold - min(hot):5.2f} s "
              f"({100 * (cold / min(hot) - 1):.0f}% on top of hot)   result {h} rc={rc}")
        if not a.no_strace:
            c = census(a.mlnix, args)
            files = ["openat", "open", "close", "read", "pread64", "newfstatat", "fstat", "stat", "lstat", "statx",
                     "readlink", "readlinkat", "getdents64", "mmap", "munmap", "access", "faccessat", "faccessat2"]
            have = {k: c[k] for k in files if k in c}
            print("    file syscalls:", ", ".join(f"{k} {v}" for k, v in sorted(have.items(), key=lambda kv: -kv[1])),
                  f"  (total {sum(have.values())} of {sum(c.values())})")


if __name__ == "__main__":
    main()
