# Lazy list-return recipes, 28 October 2026

List Returns V1 compiles tail lists containing one to four persistent element handles. This covers both
branches of the generic `cond: elem: if cond then [elem] else []` shape while keeping elements unevaluated.
The compiler recognizes graph structure; it does not match a library function's name or source location.
Against the same binary with list recipes disabled, it removes 120,304 / 34,274 frame allocations and
60,152 / 17,137 Value allocations on NixOS / nixpkgs-73, saving 4,330,944 / 1,233,864 requested bytes.
Median wall time changes +1.2% / −7.6%, but minima do not support the large package-workload median gain.
Whole-JIT-off/on wall time rises 6.5% / 4.0%, so native execution remains opt-in.

## Implementation and semantic limits

ReturnList checks only pointer availability, without reading element tags. Thunk, App and Blackhole cells
are valid lazy elements. Root arguments already supply handles. A missing capture requests one host batch
that peeks its real frame slot and calls nonforcing `lookup` only if necessary. Resolution happens in the
current closure environment before any required native Leave clears that context. The operation does not
invoke a predicate, force a projected field or evaluate an element.

Codes `20 + recipe-id` identify bounded plan descriptors, separate from cell and empty-recipe results.
After the complete Leave chain reaches status `6`, the host validates root context, zero relative depth,
an allowlisted descriptor, length and every nonnull Cell handle. It copies the ordered pointers into the
result's own bounded array, then allocates and fills a fresh arena list only after trusted completion.
No Runtime stack storage or plan storage escapes. Duplicate elements retain their original shared cell;
active-run pinning covers demands, fallback, final materialization and reentrant retirement.

The observer only peeks existing handles. Grace checks list length and ordered element-pointer identities,
without inspecting element payloads, deep equality or duplicate list allocation. Missing handles deopt,
and the interpreter's original list is returned during grace. Boolean consumers still reject lists with
the ordinary type diagnostic. Input/output alias bypass, call-depth restoration and current-callee guards
retain the existing contract.

Every element must qualify before a recipe is built. Current-local computations, virtual projections,
locals belonging to eliminated call frames and `kNoSlot` captures remain unsupported. In particular,
`[x.field]` cannot use the existing projection recipe: list construction must leave that field lazy.
Larger lists and local expression/closure creation need further lowering. The existing 64-node, 16-leaf,
256-continuation/block, four-inline-depth and 32-resume limits remain. The list descriptors are bounded by
the source-node limit; emitted handle checks and requests count against the block budget.

`MLNIX_JIT_LISTS=0` disables nonempty recipes while retaining cell and empty returns. It is subordinate to
`MLNIX_JIT_VALUES=0`, and is read during cold plan construction. Both are inside the opt-in `MLNIX_JIT=1`
tier. [JIT.md](../../../JIT.md) and [JIT-CALLS.md](../../../JIT-CALLS.md) describe the protocol.

## Coverage and allocation analysis

The [saved local analysis](../../local/list-returns-20261028/v1/profile-analysis.txt) and
[structured evidence](../../local/list-returns-20261028/v1/profile-analysis.json) compare JIT disabled,
LISTS disabled and LISTS enabled at the default threshold of 1,024 calls. LISTS disabled reproduces all
59 prior JIT aggregate values other than `compile_ns`, all five allocator fields and the JIT-off allocator
controls. The three new list counters are zero in that ablation. All six local outputs match their saved
goldens; the distinct local NixOS result does not replace Kali's golden.

Kali's [three-arm profiles](v1/profile-summary.json) and [exact deltas](v1/profile-deltas.json) reproduce
the same native-counter and allocation reductions, with all six outputs matching the unchanged Kali goldens:

| Measurement, LISTS off → on | NixOS | nixpkgs-73 |
|---|---:|---:|
| Total compiled engines | 16 → 16 | 16 → 16 |
| Nonempty-list completions | 0 → 23,930 | 0 → 17,138 |
| Curried completions | 100,982 → 161,134 | 452,713 → 469,850 |
| Curried fallbacks | 139 → 0 | 17,137 → 0 |
| All lazy-graph fallbacks | 7,460 → 7,257 | 19,293 → 2,091 |
| Lazy-graph native invocations | 786,660 → 902,262 | 1,196,516 → 1,196,387 |
| Host forcing actions | 369,581 → 425,298 | 470,862 → 470,863 |
| Frame allocations | 4,612,632 → 4,492,328 | 2,481,560 → 2,447,286 |
| Value allocations | 14,305,059 → 14,244,907 | 11,277,147 → 11,260,010 |
| Compiler elapsed time, diagnostic sample | 126.7 → 131.0 ms | 124.6 → 143.9 ms |

