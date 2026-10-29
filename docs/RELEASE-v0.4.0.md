# mlnix v0.4.0: the evaluator runs nodes

v0.4.0 evaluates a NixOS system in about half the time Nix 2.35.4 takes on the benchmark host, with prelowering on. Each evaluation step
used to walk MLIR's own structures: a chain of TypeID compares to find the op's kind, the op's operand list, and a hash probe per operand
to find where its value lives. Now the evaluator reads one 64-byte record per value, made once, when the body is indexed. Nothing in the
release changes what an evaluation computes: every output below is byte-identical to Nix's.

## The numbers

Kali (i7-6820HK, 4 cores / 8 threads, Linux under WSL2), `scripts/vs-nix.py --native --demand --runs 7`: the evaluators run in turn, seven
interleaved rounds, and their outputs are compared byte for byte (identical from all, every run below). The tree is `3ffa197`, the code of
this release. Nix, Lix and mlnix were measured in the same run, on the same boot.

With prelowering (`MLNIX_DEFER=1 MLNIX_PREFETCH=auto MLNIX_PRELOWER=1 MLNIX_PRELOWER_THREADS=2`, warm start):

| | Nix 2.35.4 | Lix 2.91.3 | mlnix, demand | mlnix / Nix |
|---|---:|---:|---:|---:|
| nixos-toplevel, min | 3.73 s | 4.40 s | **1.93 s** | **×0.52** |
| nixos-toplevel, median | 4.01 s | 4.47 s | 2.04 s | ×0.51 |
| nixpkgs-73, min | 3.51 s | 4.16 s | **1.81 s** | **×0.52** |
| nixpkgs-73, median | 3.59 s | 4.40 s | 1.88 s | ×0.52 |

Without prelowering (the demand schedule alone, `MLNIX_DEFER=1`):

| | Nix 2.35.4 | mlnix, eager | mlnix, demand | demand / Nix |
|---|---:|---:|---:|---:|
| nixos-toplevel, min | 3.71 s | 2.97 s | 2.58 s | ×0.70 |
| nixpkgs-73, min | 3.48 s | 2.60 s | 2.30 s | ×0.66 |

Peak RSS is still about 1.7 times Nix's: 1081 MB against 630 MB on nixos-toplevel, prelowered.

How it got here. Every row was measured against Nix in the same run, prelowered, on the minimum:

| tree | what it added | nixos-toplevel | ×Nix | nixpkgs-73 | ×Nix |
|---|---|---:|---:|---:|---:|
| `b92a684` | the heap work and Kursive (below) | 2.59 s | ×0.69 | 2.37 s | ×0.68 |
| `77ae13a` | `once` cells, memoised errors | 2.53 s | ×0.69 | 2.28 s | ×0.66 |
| `d03a390` | **the node form** | 2.08 s | ×0.56 | 1.93 s | ×0.55 |
| `d6f4fdd` | fast paths, per-kind evaluation | 1.98 s | ×0.53 | 1.86 s | ×0.53 |
| `3ffa197` | windows, frames inline, devirtualization | 1.93 s | ×0.52 | 1.81 s | ×0.52 |

## Nodes instead of MLIR ops

Before this release, forcing a thunk ran `evalOp(mlir::Operation *)`: a `TypeSwitch` over the op's TypeID, the generated accessors over
its operand segments, and for each operand `slotOf(mlir::Value)`, a direct-mapped cache in front of a hash map, to find the value's region,
slot and promotion. Each of those costs was small in the profile. Together they were most of the gap.

Now every SSA value of an indexed body has a `Node` (`include/Nix/Eval.h`): one cache line, allocated in the arena when the body is
indexed, at an address that never moves.

| field | what it holds |
|---|---|
| `kind`, `how`, `promo`, `flags` | what the op is, what its cell starts as, what the dialect promoted it to, its segments' shape |
| `idx`, `ri` | its frame slot (or none) and the region whose frames hold it |
| `fixed` | a literal's or builtin's one cell, shared by every frame |
| `operands`, `nOperands`, `nDyn` | the records of the values it reads, in operand order |
| `def` | the op (its attributes, names, paths and literals, are still read from it) |
| `prim` | for a continent-dialect op, the primop it runs, found at its first evaluation |
| `eval` | the function that evaluates its kind |

