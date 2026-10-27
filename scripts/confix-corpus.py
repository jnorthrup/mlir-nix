#!/usr/bin/env python3
"""Check the Confix scan against the lexer over a corpus of .nix files.

`mlnix-parse -b` lexes every file with the real lexer, derives the table of delimiter pairs ("bands") from its tokens,
and compares it with the table of confix::scan, which never builds a token.  They must agree on every file: the same
bands, or both reject.  With --fuzz, random mutations of the first files are compared too (most are not Nix; the two
still have to agree on whether they are balanced).  Prints the speed of both.

usage: confix-corpus.py [--fuzz SEED]... MLNIX-PARSE [DIR ...]
"""
import argparse, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fuzz", type=int, action="append", default=[], metavar="SEED")
    ap.add_argument("exe")
    ap.add_argument("dirs", nargs="*", default=[os.path.join(ROOT, ".cache", "nixpkgs"), os.path.join(ROOT, "test")])
    a = ap.parse_args()
    files = sorted(os.path.join(d, f) for top in a.dirs for d, _, fs in os.walk(top) for f in fs if f.endswith(".nix"))
    lst = tempfile.NamedTemporaryFile("w", suffix=".list", delete=False)
    lst.write("\n".join(os.path.abspath(f) for f in files) + "\n")
    lst.close()
    ok = True
    try:
        runs = [["-b"]] + [["-b", "-f", str(s)] for s in a.fuzz]
        for args in runs:
            p = subprocess.run([a.exe] + args + [lst.name], capture_output=True, text=True)
            print(p.stdout.strip())
            ok = ok and p.returncode == 0
    finally:
        os.unlink(lst.name)
    print("AGREE" if ok else "DISAGREE")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
