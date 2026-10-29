# Saturated curried calls, 28 October 2026

The native compiler now consumes exactly saturated unary-lambda chains with two to four remaining arguments.
This removes intermediate closure Values and their frames while preserving lazy arguments and current captures.
Kali profiles measure 77,354 fewer frames and Values on NixOS, and 188,506 fewer of each on nixpkgs-73:
3.71 / 9.05 MB of requested storage removed. Throughput does not improve: the within-binary curried tier
raises median wall time by 0.5% / 2.8%. The whole JIT remains opt-in.

## Implemented pipeline

The existing TrikeShed source/region representation feeds the lazy Nix graph, a bounded argument/call/CPS plan,
typed MLIR and LLVM IR/native code. The new `callFunction` hook sees all remaining arguments before it allocates
an intermediate result. It admits a direct chain of unary lambdas, discovering descendant bodies only after
an interpreter oracle has already indexed them. It binds formals to persistent argument cells and resolves
other captures through the actual outer closure. No temporary stack frames or observed environments are baked
into code. Reached inlined callees retain their own actual capture environments, even when their SSA identities
also appear among the eliminated stages.

The caller's original depth surrounds the oracle and fallback. Native execution and observation enter one
logical stage: curried stages are sequential calls at caller depth plus one, while nested calls add depth normally.
Partial applications retain durable closures. Unsupported outer locals, defaults and escaping result branches
stay interpreted. An ordinary prefix may expose an eligible two-to-four-argument suffix. If an argument aliases
the output cell, the saturated tier is bypassed so the oracle cannot overwrite an input before validation.

Each region holds an optional pointer to an arity-indexed cache. The JIT owns at most 256 such caches and
256 saturated entries, separately from the existing 256 unary candidates; all tiers share 16 compiler attempts.
Graphs retain the 64-node, 16-leaf, 256-block, inline-depth-four and 32-native-invocation bounds. The shared lazy
executor retains nonforcing admission, three interpreter-first grace completions and retirement after 64
consecutive native deopts, with active runs pinning their code through recursive demands and exceptions.
`MLNIX_JIT_CURRIED=0` ablates the new tier; `MLNIX_JIT_INLINE=0` independently disables cross-lambda expansion.

[JIT.md](../../../JIT.md) and [JIT-CALLS.md](../../../JIT-CALLS.md) describe the contracts and limitations.
The [three-argument IR example](../../local/curried-20261028/ir-v1/) preserves current ancestor captures, untouched
throwing branches, exactly-once traces and a changed-callee guard miss. Its plan, typed MLIR and optimized LLVM
IR are saved. Tests cover two through four arguments; measured workload kernels below all have arity two.

## Coverage and allocation evidence

Untimed profiles compare the same binary with JIT enabled, changing only the curried flag. All six profile
outputs have the original full hashes. Compiler failures and mismatches are zero; measured saturated kernels
complete without deopts. Existing unary predicates still execute during warmup and grace.

| Kernel | NixOS calls / native completions | nixpkgs calls / native completions |
|---|---:|---:|
| `removeFunctions` predicate, systems/default.nix:46:41 | 63,140 / 62,117 | 163,020 / 161,997 |
| `assertMsg`, asserts.nix:50:15 | 13,536 / 12,513 | 25,078 / 24,055 |
| types.nix:833:32 | 3,577 / 2,554 | no compiled kernel |
| customisation.nix:254:24 | 1,205 / 182 | 3,486 / 2,463 |

Per-outer `jit-curried` rows record actual remaining arity and native completions, avoiding inference from unary
call counts. Sources: [NixOS profile](v1/profile-curried-on-nixos-toplevel.txt) and
[nixpkgs profile](v1/profile-curried-on-nixpkgs-73.txt).

| Workload | Frames off → on | Value rows off → on | Reduction in each | Combined requested bytes removed |
|---|---:|---:|---:|---:|
| NixOS | 4,868,020 → 4,790,666 | 14,424,286 → 14,346,932 | 77,354 | 3,712,992 |
| nixpkgs-73 | 3,032,316 → 2,843,810 | 11,770,533 → 11,582,027 | 188,506 | 9,048,288 |

These are actual `newFrame` and `allocValue` counts. Both eliminated objects request 24 bytes on these paths.
The combined byte figures exclude arena overhead and retained pages and are not RSS. The three grace calls
per kernel still execute the oracle. `curried_frames_saved` instead counts all semantic chain frames avoided:
154,708 / 377,012, twice the incremental frame reduction here because the unary JIT already avoids final-stage
frames. Use the allocation table for measured savings. Sources: [NixOS off](v1/profile-curried-off-nixos-toplevel.txt)
and [nixpkgs off](v1/profile-curried-off-nixpkgs-73.txt), paired with the on profiles above.

Native invocations fall 281,938 → 277,566 / 561,236 → 552,451; actual lazy-demand counts remain unchanged.
Compilation elapsed time in these single diagnostic samples rises 68.6 → 100.4 ms / 56.5 → 69.7 ms.
These unpaired compile clocks include IR emission, lowering, native generation and first context setup,
but exclude analysis, specialization and interpretation. They cannot be subtracted from paired timing runs
as a causal explanation. The saturated candidate table reaches its bound in both workloads; no additional
coverage beyond the admitted kernels is claimed.

