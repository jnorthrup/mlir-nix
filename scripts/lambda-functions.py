#!/usr/bin/env python3
"""Rank the functions that take the lambda calls, from the 'busiest lambdas' section of MLNIX_STATS=1 MLNIX_STATS_LAMBDAS=N output.

A curried function is one lambda per argument, all on one line of source, so the rows are grouped by (file, line): `calls` is the
sum over the group (the interpreter's work), `entries` the largest single row (how many times the function was called at all), `depth`
the number of lambdas on the line.

usage: lambda-functions.py STATS.txt [--top N]
"""
import re, sys, collections

ROW = re.compile(r"^\s+(\d+)\s+([\d.]+)%\s+(\d+) ops\s+(\S+):(\d+):(\d+)\s+(.*)$")


def main():
    path = sys.argv[1]
    top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 40
    groups = collections.OrderedDict()
    total = None
    for ln in open(path, errors="replace"):
        if m := re.match(r"== lambda calls: (\d+) calls", ln):
            total = int(m[1])
        if not (m := ROW.match(ln)):
            continue
        calls, _, ops, file, line, col, text = int(m[1]), m[2], int(m[3]), m[4], int(m[5]), int(m[6]), m[7]
        g = groups.setdefault((file, line), {"calls": 0, "entries": 0, "depth": 0, "ops": 0, "text": text})
        g["calls"] += calls
        g["entries"] = max(g["entries"], calls)
        g["depth"] += 1
        g["ops"] += ops
    if total is None:
        sys.exit("no '== lambda calls:' line: run with MLNIX_STATS=1")
    ranked = sorted(groups.items(), key=lambda kv: -kv[1]["calls"])
    seen = sum(g["calls"] for g in groups.values())
    print("%d lambda calls in all; the rows given cover %d of them (%.1f%%), in %d functions" % (total, seen, 100 * seen / total, len(groups)))
    print("%10s %6s %6s %9s %5s %4s  %s" % ("calls", "share", "cum.", "entries", "depth", "ops", "where, and the line"))
    acc = 0
    for (file, line), g in ranked[:top]:
        acc += g["calls"]
        name = g["text"][:64]
        print("%10d %5.1f%% %5.1f%% %9d %5d %4d  %s:%d  %s" % (g["calls"], 100 * g["calls"] / total, 100 * acc / total, g["entries"], g["depth"], g["ops"],
                                                              file, line, name))
    # by file, and the share of the calls that are in functions of at most N ops (all levels together)
    by = collections.Counter()
    for (file, _), g in groups.items():
        by[file] += g["calls"]
    print()
    for cut in (4, 8, 16, 32):
        small = sum(g["calls"] for g in groups.values() if g["ops"] <= cut)
        print("functions of at most %2d ops (all levels together): %5.1f%% of all calls" % (cut, 100 * small / total))


if __name__ == "__main__":
    main()
