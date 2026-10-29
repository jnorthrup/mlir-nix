#!/usr/bin/env python3
"""Check schedule isolation and invalid round counts in the reference harness."""
import contextlib
import importlib.util
import io
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("vs_nix", Path(__file__).with_name("vs-nix.py"))
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
STARTUP = hashlib.sha256(b"1\n").hexdigest()[:12]


class Harness(unittest.TestCase):
    def test_schedule_is_independent_of_inherited_demand_flag(self):
        schedules = []

        def run(_binary, _args, extra=None, cap=None):
            env = dict(os.environ)
            env.update(extra or {})
            schedules.append("MLNIX_DEFER" in env)
            return 1.0, 42.0, 0, STARTUP

        argv = ["vs-nix.py", "--native", "--runs", "1", "--demand",
                "--ref", "Nix=/reference", "--workload", "nixos-toplevel"]
        with patch.dict(os.environ, {"MLNIX_DEFER": "1"}), patch("sys.argv", argv), \
                patch.object(bench, "machine", return_value="test host"), \
                patch.object(bench, "host", return_value="reference version"), \
                patch.object(bench, "run_once", side_effect=run), \
                patch.object(bench, "nix_once", return_value=(1.0, 0, STARTUP)), \
                patch.object(bench, "nix_rss_and_cpu", return_value=(42.0, 1.0, 1, 1.0)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(bench.main(), 0)
        # Five startup samples per schedule, then one measured pair.
        self.assertEqual(schedules, [False] * 5 + [True] * 5 + [False, True])

    def compare(self, mlnix=None, reference=None, runs=1, startup=None):
        """Use successful startup probes, then controlled workload outcomes."""
        a_samples = iter(mlnix or [(1.0, 42.0, 0, "same")] * runs)
        r_samples = iter(reference or [(1.0, 0, "same")] * runs)

        def run(_binary, args, extra=None, cap=None):
            if args[-2:] == ["-E", "1"]:
                return startup or (1.0, 42.0, 0, STARTUP)
            return next(a_samples)

        def nix(args, *_args, **_kwargs):
            return (1.0, 0, STARTUP) if args == "--eval -E 1" else next(r_samples)

        argv = ["vs-nix.py", "--native", "--runs", str(runs),
                "--ref", "Nix 2.35.4=/reference", "--workload", "nixos-toplevel"]
        output = io.StringIO()
        with patch("sys.argv", argv), patch.object(bench, "machine", return_value="test host"), \
                patch.object(bench, "host", return_value="reference version"), \
                patch.object(bench, "run_once", side_effect=run), patch.object(bench, "nix_once", side_effect=nix), \
                patch.object(bench, "nix_rss_and_cpu", return_value=(42.0, 1.0, 1, 1.0)), \
                contextlib.redirect_stdout(output):
            rc = bench.main()
        return rc, output.getvalue()

    def rejected(self, result, message):
        rc, output = result
        self.assertEqual(rc, 1, output)
        self.assertIn(message, output)
        self.assertNotIn("identical output from all: yes", output)
        self.assertNotIn("median x", output)
        self.assertFalse(any(bench.benchref.GOLD.match(line) for line in output.splitlines()))

    def test_nonzero_and_signal_are_not_accepted(self):
        for code in (7, -11):
            with self.subTest(code=code):
                self.rejected(self.compare(mlnix=[(1.0, 42.0, code, "same")]), f"failed rc={code}")
                self.rejected(self.compare(reference=[(1.0, code, "same")]), f"failed rc={code}")

    def test_all_arms_failing_with_equal_empty_output_are_not_an_oracle(self):
        empty = hashlib.sha256(b"").hexdigest()[:12]
        self.rejected(self.compare(mlnix=[(0.0, 0.0, 1, empty)], reference=[(0.0, 1, empty)]), "failed rc=1")

    def test_different_and_changing_answers_are_not_accepted(self):
        self.rejected(self.compare(mlnix=[(1.0, 42.0, 0, "different")]), "output mismatch")
        self.rejected(self.compare(mlnix=[(1.0, 42.0, 0, "same"), (1.0, 42.0, 0, "changed")], runs=2),
                      "output mismatch in round 2")
        self.rejected(self.compare(reference=[(1.0, 0, "same"), (1.0, 0, "changed")], runs=2),
                      "output mismatch in round 2")

    def test_startup_must_succeed_and_evaluate_one(self):
        self.rejected(self.compare(startup=(0.0, 0.0, -5, STARTUP)), "start-up: mlnix rejected rc=-5")
        self.rejected(self.compare(startup=(0.0, 0.0, 0, "wrong")), "start-up: mlnix rejected rc=0")

    def reuse(self, records, answer="2057239a9017", host="test host"):
        argv = ["vs-nix.py", "--native", "--runs", "1", "--demand", "--reuse-refs",
                "--records", str(records), "--ref", "Nix 2.35.4=/must/not/run",
                "--ref", "Lix 2.91.3=/must/not/run", "--workload", "nixos-toplevel"]

        def run(_binary, args, *_args, **_kwargs):
            return (1.0, 42.0, 0, STARTUP if args[-2:] == ["-E", "1"] else answer)

        output = io.StringIO()
        with patch("sys.argv", argv), patch.object(bench, "machine", return_value=host), \
                patch.object(bench, "host", side_effect=AssertionError("reference invocation")), \
                patch.object(bench, "nix_once", side_effect=AssertionError("reference timing")), \
                patch.object(bench, "nix_rss_and_cpu", side_effect=AssertionError("reference stats")), \
                patch.object(bench, "run_once", side_effect=run), contextlib.redirect_stdout(output):
            rc = bench.main()
        return rc, output.getvalue()

    def records(self, directory):
        for i in range(2):
            generation = Path(directory) / f"0{i + 1}-test"
            generation.mkdir()
            (generation / "nixos-toplevel.txt").write_text(
                "test host\n"
                "== nixos-toplevel (5 interleaved rounds; output sha256 2057239a9017; identical output from all: yes)\n"
                "   Nix 2.35.4 min 3.00s median 4.00s peak RSS 600 MB\n"
                "   Lix 2.91.3 min 4.00s median 5.00s peak RSS 700 MB\n")

    def test_reused_references_never_execute_even_for_startup_or_version(self):
        with tempfile.TemporaryDirectory() as directory:
            self.records(directory)
            rc, output = self.reuse(directory)
            self.assertEqual(rc, 0, output)
            self.assertIn("[pinned: cached, best of 2 generations", output)
            self.assertIn("identical output from all: yes", output)
            self.rejected(self.reuse(directory, answer="different"), "output mismatch")
            self.rejected(self.reuse(directory, host="other host"), "cached references unavailable")

    def test_missing_or_failed_records_never_trigger_reference_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            self.rejected(self.reuse(directory), "cached references unavailable")
            self.records(directory)
            bad = Path(directory) / "02-test/nixos-toplevel.txt"
            bad.write_text(bad.read_text() + "nixos-toplevel: mlnix failed rc=7\n")
            self.rejected(self.reuse(directory), "cached references unavailable")

    def test_gc_environment_reaches_evaluator_and_stats_failures_propagate(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "reference"
            binary.write_text('#!/bin/bash\n[ "$GC_INITIAL_HEAP_SIZE" = 4g ] || exit 9\nprintf "1\\n"\n')
            binary.chmod(0o755)
            with patch.object(bench, "NATIVE", True):
                _, code, answer = bench.nix_once("--eval -E 1", directory, "GC_INITIAL_HEAP_SIZE=4g", str(binary))
                self.assertEqual((code, answer), (0, STARTUP))
                # A failed stats process must not be hidden by the final echo.
                with self.assertRaises(SystemExit):
                    bench.nix_rss_and_cpu("--eval -E 1", directory, str(binary))

    def test_nonpositive_rounds_rejected_before_running(self):
        for rounds in ("0", "-1"):
            with self.subTest(rounds=rounds), patch("sys.argv", ["vs-nix.py", "--runs", rounds]), \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as exc:
                bench.main()
            self.assertEqual(exc.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
