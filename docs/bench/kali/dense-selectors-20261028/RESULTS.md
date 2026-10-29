# Dense attributes and lazy native selectors, 28 October 2026

The retained default change reduces demand-mode peak memory by 5.3% on NixOS and 8.3% on nixpkgs-73.
Timing gains depend on the schedule; eager NixOS regressed in the layout comparison. The native tier
now executes real library code but remains opt-in: the final off/on comparison is +3.1% / -1.4% in
demand wall time, with slightly higher RSS. This is progress in memory use and native coverage, not
a completed general Nix compiler or a consistent JIT speedup.

This iteration follows the [first guarded integer tier](../locality-20261028/RESULTS.md).
It retains the lazy sea-of-nodes evaluator and adds two independently measurable changes:

- Attribute cells shrink from 24 to 16 bytes: a 32-bit symbol, a 32-bit position index and a value pointer.
  Cold positions live in a per-evaluator `MutableSeries`. Each evaluated source attribute operation reuses
  one contiguous range; copying or merging cells copies their indices. The MLIR positions property is
  unchanged, and runtime table indices never enter serialized IR.
- The opt-in native tier recognizes argument identities, captured-value identities and captured-Boolean
  choices between the argument and an empty set, list or string. One LLVM pointer-selection kernel serves
  those shapes. Captures resolve in the current closure, the host preserves demand order and positions,
  and empty collections retain fresh allocation. Every selected pointer is checked before forcing it;
  the first three successful calls per entry also receive shallow interpreter validation.

The compilation path is TrikeShed-backed source and deferred-body storage → lazy Nix graph regions →
bounded arithmetic plans or pointer recipes → typed MLIR → LLVM dialect → LLVM IR and native code.
General closure conversion, arbitrary branches, native attribute access and collection kernels remain
future work. See [JIT.md](../../../JIT.md) for eligibility, guards and inspectable IR.
The [saved pointer-kernel artifacts](../../local/dense-selectors-20261028/pointer-ir/) include typed MLIR,
LLVM-dialect MLIR, optimized LLVM IR and a checked eight-call execution with three grace comparisons.

## Measurement method

The host is Kali under WSL2 on an Intel i7-6820HK, using Clang/MLIR 22.1.8. The two repository workloads
remain NixOS toplevel and nixpkgs-73, with output hashes `2057239a9017` and `5e8fff662dff`.
Every A/B round checks successful exit and identical full output hashes before accepting timings.
Round order alternates A/B and B/A. Time includes process startup, compilation and grace checks.
RSS comes from each child's `wait4` record; A/B tables use decimal GB.

Two comparisons separate layout and execution: the preserved prior evaluator versus the new candidate
with JIT disabled in both, then JIT disabled versus enabled in the same candidate. Demand uses
`MLNIX_DEFER=1`; eager removes the variable entirely. Native thresholds stay at the default 1,024 calls.
Statistics and hardware-counter samples run separately from timing rounds.

Nix 2.35.4 and Lix 2.91.3 are historical comparison points from accepted same-host records.
**Neither reference executable was invoked in this iteration.** `--reuse-refs` validates saved output
hashes and fails if compatible reference records are missing. Cached comparisons cannot establish a
simultaneous speedup against either reference under the current host load.

## Dense attributes, JIT disabled

Five demand rounds and three eager rounds compare the preserved evaluator (A) with the dense-attribute
candidate (B), with JIT disabled throughout. Attribute storage is retained: RSS falls in both workloads
and schedules. Timing is schedule-dependent; eager NixOS regresses in this sample.

| Workload | Schedule | Prior median | Dense median | Wall change | CPU change | Prior / dense RSS median |
|---|---|---:|---:|---:|---:|---:|
| NixOS toplevel | demand | 4.002 s | 3.748 s | -6.3% | -10.5% | 1.392 / 1.318 GB |
| nixpkgs-73 | demand | 3.837 s | 3.669 s | -4.4% | -4.5% | 1.330 / 1.220 GB |
| NixOS toplevel | eager | 3.891 s | 4.151 s | +6.7% | +10.7% | 1.513 / 1.438 GB |
| nixpkgs-73 | eager | 3.891 s | 3.758 s | -3.4% | -4.5% | 1.458 / 1.348 GB |

Sources: [demand](ab-old-off-candidate-off-demand.txt), [eager](ab-old-off-candidate-off-eager.txt).
Demand RSS falls 5.3% and 8.3%; eager RSS falls 4.9% and 7.6%, respectively. RSS maxima are within
about 2 MB of the reported medians. The repeated allocation savings are clearer than a general timing
claim: the eager NixOS minimum also rises, by 2.2%, and different batches show noticeable timing drift.

During the demand comparison, the [host sample](metadata-during-demand.txt) recorded load 1.54,
about 5.4 GiB available and unused swap. Both unrelated resident Java processes used 0% CPU during
that one-second sample. This is a sample, not proof of an uncontended host throughout every run.

