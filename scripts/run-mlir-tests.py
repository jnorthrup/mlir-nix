#!/usr/bin/env python3
"""Run the FileCheck tests in test/mlir (a minimal lit: `// RUN:` lines).

Each RUN line is executed with `%s` replaced by the test file and with
build/bin (mlnix, mlnix-opt) and the LLVM bin dir (FileCheck, not) on PATH.

usage: run-mlir-tests.py [-v] [FILTER]
"""
import glob, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLVM_BIN = os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")


def main():
    verbose = "-v" in sys.argv
    filt = next((a for a in sys.argv[1:] if not a.startswith("-")), "")
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([os.path.join(ROOT, "build", "bin"), LLVM_BIN, env.get("PATH", "")])
    tmp = tempfile.mkdtemp(prefix="mlnix-mlir-test-")
    env.update({"NIX_REMOTE": "dummy://", "MLNIX_STORE_ROOT": tmp + "/root", "MLNIX_STATE_DIR": tmp + "/state"})
    passed = failed = 0
    for f in sorted(glob.glob(os.path.join(ROOT, "test", "mlir", "*.mlir"))):
        if filt not in os.path.basename(f):
            continue
        text = open(f).read()
        runs = re.findall(r"^// RUN: (.*)$", text, re.M)
        ok = True
        for cmd in runs:
            cmd = cmd.replace("%s", f)
            p = subprocess.run(["bash", "-c", "set -o pipefail; " + cmd], env=env, cwd=ROOT,
                               capture_output=True, text=True)
            if p.returncode != 0:
                ok = False
                print(f"FAIL {os.path.basename(f)}\n  $ {cmd}\n{p.stdout}{p.stderr}")
        if ok:
            passed += 1
            if verbose:
                print(f"PASS {os.path.basename(f)}")
        else:
            failed += 1
    print(f"mlir tests: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
