# Lazy projections and saturated inline calls, 28 October 2026

V1 compiles lazy one-key attribute projections and guarded calls supplying one to four arguments. It removes
17,253 / 28,701 frame allocations and 8,430 / 21,368 Value allocations on NixOS / nixpkgs-73 against the same
binary with projection disabled. That saves 985,712 / 1,786,864 requested bytes. Timing is mixed: projection-off/on
changes wall time by −1.0% / +2.5%, and whole-JIT-off/on by +1.2% / +2.0%. Native execution remains opt-in.
These allocation savings do not establish a cache-locality or peak-memory improvement.

## Implemented scope

A Select with one static or dynamic key and no default can supply a virtual argument. Its base and dynamic key
must be actual persistent cells, including after formal substitution. Passing the argument does not force it.
A reached consumer requests key, base and field in that order; the host preserves Select positions and the
consuming predicate's builtin error wrapper. Successful component forces remain memoized across fallback.
Flat and layered lookup uses the existing read-only lookup, without flattening or forcing unused fields.

Inline Apply expansion now accepts one to four arguments when already-indexed bodies form a direct unary-lambda
chain. The reached outer lambda and current closure environment are guarded before any argument demand. Chain
stages share their original sequential call depth; nested calls still add depth. No temporary interpreter frame
or projection thunk is published. Defaults, multiple path components, nested virtual bases/keys, projected
callees and arbitrary local/escaping values remain outside this scope.

The interpreter and projection host share `selectField` for base checks and missing-attribute errors. Preflight
and native grace only peek existing cells; dynamic-name observation uses `symbols.map.find`, never interning.
Existing graph, leaf, continuation, inline-depth, resume, candidate and compiler limits remain in force, with
projection recipes counted in the shared budgets. [JIT.md](../../../JIT.md) and
[JIT-CALLS.md](../../../JIT-CALLS.md) describe the protocol and exclusions.

`MLNIX_JIT_PROJECTION=0` disables virtual Select acceptance, leaving multi-argument inline expansion enabled.
`MLNIX_JIT_INLINE=0` disables Apply expansion; `MLNIX_JIT_CURRIED=0` independently disables saturated entry hooks.
All remain inside the opt-in `MLNIX_JIT=1` tier.

## Coverage and allocation evidence

Untimed demand-mode profiles use the default threshold of 1,024 calls. All four outputs match the unchanged
Kali goldens. The full [profile deltas](v1/profile-deltas.json) and
[off](v1/profile-projection-off-nixos-toplevel.txt) / [on](v1/profile-projection-on-nixos-toplevel.txt) NixOS and
[off](v1/profile-projection-off-nixpkgs-73.txt) / [on](v1/profile-projection-on-nixpkgs-73.txt) nixpkgs logs are saved.

| Measurement, projection off → on | NixOS | nixpkgs-73 |
|---|---:|---:|
| Total compiled engines | 12 → 16 | 9 → 14 |
| Engines containing a projection | 0 → 6 | 0 → 5 |
| Projection requests | 0 → 28,689 | 0 → 33,296 |
| Actual projection component forces | 0 → 29,769 | 0 → 10,019 |
| `filterAttrs` callback completions | 0 → 9,130 | 0 → 20,350 |
| All Boolean completions | 111,116 → 119,951 | 201,807 → 209,155 |
| All Boolean fallbacks | 578 → 8,882 | 1,859 → 7,692 |
| Native invocations | 277,566 → 323,464 | 552,451 → 604,679 |
| Frame allocations | 4,790,666 → 4,773,413 | 2,843,810 → 2,815,109 |
| Value allocations | 14,346,932 → 14,338,502 | 11,582,027 → 11,560,659 |
| Compiler elapsed time, diagnostic sample | 118.0 → 156.3 ms | 72.2 → 129.7 ms |

Every measured projection lookup is flat. Layered and cached-flat behavior passes targeted tests, but these
workloads do not supply measured evidence of that path's speed. There are zero mismatches or compiler failures.
The projection-deopt counter is zero because it counts unavailable observe-only projection peeks; it does not
count every fallback in a surrounding graph. Each request can force key, base and field, so force actions can
exceed requests. These counters omit throwing runs and the separate C++ preflight observer.

The `filterAttrs` callback is only partially covered: 9,130 of 70,968 calls and 20,350 of 168,382. Its new inline
execution largely replaces existing curried execution in `systems/default.nix:46`: those curried completions
fall by 9,127 / 20,347, exactly the new callback completions less three grace calls. These counts must not be
added as independent savings. Actual frame counts fall 0.36% / 1.01%, and Value counts 0.06% / 0.18%.
Requested frame bytes fall 783,392 / 1,274,032 and Value bytes 202,320 / 512,832; arena overhead and retained
pages are excluded. Requested bytes are not RSS.

