# Persistent value returns and empty recipes, 28 October 2026

Values V1 lets guarded lazy graphs return existing values and fresh empty sets, lists and strings. Against
the same binary with this extension disabled, it removes 160,781 / 333,549 frame allocations and 33,443 /
283,512 Value allocations on NixOS / nixpkgs-73, saving 5,467,992 / 14,800,312 requested bytes. Five paired
rounds show peak RSS falling 0.3% / 1.2%, while median wall time changes +0.2% / +1.7%. Whole-JIT-off/on
wall time rises 5.9% / 6.2%. Native execution remains opt-in; allocation savings have not delivered a
throughput improvement.

## Implemented scope

A tail argument, capture or supported one-key projection can return its existing persistent cell after
forcing only the outer value. Lists, sets, strings with contexts, paths, closures and primops retain their
original payload and environment. Elements and fields remain lazy. A reached empty set, list or literal
string returns a bounded construction recipe instead. The trusted host creates the fresh result only
after native execution has left every inline call scope. Current closure captures, logical call depth,
Select component order and source positions remain checked.

Tail `if` arms and guarded calls propagate the value continuation. Conditions and Boolean operators keep
their strict Boolean contract. Native status `6` is reached through the required Leave chain; it is not
a resumable continuation. The host validates root context, zero relative depth and a per-plan allowlist
of return cells or empty recipes. Native code and the post-oracle observer do not allocate result containers.
Grace compares shallow payload identity or an empty recipe without deep forcing, then returns the oracle's
answer. Invocation alias checks and active-run pinning protect interpreter state and executable lifetime.

`MLNIX_JIT_VALUES=0` restores Boolean-only result construction while retaining the prior projection,
inline and saturated-call support. It is read when a plan is created, outside hot execution. Existing node, leaf, continuation,
inline-depth, resume, candidate and compiler limits remain in force. Nonempty constructors, new local memo
cells and escaping local closures remain unsupported. [JIT.md](../../../JIT.md) and
[JIT-CALLS.md](../../../JIT-CALLS.md) document the protocol.

## Coverage and allocation evidence

Untimed demand profiles use the default threshold of 1,024 calls. All six outputs, including JIT-off controls,
match the saved Kali goldens. [Three-arm profiles](v1/profile-summary.json) and
[VALUES-off/on deltas](v1/profile-deltas.json) retain exact counters.
With VALUES=0, all 55 prior JIT aggregate keys match the saved Projection V1 profile except the elapsed
`compile_ns` sample. All new value/empty counters are zero in that control.

| Measurement, VALUES off → on | NixOS | nixpkgs-73 |
|---|---:|---:|
| Total compiled engines | 16 → 16 | 14 → 16 |
| Engines with value-return continuations | 0 → 10 | 0 → 6 |
| Value-return completions | 0 → 227,199 | 0 → 290,291 |
| Included empty-recipe completions | 0 → 62,724 | 0 → 231,429 |
| All lazy-graph completions | 119,951 → 329,354 | 209,155 → 492,101 |
| All lazy-graph fallbacks | 8,882 → 7,460 | 7,692 → 19,293 |
| Curried fallbacks | 2,110 → 139 | 1,482 → 17,137 |
| Lazy-graph native invocations | 323,464 → 786,660 | 604,679 → 1,196,516 |
| Frame allocations | 4,773,413 → 4,612,632 | 2,815,109 → 2,481,560 |
| Value allocations | 14,338,502 → 14,305,059 | 11,560,659 → 11,277,147 |
| Compiler elapsed time, diagnostic sample | 130.0 → 130.0 ms | 112.7 → 122.6 ms |

All mismatch and compiler-failure counts are zero. Historical `boolean_*` aggregate names now include the
general value paths. Value completions include Boolean cells and 30 / 18 grace completions; empty and
curried completions are subsets, not additional work. Pointer-selector executions fall by 82,065 / 232,903
because the new routes replace existing native selector calls. These counts must not be added as independent
savings. Actual frame requests fall 3.37% / 11.85%; Value requests fall 0.23% / 2.45%. Requested frame bytes
fall 4,665,360 / 7,996,024 and Value bytes 802,632 / 6,804,288. These exclude allocator overhead and retained
pages and are distinct from RSS.

The first local experiment returned persistent cells but lacked empty recipes. Its new `optionalAttrs`
plan fell back frequently on the empty-set arm. The final implementation covers both arms of that shape,
and the admitted `optionals` and `optionalString` shapes, before any Kali measurement. The preserved
[initial analysis](../../local/values-20261028/initial-persistent/profile-analysis.txt) and
[final analysis](../../local/values-20261028/v1/profile-analysis.txt) explain the change. The initial candidate
was never built or timed on Kali.

