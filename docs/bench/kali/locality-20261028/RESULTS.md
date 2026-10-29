# Kali measurements, 28 October 2026

This report records the first integer-only tier. The subsequent [dense-attribute and lazy-selector iteration](../dense-selectors-20261028/RESULTS.md)
adds real workload native coverage and measured memory savings; the results below remain evidence for the earlier binaries.

The retained change is an opt-in, guarded integer JIT and corrected MLIR speculation contracts.
It does **not demonstrate a JIT speedup on either real workload**: both compiled zero kernels at the
default threshold. A generated million-call arithmetic workload did benefit, including compilation:
median wall time fell from 0.574 s to 0.205 s, and peak RSS from 0.290 GB to 0.196 GB.
The inline-list representation experiment was rejected and reverted.

These measurements use the repository's NixOS toplevel and 73-package nixpkgs workloads on Kali under WSL2,
with an Intel i7-6820HK (four cores, eight threads), Clang/MLIR 22.1.8, Nix 2.35.4 and Lix 2.91.3.
The workloads retain the output hashes `2057239a9017` and `5e8fff662dff`, respectively. The saved logs are
the evidence for the numbers below; faster failed or different evaluations are rejected.

Direct A/B runs alternate the two evaluators within a round and rotate which goes first. Wall and CPU
times are whole-process measurements; RSS is obtained from that child's `wait4` record. The A/B logs
use decimal GB, whereas the reference tables' historical "MB" column is MiB. Eager means `MLNIX_DEFER`
is absent; demand means `MLNIX_DEFER=1`. Setting it to `0` would still enable demand.

## Final evaluator: real workloads

Three interleaved runs per arm used the same final binary, with JIT disabled (A) and enabled (B).
The threshold was the default 1,024 eligible integer calls. All timed result hashes matched.

| Workload | Schedule | JIT off median | JIT on median | Wall change | Off / on peak RSS |
|---|---|---:|---:|---:|---:|
| NixOS toplevel | eager | 4.891 s | 6.083 s | +24.4% | 1.516 / 1.516 GB |
| nixpkgs-73 | eager | 4.608 s | 4.735 s | +2.8% | 1.462 / 1.463 GB |
| NixOS toplevel | demand | 3.957 s | 4.057 s | +2.5% | 1.395 / 1.397 GB |
| nixpkgs-73 | demand | 3.875 s | 3.826 s | -1.3% | 1.333 / 1.331 GB |

Sources: [eager off/on](final/ab-jit-off-on-eager.txt), [demand off/on](final/ab-jit-off-on-demand.txt).
These final timings are exploratory: unrelated work contended for the host during the run.
The [host sample](final/host-during-bench.txt) records a Java process using 276% CPU and a load average
of 2.92. The NixOS eager minima were much closer than its medians, 4.208 s off and 4.269 s on.
The sample size and changing load do not establish an improvement or a stable regression magnitude.

Untimed [NixOS statistics](final/jit-stats-nixos-toplevel.txt) and
[nixpkgs statistics](final/jit-stats-nixpkgs-73.txt) explain the limit directly:

| Demand workload | Compiled kernels | Native executions | Rejected plans | Calls without an already-forced integer argument |
|---|---:|---:|---:|---:|
| NixOS toplevel | 0 | 0 | 9 | 5,206,625 |
| nixpkgs-73 | 0 | 0 | 5 | 3,711,305 |

The native tier covers bounded, capture-free integer arithmetic graphs. It does not compile branches,
attribute access, collection operations or arbitrary Nix functions. Enabling it here adds dispatch and
eligibility checks without executing native kernels. A single separate PMU pair per workload is saved
in `final/pmu-*.json`; it is insufficient to establish a cache-locality improvement. The JIT remains opt-in.

A separate three-round A/B compared the original preserved evaluator with the final evaluator with
JIT disabled. It must not be conflated with the same-binary off/on experiment above:

| Workload | Schedule | Incoming median | Final, JIT off median | Wall change |
|---|---|---:|---:|---:|
| NixOS toplevel | eager | 5.722 s | 5.278 s | -7.7% |
| nixpkgs-73 | eager | 4.820 s | 4.623 s | -4.1% |
| NixOS toplevel | demand | 6.227 s | 6.562 s | +5.4% |
| nixpkgs-73 | demand | 3.898 s | 3.856 s | -1.1% |

Sources: [eager incoming/final](final/ab-original-jit-off-eager.txt),
[demand incoming/final](final/ab-original-jit-off-demand.txt). All outputs matched; RSS medians changed
by about +0.1%. Changing host contention prevents a claim that the default evaluator became faster.

## Scalar compilation payback

[The generated scalar sweep](final/scalar-payback.txt) uses
`builtins.foldl' builtins.add 0 (builtins.genList (x: ((x * 3) - 1) + 7) N)`.
Every timed answer must match the independent sum `3*N*(N-1)/2 + 6*N`. The three rotating rounds
measure the complete process, including startup, compilation and the three interpreter grace checks.
The same host-contention limitation applies.

| Calls | Interpreter median | JIT median | JIT / interpreter | Interpreter peak RSS | JIT peak RSS |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 0.035 s | 0.033 s | 0.931× | 0.068 GB | 0.070 GB |
| 100,000 | 0.078 s | 0.056 s | 0.717× | 0.097 GB | 0.104 GB |
| 1,000,000 | 0.574 s | 0.205 s | 0.357× | 0.290 GB | 0.196 GB |

Ratios use the harness's unrounded timings. The 1,000-call case stays below the compilation threshold;
its small difference is not a native-code gain. At one million calls, the measured reduction is 64.3%
in wall time and 32.4% in peak RSS. An additional untimed validation proves the native path ran:
one compiled kernel, 3,073 executions, three grace comparisons, zero mismatches and zero compiler failures.
This establishes payback for the supported arithmetic subset, not for nixpkgs.

## Rejected inline-list experiment

The prototype stored lists of at most two elements inside the existing 24-byte `Value` payload, avoiding
a separate allocation for those cells. It passed the language and dialect gates but did not improve both
real workloads. It was reverted; its measurements remain here as a rejected experiment.

Five interleaved runs per arm, comparing the preserved incoming evaluator (A) with the inline-list
prototype and conservative speculation declarations (B):

| Workload | Schedule | A median | B median | Wall change | RSS median change |
|---|---|---:|---:|---:|---:|
| NixOS toplevel | eager | 4.134 s | 4.033 s | -2.4% | -0.1% |
| nixpkgs-73 | eager | 3.645 s | 3.787 s | +3.9% | -0.3% |
| NixOS toplevel | demand | 4.001 s | 3.954 s | -1.2% | -0.1% |
| nixpkgs-73 | demand | 3.707 s | 3.782 s | +2.0% | -0.3% |

Sources: [eager A/B](small-lists/ab-eager.txt), [demand A/B](small-lists/ab-demand.txt).
All timed outputs matched. The small memory reduction did not justify the nixpkgs regression.

Separate user-space PMU samples included inherited threads and children. The following changes use the
median scaled count of three demand runs per binary, independently of the timing samples above:

| Workload | Cycles | Instructions | Cache references | Cache misses | Branches | Branch misses |
|---|---:|---:|---:|---:|---:|---:|
| NixOS toplevel | +0.79% | +0.44% | +1.04% | +1.06% | +0.54% | +0.81% |
| nixpkgs-73 | +0.41% | -0.03% | -0.25% | -0.56% | +0.05% | +0.18% |

The twelve `small-lists/pmu-*.json` files retain raw counts, time enabled/running and scaled counts.
These samples provide no evidence of a useful cache-locality improvement from this representation.

## Cached reference measurements

Reference comparisons reuse accepted same-host records from generations
[`04-20b5ad596`](../04-20b5ad596/), [`05-f2c37f51b`](../05-f2c37f51b/) and
[`06-aea88bf65`](../06-aea88bf65/). Each generation records the same output hashes as this run.
The minimum and median below are each the best of those three generations; RSS is from the most recent
one. They are historical comparison points, not contemporaneously interleaved reference timings.

