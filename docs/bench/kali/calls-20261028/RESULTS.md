# Guarded calls in the Boolean graph, 28 October 2026

V2 keeps ordinary inlined entry and return inside generated MLIR control flow. It removes two native-to-host
round trips per inlined call and retains the frame savings: 62,114 frames on NixOS and 161,994 on nixpkgs-73.
It does not establish an end-to-end speedup. Enabling the whole JIT raises median wall time by 2.2% / 3.9%
in the current paired runs. Native execution remains opt-in; Value allocations remain unchanged.

## Implementation and limits

The path is TrikeShed source storage → lazy Nix graph → bounded call/CPS IR → typed MLIR → LLVM IR/native code.
Compilation is independent of source names. After an interpreter oracle returns, specialization reads only
already-WHNF lambda cells and already-indexed bodies. Each formal maps to a persistent caller handle;
captures resolve through the current callee's environment. No observed environment is baked into the plan.

Generated code guards the actual lambda at each reached call, before demanding its argument. In V2 it checks
logical depth, installs the current closure environment, activates its context and branches into the callee
graph. Native Leave restores its parent and continues directly. The host handles lazy demands, missing callee
cell resolution, guard misses and depth errors. Host forcing temporarily installs the active logical depth,
including when a callee formal was mapped to a root argument. Scoped cleanup restores depth on return or
exception. The active-run pin prevents retirement from destroying code suspended in a recursive demand.

Nonforcing admission, three interpreter-first grace completions and bounded retirement remain in place.
Expansion shares 64 nodes, 16 leaves and 256 blocks, with inline depth four and at most 32 native invocations
per run. `MLNIX_JIT_INLINE=0` disables call expansion while retaining the other JIT tiers. Saturated currying,
dynamic projection and collection fusion remain unimplemented. [JIT.md](../../../JIT.md) and
[JIT-CALLS.md](../../../JIT-CALLS.md) describe the contracts.

The [V2 IR example](../../local/calls-20261028/inline-ir-v2/) contains the actual LLVM callee guard and inlined
Boolean graph. Seven inline calls, one guard miss and two exactly-once traces match interpretation; an unused
field stays lazy. It takes 24 native invocations versus 37 in the [V1 example](../../local/calls-20261028/inline-ir/).
The complete [V1 report](RESULTS-V1.md) and raw artifacts are preserved.

## Measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. Inputs and full output hashes are unchanged from the
[Boolean experiment](../lazy-boolean-20261028/RESULTS.md). Runs use demand mode and the default 1,024-call
threshold. Time includes startup, specialization, compilation and grace. Every rotating A/B round requires
success and identical full output hashes. Profiles and PMU samples run separately. RSS below is decimal GB.
The [manifest](v2/commands.txt) and [launcher](v2/commands-v2.sh) record all environments and commands.

Five pairs hold JIT enabled in both arms and change only inlining:

| Workload | Inline off median | Inline on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.128 s | 4.190 s | +1.5% | +0.5% | 1.327 / 1.325 GB |
| nixpkgs-73 | 3.683 s | 3.711 s | +0.8% | +2.6% | 1.229 / 1.222 GB |

Source: [inline ablation](v2/ab-inline-off-on-demand.txt). RSS falls 0.2% / 0.5% in these runs.

Five pairs compare all native tiers disabled/enabled in the same V2 binary:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.084 s | 4.173 s | +2.2% | +4.0% | 1.318 / 1.325 GB |
| nixpkgs-73 | 3.722 s | 3.866 s | +3.9% | +4.1% | 1.220 / 1.222 GB |

Source: [whole-JIT ablation](v2/ab-jit-off-on-demand.txt). These results do not justify enabling JIT by default.

Three additional pairs compare the preserved V1 and V2 binaries with JIT and inlining enabled:

| Workload | V1 median | V2 median | Wall change | CPU change | RSS V1 / V2 |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.131 s | 4.169 s | +0.9% | +0.1% | 1.320 / 1.325 GB |
| nixpkgs-73 | 3.653 s | 3.902 s | +6.8% | +8.5% | 1.217 / 1.222 GB |

Source: [V1/V2 comparison](v2/ab-v1-on-v2-on-demand.txt). Eliminating bookkeeping returns alone did not
produce a timing win in this sample. Host load and run-to-run variation preclude comparing individual
arms across separate experiments as if they were paired measurements.

## Allocation and execution evidence

Untimed profiles isolate actual `newFrame` requests. Requested bytes exclude arena bookkeeping, retained
pages and allocator overhead; they are not RSS. `value allocations` counts actual `allocValue` rows. The old
per-tag counters now explicitly describe instrumented writes, since stack temporaries and repeated retyping
are not a heap census.