The remaining `optional = cond: elem: if cond then [elem] else []` plan supports only its empty arm.
Its curried package-workload entry records 51,633 completions and 17,137 fallbacks. Interspersed successes
prevent consecutive-miss retirement from bounding this total cost. The inner unary entry adds 65 fallbacks.
Callback guard misses remain 134 / 232, so broader callback specialization does not explain this hotspot.
Both final workloads exhaust the 16-attempt compilation budget. Changed coverage is consistent with
admission/budget displacement of previously productive plans; per-entry refusal causes and compilation order
are not logged. Profiles print only the 60 highest-call rows, so residual counts are not
attributed to unseen locations. More coverage and fewer allocations do not imply less dispatch work:
native invocations and host demands rise substantially.

## Paired Kali measurements

Kali under WSL2, Intel i7-6820HK, Clang/MLIR 22.1.8. All timing runs use demand mode, rotating A/B order,
successful child exits and identical full output hashes. Stats and profiling are absent. Time includes
startup, specialization, compilation and grace. RSS is decimal GB. The [manifest](v1/commands.txt) and
[launcher](v1/commands-v1.sh) record exact settings.

Five pairs compare VALUES disabled/enabled, with JIT enabled in both:

| Workload | VALUES off median | VALUES on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.934 s | 3.940 s | +0.2% | −0.6% | 1.323 / 1.319 GB |
| nixpkgs-73 | 3.466 s | 3.524 s | +1.7% | +2.4% | 1.222 / 1.208 GB |

[Value-return ablation](v1/ab-values-off-on-demand.txt). Separate five-pair whole-JIT comparisons:

| Workload | JIT off median | JIT on median | Wall change | CPU change | RSS off / on |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.712 s | 3.930 s | +5.9% | +4.9% | 1.318 / 1.319 GB |
| nixpkgs-73 | 3.296 s | 3.502 s | +6.2% | +7.5% | 1.220 / 1.208 GB |

[Whole-JIT ablation](v1/ab-jit-off-on-demand.txt). Unrounded whole-JIT RSS changes are +0.0% / −1.0%.
Arms from separate series are not paired comparisons and must not be combined into a speedup estimate.

Three pairs compare the preserved Projection V1 binary with Values V1, with JIT enabled in both:

| Workload | Projection V1 median | Values V1 median | Wall change | CPU change | RSS prior / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.946 s | 3.952 s | +0.1% | −0.2% | 1.318 / 1.319 GB |
| nixpkgs-73 | 3.460 s | 3.488 s | +0.8% | −1.1% | 1.218 / 1.208 GB |

[Preserved-binary comparison](v1/ab-projection-v1-candidate-jit-on-demand.txt). Separate three-pair controls
disable JIT in both binaries:

| Workload | Projection V1 median | Values V1 median | Wall change | CPU change | RSS prior / candidate |
|---|---:|---:|---:|---:|---:|
| NixOS | 3.666 s | 3.702 s | +1.0% | +2.8% | 1.316 / 1.318 GB |
| nixpkgs-73 | 3.308 s | 3.302 s | −0.2% | −1.6% | 1.217 / 1.220 GB |

[Default-path controls](v1/ab-projection-v1-candidate-jit-off-demand.txt). These controls are small and mixed;
subtracting their changes from a separate JIT series would not isolate the extension's cost. The within-binary
VALUES ablation is the direct feature comparison. No new reference-tool processes were involved.

The benchmark lock serialized the job. Eight host snapshots cover before-build, before profiles, every
timing/PMU series and completion. All show zero swap and no Java, mlnix or build process at those boundaries.
Available memory stays between 14,489 and 14,627 MiB. One-minute load is 0.13 before the build, 1.97 after
build/checks, 1.16–1.64 before the timed/PMU series and 1.18 at completion. See
[start](v1/host-00-before-build.txt), [first timing boundary](v1/host-02-before-values-ablation.txt) and
[completion](v1/host-07-complete.txt); all eight snapshots are retained alongside the logs. These are boundary
observations, not continuous host monitoring. No external process was changed.

## Separate hardware counters

One VALUES-off/on pair per workload uses JIT enabled in both, separately from timing series. Counters cover
inherited user-space threads/children; all events ran for 100% of enabled time.

| Workload, VALUES on versus off | Cycles | Instructions | Cache misses | Branch misses |
|---|---:|---:|---:|---:|
| NixOS | −0.02% | −0.06% | −0.89% | −1.51% |
| nixpkgs-73 | +0.56% | +0.35% | −0.57% | +0.46% |

