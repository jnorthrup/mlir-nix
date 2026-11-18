# mlir-nix

ai: yes, disclosing

A Nix evaluator on MLIR, and the dialects and tools grown around it. `mlnix` reads Nix, lowers it to the `nix` dialect and
evaluates that IR on demand. It is meant to be a drop-in for `nix-instantiate`; called as `nix-build`, `nix-store` or `nix`, it
behaves as those. It is held to that: its output is compared with Nix 2.35.4 and Lix 2.91.3, and a faster answer that differs
is not a result.

Everything here is to build to TrikeShed's `PRELOAD.md` as MLIR ([AGENTS.md](AGENTS.md)). TrikeShed's algebra (joins,
series, cursors, Confix) is the data structure of the C++ (`include/Composite/`), and the `trikeshed` dialect is to be the
form every other dialect lowers to. Today only confix, kif and sumo lower through it. Nix values carry trikeshed types in the
IR, but the evaluator runs the `nix` ops as C++ nodes, so the Nix path bypasses TrikeShed's ops, fill and drain included
([docs/PRELOAD-DIALECTS.md](docs/PRELOAD-DIALECTS.md), steps 2-4).

## What is here

| | |
|---|---|
| `mlnix` | the evaluator; a `nix-instantiate`, `nix-build` and `nix-store` front; and, invoked as `nix`, a `nix` command: `build`, `eval`, `run`, `profile`, flakes, and binary caches whose narinfo signatures are checked with ed25519 ([docs/NIX-CLI.md](docs/NIX-CLI.md)) |
| `mlnix-opt` | `mlir-opt` with the dialects and passes below |
| `mlnix-kif` | KIF files (SUMO) into a `kif.theory`; the chase over its Horn fragment, keeping each derived fact's rule and premises (`--chase`); Lean certificates (`--lean`, `--lean-piece`); TPTP (`--tptp`, SigmaKEE's FOF translation) |
| `mlnix-parse` | parses every file of a list in one process, to compare two front ends byte for byte |
| `mlnix-c` | the C surface of the dialects (`include/mlnix-c/MlnixC.h`), what Kotlin/Native's cinterop links |
| `graal/` | nix-truffle, the Graal/Truffle arm: it reads the IR that `mlnix-opt --son-export` writes and runs it |
| `utils/mlnixci/` | mlnix's configuration interface (formerly mini-luci), after OpenWrt's LuCI: a NixOS configuration's options rendered as a manifest, with its facets written as Nix code, a what-if overlay, the running system's values beside the configured ones, and a server written in MLIR with no C++ ([docs/MLNIXCI.md](docs/MLNIXCI.md)) |

## The dialects

- `nix` (29 ops) is the language. The base environment's 121 primops are declared as ops of 24 IRDL dialects
  (`include/NixDialect/NixPrims.irdl.mlir`) and defined at load time by a loader that names none of them. `NixSyntax.td`
  declares the syntax for a front end that builds no tree.
- `mlnix` (`MlnixControl.td`) is the control surface of the utility: its flags, `MLNIX_*` variables and settings in one place.
- `son` is the sea of nodes' schedule. A lambda body is minted on its first call (`MLNIX_DEFER=1`). The must-force set is
  what a frame forces before it returns, and `son.release` states the Graal arm's one lifecycle rule in the IR: when a call
  returns, its frame keeps what its unforced cells can read and lets go of the rest. `arg_forced` on a body says it forces
  its argument, so the Graal arm computes that argument before the call and makes no cell over its own frame for it
  ([docs/SEA-OF-NODES.md](docs/SEA-OF-NODES.md)).
- `trikeshed` and `confix` are series, cursors and joins as ops, and Confix's index of a JSON text. `trikeshed-lower-cursors`
  lowers them to `scf`, `arith` and `memref` ([docs/PRELOAD-DIALECTS.md](docs/PRELOAD-DIALECTS.md)).
