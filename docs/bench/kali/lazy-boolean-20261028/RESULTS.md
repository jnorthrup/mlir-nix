# Lazy Boolean graphs and adaptive retirement, 28 October 2026

The native tier now compiles Boolean control flow with lazy demand continuations. It handles real
`lib.isFunction` calls whose arguments are still thunks, while preserving short circuits, traces and
errors. V3 avoids compilation of four / three unused Boolean kernels while preserving all v2 native
completions. This expands compiler coverage but does not yet improve end-to-end performance: the final
JIT off/on comparison raises demand median wall time by 5.4% on NixOS and 2.1% on nixpkgs-73.
Native execution remains opt-in. The earlier [dense attribute layout](../dense-selectors-20261028/RESULTS.md)
remains the supported default memory improvement.

## What changed

The path is TrikeShed source/deferred-body storage → lazy Nix graph → bounded Boolean/CPS plan →
typed `func`/`arith`/`cf`/LLVM-pointer MLIR → LLVM dialect → LLVM IR and native execution.
Supported nodes are Boolean literals, persistent arguments/captures, nine type predicates, negation,
AND/OR/implication, `if`, and single-name static attribute existence. Native code tests tags and searches
flat attribute rows without forcing the attribute value. Unsupported reached branches deoptimize.

A generated kernel returns a continuation ID when it needs a persistent cell. The host resolves and
forces that cell at the original consuming operation, retaining builtin error wrappers, then resumes
the kernel. Failed forcing propagates directly. Whole-lambda fallback can reuse successful forces
because those cells are memoized. Local opaque computation is never speculatively forced.

The first three native completions receive interpreter-first validation. The native observer may inspect
already demanded cells but cannot force an additional thunk. Bounds cover source nodes, leaves,
continuation expansion, generated blocks, compiler attempts and per-call resumes. See [JIT.md](../../../JIT.md).
The [saved example](../../local/lazy-boolean-20261028/boolean-ir/) contains the CPS plan, both MLIR stages,
optimized LLVM IR and execution counters: seven completions, four host demands, one deopt and three
grace comparisons. Its traced argument runs once and its unused field remains lazy.

V1 introduced this compiler. V2 retires a kernel after 64 consecutive deopts without a completion.
Later calls bypass native dispatch; plan/code destruction waits until all active calls exit, including
calls suspended in a recursive host demand and exception unwinding. Retirement does not replenish
the compilation budget.

V3 adds a nonforcing admission check before the first compilation. After the interpreter returns, a
C++ observer walks the same CPS using existing persistent WHNF cells. It neither allocates nor forces
a value. A matching Boolean completion admits compilation; an unsupported path delays it, with refusal
after 64 such observations. The oracle result is reused, and native grace remains three separate
comparisons. Entry state is rechecked after recursive oracle calls.

## Method

Kali/WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. The existing NixOS and nixpkgs-73 workloads and
pinned nixpkgs inputs are unchanged. Every timing pair requires successful exit and identical full
output hashes. A/B order rotates; startup, compilation and grace are included. Demand uses
`MLNIX_DEFER=1`; the hotness threshold is the default 1,024. Profiles and PMU samples are separate
from timed rounds. RSS in A/B tables is decimal GB.

The [v1](v1/commands.txt), [v2](v2/commands.txt) and [v3](v3/commands.txt) manifests retain exact launchers and environment
settings. A host lock serializes benchmarks. Nix 2.35.4 and Lix 2.91.3 were not executed; their accepted
same-host timings are reused below. Cached comparisons do not control for changes in host load.

## Native coverage and retirement

Untimed, default-threshold profiles show actual native completion rather than only entry counts:

| Workload | Version | Boolean kernels | Completions | Host demands | Deopts | Retired |
|---|---|---:|---:|---:|---:|---:|
| NixOS | v1 | 10 | 111,656 | 103,749 | 74,532 | 0 |
| NixOS | v2 | 10 | 111,101 | 103,749 | 845 | 5 |
| nixpkgs-73 | v1 | 7 | 202,943 | 186,782 | 97,191 | 0 |
| nixpkgs-73 | v2 | 7 | 201,795 | 186,782 | 2,051 | 4 |

Sources: [v1 NixOS](v1/profile-nixos-toplevel.txt), [v1 nixpkgs](v1/profile-nixpkgs-73.txt),
[v2 NixOS](v2/profile-nixos-toplevel.txt), [v2 nixpkgs](v2/profile-nixpkgs-73.txt).
All have zero mismatches and compiler failures. The existing shared pointer kernel remains active.
NixOS profiling reaches the 4,096-row diagnostic-table limit; its global counters remain available.

`lib.isFunction` completes 94,113 NixOS and 173,751 nixpkgs calls natively, with 91,631 / 169,067
host demands. Retirement preserves all of those completions. In contrast, `platformMatch` had
36,975 / 89,921 deopts and no completions in v1; v2 stops each such entry after 64 misses.
Some other retired entries had earlier completions, explaining the small drop in the completion totals.
Demand/resume counters omit work from runs whose host force throws before returning the counter record.