Profiles expose costs as well as coverage. The `modules.nix:802` predicate can complete when `_type` is absent,
but reaches unsupported equality/error logic when present: NixOS records 6,768 completions and 5,995 fallbacks.
The bare `_: v: v.value` result at `modules.nix:273` enters a Boolean-only result tier and correctly falls back
for non-Booleans: 1,857 completions / 2,110 fallbacks on NixOS and 1,024 / 1,482 on nixpkgs. Callback guard misses
are only 134 / 232. These sources explain most extra NixOS fallbacks; truncated per-location profiling does not
justify attributing every residual. [Local analysis](../../local/projection-20261028/v1/profile-analysis.txt)
records the source evidence, aggregate counters and truncation limits.

One successful post-oracle observation currently admits compilation, while retirement requires 64 consecutive
fallbacks. Interspersed successes keep low-yield kernels alive. NixOS reaches the global 16-attempt cap; loss of
a previously productive kernel is consistent with budget displacement, although refusal reasons are not logged.
Compiler elapsed samples include setup/emission/lowering/native generation, exclude analysis and oracle work,
and cannot be subtracted from timing results as a causal explanation.

## Paired Kali measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. All runs use demand mode, rotating A/B order, successful
child exits and identical full output hashes. Stats and profiling are absent from timings. Time includes
startup, specialization, compilation and grace. RSS is decimal GB. Exact commands are in the
[manifest](v1/commands.txt) and [clean-build launcher](v1/commands-clean-v1.sh).

Five pairs compare projection disabled/enabled with JIT enabled in both:

| Workload | Projection off median | Projection on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.218 s | 4.176 s | −1.0% | −1.5% | 1.327 / 1.323 GB |
| nixpkgs-73 | 3.622 s | 3.712 s | +2.5% | +2.5% | 1.221 / 1.222 GB |

[Projection ablation log](v1/ab-projection-off-on-demand.txt).

Five separate pairs compare the whole JIT disabled/enabled:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.062 s | 4.110 s | +1.2% | +0.5% | 1.318 / 1.323 GB |
| nixpkgs-73 | 3.582 s | 3.655 s | +2.0% | +2.2% | 1.220 / 1.222 GB |

[Whole-JIT ablation log](v1/ab-jit-off-on-demand.txt).

These series do not justify enabling native execution by default. Arms from separate series are not paired
comparisons and must not be combined into a speedup estimate.

Three pairs compare preserved dispatch V2 with the candidate, with JIT enabled in both:

| Workload | Dispatch V2 median | Candidate median | Wall change | CPU change | RSS V2 / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.175 s | 4.179 s | +0.1% | +0.1% | 1.323 / 1.324 GB |
| nixpkgs-73 | 3.568 s | 3.734 s | +4.6% | +6.2% | 1.216 / 1.222 GB |

[Candidate comparison](v1/ab-dispatch-v2-candidate-jit-on-demand.txt). Separate three-pair controls disable JIT in both:

| Workload | Dispatch V2 median | Candidate median | Wall change | CPU change | RSS V2 / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 4.198 s | 3.859 s | −8.1% | −8.2% | 1.316 / 1.318 GB |
| nixpkgs-73 | 3.650 s | 3.594 s | −1.5% | +0.6% | 1.217 / 1.220 GB |

[Default-path controls](v1/ab-dispatch-v2-candidate-jit-off-demand.txt). These controls vary substantially:
NixOS minima are 3.931 → 3.834 s; nixpkgs minima are 3.325 → 3.456 s despite its lower candidate median.
The shared selection helper's isolated cost is not established. The within-binary projection ablation is the
more direct feature comparison; neither control-series subtraction nor instruction-shape inference identifies
a cause for the cross-binary timing differences.

The benchmark lock serialized the job, and no competing mlnix build/benchmark was present at launch. Unrelated
host processes were left untouched. Available memory changed materially, from 8,677 to 14,599 MiB; unrelated
Java daemons present before the job were absent afterward. Their exit time was not recorded. One-minute load
changed 0.14 → 1.22, with no swap used. [Start](v1/metadata-start.txt) and [end](v1/metadata-end.txt) metadata
therefore limit causal interpretation; endpoint readings cannot establish conditions during each pair.

## Separate hardware counters

One projection-off/on PMU pair per workload uses JIT enabled in both, separately from the timing series.
Counters cover inherited user-space threads/children; every event ran for 100% of enabled time.

