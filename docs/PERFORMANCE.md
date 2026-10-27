# The performance dialect families, examined

"Examine all the families of performance dialects as a potential large speedball of dense
interlocking dialect team-ups." Here is the examination, against what is measured rather than
against what the families promise. The rule stays: a team-up needs a consumer, and it has to win
its interleaved A/B with identical result hashes or it goes in the failures column.

## What the time actually goes to (NixOS toplevel, hot, this branch)

    MLIR generation of ~1.1M ops (uniquing of locations/strings, ~20% of a cold profile;
      only 5.5% of nix.formal, 19% of select, 26% of attrs ops are ever evaluated)
    evalOp dispatch + handlers                     ~10%
    lookup/slot resolution (DenseMap<Value, Slot>)  ~8%
    forcing, callLambda/callFunction, allocation    ~8%
    lexer (was 22%, now ~7% after the tape rewrite)
    everything else: builtins, strings, attrsets (now a layered view), store

Two runs of the same expression touch the same files; cold, 29% of the run was the disk (docs/IO.md).

## Where a run goes now (Mac, demand schedule, nixos-toplevel, after the name properties)

`/usr/bin/sample` at 1 ms, 3 runs, the evaluator thread only (1,326 ms busy a run), every sample charged to the
innermost phase on its stack:

    eval            66.9%   evalOp / force 19.2, lookup / slotMap 15.9, other 11.6, symbols / strings 7.3,
                            malloc / free 6.5, attrsets 6.1
    parse           12.5%   lexer 7.4, malloc / free 2.1, strings 1.6, file I/O 0.9
    store / drv     11.1%   the forcing a derivation does is charged to eval; this is the .drv text, hashing, files
    demand mint      6.8%   MLIR uniquing 1.9 (was 5.6 before the names), op creation 0.7
    file lowering    2.6%