A thunk holds its op's node, and evaluating it is `n->eval(state, n, frame, out)`: one indirect call into a function for that kind,
which saves only the registers that kind needs. An operand is `n->operands[i]`. A lookup is the node's `fixed` cell, or a walk to the
frame of `n->ri` and a read of slot `n->idx`. Closures still hold their `LambdaOp`, so the two JITs are unchanged.

This one change (`d03a390`) took 18% off the Mac's toplevel time and 16% off nixpkgs-73's, with the same 15.1M evaluations, 12.2M cells and
4.57M frames. On Kali, in the same-boot runs above, toplevel went from ×0.69 to ×0.56 of Nix. The profiles had put "dispatch" at about 1%.
That figure was wrong because the cost never sat in one place. It was spread over inlined accessors, cache misses on the operation
storage and the use lists, and the hash probes.

Following the node form:

- **Indexing (`83ae9b7`).** An operand defined in its own block is found in a scratch map the size of the blocks being indexed. Only a
  value read from somewhere else goes into the map of every value: a nested body, a lambda's capture list, or every value when a JIT is
  on. That map went from 613k entries to 13.6k a toplevel run, and its inserts and probes had been 3% of the evaluator thread in cache
  misses.
- **Fast paths (`132e80c`, `e34fc21`).** `lookupImpl`, `forceValue`, `newFrame` and `stackFrameOK` have their common case inline: a filled
  slot, a value that is already one, a bump of the arena, a cached verdict. The rest is out of line. As single functions they saved and
  restored every callee-saved register on every call for the sake of their cold paths (Mac: -4%, then -2.4%).
- **Per-kind evaluation (`d6f4fdd`).** The switch saved, at every entry, the registers of its biggest case. The node's own function
  doesn't.
- **`makeCell` (`27a7f01`)** is thunk creation only. Fixed cells, evaluation-now with its exception handling, and the census are functions
  of their own. Timing-neutral, kept for its shape.

## Promotions: `once`

`NixDialect::promotionOf` decides what cell each value gets (`docs/SEA-OF-NODES.md`, `test/mlir/promotions.mlir`). The new promotion
`once` applies to a value with exactly one use, which is lazy and in the same body. Its consumer runs once per frame and makes the cell
then, so the frame keeps no slot for it (`533df29`). Frame storage on nixos-toplevel halved, from 256.6 MB to 127.9 MB: slots went from
22.9M to 6.85M and the arena from 921 MB to 796 MB, with the same 12.2M cells.

The first version of the rule caused an explosion: evaluations went from 15.1M to 22.5M and cells from 12.2M to 33.2M, yet the outputs
stayed identical. The cause was a lambda's operands. They are its body's *capture list*, and a deferred body's own uses don't exist until
the body is minted. So a captured value looked single-use, lost its slot, and was re-evaluated by every nested read. A use by an op with
regions now never counts as the one consumer, and the test pins that case.

## Errors are memoised, as Nix 2.34 does

A thunk whose evaluation throws an evaluation error now keeps it (`VType::Failed`). Forcing it again throws a fresh copy of that error,
in the state it has reached by then: the first throw may still be gathering traces on its way out. The thunk isn't evaluated again
(`533df29`). Before, `eval-okay-tryeval-failed-thunk-reeval` passed only because a frame slot happened to keep a trace's result. Now
`eval-fail-memoised-error-trace-not-mutated` reports Nix's trace structure: *forcing d*, *forcing b*, and not *forcing c*.

## Less heap, fewer copies

- **Strings that already exist are windows.** The names `mapAttrs`, `attrNames` and `zipAttrsWith` hand out point at the symbol table's
  own bytes. The pieces and groups of `match` and `split` point at their input when it is an arena string (`9b6c3f9`). `mapAttrs` alone
  had been 1.5% of the evaluator thread in `memmove`, copying names its callbacks mostly never read.
