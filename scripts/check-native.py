#!/usr/bin/env python3
"""Check the demand JIT against the interpreter, including errors and laziness."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ("argument", "let f = x: x * 3 + 7; in map f [1 2 3]", True),
    ("stable capture", "let k = builtins.add 1 2; f = x: x * k + 7; in builtins.seq k (map f [1 2 3])", True),
    ("separate closures", "let mk = n: let k = builtins.add n 1; in builtins.seq k (x: x * k + 2); a = mk 2; b = mk 5; in [ (a 1) (b 1) (a 2) (b 2) ]", True),
    ("unused argument", "let f = x: 42; in f (throw \"unused\")", True),
    ("dead graph", "let f = x: let cycle = cycle; in x * 2; in f 3", True),
    ("mixed numeric input", "let f = x: x * 3 + 7; in map f [1 1.5 2]", True),
    ("string fallback", "let f = x: x + x; in map f [1 \"a\" 2]", True),
    ("add overflow", "let f = x: x + 1; in map f [1 9223372036854775807]", True),
    ("multiply overflow", "let f = x: x * x; in map f [1 9223372036854775807]", True),
    ("subtract overflow", "let f = x: x - 1; in map f [1 (-9223372036854775807 - 1)]", True),
    ("error order", "let f = x: (9223372036854775807 + 1) + x; in f (throw \"must not run first\")", False),
    ("lazy branch", "let f = x: if x then 7 else throw \"branch\"; in f true", False),
    ("overridden builtin", "let __mul = x: y: x + y; f = x: x * 3; in map f [1 2]", False),
    ("recursive graph", "let f = x: let y = y + x; in y; in f 1", False),
]
TRACE = re.compile(r"^jit: compiled=(\d+) calls=(\d+) bailouts=(\d+) rejected=(\d+)\n", re.M)


def run(binary, expression, env):
    p = subprocess.run([str(binary), "eval", "--show-trace", "-E", expression],
                       cwd=ROOT, env=env, text=True, capture_output=True, timeout=30)
    traces = TRACE.findall(p.stderr)
    return (p.returncode, p.stdout, TRACE.sub("", p.stderr)), traces


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mlnix", type=Path, default=ROOT / "build/bin/mlnix")
    args = parser.parse_args()
    count = 0
    with tempfile.TemporaryDirectory(prefix="mlnix-native-") as tmp:
        base = dict(os.environ, NIX_REMOTE="dummy://", MLNIX_STORE_ROOT=tmp + "/root",
                    MLNIX_STATE_DIR=tmp + "/state")
        for key in ("MLNIX_JIT", "MLNIX_JIT_TRACE", "MLNIX_JIT_THRESHOLD", "MLNIX_STATS", "MLNIX_DEFER"):
            base.pop(key, None)
        for demand in (False, True):
            env = dict(base)
            if demand:
                env["MLNIX_DEFER"] = "1"
            for name, expression, native in CASES:
                before, _ = run(args.mlnix, expression, env)
                after, traces = run(args.mlnix, expression,
                                    dict(env, MLNIX_JIT="1", MLNIX_JIT_TRACE="1", MLNIX_JIT_THRESHOLD="1"))
                assert before == after, f"{name}, demand={demand}:\n{before!r}\n!=\n{after!r}"
                assert len(traces) == 1, f"{name}: missing JIT execution report; this test must not pass on an interpreter-only build"
                compiled, calls, _, _ = map(int, traces[0])
                if native:
                    assert compiled > 0 and calls > 0, f"{name}: no native execution: {traces[0]}"
                count += 1
        cold, trace = run(args.mlnix, "let f = x: x * 3 + 7; in f 1",
                          dict(base, MLNIX_JIT="1", MLNIX_JIT_TRACE="1", MLNIX_JIT_THRESHOLD="16"))
        assert cold[:2] == (0, "10\n"), cold
        assert len(trace) == 1 and trace[0][:2] == ("0", "0"), f"cold code compiled: {trace}"
    print(f"native tests: {count + 1} passed (both schedules, native execution required, cold code stays interpreted)")


if __name__ == "__main__":
    main()
