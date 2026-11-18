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
3. The fork.  LLVM: schedule son into blocks, lower with tag checks dropped where a type is known (first cut below).  Graal: export the node graph
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
     strict → force → strict inlines without end).  Speed at the first cut: a fib/foldl'/`//` mix ran ~75 ms per evaluation
     once compiled, mlnix ~40 ms for the whole process: apply a boundary (no callee inlining), each call allocating its
     frame, sets TreeMaps.  Since then: frames stay virtual where nothing escapes (625c9fb, docs/SEA-OF-NODES.md), the
     pool's bodies are appended rows whose bodies are anchors (930aa98), and a set is TrikeShed's row split in two
     (cursor/ReifiedSplitSeries2.kt): its sorted names, one array shared by every set a `{ ... }` makes (a cursor's metas),
     and its cells.  A select, a formal or a `with` keeps where its name lies in the names it met first (a Truffle inline
     cache) and searches any others; `//` merges the two sorted rows, keeping a side's names when the other's are a subset
     of them.  graal/bench/attrs.nix: 25.0 -> 22.9 ms with son, 28.1 -> 24.4 ms without, 23 MB a run less; the other six
     the same.  Next: a DirectCallNode inline cache in ApplyNode.
   - LLVM arm, first cut (done): `nix-truffle --emit-trikeshed F.nix` (graal/.../Native.kt) reads the same son-form export
     and writes F as an MLIR module in TrikeShed's ops; `mlnix-opt --trikeshed-lower-cursors` and the stock lowering mlnixci
     is built with take it to a native program that prints F's value (`scripts/nix-native.sh F OUT`).  No C++ is added: the
     emitter is Kotlin over the export, and the lowering is mlnixci's.
     - The forms: genList is `trikeshed.series n { i -> f i }` (Series.kt's `n j { ... }`), foldl' `trikeshed.fold`, length
       and elemAt `trikeshed.size` and `trikeshed.at`; an integer or a Boolean is PRELOAD's plain element (i64, i1), each
       operation checked as Nix checks it, with Nix's messages.  A closure is its row and its captures, known while writing,
       so an application is the body written in place; a body that calls itself is a func.func.
     - Laziness: a value is written where it is first needed, inside the region that needs it (an `if`'s branch, the right
       side of `&&`, `||` or `->`, a fold's step).  It is computed sooner only where son says it may be: a call's argument
       (son.body's arg_forced), a recursive body's captures (forced_captures), a fold's first accumulator that the step
       forces.  A series computes a list's elements when the list is made, so a list whose elements may fail is kept only
       where it is the printed value (`--strict` forces each in order) and refused under length, elemAt and foldl'.
     - A function made for a recursive body takes its captured integers as parameters; where the body names itself, it is
       the row over those parameters.  A closure it captures must capture only closures, all the way down (the function
       sees none of its caller's values).
     - Refused, saying what it met: sets, strings, floats, set patterns, recursion over Booleans, and the cases
       test/native's `# refused:` files name.
     - `scripts/native-check.py`: 30 of test/native's 37 cases and graal/bench's six (attrs.nix uses sets) print what mlnix
       prints (stdout, exit code, an error's first line); the other 7 are refused as their first line says.  Two mutants
       fail it: an `if` computing both branches first, `+` unchecked.  On Linux (mlnix-os, LLVM 22; the modules emitted on
       the Mac, lowered and compiled there) the 36 programs print what that build of mlnix prints.  The programs link the C
       library alone (libc; libSystem on the Mac): no libstdc++.
     - Speed on the Mac (hyperfine, 20+ runs; the Graal arm's warm runs from its 930aa98/1cbb492 bench, with son):

       | file | mlnix, process | Graal arm, process | Graal arm, warm run | native, process | compile |
       |---|---|---|---|---|---|
       | leaf | 39.2 ms | 369 ms | 18.0 ms | 1.5 ms | 0.43 s |
       | curried | 51.5 ms | 418 ms | 24.5 ms | 1.5 ms | 0.26 s |
       | prims | 40.1 ms | 383 ms | 17.7 ms | 1.5 ms | 0.27 s |
       | slots1 | 33.3 ms | 378 ms | 15.7 ms | 1.4 ms | 0.26 s |
       | slots9 | 44.4 ms | 385 ms | 19.8 ms | 1.4 ms | 0.27 s |
       | fib | 22.8 ms | 335 ms | 2.2 ms | 1.3 ms | 0.27 s |

       Most of a native run is the process: a program that only prints `<LAMBDA>` takes 1.2 ms.  Peak RSS: leaf 3.5 MB
       (mlnix 93 MB), fib 1.2 MB (44 MB).  These files are the best case (integer loops, no sets or strings), and the
       compile costs more than ten mlnix runs, so this pays where a program is compiled once and run many times.
     - Found on the way: the arms' export reader (Graph.kt) read every JSON number as a Double, so an integer past 2^53 lost
       its low bits (`9223372036854775800` read as Long.MAX_VALUE); and mlnix's `+` overflow error printed the wrapped sum
       for the left operand (the upstream test eval-fail-overflowing-add is now exact).
     - Next: sets as `trikeshed.series2` (attrs.nix), strings as CharSeries, and lazy elements (a series as a view) so
       length and elemAt need not refuse.
4. `//` as `trikeshed.layers` for large bases: on nixpkgs-73 the ~800 merges with a side of 4096+ rows copy ~260 MB of the arena's
   311 MB of flat merges (b58d02c chose flat for speed: layering every merge read 2.5-7% slower).  The layer here is only for the
   package set.  Fix the stale `Bindings::Layer` reference in TS_LayersType's description in the same change.
5. confix's index as twin + series; its LLVM lowering moves below trikeshed.
   - Built (branch confix-trikeshed): `confix.index` scans a `!trikeshed.series<i8>` into ConfixIndexK's rows as a
     `!trikeshed.cursor<"ConfixIndex", [!trikeshed.twin<i32>, i8, !trikeshed.twinpacked<i32>]>` (Spans as (open, close), Tags,
     DirectChildren as (first, count) into the kid series it also makes), and `confix.columns` is the Columns facet: over a
     series of object rows, a cursor of one i32 column per member name, the value's row or -1.  Both lower in
     trikeshed-lower-cursors' conversion, through CursorLoweringInterface (include/Composite/CursorLowering.h): the scanner's
     arrays are series buffers and every read after the scan is a trikeshed op.  The scan itself is still confix.ll.
   - trikeshed-lower-cursors also lowers what the facets are read with: slice (a view: a series is now
     `memref<?xT, strided<[1], offset: ?>>`, the same descriptor, so a caller passing offset 0 sees no change), compare,
     sorted (stable) and bisect with a comparator region, and j/first/second on a pair of two i32 (one i64, the first high).
     test/mlir/confix-index.mlir checks every column, both facets, and a sort and a search of the text's strings against a
     separate reader of the text.
   - Not done: Depths, KeyToChild for a key known only at run time, YAML (its retry on Room), groupBy.
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
   - sumo-nix's tables over TrikeShed (built, branch confix-trikeshed).  `kif.terms`, `kif.facts` and `kif.rules` give a
     theory as TrikeShed forms: the terms a cursor (tag, name, kids) in the shape of Confix's index, with the kid series and
     the names text; the facts (term, file); the rules (antecedent, consequent, file); `kif.atom_row` an atom's row.
     `kif-to-trikeshed` lays the tables out as constant buffers seen as those series and cursors (an atom's row a constant)
     and removes the theory, so a query over it is trikeshed and sumo ops that `trikeshed-lower-cursors` takes to loops.
     Each relation is a cursor of rows: `sumo.relation` is SumoClassifier.kt's taxonomy projection (`subclassEdges`,
     `instanceEdges`, the domain slots) with sumo.nix's reading of an argument (anything but a list: SumoClassifier also
     drops variables, string literals and a position that is not an integer), lowered below TrikeShed through
     CursorLoweringInterface as confix's ops are.  `trikeshed.adjacency` is the counting sort of ClosureIndex.build and
     SumoClassifier.of (edges to each node's (first, count)), and `trikeshed.closure` ClosureIndex's ancestor sets in that
     DirectChildren shape.  test/mlir/kif-trikeshed.mlir is sumo.nix's `parents`, `ancestors`, `classOf` and `domains` in
     those ops, checked against sumo.nix's own evaluation of the same KIF (test/kif/taxonomy-oracle.nix through `mlnix
     eval`); test/mlir/closure.mlir checks adjacency and closure on a cycle and a self edge.  `scripts/sumo-trikeshed.sh`
     runs the query, compiled, on sumo.full's 78 files (Kali, each step in a 4 GB cgroup without swap, load 6-8 on 8
     cores): identical to sumo.nix in 201,007 forms, 9,045 classes, 9,040 with a parent, 90,404 ancestor links, 21,691
     things, 1,765 relations, Human's 17 ancestors, and the ancestor count of each of the 9,040 classes in name order.
     | step | time | peak RSS |
     | sumo.nix on `mlnix eval` (kif.nix's parse, then the tables, forced) | 3.00 s | 902 MB |
     | mlnix-kif, the text into kif IR, printed (31 MB of MLIR) | 2.64 s | 249 MB |
     | mlnix-opt: that text parsed again, kif-to-trikeshed, trikeshed-lower-cursors | 3.96 s | 332 MB |
     | mlir-opt to the LLVM dialect; mlir-translate; clang -O2 | 0.52 + 1.59 + 2.20 s | 188-235 MB |
     | the compiled query (17 MB, the tables inside) | 0.07 s | 78 MB |
     (The first version, with the selections written by hand in trikeshed ops, ran in 0.09 s: it found each relation's
     atom by a scan of the terms.)  kif-to-nix does not track sumo.nix better: it lowers a theory to a nix.expr of its
     facts and rules, which is sumo.nix's input, so its tables would still be sumo.nix evaluated by Nix (the first row).
     Not done: the tables straight from mlnix-kif (most of the 10.9 s before the query runs is printing the theory as text
     and parsing it again); tq.nix's queries and SumoClassifier's other masks (instance types closed upward, disjointness)
     over the closure.
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
   - Who checks and who searches (Lean's kernel, Vampire, these layers): REASONING-SPLIT.md, three tests on Kali with
     their tables in bench/kali/reasoning-20261117/.

Each step: lang 487/487 on both schedules (229 exact), mlir tests, the three workloads' answers, and the Kali difftest.
