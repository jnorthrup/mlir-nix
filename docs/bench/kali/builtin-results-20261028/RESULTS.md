# Builtin result allocation experiment, 28 October 2026

**Parked; the evaluator source is restored to Calls V2.** Deferring result allocation until a builtin's
arity is known removes 676,207 Value rows on NixOS and 312,654 on nixpkgs-73. Peak RSS falls, but the paired
Kali runs are slower with JIT disabled and enabled. The candidate patch, frozen binaries and measurements
are retained for later work; the default path does not retain this experiment.

## Change

`callFunction` allocated a tentative result before dispatch whenever another argument followed. The
builtin branch then selected a different result after computing how many arguments it consumed, leaving
the earlier arena row unused. Partial builtin application similarly built its own application chain.
The candidate [patch](v1/candidate.patch) moves the tentative allocation into the lambda and functor
branches. Builtins allocate only after arity is known; their partial-application alias handling is unchanged.

This is a generic evaluator change with no source-name matching. Existing JIT code, guards, grace and
retirement are unchanged. Allocation counts fall equally with JIT disabled or enabled; frame allocations
and native execution counts are unchanged. Reducing allocation alone did not establish better locality
or faster evaluation in this experiment.

## Allocation evidence

Untimed before/after profiles use demand mode on Kali / WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8.
These are actual `allocValue` calls, with 24 bytes of requested payload per row. Requested bytes are not RSS.

| Workload | Baseline Value rows | Candidate Value rows | Rows removed | Requested bytes removed |
|---|---:|---:|---:|---:|
| NixOS | 14,424,286 | 13,748,079 | 676,207 | 16,228,968 |
| nixpkgs-73 | 11,770,533 | 11,457,879 | 312,654 | 7,503,696 |

The reductions are 4.69% / 2.66% of Value allocations. Frame counts, slots and bytes match exactly within
each JIT mode; JIT execution, inline-call, demand and resume counts also match. All eight profile outputs
have the full golden hashes, and enabled arms report zero compiler failures or mismatches.
Sources: [NixOS baseline](v1/profile-baseline-jit-off-nixos-toplevel.txt) / [candidate](v1/profile-candidate-jit-off-nixos-toplevel.txt),
[nixpkgs baseline](v1/profile-baseline-jit-off-nixpkgs-73.txt) / [candidate](v1/profile-candidate-jit-off-nixpkgs-73.txt),
and the [profile hashes](v1/profile-hashes.txt).

## Paired measurements

Both arms use preserved binaries, identical inputs and rotating A/B order. Every run must succeed and
match the full output hash. Timings omit stats/profiling; JIT-enabled runs use the default 1,024-call
threshold and include compilation and grace. RSS below is decimal GB. Exact settings are recorded in
[commands.txt](v1/commands.txt) and the [launcher](v1/commands-v1.sh).

Five pairs with JIT disabled:

| Workload | Baseline median | Candidate median | Wall change | CPU change | RSS baseline / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.041 s | 4.099 s | +1.4% | +2.0% | 1.316 / 1.302 GB |
| nixpkgs-73 | 3.547 s | 3.702 s | +4.4% | +3.9% | 1.217 / 1.212 GB |

RSS falls 1.1% / 0.4%. [Raw JIT-disabled comparison](v1/ab-baseline-candidate-jit-off-demand.txt).

Three pairs with JIT enabled:

| Workload | Baseline median | Candidate median | Wall change | CPU change | RSS baseline / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.119 s | 4.246 s | +3.1% | +4.0% | 1.321 / 1.310 GB |
| nixpkgs-73 | 3.572 s | 3.837 s | +7.4% | +9.2% | 1.217 / 1.216 GB |

RSS falls 0.8% / 0.1%. [Raw JIT-enabled comparison](v1/ab-baseline-candidate-jit-on-demand.txt).
The smaller allocation counts and RSS are real benefits in these runs, but neither timing series
supports adopting this candidate for throughput. These samples do not explain the timing regression.

Separate single JIT-disabled PMU pairs show NixOS / nixpkgs cycles +2.84% / +0.11%, instructions
+0.17% / −0.16%, cache misses +3.01% / +6.60%, and branch misses +0.43% / −0.66%. All events ran for
100% of enabled time and cover inherited user-space threads/children. Single samples do not establish
a causal cache penalty. Raw [NixOS baseline](v1/pmu-baseline-jit-off-nixos-toplevel.json) /
[candidate](v1/pmu-candidate-jit-off-nixos-toplevel.json) and
[nixpkgs baseline](v1/pmu-baseline-jit-off-nixpkgs-73.json) / [candidate](v1/pmu-candidate-jit-off-nixpkgs-73.json)
are retained.

## Cached Nix and Lix

No Nix or Lix executable was run. The accepted same-host reference records from generations
[04](../04-20b5ad596/), [05](../05-f2c37f51b/) and [06](../06-aea88bf65/) are reused. Historical medians
below are the best accepted medians across those generations, not a simultaneous controlled comparison.

| Workload | Retained baseline, JIT off | Parked candidate, JIT off | Cached Nix 2.35.4 | Cached Lix 2.91.3 |
|---|---:|---:|---:|---:|
| NixOS | 4.041 s | 4.099 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.547 s | 3.702 s | 3.85 s | 4.53 s |

Latest cached RSS is Nix 628 / 609 MiB and Lix 755 / 757 MiB. Even the parked allocation reduction leaves
mlnix with substantially higher peak memory. The retained [Calls V2 report](../calls-20261028/RESULTS.md)
records the separate native-compilation comparison.

## Validation and provenance

The candidate passes 240 exact eager/demand JIT/interpreter checks on macOS/LLVM 23 and Kali/LLVM 22.
Both macOS full schedules pass 479/479 semantic cases and 221/479 stored exact expectations. Every one of
the 1,437 output/error/status files per schedule matches Calls V2 byte for byte. See [local validation](../../local/builtin-results-20261028/v1/validation-summary.txt)
and the [Kali focused gate](v1/check-jit.txt). Kali did not rerun the broad suites.

| Snapshot | SHA-256 |
|---|---|
| Candidate source archive | `5827b1cdc1ce02386ebc38cdc9aa7327d99ec754e390006fa73532d114f6d7a4` |
| Candidate macOS binary | `228694d2b84f7d6bd76da852a5028b0f926167afb45a947c80aaef5c45c8c6e5` |
| Candidate Kali binary | `150d8914c1369d4ad5adbf1e375fb56b013bcbe12db0b6957e6f01e945749f0d` |
| Preserved Calls V2 Kali baseline | `1679d14d0d3d2a1faabf17e94e11db414c97f3b2bf64fa5b13d50807194bcd85` |

The candidate source archive is `/tmp/mlir-nix-builtin-results-v1-20261028.tar.gz`; preserved candidate
binaries are `/tmp/mlnix-locality/mlnix-builtin-results-v1` on macOS and
`/tmp/kb/builtin-results-20261028-v1/mlnix` on Kali. The candidate's only functional source difference
from Calls V2 is the saved patch. Restoring that file returns the working implementation to the fully
validated Calls V2 snapshot; documentation and experiment evidence remain.
