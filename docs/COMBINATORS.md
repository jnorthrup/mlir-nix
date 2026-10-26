# Combinators, declarations as IR, and what failed

The question: is mlnix "at the mercy of C++ rote structural declarations", or does
MLIR have combinator mechanisms in the wild that let a language like Nix be
declared as dialects, rewrites and pipelines *as data*?

Short answer: MLIR ships several declarative layers (IRDL for dialects, PDL for
rewrites, the Transform dialect and textual pipelines for strategies, a matcher
language for queries). IRDL now carries the declaration of all 105 primops: it
works, it costs nothing measurable at run time, and it failed in thirteen specific
ways, listed in section 4 with the evidence. PDL and pipeline-as-data were tried in
side branches (section 7). What is still handwritten C++ is mostly algorithms
(parser, evaluator, primop library, store), not structure.

How each claim is marked: **tested** (a command was run, output seen),
**header** (read from the installed LLVM 23.1.1 headers or `--help`),
**inferred** (follows from the API, not run).

## 1. What MLIR offers

| mechanism | what it composes | tool / library in LLVM 23.1.1 | used here |
|---|---|---|---|
| ODS constraint combinators (`AnyTypeOf`, `And`, `Or`, `Variadic`, `Optional`, `CPred`, ...) | op and type constraints, in TableGen | mlir-tblgen | core dialect (`NixOps.td`) |
| **IRDL** (`irdl.is`, `any_of`, `all_of`, `base`, `parametric`, `any`, `c_pred`, `operation`, `operands`, `results`, `attributes`, `region`) | a *dialect definition written as IR*; loadable at run time | `mlir-opt --irdl-file`, `irdl::loadDialects`, `tblgen-to-irdl`, `mlir-translate --irdl-to-cpp` | **all 105 primops (24 dialects)** |
| PDL / PDLL (`pdl.pattern`, `pdl.operation`, `pdl.replace`) | rewrite rules as IR, compiled to a matcher bytecode | `mlir-pdll -x=mlir\|cpp`, `PDLPatternModule` | experiment B (see section 7) |
| Transform dialect (`sequence`, `alternatives`, `foreach_match`, `include`, `apply_registered_pass`, `apply_patterns`, `apply_cse`; extensions: PDL, IRDL `irdl.collect_matching`, SMT `smt.constrain_params`, Tune `tune.knob` / `tune.alternatives`) | strategies: try/else, sequencing, match-then-act tables | `mlir-transform-opt`, `-transform-interpreter` | experiment C (section 7) |
| textual pass pipelines (`builtin.module(a,b,c)`) | passes | `parsePassPipeline`, `--pass-pipeline` | experiment C |
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

Restructuring is a data edit: the split from 11 to 24 dialects changed the IRDL file
and four FileCheck op names, and no C++.

## 3. Measured

All **tested**. Master `11b03dd` (11 static ODS dialects, built in its own worktree)
against this branch, runs interleaved on a shared machine (load average ~4), result
hashes identical on both workloads.

| | master | this branch |
|---|---|---|
| NixOS toplevel, median wall of 5 | 3.631 s | 3.631 s (0.0%) |
| 73 nixpkgs attrs, median wall of 5 | 3.335 s | 3.273 s (-1.9%) |
| process start-up, median CPU of 80 | 7.95 ms | 9.07 ms (**+1.12 ms**) |
| full rebuild CPU (single measurement each) | 76.3 s user | 40.8 s user |
| C++/TD/CMake lines (library + tools) | | +432 / -841 (net -409) |
| translation units in the dialect library | 13 | 2 |
| declaration data | 251-line TD + 12 TUs | 625 lines IRDL |

Correctness gates, unchanged: upstream lang suite 466/466 semantic in all three
pipeline modes (default 208 / all passes 207 / `--no-opt` 207 byte-exact stderr, same
as before), 53/53 expressions identical to Nix 2.35.4, 8/8 FileCheck files,
registry-vs-declaration check 105/105 (it fails when an arity in the data is changed).

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

## 5. What is still handwritten C++

| | lines | structural declaration? |
|---|---|---|
| Nix lexer + parser | 1423 | no: an algorithm |
| AST printer (`--parse` output) | 253 | no |
| AST -> MLIR lowering (scopes, `rec`, `with`) | 514 | no, but it is the natural next dialect conversion |
| evaluator core (`evalOp` type switch, force, call) | 2185 | partly: the type switch is "conditionals theater" and could be interface models |
| primop implementations | 2909 | no: the library the declarations point at |
| store, hashing, derivations, builder | 2448 | no |
| core dialect (ops, folders, passes) | 863 | yes, but see F11 |
| continents: generic loader | 248 | no code per op |
| continents: declaration | 625 | data |

The structural declarations that were C++ or TableGen (251-line TD, 12 translation units, a CMake
loop, 105 generated classes) are now data plus 248 generic lines. The rest is not structure, and no
MLIR mechanism I found removes the need to write a parser or the 105 primop bodies.

## 6. Next, by what the data says

1. Core ops behind `NixEvalOpInterface` models, deleting the `evalOp` type switch (needs a
   measurement; the lookup is not free).
2. AST -> `nix` as a dialect conversion (the Toy-tutorial shape): the parser emits an AST dialect,
   `MLIRGen` becomes patterns plus a `ConversionTarget`.
3. Resolved-addressing runtime dialect (see `FABRIC.md`), where `lookup` (10.6%) lives.

## 7. Side experiments

Two further mechanisms were tried on separate branches, against master, by
independent workers; their results are appended here once verified:

* `exp/pdl-devirt`: the devirtualization rewrite as PDL/PDLL patterns.
* `exp/pipeline-as-data`: the optimization pipeline as a textual pass pipeline and as
  a Transform-dialect script.
