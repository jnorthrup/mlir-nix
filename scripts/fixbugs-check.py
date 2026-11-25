#!/usr/bin/env python3
"""Regression check for the 2026-11-25 fixbugs wave: each test/fixbugs/NAME.nix is evaluated by `mlnix eval --strict --json`
and its stdout must equal NAME.exp (Nix 2.28.4's --json output, recorded from real Nix), or the run must fail when the .exp
says `error`.  Usage: fixbugs-check.py [MLNIX]   (default: build/bin/mlnix next to this repo)."""
import glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MLNIX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "bin", "mlnix")
bad = 0
cases = sorted(glob.glob(os.path.join(ROOT, "test", "fixbugs", "*.nix")))
for f in cases:
    name = os.path.splitext(f)[0]
    want = open(name + ".exp").read().strip()
    p = subprocess.run([MLNIX, "eval", "--strict", "--json", "--expr", open(f).read()],
                       capture_output=True, text=True, timeout=300)
    ok = (want == "error" and p.returncode != 0) or (want != "error" and p.returncode == 0 and p.stdout.strip() == want)
    if not ok:
        bad += 1
        print("FAIL", os.path.basename(name), "want", want[:120], "got rc", p.returncode, (p.stdout or p.stderr).strip()[:160])
print(f"fixbugs: {len(cases) - bad}/{len(cases)} match Nix 2.28.4")
sys.exit(1 if bad else 0)
