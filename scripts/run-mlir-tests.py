#!/usr/bin/env python3
"""Run the FileCheck tests in test/mlir (a minimal lit: `// RUN:` lines).

Each RUN line is executed with `%s` replaced by the test file (`%S`: its directory) and with
build/bin (mlnix, mlnix-opt) and the LLVM bin dir (FileCheck, not) on PATH.

A RUN line may start with `[feature]`; it is skipped, and the skip is reported, when this LLVM lacks the feature.
Features are probed by running something small (see probe_features), not read from a version string.

usage: run-mlir-tests.py [-v] [FILTER]
"""
import glob, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLVM_BIN = os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")


def probe_features(env):
    """What this LLVM can do that a test may depend on.

    cse-dynamic-ops: the stock `cse` merges two equal ops of an IRDL-defined dialect.  LLVM 22's
    DynamicOpDefinition::compareProperties returns false, so there two such ops are never equal: a test that
    expects a merge cannot pass, and one that expects two ops to stay apart passes without proving anything.
    LLVM 23 returns true.
    """
    probe = os.path.join(ROOT, "test", "mlir", "inputs", "probe-cse.mlir")
    p = subprocess.run(["bash", "-c", f"mlnix-opt {probe} -cse"], env=env, cwd=ROOT, capture_output=True, text=True)
    return {"cse-dynamic-ops": p.returncode == 0 and p.stdout.count("nixnum.add") == 1}


def main():
    verbose = "-v" in sys.argv
    filt = next((a for a in sys.argv[1:] if not a.startswith("-")), "")
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([os.path.join(ROOT, "build", "bin"), LLVM_BIN, env.get("PATH", "")])
    tmp = tempfile.mkdtemp(prefix="mlnix-mlir-test-")
    env.update({"NIX_REMOTE": "dummy://", "MLNIX_STORE_ROOT": tmp + "/root", "MLNIX_STATE_DIR": tmp + "/state"})
    feats = probe_features(env)
    passed = failed = 0
    skipped = []  # (file, feature) of the RUN lines not run
    for f in sorted(glob.glob(os.path.join(ROOT, "test", "mlir", "*.mlir"))):
        if filt not in os.path.basename(f):
            continue
        text = open(f).read()
        runs = re.findall(r"^// RUN: (.*)$", text, re.M)
        ok = True
        ran = 0
        for cmd in runs:
            gate = re.match(r"\[([\w-]+)\]\s+(.*)$", cmd)
            if gate:
                feature, cmd = gate.groups()
                if not feats.get(feature, False):
                    skipped.append((os.path.basename(f), feature))
                    continue
            ran += 1
            cmd = cmd.replace("%S", os.path.dirname(f)).replace("%s", f)
            p = subprocess.run(["bash", "-c", "set -o pipefail; " + cmd], env=env, cwd=ROOT,
                               capture_output=True, text=True)
            if p.returncode != 0:
                ok = False
                print(f"FAIL {os.path.basename(f)}\n  $ {cmd}\n{p.stdout}{p.stderr}")
        if not ok:
            failed += 1
        elif ran == 0:
            continue  # every RUN line of it was skipped: neither a pass nor a failure
        else:
            passed += 1
            if verbose:
                print(f"PASS {os.path.basename(f)}")
    for name, feature in skipped:
        print(f"SKIP {name}: a RUN line needs {feature}, which this LLVM lacks")
    note = f", {len(skipped)} run lines skipped ({', '.join(sorted({ft for _, ft in skipped}))})" if skipped else ""
    print(f"mlir tests: {passed} passed, {failed} failed{note}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