- **Derivations.** The ATerm text is streamed into SHA-256 instead of being built whole, so evaluator heap bytes fell from about 443 MB
  to about 152 MB a toplevel run (`630ae24`). The hash context lives inside the sink (`11a9568`). A derivation's containers are sorted rows
  rather than trees (`b92a684`). String contexts are read where they lie, interned, instead of being copied into `std::set`s (`7144cad`,
  `aa77847`). Evaluator `malloc` calls fell from 3.61M to about 1.04M a toplevel run.
- **No `std::regex` (`7c4be23`, `37120b5`).** `builtins.match` and `builtins.split` run on Kursive (`include/Composite/Kursive.h`), a step
  program with libstdc++'s exact `std::regex::extended` executor semantics. Nix's libstdc++ is built strict, so only `.[\()*+?{|^$` may be
  escaped, and Kursive matches that too. A `(pattern, input)` pair seen before is answered from a memo (`b84d4ff`).
  `scripts/kursive-check.cc` ran 342,715 match and split checks on Kali against libstdc++, plus random patterns compared on their error
  verdicts: 0 differences.
- **Devirtualization (`3ffa197`).** A walk that stops only at `nix.apply` replaces the generic pattern driver, which was 1.5% of the
  evaluator thread for a rewrite that costs 0.04%.

Earlier in this release's range, the TrikeShed algebra under the evaluator (`include/Composite`) lost its last standard headers. No
`std::vector`, `std::deque` or `std::list` remains outside it, and sorting, uniquing and merging rows are `Composite/Rows.h` folds.

## Measured and not kept

- **A four-way set-associative slot cache (`113ceb0`, reverted in `30d9d47`).** It cut hash-map answers by 65% but showed no gain on Kali.
  The node form later removed the lookup it was tuning.
- **Whole-evaluator PGO (`990d7cd`).** -3% on the Mac. It can't be measured on Kali until `libclang-rt-22-dev` is installed there.
- **Formals bound at the call.** The call already finds each formal's attribute, so it could fill the formal's frame slot, as Nix binds
  it. This was tried both with and without a `bound` promotion. Eleven interleaved rounds showed no gain (equal minimums, medians within
  noise), so it isn't in the tree.

## What is on by default

The node form, `once` cells, memoised errors, windows and Kursive are always on. The demand schedule (`MLNIX_DEFER=1`) and prelowering
(`MLNIX_PRELOWER=1` with `MLNIX_PREFETCH=auto`, or `MLNIX_PRELOWER_LIST=file`) are opt-in, as in v0.3.0. Prelowering needs a previous run
of the same invocation to record its file list: a cold start gets nothing from it.

## Gates, on Kali, for this tree (`3ffa197`)

- Build clean: clang 22, Release.
- Nix's language tests: 487/487 semantic on the eager and the demand schedule (229/487 exact, stderr included).
- MLIR tests: 15 passed, 0 failed (4 run lines skipped: `cse-dynamic-ops`).
- Primops: 105 registered, 105 declared.
- difftest: 72/72 identical to Nix 2.35.4 and 71/72 identical to Lix 2.91.3, on both schedules.
- The algebra: its 14 pure headers compile alone, with no standard headers, under clang 22 and g++ 16 (`scripts/hot-check.sh`). Its
  checks pass under AddressSanitizer and UndefinedBehaviorSanitizer with g++ 16. Clang's sanitizer runtime is not installed on the host.

## Reproduce

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++-22 \
          -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm -DMLIR_DIR=/usr/lib/llvm-22/lib/cmake/mlir
    cmake --build build --target mlnix mlnix-opt
    # once, to record the files an evaluation reads; then the timed runs
    MLNIX_DEFER=1 MLNIX_PREFETCH=auto build/bin/mlnix instantiate --readonly-mode --eval --strict \
        test/nixos-toplevel.nix --arg nixpkgs ./.cache/nixpkgs > /dev/null
    MLNIX_PREFETCH=auto MLNIX_PRELOWER=1 MLNIX_PRELOWER_THREADS=2 python3 scripts/vs-nix.py --native --demand --runs 7 \
        --workload nixos-toplevel --mlnix $PWD/build/bin/mlnix --ref "Nix 2.35.4=$(which nix-instantiate)"