## Paired Kali measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. All runs use demand mode, the default 1,024-call threshold,
rotating A/B order, success checks and identical full output hashes. Stats and profiling are absent from timings.
RSS is decimal GB. The [manifest](v1/commands.txt) and [launcher](v1/commands-v1.sh) record exact environments,
including explicit clearing of `MLNIX_JIT_CURRIED`. Nix and Lix are never launched.

Five pairs with JIT enabled in both arms:

| Workload | Curried off median | Curried on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.117 s | 4.139 s | +0.5% | −1.8% | 1.325 / 1.327 GB |
| nixpkgs-73 | 3.589 s | 3.690 s | +2.8% | +5.0% | 1.222 / 1.221 GB |

[Curried ablation](v1/ab-curried-off-on-demand.txt). RSS changes +0.2% / −0.1%, despite fewer requested bytes.

Five pairs with the whole JIT disabled/enabled in the candidate:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.985 s | 4.097 s | +2.8% | +2.1% | 1.318 / 1.327 GB |
| nixpkgs-73 | 3.526 s | 3.654 s | +3.6% | +6.8% | 1.220 / 1.221 GB |

[Whole-JIT ablation](v1/ab-jit-off-on-demand.txt). These measurements do not justify enabling native execution by default.

Three pairs check the new default path against preserved Calls V2, with JIT disabled in both:

| Workload | Calls V2 median | Candidate median | Wall change | CPU change | RSS V2 / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.038 s | 3.995 s | −1.1% | −2.7% | 1.316 / 1.318 GB |
| nixpkgs-73 | 3.577 s | 3.689 s | +3.1% | +4.0% | 1.217 / 1.220 GB |

[Default-path control](v1/ab-calls-v2-candidate-jit-off-demand.txt). Results are mixed. Minima are 3.987 → 3.899 s
and 3.559 → 3.554 s; those do not remove the observed median/CPU regression on nixpkgs. The new hook and region
cache field have not demonstrated a default-path speedup. These small samples do not isolate a cause, and arms
from separate series must not be treated as a paired comparison.

Single curried-off/on PMU pairs show cycles +4.24% / +1.70%, instructions +1.72% / +1.03%, cache misses
+6.29% / +3.79% and branch misses +2.65% / +1.94%. Events cover inherited user-space threads/children and run for
100% of enabled time. Single samples do not establish a causal cache penalty or locality improvement.
Raw [NixOS off](v1/pmu-curried-off-nixos-toplevel.json) / [on](v1/pmu-curried-on-nixos-toplevel.json) and
[nixpkgs off](v1/pmu-curried-off-nixpkgs-73.json) / [on](v1/pmu-curried-on-nixpkgs-73.json) are retained.

## Cached competitors

Accepted same-host reference records from generations [04](../04-20b5ad596/), [05](../05-f2c37f51b/) and
[06](../06-aea88bf65/) are reused. Medians below are the best accepted historical medians across those generations;
RSS is from the latest accepted record. They were not collected under the current load and do not support
controlled speedup claims against Nix or Lix.

| Workload | Candidate JIT off | Candidate JIT on | Cached Nix 2.35.4 | Cached Lix 2.91.3 |
|---|---:|---:|---:|---:|
| NixOS | 3.985 s | 4.097 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.526 s | 3.654 s | 3.85 s | 4.53 s |

Cached minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s. Cached RSS is Nix 628 / 609 MiB and
Lix 755 / 757 MiB. mlnix still uses substantially more peak memory. No reference startup, version,
RSS measurement or evaluation process was invoked.

## Validation and provenance

The candidate passes 300 exact eager/demand JIT/interpreter comparisons on macOS/LLVM 23 and Kali/LLVM 22.
New cases cover multiple argument handles, same-lambda/different-environment captures, preserved deferred
closures, wrong arity followed by valid saturation, sequential and nested depth, skipped effects, fallback
following persistent demands, recursive admission and retirement, and the curried-disabled ablation.
Both macOS full schedules pass 480/480 semantic cases and 222/480 stored exact expectations; all 1,437 prior
output/error/status files per schedule match Calls V2, and the new fixture returns true with no stderr.
[Local validation](../../local/curried-20261028/v1/validation-summary.txt) and the [Kali gate](v1/check-jit.txt)
preserve evidence. Kali did not repeat the broad suites.

| Snapshot | SHA-256 |
|---|---|
| Curried V1 source archive | `86b2153ef7087a382bceca6c4d3a79d3a87afc106844883256fc4d408a7c5b49` |
| Curried V1 macOS binary | `72196002deb30582c917690cfa35322ef39a7a17ee172c1083103194e89e564a` |
| Curried V1 Kali binary | `919d653831c6b034770dd9312f7cfdf305c075b7e01ee87fd33d56f4de8a95bc` |

Source and binaries were frozen before measurements. Preserved Calls V2 remains available; the
[parked builtin-allocation patch](../builtin-results-20261028/RESULTS.md) is absent. Full workload hashes remain
`2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86` and
`5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`.

General local memo cells with durable deoptimization state, dynamic attribute projection, escaping native
closures and collection fusion remain unfinished. The measured next costs include per-arity dispatch and
compilation; fewer frames alone does not prove that this compiler stage is faster or more cache-local.
