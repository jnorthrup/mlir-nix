# The dialect fabric

mlnix started as a hand-written evaluator that happened to print MLIR. This file
tracks the move of its logic into dialects, passes, interfaces and declarations,
what that bought (measured), and what is next. Numbers are from
`scripts/bench.py` on the NixOS toplevel and 73-package evaluations; nothing here
is aspirational unless it says so.

## What exists

Twelve dialects, all present in the IR of real programs:

    nix        language core: lambda, apply, attrs, list, select, if, with, ...
    nixnum     10 ops   arithmetic, bit ops, rounding, ordering
    nixty      11 ops   type predicates, typeOf, functionArgs
    nixstr     11 ops   substring, replaceStrings, toString, match, versions, ...
    nixctx      6 ops   string context
    nixlist    17 ops   length, elemAt, map, filter, foldl', sort, ...
    nixattr    11 ops   attrNames, getAttr, mapAttrs, ...
    nixpath     9 ops   readFile, pathExists, dirOf, baseNameOf, getEnv, ...
    nixstore    9 ops   toFile, path, derivationStrict, fetchers
    nixhash     3 ops   hashString, hashFile, convertHash
    nixfmt      6 ops   toJSON, fromJSON, toXML, fromTOML, flake refs
    nixctl     12 ops   seq, throw, trace, tryEval, import, ...

The 105 continent ops are declared once, in `include/NixDialect/NixPrims.td`:
arity, effects and foldability. Everything else follows:

- **Verification**: ODS verifier checks arity. `mlnix primops` (the runtime
  registry) is compared with the declarations by `scripts/check-prims.py`.
- **Effects**: `Pure`, `MemRead<NixFS|NixEnv>`, `MemWrite<NixTrace|NixStore>`.
  The stock `-cse` pass is therefore sound on Nix IR: pure primops merge, ops
  that may run user code or trace do not (`test/mlir/effects.mlir`).
- **Folding**: one generic folder serves every `foldable` primop by calling the
  evaluator's own implementation; a call that would throw is left alone, so
  errors keep their position and trace.
- **Evaluation**: `NixEvalOpInterface` is attached from outside as an external
  model (`lib/Eval/EvalModels.cpp`). The dialects know nothing about the
  evaluator; a JIT or symbolic executor can attach its own model the same way.
- **Devirtualization** (`nix-prims`): `builtins.length x`, `__add a b`, `map f l`
  become `nixlist.length(x)`, `nixnum.add(a, b)`, `nixlist.map(f, l)`. A single
  walk (`walkAndApplyPatterns`), not the greedy fixpoint driver.
- **Constants**: `true`, `false`, `null` are `nix.bool` / `nix.null`
  (ConstantLike), so they fold and feed folded primops.

## Tests (each layer can fail)

    python3 scripts/run-lang-tests.py   upstream lang suite: 466/466 semantic
    python3 scripts/difftest.py         53 expressions identical to Nix 2.35.4
    python3 scripts/run-mlir-tests.py   FileCheck tests of the dialects/passes
    python3 scripts/check-prims.py      declarations == runtime registry
    python3 scripts/bench.py            wall-clock, peak RSS, result hash

## Measured

`scripts/bench.py`, min of 3 runs, NixOS toplevel / 73 nixpkgs attrs. Every row
has the identical result hash (same `.drv` paths), 466/466 on the lang suite,
53/53 against Nix 2.35.4.

    change                                          toplevel    nixpkgs-73   peak RSS
    v0.1.0 (nix-simplify = greedy driver per file)    4.59 s      4.91 s     2554 MB
    --no-opt                                          4.52 s      3.76 s     2549 MB
    + devirtualization to continent dialects          4.25 s      3.63 s     2509 MB
    + static select/has_attr paths as attributes      4.12 s      3.53 s     2453 MB
    + ctx.disableMultithreading()                     3.82 s      3.38 s     2344 MB
    + literals without locations, filename attr once  3.59 s      3.13 s     2349 MB
    + Symbols keyed by StringAttr; CommonCrypto SHA   3.48 s      2.97 s     2378 MB

Optional stages (`MLNIX_PASSES`), measured on top of `devirt`:

    devirt,dce +0.14 s    devirt,fold +0.35 s    devirt,fold,dce +0.56 s

`fold` and `dce` cost more than they save here, so only `devirt` is on by
default. The greedy rewriter is a fixpoint machine; use it only where a
fixpoint is needed. Devirtualization is one `walkAndApplyPatterns` walk.

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
Continent ops are 0.6% (most applications in nixpkgs are of user lambdas).

## What this does not buy

Arithmetic and `if` are a rounding error in this workload (`nix.int` 0.5%,
`nix.if` < 0.3%). `arith` and `scf` would be ornamental here, and the rungs
below are ordered by the profile, not by which dialects are fashionable.

## Next rungs (by measured weight)

1. A lowering to a runtime dialect with *resolved addressing*: operand
   (depth, slot) and Symbol ids as attributes, so `lookup` (10.6%, a hash probe
   per operand) and the `TypeSwitch` chain in `evalOp` disappear. Progressive
   lowering `nix + continents -> nixrt`.
2. Core ops behind `NixEvalOpInterface` models; delete the `TypeSwitch`.
3. Lexer (7.8% self): a table-driven scanner instead of per-character calls.
4. Lowered-IR cache as MLIR bytecode, keyed by file hash (skips lex, parse and
   lowering on warm runs; the uniquing cost moves to the reader, so measure).
5. Only then: closure conversion to `func` + the stock inliner, strictness
   analysis (needs a lattice type instead of the single `!nix.value`).
