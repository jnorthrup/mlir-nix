#!/usr/bin/env python3
"""Exercise the A/B acceptance gate with real child processes, including failed and unstable evaluators."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("ab.py")


class Acceptance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mlnix-check-ab-")
        self.addCleanup(self.tmp.cleanup)
        self.binary = Path(self.tmp.name) / "evaluator"
        self.binary.write_text(f"#!{sys.executable}\n" + '''
import os
import json
from pathlib import Path
if "READ_SAMPLES" in os.environ:
    rows = Path(os.environ["READ_SAMPLES"]).read_text().splitlines()
    assert len(rows) == int(os.environ["EXPECT_ROWS"]), rows
    for row in rows:
        json.loads(row)
if "ORDER" in os.environ:
    with open(os.environ["ORDER"], "a") as f:
        f.write(os.environ["ARM"])
if "COUNTER" in os.environ:
    p = Path(os.environ["COUNTER"])
    n = int(p.read_text()) + 1 if p.exists() else 0
    p.write_text(str(n))
    print(n)
else:
    print(os.environ.get("ANSWER", "42"))
raise SystemExit(int(os.environ.get("EXIT", "0")))
''')
        self.binary.chmod(0o755)

    def compare(self, a="-", b="-", runs=2, binary_b=None, samples=None, env=None):
        cmd = [sys.executable, str(SCRIPT), "--mlnix", str(self.binary),
               "--runs", str(runs), "--workload", "nixos-toplevel"]
        if binary_b is not None:
            cmd += ["--mlnix-b", str(binary_b)]
        if samples is not None:
            cmd += ["--samples", str(samples)]
        return subprocess.run(cmd + ["--", a, b], capture_output=True, text=True, timeout=20, env=env)

    def rejected(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("B vs A:", result.stdout)
        self.assertIn(message, result.stderr)

    def test_identical_success_rotates_first_arm(self):
        order = Path(self.tmp.name) / "order"
        r = self.compare(f"ORDER={order};ARM=A", f"ORDER={order};ARM=B", runs=3)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("identical output from all: yes", r.stdout)
        self.assertEqual(order.read_text(), "ABBAAB")

    def test_same_output_does_not_hide_failed_evaluation(self):
        self.rejected(self.compare(b="EXIT=7"), "FAILED rc=7")

    def test_two_failed_evaluations_are_not_a_comparison(self):
        self.rejected(self.compare(a="EXIT=1", b="EXIT=1"), "FAILED rc=1")

    def test_different_answers(self):
        self.rejected(self.compare(b="ANSWER=43"), "output mismatch")

    def test_same_arm_changes_answer_between_rounds(self):
        counter = Path(self.tmp.name) / "counter"
        self.rejected(self.compare(a="ANSWER=0", b=f"COUNTER={counter}"), "output mismatch in round 2")

    def test_missing_executable(self):
        self.rejected(self.compare(binary_b=Path(self.tmp.name) / "absent"), "FAILED")

    def test_no_rounds_is_invalid(self):
        self.rejected(self.compare(runs=0), "--runs must be positive")

    def test_samples_keep_rotating_order_and_exact_individual_results(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        env = dict(os.environ, AB_INHERITED_SENTINEL="not-to-be-serialized")
        r = self.compare(a="ARM=A;API_TOKEN=not-a-real-token", b="ARM=B", runs=3, samples=path, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual([x["arm"] for x in rows], list("ABBAAB"))
        self.assertEqual([x["round"] for x in rows], [1, 1, 2, 2, 3, 3])
        self.assertEqual([x["position"] for x in rows], [1, 2, 1, 2, 1, 2])
        self.assertEqual([x["sequence"] for x in rows], list(range(1, 7)))
        self.assertNotIn("AB_INHERITED_SENTINEL", path.read_text())
        self.assertNotIn("not-to-be-serialized", path.read_text())
        self.assertNotIn("not-a-real-token", path.read_text())
        for row in rows:
            self.assertEqual(row["environment"], {"ARM": "A", "API_TOKEN": "[redacted]"} if row["arm"] == "A" else {"ARM": "B"})
            self.assertEqual(row["workload"], "nixos-toplevel")
            self.assertEqual(row["binary"], str(self.binary))
            self.assertEqual(row["returncode"], 0)
            self.assertEqual(row["status"], "completed")
            self.assertEqual(row["stdout_sha256"], hashlib.sha256(b"42\n").hexdigest())
            self.assertGreater(row["wall_seconds"], 0)
            self.assertGreater(row["cpu_seconds"], 0)
            self.assertGreater(row["peak_rss_gb"], 0)
        for arm in "AB":
            samples = [x for x in rows if x["arm"] == arm]
            self.assertIn(f"wall med {statistics.median(x['wall_seconds'] for x in samples):6.3f}s min {min(x['wall_seconds'] for x in samples):6.3f}s", r.stdout)

    def test_samples_are_created_before_children_and_flushed_between_them(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        r = self.compare(a=f"READ_SAMPLES={path};EXPECT_ROWS=0", b=f"READ_SAMPLES={path};EXPECT_ROWS=1", runs=1, samples=path)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(path.read_text().splitlines()), 2)

    def test_existing_sample_file_is_preserved_and_no_child_starts(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        path.write_text("preserve\n")
        order = Path(self.tmp.name) / "order"
        r = self.compare(a=f"ORDER={order};ARM=A", samples=path)
        self.rejected(r, "cannot create sample file")
        self.assertEqual(path.read_text(), "preserve\n")
        self.assertFalse(order.exists())

    def test_failed_child_retains_prior_and_failed_samples(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        self.rejected(self.compare(b="EXIT=7", samples=path), "FAILED rc=7")
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual([x["returncode"] for x in rows], [0, 7])
        self.assertTrue(all(x["stdout_sha256"] == hashlib.sha256(b"42\n").hexdigest() for x in rows))

    def test_mismatch_retains_both_full_hashes(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        self.rejected(self.compare(b="ANSWER=43", samples=path), "output mismatch")
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual([x["stdout_sha256"] for x in rows], [hashlib.sha256(x).hexdigest() for x in (b"42\n", b"43\n")])

    def test_startup_failure_retains_attempt_without_fabricated_measurements(self):
        path = Path(self.tmp.name) / "samples.jsonl"
        self.rejected(self.compare(binary_b=Path(self.tmp.name) / "absent", samples=path), "FAILED")
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[1]["status"], "startup_error")
        for key in ("returncode", "stdout_sha256", "wall_seconds", "cpu_seconds", "peak_rss_gb"):
            self.assertIsNone(rows[1][key])


if __name__ == "__main__":
    unittest.main()
