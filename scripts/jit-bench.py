#!/usr/bin/env python3
"""Whole-process scalar JIT payback sweep, including compilation and grace checks.

This generated arithmetic workload measures the supported JIT subset, not nixpkgs.
Use vs-nix.py for the two real workload comparisons. Every arm must match the
independent integer sum before any timing is reported.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import statistics
import subprocess

from ab import run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mlnix", default=str(Path(__file__).resolve().parent.parent / "build/bin/mlnix"))
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--count", action="append", type=int, help="number of calls (repeatable)")
    parser.add_argument("--demand", action="store_true")
    parser.add_argument("--ref", action="append", default=[], help="NAME=/path/to/nix-instantiate")
    args = parser.parse_args()
    counts = args.count or [1000, 100000, 1000000]
    if args.runs < 1 or any(n < 1 or n > 10000000 for n in counts):
        parser.error("--runs must be positive; counts must be in 1..10000000")
    for key in list(os.environ):
        if key.startswith("MLNIX_JIT") or key in ("MLNIX_STATS", "MLNIX_DEFER", "MLNIX_PIPELINE", "MLNIX_PRIMS_IRDL"):
            os.environ.pop(key)
    schedule = {"MLNIX_DEFER": "1"} if args.demand else {}
    arms = {"interpreter": (args.mlnix, dict(schedule), ["instantiate"]),
            "scalar JIT": (args.mlnix, dict(schedule, MLNIX_JIT="1"), ["instantiate"])}
    for ref in args.ref:
        name, sep, binary = ref.partition("=")
        if not sep or not binary or not name or name in arms:
            parser.error("each --ref needs a unique NAME=/path/to/nix-instantiate")
        arms[name] = (binary, {}, [])
    print(f"schedule={'demand' if args.demand else 'eager'}; JIT threshold=1024; compilation included")
    if max(counts) >= 1024:
        # An old or non-JIT build can produce the right sum. Prove this binary
        # actually enters native code in an untimed probe before labeling an arm.
        n = min(max(counts), 4096)
        expression = f"builtins.foldl' builtins.add 0 (builtins.genList (x: ((x * 3) - 1) + 7) {n})"
        probe = subprocess.run([args.mlnix, "instantiate", "--eval", "--strict", "-E", expression],
                               env=dict(os.environ, **schedule, MLNIX_JIT="1", MLNIX_STATS="1"),
                               capture_output=True, timeout=60)
        line = next((line for line in probe.stderr.decode().splitlines() if line.startswith("jit:")), "")
        fields = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
        expected = str(3 * n * (n - 1) // 2 + 6 * n) + "\n"
        if (probe.returncode or probe.stdout.decode() != expected or fields.get("compiled", 0) < 1
                or fields.get("executions", 0) < 1 or fields.get("mismatches", 0) or fields.get("compile_failures", 0)):
            raise SystemExit(f"native validation failed: rc={probe.returncode}, stats={line or 'absent'}")
        print("native validation (untimed): " + line)
    for n in counts:
        expression = f"builtins.foldl' builtins.add 0 (builtins.genList (x: ((x * 3) - 1) + 7) {n})"
        expected = str(3 * n * (n - 1) // 2 + 6 * n) + "\n"
        golden = hashlib.sha256(expected.encode()).hexdigest()
        results = {name: [] for name in arms}
        names = list(arms)
        for i in range(args.runs):
            for name in names[i % len(names):] + names[:i % len(names)]:
                binary, env, prefix = arms[name]
                wall, cpu, rss, rc, digest = run(binary, prefix + ["--eval", "--strict", "-E", expression], env)
                if rc or digest != golden:
                    raise SystemExit(f"{n} calls: {name} rejected rc={rc}, hash={digest}, expected={golden}")
                results[name].append((wall, cpu, rss))
        print(f"== {n} calls ({args.runs} interleaved rounds; all outputs match arithmetic oracle {golden[:12]})")
        for name, samples in results.items():
            wall, cpu, rss = zip(*samples)
            print(f"  {name:16s} wall min {min(wall):.3f}s median {statistics.median(wall):.3f}s "
                  f"cpu median {statistics.median(cpu):.3f}s RSS max {max(rss):.3f}GB")
        a = statistics.median(s[0] for s in results["interpreter"])
        b = statistics.median(s[0] for s in results["scalar JIT"])
        print(f"  JIT / interpreter wall median x{b/a:.3f}")


if __name__ == "__main__":
    main()
