#!/usr/bin/env python3
"""native-check.py [--keep DIR] [F.nix ...]: each file through scripts/nix-native.sh (the LLVM arm's first cut, through
TrikeShed) and through `mlnix instantiate --eval --strict`.  A file compiled must print what mlnix prints and exit as it
does, with the same first line on stderr when it fails.  A file whose first line is `# refused: TEXT` must be refused by
the emitter (exit 2) with TEXT in its reason; any other refusal is a failure.  Default files: test/native/*.nix and
graal/bench/*.nix but attrs.nix (sets are not in the first cut).

Needs mlnix and mlnix-opt (BIN, default build/bin), nix-truffle installed (graal/: ./gradlew installDist), and LLVM's
mlir-opt, mlir-translate and clang (LLVM_BIN).  Exit 0 when every file is as expected."""
import glob, os, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
keep = None
if args[:1] == ["--keep"]:
    keep, args = args[1], args[2:]
files = args or sorted(glob.glob(os.path.join(REPO, "test/native/*.nix"))) + \
    [f for f in sorted(glob.glob(os.path.join(REPO, "graal/bench/*.nix"))) if not f.endswith("/attrs.nix")]
out = keep or tempfile.mkdtemp(prefix="native-check-")
os.makedirs(out, exist_ok=True)
BIN = os.environ.get("BIN", os.path.join(REPO, "build/bin"))
first = lambda s: (s.strip().splitlines() or [""])[0]
counts = {"same": 0, "refused": 0, "bad": 0}
for f in files:
    name = os.path.basename(f)[:-4]
    head = first(open(f).read())
    want_refusal = head[len("# refused:"):].strip() if head.startswith("# refused:") else None
    b = os.path.join(out, name)
    c = subprocess.run(["sh", os.path.join(REPO, "scripts/nix-native.sh"), f, b], cwd=REPO, capture_output=True, text=True)
    if c.returncode == 2:
        reason = c.stderr.strip().splitlines()[-1].split("refused: ", 1)[-1]
        ok = want_refusal is not None and want_refusal in reason
        counts["refused" if ok else "bad"] += 1
        print(f"{'refused' if ok else 'BAD':8} {name}: {reason}" + ("" if ok else "  (expected to compile)" if want_refusal is None else f"  (expected: {want_refusal})"))
        continue
    if c.returncode != 0:
        counts["bad"] += 1
        print(f"BAD      {name}: nix-native.sh exit {c.returncode}: {c.stderr.strip()[-400:]}")
        continue
    if want_refusal is not None:
        counts["bad"] += 1
        print(f"BAD      {name}: compiled, expected a refusal ({want_refusal})")
        continue
    n = subprocess.run([b], capture_output=True, text=True)
    m = subprocess.run([os.path.join(BIN, "mlnix"), "instantiate", "--eval", "--strict", f], capture_output=True, text=True)
    ok = n.stdout == m.stdout and n.returncode == m.returncode and (m.returncode == 0 or first(n.stderr) == first(m.stderr))
    counts["same" if ok else "bad"] += 1
    shown = (m.stdout.strip() or first(m.stderr))[:72]
    print(f"{'same' if ok else 'BAD':8} {name}: {shown}" +
          ("" if ok else f"   native: exit {n.returncode} {(n.stdout.strip() or first(n.stderr))[:72]}"))
print(f"native-check: {counts['same']} the same as mlnix, {counts['refused']} refused as expected, {counts['bad']} wrong"
      + (f"; programs in {out}" if keep else ""))
sys.exit(1 if counts["bad"] else 0)
