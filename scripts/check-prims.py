#!/usr/bin/env python3
"""Check that the primops declared in include/NixDialect/NixPrims.irdl.mlir are
exactly the primops the evaluator registers (`mlnix primops`), with the same
arities.

A primop added in C++ without a declaration is not an op, so it would silently keep
going through the generic builtin/apply path.  (The arity of an op is the number of
`irdl.operands` entries; the key is its `nix.key` attribute.)
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IRDL = "NixPrims.irdl.mlir"


def declared_prims(text):
    declared = {}
    for m in re.finditer(r'irdl\.operation @(\w+) attributes \{nix\.key = "([^"]+)"[^}]*\} \{(.*?)\n  \}', text, re.S):
        body = m.group(3)
        ops = re.search(r"irdl\.operands\(([^)]*)\)", body)
        arity = len(ops.group(1).split(",")) if ops else 0
        declared[m.group(2)] = arity
    return declared


def main():
    declared = declared_prims(open(os.path.join(ROOT, "include", "NixDialect", IRDL)).read())
    env = dict(os.environ, NIX_REMOTE="dummy://")
    out = subprocess.run([os.path.join(ROOT, "build", "bin", "mlnix"), "primops"], env=env,
                         capture_output=True, text=True, check=True).stdout
    registered = {k: int(a) for k, a in (l.split() for l in out.splitlines())}
    bad = False
    for k in sorted(set(registered) - set(declared)):
        print(f"registered but not declared in {IRDL}: {k}")
        bad = True
    for k in sorted(set(declared) - set(registered)):
        print(f"declared in {IRDL} but not registered: {k}")
        bad = True
    for k in sorted(set(declared) & set(registered)):
        if declared[k] != registered[k]:
            print(f"arity mismatch for {k}: irdl {declared[k]}, runtime {registered[k]}")
            bad = True
    print(f"primops: {len(registered)} registered, {len(declared)} declared" + ("" if not bad else "  -- MISMATCH"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
