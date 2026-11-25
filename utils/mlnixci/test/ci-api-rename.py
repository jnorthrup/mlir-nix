#!/usr/bin/env python3
"""ci-api: a copy of an mlnixci .mlir with every symbol it defines renamed old_<name> (functions with a body, globals with
a definition), so that the old and new versions of one module can be linked into one shared object for a differential.
usage: ci-api-rename.py IN.mlir OUT.mlir   (prints the renamed names; the rest of the module is unchanged)"""
import re
import sys

src = open(sys.argv[1]).read()
lines = src.split("\n")
defined = set()
for ln in lines:
    m = re.match(r"^\s*func\.func\s+(?!private\b)(@\w+)\b", ln)  # func.func without private has a body
    if m:
        defined.add(m.group(1)[1:])
    m = re.match(r"^\s*llvm\.func\s+(?!private\b)(@\w+)\b.*\{\s*$", ln)
    if m:
        defined.add(m.group(1)[1:])
    m = re.match(r"^\s*(?:llvm\.mlir\.global|memref\.global)\s+(?:(?:internal|private|external|constant)\s+)*@(\w+)", ln)
    if m:
        defined.add(m.group(1))
pat = re.compile(r"@(\w+)")
out = []
for ln in lines:
    out.append(pat.sub(lambda m: "@old_" + m.group(1) if m.group(1) in defined else m.group(0), ln))
open(sys.argv[2], "w").write("\n".join(out))
print(" ".join(sorted(defined)))