## Native coverage and initial dispatch cost

The first selector candidate, v1, has useful execution coverage but loses on end-to-end timing.
Five demand rounds and three eager rounds compare JIT off/on within that same binary:

| Workload | Schedule | Off median | On median | Wall change | Off / on RSS median |
|---|---|---:|---:|---:|---:|
| NixOS toplevel | demand | 4.031 s | 4.174 s | +3.6% | 1.319 / 1.327 GB |
| nixpkgs-73 | demand | 3.488 s | 3.735 s | +7.1% | 1.220 / 1.228 GB |
| NixOS toplevel | eager | 3.874 s | 4.330 s | +11.8% | 1.438 / 1.445 GB |
| nixpkgs-73 | eager | 3.719 s | 3.884 s | +4.4% | 1.348 / 1.356 GB |

Sources: [demand](ab-candidate-off-on-demand.txt), [eager](ab-candidate-off-on-eager.txt).
CPU changes are +2.7% / +10.5% in demand and +14.5% / +3.9% in eager. Native execution remains opt-in.

Untimed counters prove which paths ran, with the default threshold:

| Demand workload | Shared kernels | Native calls | Argument identities | Capture identities | Conditional selectors | Grace checks |
|---|---:|---:|---:|---:|---:|---:|
| NixOS toplevel | 1 | 348,730 | 211,636 | 9,046 | 128,048 | 36 |
| nixpkgs-73 | 1 | 367,815 | 122,890 | 11,799 | 233,126 | 30 |

Sources: [NixOS statistics](stats-nixos-toplevel.txt), [nixpkgs statistics](stats-nixpkgs-73.txt).
Both have zero mismatches, compiler failures and type misses. Candidate counts are 32 and 29,
below the 256-entry cap. The cold position vectors hold 143,365 and 104,540 rows, respectively,
with capacities of 2 MiB and 1 MiB; auxiliary lookup maps are additional storage.

The v2 follow-up keeps the same plans and kernels but bypasses JIT dispatch for a region already
classified as unsupported. Profiling deliberately retains dispatch so every call is counted. This
targets repeated dispatch into the rejected path without expanding speculative eligibility.

### Final candidate: bypass cached refusals

Five rotating demand rounds within v2 retain the same answers and show mixed native performance:

| Workload | JIT off median | JIT on median | Wall change | CPU change | Off / on RSS median |
|---|---:|---:|---:|---:|---:|
| NixOS toplevel | 3.996 s | 4.118 s | +3.1% | +3.9% | 1.318 / 1.327 GB |
| nixpkgs-73 | 3.764 s | 3.710 s | -1.4% | -0.2% | 1.220 / 1.228 GB |

Source: [v2 off/on](v2/ab-v2-off-on-demand.txt). RSS increases 0.6% and 0.7% with JIT enabled.
Three additional pairs isolate v1-on versus v2-on: NixOS wall 4.285 → 4.035 s (-5.8%), CPU -2.2%;
nixpkgs wall 3.778 → 3.700 s (-2.1%), CPU +5.4%.
[Those pairs](v2/ab-v1-on-v2-on-demand.txt) support retaining the cheaper rejection path, but the
mixed CPU results and the off/on comparison do not justify enabling the native tier by default.
No v2 eager timing or broad language-suite rerun was made; the dispatch-only change received targeted
validation described below.

## Hardware-counter samples

One separate pair per workload compares dense attributes with the prior layout, both with JIT off.
The counters cover inherited user-space threads/children and were running for 100% of their enabled time.

| Workload | Cycles | Instructions | Cache misses |
|---|---:|---:|---:|
| NixOS toplevel | +0.4% | +0.25% | -2.5% |
| nixpkgs-73 | +0.8% | +0.28% | +1.0% |

Raw pairs: [NixOS prior](pmu-dense-original-nixos-toplevel.json) /
[dense](pmu-dense-candidate-nixos-toplevel.json), [nixpkgs prior](pmu-dense-original-nixpkgs-73.json) /
[dense](pmu-dense-candidate-nixpkgs-73.json). These single samples do not establish a consistent cache-miss
or cycle improvement. The attribute-density and repeated RSS reductions are the supported memory result.

The separate v1 JIT off/on pairs show cycles +3.6% / +0.7%, instructions +1.37% / +0.63%, and cache
misses +11.7% / -6.3%. They likewise do not support a broad native-code speedup. Raw samples are
`pmu-off-*.json` and `pmu-on-*.json`; timing conclusions use the rotating rounds above.

One further [NixOS](v2/pmu-v2-on-nixos-toplevel.json) and
[nixpkgs](v2/pmu-v2-on-nixpkgs-73.json) pair compared v2-on with v1-on. Cycles fell 2.10% / 1.99%,
instructions 1.41% / 1.16%, and cache misses 1.86% / 1.54%, with 100% counter running time.
These are single samples of the dispatch change, not evidence that JIT beats interpretation.

## Cached Nix and Lix references