- `kif` and `sumo` are KIF theories and SUMO's taxonomy. `kif-to-trikeshed` lays a theory out as cursors
  ([docs/REASONING-SPLIT.md](docs/REASONING-SPLIT.md): who reasons over SUMO, with the numbers).

## How the evaluator works

**A sea of nodes, minted on demand.** The IR is a graph of mostly pure ops with explicit use-def edges and no fixed order
(Cliff Click's sea of nodes; [Sam H. Smith's talk](https://www.youtube.com/watch?v=NxiKlnUtyio) is the clearest hour on
building one while parsing, with no syntax tree), plus a schedule that decides when a node exists. Of the ops that lowering a
file creates, 89-90% are never evaluated (nixos-toplevel: 121,687 of 1,095,819 are), so with `MLNIX_DEFER=1` a lambda body is
lowered on its first call. The eager schedule is the default and stays the oracle.

**TrikeShed's algebra, and no `std::string`.** `a j b` joins two things; a `Series` is a size and an index function read
without bounds checks; a `Cursor` is a series of rows; a `MutableSeries` is filled and then drained. Tokens are spans over an
immutable source, and positions and names are packed words. Owning text is `composite::Text` (`include/Composite/Text.h`);
what only reads is a window (`Chars`, `std::string_view`). `lib/`, `include/` and `tools/` use no `std::string`,
`std::to_string`, `std::sto*`, string stream or `<iostream>`; the checks under `scripts/` keep the standard library as the
oracle `Text` is tested against.

**What the ops mean is attached from outside.** Evaluation is one `NixEvalOpInterface` model, effects are
`MemoryEffectOpInterface` models (which is what makes stock `cse` sound on Nix IR), and folding is one generic pattern. The
dialects know nothing about the evaluator, so another consumer can attach its own models. The optimizer is pass-pipeline text
(`MLNIX_PIPELINE`), and the primop set is data: `MLNIX_PRIMS_IRDL=file` swaps the declaration without a rebuild.

**Dense attribute rows.** An attribute is 16 bytes: a name, a position index and a value pointer. A set is one sorted array of
them, and `a // b` writes a new array in one pass, as Nix does
([record](docs/bench/kali/dense-selectors-20261028/RESULTS.md)).

**No native tier.** The opt-in JIT (`MLNIX_JIT=1`) lowered hot lambdas straight to `arith`, `cf` and LLVM, beside TrikeShed
rather than through it. On both workloads it was slower than the interpreter (11-12%) and used more memory (4-7%), with the
same answers, so it was removed; it is at 3b46257
([record](docs/bench/local/jit-removal-20261118/RESULTS.md)). An LLVM arm is to lower through `trikeshed`.

**The default evaluator** is C++ over nodes. When a body is indexed, each of its SSA values gets a record of its kind, its
operands, its frame slot and the function that evaluates it; a thunk holds its node, so evaluating is one indirect call. The
MLIR ops stay the program: nodes are made from them and read their attributes.

## Open work

- The Nix path through TrikeShed ([docs/PRELOAD-DIALECTS.md](docs/PRELOAD-DIALECTS.md), steps 2-4):
  - `son`'s pool rows as `trikeshed.append` and first forces as `trikeshed.anchor`, with the evaluator reading son IR;
  - an LLVM arm that lowers through `trikeshed` (the JIT, which lowered straight to `arith` and LLVM, is removed);
  - `//` as `trikeshed.layers`.

  No pass creates a trikeshed op yet. `trikeshed.append` and `trikeshed.anchor` are used nowhere, and `trikeshed.drain` only
  by tests and mlnixci's query. The evaluator's containers are `composite::MutableSeries`, but whether they are filled and
  then drained was measured once, in October, and nothing checks it now.
