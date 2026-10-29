# Guarded calls in the Boolean graph, 28 October 2026

The compiler now combines a Boolean wrapper with a supported callee graph, using guards on the actual
closure at each reached call. This removes 62,114 frames on NixOS and 161,994 on nixpkgs-73, but the
first implementation is slower: the within-binary inlining comparison raises median wall time by
1.1% / 3.1%. Native execution remains opt-in. Requested frame storage falls; Value allocations do not.

## Implementation and limits

The path remains TrikeShed source storage → lazy Nix graph → bounded call/CPS IR → typed MLIR →
LLVM IR/native code. This is graph-based compilation, independent of source names. A hot plan is
specialized after its interpreter oracle returns, reading only already-WHNF lambda cells and
already-indexed bodies. Its formal argument maps to a persistent caller handle; captures resolve
through the current callee's environment, not the environment seen during specialization.

Generated code checks each reached callee's tag and lambda-operation identity before entering its
compiled graph. An unready or changed target falls back before forcing the argument. Unknown local
computation remains opaque. In v1, native Enter/Leave continuations return to the host to preserve
logical call depth, closure context and source diagnostics. Scoped cleanup restores depth on deopt
or exception; the existing active-run pin retains retired code while a recursive demand is suspended.

Three interpreter-first native grace comparisons remain required. The nonforcing admission check
and bounded retirement remain in place. Expansion has global node, leaf and block limits plus inline
depth four. `MLNIX_JIT_INLINE=0` disables only call expansion; scalar, pointer and ordinary Boolean
kernels remain enabled with `MLNIX_JIT=1`. Saturated currying, dynamic projection and collection fusion
remain unimplemented. [JIT.md](../../../JIT.md) and [JIT-CALLS.md](../../../JIT-CALLS.md) describe the contracts.

The [saved IR example](../../local/calls-20261028/inline-ir/) includes a separate inlined wrapper kernel,
actual LLVM callee guards, the callee Boolean graph and Enter/Leave continuations. Seven inlined calls,
one target-guard miss and two exactly-once traces are checked against interpretation; an unused field
stays lazy. Recursive functor computation remains an explicit fallback.

## Measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. Inputs and full output hashes are unchanged from
the [Boolean experiment](../lazy-boolean-20261028/RESULTS.md). Both comparisons use five rotating A/B
demand pairs and the default 1,024-call threshold. Time includes startup, specialization, compilation
and grace. Every round requires success and identical full output hashes. Profiles and PMU samples
run separately; RSS in A/B tables is decimal GB. The [manifest](v1/commands.txt) and
[launcher](v1/commands-v1.sh) record all environment settings, including `MLNIX_JIT_INLINE`.

The first comparison keeps JIT enabled in both arms and changes only inlining:

| Workload | Inline off median | Inline on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.061 s | 4.107 s | +1.1% | +0.5% | 1.327 / 1.325 GB |
| nixpkgs-73 | 3.557 s | 3.667 s | +3.1% | +3.1% | 1.228 / 1.222 GB |

Source: [inline ablation](v1/ab-inline-off-on-demand.txt). RSS falls about 0.1% / 0.5% in these runs.

The second compares all native tiers disabled/enabled in the same binary:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.037 s | 4.133 s | +2.4% | +1.6% | 1.318 / 1.325 GB |
| nixpkgs-73 | 3.524 s | 3.642 s | +3.4% | +3.4% | 1.220 / 1.222 GB |

Source: [whole-JIT ablation](v1/ab-jit-off-on-demand.txt). This still does not support enabling JIT by default.

## Allocation and execution evidence

Untimed profiles isolate frame requests. These bytes exclude arena bookkeeping, retained pages and
allocator overhead; they are not RSS. The old per-tag counters have been relabeled because writes to
stack temporaries and repeated retyping are not a heap census. `value allocations` counts actual
`allocValue` rows, while `frame allocations` counts `newFrame` requests and their payload storage.

| Workload | Frames, inline off | Frames, inline on | Frames removed | Requested frame bytes removed | Inlined calls |
|---|---:|---:|---:|---:|---:|
| NixOS | 4,930,134 | 4,868,020 | 62,114 | 1,490,736 | 62,117 |
| nixpkgs-73 | 3,194,310 | 3,032,316 | 161,994 | 3,887,856 | 161,997 |

