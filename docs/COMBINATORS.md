# Combinators, declarations as IR, and what failed

The question: is mlnix "at the mercy of C++ rote structural declarations", or does
MLIR have combinator mechanisms in the wild that let a language like Nix be
declared as dialects, rewrites and pipelines *as data*?

Short answer: MLIR ships several declarative layers (IRDL for dialects, PDL for
rewrites, the Transform dialect and textual pipelines for strategies, a matcher
language for queries). IRDL now carries the declaration of all 105 primops, and
the optimization pipeline is MLIR pass-pipeline text instead of a hand-rolled
options struct. Both work and cost nothing measurable at run time. PDL as a
replacement for the devirtualizer was tried and lost on every count. Seventeen
specific failures are listed in section 4 with the evidence, including one real
soundness bug in my own core dialect. What is still handwritten C++ is mostly
algorithms (parser, evaluator, primop library, store), not structure.

How each claim is marked: **tested** (a command was run, output seen),
**header** (read from the installed LLVM 23.1.1 headers or `--help`),
**inferred** (follows from the API, not run).

## 1. What MLIR offers

| mechanism | what it composes | tool / library in LLVM 23.1.1 | used here |
|---|---|---|---|
| ODS constraint combinators (`AnyTypeOf`, `And`, `Or`, `Variadic`, `Optional`, `CPred`, ...) | op and type constraints, in TableGen | mlir-tblgen | core dialect (`NixOps.td`) |
| **IRDL** (`irdl.is`, `any_of`, `all_of`, `base`, `parametric`, `any`, `c_pred`, `operation`, `operands`, `results`, `attributes`, `region`) | a *dialect definition written as IR*; loadable at run time | `mlir-opt --irdl-file`, `irdl::loadDialects`, `tblgen-to-irdl`, `mlir-translate --irdl-to-cpp` | **all 105 primops (24 dialects)** |
| PDL / PDLL (`pdl.pattern`, `pdl.operation`, `pdl.replace`) | rewrite rules as IR, compiled to a matcher bytecode | `mlir-pdll -x=mlir\|cpp`, `PDLPatternModule` | tried for the devirtualizer, **rejected** (section 7, F16) |
| Transform dialect (`sequence`, `alternatives`, `foreach_match`, `include`, `apply_registered_pass`, `apply_patterns`, `apply_cse`; extensions: PDL, IRDL `irdl.collect_matching`, SMT `smt.constrain_params`, Tune `tune.knob` / `tune.alternatives`) | strategies: try/else, sequencing, match-then-act tables | `mlir-transform-opt`, `-transform-interpreter` | not used: a flat pass list is all the pipeline needs (section 7) |
| textual pass pipelines (`a,b,c`) | passes | `parsePassPipeline`, `--pass-pipeline` | **`MLNIX_PIPELINE`**, the evaluator's whole optimizer |
| C++ matcher combinators (`m_Op`, `m_Constant`, `m_Zero`, `matchPattern`) | value/op matchers | `mlir/IR/Matchers.h` | `FoldPrim` pattern |
| `mlir-query` matcher language (`anyOf`, `allOf`, `hasOpName`, `hasOpAttrName`, `getDefinitions`, `getAllDefinitions`, `getDefinitionsByPredicate`, `getUsersByPredicate`) | read-only IR queries | `mlir-query`, `MLIRQueryLib` | `mlnix-query` |
| `DialectExtension`, external interface models, `OperationName::attachInterface` | dialects with each other and with behaviour, after the fact | core MLIR | `ContinentsExtension`, evaluator model, effects model |

Outside the tree (sources fetched or searched this session, claims limited to what
those pages state):

* **ELEVATE / RISE** (Hagedorn et al., `bastianhagedorn.github.io/files/publications/2020/arxiv-elevate-2020.pdf`):
  rewrite *strategies* as combinators (`seq`, `lChoice`, `try`, `repeat`, ...). The
  Transform dialect paper (arXiv 2409.03864) positions itself against it: ELEVATE
  needs a pure payload, Transform does not.
