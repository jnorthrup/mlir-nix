#!/bin/bash
# bash scripts/ir-pairs.sh [clang++]: what survives of each pair in scripts/ir-pairs.cc at -O2
CXX=${1:-clang++}
$CXX -std=c++20 -O2 -S -emit-llvm -I include scripts/ir-pairs.cc -o /tmp/ir-pairs.ll || exit 1
python3 - <<'PY'
import re
txt=open("/tmp/ir-pairs.ll").read()
print(f"{'function':20s} {'alloca':>6s} {'load':>5s} {'store':>6s} {'call':>5s} {'IR lines':>9s}  signature")
for m in re.finditer(r"define [^@]*@(\w+)\(([^)]*)\)[^{]*\{(.*?)\n\}",txt,re.S):
    name,args,body=m.groups()
    if name in("slice","sliceOfSlice","trimmedLength","cursorWalk","pack","unpack","joinsSum","sumByValue","sumThis","sumValueClobber"):
        n=lambda op: len(re.findall(r"^\s+(?:%\S+ = )?"+op+r"\b",body,re.M))
        print(f"{name:20s} {n('alloca'):6d} {n('load'):5d} {n('store'):6d} {n('call'):5d} {body.count(chr(10)):9d}  ({args[:70]})")
PY
