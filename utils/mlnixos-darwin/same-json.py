#!/usr/bin/env python3
"""Compare two JSON values, the second possibly wrapped in other text (an oracle log):  same-json.py A B"""
import json, sys

a = json.load(open(sys.argv[1]))
t = open(sys.argv[2]).read()
start = min(i for i in (t.find("["), t.find("{")) if i >= 0)
end = max(t.rfind("]"), t.rfind("}")) + 1
b = json.loads(t[start:end])
if a == b:
    print(f"   SAME as the oracle ({len(a) if isinstance(a, list) else 1} values)")
else:
    print("   DIFFERENT from the oracle")
    for x, y in zip(a if isinstance(a, list) else [a], b if isinstance(b, list) else [b]):
        if x != y:
            print("     mlnix: ", x); print("     oracle:", y)
    sys.exit(1)
