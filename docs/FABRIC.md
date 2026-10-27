# The dialect fabric

mlnix evaluates Nix by interpreting MLIR. A Nix file is lowered into ops of the `nix` dialect, the evaluator walks those ops, and the ops,
their effects and their strictness are declared in ODS and IRDL, with a pass pipeline and FileCheck tests around them. What is not MLIR
is the interpreter itself, the values it makes, the front end and the store: they are C++. Nothing is compiled (no LLVM lowering, no
ExecutionEngine): the sea of nodes here is a schedule for *minting* IR (`docs/SEA-OF-NODES.md`), and the interpreter is the only
executor. This file tracks the move of logic from that C++ into dialects, passes, interfaces and declarations, what that bought
(measured), and what is next. Numbers are from `scripts/bench.py` on the NixOS toplevel and 73-package evaluations; nothing here is
aspirational unless it says so.

## What is MLIR here, and what is C++

The IR of a small function, as `mlnix emit-mlir -E 'let f = x: { a = x + 1; b = [ x 2 ]; }; in (f 2).a'` prints it (`+` is
`nix.concat_strings`, the op that adds numbers and joins strings alike):

    nix.expr @expr1 attributes {base_dir = "..."} {
      %0 = nix.lambda attributes {arg_name = "x", name = "f"} {
      ^bb0(%arg0: !nix.value):
        %4 = nix.int 1
        %5 = nix.concat_strings %arg0, %4
        %6 = nix.int 2
        %7 = nix.list[%arg0, %6]
        %8 = nix.attrs ["a", "b"](%5, %7)
        nix.return %8
      }
      %1 = nix.int 2
      %2 = nix.apply %0(%1)
      %3 = nix.select %2 ["a"]
      nix.return %3
    }

Piped into `mlnix-opt` (that is `MlirOptMain`: parse, verify, print) it round-trips. The NixOS toplevel lowers to 1,095,819 such ops
on the eager schedule and 619,842 on the demand schedule; 121,687 and 121,680 of them are ever evaluated. What the running program does
with MLIR, checked against the code at 415872c:

    declares in ODS/IRDL   28 ops, 1 type (`!nix.value`) and 1 interface (`NixEvalOpInterface`) in NixBase.td and NixOps.td; 105 primops
                           in 24 dialects in NixPrims.irdl.mlir, defined at load time and compared with the runtime registry by
                           check-prims.py (105 registered, 105 declared)
    evaluates the IR       `EvalState::evalOp` is a `llvm::TypeSwitch<Operation *>` of 25 cases (lib/Eval/Eval.cpp:1347); `nix.expr`,
                           `nix.return` and `nix.lambda` are handled around it. Every other op, that is every primop op, goes to
                           `NixEvalOpInterface`, attached from outside as one fallback model (Eval.cpp:1508, lib/Eval/EvalModels.cpp).
                           Primop ops are 0.9% of the ops a demand run lowers (5,324 of 619,842)
    optimizes the IR       `mlir::PassManager` from pass-pipeline text (`MLNIX_PIPELINE`, default `nix-prims`), run on each file's
                           `nix.expr`, which is IsolatedFromAbove; `nix.expr` and `nix.lambda` are graph regions (RegionKindInterface)
    tests the IR           14 FileCheck tests on the Mac; on kali 13, with the 4 run lines of `cse-dynamic-ops` skipped (LLVM 22's `cse`
                           cannot merge IRDL ops)
    does not verify it     the evaluator turns the verifier off (`pm->enableVerifier(false)`, Eval.cpp:1935) and calls `verify` nowhere,
                           so on the evaluation path the IR is trusted; `mlnix-opt` and the FileCheck tests do verify. A deferred
                           lambda is an empty shell that `SingleBlock` would refuse (NixOps.td)
    does not use           ExecutionEngine, ORC, the LLVM dialect, the transform dialect, PDL, the dataflow framework, Liveness, the
                           inliner and call interfaces: 0 references in lib/, include/, tools/. Bytecode: the property hooks exist
                           (NixBase.td); nothing reads or writes a bytecode file
    avoids on purpose      MLIR locations and uniqued attributes on the hot path: a position is a word in a property (`nixfe::Pos`), a
                           name a `nixfe::Name` property (rung 3 below); uniquing was 26% of the first profile