Frame requests fall 2.61% / 1.38%; Value requests fall 0.42% / 0.15%. Frame bytes fall 2,887,296 /
822,576, and Value bytes fall 1,443,648 / 411,288. These counters measure evaluator frame and Value
allocation requests, excluding allocator overhead, list buffers and retained pages; they are not peak RSS.
NixOS's extra coverage adds 115,602 native invocations and 55,717 host forcing actions. Compiler elapsed
samples include setup/emission/lowering/native generation, exclude analysis and oracle work, and are not
the full cost of compilation or causal explanations for separate timing-series changes.

The two list-capable engines on each workload record 23,930 / 17,138 nonempty-list completions, including
grace. The printed curried `optional` entry records 23,927 / 17,137 of these; top-60 rows do not locate the
remaining 3 / 1 completions. That curried entry now completes 60,185 / 68,770 calls with zero fallbacks.
NixOS's formerly retired partial plan stays active, gaining many empty-arm completions as well as nonempty
ones. The package plan replaces its 17,137 reached nonempty-arm fallbacks directly.

Value, empty, list and curried counts overlap: empty and nonempty recipes are disjoint subsets of value
completions, and curried counts also contribute to the aggregate lazy-graph counts. They must not be
added as independent savings. Pointer-selector executions and persistent-cell completion totals are unchanged.
The old `boolean_*` names still aggregate the whole lazy graph tier, including general value results.

Both workloads compile 16 total engines, with unchanged curried counts of 3 / 7 and value-capable counts
of 10 / 6. Shared printed plans retain their native coverage. The observed change is `optional` remaining
active past its old retirement point; there is no measured productive-plan displacement. Per-entry refusal
causes and compilation order are not logged. Both workloads still reach the curried candidate cap.

Remaining fallbacks are 7,257 / 2,091. Visible NixOS rows account for 5,995 at `modules.nix:802` and 134
callback guard misses; 1,128 remain unattributed. Package callback misses account for 232, leaving 1,859
unattributed. NixOS profiling reaches its 4,096-entry unary cap, and only 60 highest-call rows per category
are printed. Aggregate counters are complete. Durable-capture handle lookup is tested, but the two real
workloads record zero such lookups: their hot list returns use existing argument handles.

## Paired Kali measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. All timings use demand mode, rotating A/B order,
successful child exits and identical full output hashes. Stats and profiling are absent. Times include
startup, specialization, compilation and grace. RSS is decimal GB. The [manifest](v1/commands.txt) and
[launcher](v1/commands-v1.sh) record exact settings; inherited feature flags, including LISTS, are cleared
before the series, then explicitly set per arm.

Five pairs compare LISTS disabled/enabled with JIT enabled in both:

| Workload | LISTS off median | LISTS on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.153 s | 4.201 s | +1.2% | +1.2% | 1.319 / 1.321 GB |
| nixpkgs-73 | 3.802 s | 3.515 s | −7.6% | −7.1% | 1.208 / 1.208 GB |

[List ablation](v1/ab-lists-off-on-demand.txt). RSS changes are +0.2% / +0.0%; the extra allocation savings
do not produce a measured peak-memory reduction. Minima are 3.996 → 3.982 s and 3.496 → 3.499 s. The package
median improvement is therefore not supported by a lower minimum, and should not be treated as a robust
7.6% speedup. These five rounds show substantial variability.

Five separate pairs compare the whole JIT disabled/enabled:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.958 s | 4.215 s | +6.5% | +5.9% | 1.319 / 1.321 GB |
| nixpkgs-73 | 3.586 s | 3.730 s | +4.0% | +3.1% | 1.220 / 1.208 GB |

[Whole-JIT ablation](v1/ab-jit-off-on-demand.txt). RSS changes are +0.2% / −1.0%; minima are 3.723 → 4.067 s
and 3.351 → 3.509 s. These series do not justify enabling native execution by default. Arms from different
series are not paired comparisons and must not be combined into a speedup estimate.

Three pairs compare preserved Values V1 with the candidate, JIT enabled in both:

| Workload | Values V1 median | Candidate median | Wall change | CPU change | RSS prior / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.980 s | 4.291 s | +7.8% | +9.0% | 1.314 / 1.323 GB |
| nixpkgs-73 | 3.699 s | 3.568 s | −3.5% | −3.5% | 1.203 / 1.208 GB |