These small changes from single pairs do not establish a cache-locality improvement. Raw
[NixOS off](v1/pmu-values-off-nixos-toplevel.json) / [on](v1/pmu-values-on-nixos-toplevel.json) and
[nixpkgs off](v1/pmu-values-off-nixpkgs-73.json) / [on](v1/pmu-values-on-nixpkgs-73.json) are retained.
The launcher records inherited JIT/VALUES settings omitted from the PMU JSON child command arrays.

## Cached Nix and Lix references

Accepted same-host records from generations [04](../04-20b5ad596/), [05](../05-f2c37f51b/) and
[06](../06-aea88bf65/) are reused. Competitor medians below are the best accepted historical medians across
those generations; RSS uses the latest accepted record. Host conditions differ, so these are historical
comparisons rather than controlled competitor speedup claims.

| Workload | Candidate JIT off | Candidate JIT on | Cached Nix 2.35.4 | Cached Lix 2.91.3 |
|---|---:|---:|---:|---:|
| NixOS | 3.712 s | 3.930 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.296 s | 3.502 s | 3.85 s | 4.53 s |

Cached minima are Nix 3.70 / 3.46 s and Lix 4.42 / 4.31 s. Cached RSS is Nix 628 / 609 MiB and Lix 755 /
757 MiB. mlnix still uses substantially more peak memory. No reference evaluation, startup, version query
or RSS measurement was invoked.

## Validation and provenance

The final candidate passes [472 exact comparisons on Kali](v1/check-jit.txt) and
[macOS](../../local/values-20261028/v1/check-jit.txt), including 33 persistent-value and 13 empty-recipe cases
plus ablations. Separate counters prove native execution beyond grace. Tests cover strict Boolean contexts,
lazy fields and elements, current captures, returned closures, strings with contexts, dynamic projections,
nested Leave/depth restoration, memoized fallback, recursive retirement and bounded resources.

Both full macOS schedules pass 482/482 semantic cases with 224 stored exact expectations. All 1,443 prior
output/error/status files per schedule remain byte-identical; the new fixture returns true without stderr.
[Validation](../../local/values-20261028/v1/validation-summary.txt) and
[suite parity](../../local/values-20261028/v1/suite-parity.txt) retain the evidence. Kali did not rerun the broad
language suites. The [IR example](../../local/values-20261028/ir-v1/README.txt) maps a selected persistent value
and empty-list recipe through two native Leave scopes, typed MLIR and optimized LLVM. Its output and
exactly-once trace match the preserved interpreter oracle.

| Snapshot | SHA-256 |
|---|---|
| Values V1 source, 1,296,899 bytes | `3d54905419b293a778a4c91a26d6b8d01b729906c634f68822b1b5cf69b5d1c5` |
| Values V1 macOS binary | `2b2f4d6b25927e4138662cc05104b2673271df845bec350ea572704dda2324e0` |
| Values V1 Kali binary | `dff41c359c62bbc2108cd75643c829a00c40e8949a59f31aafb17940ee8812e4` |
| Preserved Projection V1 Kali binary | `0e66ac30093a2d044cdbdf2c72f93d65eea0e4e9e20b3592d3f2ab01eb3ca466` |

The frozen source is `/tmp/mlir-nix-values-v1-20261028.tar.gz`; the preserved Kali candidate is
`/tmp/kb/values-20261028-v1/mlnix`. All 1,791 archived regular files were verified byte-for-byte, then the
entire isolated build directory was cleaned and rebuilt. The prior binary was preserved unchanged.
[Archive verification](v1/verified-archive-files.sha256), [clean log](v1/clean.log),
[build log](v1/build.log) and [source hashes](v1/source.txt) are retained. The final
[source parity check](../../local/values-20261028/v1/final-source-parity.txt) verifies that all 1,174 archived code/build/test
files still match locally and 13 incoming user files match their original snapshot. The parked builtin-result
allocation patch remains absent.

Full Kali workload SHA-256 values remain:

- NixOS: `2057239a9017fb18a37976ec6c96ad31ee36847cfa2107f146d4fac427f0cd86`
- nixpkgs-73: `5e8fff662dffa4eab642b75e78028fb54204cd15ec1a9972c2cafe2306234959`

macOS retains its preexisting distinct NixOS golden, reproduced by the preserved Projection V1 interpreter.
It did not replace the Kali oracle.

## Remaining work

A bounded lazy list recipe could cover `optional` if it retains durable element handles without forcing
them and preserves fresh-list construction and nonforcing grace. Local computed elements require durable
memo/deoptimization frames first. Profitability admission, fewer host resumptions, general closure conversion,
broader projections, collection fusion and persistent machine-code caching remain unfinished.