Boolean v1 has the same `allocValue` count as the selector baseline: 14,424,286 / 11,770,533.
Fewer Boolean tag writes do not imply fewer heap cells; those counters also include stack temporaries.
This stage establishes native execution coverage, not a measured heap-allocation discount.

## Paired timings

Three demand pairs compare the preserved selector v2 with Boolean v1, both with JIT enabled:

| Workload | Selector median | Boolean v1 median | Wall change | CPU change | RSS A / B |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.899 s | 4.185 s | +7.3% | +8.6% | 1.322 / 1.329 GB |
| nixpkgs-73 | 3.542 s | 3.557 s | +0.4% | -0.4% | 1.223 / 1.233 GB |

Source: [selector → Boolean v1](v1/ab-selector-v2-on-boolean-v1-on-demand.txt).

Three more pairs isolate retirement within the Boolean tier:

| Workload | v1 on median | v2 on median | Wall change | CPU change | RSS A / B |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.158 s | 4.064 s | -2.3% | -2.2% | 1.324 / 1.327 GB |
| nixpkgs-73 | 3.696 s | 3.676 s | -0.5% | -2.1% | 1.228 / 1.229 GB |

Source: [v1 → v2](v2/ab-boolean-v1-on-v2-on-demand.txt). Retirement reduces repeated native fallback
and modestly lowers CPU time in this sample; it does not recover the initial cost of compiling those kernels.

Five pairs compare JIT disabled/enabled in the same v2 binary:

| Workload | Off median | On median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.918 s | 4.234 s | +8.1% | +10.7% | 1.318 / 1.327 GB |
| nixpkgs-73 | 3.531 s | 3.603 s | +2.0% | +1.6% | 1.220 / 1.228 GB |

Source: [v2 off/on](v2/ab-boolean-v2-off-on-demand.txt). Minima are 3.853 / 3.893 s for NixOS and
3.403 / 3.571 s for nixpkgs. Host variability affects the size of the loss, but these results do not
justify enabling the tier by default. RSS rises about 0.7% on each workload.

One separate PMU pair per workload reports cycles +3.44% / +2.26%, instructions +1.60% / +0.26%,
cache misses -0.05% / +6.99%, and branch misses +5.79% / +3.32%. Counters cover inherited user-space
threads/children and ran for 100% of enabled time. These single samples do not establish a locality win.
Raw records: [NixOS off](v2/pmu-v2-off-nixos-toplevel.json) / [on](v2/pmu-v2-on-nixos-toplevel.json),
[nixpkgs off](v2/pmu-v2-off-nixpkgs-73.json) / [on](v2/pmu-v2-on-nixpkgs-73.json).

## V3: avoid unproductive compilation

The observer prevents four NixOS and three nixpkgs engines from being built, with unchanged completion
and demand counts. This is a compilation-cost reduction; the engine still has incomplete graph coverage.

| Workload | Boolean kernels | Completions | Demands | Native deopts | Preflight deopts / refusals | Native retirements |
|---|---:|---:|---:|---:|---:|---:|
| NixOS | 6 | 111,101 | 103,749 | 578 | 267 / 4 | 1 |
| nixpkgs-73 | 4 | 201,795 | 186,782 | 1,859 | 192 / 3 | 1 |

Sources: [v3 NixOS](v3/profile-nixos-toplevel.txt), [v3 nixpkgs](v3/profile-nixpkgs-73.txt).
There are 273 / 196 observer passes, zero mismatches and zero compiler failures. The remaining
retirement belongs to a kernel admitted on a useful path before a later deopt streak.

Three pairs compare v2-on with v3-on:

| Workload | v2 median | v3 median | Wall change | CPU change | RSS A / B |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.054 s | 4.035 s | -0.5% | +1.2% | 1.324 / 1.327 GB |
| nixpkgs-73 | 3.628 s | 3.531 s | -2.7% | -2.3% | 1.224 / 1.229 GB |

Source: [v2 → v3](v3/ab-boolean-v2-on-v3-on-demand.txt). Nixpkgs timing improves in this sample;
NixOS is mixed, and RSS does not fall despite skipping engine creation. No general speedup or memory
saving is inferred from admission counts.

The final five-pair off/on comparison uses the same v3 executable:

| Workload | Off median | On median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.877 s | 4.087 s | +5.4% | +5.3% | 1.318 / 1.327 GB |
| nixpkgs-73 | 3.516 s | 3.588 s | +2.1% | +1.8% | 1.220 / 1.229 GB |

Source: [v3 off/on](v3/ab-boolean-v3-off-on-demand.txt). Minima are 3.834 / 3.925 s for NixOS and
3.435 / 3.485 s for nixpkgs. Native execution remains opt-in.

