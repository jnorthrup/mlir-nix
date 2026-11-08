#!/usr/bin/env python3
"""kif-chase against the solver it retires: sumo-nix/datalog.nix, run by mlnix on the same KIF files.

Both sides print every fact of the closure as `fact<TAB>rule<TAB>premise...` (an asserted fact: rule `-`), datalog.nix through
its `why`, kif-chase through `mlnix-kif --chase --dump`; the lines must be equal, proofs included.

  python3 scripts/kif-oracle.py --kb FACTS.kif RULES.kif [--ontology Merge.kif nix-domain.kif] [--sumo ~/work/sumo-nix]
"""
import argparse, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--kb", nargs="+", required=True)
ap.add_argument("--ontology", nargs="*", default=[])
ap.add_argument("--sumo", default=os.path.expanduser("~/work/sumo-nix"))
ap.add_argument("--mlnix", default=os.path.join(ROOT, "build", "bin", "mlnix"))
ap.add_argument("--engine", default=os.path.join(ROOT, "build", "bin", "mlnix-kif"),
                help="the command that prints the closure: mlnix-kif, or nix-truffle's kif mode")
ap.add_argument("--show", type=int, default=8, help="differing lines to print")
a = ap.parse_args()

paths = lambda fs: "[ " + " ".join(os.path.abspath(f) for f in fs) + " ]"
expr = f'''
let
  inherit (builtins) concatMap concatStringsSep filter head isList length readFile map sort lessThan;
  sumo = {os.path.abspath(a.sumo)};
  kif = import (sumo + "/kif.nix");
  forms = concatMap (f: kif.parse (readFile f)) {paths(a.kb)};
  isRule = f: isList f && length f == 3 && head f == "=>";   # as mlnix-kif reads a top-level form
  onto = {paths(a.ontology)};
  ontology = if onto == [ ] then null else import (sumo + "/sumo.nix") {{ forms = concatMap (f: kif.parse (readFile f)) onto; }};
  e = import (sumo + "/datalog.nix") {{ inherit ontology; rules = filter isRule forms; facts = filter (f: !(isRule f)) forms; }};
  line = f: let p = e.why f; in
    if p ? asserted then p.fact + "\\t-" else concatStringsSep "\\t" ([ p.fact p.rule ] ++ map (q: q.fact) p.from);
in concatStringsSep "\\n" (map line e.facts) + "\\n"
'''
t0 = time.time()
r = subprocess.run([a.mlnix, "eval", "--raw", "-E", expr], capture_output=True, text=True)
t1 = time.time()
if r.returncode:
    sys.exit("datalog.nix failed: " + r.stderr[-2000:])
old = sorted(set(l for l in r.stdout.split("\n") if l))
cmd = a.engine.split() + ["--chase", "--dump"] + sum((["--ontology", f] for f in a.ontology), []) + a.kb
r2 = subprocess.run(cmd, capture_output=True, text=True)
t2 = time.time()
if r2.returncode:
    sys.exit("kif-chase failed: " + r2.stderr[-2000:])
new = sorted(set(l for l in r2.stdout.split("\n") if l))
derived = sum(1 for l in old if l.split("\t")[1] != "-")
print(f"datalog.nix: {len(old)} facts ({derived} derived) in {t1 - t0:.2f} s; {os.path.basename(a.engine.split()[0])}: {len(new)} facts in {t2 - t1:.2f} s")
if old == new:
    print("identical: every fact and every proof")
    sys.exit(0)
so, sn = set(old), set(new)
print(f"DIFFERENT: {len(so - sn)} lines only from datalog.nix, {len(sn - so)} only from the chase")
for l in sorted(so - sn)[: a.show]: print("  datalog:", l[:300])
for l in sorted(sn - so)[: a.show]: print("  chase:  ", l[:300])
sys.exit(1)
