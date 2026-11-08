# The dialects against PRELOAD.md

AGENTS.md: everything builds to TrikeShed's PRELOAD.md as MLIR.  In the IR that means every dialect is written in, or lowers to, the
`trikeshed` dialect (include/Composite/TrikeShed.td: join, twin, twinpacked, series, series2, cursor, either, layers; j, alpha, select,
combine, slice, project, where, fold, append, anchor, resolve, facet, ...).  Today none does.

Measured 2026-11-06 on the tree after 571b57d: no .td of include/NixDialect names a trikeshed type, and no pass lowers into trikeshed.
The passes are confix-to-llvm, kif-to-nix, nix-dce, nix-defer, nix-fold, nix-inline-values, nix-prims, nix-promotions, son-mint,
sumo-to-kif and trikeshed-lower-clusters (which starts in trikeshed).

| dialect | what it is | where it leaves the algebra | the PRELOAD form |
|---|---|---|---|
| nix (NixBase.td, NixOps.td) | the language, 29 ops | one opaque `!nix.value` for every value | attrs = `Join<CSeries<Symbol>, Series<Value>>` (sorted rows), list = `Series<Value>`, string = `Join<CharSeries, context>`, `//` = `!trikeshed.layers` + `trikeshed.resolve` |
| nix syntax (NixSyntax.td) | the parser's forms, 4 ops | spans held as attributes | a token's span is `!trikeshed.twinpacked` (TwInt), a source is a CharSeries |
| son (Son.td) | the demand schedule: pool, body, defer | the pool is its own region kind | a row of the pool is `trikeshed.append`, its first force `trikeshed.anchor` (named in 1547e4a as not built) |
| confix (Confix.td) | TrikeShed's scanner over LLVM IR | lowers straight to LLVM; the index is a C struct | the index is PRELOAD's `JsElement = Join<Twin<Int>, Series<Int>>`: twin + series in, LLVM below trikeshed |
| kif (Kif.td) | terms and theories | `kif.list` is its own list | `Series<Term>`; a theory's facts are a Cursor |
| sumo (Sumo.td) | subclass, instance, domain, range, holds | lowers to kif, then to nix strings | each relation is a Cursor of rows (child, parent), (relation, position, class); kif-to-nix makes text the gate, not the carrier |
| mlnix (MlnixControl.td) | the run's settings | in order: its one enum (eager / demand) decides the domain outcome PRELOAD allows | stays a control surface |

## Order

The pipeline: step 1 types the nix values, son is the one sea of nodes both backends read, and the fork comes after son.

```
nix ─step 1─▶ typed nix/trikeshed ──▶ son (typed sea of nodes, demand schedule)
                                        ├──▶ schedule into a CFG ──▶ LLVM lowering ──▶ LLVM opt
                                        └──▶ node-graph export ──▶ Truffle ──▶ Graal IR + GC
```

Rules that keep both arms open (the LLVM arm must not close the Graal one):
- every heap allocation is one typed call per site (one Java class and one `new` each);
- a packed address (`twinpacked`, int + address bits) lives only in SSA values and registers, never in a stored heap cell, or it stays
  a distinct type the export splits into a reference and an int;
- no free and no address arithmetic on heap references in the shared IR (interior pointers are a base plus an index);
- `Series` reaches LLVM as direct loads with its size known, never as an indirect call to its index function.

Steps:

