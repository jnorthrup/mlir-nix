# The PRELOAD composite

`../TrikeShed/PRELOAD.md` is TrikeShed's kernel: most shapes collapse back to `Join`, `Series` is
the default indexed abstraction, `Cursor` is its dataframe form, side effects sit at a userspace
ring. Its own rules apply here: nothing is built until something consumes it, and a layer that
nothing uses is a placeholder. This is what exists, what consumes it, and what does not.

| PRELOAD | here | status | consumer / evidence |
|---|---|---|---|
| `Join<A,B>`, `Twin<T>`, `a j b` | dialect `trikeshed` (`include/Composite/TrikeShed.td`): `!trikeshed.join<A,B>`, `trikeshed.j/first/second`, with the laws in their descriptions; in C++ `composite::Join` and `a |j| b` (`Series.h`) | declared; the C++ is consumed | the parser (`joins` of a group's values and positions), `Value::items()` in `==`; no IR emits a `trikeshed` op: the ops document the algebra, as `NixSyntax.td`'s document the layers |
| `TwInt`: Twin<Int> collapsed to a Long | the layout `TrikeShed.td` states for a Join of fixed-width scalars (first side high); `include/Composite/Pack.h` is that word in C++, its `static_assert`s the layout's constants | built | the lexer's tokens, a body_index, a position, a band's span |
| the JVM stops at Long; LLVM has `iN` | stated in `TrikeShed.td` (a segment `<i32,<i32,i32>>` is an i96, `Twin<i64>` an i128); `Pack.h`'s `dense` builds any nest up to 128 bits | built in C++; the IR pass that applied it (`join-densify`, 143 code lines with its dialect) is cut: its only consumer was its own test | `Pack.h` `static_assert`s |
| segments: "index first, reify later", no mutation of the mmap'd input | tape lexer: a token is a `TwInt` (start,end) of an immutable `nixfe::Source`; text that is not a slice (an unescaped string) is appended to a pool | built | 40,131 files parse to byte-identical ASTs (`scripts/parse-corpus.py`); parser 2.49 -> 1.02 s per 104 MB, then 0.86 s once the tree owned no string (the name row), then 0.375 s once the tree was a region and the lexer took the common cases without the longest-match (the region row) |
| the tree is a region of Series | was `composite::Slice<T>` and `composite::Grow<T>`, `n j (i -> p[i])` over cells in the thread's arena, in place of every `std::vector` a node held | **cut with the tree** (41 code lines, `exp/treeless`): no front end builds a node; a band's statements are a view of the scan's `ends` (`composite::series`) and a scope is a run of a bindings Cursor | the history of the cut: the parser over the corpus went 0.757 s -> 0.375 s with them (-50%), and the treeless parse needs none of it |
| a position is a segment too | `nixfe::PackedPos` (`include/Nix/Pos.h`): (file, line, column) in the 64 bits of a `TwInt`, bit 63 set so a decoder can tell it from a `Location` pointer; the `pos` property (`I64Prop`, default 0, in no assembly format) of the 23 ops that can fail, and `positions` / `formal_locs` as `DenseI64ArrayAttr`. `PosPtr` is a packed word, an op (decoded only when a message prints it) or a `Location` (a devirtualized primop keeps its call's `FileLineColLoc`: an IRDL op has no property) | built | Mac wall -9.2% / -8.7% demand, -11.8% / -13.0% eager (toplevel / nixpkgs-73), footprint -1.6% / -2.3%, identical hashes; kali (x86_64, WSL2, i7-6820HK, Linux, three interleaved A/Bs, min of 5 to 9 runs; medians swing +-8% with the host's load) demand -1.5% / -3.2% / -1.4% (one cell +4.7%), eager -5.6% / -5.5%, so on that host the gain is a few percent, not a tenth; the 467 lang cases print the same bytes on both schedules (`run-lang-tests.py --save`, `diff -r`), 72/72 difftest, 14/14 FileCheck |
| a name is a segment too | `nixfe::Name` (`include/Nix/Name.h`): a pointer and a length into bytes that live for the process, 16 bytes with the evaluator's Symbol (+1) cached in it by the first evaluation that asks, so a name in code nobody runs is never hashed. The ODS properties `Nix_NameProp` / `Nix_NamesProp` (`NixBase.td`) of `nix.str`, `nix.path`, `nix.builtin`, `nix.with_var`, `nix.formal`, `nix.attrs` (names, positions) and `nix.select` / `nix.has_attr` (path; the null name is a computed component). Properties are not inherent attributes, so the generic form is `<{path = [...]}>`. The tree holds them too: `ExprString`, `ExprPath`, `ExprVar`, `AttrName`, `Formal`, a lambda's `arg` / `name` and the key of an `ExprAttrs` are `Name`s, and `Parser::nameOf(token)` turns the lexer's `TwInt` span into one without a copy. Only text that is not a slice of the input (an escaped string, an indented string with its indentation stripped, a derived path) is copied, into `Name::persist`'s arena; a `Source` is kept for the life of the process so a slice outlives the parse | built | IR half: Mac wall -6.6% / -6.8% demand, -8.8% / -8.3% eager (toplevel / nixpkgs-73), footprint +-1%; kali demand -5.6% / -5.2%, eager -13.3% / -7.1%, footprint 1635 -> 1640 MB. Tree half: the 40,132-file corpus prints identical ASTs and parses in 0.863 s against 1.012 s (-14.7%); in situ demand -2.1% / -2.4%, eager -2.6% / -1.4%, footprint -0.9% to -2.4%. Identical hashes; 0 of 1,401 lang outputs differ, 72/72 difftest, 14/14 FileCheck |
| strref | no dialect of its own: it is a join of (buffer, start, end), `i96` dense | decided | no standalone MLIR dialect fits (IREE `util.buffer`, LingoDB `util.varlen32`, `memref` + `subview`, upstream resource blobs are the nearest; none is usable without its host project) |
| `Series<T>` = size + index function | runtime: `a // b` is a `Bindings::Layer` view, flattened on first iteration; C++: `composite::Series` is `Join<uint32_t, F>` with unchecked indexing (`include/Composite/Series.h`) | built | -3.7% / -8.3% footprint, `docs/COLLECTIONS.md` 6b; the free-name view of `Gen::defer`, `docs/SEA-OF-NODES.md` |
| `MetaSeries` | the meta is "sorted by symbol, unique": a property of `Bindings`, not a type | not a type | |
| `α`, `get(range)`, fusion | `α` in `Series.h`, infix over a Series, fusion a `static_assert`; no `series` dialect | `α` built; `get(range)` **not built** | `Gen::defer` projects each free name through the live scope; a dialect would still have no IR consumer: lists are `Value**` arrays read directly in ~100 places |
| `↺`, left identity / constant anchor | `composite::anchor`: the first force of a cell mints it, every read after is the constant it produced | built | `EvalState::bodyOf`, the body of a deferred lambda |
| a list that is mutated says so in its type | `composite::MutableSeries`: `append`, `drain`, `view` | built (the accumulate half) | the columns of `nixfe::FilePool`: rows accumulate as lowering defers lambdas, drain as evaluation mints them |
| `Cursor`, `RowVec`, `ColumnMeta` | `composite::Cursor<T...>`: a MutableSeries per column; the ColumnMeta and the column indices are the cases of an enum generated from `TrikeShed.td` (`BandCol`, `PoolCol`, `BindCol`), so `col<PoolCol::Op>()` and `MLNIX_STATS`'s column names come from the declaration | columns built, and `row(i)`, a row copied out as a tuple (a mint reads its pool row so, where `Row` and `read()` were 17 lines); `append`, `clear` and `reserve` fold over the columns; the `Series<RowVec>` face is `rows()`, the same columns as one Series of row tuples, pinned by `rowSeriesHolds` -- a use that reads one member dissolves the copies of the rest as dead code, so no lazy projection beside it | `confix::Bands`, `nixfe::FilePool`, the parser's bindings (a scope is a run of rows, first j count) |
| Confix index, JSON as a tree of cursors | none; `fromJSON` still builds the whole value | **not built** | a lazy `fromJSON` needs a lazy value; no benchmark workload spends measurable time in it |
| the Confix index of a Nix source | `confix::scan` (`include/Nix/Confix.h`, `lib/Frontend/Confix.cpp`): the lexer's state machine without its tokens, every rule shared with the lexer in `include/Nix/LexRules.h`; the bands (`{ }`, `[ ]`, `( )`, strings, `${ }`, `let ... in`) as a `Cursor<TwInt, kind, TwInt>` in the order they open, and per band its qualified semicolons and commas (layers 0 and 1 of `NixSyntax.td`) | built, consumed | the parser: the heads of a `let`, a `rec` set and a formals list (layer 2), and a check of every statement end it meets; `mlnix-parse -b` derives the same table from the real lexer's tokens: 39,646 files and 15,984 mutants, 0 disagreements; the scan runs at 1.86x the lexer's speed |
| userspace uring, mapped memory kept apart from I/O | `nixprefetch`: record the files an evaluation touches, replay them through one ring; imports are mapped read-only | built (not CCEK) | cold start -19.5% / -16.8% on Linux, `docs/IO.md` |

## Vestigial, counted (2026-10-27)

What is in the tree because of PRELOAD and has no consumer in what `mlnix` runs:

- The `trikeshed` ops (`TrikeShed.td`): declarations, generated for no C++; the enums of the same file are generated and used.
- `experiments/`: 6 files, 1,109 lines, built by nothing, cited by `docs/COLLECTIONS.md` and `docs/IO.md`. Cut from the tree; the sources are in
  history at `dd55950`.
- The `join` dialect and its `join-densify` pass (`lib/Composite/Composite.cpp` 174 lines, `Composite.h` 29, `JoinOps.td` 89, two tests):
  cut, their declarations folded into `TrikeShed.td`; the sources are in history before `799900b`.

Where the algebra is the shape but not the type: `Value::list`, the strings and the attribute arrays are a size and cells in the
arena, written by hand. `lib/` and `include/` (outside `Composite/`) still hold 98 `std::vector`, 50 `std::map`, 53 `std::set` and
17 `std::function`; the vectors are mostly in `Builtins.cpp` (17), `LocalStore.cpp` (14), `Formats.cpp` (9) and `Eval.h` (9).

## Span census (2026-10-27)

TrikeShed code is span code: a pointer and a count, indexed by whoever built it. `scripts/span-census.py` counts, by regex, the
mentions of the non-owning types (`std::string_view`, `llvm::StringRef`, `ArrayRef`, `Slice`, `nixfe::Name`) against the owning ones
(`std::string`, `std::vector`, `std::map`, `std::set`, `std::function`, `SmallVector`), and the signatures that take or return each.

    front end   3,722 lines   spans: string_view 32, StringRef 28, ArrayRef 12, Slice 10, Name 50;  std::string 55, vector 17
                              parameters view 39 / owning 12, returns view 4 / owning 11
    evaluator   5,690 lines   spans: string_view 75, StringRef 20, ArrayRef 3, Slice 0, Name 5;      std::string 398, vector 48, map 18, set 16
                              parameters view 54 / owning 64, returns view 9 / owning 57
    store       2,704 lines   spans: string_view 100;                                                 std::string 452, vector 33, map 32, set 39
                              parameters view 73 / owning 99, returns view 1 / owning 80
    dialects      907 lines   spans: StringRef 17, ArrayRef 2, Name 10;                                std::string 6

So the front end is span code (the tree is a region of `Slice`s, a token is a span, a name is a pointer and a length) and the
evaluator and the store are not: `Slice` appears nowhere in them, a list is a `Value **` read with `listSize()` in 72 + 54 places,
the primops take `Value **args` without a count, and strings are built and returned as `std::string`. None of the
(pointer, count) pairs in the arena (`Bindings`, `StringContext`, a list, a `Frame`) is a `Slice`; `Name` and `Source` are pairs of
their own that hand out a `string_view`. What the owning containers cost, from the Mac profile of the evaluator thread (3,877 busy samples, frames of the container's own
methods, so a lower bound: what the compiler inlined has no frame): `std::basic_string` 3.2%, `std::map` / `std::set` 3.4%,
`std::vector` 0.15%. More than half of it is the derivation path: `Derivation::unparse` 0.6% in strings and 0.5% in maps, and the
copy, the assignment and the destruction of a `Derivation` 1.5%; then `evalConcatStrings` 0.4%, `appendEscaped` 0.4%,
`Hash::to_string` 0.3%. (`std::function` is 1.5% at most: `NarWriter::dump` 1.2%, `callPrimOp` 0.3%; the 39% under
`runWithLargeStack` is the whole evaluation.)

## Measured and left alone

- **A segment attribute for `nix.str`.** The toplevel evaluation creates 223,587 string literals,
  7.08 MB of text in all, 107,239 of them longer than 15 bytes. That bounds what hashing and copying
  them into `StringAttr`s can cost, and every folder that matches `StringAttr` would have to learn a
  second attribute. Names are the opposite case: they repeat, a `StringAttr` unifies them, and a
  per-occurrence segment would not.
- **mmap against read-and-copy.** Neutral on time (-0.1%, 0.0%), 26 MB lower footprint. Kept
  because the input is never written or copied, not because it is faster.
- **io_uring for the hot path.** Hot, the file syscalls are 61k of 327k and cost about a percent.
  The ring pays when the page cache is cold.

## Failures and corrections

- Positions first came out of `Value::getLoc()` as nothing for a lambda argument: a block argument carried the position of its lambda, which the `pos` property had not replaced. One of 1,401 outputs differed (`eval-fail-zipAttrsWith-4.err` lost a source excerpt) and the exact-pass count, 209 of 467 before and after, would not have shown it. Compare bytes, not counts.
- A custom assembly directive that prints nothing still emits its leading space: every op line ended in one and `modes.mlir` (`{{$}}`) failed. A default-valued property mentioned in no format is neither printed nor parsed, which is what was wanted.
- I called I/O a small fixed cost from a warm-cache profile. Cold it is 29% of the run.
- The first ring benchmark read nothing (`O_CLOEXEC` on a direct open is `-EINVAL`) and reported a
  great time; the byte count caught it.
- A "hot" benchmark row followed a cache drop and was cold.
- On MLIR 22 stock CSE does not unify two identical IRDL-defined ops; 3 of 12 FileCheck tests fail
  there. The 466 lang tests do not depend on it.
- The first `Series.h` said it held only what the sea of nodes consumes. `Join`, `Twin` and `view()` had no
  caller, and `view()` held a raw pointer into cells that a later append moves. Checked against this file's
  rule (nothing is built until something consumes it): `Series` is now the `Join` alias, `j` pairs each
  free name with its resolution in `Gen::defer`, `view()` indexes through the series and feeds the stats
  loop, `anchor` is `bodyOf`'s one line, and `Twin` and `empty()` are deleted.
- The upstream lang suite is blind to the free-name rules of the demand schedule: a mutation that read
  `inherit x;` inside its own group passed 466/466. `test/lang/eval-okay-demand-scope.nix` (expected
  output from Nix 2.35.4) kills it and six others; `docs/SEA-OF-NODES.md` has the table.
