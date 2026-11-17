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
