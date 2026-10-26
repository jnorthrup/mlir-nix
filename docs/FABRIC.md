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

    pipeline                  nixos-toplevel   nixpkgs-73
    nix-simplify (v0.1.0)          4.59 s        4.91 s     greedy driver on every file
    --no-opt                       4.52 s        3.76 s
    devirt   (default)             4.25 s        3.63 s     walk-based
    devirt,dce                     4.39 s        3.71 s
    devirt,fold                    4.60 s        3.94 s
    devirt,fold,dce                4.81 s        3.98 s

Result hashes are identical in every row. `fold` and `dce` cost more than they
save on these workloads, so only `devirt` is on by default (`MLNIX_PASSES`
selects stages). The lesson is as much about drivers as about dialects: the
greedy rewriter is a fixpoint machine; use it only where a fixpoint is needed.

`MLNIX_STATS=1` prints the op histogram of everything an evaluation lowers. For
the NixOS toplevel (1.3M ops): `nix.str` 33%, `nix.formal` 16%, `nix.select`
11%, `nix.apply` 9.5%, `nix.attrs` 9.6%, `nix.with_var` 4.5%. Continent ops are
0.6% (primop calls are rare in nixpkgs; most applications are of user lambdas).

## What this does not buy

Arithmetic and `if` are a rounding error in this workload (`nix.int` 0.4%,
`nix.if` < 0.3%). `arith` and `scf` would be ornamental here, and the rungs
below are ordered by the histogram, not by which dialects are fashionable.

## Next rungs (by measured weight)

1. Static attribute paths as attributes: `nix.select`/`nix.has_attr` keys that
   are literals become a mixed static/dynamic attribute (the `static_offsets`
   idiom of `memref.subview`) instead of one `nix.str` op each. Target: remove
   most of the 33%.
2. Core ops behind `NixEvalOpInterface` models; delete the `TypeSwitch` in
   `evalOp`.
3. Resolve operand slots at lowering instead of hashing per lookup.
4. Only then: closure conversion to `func` + the stock inliner, strictness
   analysis (needs a lattice type instead of the single `!nix.value`).
