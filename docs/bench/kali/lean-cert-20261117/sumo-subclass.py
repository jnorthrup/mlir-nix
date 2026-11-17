#!/usr/bin/env python3
"""sumo-subclass.py SUMO_NIX OUT.kif [ORACLE.json]

SUMO's taxonomy as a theory for kif-chase: every top-level (subclass Child Parent) form of sumo.full (SUMO_NIX/sumo.full/PINS's
files, in its order) whose two arguments are not lists, as sumo.nix reads its `parents`, and the rule that makes the
ancestors of sumo.nix (`ancestors`: the parents and theirs) out of them:

    (=> (and (subclass ?X ?Y) (subclass ?Y ?Z)) (subclass ?X ?Z))

With ORACLE (test/kif/taxonomy-oracle.nix's output, through mlnix eval), the counts of this script's own closure of the
edges are checked against sumo.nix's: classes with a parent, ancestor links, and each class's number of ancestors."""
import json, re, sys
from collections import defaultdict

# bags-oracle.py's tokens: strings, parentheses, and the runs between them
TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"|[()]|[^\s()";]+|;[^\n]*')


def forms(text):
    stack, out = [], []
    for m in TOKEN.finditer(text):
        t = m.group(0)
        if t.startswith(";"):
            continue
        if t == "(":
            stack.append([])
        elif t == ")":
            done = stack.pop()
            (stack[-1] if stack else out).append(done)
        else:
            (stack[-1] if stack else out).append(t)
    return out


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    root, out = argv[1], argv[2]
    pins = [l.split() for l in open(f"{root}/sumo.full/PINS") if l.strip() and not l.startswith("#")]
    files = [f"{root}/sumo.full/{p[1]}" for p in pins if len(p) >= 2]
    edges, seen, n = [], set(), 0
    for f in files:
        for form in forms(open(f, encoding="utf-8", errors="replace").read()):
            n += 1
            if isinstance(form, list) and len(form) == 3 and form[0] == "subclass" and all(isinstance(x, str) for x in form[1:]):
                e = (form[1], form[2])
                if e not in seen:
                    seen.add(e)
                    edges.append(e)
    with open(out, "w", encoding="utf-8") as o:
        for c, p in edges:
            o.write(f"(subclass {c} {p})\n")
        o.write("(=> (and (subclass ?X ?Y) (subclass ?Y ?Z)) (subclass ?X ?Z))\n")
    print(f"{len(files)} files, {n} forms, {len(edges)} subclass edges -> {out}")
    if len(argv) > 3:
        parents = defaultdict(list)
        for c, p in edges:
            parents[c].append(p)
        memo = {}

        def anc(c):
            if c not in memo:
                memo[c] = None  # a cycle would show as None below
                s = set()
                for p in parents[c]:
                    s.add(p)
                    a = anc(p) if p in parents else set()
                    if a is None:
                        raise SystemExit(f"a cycle through {c}")
                    s |= a
                memo[c] = s
            return memo[c]

        sys.setrecursionlimit(100000)
        counts = [len(anc(c)) for c in sorted(parents)]
        want = json.load(open(argv[3]))
        print(f"classes with a parent: {len(parents)} (sumo.nix {want[0][2]}); ancestor links: {sum(counts)} "
              f"(sumo.nix {want[0][3]}); each class's count: {'equal' if counts == want[1] else 'DIFFERENT'}")
        return 0 if (len(parents), sum(counts), counts) == (want[0][2], want[0][3], want[1]) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