| Workload | Frames, inline off | Frames, inline on | Frames removed | Frame bytes removed | Inlined calls |
|---|---:|---:|---:|---:|---:|
| NixOS | 4,930,134 | 4,868,020 | 62,114 | 1,490,736 | 62,117 |
| nixpkgs-73 | 3,194,310 | 3,032,316 | 161,994 | 3,887,856 | 161,997 |

The three-call difference is grace: its oracle still allocates frames. Value allocation counts remain
14,424,286 / 11,770,533 with inlining disabled or enabled. V1 and V2 have identical allocation counts and inline
coverage. One additional kernel per workload handles the wrapper. All six profile outputs match the goldens;
all enabled arms have zero mismatches and compiler failures, and real-workload target guards have zero misses.
Sources: [NixOS off](v2/profile-inline-off-nixos-toplevel.txt) / [on](v2/profile-inline-on-nixos-toplevel.txt),
[nixpkgs off](v2/profile-inline-off-nixpkgs-73.txt) / [on](v2/profile-inline-on-nixpkgs-73.txt).

| Workload | Native invocations, inline off | V1 inline on | V2 inline on | V1 → V2 reduction |
|---|---:|---:|---:|---:|
| NixOS | 219,818 | 406,172 | 281,938 | 124,234 |
| nixpkgs-73 | 399,236 | 885,230 | 561,236 | 323,994 |

V2 removes exactly two invocations per inline call. Reached callee resolution still returns to the host;
actual lazy demands are unchanged. The inline-on profiles report compilation elapsed time of 70.6 ms / 151.5 ms,
versus 60.0 ms / 36.0 ms with inlining disabled. These single diagnostic samples include initial context setup,
IR emission, lowering and native generation, including failed attempts; they exclude plan analysis, specialization,
hotness and interpretation. They are neither paired compiler costs nor total JIT cost.

Separate single PMU pairs for inline off/on show cycles +0.77% / −2.30%, instructions +0.23% / −0.23%,
cache misses +2.64% / +0.30% and branch misses +0.19% / +0.76%. Events cover inherited user-space threads/children
and run for 100% of enabled time. These small, single samples do not establish a cache-locality benefit.
Raw [NixOS off](v2/pmu-inline-off-nixos-toplevel.json) / [on](v2/pmu-inline-on-nixos-toplevel.json) and
[nixpkgs off](v2/pmu-inline-off-nixpkgs-73.json) / [on](v2/pmu-inline-on-nixpkgs-73.json) remain available.

## Cached competitors

Neither Nix nor Lix was executed. Accepted same-host references from generations
[04](../04-20b5ad596/), [05](../05-f2c37f51b/) and [06](../06-aea88bf65/) are reused. Reference medians/minima are
the best accepted results across those generations; RSS is the latest accepted result. They were not measured
under the current host load, so ratios against them are not controlled speedup claims.

| Workload | V2 JIT off median | V2 JIT on median | Cached Nix 2.35.4 median | Cached Lix 2.91.3 median |
|---|---:|---:|---:|---:|
| NixOS | 4.084 s | 4.173 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.722 s | 3.866 s | 3.85 s | 4.53 s |

Cached reference minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s. Latest cached RSS is Nix
628 / 609 MiB and Lix 755 / 757 MiB. Current memory remains substantially higher, even after the earlier
default [dense-attribute improvement](../dense-selectors-20261028/RESULTS.md).

## Validation and provenance

V2 passes 240 exact eager/demand JIT/interpreter comparisons on macOS/LLVM 23 and Kali/LLVM 22. The focused
gate covers changed targets and captures, skipped effects, original error positions, logical depth, recursion,
bounds, inline-disabled ablation and retirement while a demand is suspended, including exceptions. Two added
cases check logical depth during host forcing inside a callee and restoration before a later caller demand.

Both macOS full schedules pass 479/479 semantic cases and 221/479 stored-expectation exact cases. All 1,437
saved output/error/status files per schedule are byte-identical to V1. [Local validation](../../local/calls-20261028/v2/validation-summary.txt)
and the [Kali focused gate](v2/check-jit.txt) preserve evidence. Kali did not repeat the broad suites.

| Snapshot | SHA-256 |
|---|---|
| V2 source archive | `af5cbebee803f37d72b8a1e98cf5b55a03b49e4ca6481e65522b3e8a260553b5` |
| V2 macOS binary | `7c9475f29ec2639e8f3f3798da431a0f5cab896e93020ee28bc4bf3e26d54fca` |
| V2 Kali binary | `1679d14d0d3d2a1faabf17e94e11db414c97f3b2bf64fa5b13d50807194bcd85` |

Source and binaries were frozen before measurement and retained separately from V1 and Boolean V3.
Full workload hashes remain `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
and `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`.