1. nix values as trikeshed types: attrs, lists and strings typed in the IR; the evaluator's Bindings, list cells and Chars are their
   C++ form already.  Everything below reads these types.
   - Lists: done.  `nix.list` and `nix.concat_lists` make `!trikeshed.series<!nix.value>` (printed `!nix_list` by alias); every
     operand of the nix family, son.defer and the 105 primops takes either kind (`NixAny`; IRDL `any_of`, one constraint value per
     position, since IRDL binds every use of one value to one type).  An operand of a typed kind prints `%v : type` (the
     NixValue / NixValues directives): a graph region reads values before their definition, so the type cannot be looked up there.
     Checked: lang 487/487 both schedules, mlir 23/23, primops 105/105, JIT 652 exact, the three workloads' answers on both schedules,
     the AST of 40,196 files byte-identical, 3,260 nixpkgs files emit IR that mlnix-opt reads back to a fixed point and that equals the
     untyped build's IR once the 50,838 annotations are removed; nixpkgs-73 time and RSS unchanged.  Not run: Kali.
   - Attrs: done.  `nix.attrs` and `nix.update` make `!trikeshed.series2<i32, !nix.value>` (`!nix_attrs`); NixAny and the primops'
     any_of take it.  Checked the same way: lang 487/487 both schedules, mlir 23/23, primops 105/105, JIT 652 exact, the three
     workloads' answers on both schedules, AST corpus identical, the 3,260-file IR round trip a fixed point and equal to the untyped
     build's IR once its 111,681 annotations (60,843 of them attrs) are removed; nixpkgs-73 time and RSS unchanged.  Not run: Kali.
   - Strings: literals done.  `nix.str` makes `!trikeshed.join<!trikeshed.series<i8>, !trikeshed.series<!trikeshed.series<i8>>>`
     (`!nix_string`: the characters, and the context as a series of store paths).  A constant folded from an op of unfixed kind
     (`"a" + "b"`, a primop) keeps that op's type and prints `nix.str "ab" : !nix.value`: a materialized constant must have the type
     of the value it replaces.  The 3,260-file IR round trip: a fixed point, and equal to the untyped build's IR once its 258,264
     annotations (146,583 of them strings) are removed; AST corpus identical; mlir 23/23; lang 487/487 both schedules, primops
     105/105, JIT 652 exact, the three workloads' answers on both schedules; nixpkgs-73 time and RSS unchanged.  Not run: Kali.
   - Interpolation: done.  `"a${e}b"` is `nix.interpolate`, which always makes a `!nix_string`; `nix.concat_strings` is only `+`
     now (its `force_string` attribute is gone: the evaluator's node keeps kForceString, set by the op class).  test/mlir/kinds.mlir
     covers every kind, the round trip, folding (an interpolation folds to a string, `+` to `nix.str ... : !nix.value`) and a typed
     capture through nix-defer; it fails with the interpolation folder switched off.  The 3,260-file IR round trip: a fixed point, and
     equal to the old build's IR once annotations are stripped and the 6,335 interpolations are written back as
     `concat_strings {force_string}`.
   - Paths: done.  `nix.path` makes `!trikeshed.series<i8>`, a CharSeries with no context, printed `!char_series` (the alias is the
     CharSeries', since a string's characters are the same type: naming it `nix_path` printed strings as `join<!nix_path, ...>`).
     Checked: mlir 24/24 (kinds.mlir gains a path), lang 487/487 both schedules, primops 105/105, JIT 652 exact, the three workloads'
     answers on both schedules, AST corpus identical, the 3,260-file IR round trip a fixed point and equal to the old build's IR once
     normalized (1,292 path annotations).
   - Functions: done.  `nix.lambda` and `son.defer` (the lambda it stands for) make `(!nix.value) -> !nix.value`, the builtin
     function type (`!nix_fn`; IRDL `!builtin.function`); nix-defer gives the defer the lambda's type and son-mint gives it back.
     Checked: mlir 24/24 (kinds.mlir applies a function and checks the defer's type; son.mlir's apply check reads the typed callee),
     lang 487/487 both schedules, primops 105/105, JIT 652 exact, the three workloads' answers on both schedules, nixos-toplevel
     prelowered with two helpers (recorded run, then replayed) the same answer, AST corpus identical, the 3,260-file IR round trip a
     fixed point and equal to the old build's IR once normalized (26,855 function annotations; the unaliased form `%f : (!nix.value)
     -> !nix.value(%x)` that emit-mlir prints reads back).
   - Primop results: done for the 53 whose kind is fixed.  NixPrims.irdl.mlir constrains their result with `irdl.is` (13 lists,
     15 sets, 24 strings, `findFile` a path); the dialect records the type (PrimInfo::result), and nix-prims and the primop parser
     make the op with it.  Chosen where Nix fixes the kind and a census of every primop call (lang suite both schedules, the three
     workloads both schedules: 96 of the 105 primops called) saw that kind alone; `match`, `dirOf`, `unsafeGetAttrPos`, `fromJSON`
     and the control primops vary, and the 9 never called stay untyped.  MLNIX_CHECK_KINDS=1 makes a typed op that makes another kind
     an internal error: with it on, lang 487/487 both schedules and the three workloads both schedules, 0 errors; with `match`
     declared a list, it fails eval-okay-regex-match2 ("declared to make !trikeshed.series<!nix.value> but made a value of tag 8").
     The check sees only the calls nix-prims made into typed ops (a `builtins.match` reached through a variable stays an untyped
     `nix.apply`).  kinds.mlir checks a typed primop and a devirtualized call (fails when nix-prims keeps the call's type).
   - Not typed yet: `+` (int, float, path or string by its operands), and the scalars: int, float, bool and null are PRELOAD's
     plain elements (Kotlin Int, Double, Boolean) and have builtin types (`i64`, `f64`, `i1`, `none`); `nix.int`, `nix.float`,
     `nix.bool`, `nix.null` and the comparison / test primops (`nixty.is_*`, `less_than`, `length`, ...) would make them.
2. son typed: the pool's rows (`trikeshed.append`) and first forces (`trikeshed.anchor`) carry step 1's types, and the evaluator
   reads son IR (1547e4a: not built).
3. The fork.  LLVM: schedule son into blocks, lower with tag checks dropped where a type is known.  Graal: export the node graph
   with the attributes and positions a node now reaches through its `def`.
   - Graal arm, first cut (done): `mlnix-opt --nix-defer --son-export` writes the son-form module as JSON (an op per object, values
     numbered, a primop's `prim_key`, no source positions; test/mlir/son-export.mlir).  `graal/` is a Kotlin Truffle interpreter
     (truffle-api 25.4.4.1.1, the installed Oracle GraalVM 25.4; Confix from TrikeShed-jvm reads the export; built with
     its Gradle wrapper, copied from TrikeShed: `cd graal && ./gradlew installDist`): a son.body or
     nix.expr is a RootNode, its ops its children, a call's values a frame of slots filled when first forced; son.defer is a
     Closure over the body's CallTarget; `import` exports the imported file through mlnix.  Every value is a JVM object and the
     collector frees them.  `scripts/truffle-lang-tests.py`: 122/146 eval-okay tests print exactly their .exp (13 with flags or
     postprocessing not run).  Not done: source positions (unsafeGetAttrPos, 3 tests), string context (4), derivations, the
     store, toXML, fromTOML, flake refs, scopedImport, findFile, convertHash (15), and «repeated» where Nix copies a value from
     one cell to another (eval-okay-print).  Graal compiles the bodies (both tiers; forcing a cell is a TruffleBoundary, else
     strict → force → strict inlines without end).  Speed: a fib/foldl'/`//` mix runs ~75 ms per evaluation once compiled,
     mlnix ~40 ms for the whole process: apply is a boundary (no callee inlining), each call allocates its frame, sets are
     TreeMaps.  Next: a DirectCallNode inline cache in ApplyNode, frame slots in the VirtualFrame, sets as sorted arrays.
4. `//` as `trikeshed.layers` for large bases: on nixpkgs-73 the ~800 merges with a side of 4096+ rows copy ~260 MB of the arena's
   311 MB of flat merges (b58d02c chose flat for speed: layering every merge read 2.5-7% slower).  The layer here is only for the
   package set.  Fix the stale `Bindings::Layer` reference in TS_LayersType's description in the same change.
5. confix's index as twin + series; its LLVM lowering moves below trikeshed.
6. kif and sumo as series and cursors.
   - KIF lowered out of the Nix reader (started): `mlnix-kif` reads KIF files into a `kif.theory` (lib/Dialect/KifImport.cpp,
     sumo-nix/kif.nix's tokens and forms; equal terms one node across all the files of a bag; `file` on each fact and rule).
     sumo.full whole (78 files, 201,007 forms: 193,050 facts, 7,957 rules; 139,796 atoms, 3,352 variables, 251,454 lists, the
     counts of a separate Python reader, per file equal to kif.nix's) reads in 0.20 s at 170-182 MB peak; kif.nix on mlnix takes
     1.15 s and 820 MB (9.3 GB before `++` wrote into a buffer's room, ListExtent).
   - The inference as a pass: `kif-chase` (lib/Dialect/KifChase.cpp) is datalog.nix's forward chaining with its proofs, on
     interned term rows, each new fact a `kif.derived` with its rule and the facts it rests on; a theory's `ontology` gives
     `(instance X Class)` its subclass meaning.  `scripts/kif-oracle.py` runs datalog.nix and an engine on the same files and
     compares every fact and every proof: identical on the scenario (23 facts, with and without Merge.kif as the ontology),
     test/kif/chase-cases.kif (69 facts: instance through the ontology, several proofs of one fact, two rules in one round, a
     chain, not, equal, exists, a ground premise, a variable relation) and paperclip's first stratum (7,147 facts, 1,964 derived;
     0.05 s).  Mutants caught on the cases: no ancestors, the last solution kept, facts in file order, a round reading its own
     new facts, `not` and `equal` ignored (the byFirst index is an equivalent mutant: it narrows, in the same order).
   - The Graal analog: nix-truffle `--kif` reads the theory from son-export and makes each rule's antecedent a tree of Truffle
     nodes (and, not, equal, exists, instance, pattern) under a RootNode; identical to datalog.nix on the same three cases.
   - Memory, measured on Kali only (each case in a cgroup of 12 GB, no swap: an OOM kill is the result), sumo.full whole through
     kif.nix (78 files, 201,007 forms):
     | engine | result | time | peak RSS |
     | mlnix 571b57d (no ListExtent; std::string already gone), both schedules | OOM-killed at 12 GB | 5.9 s | 12.3 GB |
     | mlnix tree, `++` into a buffer's room (ListExtent), both schedules | ok | 1.4 s | 845 MB |
     | mlnix-kif, the text into kif IR | ok | 0.7 s | 201 MB |
     | nix-truffle, copying `++`, frames that kept their temporaries | Java OOM at 2 GB heap; ok at 4 GB | 25 s | 4.3 GB |
     | nix-truffle, `++` an immutable join flattened at first read, frames that keep only what pending cells read | ok down to -Xmx256m | 4.5 s | 502 MB (256 MB heap; 221-314 MB after a GC) |
     The join is the PRELOAD form of `++` (Join of two Series, nothing shared written): the Graal arm needs no mutation to stay
     small.  ListExtent writes a shared buffer's room in place (Nix breaking its own rule inside): an LLVM-arm lowering detail only.
   - sumo.full in memory (Kali, 12 GB cgroup, no swap): every file through kif.nix, then sumo.nix's ontology over all 201,007 forms,
     forced (9,045 classes, 90,404 ancestor links, 21,691 things, 1,765 relations: a separate Python reader's counts).  mlnix 995 MB
     -> 916 MB with `split`/`match`'s null and short strings in shared cells -> 901 MB with equal pieces of one call in one cell
     (1.7 s; parse alone 845 -> 756 MB); MLNIX_RECYCLE changes nothing here.  nix-truffle: ok at -Xmx384m (710 MB RSS; 561 MB with
     SerialGC and one compiler thread), out of heap at 256m: the live set is kif.nix's own (each form a genList of lazy elemAt over
     the unreversed list, so both stay) plus 32-byte NixLists.  A list's or a function's cell identity is observable (`[ s.f ] ==
     [ s.f ]` is false, `[ x x ]` prints «repeated», `[ s.l s.l ]` does not), so a select is not given its attribute's own cell.
   - Not done: the callers that build facts in Nix (sumo-nix's tq.nix, org/check.nix, paperclip's second stratum, the
     scenario's checks) still call datalog.nix.  Retiring it needs the chase as a primop over Nix values (the facts lowered into a
     theory, `ask`/`holds`/`why` on the closure), then each caller moved and compared.

Each step: lang 487/487 on both schedules (229 exact), mlir tests, the three workloads' answers, and the Kali difftest.