[Preserved-binary comparison](v1/ab-values-v1-candidate-jit-on-demand.txt). RSS changes are +0.6% / +0.4%.
Minima are 3.967 → 3.964 s and 3.518 → 3.463 s; the NixOS median difference accompanies substantial
candidate dispersion. Separate three-pair controls disable JIT in both binaries:

| Workload | Values V1 median | Candidate median | Wall change | CPU change | RSS prior / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.023 s | 3.940 s | −2.1% | −2.2% | 1.316 / 1.318 GB |
| nixpkgs-73 | 3.510 s | 3.724 s | +6.1% | +4.0% | 1.217 / 1.220 GB |

[Default-path controls](v1/ab-values-v1-candidate-jit-off-demand.txt). Their minima are 3.759 → 3.772 s and
3.494 → 3.443 s, moving differently from their medians. The mixed controls further limit causal claims;
subtracting control-series changes from JIT-series changes would not isolate the feature's cost. The
within-binary LISTS ablation is the direct feature comparison, including its observed variability.

The benchmark lock serialized the main job. Eight host snapshots span before-build, before profiles, each
timing/PMU series and completion. Each shows zero swap and no Java, mlnix or build process at that boundary.
Available memory stays between 14,472 and 14,555 MiB. One-minute load is 0.10 before build, 1.46 after
build/gates, 1.10–1.30 before timing/PMU series and 1.22 at completion. See
[start](v1/host-00-before-build.txt), [first timing boundary](v1/host-02-before-lists-ablation.txt) and
[completion](v1/host-07-complete.txt); all eight snapshots are retained. These are boundary observations,
not continuous monitoring. No external process was changed.

## Hardware counters and repeatability

The initial separate LISTS-off/on pair showed large cache-miss reductions. Exactly three additional pairs
per workload tested repeatability with the same frozen binary, using on/off, off/on, on/off order. The
original pair remains unchanged, giving four equally weighted pairs and balanced order. Counters cover
inherited user-space threads/children, excluding kernel/hypervisor; every event ran for 100% of enabled time.

All changes below are `(ON/OFF − 1) × 100` for that pair:

| Workload | Pair | Order | Cycles | Instructions | Cache misses | Branch misses |
|---|---:|---|---:|---:|---:|---:|
| NixOS | 0 | off/on | −0.90% | +0.0004% | −7.13% | +0.01% |
| NixOS | 1 | on/off | +2.71% | −0.18% | +9.36% | +5.54% |
| NixOS | 2 | off/on | −0.09% | −0.26% | −1.15% | −0.37% |
| NixOS | 3 | on/off | −0.31% | −0.04% | −1.71% | +0.56% |
| nixpkgs-73 | 0 | off/on | −3.01% | −0.07% | −17.11% | −0.86% |
| nixpkgs-73 | 1 | on/off | +0.79% | −0.07% | +3.82% | +0.63% |
| nixpkgs-73 | 2 | off/on | −1.92% | −0.30% | −13.21% | −0.60% |
| nixpkgs-73 | 3 | on/off | +1.13% | −0.22% | +1.55% | +0.27% |

Median paired cache-miss changes are −1.43% / −5.83%, with ranges −7.13%…+9.36% and −17.11%…+3.82%.
Both ranges cross zero. On the package workload, both off/on pairs reduce misses and both on/off pairs
increase them. That order-sensitive result does not identify the cause, but it does not confirm the initial
large reduction as a robust locality improvement. Median paired cycle changes are −0.20% / −0.56%,
instruction changes −0.11% / −0.15%, and branch-miss changes +0.28% / −0.17%. These are medians of four
paired percentages, not ratios of pooled counters, and do not establish a wall-time speedup.

Raw [NixOS off](v1/pmu-lists-off-nixos-toplevel.json) / [on](v1/pmu-lists-on-nixos-toplevel.json) and
[nixpkgs off](v1/pmu-lists-off-nixpkgs-73.json) / [on](v1/pmu-lists-on-nixpkgs-73.json) are retained.
The launcher records inherited JIT/LISTS settings omitted from the PMU JSON child command arrays.
The PMU helper records successful exits but does not capture stdout hashes; output validation comes from
the separate profile and paired timing runs with the same frozen binary and workloads.
The [confirmation summary](v1/pmu-confirmation/summary.txt), [structured samples](v1/pmu-confirmation/summary.json),
[exact launcher](v1/pmu-confirmation/commands.sh) and [parameters](v1/pmu-confirmation/parameters.json) retain
all four pairs, all raw counters and ranges. All 16 samples exit successfully. Candidate hashes were checked
before and after each added pair; six before-pair host snapshots and a completion snapshot are retained.
No build, gate, broad suite, new timing series or Nix/Lix process ran during confirmation.

