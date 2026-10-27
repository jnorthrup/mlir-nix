# MLIR in mlnix, X-rayed

What is MLIR here and what is C++, what the running program does from the inside, which rungs of a resolution ladder exist
and what the counts say about the next one, and what GitHub has. Every number is from `MLNIX_STATS=1` on the Mac (demand
schedule, `nixos-toplevel` and `nixpkgs-73`) unless it says kali. Written 2026-10-27; the counters are in `lib/Eval/Eval.cpp`
(`printStats`), so the plates are reproducible.

## 1. What is MLIR here

The encoding is MLIR; the execution is not.

    ODS/IRDL     NixBase.td 225 + NixOps.td 280 lines: 28 ops, 1 type, 1 interface; NixPrims.irdl.mlir 628 lines: 105 primops in 24 dialects
    dialect C++  NixDialect.cpp 515, NixPrimDialects.cpp 252, NixDialect.h 140; passes nix-prims, nix-fold, nix-dce, join-densify
    hand C++     evaluator (lib/Eval, Eval.h, Arena.h) 5,690 lines; front end 3,722; store 2,704; tools 1,187

What the ODS already says: `Pure` on 22 ops, `ConstantLike` on 5, `hasFolder` on 6, `NixModes<strict, tail>` (which operands an op
forces, which it returns), `nix.expr` is `IsolatedFromAbove` (one per file), `nix.expr` and `nix.lambda` are graph regions. Stock
`cse` and `canonicalize` are sound because identity is declared (`NixFreshVal`, `NixFxUser`).

What is not used, counted as references in `lib/`, `include/` and `tools/`:

    bytecode (lazy loading of IsolatedFromAbove ops)      0   in LLVM 22 (kali) and 23 (Mac): BytecodeReader.h `lazyLoad`, isMaterializable, materialize
    ExecutionEngine / ORC                                  0   libMLIRExecutionEngine.a on both
    transform dialect                                      0   libMLIRTransformDialect.a on both; the driver is pipeline text
    PDL / PDLL                                             0   tried on exp/pdl-devirt, lost on every count (COMBINATORS.md)
    dataflow framework, Liveness                           0   libMLIRAnalysis.a on both
    inliner interface, CallOpInterface, CallableOpInterface  0
    getUsedValuesDefinedAbove                              0   (the front end has its own FreeVars walk)
    canonicalization patterns                              1

The structural gap behind most of these: `nix.lambda` is not `IsolatedFromAbove` (it reads the values it captures), so no
PassManager can run on a lambda body, no pass runs on several threads, no lambda can be lazily loaded from bytecode, and no lambda is a
unit a JIT can compile. `nix.lambda` carries `captures` operands only in the deferred form. The MLIR idiom for this is a closure with
an explicit capture list and a body that takes the captures as block arguments (LangRef: "Closure"); `jaredhoberock/mlir-closure-dialect`
is a 1,200-byte README of exactly that, with a pass lowering it to a tuple of captures and a private function.

