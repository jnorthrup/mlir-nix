#!/usr/bin/env python3
"""Build and run the unit test of nixfe::PosTable (test/unit/pos-table.cpp).

usage: check-pos-table.py [--cxx COMPILER] [--include DIR ...]

The test includes "Nix/Pos.h" and needs nothing else.  --include puts a directory ahead of include/, which is how a mutated copy of the
header is tested (scripts never mutate the tree).  Exit status: 0 passed, 1 the test failed, 2 it did not build.
"""
import argparse, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    ap.add_argument("--include", action="append", default=[])
    a = ap.parse_args()
    with tempfile.TemporaryDirectory() as d:
        exe = os.path.join(d, "pos-table")
        sdk = []
        if sys.platform == "darwin":  # the Command Line Tools compiler does not find the C++ headers without the SDK
            r = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                sdk = ["-isysroot", r.stdout.strip()]
        cmd = [a.cxx, "-std=c++20", "-O1", "-Wall", "-Werror"] + sdk + ["-I" + i for i in a.include] + \
              ["-I" + os.path.join(ROOT, "include"), os.path.join(ROOT, "test", "unit", "pos-table.cpp"), "-o", exe]
        b = subprocess.run(cmd, capture_output=True, text=True)
        if b.returncode:
            sys.stderr.write(b.stderr)
            return 2
        r = subprocess.run([exe], capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)
        return 1 if r.returncode else 0


if __name__ == "__main__":
    sys.exit(main())