| Workload | Reference | Cached minimum | Cached median | Cached peak RSS |
|---|---|---:|---:|---:|
| NixOS toplevel | Nix 2.35.4 | 3.70 s | 4.10 s | 628 MiB |
| NixOS toplevel | Lix 2.91.3 | 4.42 s | 4.65 s | 755 MiB |
| nixpkgs-73 | Nix 2.35.4 | 3.46 s | 3.85 s | 609 MiB |
| nixpkgs-73 | Lix 2.91.3 | 4.31 s | 4.53 s | 757 MiB |

Using the final demand off/on medians from the same-binary experiment above, the historical median
ratios are:

| Workload | JIT off / cached Nix | JIT on / cached Nix | JIT off / cached Lix | JIT on / cached Lix |
|---|---:|---:|---:|---:|
| NixOS toplevel | 0.97× | 0.99× | 0.85× | 0.87× |
| nixpkgs-73 | 1.01× | 0.99× | 0.86× | 0.84× |

These ratios divide measurements from different runs and host loads. They do not attribute a speedup
to this change. The evaluator also retains roughly twice Nix's peak RSS on these workloads.

`scripts/vs-nix.py --reuse-refs` validates and labels these cached rows without invoking reference
version, startup, RSS or timing commands. Missing or incompatible records cause a failure rather than
a reference rerun. The fresh reference runs in `baseline/` and `small-lists/` were completed earlier
in this session, before the instruction to reuse saved references; they are retained but are not mixed
into the historical pins above.

## Provenance

The incoming baseline is commit `46182e5b41a88d96f619b53f923bd6aafb7f46a2` plus the user's initial
uncommitted TrikeShed work. It is therefore identified by its source archive and binary, not by that
commit alone. The prototype archive includes the list experiment and speculation declarations.

| Snapshot | Source archive SHA-256 | Evaluator SHA-256 |
|---|---|---|
| Incoming baseline | `6181c2a58fadedf3969dc0ba34b7db1e51dfd7e1f8f55e8855e976d95d6dad9d` | `f8939ee9c907ab21332a4c97aca079256fcfd9daccf5d048c7371cf606ca64d0` |
| Rejected inline-list prototype | `ae9fddaa90477b6c0e79fbf7fbd0274ee436763a368f1797cb91835030af8bba` | `1d485abb82821c7aaa704d574a9b96ba51d9447a0f80a3a331c698fbd73c22cd` |
| Final guarded scalar tier, list prototype reverted | `b23d1a0c11399ceb676b84b54dfe08eecbe7e9ac6b38a131274b43556ead91af` | `2ac530d5f222b72134ed1b12f04a49b23473d7bb88667ff3a2e09f1872d7e279` |

Source records: [baseline metadata](baseline/metadata.txt), [prototype hashes](small-lists/source.txt),
[final hashes](final/source.txt). The final reference harness was updated separately without changing
the measured evaluator; [harness hashes](final/harness-update.txt) identify that update.
The incoming baseline passed 473/473 language cases semantically on both schedules; the prototype
passed 474/474 after adding its regression case. Both produced 72/72 differential matches with Nix and
71/72 with Lix. Exact stderr parity remains incomplete and is recorded separately in the gate logs.

The final binary passed 475/475 language cases semantically in each of four configurations: eager and
demand, with the JIT disabled and with the JIT enabled at threshold 1. Each recorded 217/475 exact
matches including stderr. The [JIT acceptance gate](final/check-jit.txt) passed 42 exact interpreter/native
comparisons, including error status and diagnostics, with counters proving native execution, grace
validation, type/overflow fallback and compilation limits. The [dialect gate](final/mlir-tests.txt)
passed 14 tests; four run lines were skipped because LLVM 22 lacks dynamic-operation CSE.
[Primop declarations](final/primops.txt) remained 105 registered and 105 declared.
No additional Nix/Lix differential or timing runs were made for the final binary after the reuse request;
its real-workload hashes match the saved reference oracle.
