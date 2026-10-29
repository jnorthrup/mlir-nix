# Curried dispatch gate, 28 October 2026

V2 bypasses the curried dispatcher for arity slots already refused. It reduces dispatcher entries by 86.4%
on NixOS and 73.8% on nixpkgs-73 while preserving native coverage and allocation counts exactly. Paired timings
remain mixed: with JIT enabled, median wall time changes by −0.4% / +2.8%. The JIT-disabled controls also vary,
so this experiment does not establish a causal end-to-end speedup. Native execution remains opt-in.

## Change and scope

The frozen change adds an inline rejected-arity gate and publishes every curried refusal to that gate.
Previously, calls with a cached refused arity still entered the dispatcher. Accepted plans, their grace,
native execution and fallback behavior are unchanged. The source snapshot predates dynamic projection work;
the parked builtin-result allocation patch is absent. The [Curried V1 report](RESULTS.md) describes the
underlying saturated-call implementation and remains the baseline for this comparison.

## Profile evidence

Untimed candidate profiles use demand mode, JIT enabled and the default 1,024-call threshold. They are
compared with the saved Curried V1 profiles. Full output hashes match. Every printed JIT counter is identical
except compilation elapsed time and the three arity-entry counters; frame and Value counts, requested bytes
and frame slots are identical. Compiler failures, mismatches and curried deopts remain zero.

| Workload | V1 dispatcher entries | V2 dispatcher entries | Entries removed | Reduction |
|---|---:|---:|---:|---:|
| NixOS | 1,346,033 | 183,552 | 1,162,481 | 86.4% |
| nixpkgs-73 | 1,029,400 | 269,277 | 760,123 | 73.8% |

Entries are the sum of `curried_arity2`, `curried_arity3` and `curried_arity4`. In V2 these counters exclude
calls bypassed by the rejected-slot gate; the reduction does not mean fewer Nix function calls or less
semantic work. Per-location native completion counts remain unchanged.

| Workload | Compiled curried kernels | Curried completions | Native invocations | Frame allocations | Value allocations |
|---|---:|---:|---:|---:|---:|
| NixOS, both versions | 4 | 77,366 | 277,566 | 4,790,666 | 14,346,932 |
| nixpkgs-73, both versions | 3 | 188,515 | 552,451 | 2,843,810 | 11,582,027 |

Native invocations here are the existing `boolean_resumes` counter. Requested frame/Value bytes remain
299,481,416 / 344,326,368 for NixOS and 257,876,320 / 277,968,648 for nixpkgs-73. Frame slots remain
27,853,845 / 26,546,920. Requested storage excludes arena overhead and retained pages; it is not RSS.

Compilation elapsed time is 100.4 → 105.8 ms / 69.7 → 72.3 ms in the single diagnostic samples. These clocks
include IR emission, lowering, native generation and first context setup, but exclude analysis,
specialization and interpretation. They cannot be subtracted from paired timing runs as a causal explanation.
Sources: [V1 NixOS](v1/profile-curried-on-nixos-toplevel.txt) / [V2 NixOS](dispatch-v2/profile-jit-on-nixos-toplevel.txt)
and [V1 nixpkgs](v1/profile-curried-on-nixpkgs-73.txt) / [V2 nixpkgs](dispatch-v2/profile-jit-on-nixpkgs-73.txt).

## Paired Kali measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. Every series uses demand mode, rotating A/B order,
successful child exits and identical full output hashes. Stats and profiling are absent from timings.
Time includes startup, specialization, compilation and grace. RSS is decimal GB. The
[manifest](dispatch-v2/commands.txt) and [launcher](dispatch-v2/commands-v2.sh) record exact commands and
cleared environment variables, including `MLNIX_JIT_CURRIED` and `MLNIX_JIT_INLINE`.

Five pairs compare preserved Curried V1 against dispatch V2, with JIT enabled in both:

| Workload | V1 median | V2 median | Wall change | CPU change | RSS V1 / V2 |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.181 s | 4.163 s | −0.4% | +0.1% | 1.323 / 1.327 GB |
| nixpkgs-73 | 3.627 s | 3.726 s | +2.8% | +2.5% | 1.216 / 1.221 GB |

[JIT-enabled comparison](dispatch-v2/ab-v1-v2-jit-on-demand.txt). RSS changes +0.3% / +0.4%, despite identical
allocation counts.

Three paired controls compare the same binaries with JIT disabled:

| Workload | V1 median | V2 median | Wall change | CPU change | RSS V1 / V2 |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.969 s | 3.959 s | −0.3% | −0.1% | 1.316 / 1.318 GB |
| nixpkgs-73 | 3.553 s | 3.758 s | +5.7% | +5.4% | 1.217 / 1.220 GB |

[JIT-disabled controls](dispatch-v2/ab-v1-v2-jit-off-demand.txt). RSS changes +0.2% / +0.3%. The nixpkgs control
minima are 3.535 → 3.517 s despite the slower V2 median, demonstrating material variation. The OFF control
regresses more than the ON comparison on that workload. These results neither isolate an ON slowdown to the
dispatch gate nor establish a causal speedup from it. Arms from the separate ON and OFF series are not a
paired whole-JIT comparison and must not be treated as one.

The benchmark lock serialized this work; no competing mlnix build or benchmark was present at launch.
Unrelated host processes were left untouched. One-minute load was 0.10 at the start and 1.02 at completion;
available memory was 8,714 → 8,658 MiB, with no swap used. These endpoint readings do not rule out transient
contention or frequency variation. [Start metadata](dispatch-v2/metadata-start.txt) and
[end metadata](dispatch-v2/metadata-end.txt) are retained.

## Separate hardware counters

One V1/V2 pair per workload uses JIT enabled in both arms, separately from timing runs. Counters cover
inherited user-space threads/children; every event ran for 100% of enabled time, without multiplexing.

| Workload | Cycles | Instructions | Cache misses | Branch misses |
|---|---:|---:|---:|---:|
| NixOS, V2 versus V1 | −0.90% | −0.46% | −2.65% | −0.35% |
| nixpkgs-73, V2 versus V1 | +1.43% | −0.22% | +7.53% | +0.38% |

Instructions decrease slightly in both single samples, consistent with less dispatcher work, but these pairs
do not establish a robust cache-locality or throughput improvement. Raw
[NixOS V1](dispatch-v2/pmu-v1-jit-on-nixos-toplevel.json) / [V2](dispatch-v2/pmu-v2-jit-on-nixos-toplevel.json) and
[nixpkgs V1](dispatch-v2/pmu-v1-jit-on-nixpkgs-73.json) / [V2](dispatch-v2/pmu-v2-jit-on-nixpkgs-73.json) are saved.

## Cached competitors

Saved Nix 2.35.4 and Lix 2.91.3 references are unchanged. Accepted same-host records from generations
[04](../04-20b5ad596/), [05](../05-f2c37f51b/) and [06](../06-aea88bf65/) remain the source: historical best
accepted medians are Nix 4.10 / 3.85 s and Lix 4.65 / 4.53 s for NixOS / nixpkgs-73. Latest accepted RSS is
Nix 628 / 609 MiB and Lix 755 / 757 MiB. No reference evaluation, startup, version query or RSS measurement
was executed. These cached values were collected under different host conditions and do not support a
controlled competitor speedup claim for this candidate.

## Validation and provenance

The [Kali focused gate](dispatch-v2/check-jit.txt) passes all 300 exact comparisons: 150 eager and 150 demand,
covering scalar, pointer, Boolean, inline-call, curried, ablation, demand, deopt, grace and budget behavior.
Kali did not repeat the broad language suites. This report adds no new measurements.

| Snapshot | SHA-256 |
|---|---|
| Curried V1 source archive | `86b2153ef7087a382bceca6c4d3a79d3a87afc106844883256fc4d408a7c5b49` |
| Curried V1 Kali binary | `919d653831c6b034770dd9312f7cfdf305c075b7e01ee87fd33d56f4de8a95bc` |
| Dispatch V2 source archive, 821,625 bytes | `77d0788b1a5355acd3d7d9511c69c150c030b5b18446e7b6d6817415b56dec71` |
| Dispatch V2 macOS binary | `498a6a7db966d60c0457b4363621e63dd16c098a000bfdbf95b3fed061fdd12c` |
| Dispatch V2 Kali binary | `de551d73456085ea01fe1770d6011ceb99106b0d077ed9d5be2750fe4c6465ae` |

The frozen archive is `/tmp/mlir-nix-curried-dispatch-v2-20261028.tar.gz`. Preserved Kali binaries are
`/tmp/kb/curried-20261028-v1/mlnix` and `/tmp/kb/curried-20261028-dispatch-v2/mlnix`.
[Source/binary checksums](dispatch-v2/source.txt) and [completion record](dispatch-v2/complete.txt) are retained.
Full workload SHA-256 values remain:

- NixOS: `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
- nixpkgs-73: `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`
