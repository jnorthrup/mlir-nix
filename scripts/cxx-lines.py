#!/usr/bin/env python3
"""Count the C++ of the repository, by area, and compare two revisions.

The rule: the C++ of the repository as a whole only goes down.  A candidate (an experiment, a change) must have fewer C++ code lines than
the state it starts from; the total may move between modules (into the Composite kernel, into a dialect) but the sum must fall.  Code
lines are the lines of every tracked *.cpp, *.h, *.hpp and *.cc (tests and experiments included) that are not blank and not only a
comment.  The dialect declarations (*.td, *.irdl.mlir) are shown beside the C++, not in it, so that a move into a dialect shows as lines
gone from one column and fewer added to the other.

usage: cxx-lines.py [--rev REV] [--base REV] [--ratchet]
  (nothing)        the working tree
  --rev REV        a revision instead of the working tree
  --base REV       also print the change from REV to the working tree (or to --rev), by area
  --ratchet        with --base: exit 1 unless the C++ code lines went down
"""
import argparse, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CXX = (".cpp", ".h", ".hpp", ".cc")
DECL = (".td", ".irdl.mlir")


def git(*a):
    return subprocess.run(["git", "-C", ROOT] + list(a), capture_output=True, text=True, check=True).stdout


def code_lines(text):
    """Lines holding something that is not a comment: a small scanner for // and /* */, with strings and characters."""
    n, block, i, code = 0, False, 0, False
    s = text
    L = len(s)
    in_str = in_chr = in_line = False
    while i < L:
        c = s[i]
        if c == "\n":
            n += code
            code, in_line = False, False
            i += 1
            continue
        if in_line:
            i += 1
        elif block:
            if s.startswith("*/", i):
                block = False
                i += 2
            else:
                i += 1
        elif in_str or in_chr:
            code = True
            if c == "\\":
                i += 2
                continue
            if (in_str and c == '"') or (in_chr and c == "'"):
                in_str = in_chr = False
            i += 1
        elif s.startswith("//", i):
            in_line = True
            i += 2
        elif s.startswith("/*", i):
            block = True
            i += 2
        else:
            if c == '"':
                in_str = True
            elif c == "'" and not (i > 0 and (s[i - 1].isalnum() or s[i - 1] == "_")):  # not a digit separator
                in_chr = True
            if not c.isspace():
                code = True
            i += 1
    return n + code


def files(rev):
    names = git("ls-tree", "-r", "--name-only", rev).split("\n") if rev else git("ls-files").split("\n")
    return [f for f in names if f.endswith(CXX + DECL)]


def read(rev, f):
    if rev:
        return git("show", "%s:%s" % (rev, f))
    with open(os.path.join(ROOT, f), errors="replace") as fh:
        return fh.read()


def area(f):
    p = f.split("/")
    return "/".join(p[:2]) if p[0] in ("lib", "include", "test") and len(p) > 2 else p[0]


def count(rev):
    cxx, decl = {}, {}
    for f in files(rev):
        text = read(rev, f)
        if f.endswith(DECL):
            decl[area(f)] = decl.get(area(f), 0) + code_lines(text)  # TableGen and IRDL share // and /* */ with C++
        else:
            cxx[area(f)] = cxx.get(area(f), 0) + code_lines(text)
    return cxx, decl


def show(title, cxx, decl, base=None):
    areas = sorted(set(cxx) | set(decl) | (set(base[0]) | set(base[1]) if base else set()))
    print("%-22s %9s %9s" % (title, "C++", "dialect") + ("   %8s %8s" % ("d C++", "d dialect") if base else ""))
    for a in areas:
        line = "%-22s %9d %9d" % (a, cxx.get(a, 0), decl.get(a, 0))
        if base:
            line += "   %+8d %+8d" % (cxx.get(a, 0) - base[0].get(a, 0), decl.get(a, 0) - base[1].get(a, 0))
        print(line)
    tc, td = sum(cxx.values()), sum(decl.values())
    line = "%-22s %9d %9d" % ("total", tc, td)
    if base:
        line += "   %+8d %+8d" % (tc - sum(base[0].values()), td - sum(base[1].values()))
    print(line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev")
    ap.add_argument("--base")
    ap.add_argument("--ratchet", action="store_true")
    a = ap.parse_args()
    cxx, decl = count(a.rev)
    if a.base:
        b = count(a.base)
        show("area", cxx, decl, b)
        delta = sum(cxx.values()) - sum(b[0].values())
        if a.ratchet and delta >= 0:
            sys.exit("cxx-lines: the C++ code lines went %s by %d against %s: a candidate must have fewer" % ("up" if delta > 0 else "nowhere, change", abs(delta), a.base))
    else:
        show("area", cxx, decl)


if __name__ == "__main__":
    main()