The three-call difference is native grace: its oracle still allocates frames. Value allocation counts
remain 14,424,286 / 11,770,533 with inlining either disabled or enabled. One additional kernel per
workload handles the wrapper. All six profiles have the same output hashes; all enabled arms have
zero mismatches and compiler failures, and real-workload target guards have zero misses.
Sources: [NixOS off](v1/profile-inline-off-nixos-toplevel.txt) / [on](v1/profile-inline-on-nixos-toplevel.txt),
[nixpkgs off](v1/profile-inline-off-nixpkgs-73.txt) / [on](v1/profile-inline-on-nixpkgs-73.txt).

Native invocation counts rise 219,818 → 406,172 on NixOS and 399,236 → 885,230 on nixpkgs. This is
three extra native invocations per inlined call, chiefly guard resolution and Enter/Leave bookkeeping.
The extra round trips are the next implementation target. Measured compilation wall time rises
57.2 → 67.3 ms / 36.6 → 51.2 ms in these diagnostic runs. `compile_ns` covers IR emission, lowering,
native generation and first JIT-context setup, including failed attempts; it excludes plan analysis,
specialization, hotness and interpretation. These are single elapsed-time samples, not paired CPU costs.

Separate single PMU pairs for inline off/on show cycles +7.49% / +1.96%, instructions -0.11% / -0.04%,
cache misses +22.94% / +13.19% and branch misses +1.75% / +1.13%. Events cover inherited user-space
threads/children and run for 100% of enabled time. These single samples are variable and do not establish
a cache benefit. Raw [NixOS off](v1/pmu-inline-off-nixos-toplevel.json) / [on](v1/pmu-inline-on-nixos-toplevel.json)
and [nixpkgs off](v1/pmu-inline-off-nixpkgs-73.json) / [on](v1/pmu-inline-on-nixpkgs-73.json) remain available.

## Cached competitors

Neither Nix nor Lix was executed. The same accepted references from generations
[04](../04-20b5ad596/), [05](../05-f2c37f51b/) and [06](../06-aea88bf65/) are reused. These historical
columns were not measured under the current host load, so their ratios are not controlled speedup claims.

| Workload | Current JIT off median | Current JIT on median | Cached Nix 2.35.4 median | Cached Lix 2.91.3 median |
|---|---:|---:|---:|---:|
| NixOS | 4.037 s | 4.133 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.524 s | 3.642 s | 3.85 s | 4.53 s |

Cached reference minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s. Latest cached RSS is Nix
628 / 609 MiB and Lix 755 / 757 MiB. Current memory remains substantially higher, even after the
earlier default [dense-attribute improvement](../dense-selectors-20261028/RESULTS.md).

## Validation and provenance

V1 passes 236 exact eager/demand JIT/interpreter comparisons on macOS/LLVM 23 and Kali/LLVM 22.
Independent call cases cover changed targets and captures, skipped effects, original error positions,
logical depth, recursion, bounds, inline-disabled ablation, and retirement while an expanded callee
is suspended in a demand, including an exception. The macOS full suites pass 479/479 semantic cases
and 221/479 stored-expectation exact cases on both schedules. All 1,434 prior output/error/status files
per schedule match the saved Boolean v3 results; the new fixture returns `true` with no stderr.
[Local validation](../../local/calls-20261028/v1/validation-summary.txt) and the
[Kali focused gate](v1/check-jit.txt) preserve evidence. Kali did not repeat the broad suites.

| Snapshot | SHA-256 |
|---|---|
| V1 source archive | `76c9d9d99ca30eafa717b086ae7816a8c2c488ac4a2ce158ef12836294c6c105` |
| V1 macOS binary | `d1f48f82fefbb26a19ad5008a67cb515386a61451602fd4a7223e5bbe23602c6` |
| V1 Kali binary | `8e4549f55f54ff813973c5d75070b84b48d8b8b4e6db691fedf50f2ed29e88bd` |

The source and binaries were frozen before measurement and retained separately from Boolean v3.
Full workload hashes remain `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
and `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`.