Where the code is (code lines, comments and blanks not counted: `python3 scripts/cxx-lines.py --rev 415872c`):

    include/NixDialect, lib/Dialect      C++    682     declarations (ODS, IRDL)            923
    include/Composite, lib/Composite     C++    419     declarations (join, not run)         61
    include/Nix (headers)                C++  1,329
    lib/Eval                             C++  4,911
    lib/Frontend                         C++  2,601
    lib/Store                            C++  2,197
    tools                                C++  1,084
    total                                C++ 13,223                                          984

Declarations are 6.9% of the lines that define the system. "Move most code into dialects" has barely started, and from this commit the
C++ total only goes down (`scripts/cxx-lines.py --base REV --ratchet` exits 1 unless it fell).

The demand schedule (`MLNIX_DEFER=1`) changes when ops exist, not what the IR is: a deferred `nix.lambda` is lowered as a shell with
`captures` operands and a `body_index` (`file j row`, a row of a per-file pool that retains the syntax tree); its body region is minted on
the first call by the same generator that lowers eagerly. The pool is C++ beside the IR: it is not in the module, so it cannot be
printed, verified or serialized. That is the one place where the IR is incomplete by design.

## The treeless design, built

Sam H. Smith, [*Parsing without ASTs and Optimizing with Sea of Nodes*](https://www.youtube.com/watch?v=NxiKlnUtyio) (Better Software
Conference 2025; the questions start at [1:00:16](https://www.youtube.com/watch?v=NxiKlnUtyio&t=3616s)), is the design this tree is
measured against. Its claim: a compiler can parse straight into the graph with no tree between the text and the nodes, and optimize the
graph while it is built. Each mechanism of the talk, and what is here:

- **Group characters, keep no token array** ([3:30](https://www.youtube.com/watch?v=NxiKlnUtyio&t=210s)): `peek` gives an enum and a
  slice of the file, `consume` moves on. Here: `Parser::peek` over a ring of four 32-byte tokens, none kept (Parser.cpp:579-602). Have it.
- **Rewind to a save point when a later token changes what an earlier one meant**
  ([12:31](https://www.youtube.com/watch?v=NxiKlnUtyio&t=751s)). Here there is no rewind: Nix tells `{ a, b }: x` from `{ a = 1; }`
  within three tokens (`looksLikeFormals`, Parser.cpp:641-650). The talk prices it: the tokenizer runs more
  ([69:01](https://www.youtube.com/watch?v=NxiKlnUtyio&t=4141s)). Not needed.
- **Parse straight into the graph; no tree.** Built (`lib/Frontend/Parser.cpp`, 4555421). One parser in three modes: `Gen` lowers to the
  nix dialect as it reads, resolving each name on the spot; `Skip` builds nothing and learns a lambda's free names; `Show` prints
  `--parse`. `AST.h`, `MLIRGen.cpp`, `Printer.cpp` and the `FreeVars` walk are gone (the tree's 1,185 code lines; the front end is 238
  code lines smaller than with them, 13,117 -> 12,879). The tree weighed 5.4 to 5.5 bytes per byte of source (720 MB parsed against
  161 MB scanned over the 39,646 files of nixpkgs); the toplevel's peak RSS is 9 to 10% lower without it (kali, same host, 9 interleaved
  runs: 1.577 -> 1.414 GB demand, 1.708 -> 1.535 GB eager).
- **Peepholes and value numbering when the node is made, while it is still in L1**
  ([35:01](https://www.youtube.com/watch?v=NxiKlnUtyio&t=2101s), [36:31](https://www.youtube.com/watch?v=NxiKlnUtyio&t=2191s),
  [41:32](https://www.youtube.com/watch?v=NxiKlnUtyio&t=2492s)). Here a base name resolves when its op is made (`baseRef`,
  MLIRGen.cpp:368, 515), but devirtualization (`nix-prims`) is a second walk over the lowered file; on the demand schedule it runs
  directly on a minted body (Eval.cpp:1948). There is no value numbering: stock `cse` as a pass costs +7.1% / +5.4% (below), because a
  file is lowered once; made at creation, where the table is hot and there is no second pass, it has not been measured. Partly.
- **A variable is a name bound to a node, and the scope is a stack** ([44:00](https://www.youtube.com/watch?v=NxiKlnUtyio&t=2640s)).
  Built: a scope is a run of rows of one bindings Cursor (`BindCol` in `TrikeShed.td`: name, hash, value), `first j count`, compared
  by hash before bytes; a lambda's free names are noted as its skim reads them, at the edge of its scope.
- **Inline or defer by jumping into the source and parsing it again** ([28:31](https://www.youtube.com/watch?v=NxiKlnUtyio&t=1711s)).
  Built: a deferred lambda is `file j row`, the row is where it starts (`PoolCol` in `TrikeShed.td`), and its mint parses it again
  from there. A skim records where each lambda inside it ends and what it reads, so the mint jumps over them. The expression of a
  whole source, which its importer calls, is lowered with its body at the import (9729014): its body is parsed once, not skimmed
  and parsed again (toplevel demand, `MLNIX_STATS`: minted on demand 315 ms -> 31 ms).
- **A prepass over the global declarations, so that later work knows them**
  ([63:00](https://www.youtube.com/watch?v=NxiKlnUtyio&t=3780s)). Built and consumed: the Confix scan finds the bands and the
  statements that end in them (`NixSyntax.td`, layers 0 and 1), and the parser reads the names a `let`, a `rec` set or a formals list
  binds from where its statements start (layer 2) before it reaches the first value. The scan runs where the parser asks, over one
  band at a time; run ahead over a whole source on a thread (9729014, 745f861) it covered four times the bytes anything read
  (24.3% of the toplevel's are inside a band whose heads are read).
- **Treeless parsing and the sea of nodes are independent** ([92:31](https://www.youtube.com/watch?v=NxiKlnUtyio&t=5551s)); the talk
  calls the first the front end and the second the back end ([95:02](https://www.youtube.com/watch?v=NxiKlnUtyio&t=5702s)). Here the back
  end exists (graph regions of `nix` ops) with a tree front end.

Not applicable: global code motion, phi nodes, the dominator tree. Nix has no control-flow graph to schedule; `if` is a lazy expression
and the schedule is demand.

What building it asks of Nix, beyond the three obstacles of rung 4 below (a band is not opaque, a deferred body needs its scope, an error
in a body nobody enters must still be reported): a recursive binding (`let`, `rec`) uses a name before it is defined, which is this
language's forward-knowledge problem. A graph region allows the use before the definition, but the builder needs a value to make the use
with, so it makes a placeholder and replaces it when the definition appears (the talk does that for loops, [56:02](https://www.youtube.com/watch?v=NxiKlnUtyio&t=3362s)),
or it skims the binding heads first. `--parse` and `mlnix-parse` need a tree-shaped consumer: a parser written against a sink serves both,
the printer one sink and the IR builder the other.

## What exists

The core dialect `nix` (ODS: lambda, apply, attrs, list, select, if, with, ...) and
24 *primop dialects* in 6 macro scopes, all 105 base-environment primops as ops:

    scope  dialects
    val    nixnum nixbit nixty nixrefl
    coll   nixlist nixlistfn nixattr nixattrfn
    text   nixstr nixver nixre nixctx
    io     nixpath nixfs nixstore nixhash
    meta   nixjson nixtoml nixxml nixflake
    ctl    nixctl nixerr nixtrace nixload

They are **not TableGen**. They are declared once, as data, in
`include/NixDialect/NixPrims.irdl.mlir` (IRDL), and defined at load time by the
generic loader `lib/Dialect/NixPrimDialects.cpp`, which names no op. How, what failed
and what it cost: `docs/COMBINATORS.md`. What follows from the declaration:

- **Verification**: the stock IRDL verifier checks arity, in `mlnix-opt` and the FileCheck tests; the evaluator never runs it (above).
  `mlnix primops` (the runtime registry) is compared with the declaration by `scripts/check-prims.py`.
- **Effects**: `nix.fx` per op becomes a `MemoryEffectOpInterface` model
  (`Pure`, `MemRead<NixFS|NixEnv>`, `MemWrite<NixTrace|NixStore>`). The stock `-cse`
  pass is therefore sound on Nix IR: pure primops merge, ops that may run user code
  or trace do not (`test/mlir/effects.mlir`, `declaration.mlir`).
- **Folding**: one generic pattern serves every `nix.fold` primop by calling the
  evaluator's own implementation; a call that would throw is left alone, so errors keep
  their position and trace.
- **Evaluation**: `NixEvalOpInterface` is attached from outside as one fallback model
  (`lib/Eval/EvalModels.cpp`). The dialects know nothing about the evaluator; a JIT or
  symbolic executor can attach its own model the same way.
- **Devirtualization** (`nix-prims`): `builtins.length x`, `__add a b`, `map f l`
  become `nixlist.length(x)`, `nixnum.add(a, b)`, `nixlistfn.map(f, l)`. A single walk
  (`walkAndApplyPatterns`), not the greedy fixpoint driver.
- **Constants**: `true`, `false`, `null` are `nix.bool` / `nix.null` (ConstantLike), so
  they fold and feed folded primops.
- **Identity**: `nix.fresh` (primops) and `NixFreshVal` (core lists, attrs, lambdas,
  `//`, `++`) declare an allocation, so stock `cse` cannot merge values whose identity
  is observable (`test/mlir/identity.mlir`; 466/466 with `cse` in the pipeline).
- **Pipeline**: the optimizer is MLIR pass-pipeline text, not an options struct:
  `MLNIX_PIPELINE='nix-prims,cse'` (default `nix-prims`). Passes: `nix-prims`,
  `nix-fold`, `nix-dce`, pipeline `nix-simplify`, plus any stock pass by name. Write a
  bare list: `any(...)` / `builtin.module(...)` wrappers silently nest and do nothing.
- **Replaceable**: `MLNIX_PRIMS_IRDL=file` swaps the declaration without a rebuild.

## Tests (each layer can fail)

    python3 scripts/run-lang-tests.py   upstream lang suite: 473/473 semantic, 215 exact (kali, 6344b5c82)
    python3 scripts/difftest.py         72 expressions identical to Nix 2.35.4 (71 to Lix 2.91.3)
    python3 scripts/run-mlir-tests.py   FileCheck tests of the dialects/passes: 14 on the Mac
    python3 scripts/check-prims.py      declarations == runtime registry
    python3 scripts/ab.py A B           interleaved A/B (two envs or two binaries)
    python3 scripts/startup-bench.py    process start-up cost of two binaries
    python3 scripts/bench.py            wall-clock, peak RSS, result hash

## Measured

`scripts/bench.py`, min of 3 runs, NixOS toplevel / 73 nixpkgs attrs. Every row
has the identical result hash (same `.drv` paths), 466/466 on the lang suite,
60/60 against Nix 2.35.4.

    change                                          toplevel    nixpkgs-73   peak RSS
    v0.1.0 (nix-simplify = greedy driver per file)    4.59 s      4.91 s     2554 MB
    --no-opt                                          4.52 s      3.76 s     2549 MB
    + devirtualization to continent dialects          4.25 s      3.63 s     2509 MB
    + static select/has_attr paths as attributes      4.12 s      3.53 s     2453 MB
    + ctx.disableMultithreading()                     3.82 s      3.38 s     2344 MB
    + literals without locations, filename attr once  3.59 s      3.13 s     2349 MB
    + Symbols keyed by StringAttr; CommonCrypto SHA   3.48 s      2.97 s     2378 MB
    + intersectAttrs walks the smaller set            3.38 s      2.80 s     2359 MB
    + operands evaluated in place (NixModes)          3.41 s      2.82 s     1993 MB
    + lexer: first-character dispatch                 3.02 s      2.50 s     1983 MB
    + tape lexer (tokens are segments)                2.92 s      2.43 s     2026 MB
    + `//` as a layered view over a big set           2.92 s      2.40 s     1945 MB

Timings are min-of-3 `bench.py` runs on the machine of the day and move a few percent between
sessions; each row's own interleaved A/B is in the commit message. Peak RSS counts mapped
file pages since `nixfe::Source`; peak *footprint* is the number to compare for memory.

The last row is an algorithm fix, not an MLIR change: one builtin made 90-96% of all
attrset lookups (`docs/COLLECTIONS.md`).

Optional pipeline stages, interleaved A/B against the default `nix-prims` (same
binary, identical result hashes), NixOS toplevel / 73 attrs:

    nix-prims,cse            +7.1%  / +5.4%
    nix-prims,canonicalize  +19.6%  / +16.6%
    nix-simplify (fold+dce)  +9.8%  / +10.4%

None pays: each file is lowered and evaluated once, so a pass has no second run to
amortize against (`docs/COMBINATORS.md`, F17). Only devirtualization is on by default.
Devirtualization is one `walkAndApplyPatterns` walk; the greedy rewriter is a fixpoint
machine, use it only where a fixpoint is needed.

### The MLIR tax, and what it was made of

The first profile of the evaluator thread (busy samples only) put **26%** in
MLIR attribute/location uniquing. Three causes, each a one-spot fix:

1. Multithreading enabled: every uniquer access is sharded, locked and
   thread-cached. The evaluator is single-threaded. (-7%)
2. A `FileLineColLoc` per op, built from the file *name* so the path was
   re-hashed each time; literals, lists and returns cannot fail and now carry no
   location, and the few consumers that report an operand's position (`with`
   scopes, computed attribute names, interpolation parts) get it back
   explicitly. (-6%)
3. 48% of all `nix.str` ops existed only to name an attribute in a select path:
   structural constants as ops instead of attributes. (-16% of all ops)

After 1-2 the uniquing share was 13.6%. The remaining profile (self time, busy):
evalOp/force/call 17.5%, `memcmp`/`strlen` 15% (mostly symbol re-interning, fixed
after this profile), uniquing 13.6%, lexer/parser 10.8%, `lookup` 10.6%,
malloc 6%, SHA-256 4.7% (fixed after this profile).

`MLNIX_STATS=1` prints the op histogram of everything an evaluation lowers. For
the NixOS toplevel, now 1.10M ops (was 1.30M): `nix.str` 20%, `nix.formal` 19%,
`nix.select` 13%, `nix.apply` 11%, `nix.attrs` 11%, `nix.with_var` 5%.
Continent ops are 0.68% (most applications in nixpkgs are of user lambdas).

## What this does not buy

Arithmetic and `if` are a rounding error in this workload (`nix.int` 0.5%,
`nix.if` < 0.3%). `arith` and `scf` would be ornamental here, and the rungs
below are ordered by the profile, not by which dialects are fashionable.

## Next rungs (by measured weight)

Fresh profile of the NixOS toplevel run (2 s main-thread sample, 1449 busy samples) and
`/usr/bin/time -l`; these replace the earlier numbers in this list.

    MLIR uniquing (locations 6.2%, string attrs 3.9%, rest 8%)   18.2%
    lexer                                                        10.4%
    memcmp (string attr equality, StringMap)                      9.3%
    kernel time: 151,567 page reclaims over a 2.42 GB footprint   10%  (0.36 s of 3.46 s)
    EvalState::lookup (operand -> Value*, a hash probe)            8.6%
    malloc/free                                                    5.7%
    Bindings::get                                    was 5.9%, now about 1% (see COLLECTIONS.md)

1. Memory volume. The arena never frees, so 2.4 GB is touched fresh and the kernel
   charges about 10% of the run for it. Arena by kind (NixOS): Values 842 MB (26.3M at
   32 B), frames 465 MB, attrsets 404 MB; MLIR IR is another 686 MB. `//` alone is 65-81%
   of attrset memory (264 MB / 514 MB copied; 374 / 773 calls with a 256+ entry left
   operand are 56% / 67% of that). A persistent or layered attribute set is the one place
   a tree structure could pay (`docs/COLLECTIONS.md`, section 6); not built.
   The 24-byte `Value` is built: a tag and a 32-bit count (the length of a string, a path or a list), then two words.
   Max RSS of the toplevel 1,696 -> 1,580 MB (-6.7%, demand) and 1,833 -> 1,705 MB (-7.0%, eager); wall within the noise
   of 13 interleaved runs on the Mac (+0.4% / 0.0% demand, -0.5% / -0.8% eager on toplevel / nixpkgs-73), identical hashes.
   Where the rest is (toplevel, demand, `MLNIX_STATS`, before it): the evaluator's arena 1,147 MB = Values 461 MB (14.4M),
   attribute arrays 315 MB (1.64M sets, 13M attributes at 24 B each), frames 315 MB (5.39M, half of their 28.6M slots ever
   filled), strings 39 MB, list cells 14 MB; the syntax trees 186 MB (33.8 MB of source); malloc 287 MB (1.27M blocks: the IR).
   What is done is the first touch of those pages, a page fault on the one thread that evaluates. The arena
   (`include/Nix/Arena.h`) takes 4 MiB slabs in order from reserved ranges of address space, and a helper thread
   populates the next slab while the evaluator fills the current one. Mac wall -2.1% / -3.1% (demand), -3.5% / -2.7%
   (eager), identical hashes. The carved arena alone, helper off, loses (+2.3% / +2.0% demand, +1.7% / +0.7% eager,
   against malloc slabs): the helper is what pays. On Linux the ranges are 2 MiB aligned and `MADV_HUGEPAGE`, which takes
   the minor faults of a toplevel run from 87,492 to 7,875. Kali, against the generation before, 7 interleaved runs,
   min / median: demand -6.5% / -12.2% (toplevel) and -12.1% / -21.1% (nixpkgs-73), eager -5.0% / -17.1% and
   -6.8% / -8.3%; the helper off against on, same build, demand: -3.9% / -7.6% (min). The medians overstate it: the old arm's
   median sits 11-16% above its min in four of four cells, the new arm's 1-10%. Why that host spreads the old arena's runs
   more is not measured; the min-based figures are the ones to expect.
2. A lowering to a runtime dialect with *resolved addressing*: operand
   (depth, slot) and Symbol ids as attributes, so `lookup` (8.6%) and the `TypeSwitch`
   chain in `evalOp` disappear. Progressive lowering `nix + continents -> nixrt`.
   Two cheaper forms of the same idea were measured and lose, so `lookup` is not a hash-probe problem:
   the slot of a value kept in a `slot` property of its defining op, found through a per-class offset
   table (branch `exp/slot-prop`): +0.3% / +2.1% (demand) and +3.2% / +2.1% (eager) wall on toplevel /
   nixpkgs-73, identical hashes; and `operand()` / `evalTail()` handing the slot they already found to
   `lookup()` instead of probing twice: +2.5% / +0.4% (demand; CPU -0.3% / +0.6%). The cost that is
   left is more likely the memory behind the slot (frames 465 MB, Values 842 MB, the first item of this
   list); that is an inference from the two results, not a measurement.
   A third form lost too (branch `exp/lookup-fast`): `lookup()` as an inline probe-and-walk with its first-touch path out of line,
   and `operand()` / `evalTail()` probing once instead of twice. Demand +3.3% / +1.3%, eager +1.5% / +0.7% wall (toplevel /
   nixpkgs-73, 17 interleaved runs, identical hashes). What the counts say about the ceiling (toplevel, demand): 20.9M `lookup`,
   9.9M `operand` and 7.1M `evalTail` calls, about 38M probes of `slotMap`, for the ~190 ms the line profile charges them: about 5 ns
   a call. The table is mostly cache-resident, so even a free probe is worth a few percent, and the 15.4M `evalOp` and 30.8M
   `forceValue` calls are 9 ns and 1.6 ns each.
3. Locations (done): 6.2% was FileLineColRange uniquing, one per op; sampled again on the demand
   schedule it was 143 of 269 ms of uniquing per run. A position is now a 64-bit word in the op's
   `pos` property (`include/Nix/Pos.h`, `docs/COMPOSITE.md`): wall -9.2% / -8.7% (demand) and
   -11.8% / -13.0% (eager) on toplevel / nixpkgs-73 on the Mac, identical hashes; on kali a few percent (min of N: demand
   -1.5% to -3.2%, eager -5.6%). What is left of the uniquing
   in the same profile is `StringAttr` (63 ms) and `ArrayAttr` (43 ms): names, and the arrays of them.
   Names (done): `nixfe::Name`, a pointer and a length, is the property of the ops that carry text, with the evaluator's Symbol
   cached in the op (`docs/COMPOSITE.md`): wall -6.6% / -6.8% (demand), -8.8% / -8.3% (eager) on the Mac, -5.6% / -5.2% and
   -13.3% / -7.1% on kali. Uniquing inside mint went from 5.6% to 1.9% of the evaluator thread (20 ms a run: the attributes
   of lambdas, `body_index`, integer literals). Not converted, on purpose: a lambda's `arg_name` / `name` / `formals`, because
   a property is not an inherent attribute and the custom syntax of `nix.lambda` (`attributes {arg_name = "x"}`) would change
   for about one percent.
   The tree (done): the AST owns no string either (`docs/COMPOSITE.md`): the corpus parses in 0.863 s against 1.012 s (-14.7%),
   in situ -2.1% / -2.4% (demand) and -2.6% / -1.4% (eager), footprint -0.9% to -2.4%.
4. Dead bands (measured, not built). Which bands of the source does an evaluation never enter? `MLNIX_TRACE_POS` dumps the
   position of every evaluated op and `mlnix-parse -d` reads it against the Confix scan (`docs/COMPOSITE.md`; the code is on
   branch `scratch/dead-bands`, not master). The NixOS toplevel touches 2,889 files and 33.8 MB; 71.8% of those bytes are in
   maximal `{ [ (` bands with no evaluated position inside (86,188 bands), 66.0% in bands of at least 256 bytes (26,954),
   56.4% at 512 (18,924), 27.7% at 1024 (5,405). A parser told to jump past exactly those bands (a stub where each was) gives the
   baseline's output once the 24 to 28 bands in each list that were in fact entered are taken out (0.1%, found one at a time
   from the stub that reports its position; an evaluated op without a position cannot mark its band live, and `nix.list`, which had
   none, was given one in that branch). Interleaved, 11 runs, the
   scan not counted: wall -10.8% skipping bands of 256 bytes and up, -10.8% at 512, -4.3% at 1024. Of the 194 ms the 256 list
   saves, 127 ms is the parser (270.6 ms over those files to 144 ms) and about 67 ms lowering and minting.
   That is the ceiling. Against it stand the scan (33.8 MB at 800 MB/s is 42 ms), the bands that are live (parsed later, and
   scanned once already), and three things a real consumer has to solve:
   (a) Nix merges `a = { x = 1; }; a.y = 2;` while parsing, so a `{` that is the value of a binding cannot be opaque: with a
   `throw` stub the 256 list stopped the parse with `attribute 'environment.etc' already defined`; an empty attribute set as
   the stub merges, and a real band would have to be expanded when a later binding extends its path;
   (b) a deferred band needs its free variables for its captures, and finding them means reading its identifiers, which costs
   what skipping it saves (the bands of the 256 list average 828 bytes). The runtime does not need captures:
   `lookup` walks `Frame::up` to the frame of the region that defines a value, so a band could be minted later as a nested
   region that names outer values directly, from a scope snapshot kept at its site. But deferred lambdas capture by value
   today, and a lambda that contains a band would have to reach names only its band uses, so the two change together;
   (c) a syntax error, or an undefined variable, inside a band nobody enters would go unreported, where Nix reports it at parse
   time. A scan that does not balance falls back to the full parse, so lexical errors still surface.
   A fair estimate of the net is a third to a half of the ceiling, that is 4 to 6% on the Mac, for a change that touches the
   lambda deferral; the cheaper rungs above and below come first.
5. Core ops behind `NixEvalOpInterface` models; delete the `TypeSwitch`.
6. Lexer and parser (done). `Parser::fill`, the token pull with its 88-byte `Token` and a deque, was 10.5% of the evaluator thread and the
   parse phase 17.9%. The token is 32 bytes and the lookahead a ring of four, `posAt` goes from newline to newline, and the AST is a
   region of `Slice`s with no vector, map, virtual destructor or string (`docs/COMPOSITE.md`): the parser over the 40,181-file corpus
   (104 MB) went from 0.757 s to 0.375 s (-50%), the region commit alone -5% to -7% of a run in situ, and the parse phase is 6.5% of
   the evaluator thread now.
7. Lowered-IR cache as MLIR bytecode, keyed by file hash (skips lex, parse and
   lowering on warm runs; the uniquing cost moves to the reader, so measure).
8. The call path (done; Mac, interleaved, identical hashes). A sampled profile put the allocator at 5.1% of the evaluator thread, and
   the callers that owned it were places that allocated or hashed on every call: `callFunction` (two `std::vector` for the arguments
   of a primop call), `BindingsBuilder` (a `std::vector<Attr>` grown 1, 2, 4, 8) and `callLambda` (a string hash per formal per call,
   915,300 of them in a toplevel run). Stack storage for the first two and the formals' symbols made once: wall -4.4% / -3.5% (demand)
   and -5.1% / -3.3% (eager) on toplevel / nixpkgs-73, 17 runs; the allocator share fell from 5.1% to 3.9%.
   What the hop histogram says about `lookup` (toplevel, demand): of 20.9M calls, 72% walk no frame (mean 0.59 hops, 12.4M hops in the
   run), and 9.2M are first touches of a cell, 7.75M of those making a thunk. So the chain of frames is not what `lookup` costs, which
   is why rung 2's cheaper forms lost; the first touch is. It called `Value::getDefiningOp()` (a call into libMLIR, 2.3% of the
   thread) and then eight `isa<>` that read the op's header, in every frame. The `Slot` now holds the defining op and the kind of
   first touch: -1.0% / -1.6% (demand), -1.4% / -0.6% (eager). Primops are function pointers, not `std::function` (the call was
   1.6% of the thread): -0.6% / -0.6% (demand), -0.5% / -0.3% (eager), the sign the same in all eight wall and cpu figures.
   Two lost to the noise (17 runs, identical hashes, branches kept): `forceValue` as an inline compare of the type tag
   (`exp/force-inline`: demand +0.1% / -1.6%, eager -1.8% / +0.0% wall) and `newFrame` without its `memset`, the arena being zero
   (`exp/frame-zero`: demand +0.4% / -1.0%, eager +0.4% / +0.1%): the 1.3% of samples on that `memset` moves to the first write of
   the same lines.
9. Hashing (Linux; `docs/PERFORMANCE.md`, section Hashing): a toplevel run puts 53 MB through SHA-256, and Linux did it in LLVM's
   portable C. libcrypto now, where there is one. Not measured on kali yet.
10. Parse into the IR with no tree (the section above): done, on master since 745f861. Kali, same host, 9 interleaved runs against
   aea88bf65 (median wall, peak RSS): demand -3.6% / -2.2% and -10.4% / -8.8%, eager -10.1% / -1.1% and -10.1% / -6.9% (toplevel /
   nixpkgs-73); the minima went the other way (demand +7.4% / +5.4%, eager +4.2% / +3.9%), and the old binary's runs spread 18%
   between minimum and median against the new one's 2 to 7%. Mac, 7 interleaved runs under a load average of 5: demand +4.4% /
   +2.4%, eager +2.9% / +2.8%. Hashes identical everywhere.
   The generation benches of 4ff9187ca, c452893cb and 8f0bf3aa1 (vs-nix.py, runs stopped at 1.2x the record) stopped 5, 2 and 5
   mlnix runs, and their medians count them: the same host ran aea88bf65's own binary, interleaved, at a median 20% above that
   record (4.135 s against 3.456 s, toplevel demand), so the record is no longer what the host does and the A/B above is the
   comparison. Their raw output is on kali under /tmp/kb/gen-*; the README keeps aea88bf65 as the last generation until a bench
   of the host stops no run.
11. Only then: closure conversion to `func` + the stock inliner, strictness
   analysis (needs a lattice type instead of the single `!nix.value`).
