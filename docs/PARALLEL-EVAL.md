# Parallel evaluation: what it would take, and what it could buy

Written 2026-10-29 as the costed option beside the others (thinner IR, JIT). Nothing here is built. The frontend already runs on other threads
(`docs/PRELOAD-PIPELINE.md`); this is about the evaluator itself.

## What it could buy (measured)

- **nixpkgs-73** (`MLNIX_STATS`, epochs): 73 attributes, 10.4M evalOps; median attribute 3.7k, p90 617k, largest 15.7% of the work, the first
  ten attributes 8.8%. Most attributes are tiny because an earlier one already forced what they share. Four workers on independent attributes could
  at best finish in max(25%, 15.7%) of the time; shared thunks that a worker must wait for take much of that back, so a realistic figure is a
  fraction of it (say 1.5 to 2.5x, unmeasured).
- **nixos-toplevel** is one attribute (the module-system fixpoint): no attribute-level parallelism; only forcing independent subgraphs inside it
  would help, which is speculation. Expect about 1.0 to 1.2x.
- The evaluator thread is 91% of its own cycles once the frontend is pipelined, with a flat profile: 29% useful, 36% back-end stalls, 22%
  front-end, 13% discarded (Mac counters; the category order is inferred). More cores do not make any of those faster per thread.

## What every thread would share, and what each needs

| shared state (`EvalState`) | hazard | fix |
|---|---|---|
| `Arena alloc` (values 24 B, frames, rows) | bump pointer | one arena a thread over a shared slab source; nothing is freed, so pointers stay valid across threads |
| a `Value` cell being forced (`type` Thunk -> Blackhole -> result) | two threads force one cell | CAS the tag Thunk -> Blackhole with an owner; a thread that meets a Blackhole it does not own waits; the cycle check (`InfiniteRecursionError`) must then be by owner, not by tag |
| `symbols` (`SymbolTable`: StringMap + names series) | `create` on dynamic keys and formals | lock on create, lock-free reads of an append-only names chunk list |
| `slotMap`, `slotStore`, the `infoOf`/`slotOf` direct-mapped caches | indexRegion writes while others read | slots immutable once a region is indexed (index under a lock, publish with release); caches thread-local |
| `regionInfos`, `RegionInfo` fields (`formalSyms`, `selShape`, `calls`, `everRan`) | lazy, written on first call | the same publish rule; counters are stats-only and per-thread or off |
| `constCache`, `fileEvalCache`, `scopedImportCache`, `srcToStore`, `pools`, `origins` | maps mutated at import and mint time | a lock (cold), or the prelowering hand-off for files |
| lambda minting (`mintLambda`, `lowerToMLIR`) | parse + `genExpr` + indexRegion on the evaluator thread | already thread-capable (the prelowering helpers run `genExpr` with a multithreaded MLIR context); the indexing step takes the lock above |
| `callDepth`, `tryLevel`, `lastThunk`, `freeFrames`, error traces | per-evaluation state | thread-local |
| `Bindings::merged` and other static counters, `printTrace` | benign counters, interleaved output | per-thread; trace ordering is nondeterministic by nature |
| `store` (writes `.drv` files, hashes), `nixprefetch` recorder | file and map writes | the store's own lock; the recorder is off in parallel mode |
| `ScalarJIT`, `LazyJIT` (opt-in) | native code and caches | off in parallel mode |
| `tryEval`, `builtins.trace`, `throw` | a failure on one thread while others speculate | an error cancels only its own epoch; evaluation stays pure, so results do not depend on order |

Purity is what makes this sound: two threads that evaluate the same thunk compute the same value, so a lost race costs time, not correctness
(GHC-style lazy blackholing). The delicate parts are the Blackhole ownership rule and the publication order of a cell's payload before its tag.

## Staged plan, each stage gated like the others

1. **Atomic tags, one thread.** Make forcing CAS-based and measure what the atomics cost a single-threaded run (this is the floor of the price).
2. **Per-thread arenas, caches and counters**, still one worker; the A/B against the current build must show the cost of the indirection.
3. **Attribute-level driver parallelism** (the epochs above: list elements of the top-level result, `getDerivations`), two to four workers,
   measured on nixpkgs-73 and the language suite with outputs byte-identical.
4. Only if stage 3 pays: parallel forcing of independent subgraphs inside one attribute (`map`, `mapAttrs`, `deepSeq`), which is where
   nixos-toplevel could gain at all.

## The honest comparison

Against the thinner IR (the sub-levers measured nil) and the JIT (partial tiers lost), this is the only option with a measured ceiling above
twenty percent, and only on nixpkgs-73-style workloads. Against a process-level split (what `nix-eval-jobs` does), it shares the shared prefix once
instead of once a process. Stage 1 is the cheap experiment that says whether the rest is affordable.