Separate single PMU pairs show cycles +1.82% / +2.11%, instructions +0.70% / -0.47%, cache misses
+1.72% / +5.84%, and branch misses +3.02% / +2.19%, with all counters running for 100% of enabled time.
These are diagnostic samples, not replicated improvements. Raw [NixOS off](v3/pmu-v3-off-nixos-toplevel.json) /
[on](v3/pmu-v3-on-nixos-toplevel.json) and [nixpkgs off](v3/pmu-v3-off-nixpkgs-73.json) /
[on](v3/pmu-v3-on-nixpkgs-73.json) remain available.

## Alongside cached Nix and Lix

Reference minima and medians are the best accepted same-host values from generations
[04](../04-20b5ad596/), [05](../05-f2c37f51b/) and [06](../06-aea88bf65/); RSS is from the latest.
Only the two current-candidate columns below were measured together. Reference RSS is MiB.

| Workload | v3 JIT off median | v3 JIT on median | Cached Nix median | Cached Lix median |
|---|---:|---:|---:|---:|
| NixOS | 3.877 s | 4.087 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.516 s | 3.588 s | 3.85 s | 4.53 s |

| Workload | Cached Nix minimum / RSS | Cached Lix minimum / RSS |
|---|---:|---:|
| NixOS | 3.70 s / 628 MiB | 4.42 s / 755 MiB |
| nixpkgs-73 | 3.46 s / 609 MiB | 4.31 s / 757 MiB |

The current interpreter remains near these historical time ranges and still uses roughly twice Nix's
peak memory. Historical ratios are not a simultaneous speedup claim. No reference startup, version,
RSS probe or language-test invocation was made in this iteration.

## Correctness and provenance

V2 passes 174 exact JIT/interpreter comparisons on macOS/LLVM 23 and Kali/LLVM 22. Independent
Boolean expectations also check values, diagnostic fragments and ordered traces. Cases cover all type
predicates, short circuits, changing captures, non-Boolean `if` tails, layered sets, opaque functor calls,
bounds, reentrancy, and retirement during a recursive demand or exception.

The saved macOS full suites contain 478 cases under eager and demand schedules with JIT threshold 1.
All 1,431 stdout/stderr/status files for the 477 prior cases are byte-identical; the added Boolean
fixture returns `true` successfully with no stderr. This retains 478 semantic / 220 stored-expectation
exact matches. [Validation evidence](../../local/lazy-boolean-20261028/validation-summary.txt) includes
manifest hashes. V1 also passed 15 MLIR tests locally; the retirement-only follow-up did not rerun them.
Kali uses the focused gate and the two unchanged full workload hashes, not a repeated broad suite.

V3 passes 186 exact comparisons on both hosts, including six new preflight cases: no-engine refusal,
delayed admission, recursive compilation/refusal/retirement, and an error in the first oracle call.
The macOS full suites again pass 478/478 semantic and 220/478 stored-expectation exact cases in both
schedules; every one of the 1,434 saved files per schedule matches v2.
[The v3 validation record](../../local/lazy-boolean-20261028/v3/validation-summary.txt) retains hashes
and commands. The latest [Kali focused gate](v3/check-jit.txt) also passes.

The unchanged v2/v3 workload hashes are
`2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86` and
`5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`.

| Snapshot | SHA-256 |
|---|---|
| Boolean v1 source archive | `0ada688e366987b7c7680f259ed342d3e850eb2e468a29645702d4a2c5e58a50` |
| Boolean v1 Kali binary | `fd3bb9c529b8021762dc64372764f670a6850c8088e0079bcc08d89a4115674b` |
| Boolean v2 source archive | `47d7f80c07ea6decd79c9912537ba038764dbd9f9d3c98cd103e3460d4325e2b` |
| Boolean v2 Kali binary | `7f6c7ec17d8f4bda9ba08219fab2cb730caaa1c7bd93d5464db649525452f6e8` |
| Boolean v2 macOS binary | `17b3e5cd330acef23602533987697e295cfd578cf636a330de290a5f29a48d39` |
| Boolean v3 source archive | `7a69f6b8391960baca027c225ff87e49986ea494a73909f45026ea7fbba5478d` |
| Boolean v3 Kali binary | `712827b4c2b5f8742d6920f51d3e6d7cde4b26926253dc13ff0517f0b7340d53` |
| Boolean v3 macOS binary | `d48c18bdfcfdcf65cf0dd063881f7224f6c39a4cc7dfb9ce148243e650c39438` |

Archives and binaries were frozen separately before measurement; documentation can evolve afterward.
All 13 files containing the user's incoming TrikeShed work remain byte-identical to the original snapshot.
General closure conversion, higher-order calls, local effectful graph compilation, attribute value
projection and collection kernels remain unfinished. The next [call-inlining design](../../../JIT-CALLS.md)
is explicitly unimplemented and keeps those remaining requirements visible.