## Cached Nix and Lix references

Accepted same-host records from generations [04](../04-20b5ad596/), [05](../05-f2c37f51b/) and
[06](../06-aea88bf65/) are reused. Competitor medians are the best accepted historical medians across those
generations; RSS uses the latest accepted record. Host conditions differ, so this is historical context,
not a controlled competitor speedup claim.

| Workload | Candidate JIT off | Candidate JIT on | Cached Nix 2.35.4 | Cached Lix 2.91.3 |
|---|---:|---:|---:|---:|
| NixOS | 3.958 s | 4.215 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.586 s | 3.730 s | 3.85 s | 4.53 s |

Cached minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s; cached RSS is Nix 628 / 609 MiB and Lix 755 /
757 MiB. mlnix still uses substantially more peak memory. No reference evaluation, startup, version query
or RSS process was invoked.

## Validation and inspectable lowering

The candidate passes 536 exact comparisons [locally](../../local/list-returns-20261028/v1/check-jit.txt) and
[on Kali](v1/check-jit.txt),
268 on each schedule. The 29 new cases and three ablations cover unforced throwing/tracing/cyclic elements,
productive self-lists, delayed errors, duplicate handles, fresh/current captures, two-to-four-argument
ordering, nested and saturated inline calls, strict Boolean contexts, local/virtual-projection exclusions,
resource bounds, recursive admission and retirement with escaping results. Independent counters prove
execution beyond grace; the direct singleton case has five list completions, three grace checks, zero
forcing demands and zero capture lookups. The fresh-capture case proves a nonforcing lookup.

Both full local schedules pass 483/483 semantic cases with 225 stored exact expectations. All 1,446 prior
output/error/status files per schedule remain byte-identical; the new fixture returns true without stderr.
[Validation](../../local/list-returns-20261028/v1/validation-summary.txt) and
[suite parity](../../local/list-returns-20261028/v1/suite-parity.txt) retain the commands and manifests.

The [IR guide](../../local/list-returns-20261028/ir-v1/README.txt) follows descriptor `20`, ordered leaves
`3,2,3`, ReturnList continuation `9`, nested Leaves `8 → 5` and status `6` through typed MLIR and LLVM.
Its output `[3,42,42]` and single trace match the preserved Values V1 interpreter. The final example realizes
the changed closure while leaving its capture lazy, then records 17 list completions, 15 grace checks,
zero demands/fallbacks/guard misses and one nonforcing capture lookup. The throwing middle element is unused.

## Provenance

| Snapshot | SHA-256 |
|---|---|
| List Returns V1 source, 1,559,218 bytes | `d6e161d79b6ef2eeadf1281ed79fc1eaeee34679b41455dea06b49c04613a9d8` |
| List Returns V1 macOS binary | `e2798d307b0dca6a41d7718cd33f38a6578b2173bfa5fed7564555077187935d` |
| List Returns V1 Kali binary | `a34739ca7f9dddaf7db70c45fa33c445b3ead6192e8bb5b2736527797b227e14` |
| Preserved Values V1 Kali binary | `dff41c359c62bbc2108cd75643c829a00c40e8949a59f31aafb17940ee8812e4` |

Frozen source: `/tmp/mlir-nix-list-returns-v1-20261028.tar.gz`. Saved macOS binary:
`/tmp/mlnix-locality/mlnix-list-returns-v1`. The measured implementation and test files remain fixed.
All 1,886 archived regular files were verified byte-for-byte on Kali, then the complete isolated build
directory was cleaned and rebuilt. The saved candidate is `/tmp/kb/list-returns-20261028-v1/mlnix`;
the preserved Values V1 binary remains unchanged. [Archive verification](v1/verified-archive-files.sha256),
[clean log](v1/clean.log), [build log](v1/build.log) and [source hashes](v1/source.txt) are retained.
Kali ran the focused gate and workload measurements, without repeating the broad language suites.
The [final source parity check](../../local/list-returns-20261028/v1/final-source-parity.txt) verifies all
1,176 archived implementation/build/test files unchanged locally and all 13 protected incoming files
byte-identical to their original snapshot. The parked builtin-result allocation patch remains absent.

Full Kali workload SHA-256 values remain:

- NixOS: `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
- nixpkgs-73: `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`

## Remaining work

Lists with newly computed elements need durable lazy cells and environments, including interpreter-compatible
memoization after native fallback. General closure conversion, local deoptimization frames, broader scalar
subgraphs and projections, collection fusion and persistent machine-code caching remain unfinished.