Footprint, 1.57 GB peak: the evaluator's bump arena is 1,147 MB of it, and `MLNIX_STATS` splits it:

    Value        462 MB   14.4M objects of 32 bytes (a tag and a 24-byte union; Nix's Value is 16)
    frames       315 MB    5.4M frames, 58 bytes on average (after an in-place value stopped getting a slot: 465 MB before)
    attrsets     315 MB    1.64M Bindings of 192 bytes on average (24 bytes per attribute: symbol, value, position)
    strings       40 MB, lists 15 MB, contexts 0

and the rest is the retained AST (188 MB: 1.59M nodes at 118 bytes, 5.5 bytes of heap per byte of source, measured with
`malloc_zone_statistics` around the parse), the MLIR ops and the sources.  The reference holds the same evaluation in 626 MB.

## The headline measurement: the interpreter is not the bottleneck on this workload

2M-element fold, min of 3, hot (ns per list element):

                                 construction    fold loop     total
    mlnix (interpreted ops)            17           68          86
    Nix 2.35.4 (C++ Expr walker)       28           68          96

The per-element cost of the interpreted fold is the same 68 ns as the reference C++ walker's, and
constructing the list is twice as fast here. So "interpret ops" is not a tax this evaluator pays
against the reference on expression-shaped work. The remaining 2.2x gap on the toplevel lives in
codegen (work the reference never does), slot resolution, and footprint - not in the op loop.

## Family by family

| family | what it is for | interlock with a lazy expression evaluator | verdict |
|---|---|---|---|
| arith, math, index | scalar math, libm, target-invariant offsets | none: nixpkgs evaluation is attrs/select/apply (its arithmetic folds through `nixnum` devirtualization already) | used only as the lowering target of `join-densify` |
| vector (+ ArmNeon, XeGPU...) | SIMD kernels | a vectorized binary search over the 40k-entry attrsets is the one candidate; `lookup` is ~8% of the profile and big sets are few of the 1.65M | bounded at ~1%; Krapivin/elastic and the lazy index already lost here (COLLECTIONS.md) |
| memref, linalg, affine | arrays of numbers, tiled loops, polyhedral scheduling | no arrays of numbers exist in the workload | no consumer |
| tensor, bufferization | dataflow tensors, ownership | a lazy language with thunks has no tensor dataflow; ownership is the arena's never-free policy (ARC-like freeing would trade speed for the 1.9 GB footprint; measured arena: 72-75% of RSS) | no consumer; footprint is real but the fix is cheaper values/lazy codegen, not a bufferization pass |
| scf, cf | structured control flow | could carry the `if` arms once regions become strict; today `nix.if` evaluates into a frame slot, graph regions make loops implicit | deferred until a strict form exists |
| async + ARC | tasks, ownership of async values | the one async need (prefetch) is a detached helper thread driving io_uring, already built and measured; ARC models exactly the lifetimes our arena deliberately never ends | realized outside the IR, on purpose |
| gpu, spirv, openmp | kernels and parallel targets | single-threaded lazy evaluation; `builtins.map` is not data-parallel work | no consumer |
| quant, shape, shard, sparse | quantization, shape casts, partitioning, sparse tensors | nothing in the workload | no consumer |
| ub (poison) | legality of speculation | speculative forcing of both `if` arms marked poison-on-error would let folds fire before the branch is known; Nix's observable exception order forbids it | rejected on semantics |
| EmitC | emit C++ | a compile-at-runtime side door; ORC below is the same idea without the C++ compile time | no consumer |
| LLVM + ORC / ExecutionEngine | JIT | **see below** | the only "large speedball" shape, and the measurement above bounds it |
| transform | passes as IR | the driver (`nix-prims,nix-fold,nix-dce` greedy loop) could become one transform op per stage with `apply_to` targets; the pipeline is already text, so this is organization, not speed | candidate, neutral on time |
| PDL / PDLL | patterns as data | tried: devirtualization via PDL lost on every count (COMBINATORS.md F-series) | on record as a failure |
| IRDL / ODS + stock passes | declarations as data | **the working team-up of this project**: 105 primops declared with effects/fold/fresh, `nix-prims` devirtualizes, stock `cse`/`canonicalize` are sound because identity is declared, `join-densify` consumes `NixModes` | in production |
| func, builtin | functions and modules | `join.mlir` tests through `func` signatures | used |

## The one large bet, and what it would and would not buy

Lower `nix` (graph regions, implicit laziness) to `nixrt` (an explicit machine: force/thunk/frame
ops, strict operands, slot indices as op properties), lower `nixrt` through arith+func to the LLVM
dialect, and ORC-JIT the hot bodies with the evaluator as the runtime library. That is a dense
interlock (declarations -> analysis -> nixrt -> LLVM -> ORC) and it is the only family combination
with a multiplier in it:

- On compute-shaped scripts (`foldl'`, `genList`, string munging), 68 ns/element interpreted could
  plausibly become 5-15 ns native: 5-10x. The reference would stay at 68.
- On nixpkgs/NixOS evaluation, the profile says arithmetic-class work is noise: the gain would be
  unmeasurable, while the cost (a second evaluator, plus compile latency on ~thousands of lambdas)
  is real. JIT fees are also regressive on 33k created lambdas - a 100 us compile each is 3 s.

So the team-up with the measured headroom is not the JIT. It is:

1. **Deferred codegen.** Generate a lambda's body from the retained AST when it is first called
   (the tape lexer and zero-copy AST exist partly to make retention cheap). 75-85% of generated ops
   are never evaluated; the lever is ~12-17% of a hot run and 300+ MB, and it is a dialect-side
   change (a deferred `nix.expr` region materialized on demand), not a C++ one.
   **Built, behind `MLNIX_DEFER=1`; the default is unchanged** (`docs/SEA-OF-NODES.md`). Measured on
   the two real workloads, identical result hashes: -8.8% to -14.7% wall, -6.8% to -8.7% peak footprint
   (about 130-160 MB), and 89-90% of the eager schedule's ops are never evaluated. It needed the
   dialect (captures and a `body_index` on `nix.lambda`) and C++ (a pool of deferred lambdas, a
   free-name analysis, a mint on first call), so "not a C++ one" was wrong. It costs +7.5% to +9.8% on
   a file whose lambdas are all called; break-even is near 88% called, and the real workloads call 15-18%.
2. **Slot addressing on the ops.** The DenseMap<Value, Slot> probe per operand (~8%) becomes a
   property read or an `nixrt` index once frames are addressed by declaration.
3. **The transform dialect as the composer**, so the driver's stages are inspectable IR.

Both 1 and 2 are prerequisites of the JIT bet anyway: `nixrt` wants strictness and slots, and they
pay before any compiler is wired in. That ordering is the point: build the team-ups that have a
measured consumer today, and the speedball, if it ever pays, arrives already fed.

## On record as failures

PDL devirtualization (lost every count); eager `nix.apply` inlining (the callee is a select, not a
lambda, in nixpkgs' calling idiom); elastic and funnel tables and the lazy index on Bindings (0%);
mmap against read-and-copy (neutral); a segment attribute for `nix.str` (7.08 MB of literal text
in the whole toplevel evaluation: bounded too small); speculating both `if` arms (poison would be
sound, Nix's error order is not).
