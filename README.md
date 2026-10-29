# mlir-nix

A Nix evaluator on MLIR. `mlnix` reads Nix, lowers it to a `nix` dialect, and evaluates that IR on demand. It is meant to be a drop-in for
`nix-instantiate` (called as `nix-build` or `nix-store`, it behaves as those), and it is held to that: on every change its output is
compared with Nix 2.35.4 and Lix 2.91.3.

The project is pragmatic. An idea stays if a measurement says it pays. Each change is timed against the reference evaluators on two real
workloads, the NixOS system evaluation and 73 nixpkgs packages, with the answer required to be identical. What loses is written down and
parked, not merged ([docs/FABRIC.md](docs/FABRIC.md), [docs/PERFORMANCE.md](docs/PERFORMANCE.md)).

## How it is built

**A sea of nodes, minted on demand.** The IR is a graph of mostly pure ops with explicit use-def edges and no fixed order (Cliff Click's
sea of nodes; [Sam H. Smith's talk](https://www.youtube.com/watch?v=NxiKlnUtyio) is the clearest hour on building one while parsing, with
no syntax tree), plus a schedule that decides when a node exists. Of the ops that lowering a file creates, 89-90% are never evaluated (NixOS
toplevel: 121,687 of 1,095,819 are). So with `MLNIX_DEFER=1` a lambda body is lowered on its first call, not when its file is read. The
eager schedule is the default and stays the oracle. See [docs/SEA-OF-NODES.md](docs/SEA-OF-NODES.md).

**TrikeShed's algebra.** The data structures follow the kernel of [TrikeShed](https://github.com/jnorthrup/TrikeShed) (`PRELOAD.md`): `a j b`,
a join of two things; the `Series`, a size and an index function read without bounds checks; the `Cursor`; and the `MutableSeries` that is
filled and then drained. The C++ side is `include/Composite/`. Tokens are (start, end) spans over an immutable source, a syntax tree is
regions of series cells in an arena, positions and names are packed words. Some of it is consumed by the evaluator and some is built and
tested only (the `join` dialect and its densify pass); [docs/COMPOSITE.md](docs/COMPOSITE.md) says which.

**Abstractions offloaded to MLIR dialects.** The language is the core `nix` dialect (28 ops). All 105 base-environment primops are declared
as ops of 24 IRDL dialects in `include/NixDialect/NixPrims.irdl.mlir` and defined at load time by a loader that names none of them. Passes
(`nix-prims`, `nix-fold`, `nix-dce`) and MLIR's own `cse` and `canonicalize` work on the IR because identity and effects are declared on
the ops. The IR prints, parses, queries (`mlnix-query`) and transforms (`mlnix-opt`) like any other MLIR.

What the ops mean is attached from outside. Evaluation is one `NixEvalOpInterface` model, effects are `MemoryEffectOpInterface` models
(which is what makes stock `cse` sound on Nix IR), folding is one generic pattern. The dialects know nothing about the evaluator, so
another consumer can attach its own model the same way ([docs/FABRIC.md](docs/FABRIC.md)). The optimizer is MLIR pass-pipeline text
(`MLNIX_PIPELINE`), and the primop set is data: `MLNIX_PRIMS_IRDL=file` swaps the declaration without a rebuild.

**Dense attribute rows.** Each evaluator attribute is 16 bytes: a name, a position index and a Value pointer. Cold source positions
live in a per-evaluator TrikeShed `MutableSeries`; repeated evaluations of one source definition reuse its position range. The MLIR
`positions` property is unchanged. Demand-mode RSS fell 5.3% on NixOS and 8.3% on nixpkgs-73 against the saved evaluator;
timing was mixed across schedules. The [attribute layout report](docs/bench/kali/dense-selectors-20261028/RESULTS.md) records the comparisons.

**Guarded native execution.** `MLNIX_JIT=1` lowers hot integer graphs, lazy value selectors and demand graphs through typed MLIR to LLVM.
Demand graphs include short-circuit operators, type predicates, static attribute existence checks and bounded calls guarded
against the actual closure. Native code inspects persistent
cells and returns a continuation when an argument or capture needs forcing; the host performs that demand with the original error
context, then resumes native code. Unsupported branches return to the interpreter. A nonforcing check of already evaluated cells
delays compilation until a reached path can finish natively. The first three native completions receive interpreter validation without
forcing an additional branch, and 64 consecutive fallbacks retire an unproductive kernel after active calls return.
Inlined calls retain the current callee's captures and logical call depth; ordinary entry and return stay in generated control flow.
Saturated chains with two to four remaining arguments bind their formals directly to persistent cells, eliminating intermediate
closures and frames. Partial applications retain their ordinary environments, and each curried stage has the original sequential
call depth. `MLNIX_JIT_CURRIED=0` disables this tier independently. Inline calls accept one to four arguments; lazy one-key
projections bind selected arguments without allocating temporary thunks. Only a reached consumer demands the key, set and field,
in that order, preserving traces and errors. `MLNIX_JIT_PROJECTION=0` provides a separate ablation.
Tail paths can now return existing values or recipes for fresh empty sets, lists and strings through the same checked call scopes.
Fields and elements stay lazy; grace compares shallow results without additional forcing. `MLNIX_JIT_VALUES=0` disables these returns.
Lists of one to four persistent handles can also return without forcing any element; `MLNIX_JIT_LISTS=0` disables this extension.
It saves another 120,304 / 34,274 frames and 60,152 / 17,137 Value allocations on NixOS / nixpkgs-73. Paired wall time changes
+1.2% / −7.6%, but minima do not support the large package median gain; peak RSS does not fall. Whole-JIT-off/on wall time rises
6.5% / 4.0%, so the native tier remains opt-in. The
[current Kali report](docs/bench/kali/list-returns-20261028/RESULTS.md) separates allocation savings from runtime and peak-memory costs,
and compares with cached Nix/Lix references without rerunning them. Broader projection paths, general escaping closures and
collection fusion remain future work.
[docs/JIT.md](docs/JIT.md) describes the guards, resource bounds, retirement and inspectable intermediate representations.

**Where it stands, and where it goes.** The default evaluator is hand-written C++ walking MLIR ops, with the optional native tier above.
[docs/MLIR.md](docs/MLIR.md) counts what is dialect and what is C++. The aim is to keep moving what the evaluator does by hand
into dialects, passes, interfaces and declarations ([docs/FABRIC.md](docs/FABRIC.md) tracks what moved and what it bought), and to grow
dialects, interface models and tools around Nix that do more than evaluate it; evaluating is the first function, and none of the others
exists yet beyond the query and opt tools. The next steps the measurements support:

- Make `nix.lambda` an isolated unit (closure conversion). Until then no pass can run directly on a lambda body and a lambda cannot be
  loaded lazily from bytecode. The native tier extracts bounded graphs whose captures are resolved
  by the host on each call; arbitrary calls and local lazy values still need general closure conversion ([docs/MLIR.md](docs/MLIR.md)).
- Subsume the library code that sits on the border. Of the lambda calls of a NixOS evaluation, 91% run inside nixpkgs' `lib`, which is
  Nix code over the primops, and 18 small functions of it are 31% of the calls ([docs/LIBRARY.md](docs/LIBRARY.md) has the map, a bound on
  what moving them across is worth, and the design).
- Keep the footprint down: `mlnix` still holds about twice Nix's peak memory, and the fill-then-drain
  containers of the evaluator are mapped in [docs/FILL-DRAIN.md](docs/FILL-DRAIN.md).
- Collapse the primop set into its declaration: it is declared once in IRDL and registered again in C++, and `scripts/check-prims.py` only
  checks that the two agree. And give the syntax a dialect of its own (Google's JSIR is the existence proof, [docs/MLIR.md](docs/MLIR.md)).
- Parse into the IR with no syntax tree, as in [Sam H. Smith's talk](https://www.youtube.com/watch?v=NxiKlnUtyio). The front end builds a
  tree (5.4 to 5.5 bytes per byte of source, 180 to 190 MB of the NixOS toplevel's footprint) and walks it into ops; the tree, its printer and the
  walk are 1,185 lines of C++, the largest cut on the table now that the C++ total is ratcheted down (`scripts/cxx-lines.py`).
  [docs/FABRIC.md](docs/FABRIC.md) sets the talk's mechanisms against this tree one by one.

## Benchmarks (kali)

`scripts/vs-nix.py --native --demand` on one machine (an i7-6820HK, 4 cores and 8 threads, Linux under WSL2): the evaluators run in turn,
interleaved, the first one rotating, and the results are compared byte for byte, so a faster answer that differs is not a comparison. Both
workloads evaluate the same nixpkgs, the `nixos-25.05` branch tarball with sha256 `9051fdfc3664ff378d0c51fa04fdf93fb43c8a5773c13416a28f85ce9514b73a`
(`test/nixos-toplevel.nix`, `test/nixpkgs-drvs.nix`). `demand` is `MLNIX_DEFER=1`. The min is the steadier figure here: the host's load moves
medians by several percent. Each commit is built, gated and timed by `scripts/kali-gen.sh`; the raw output is kept in
[docs/bench/kali](docs/bench/kali), and the section below is rendered from it by `scripts/readme-bench.py`.

For new iterations against these stable references, add `--reuse-refs`. Only the changed `mlnix` arms run; Nix/Lix timings and their
output oracle come from accepted same-host records, labeled as cached. No reference startup, RSS or version process is invoked.

<!-- bench:begin -->
<!-- generated by scripts/readme-bench.py from docs/bench/kali/; edit those files or the script, not this block -->

Latest generation: commit `3ffa197af`, measured on an Intel(R) Core(TM) i7-6820HK CPU @ 2.70GHz (x86_64, 8 threads), 7 interleaved rounds per workload, every evaluator's output identical to the others'.

| nixos-toplevel | min | median | peak RSS |
|---|---:|---:|---:|
| Nix 2.35.4 | 3.71 s | 3.81 s | 630 MB |
| Lix 2.91.3 | 4.43 s | 4.93 s | 755 MB |
| mlnix, eager | 2.97 s | 2.99 s | 1123 MB |
| mlnix, demand | 2.58 s | 2.67 s | 1011 MB |
| **demand / Nix** | **×0.70** | **×0.70** | ×1.60 |
| demand / Lix | ×0.58 | ×0.54 | ×1.34 |

| nixpkgs-73 | min | median | peak RSS |
|---|---:|---:|---:|
| Nix 2.35.4 | 3.48 s | 3.54 s | 609 MB |
| Lix 2.91.3 | 4.17 s | 4.36 s | 757 MB |
| mlnix, eager | 2.60 s | 2.65 s | 1030 MB |
| mlnix, demand | 2.30 s | 2.40 s | 927 MB |
| **demand / Nix** | **×0.66** | **×0.68** | ×1.52 |
| demand / Lix | ×0.55 | ×0.55 | ×1.22 |

Start-up (`--eval -E 1`, median of 5): Nix 2.35.4 33 ms, Lix 2.91.3 29 ms, mlnix 32 ms, mlnix demand 31 ms.

Parity at this commit, on the same host: Nix's language tests 487/487 semantic and 229/487 exact (stderr too) on both schedules; dialect tests (FileCheck): 15 passed, 0 failed, 4 run lines skipped (cse-dynamic-ops); primops: 105 registered, 105 declared; differential tests, eager: 72/72 identical to Nix 2.35.4, 71/72 identical to Lix 2.91.3; demand: 72/72 identical to Nix 2.35.4, 71/72 identical to Lix 2.91.3.

Every generation, as the ratio of `mlnix, demand` to Nix 2.35.4 (below 1 is faster; minima are computed from the printed minima, medians are the host's own) and its peak memory:

| commit | toplevel min | toplevel median | nixpkgs-73 min | nixpkgs-73 median | toplevel RSS |
|---|---:|---:|---:|---:|---:|
| `09896c336` | ×1.14 | ×1.02 | ×1.10 | ×1.10 | ×2.54 |
| `ef7f3d606` | ×0.94 | ×0.85 | ×0.88 | ×0.78 | ×2.53 |
| `6344b5c82` | ×0.94 | ×0.93 | ×0.88 | ×0.88 | ×2.40 |
| `20b5ad596` | ×0.91 | ×0.86 | ×0.86 | ×0.80 | ×2.40 |
| `f2c37f51b` | ×0.94 | ×0.87 | ×0.88 | ×0.79 | ×2.40 |
| `aea88bf65` | ×0.93 | ×0.84 | ×0.87 | ×0.82 | ×2.40 |
| `3ffa197af` | ×0.70 | ×0.70 | ×0.66 | ×0.68 | ×1.60 |
<!-- bench:end -->

Older generations and what changed between them: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Build

LLVM and MLIR with their CMake packages (22 on Linux and 23.1.1 on macOS are what it is built and tested with), CMake 3.20, Ninja, a C++20
compiler. `-DCMAKE_CXX_STANDARD=23` also builds. SHA-256 comes from CommonCrypto on macOS and from OpenSSL's libcrypto elsewhere when it is
found, else from LLVM (`-DMLNIX_SHA256=auto|openssl|llvm`).

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=clang-22 -DCMAKE_CXX_COMPILER=clang++-22 \
          -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm -DMLIR_DIR=/usr/lib/llvm-22/lib/cmake/mlir
    cmake --build build --target mlnix mlnix-opt

The tools: `mlnix` (the evaluator and a `nix-instantiate`, `nix-build` and `nix-store` front), `mlnix-opt` (`mlir-opt` with the Nix dialects),
`mlnix-query` (`mlir-query` with them), `mlnix-parse` (parses every file in a list in one process, to compare two front ends byte for byte).

## Use

    build/bin/mlnix instantiate --eval --strict -E '1 + 2'
    MLNIX_DEFER=1 build/bin/mlnix instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs

`MLNIX_STATS=1` prints what the run did (the dynamic mix of ops, the call ladder, allocation).

## Tests

    python3 scripts/run-lang-tests.py     # Nix's functional language tests: semantic = right status and stdout, exact = stderr too
    python3 scripts/run-mlir-tests.py     # FileCheck tests of the dialects and passes
    python3 scripts/check-prims.py        # every primop is both registered and declared
    python3 scripts/difftest.py           # the same expressions through mlnix and reference Nix (container "nixref", or --native)
    python3 scripts/check-jit.py          # exact JIT/interpreter parity, lazy demands, grace, retirement and compilation limits

Set `MLNIX_DEFER=1` to run any of them on the demand schedule. `scripts/ab.py` times two builds against each other, interleaved, and
compares the hash of their output.

## Documents

| | |
|---|---|
| [RELEASE-v0.4.0](docs/RELEASE-v0.4.0.md) | the evaluator runs nodes: what v0.4.0 changed, why, and what it measured |
| [SEA-OF-NODES](docs/SEA-OF-NODES.md) | demand-minted lambda bodies |
| [JIT](docs/JIT.md) | guarded arithmetic, selectors and resumable Boolean/call graphs through MLIR and LLVM |
| [COMPOSITE](docs/COMPOSITE.md) | TrikeShed's PRELOAD in C++: what is built, what consumes it |
| [FABRIC](docs/FABRIC.md) | the dialect fabric: logic moved into dialects, what it bought |
| [MLIR](docs/MLIR.md) | what is MLIR here and what is C++, the dynamic profile, the MLIR survey |
| [PERFORMANCE](docs/PERFORMANCE.md) | the profile, the head-to-head history, the families examined, the failures |
| [LIBRARY](docs/LIBRARY.md) | where the lambda calls are: nixpkgs' `lib` is the workload, and what moving it across the border is worth |
| [FILL-DRAIN](docs/FILL-DRAIN.md) | fill-then-drain containers of the evaluator and what translating them is worth |
| [COMBINATORS](docs/COMBINATORS.md) | declarations as IR, and what failed |
| [COLLECTIONS](docs/COLLECTIONS.md) | collections: measured, built, failed |
| [IO](docs/IO.md) | what the evaluator waits for, and what io_uring does about it |

## License

LGPL-2.1, see [COPYING](COPYING).
