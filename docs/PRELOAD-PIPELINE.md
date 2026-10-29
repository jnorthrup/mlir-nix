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

## Against Nix and Lix, one boot (Kali after the 29 October reboot)

One `vs-nix.py --demand` invocation per row, so Nix, Lix and mlnix run interleaved in the same window (five rounds); the prefetch trace was recorded by
a warm-up run first. Outputs identical in every arm. The host was noisy after the reboot (Nix's own median swung 4.11 s to 4.70 s between invocations),
so the minimum is the steadier column.

| mlnix demand | min / median | Nix 2.35.4 min / median | ratio, median | ratio, min |
|---|---|---|---:|---:|
| nixos-toplevel, plain | 3.78 / 3.81 s | 3.93 / 4.11 s | 0.93 | 0.96 |
| nixos-toplevel, prelowering (2 helpers) | 2.98 / 3.36 s | 3.79 / 4.70 s | 0.71 | 0.79 |
| nixpkgs-73, plain | 3.33 / 3.77 s | 3.96 / 4.25 s | 0.89 | 0.84 |
| nixpkgs-73, prelowering (2 helpers) | 2.87 / 2.92 s | 3.50 / 3.88 s | 0.75 | 0.82 |

Warm start only. The ratio of 0.79-0.82 on the minimum is not 0.5.

### The same comparison at HEAD ce2cf11 (Kali, 7 interleaved rounds, outputs identical)

| mlnix demand | min / median | Nix 2.35.4 min / median | ratio, median | ratio, min |
|---|---|---|---:|---:|
| nixos-toplevel, plain | 3.57 / 3.59 s | 3.76 / 3.89 s | 0.92 | 0.95 |
| nixos-toplevel, prelowering (2 helpers) | 2.92 / 3.12 s | 3.71 / 3.97 s | 0.79 | 0.79 |
| nixpkgs-73, plain | 3.39 / 3.51 s | 3.48 / 3.97 s | 0.88 | 0.97 |
| nixpkgs-73, prelowering (2 helpers) | 2.80 / 2.91 s | 3.48 / 3.55 s | 0.82 | 0.80 |

## Peak memory

Mac, nixos-toplevel, three runs each: peak RSS 1,182 MB plain, 1,208 MB with one helper, 1,210 MB with two (+27 MB, +2.3%).

## What it is not

A cold start (no list) gets nothing: 88.4% of evaluated files are named by a path literal lowered earlier, but only 16% of the 15,851 distinct
literals lead to an evaluated file (`MLNIX_STATS_IMPORTS`), so lowering every literal would waste most of its work and memory. The honest
labels are "warm start" for the numbers above and "cold" for the unchanged ones. Peak RSS with helpers is not measured yet. Default off.

### The cold-start predictor that was tried and dropped

A predictor that needs no previous run offered every `.nix` or extension-less path literal of each file the evaluator started to a stack the
helpers popped (newest first), kept a sliding window of lowered-but-unadopted files, and let literals seen by a helper wait for its file's
adoption (so speculation did not recurse). Output was identical, but on nixos-toplevel (Mac, two helpers, windows of 16 to 1,024):
214 of the 2,888 files were adopted (7%), 14,071 were lowered speculatively and 13,806 evicted unused, and the run was slower than plain
(1.56-1.66 s against 1.57-1.60 s). Which file is wanted next depends on which attribute the evaluator forces, and a literal says only that
a path exists. The code is not kept; the diff is in the session scratchpad. The warm-start trace is the predictor.
