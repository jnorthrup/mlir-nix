# Prelowering: the frontend runs ahead of the evaluator

Lexing, parsing and building the IR of the files an evaluation imports is 20-25% of its run (Mac CPU profiler: `lowerToMLIR` 24.7% of cycles,
`Lexer::nextToken` 4.8% self; Kali: `MLNIX_STATS` "lowering" 847-929 ms of a 4.8-5.1 s stats run, a plain run is 3.65-3.97 s). It needs no
evaluator state, so helper threads can do it ahead of the evaluator, the way a long production pipeline feeds a short consumer.

## How it works

`MLNIX_PRELOWER=1` (with `MLNIX_PREFETCH=auto`, whose list of the files a previous run of the same invocation evaluated it reuses; the first
run records) or `MLNIX_PRELOWER_LIST=file` (that list, or one path a line) starts `MLNIX_PRELOWER_THREADS` helpers (default 1, 2 is the sweet
spot). Each helper takes the next path, maps it, and runs `genExpr` into a module of its own with a pool whose id comes from an atomic
counter. `evalFile` asks for the file by its resolved path: a finished lowering is adopted (the pool is installed at its index, the op moves
into the evaluator's module and the optimizer runs on it there: the prim folder calls back into the evaluator, so that half stays on the
main thread), one still running is waited for, one not started is lowered by the evaluator as before. A failed or stale prediction costs only
the helper's time: the evaluator never adopts a file it did not ask for. Demand schedule (`MLNIX_DEFER=1`) only; the MLIR context keeps
multithreading enabled when prelowering is on (the old comment said that cost a quarter of the run; measured, it is 0-3 points of ratio).

## Measured (output hashes identical in every arm: `2057239a9017` toplevel, `5e8fff662dff` nixpkgs-73)

Kali, one boot, five interleaved rounds, list from a previous run (warm start):

| | plain min / med | 1 helper | 2 helpers |
|---|---:|---:|---:|
| nixos-toplevel | 3.82 / 4.17 s | 3.48 / 3.67 s | **3.29 / 3.38 s** |
| nixpkgs-73 | 3.48 / 3.65 s | 2.81 / 2.99 s | **2.80 / 2.89 s** |

CPU time rises about 5-10% (toplevel 4.00 -> 4.39 s) for the speculative and handoff work; the wall time falls 14-21%. Mac: 1.56 -> 1.27 s
(toplevel), 1.35 -> 1.14 s (nixpkgs-73). With one helper the evaluator waited for 1,152 of 2,888 files on toplevel; two helpers close most of it.

## What it is not

A cold start (no list) gets nothing: 88.4% of evaluated files are named by a path literal lowered earlier, but only 16% of the 15,851 distinct
literals lead to an evaluated file (`MLNIX_STATS_IMPORTS`), so lowering every literal would waste most of its work and memory. The honest
labels are "warm start" for the numbers above and "cold" for the unchanged ones. Peak RSS with helpers is not measured yet. Default off.
