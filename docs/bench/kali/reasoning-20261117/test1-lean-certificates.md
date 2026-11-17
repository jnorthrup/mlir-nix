# Test 1: kif-chase's paperclip stratum 1 as Lean proofs, checked by Lean's kernel

Kali (x86_64 WSL2, 8 cores, 15.9 GB). Harness: the git repo kali:~/lean-test/gen.git (kif2lean.py, measure.sh,
summarize.py, Audit.lean, nanoda_config.py); raw logs in kali:~/lean-test/logs/final. The tables below are summarize.py's.

- Input: `mlnix-kif --chase --dump` over mlir-nix test/kif/paperclip-structural.kif and sumo-nix paperclip/world.kif and
  paperclip/analysis.kif: 7,147 facts, 1,964 of them derived (counts.txt).
- Encoding: `inductive Term | atom String | list (List Term)`, `axiom Holds : Term -> Prop`; the 5,183 asserted facts as
  axioms `fN`, the 10 rules as axioms `rN : forall vars, Holds p1 -> ... -> Holds head`, each derived fact a theorem
  `dN : Holds fact := rK args premises` with the bindings and premises of the chase's own record.
- Sizes: PaperclipS1.lean 739,883 bytes; PaperclipS1.olean 5,324,856 (Empty.olean 1,032); its lean4export export 3,559,808.
- Versions: Lean 4.36.0 (611c117bfaf7), lean4export 3.1.0, mlir-nix 60130ba, sumo-nix 49acd06, harness 183fdad; sha256 of
  the inputs in versions.txt: paperclip-structural.kif b62a4363..., world.kif f5d3d78f..., analysis.kif 52c47bf6....

Controls, each of which must fail (all do):
- a derived fact's last premise replaced by another fact (BadPremise.lean): the elaborator, "Application type mismatch";
- a rule instance's binding changed, Clippy to Entity (BadInstance.lean): the elaborator, "Application type mismatch";
- a corrupted proof term handed to addDecl (KernelControl.lean): "(kernel) application type mismatch";
- `bogus : P := q`, q a proof of Q, under `debug.skipKernelTC`: lean accepts it; leanchecker rejects it ("declaration
  type mismatch"); nanoda panics (assertion failed: def_eq).

| run | n | wall s (each) | user s (each) | sys s (mean) | max RSS MB (max) | exit |
|---|---|---|---|---|---|---|
| mlnix-kif --chase --stats (3 files) | 3 | 0.07 / 0.07 / 0.07 | 0.06 / 0.06 / 0.06 | 0.01 | 61 | 0,0,0 |
| kif2lean.py (generation) | 3 | 0.21 / 0.22 / 0.21 | 0.19 / 0.20 / 0.20 | 0.01 | 26 | 0,0,0 |
| lean PaperclipS1.lean (default) | 3 | 16.28 / 16.05 / 16.04 | 17.27 / 16.97 / 16.93 | 7.14 | 863 | 0,0,0 |
| lean --profile | 3 | 15.98 / 18.32 / 18.39 | 17.16 / 19.68 / 19.51 | 7.69 | 863 | 0,0,0 |
| lean -D debug.skipKernelTC=true --profile | 3 | 18.82 / 19.06 / 18.84 | 19.81 / 19.84 / 19.70 | 7.90 | 863 | 0,0,0 |
| lean -D Elab.async=false --profile | 3 | 17.86 / 17.85 / 17.97 | 16.48 / 16.39 / 16.63 | 2.75 | 841 | 0,0,0 |
| lean -D Elab.async=false -D debug.skipKernelTC=true --profile | 3 | 17.42 / 17.57 / 17.31 | 15.91 / 16.02 / 15.96 | 2.80 | 841 | 0,0,0 |
| lean -j 1 --profile | 1 | 21.79 | 17.64 | 6.12 | 972 | 0 |
| leanchecker PaperclipS1 (replay .olean) | 3 | 0.70 / 0.70 / 0.70 | 0.42 / 0.45 / 0.43 | 0.26 | 446 | 0,0,0 |
| leanchecker Empty (baseline) | 3 | 0.54 / 0.52 / 0.52 | 0.23 / 0.26 / 0.25 | 0.27 | 441 | 0,0,0 |
| nanoda_bin on the export (7,540 decls) | 3 | 0.14 / 0.17 / 0.19 | 0.13 / 0.17 / 0.18 | 0.00 | 9 | 0,0,0 |
| nanoda_bin on Term+Holds export (354 decls) | 3 | 0.02 / 0.03 / 0.03 | 0.02 / 0.02 / 0.02 | 0.00 | 4 | 0,0,0 |

| Lean --profile (cumulative) | parsing | elaboration | linting | process pre-definitions | type checking | import |
|---|---|---|---|---|---|---|
| profile-1 | 1.320 | 14.200 | 2.310 | 0.504 | 0.578 | 0.164 |
| profile-2 | 1.690 | 16.700 | 2.590 | 0.594 | 0.664 | 0.168 |
| profile-3 | 1.670 | 16.800 | 2.590 | 0.599 | 0.651 | 0.204 |
| skipkernel-1 | 1.610 | 17.400 | 2.530 | 0.600 | 0.233 | 0.218 |
| skipkernel-2 | 1.670 | 17.600 | 2.550 | 0.604 | 0.245 | 0.213 |
| skipkernel-3 | 1.620 | 17.400 | 2.530 | 0.620 | 0.236 | 0.213 |
| async0-1 | 1.490 | 11.800 | 1.470 | 0.360 | 0.540 | 0.251 |
| async0-2 | 1.470 | 11.800 | 1.480 | 0.360 | 0.547 | 0.232 |
| async0-3 | 1.520 | 11.900 | 1.480 | 0.364 | 0.553 | 0.224 |
| async0skip-1 | 1.490 | 11.800 | 1.490 | 0.352 | 0.192 | 0.226 |
| async0skip-2 | 1.490 | 11.900 | 1.490 | 0.350 | 0.187 | 0.223 |
| async0skip-3 | 1.460 | 11.700 | 1.470 | 0.344 | 0.190 | 0.215 |
| j1-1 | 1.430 | 12.500 | 2.310 | 0.270 | 0.503 | 0.241 |
