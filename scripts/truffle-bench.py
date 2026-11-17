#!/usr/bin/env python3
"""truffle-bench.py WT INSTALL [--runs N] [--launches K] [--son] [--label L] FILES...: warm runs of nix-truffle --bench on each file; prints the median
time and allocation of the last half of the runs (over K JVMs: the median of their medians, and the range), and the
result's hash (outputs must agree between builds).  The files: graal/bench/*.nix (docs/SEA-OF-NODES.md, escape).
INSTALL is a nix-truffle install dir (graal/build/install/nix-truffle or a saved copy); --son exports with son.release."""
import hashlib, os, re, statistics, subprocess, sys

args = sys.argv[1:]
wt, inst = os.path.abspath(args[0]), os.path.abspath(args[1])
runs = int(args[args.index("--runs") + 1]) if "--runs" in args else 30
label = args[args.index("--label") + 1] if "--label" in args else ""
son = "--son" in args
files = [a for i, a in enumerate(args[2:], 2) if a.endswith(".nix")]
env = dict(os.environ, JAVA_OPTS=os.environ.get("JAVA_OPTS", "") + " -Xss64m")
if son:
    env["NIXTRUFFLE_SON_PASSES"] = "--son-release"
launches = int(args[args.index("--launches") + 1]) if "--launches" in args else 1
for f in files:
    meds, mbs, firsts, outs = [], [], [], set()
    for _ in range(launches):
        p = subprocess.run([os.path.join(inst, "bin", "nix-truffle"), "--bin", os.path.join(wt, "build", "bin"), "--bench", str(runs), f],
                           env=env, capture_output=True, text=True, timeout=1800)
        rows = [(float(m.group(1)), float(m.group(2))) for m in re.finditer(r"run \d+: ([\d.]+) ms, ([\d.]+) MB allocated", p.stderr)]
        if len(rows) != runs:
            print(f"{label}{os.path.basename(f)}: FAILED rc={p.returncode} {p.stderr[-600:]}")
            break
        tail = rows[runs // 2:]
        meds.append(statistics.median(r[0] for r in tail))
        mbs.append(statistics.median(r[1] for r in tail))
        firsts.append(rows[0][0])
        outs.add(hashlib.sha256(p.stdout.encode()).hexdigest()[:12])
    if len(meds) != launches:
        continue
    print(f"{label}{os.path.basename(f):10s} warm {statistics.median(meds):7.2f} ms (min {min(meds):6.2f}, max {max(meds):6.2f}, {launches} JVMs)"
          f"  {statistics.median(mbs):7.2f} MB/run  first {statistics.median(firsts):6.1f} ms  out {','.join(sorted(outs))}")