The accepted records come from generations [04](../04-20b5ad596/), [05](../05-f2c37f51b/), and
[06](../06-aea88bf65/), with the same workload output hashes. Minimum and median are each the best of
those generations; RSS is from the latest one. Reference RSS uses MiB, unlike the decimal-GB A/B tables.

| Workload | Reference | Cached minimum | Cached median | Cached peak RSS |
|---|---|---:|---:|---:|
| NixOS toplevel | Nix 2.35.4 | 3.70 s | 4.10 s | 628 MiB |
| NixOS toplevel | Lix 2.91.3 | 4.42 s | 4.65 s | 755 MiB |
| nixpkgs-73 | Nix 2.35.4 | 3.46 s | 3.85 s | 609 MiB |
| nixpkgs-73 | Lix 2.91.3 | 4.31 s | 4.53 s | 757 MiB |

For a side-by-side view, final candidate medians from its five paired demand rounds are:

| Workload | Current JIT off | Current JIT on | Cached Nix | Cached Lix |
|---|---:|---:|---:|---:|
| NixOS toplevel | 3.996 s | 4.118 s | 4.10 s | 4.65 s |
| nixpkgs-73 | 3.764 s | 3.710 s | 3.85 s | 4.53 s |

Only the two current-candidate columns were measured together. The reference columns are reused
historical measurements; small differences from them are not a controlled comparative win.

The [v1 cached-reference presentation](cached-references.txt) used deliberately nonexistent reference
binary paths with `--reuse-refs`; it successfully reused the records without invoking either tool.
Its additional candidate timings have JIT enabled. They are a separate batch, not substitutes for
the paired layout or JIT ablations above. Even with dense attributes, the evaluator still uses roughly
twice Nix's peak memory on these workloads.

## Correctness

The v1 candidate on both macOS/LLVM 23 and Kali/LLVM 22 passes 477/477 language cases semantically in
all four configurations: JIT off/on, eager/demand. Full-suite JIT runs use threshold 1 on macOS and
the default 1,024 on Kali. Exact matches against the suite's stored expectations are 219/477; existing
diagnostic differences remain. The focused native gate passes 90 exact status/stdout/stderr comparisons,
including native-execution counters, overflow, lazy errors/traces, changing captures, shared values,
string contexts, grace, reentrancy and compiler/candidate limits.

On macOS, all 1,428 saved output/error/status files for the 476 common prior-evaluator cases (eager) are
byte-identical after the layout change. All 1,431 files for the new 477-case suite also match between
JIT off/on in each schedule. [Local validation](../../local/dense-selectors-20261028/validation-summary.txt)
records those comparisons. The restored attribute-position fixture covers 17 construction/copy routes.
MLIR tests pass 15/15 on macOS and 14/14 on Kali, with four dynamic-CSE run lines skipped on LLVM 22.
Primop declarations remain 105 registered and 105 declared.
The v2 dispatch-only follow-up repeats the 90 exact native/interpreter comparisons on both hosts,
including eager/demand and threshold 1, and validates unchanged hashes on both real workloads.

## Provenance

The prior evaluator is the preserved first-tier result, including the user's initial TrikeShed changes,
not merely the Git HEAD. Neither that binary nor its source archive was overwritten.

| Snapshot | SHA-256 |
|---|---|
| Prior Kali evaluator | `2ac530d5f222b72134ed1b12f04a49b23473d7bb88667ff3a2e09f1872d7e279` |
| Prior source archive | `b23d1a0c11399ceb676b84b54dfe08eecbe7e9ac6b38a131274b43556ead91af` |
| Dense-attribute/selector source archive | `e2afe79429746e202b1adf2ae3acdb0837bea7d55a3d032fd9c97199ccbd254e` |
| v1 Kali candidate evaluator | `d5c0dde23088bce99d5f728896ba9e45d83ad790c29957bc7673e9094b96bbc6` |
| macOS candidate evaluator | `01e4875524af2eb3c15fe2fb90769b807b410ca0ed06ae122ae05d09db2d448b` |
| v2 source archive | `c94bf32b27b2e21e3434ae8bda2af1786493133228f4011d1f6ebac8b7aed415` |
| v2 Kali evaluator | `ef85d2ef489348f7f8aeaf9c3e042aa3159f418745c9cb5af10d92b837ebcbad` |
| v2 macOS evaluator | `9ae259db90ff8c559409972ad0406898d7fa02150318d6c4b236a834d91c7402` |

Each source archive was frozen before its Kali build and measurements. Subsequent documentation edits do
not change the measured evaluator. The 13 files containing the user's incoming TrikeShed changes were
also checked byte-for-byte against the original source archive and remain unchanged.
The [command manifest](commands.txt) and retained launchers record environment settings, workload
commands, cached-reference arguments and PMU inheritance. In particular, the PMU JSON command arrays
do not show the launcher's inherited `MLNIX_JIT`; the named arm and launcher record that setting.
