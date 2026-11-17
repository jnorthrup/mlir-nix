# SUMO's 43 tq.nix-unsupported tests through `mlnix-kif --tptp`, Vampire and the Lean statement check (Kali, 2026-11-17)

`run-tests.sh` (Kali ~/tptp): each test's KIF with Merge.kif through `mlnix-kif --tptp`, Vampire 5.1.0 `--mode casc --cores 2
-t 60` under a 4 GB cap, and a `kif-tptp-compare.py --flat` comparison with SigmaKEE's problem for the test (test 2's). The
run was cut by a Windows Update restart after 27 tests and resumed (`RESUME=1`) for the other 16. `summary.py` sets each
line next to test 2's results (logs/vampire/runs.jsonl).

Against SigmaKEE's translation on the same settings (test 2's set `sigma`): both prove 18; ours alone TQG34; SigmaKEE's alone
TQC2 and TQROW-BUILTIN, whose conjectures our port does not write ("higher order"). Against test 2's best of any set (t300,
TFF, THF, sigma1): ours Theorem where it has one 19, both time out 10, ours times out where test 2 proved 6, ours writes no
conjecture 8 (2 of them proved by test 2).

The Lean link: `15-statements.py EXPORT` (lean4export of the 29 Vampire-Hammer theorems, regenerated from 14-export.sh's
oleans) gives 28 statements agreeing with the problems Vampire ran, 82 of 82 controls disagreeing (statements-base.txt).
With `--problems ~/tptp/tests sigma`, each sigma theorem against this run's own problem: 18 agree (the axioms its proof
used found in our problem by their formulas), 1 disagrees -- TQROW-BUILTIN, whose conjecture our problem lacks -- and 54 of
54 controls disagree (statements-ours.txt). So for 18 tests the chain KIF -> mlnix-kif TPTP -> Lean kernel term holds link
by link.
