# mlnix-kif --lean on Kali, 2026-11-17

The certificate path of docs/REASONING-SPLIT.md, section 4: kif-chase's proofs as one Lean theorem in lean4export's format,
checked by the Lean 4.36 toolchain's kernels nanoda_bin 0.4.17, con-leche and con-ron (`--verified`, `--jobs=1`).  Kali is
x86_64 WSL2, 8 cores, 15.9 GB, shared with the live mini-luci demo; every run sat in a 4 GB cgroup scope without swap.
Harness: run.sh (paperclip), scale.sh (synthetic theories), shapes.py (hand-made certificates of one shape each); the repo's
scripts/kif-lean-check.py and scripts/kif-lean-kernels.py.

| log | mlir-nix | certificate form | what |
|---|---|---|---|
| run-1-pack-chase-order.log | be1bfdf | conclusion `pack d.1 .. d.n`, lets in the chase's order | paperclip stratum 1 |
| run-2-done-chase-order.log | 19defcd | conclusion `Done`, chase's order | paperclip stratum 1 |
| run-3-done-depth-first.log | e77887e | conclusion `Done`, lets depth first (as committed) | paperclip stratum 1 |
| scale-1-pack-chase-order.log | be1bfdf | pack, chase's order | N facts (p xi), p -> q -> r -> s: 3N lets; N=4000 stopped by hand |
| scale-2-done-chase-order.log | 19defcd | Done, chase's order | the same; N=16000 stopped by hand |
| scale-3-done-depth-first.log | f0bdc10 | Done, depth first | the same (s), and a hub every q uses (h); 120 s per kernel |

Paperclip stratum 1 (7,147 facts, 1,964 derived; a 5.05 MB certificate of 8,666 hypotheses and 1,964 lets), one kernel run:

| form | nanoda_bin | con-leche | con-ron |
|---|---|---|---|
| pack, chase's order | 1.91-1.93 s, 260 MB | 1.26-1.29 s, 197 MB | 1.41-1.52 s, 329 MB |
| Done, chase's order | 0.17-0.18 s, 33 MB | 0.30-0.33 s, 60 MB | 0.38-0.42 s, 101 MB |
| Done, depth first | 0.12-0.14 s, 19 MB | 0.26-0.32 s, 47 MB | 0.32-0.34 s, 83 MB |

In run-1 nanoda_bin's three control "rejections" are parse errors (the controls had two equal expression records, which
nanoda_bin refuses before checking: "Attempted to insert duplicate Expr"); kif-lean-check.py reuses equal expressions since
261433a, and in run-2 and run-3 every rejection is a type error (nanoda_bin: `assertion failed: self.def_eq(u, v)`;
con-leche and con-ron: "application type mismatch", or "let value type mismatch" for the last let).

shapes.py, run by hand (output not kept as a file): a chain of 6,000 lets each 200 back over 200 atoms checks in 0.4 s
(nanoda_bin 0.42 s, con-leche 0.39 s) when the body names the last let; with the body `pack d.1 .. d.6000` 22.6 s and 9.6 s;
with the body a balanced tree of And over the lets 9.9 s, 4.9 s and con-ron 5.1 s.  A plain chain of 8,000 lets each one back,
or one application to 8,000 lambda-bound arguments, 0.1 s.

Depth: nanoda_bin refuses a de Bruijn index past u16 ("invalid value: integer `80010`, expected u16", s16000: 32,008
hypotheses and 48,000 lets).  h16000 (about 64,000 deep) passes nanoda_bin in 0.93 s, and con-leche and con-ron did not finish
it in 120 s, where h4000 (about 16,000 deep) takes them 0.27 s and 0.33 s.

## Pieces (mlir-nix a894108, `--lean-piece N`): pieces.log, pieces.sh, sumo-subclass.py

pieces.sh runs, under a 6 GB scope, s16000 and h16000 (scale.sh's theories, which one theorem could not hold) and SUMO's
taxonomy: sumo-subclass.py reads sumo.full's 78 files (201,007 forms) for their 10,308 distinct top-level (subclass C P)
edges whose arguments are not lists, as sumo.nix reads `parents`, and adds the rule (=> (and (subclass ?X ?Y) (subclass ?Y
?Z)) (subclass ?X ?Z)).  kif-chase derives 80,096 links from them in 1.0 s and 210 MB; the closure, 90,404 links over 9,040
classes, is sumo.nix's `ancestors` class for class (each class's count against test/kif/taxonomy-oracle.nix's output,
~/kif-assess/out/step6b/oracle.json; checked once by hand after the run, not in the log).

| theory, pieces of | theorems | hypotheses in all (imports) | deepest | MB | nanoda_bin | con-leche | con-ron |
|---|---|---|---|---|---|---|---|
| s16000 (48,000 lets), 4,000 | 12 | 32,172 (8) | 6,681 | 19.3 | 0.47 s | 0.98 s | 1.31 s |
| s16000, 8,000 | 6 | 32,086 (4) | 13,349 | 25.1 | 0.58 s | 1.18 s | 1.51 s |
| s16000, 16,000 | 3 | 32,043 (2) | 26,681 | 29.4 | 0.73 s | 1.47 s | 1.59 s |
| h16000 (32,001 lets), 4,000 | 9 | 32,131 (15) | 8,015 | 15.8 | 0.42 s | 0.80 s | 1.08 s |
| h16000, 8,000 | 5 | 32,071 (7) | 16,015 | 19.8 | 0.54 s | 0.99 s | 1.16 s |
| h16000, 16,000 | 3 | 32,041 (3) | 32,015 | 24.4 | 0.68 s | 1.20 s | 1.32 s |
| SUMO taxonomy (80,096 lets), 4,000 | 21 | 71,791 (18,898) | 10,213 | 76.0 | 2.20 s, 120 MB | 3.78 s, 122 MB | 4.59 s, 223 MB |
| SUMO taxonomy, 8,000 | 11 | 62,180 (15,378) | 17,733 | 73.9 | 3.37 s, 164 MB | 4.76 s, 155 MB | 5.38 s, 301 MB |
| SUMO taxonomy, 16,000 | 6 | 53,617 (12,418) | 32,131 | 72.7 | 7.77 s, 394 MB | 8.56 s, 400 MB | 8.42 s, 568 MB |

As one theorem s16000 was past nanoda_bin's u16 (scale-3: "invalid value: integer `80010`, expected u16") and h16000, about
64,000 deep, past con-leche's and con-ron's 120 s.  Writing the SUMO certificate takes 1.85-1.87 s and 237 MB in all (the chase 1.0 s, the writing
0.8 s); kif-lean-check.py decodes its claims, equal to the dump with every import an earlier piece's let, in 8.0-8.6 s and
0.9 GB.  At 8,000 lets per piece each kernel rejects each control on all three theories: a premise and a binding broken in
closure.0, and the last let of the last piece claiming another fact.  A piece's cost grows with its depth, more than its
imports cost: SUMO's 4,000-let pieces import 18,898 facts and check in a quarter to a half of the time of 16,000-let ones.