## 2. The program from the inside

                                            nixos-toplevel      nixpkgs-73
    ops lowered / ever evaluated            619,842 / 19.6%
    evalOp runs                             15,414,014          10,807,891
      nix.apply                             20.9%               19.5%
      nix.select                            16.9%               12.1%
      nix.if                                11.0%               8.8%
      nix.attrs                             7.0%                6.5%
      eq, and, or, not, has_attr            19.1%               23.2%      (the module system's conditions)
    thunks made by lookup()                 7,751,227           5,504,574
      of them closures (nix.lambda)         14.4%               9.8%
      never forced, of the real thunks      27.2%               31.7%      (select 24.5% / 19.7%, apply 24.5% / 45.6%, concat_strings 76% / 76%)
    lambda calls                            5,387,038           3,762,175
      lambdas called / lowered              5,394 / 29,744      3,537
      called once                           1,166               1,533
      busiest 10 / 100 / 500 take           17.4 / 76.6 / 98.9% 38.7 / 83.9 / 99.2%
      calls to bodies of <= 8 ops           56.1%               62.0%
      per call                              19.5 ops, 5.3 slots 20.2 ops, 7.4 slots
    apply sites                             23,033              12,791
      callee is a primop, PAP or functor    35.9%               23.6%
      lambda calls at sites that never changed callee  89.6%    85.6%      (one-entry callee cache misses 1.9% / 1.1%)
    select: one-entry index cache hits      92.9% of 2.24M      73.7% of 0.88M
    attribute sets: built by builders       1,373,555 (4.76M cells)         828,230 (4.51M cells)
      of them literal, static names         1,062,472 (77%)     694,828 (84%)
      distinct shapes of the literals       7,737               2,738      (100 shapes cover 95.3% / 95.8% of the literals)
      flat sets made by merging             266,505 (7.29M cells)           172,688 (12.95M cells)
      share of all cells made by merging    60%                 74%        (175 MB / 311 MB of 24-byte cells)
      builder finish() already in order     55.6%               78.2%
    frames                                  5.39M, 315 MB       3.76M, 282 MB
      slots ever filled                     50.6%               36.8%
      dead when their call returned         26.9% (55 MB)       32.7% (38 MB)

Two things this overturns. The earlier JIT arithmetic ("a compile per created lambda is 3 s") priced every lambda; a lambda that
is called 1,000 times is 337 of 29,744. And the attribute memory is not the literal sets (26% / 13% of the cells): it is `//` merging
two small sets into a flat copy.

## 3. The ladder

The design: the first visit to anything is the cheapest scan that exists, a counter is the profiler, and every revisit buys more
resolution, so that what is paid is proportional to the evidence that it will be used again. A rung is entered at `calls >= C / s`
(cost of entering over saving per later call; the ski-rental rule), and the cost over all is within a constant factor of knowing the
future.

    rung  what                               paid when                      state
    0     Confix scan: bands, no AST         once per file, ~memchr speed   built (Confix.cpp, 43 edge cases), no consumer
    1     parse a band to its AST            the band is entered            whole file at first import (parser -50% this window)
    2     mint the lambda's ops              first call                     built (MLNIX_DEFER): 5,394 of 29,744 minted
    3     per-lambda counter; cheap caches   the 16th call                   not built
    4     compile the body                   the ~1000th call               not built

What the plates give to the thresholds, calls after the threshold and lambdas that reach it:

    threshold      toplevel                         nixpkgs-73
    2 calls        78.4% of lambdas, 99.8% of calls   56.7%, 99.9%
    16             21.3% (1,149), 99.5%               27.1% (957), 99.4%
    256            9.6% (519), 96.5%                  12.4% (439), 95.9%
    1024           6.2% (337), 90.8%                  7.1% (252), 89.2%
    4096           3.2% (173), 76.5%                  4.4% (154), 73.8%

Rung 0 has a measured ceiling (71.8% of source bytes are in bands never entered: skipping those of 256 bytes or more is -10.8% of
bytes before the scan costs, an estimated 4 to 6% net) and no consumer. Rung 2 has 1,166 / 1,533 lambdas that were called once,
whose mint was paid for one call. Rung 3 is where the cheap caches go: callee at a call site, the index where a static key was
found. Rung 4 pays when it saves `s` per call over the calls after the threshold: at 200 microseconds a body, 337 bodies are 67 ms, and
4.89M calls come after the 1024th, so it breaks even at 14 ns a call (the evaluator thread spends about 220 ns per lambda call in all, on the Mac).

The resolved-addressing experiments (FABRIC 2, `exp/slot-prop`) lost by paying for every lambda at once, and for a property read
that is as dependent a load as the probe it replaced; the left-over probe is 5 ns a call, about 38M of them. That is rung 4's
target (an address in the instruction stream), not rung 3's.

## 4. Candidates, by what the plates allow

    lever                                      evidence                                         ceiling                 status
    rung 0 consumer (lazy bands)               71.8% of bytes never entered                     4-6% net, estimated     needs scope-snapshot lambda deferral
    rung 3: callee cache at apply sites        98.1% / 98.9% of lambda calls hit                <= 2.5% estimated       not built
    rung 3: index cache at select              92.9% / 73.7% hit                                <= 1.6% estimated       not built
    `//` merges                                60% / 74% of attribute cells                     memory first             sweep kMinBase=32, kRatio=8
    rung 4: compile hot bodies                 337 / 252 lambdas take 90.8% / 89.2% of calls    <= 17.9% (probes) + 2% (dispatch) of the evaluator thread, before the compile cost   not built
    strictness / cheap eagerness               27% / 32% of thunks never forced                 unknown; needs "certainly forced"   not measured
    stack frames for calls that do not escape  26.9% / 32.7% of frames dead at return           <= 3.5% of RSS, as an upper bound   dropped
    shapes as types (hidden classes)           77% / 84% literal, 100 shapes cover 95%          -4% RSS, select cache already 74-93%   behind the merges

The line that moves is the second to last row of the first block: attribute memory is 60 to 74% merges, and the layering rule
(`updateAttrs`: a layer when the base has 32 or more attributes and the top is an eighth of it or less) was set once.

## 5. GitHub, 2026-10-27

Searched with the unauthenticated repository search API (51 queries, many empty) and read for facts: the stars, last push and
licence are from the API, the rest from the README or file named. Nothing here is a dependency candidate for Nix semantics; these are
designs to read.

    repo                              stars  pushed      what it has                                                    for us
    bollu/lz                          17     2022-01     a dialect after the STG machine (lz.construct, jump, papExtend), the vocabulary of a lazy machine (partial
                                                         `Demand` (a stub) and `GRIN` dialects; LZJIT.cpp on LLJIT with   application, construct, jump); LZJIT.cpp:
                                                         the runtime as absoluteSymbols                                    translateModuleToLLVMIR + LLJIT. Pre-LLVM-17 API
    Pylir/Pylir                       268    2024-06     Python AOT compiler on MLIR; Rationales.md: type objects with    the dynamic-object-model argument written down;
                                                         function pointers vs dictionary lookup                            statepoint GC
    google/jsir                       673    2026-10-25  JavaScript as an MLIR dialect that round-trips to source and      the existence proof for a formal syntax dialect
                                                         carries dataflow analyses (constant propagation, taint)           of a dynamic language, with analyses on it
    nebulastream/nautilus             36     2026-10-27  a tracing JIT for C++ with interchangeable backends (bytecode,    the ladder, built: tier 0 runs at once, tier 1
                                                         AsmJit, MLIR/LLVM); tiered by default, tier 1 compiles in the    (MLIR) compiles in the background and takes over
                                                         background and takes over
    jaredhoberock/mlir-closure-dialect 1     2026-06     closure.make with an explicit capture list and a body region;     the closure conversion that makes nix.lambda
                                                         pass to tuple + private func                                      IsolatedFromAbove
    llvm/circt                        2268   2026-10-27  hardware IRs on MLIR                                              not read
    AzizZayed/DialEgg                 32     2026-01     equality saturation over any MLIR dialect with Egglog (CGO 2025)  an e-graph is the limit of a sea of nodes
    Lancern/mlir-gccjit               24     2024-12     MLIR dialect for libgccjit                                        a second JIT route (slow compile, good code)
    llvm/torch-mlir                   1937   2026-10-27  TorchTypes.td: Torch_ListType, DictType, StringType,              dynamically typed values as MLIR types
                                                         OptionalType, UnionType, AnyType, TupleType
    SchrodingerZhu/reussir-lang       19     2025-03     reuse analysis in MLIR (README: one line)                             not applicable: Nix values are shared
    eco-lang/eco-compiler, PragmaTwice/chira, FidelityFramework/Composer  Elm, Scheme and F# on MLIR (36, 10, 73 stars)   not read

Upstream, in LLVM 22 and 23 and not used: the lazy-loading bytecode reader, ExecutionEngine, the transform dialect, the dataflow
framework, the inliner interfaces, `ptr`, `index`, `ub`, `smt`.

## 6. Order

1. Counters as the profiler: a `uint32_t` in `RegionInfo`, incremented in `callLambda` (one `inc` on a line the call reads anyway).
   The plates above used hash maps and exist only under `MLNIX_STATS`.
2. Rung 3 on the counter: the callee cache at `nix.apply` and the index cache at `nix.select`, each behind its A/B.
3. The `//` layering sweep: the constants were set once; merges are 60 to 74% of the attribute cells.
4. Rung 0 consumer: the Confix scan feeding band-at-a-time parsing, once lambdas capture a scope snapshot.
5. Closure conversion (`IsolatedFromAbove` lambdas), then rung 4 on it, with the callee caches as the guards.
