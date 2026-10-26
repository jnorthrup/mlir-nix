# The dialect fabric

mlnix started as a hand-written evaluator that happened to print MLIR. This file
tracks the move of its logic into dialects, passes, interfaces and declarations,
what that bought (measured), and what is next. Numbers are from
`scripts/bench.py` on the NixOS toplevel and 73-package evaluations; nothing here
is aspirational unless it says so.

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

- **Verification**: the stock IRDL verifier checks arity. `mlnix primops` (the runtime
  registry) is compared with the declaration by `scripts/check-prims.py`.
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

    python3 scripts/run-lang-tests.py   upstream lang suite: 466/466 semantic
    python3 scripts/difftest.py         53 expressions identical to Nix 2.35.4
    python3 scripts/run-mlir-tests.py   FileCheck tests of the dialects/passes
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
   charges about 10% of the run for it. `//` alone copies 264 MB (toplevel) / 514 MB
   (nixpkgs-73, a fifth of RSS); 374 calls with a 256+ entry left operand are 56% of that.
   A persistent or layered attribute set is the one place a tree structure could pay
   (`docs/COLLECTIONS.md`, section 6). Not built.
2. A lowering to a runtime dialect with *resolved addressing*: operand
   (depth, slot) and Symbol ids as attributes, so `lookup` (8.6%) and the `TypeSwitch`
   chain in `evalOp` disappear. Progressive lowering `nix + continents -> nixrt`.
3. Locations: 6.2% is FileLineColRange uniquing, one per op. Sharing locations per line
   needs the column kept elsewhere (errors print it).
4. Core ops behind `NixEvalOpInterface` models; delete the `TypeSwitch`.
5. Lexer (10.4%): a table-driven scanner instead of per-character calls.
6. Lowered-IR cache as MLIR bytecode, keyed by file hash (skips lex, parse and
   lowering on warm runs; the uniquing cost moves to the reader, so measure).
7. Only then: closure conversion to `func` + the stock inliner, strictness
   analysis (needs a lattice type instead of the single `!nix.value`).
