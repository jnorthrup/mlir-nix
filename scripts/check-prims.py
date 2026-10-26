#!/usr/bin/env python3
"""Check that the primops declared in include/NixDialect/NixPrims.td are exactly
the primops the evaluator registers (`mlnix primops`), with the same arities.

A primop added in C++ without a declaration is not an op, so it would silently
keep going through the generic builtin/apply path.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    td = open(os.path.join(ROOT, "include", "NixDialect", "NixPrims.td")).read()
    declared = {}
    for m in re.finditer(r'^def (\w+) : NixPrim<(\w+), "([^"]+)", "([^"]+)", (\d+)', td, re.M):
        declared[m.group(4)] = int(m.group(5))
    env = dict(os.environ, NIX_REMOTE="dummy://")
    out = subprocess.run([os.path.join(ROOT, "build", "bin", "mlnix"), "primops"], env=env,
                         capture_output=True, text=True, check=True).stdout
    registered = {k: int(a) for k, a in (l.split() for l in out.splitlines())}
    bad = False
    for k in sorted(set(registered) - set(declared)):
        print(f"registered but not declared in NixPrims.td: {k}")
        bad = True
    for k in sorted(set(declared) - set(registered)):
        print(f"declared in NixPrims.td but not registered: {k}")
        bad = True
    for k in sorted(set(declared) & set(registered)):
        if declared[k] != registered[k]:
            print(f"arity mismatch for {k}: td {declared[k]}, runtime {registered[k]}")
            bad = True
    print(f"primops: {len(registered)} registered, {len(declared)} declared" + ("" if not bad else "  -- MISMATCH"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