| Workload | Cycles | Instructions | Cache misses | Branch misses |
|---|---:|---:|---:|---:|
| NixOS, projection on versus off | +1.23% | +0.63% | +1.69% | +1.96% |
| nixpkgs-73, projection on versus off | +2.53% | +1.09% | +5.32% | +1.76% |

These single pairs do not establish a robust cache penalty or locality improvement. Raw
[NixOS off](v1/pmu-projection-off-nixos-toplevel.json) / [on](v1/pmu-projection-on-nixos-toplevel.json) and
[nixpkgs off](v1/pmu-projection-off-nixpkgs-73.json) / [on](v1/pmu-projection-on-nixpkgs-73.json) are retained.
The launcher records the inherited JIT/projection settings omitted from the PMU JSON's child command array.

## Cached Nix and Lix references

Accepted same-host records from generations [04](../04-20b5ad596/), [05](../05-f2c37f51b/) and
[06](../06-aea88bf65/) are reused. Competitor medians below are the best accepted historical medians across
those generations; RSS uses the latest accepted record. They were collected under different host conditions,
so this is historical context, not a controlled competitor speedup claim.

| Workload | Candidate JIT off | Candidate JIT on | Cached Nix 2.35.4 | Cached Lix 2.91.3 |
|---|---:|---:|---:|---:|
| NixOS | 4.062 s | 4.110 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.582 s | 3.655 s | 3.85 s | 4.53 s |

Cached minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s. Cached RSS is Nix 628 / 609 MiB and Lix 755 / 757 MiB.
mlnix still uses substantially more peak memory. No reference evaluation, startup, version query or RSS
measurement was invoked.

## Validation and provenance

The candidate passes [370 exact checks on Kali](v1/check-jit.txt) and
[macOS](../../local/projection-20261028/v1/check-jit.txt), with separate native-execution, demand, grace,
fallback, depth and resource-limit assertions. The 33 new cases include ignored projected arguments, dynamic
key/base/field ordering, current closure captures, layered/cached-flat shadowing, predicate and ordinary
consumer errors, non-Boolean tail fallback, recursive retirement and independent ablations.

Both macOS full schedules pass 481/481 semantic cases and 223 stored exact expectations; all 1,440 prior
output/error/status files per schedule are byte-identical. The new fixture returns true without stderr.
[Local validation](../../local/projection-20261028/v1/validation-summary.txt) preserves manifests and commands.
Kali did not rerun the broad language suites. The [IR example](../../local/projection-20261028/ir-v1/README.txt)
shows the projection recipe, typed MLIR and LLVM with current captures and exactly-once traces.

| Snapshot | SHA-256 |
|---|---|
| Projection V1 source, 938,097 bytes | `7b3187487ba5658fc24cbc1ed8e7ed73bed30f5da3b0af401f8948f57a9663db` |
| Projection V1 macOS binary | `24fcd57d7ed1016085fadfd1ccf5beca466cef683ac499d1f77a6a7ef212c38b` |
| Projection V1 Kali binary | `0e66ac30093a2d044cdbdf2c72f93d65eea0e4e9e20b3592d3f2ab01eb3ca466` |
| Preserved dispatch V2 Kali binary | `de551d73456085ea01fe1770d6011ceb99106b0d077ed9d5be2750fe4c6465ae` |

The frozen source is `/tmp/mlir-nix-projection-v1-20261028.tar.gz`; the preserved Kali candidate is
`/tmp/kb/projection-20261028-v1/mlnix`. The first incremental link exposed a stale object because archived
source timestamps predated it. All 1,656 archived regular files were verified byte-for-byte, then the entire
isolated build directory was cleaned and rebuilt. No tests or measurements used the stale build.
[Cache-invalidation evidence](v1/cache-invalidation.txt), both build logs and the exact retry launcher are retained.
The parked builtin-result allocation patch is absent; incoming user files are preserved.

Full Kali workload SHA-256 values remain:

- NixOS: `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
- nixpkgs-73: `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`

The macOS NixOS output differs from the saved Kali output, but preserved dispatch V2 and the current
interpreter both reproduce that existing local result. It did not replace the Kali oracle.

## Next constraints

Prioritize profitable admission and a general value-return path for bare projections. Wider callback
polymorphism has less observed opportunity than repeated unsupported-branch and non-Boolean fallbacks.
Retirement and admission changes must remain nonforcing and preserve reentrant code lifetime. The shared
selection helper also adds an out-of-line call in the local arm64 interpreter
([assembly evidence](../../local/projection-20261028/v1/select-helper-assembly.txt)); the separate Kali controls
do not isolate its cost. General closure conversion, escaping
local memo cells, broader projection paths and collection fusion remain unfinished.