- Lifetimes: the Graal arm now reads a callee's strictness at the call (`son.body`'s `arg_forced`) and a builtin's from
  its declaration (`nix.strict`, `nix.first`), and computes those values instead of making cells over the frame: fib's
  frames stay virtual (26.3 MB a run down to 3.4 MB), and the cells made over frames on the language tests fall from 9,876
  to 3,423. The declarations say what each builtin forces (56 of 121 strict, from 11), which also puts more native calls
  on a stack frame (+9% and +15% on bench.py's two workloads); a curried call's later arguments are read the same way, one
  application at a time. Left: a first argument its body does not force (a curried function's outer body only captures
  it), and list elements, attribute values and captures, which escape by design. The native evaluator reads neither
  `son.release` nor `arg_forced` ([docs/SEA-OF-NODES.md](docs/SEA-OF-NODES.md)).
- Ordering: a counting dense bucket is 2.3x to 2.7x faster than the best min-max-heap cluster shape at every scale measured
  ([docs/CLUSTER-SCALES.md](docs/CLUSTER-SCALES.md)); which one the block compressor keeps is open
  ([docs/BTRFS-COMPRESSOR.md](docs/BTRFS-COMPRESSOR.md)).
- Lowerings not done: Depths, KeyToChild for a key known only at run time, YAML, groupBy
  ([docs/PRELOAD-DIALECTS.md](docs/PRELOAD-DIALECTS.md)).
- KIF to TPTP: the port does not write the conjectures of two of SigmaKEE's 43 tests, TQC2 and TQROW-BUILTIN, which are
  higher order ([record](docs/bench/kali/tptp-20261117/README.md)).
- The front end still builds a syntax tree. Parsing straight into the IR (`NixSyntax.td`) is the larger cut.

## Benchmarks (kali)

`scripts/vs-nix.py --native --demand` on one machine (an i7-6820HK, 4 cores and 8 threads, Linux under WSL2): the evaluators run
in turn, interleaved, the first one rotating, and the results are compared byte for byte. Both workloads evaluate the same
nixpkgs, the `nixos-25.05` branch tarball with sha256 `9051fdfc3664ff378d0c51fa04fdf93fb43c8a5773c13416a28f85ce9514b73a`
(`test/nixos-toplevel.nix`, `test/nixpkgs-drvs.nix`). `demand` is `MLNIX_DEFER=1`. The min is the steadier figure: the host's
load moves medians by several percent. Each commit is built, gated and timed by `scripts/kali-gen.sh`; the raw output is kept in
[docs/bench/kali](docs/bench/kali), and the block below is rendered from it by `scripts/readme-bench.py`. The newest generation
is from 30 October (commit `ed817cba8`); the work merged since then has not been through the host.

<!-- bench:begin -->
<!-- generated by scripts/readme-bench.py from docs/bench/kali/; edit those files or the script, not this block -->

Latest generation: commit `ed817cba8`, measured on an Intel(R) Core(TM) i7-6820HK CPU @ 2.70GHz (x86_64, 8 threads), 7 interleaved rounds per workload, every evaluator's output identical to the others'.

| nixos-toplevel | min | median | peak RSS |
|---|---:|---:|---:|
| Nix 2.35.4 | 4.44 s | 4.63 s | 628 MB |
| Lix 2.91.3 | 4.70 s | 4.78 s | 755 MB |
| mlnix, eager | 2.89 s | 2.95 s | 1134 MB |
| mlnix, demand | 2.53 s | 2.73 s | 1025 MB |
| **demand / Nix** | **×0.57** | **×0.59** | ×1.63 |
| demand / Lix | ×0.54 | ×0.57 | ×1.36 |
| asnix, answer not Nix's (not a comparison) | 2.79 s | 3.24 s | 1174 MB |
| ll, answers `<LAMBDA>`, not Nix's | | | |

| nixpkgs-73 | min | median | peak RSS |
|---|---:|---:|---:|
| Nix 2.35.4 | 3.71 s | 4.13 s | 609 MB |
| Lix 2.91.3 | 4.55 s | 4.66 s | 756 MB |
| mlnix, eager | 2.50 s | 2.56 s | 1113 MB |
| mlnix, demand | 2.14 s | 2.19 s | 1012 MB |
| **demand / Nix** | **×0.58** | **×0.53** | ×1.66 |
| demand / Lix | ×0.47 | ×0.47 | ×1.34 |
| asnix | fails rc=1: asnix: derivation: too many outputs (max 16) | | |
| ll, answers `<LAMBDA>`, not Nix's | | | |

| ffmpeg | min | median | peak RSS |
|---|---:|---:|---:|
| Nix 2.35.4 | 1.97 s | 2.04 s | 356 MB |
| Lix 2.91.3 | 2.10 s | 2.21 s | 432 MB |
| mlnix, eager | 1.61 s | 1.68 s | 574 MB |
| mlnix, demand | 1.36 s | 1.45 s | 468 MB |
| **demand / Nix** | **×0.69** | **×0.71** | ×1.31 |
| demand / Lix | ×0.65 | ×0.66 | ×1.08 |
| asnix | 1.24 s | 1.32 s | 512 MB |
| asnix / Nix | ×0.63 | ×0.65 | ×1.44 |
| ll, answers `<LAMBDA>`, not Nix's | | | |

asnix ([github.com/tomberek/asnix](https://github.com/tomberek/asnix), built with `make release`) runs in the same rounds, as its own command line takes the workload; its time counts only where its answer is Nix's.

ll ([github.com/tomberek/ll](https://github.com/tomberek/ll), built with `make CC=clang-22`) runs in the same rounds, as its own command line takes the workload; its time counts only where its answer is Nix's.

Start-up (`--eval -E 1`, median of 5): Nix 2.35.4 32 ms, Lix 2.91.3 29 ms, mlnix 33 ms, mlnix demand 34 ms.

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
| `69ceffc89` | ×0.71 | ×0.68 | ×0.64 | ×0.67 | ×1.69 |
| `9ce09e362` | ×0.66 | ×0.67 | ×0.63 | ×0.57 | ×1.70 |
| `0ca4844a8` | ×0.67 | ×0.70 | ×0.61 | ×0.58 | ×1.70 |
| `ed817cba8` | ×0.57 | ×0.59 | ×0.58 | ×0.53 | ×1.63 |
<!-- bench:end -->

With prelowering (opt-in, warm start: `MLNIX_DEFER=1 MLNIX_PREFETCH=auto MLNIX_PRELOWER=1 MLNIX_PRELOWER_THREADS=3`), commit `ed817cba8` on the
same boot, 7 interleaved rounds, the evaluators' outputs identical (the raw records are the generation's `prelowered-*.txt`):

| prelowered, min | Nix 2.35.4 | mlnix, demand | ×Nix (median) | asnix | ll |
|---|---:|---:|---:|---:|---|
| nixos-toplevel | 4.05 s | **1.64 s** | **×0.40** (×0.36) | 2.81 s, answer not Nix's | answers `<LAMBDA>` |
| nixpkgs-73 | 3.62 s | **1.60 s** | **×0.44** (×0.39) | fails: at most 16 outputs a derivation | answers `<LAMBDA>` |
| ffmpeg | 2.00 s | **0.96 s** | **×0.48** (×0.48) | 1.24 s (×0.62) | answers `<LAMBDA>` |

ll takes one file and no arguments and does not call a function it is given, so on a workload that is a function it answers `<LAMBDA>`: that is
reported as it is, and nothing is wrapped for it.

Peak RSS prelowered is 1121 MB against 595 MB on nixos-toplevel (×1.88). Since `9ce09e362`, a derivation made again by another call with
equal attributes is found by its content before it is hashed: 37% of a NixOS evaluation's derivations and 44% of nixpkgs-73's skip both
SHA-256 passes. A string's context, the primops and the caches by path also left the standard library for the pure zone: a series of arena
pointers, plain function pointers, and crit-bit tries.

Older generations and what changed between them: [PERFORMANCE.md at 77de09c](https://github.com/jnorthrup/mlir-nix/blob/77de09c/docs/PERFORMANCE.md).

## Build

LLVM and MLIR with their CMake packages (22 on Linux and 23.1.1 on macOS are what it is built and tested with), CMake 3.20,
Ninja, and clang with C++20 (`-DCMAKE_CXX_STANDARD=23` builds and passes the same tests). SHA-256 comes from CommonCrypto on macOS and from OpenSSL's libcrypto elsewhere when it is found,
else from LLVM (`-DMLNIX_SHA256=auto|openssl|llvm`).

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_COMPILER=clang-22 -DCMAKE_CXX_COMPILER=clang++-22 \
          -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm -DMLIR_DIR=/usr/lib/llvm-22/lib/cmake/mlir
    cmake --build build --target mlnix mlnix-opt mlnix-kif TrikeShedRuntime

The Graal arm: `cd graal && ./gradlew installDist` (JDK 25 GraalVM; TrikeShed-jvm from mavenLocal). mlnixci: `make -C utils/mlnixci`
(it reads `build/bin` and `lib/Confix/confix.ll` from this checkout).

## Use

    build/bin/mlnix instantiate --eval --strict -E '1 + 2'
    MLNIX_DEFER=1 build/bin/mlnix instantiate --readonly-mode --eval --strict test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs

`MLNIX_STATS=1` prints what the run did (the dynamic mix of ops, the call ladder, allocation).

## Tests

    python3 scripts/run-lang-tests.py            # Nix's language tests: semantic = right status and stdout, exact = stderr too
    python3 scripts/run-mlir-tests.py            # FileCheck tests of the dialects and passes
    python3 scripts/check-prims.py               # every primop is both registered and declared
    python3 scripts/difftest.py                  # the same expressions through mlnix and reference Nix (container "nixref", or --native)
    python3 scripts/truffle-lang-tests.py        # the language tests on the Graal arm
    python3 scripts/truffle-release-check.py .   # the Graal arm with son.release on and off: the same outputs, nothing kept outside it
    make -C utils/mlnixci check NIXPKGS_LIB=...  # mlnixci's compiled query against the counted one, then its end-to-end test

Set `MLNIX_DEFER=1` to run the evaluator's tests on the demand schedule. `scripts/ab.py` times two builds against each other,
interleaved, and compares the hash of their output.

## Documents

| | |
|---|---|
| [MLNIXCI](docs/MLNIXCI.md) | mlnixci, the configuration interface: what it is today, and the direction it is to take |
| [NIX-CLI](docs/NIX-CLI.md) | the `nix` command, flakes in Nix, binary caches with ed25519 checks, and what running a substituted program needs |
| [SEA-OF-NODES](docs/SEA-OF-NODES.md) | demand-minted lambda bodies, the must-force set, `son.release`, and escape analysis on the Graal arm |
| [PRELOAD-DIALECTS](docs/PRELOAD-DIALECTS.md) | each dialect against TrikeShed's PRELOAD: what lowers to `trikeshed`, in what order, and what is done |
| [REASONING-SPLIT](docs/REASONING-SPLIT.md) | who reasons over SUMO: Nix, the MLIR layers, Vampire, Lean |
| [BTRFS-COMPRESSOR](docs/BTRFS-COMPRESSOR.md) | the btrfs inode block compressor: ordering in blocks small enough for registers and cache lines |
| [CLUSTER-SCALES](docs/CLUSTER-SCALES.md) | the ordering cluster (a min-max heap and pegs) at three scales, against a counting bucket |
| [IPNS-DEMO](docs/IPNS-DEMO.md) | two builds of mlnix, one per host, each published under its own IPNS name |
| [d3m](docs/d3m) | the D3M integrations: what was merged, each conflict and how it was settled |
| [bench](docs/bench) | raw benchmark and test records, by host and date |

The documents last changed in October (the JIT, the dialect fabric, the performance history, the frame bytes, the MLIR survey,
the composite and others) were removed by the D3M integration of 17 November as out of date. They are at
[77de09c](https://github.com/jnorthrup/mlir-nix/tree/77de09c/docs), and code comments cite them as `77de09c:docs/NAME.md`.

## License

LGPL-2.1, see [COPYING](COPYING).