* **eqsat** (arXiv 2505.09363): an e-graph dialect built on graph regions. **Not in
  the installed MLIR** (tested: absent from `mlir-opt`'s dialect list).
* **lz / hask-opt** (github.com/bollu/lz): the one MLIR stack for a lazy language I
  found: dialects `Hask` (STG-like), `GRIN`, `Pointer`, `Unification`, plus a Lean
  `lambdapure`. Tested against its file tree: `include/Hask/HaskOps.h` is 27.9 KB of
  hand-written C++ while `HaskOps.td` is a 1.3 KB stub; `lib/Pointer/PointerDialect.cpp`
  is 43 KB. That project is the "rote C++" pattern, not the alternative to it.
* **xDSL** (`docs.xdsl.dev/reference/dialects/irdl/irdl`): the same IRDL ops, with
  Python-embedded definitions.

I found no project that declares a whole language's ops, effects and rewrites as
data end to end. That is a statement about what I looked at, not a proof.

## 2. What was built

`include/NixDialect/NixPrims.irdl.mlir` (625 lines, IRDL) declares 24 dialects in 6
macro scopes. Per op, structure is IRDL (`irdl.operands(a0: %v, a1: %v)`,
`irdl.results`), and what IRDL cannot say rides as attributes on the
`irdl.operation`: `nix.key`, `nix.fx` (effect class), `nix.fold`. Per dialect:
`nix.scope`, `nix.continent`.

`lib/Dialect/NixPrimDialects.cpp` (248 lines) is generic: it names no op.

| from the data | becomes |
|---|---|
| `irdl.operands` | the stock IRDL verifier rejects wrong arity (**tested**: `test/mlir/verify.mlir`) |
| `nix.fx` | a `MemoryEffectOpInterface` fallback model attached with `OperationName::attachInterface`; stock `-cse`/DCE obey it (**tested**) |
| `nix.fold` | one `RewritePattern` per op, via the canonicalization hook |
| `nix.fresh` | a `MemAlloc` effect on the result: pure, but equal calls are not merged (F14) |
| all ops | one parser/printer pair: `nixnum.add(%a, %b)` |
| `nix.key`, arity | the core dialect's primop table (devirtualizer, evaluator) |
| `nix.scope`, `nix.continent` | `MLNIX_STATS=1` op counts per scope / continent / dialect |

The continents are defined by a `DialectExtension` once the core dialect (which
owns `!nix.value`) is loaded. The declaration can be replaced without rebuilding:
`MLNIX_PRIMS_IRDL=other.irdl.mlir`. `test/mlir/declaration.mlir` uses that to flip
one attribute in a copy and check that behaviour flips (pure -> impure stops CSE;
arity 2 -> 1 makes the verifier reject; bad effect class, duplicate key, missing file
are loader errors). Both directions were checked to fail against the wrong
expectation.

The pipeline is data too. The three stages are registered passes (`nix-prims`,
`nix-fold`, `nix-dce`) and one pipeline (`nix-simplify`); the evaluator builds one
`PassManager` from text (`EvalSettings::pipeline`, default `nix-prims`, override
`MLNIX_PIPELINE='nix-prims,cse'`). The `SimplifyOptions` struct and the `MLNIX_PASSES`
parser are gone, and any registered pass can be named.

Restructuring is a data edit: the split from 11 to 24 dialects changed the IRDL file
and four FileCheck op names, and no C++.

## 3. Measured

All **tested**. Master `11b03dd` (11 static ODS dialects, built in its own worktree)
against this branch, runs interleaved on a shared machine (load average ~4), result
hashes identical on both workloads.

| | master | this branch |
|---|---|---|
| NixOS toplevel, median wall of 5 | 3.565 s | 3.484 s (-2.3%) |
| 73 nixpkgs attrs, median wall of 5 | 3.098 s | 3.116 s (+0.6%, noise) |
| process start-up, median CPU of 60 | 7.72 ms | 9.01 ms (**+1.29 ms**) |
| full rebuild CPU (single measurement each) | 76.3 s user | 40.8 s user |
| C++/TD/CMake lines (library + tools) | | +555 / -924 (net **-369**) |
| translation units in the dialect library | 13 | 2 |
| declaration data | 251-line TD + 12 TUs | 628 lines IRDL |

The pipeline-as-text and identity-soundness step alone was +140 / -100 (net +40
lines): it removed the options mini-language and fixed F14, it did not shrink
the code.

Every gate, timed on this machine: FileCheck 0.7 s, declaration check 0.0 s, lang
suite 6-7 s per pipeline mode (three modes), difftest 2.8 s; **26 s for all of
them**. A full rebuild is about 7 s wall.

Correctness gates, unchanged: upstream lang suite 466/466 semantic in all pipeline
modes (default `nix-prims` 208 / `nix-simplify` 207 / `--no-opt` 207 byte-exact
stderr, same as before), 466/466 also with stock `cse` and `cse,canonicalize` in the
pipeline (it was 463 before F14 was fixed), 53/53 expressions identical to Nix
2.35.4, 9/9 FileCheck files, registry-vs-declaration check 105/105 (it fails when an
arity in the data is changed).

Continent ops are 0.68% of the ops of a NixOS toplevel evaluation (7.4k of 1.10M), so
"no run-time cost" means "no cost on a workload where they are rare". A workload
dominated by primops would need its own measurement.

## 4. Failure log

**F1. `tblgen-to-irdl` drops everything that mattered. (tested)** On `NixPrims.td` it
emits `irdl.operands(args: variadic %0)` for every op, because the arity lived in a C++
string in `extraClassDeclaration`. Key, effects, foldability, assembly: gone. On the core
dialect it emits `irdl.c_pred "(::llvm::isa<::mlir::ArrayAttr>($_self))"` for attribute
constraints. We generated the IRDL from our own table instead. Lesson: a TD that hides
structure in C++ strings is not declarative, and no converter will rescue it.

**F2. `irdl.c_pred` is accepted at load and never enforced. (tested)** A `cp.op` with
`c_pred "isa<ArrayAttr>($_self)"` accepts `{path = 5 : i32}` (exit 0). The structural form
`irdl.base "#builtin.array"` rejects it ("expected base attribute 'builtin.array' but got
'builtin.integer'"). So ODS -> IRDL conversion silently removes verification. The declaration
uses no `c_pred`.

**F3. Stock tools cannot load the declaration as written. (tested)** `mlir-opt --irdl-file`
fails with `no registered type with name !nix.value`, since the type belongs to a dialect stock
`mlir-opt` lacks. With `irdl.any` instead it loads, and `mlir-translate --irdl-to-cpp` produces a
static C++ dialect: 33,587 lines for 105 ops (59x the IRDL), which compiles (`-fsyntax-only`,
0.96 s) once the MLIR headers are included by hand (the generated file has none). That route stays
open for hot ops, but is not used: the dynamic ops cost nothing measurable here.

**F4. Dynamic ops have no effects, so stock CSE/DCE do nothing. (tested)** With the plain IRDL
file, `mlir-opt -cse -canonicalize` leaves two identical `nixnum.add` and a dead `nixnum.neg`.
`OperationName::attachInterface<FallbackModel>()` is public and fixes it (**tested**).

**F5. No public handle to configure an IRDL-defined op. (header + tested)**
`irdl::loadDialects` returns after registering; `ExtensibleDialect` has `registerDynamicOp` but no
`lookupOp`; `OperationName::getImpl()` is protected. Parse/print/canonicalization hooks are reached
through a derived-class accessor and `reinterpret_cast` (4 lines, `NameAccess` in
`NixPrimDialects.cpp`). Fragile; an upstream `lookupOp` would remove it.

**F6. Custom assembly on dynamic ops is a trap. (tested)** Without a parse function,
`nixnum.add %a, %a : i64` fails with **exit 1 and no diagnostic**. A print function must print the op
name itself (ODS does that in generated code; `OpState::printOpName` is protected, so its 4 lines are
copied). My first printer produced `%2 = (%0, %1)`.

**F7. Dynamic dialects cannot materialize constants. (header + inferred)** `DynamicDialect` does
not override `materializeConstant`, so an `OpFoldResult` attribute has nowhere to become an op. Folding
was therefore written as a rewrite pattern instead of a `fold` hook. Not tried: the hook itself. The
pattern gives the same answers (lang 466/466 with all passes; `builtins.add 1 2` becomes `nix.int 3`).

**F8. The verifier's wording changed. (tested)** IRDL says `op expects exactly 2 operands, but got 1`;
ours said `expects 2 operand(s) but has 1`. Anything that matches diagnostics must follow IRDL.

**F9. A dead abstraction from my own previous turn. (tested)** `NixPrimOpInterface` was declared and
implemented by all 105 ops, and nothing consumed it. Found when porting; deleted. Likewise `nix.scope` /
`nix.continent` had no consumer until `MLNIX_STATS` got one.

**F10. `mlir-query` is read-only and cannot see attribute values. (tested)** `hasOpAttrName` tests that
an attribute *exists*, not what it holds, so "a `nix.builtin` named `__add`" is not expressible; slice
matchers extract rather than test. The argument counts differ from what I remembered
(`getDefinitions` takes 5; first query: `Incorrect argument count. (Expected = 5) != (Actual = 2)`).
Useful for reading IR, not for specifying rewrites.

**F11. The core dialect stays ODS. (header + inferred)** IRDL has 17 ops and no notion of traits,
interfaces, region kinds, folders or canonicalizers; `DynamicOpTrait` ships `IsTerminator` and
`NoTerminator` only; dynamic ops keep attributes as discardable attributes, not inherent properties,
which would take `nix.select`'s `path` and friends off the fast path the evaluator reads. The core needs
graph regions, `custom<AttrPath>` assembly and `AttrSizedOperandSegments`. Not converted.

**F12. DRR cannot target IRDL ops. (inferred)** Declarative rewrite rules generate code that names op
classes; IRDL ops have none. PDL, which matches by name, is the compatible route.

**F13. eqsat is not available, and has little to chew on here. (tested for availability)** Absent from the
installed MLIR. Continent ops, the only place with algebra worth saturating, are 0.68% of the IR.

**F14. My core dialect declared unsound `Pure`. (tested)** `nix.lambda`, `nix.list`,
`nix.attrs`, `//`, `++` and 20 primops that return fresh lists or attribute sets were
`Pure`, so stock `cse` merged identical ones. In Nix `(x: x) == (x: x)` is false, so
merging broke three upstream tests with `MLNIX_PIPELINE='nix-prims,cse'`:
`eval-okay-equal-function-attrset-distinct-similar`,
`eval-okay-equal-function-list-distinct-similar`, `eval-okay-sort` (463/466). My earlier
claim "stock `-cse` is sound on Nix IR" held only for the primops I had tested. Fix:
results with observable identity declare `MemAlloc` (core: `NixFreshVal` in the TD;
primops: `nix.fresh`), and `apply` declares a user-code effect. 466/466 afterwards, and
`test/mlir/identity.mlir` fails when `nix.fresh` is removed from the data. A helper agent
found the bug; I reproduced the failure and the fix myself. The default pipeline never
ran `cse`, so shipped behaviour was unaffected.

**F15. A textual pipeline can silently do nothing. (tested)** On an any-anchored
`PassManager`, `parsePassPipeline("any(nix-prims)")` nests the passes under child ops:
they ran on the lambdas inside the expression, not on the expression, with no error.
Devirtualization silently stopped (the default exact-match count fell 208 -> 207) and
`any(nix-simplify)` ran once per nested lambda (lang suite 6 s -> 20 s). The bare list
`nix-prims` is right; `builtin.module(...)` and `nix.expr(...)` wrappers are silent
no-ops here too. It was caught only because a count moved by one.

**F16. PDL as the devirtualizer loses on every count. (tested)** Branch
`exp/pdl-devirt`: a generator that builds ~300 `pdl.pattern`s from the primop table at
start-up. Output identical, but **+627 net C++ lines** to replace a ~45-line pattern,
**+1.0 to +3.4% run time** on the two workloads (interleaved), and **+23.8 ms start-up**
per process (8.9 -> 32.7 ms CPU) to build and lower the patterns. From the helper's
transcript, not re-run: PDLL rejected `op<nixnum.add>(a0, a1)` with "invalid number of
operand groups for `nixnum.add`; expected 1, but got 2" while the op had one variadic
operand group, and ops not described to PDLL are treated as unregistered. A PDLL file
generated from the IRDL data and loaded at run time would pay the same start-up and
matching costs; not built.

**F17. Stock passes compose for free and cost run time. (tested)** Two workloads,
interleaved, same binary, identical result hashes:

| pipeline vs `nix-prims` | NixOS toplevel | 73 nixpkgs attrs |
|---|---|---|
| `nix-prims,cse` | +7.1% | +5.4% |
| `nix-prims,canonicalize` | +19.6% | +16.6% |
| `nix-simplify` (fold + dce) | +9.8% | +10.4% |

The evaluator lowers each file once and evaluates it once, mostly lazily, so a pass
has no second run to amortize against. They would only pay if the optimized IR were
reused (a bytecode cache keyed by file hash), which is not built.

## 5. What is still handwritten C++

| | lines | structural declaration? |
|---|---|---|
| Nix lexer + parser | 1423 | no: an algorithm |
| AST printer (`--parse` output) | 253 | no |
| AST -> MLIR lowering (scopes, `rec`, `with`) | 514 | no, but it is the natural next dialect conversion |
| evaluator core (`evalOp` type switch, force, call) | 2219 | partly: the type switch is "conditionals theater" and could be interface models |
| primop implementations | 2909 | no: the library the declarations point at |
| store, hashing, derivations, builder | 2448 | no |
| core dialect (ops, folders, passes) | 886 | yes, but see F11 |
| continents: generic loader | 252 | no code per op |
| continents: declaration | 628 | data |

The structural declarations that were C++ or TableGen (251-line TD, 12 translation units, a CMake
loop, 105 generated classes) are now data plus 252 generic lines. The rest is not structure, and no
MLIR mechanism I found removes the need to write a parser or the 105 primop bodies.

## 6. Next, by what the data says

0. A cache of lowered *and optimized* IR (MLIR bytecode keyed by file hash). Without it no
   pass can pay (F17); with it `cse`/`nix-fold` become one-time costs.
1. Core ops behind `NixEvalOpInterface` models, deleting the `evalOp` type switch (needs a
   measurement; the lookup is not free, and this moves lines rather than removing them).
2. AST -> `nix` as a dialect conversion (the Toy-tutorial shape): the parser emits an AST dialect,
   `MLIRGen` becomes patterns plus a `ConversionTarget`.
3. Resolved-addressing runtime dialect (see `FABRIC.md`), where `lookup` (10.6%) lives.

## 7. The two side experiments

Two helper agents ran these on separate branches with an open-ended budget; I stopped
them after 32 minutes. That was my mistake in setting them up: the experiments are small
and every gate here runs in 26 seconds. The branches are kept.

* `exp/pdl-devirt` (`638f015`): PDL devirtualizer. Measured by me, see F16. Not merged.
* `exp/pipeline-as-data` (`5db8d05`): textual pipeline, a Transform-dialect driver
  (`MLNIX_TRANSFORM`) and a micro-benchmark tool, +622 net lines. I did not use its code:
  the text pipeline is about 40 lines here, and a flat pass list needs no Transform
  script. Its second commit found F14, which I reproduced and ported.
* **Not done**, so no result: the Transform dialect's `alternatives`, `foreach_match` and
  `tune.knob`, `transform.irdl.collect_matching`, and `mlir-transform-opt` on Nix IR.
  Nothing in this document claims anything about them beyond their existence.
