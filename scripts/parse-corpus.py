#!/usr/bin/env python3
"""Compare the parser of two builds over a corpus of .nix files, byte for byte.

A lexer or parser change must be invisible: every file has to print the same AST (or the same
error, at the same position) as before.  Runs `mlnix-parse` of both builds over every .nix file
under the given directories (default: the nixpkgs checkout and test/), compares the output,
and times each side (parse + print, interleaved, best of N).

usage: parse-corpus.py [--runs N] OLD-MLNIX-PARSE NEW-MLNIX-PARSE [DIR ...]
"""
import argparse, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("dirs", nargs="*", default=[os.path.join(ROOT, ".cache", "nixpkgs"), os.path.join(ROOT, "test")])
    a = ap.parse_args()
    files = sorted(os.path.join(d, f) for top in a.dirs for d, _, fs in os.walk(top) for f in fs if f.endswith(".nix"))
    lst = tempfile.NamedTemporaryFile("w", suffix=".list", delete=False)
    lst.write("\n".join(os.path.abspath(f) for f in files) + "\n")
    lst.close()
    out, best, info = {}, {}, ""
    for r in range(a.runs):
        for tag, exe in (("old", a.old), ("new", a.new)):
            p = subprocess.run([exe, lst.name], capture_output=True)
            m = p.stderr.decode().strip().splitlines()[-1]
            t = float(m.rsplit(",", 1)[1].split()[0])
            best[tag] = min(best.get(tag, 1e9), t)
            out[tag] = p.stdout
            info = m
    os.unlink(lst.name)
    same = out["old"] == out["new"]
    print(f"{len(files)} files; {info.split(',', 1)[1].strip()}")
    print(f"old {best['old']:.2f} s   new {best['new']:.2f} s   ({100 * (best['new'] / best['old'] - 1):+.1f}%)")
    print("IDENTICAL" if same else "DIFFERENT")
    if not same:
        import difflib
        d = list(difflib.unified_diff(out["old"].decode(errors="replace").splitlines(), out["new"].decode(errors="replace").splitlines(), lineterm="", n=0))
        print("\n".join(d[:20]))
    sys.exit(0 if same else 1)


if __name__ == "__main__":
    main()
