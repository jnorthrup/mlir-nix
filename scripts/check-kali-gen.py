#!/usr/bin/env python3
"""Ensure a failed correctness gate or timed run stops the Kali generation."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="mlnix-gates-") as tmp:
        tmp = Path(tmp)
        # Run the orchestration with cheap, controlled producers. A failure still
        # prints a plausible summary, exercising the old swallowed-status bug.
        producer = tmp / "python3"
        producer.write_text("""#!/bin/bash
printf '%s %s\\n' "$1" "${MLNIX_DEFER:-unset}" >> "$CALLS"
case "$1" in
  *run-lang-tests.py) echo 'TOTAL semantic 1/1 exact 1/1';;
  *run-mlir-tests.py) echo 'mlir tests: 1 passed, 0 failed';;
  *check-prims.py) echo 'primops: 1 registered, 1 declared';;
  *difftest.py) echo '1/1 identical';;
  *vs-nix.py) [[ " $* " == *" --reuse-refs "* ]] || exit 99;;
esac
[ "$1" != "$FAIL_SCRIPT" ]
""")
        producer.chmod(0o755)
        timeout = tmp / "timeout"
        timeout.write_text('#!/bin/bash\nshift\nexec "$@"\n')
        timeout.chmod(0o755)
        cases = ["", "run-lang-tests.py", "run-mlir-tests.py", "check-prims.py", "difftest.py", "vs-nix.py"]
        for i, failing in enumerate(cases):
            out = tmp / str(i)
            calls = tmp / f"calls-{i}"
            env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}", GEN_OUT=str(out),
                       NIX_BIN=shutil.which("true"), LIX_BIN=shutil.which("true"), CALLS=str(calls),
                       FAIL_SCRIPT=f"scripts/{failing}", MLNIX_DEFER="1")
            result = subprocess.run(["bash", str(ROOT / "scripts/kali-gen.sh"), "gates", "bench"],
                                    env=env, capture_output=True, text=True)
            assert (result.returncode == 0) == (not failing), (failing, result.stdout, result.stderr)
            ran = calls.read_text()
            assert "scripts/run-lang-tests.py unset" in ran, ran
            assert "scripts/run-lang-tests.py 1" in ran, ran
            if failing and failing != "vs-nix.py":
                assert "scripts/vs-nix.py" not in ran, ran
            assert (out / "lang-eager.txt").exists()
        print(f"kali generation: {len(cases)} status-propagation checks passed")


if __name__ == "__main__":
    main()
