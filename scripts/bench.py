#!/usr/bin/env python3
"""Benchmark mlnix on the two heavy real-world evaluations.

usage: bench.py [--mlnix PATH] [--runs N] [--opt|--no-opt]

Reports min/median wall-clock and peak RSS per workload and the result hash, so a
change that alters the *answer* is as visible as one that alters the speed.
"""
import argparse, hashlib, os, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

WORKLOADS = {
    "nixos-toplevel": ["instantiate", "--readonly-mode", "--eval", "--strict", "test/nixos-toplevel.nix",
                       "--arg", "nixpkgs", "./.cache/nixpkgs"],
    "nixpkgs-73": ["instantiate", "--readonly-mode", "--eval", "--strict", "--json", "test/nixpkgs-drvs.nix",
                   "--argstr", "system", "x86_64-linux"],
}


RSS_UNIT = 1024 * 1024 if sys.platform == "darwin" else 1024  # ru_maxrss: bytes on macOS, KiB on Linux


def run_once(binary, args, extra=None, cap=None):
    """One run: (wall s, peak RSS MB, rc, sha256 prefix of stdout).  cap: dict(deadline=s, mem=bytes, diag=dir, tag=name), the
    limits of scripts/runcap.py: a run past either is stopped, its state kept (the paths are printed), and its rc is 124 or 137."""
    env = dict(os.environ)
    env.setdefault("MLNIX_STORE_ROOT", "/tmp/mlnix-np-root")
    env.setdefault("MLNIX_STATE_DIR", "/tmp/mlnix-np-state")
    env.update(extra or {})
    if cap:
        import runcap, tempfile
        with tempfile.NamedTemporaryFile() as f:
            r = runcap.run([binary] + args, env=env, cwd=ROOT, stdout=f.name, **cap)
            out = open(f.name, "rb").read()
        if r["verdict"] in ("timeout", "memory"):
            print(f"   {cap.get('tag', 'run')}: {r['verdict']} at {r['at']} s (deadline {cap.get('deadline') or 0:.2f} s, cap "
                  f"{(cap.get('mem') or 0) / 2**20:.0f} MB), state kept: {' '.join(r['diag']) or 'none'}", flush=True)
        rc = 124 if r["verdict"] == "timeout" else 137 if r["verdict"] == "memory" else r["rc"]
        return r["wall"], r["maxrss"] / 2**20, rc, hashlib.sha256(out).hexdigest()[:12]
    t0 = time.perf_counter()
    p = subprocess.Popen([binary] + args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    assert p.stdout is not None
    out = p.stdout.read()
    _, status, ru = os.wait4(p.pid, 0)
    wall = time.perf_counter() - t0
    p.returncode = os.waitstatus_to_exitcode(status)
    return wall, ru.ru_maxrss / RSS_UNIT, p.returncode, hashlib.sha256(out).hexdigest()[:12]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--no-opt", action="store_true")
    a = ap.parse_args()
    for name, args in WORKLOADS.items():
        args = list(args) + (["--no-opt"] if a.no_opt else [])
        walls, rss, hashes = [], 0.0, set()
        for _ in range(a.runs):
            w, r, rc, h = run_once(a.mlnix, args)
            if rc != 0:
                print(f"{name}: FAILED rc={rc}")
                return 1
            walls.append(w)
            rss = max(rss, r)
            hashes.add(h)
        print(f"{name:15s} min {min(walls):5.2f}s  median {statistics.median(walls):5.2f}s  "
              f"peak RSS {rss:5.0f} MB  result {','.join(sorted(hashes))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
