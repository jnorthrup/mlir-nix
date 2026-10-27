# The PRELOAD composite

`../TrikeShed/PRELOAD.md` is TrikeShed's kernel: most shapes collapse back to `Join`, `Series` is
the default indexed abstraction, `Cursor` is its dataframe form, side effects sit at a userspace
ring. Its own rules apply here: nothing is built until something consumes it, and a layer that
nothing uses is a placeholder. This is what exists, what consumes it, and what does not.

| PRELOAD | here | status | consumer / evidence |
|---|---|---|---|
| `Join<A,B>`, `Twin<T>`, `a j b` | dialect `join`: `!join.pair<A,B>`, `join.make/first/second`, folds | built | `test/mlir/join.mlir`; layout test with a mutation |
| `TwInt`: Twin<Int> collapsed to a Long | `join-densify`: `!join.pair<i32,i32>` -> `i64`, first component high; `include/Composite/Pack.h` is the same word for C++ (a `static_assert` ties it to the test constant) | built | the lexer's tokens |
| the JVM stops at Long; LLVM has `iN` | the same pass, any width: a segment `<i32,<i32,i32>>` -> `i96`, `Twin<i64>` -> `i128`, floats by their bits | built | `join.mlir`, `join-invalid.mlir` (a pair of `index` is refused) |
| segments: "index first, reify later", no mutation of the mmap'd input | tape lexer: a token is a `TwInt` (start,end) of an immutable `nixfe::Source`; text that is not a slice (an unescaped string) is appended to a pool | built | 40,131 files parse to byte-identical ASTs (`scripts/parse-corpus.py`); parser 2.49 -> 1.02 s per 104 MB |
| strref | no dialect of its own: it is a join of (buffer, start, end), `i96` dense | decided | no standalone MLIR dialect fits (IREE `util.buffer`, LingoDB `util.varlen32`, `memref` + `subview`, upstream resource blobs are the nearest; none is usable without its host project) |
| `Series<T>` = size + index function | runtime: `a // b` is a `Bindings::Layer` view, flattened on first iteration; C++: `composite::Series` is `Join<uint32_t, F>` with unchecked indexing (`include/Composite/Series.h`) | built | -3.7% / -8.3% footprint, `docs/COLLECTIONS.md` 6b; the free-name view of `Gen::defer`, `docs/SEA-OF-NODES.md` |
| `MetaSeries` | the meta is "sorted by symbol, unique": a property of `Bindings`, not a type | not a type | |
| `α`, `get(range)`, fusion | `α` in `Series.h`, infix over a Series, fusion a `static_assert`; no `series` dialect | `α` built; `get(range)` **not built** | `Gen::defer` projects each free name through the live scope; a dialect would still have no IR consumer: lists are `Value**` arrays read directly in ~100 places |
| `↺`, left identity / constant anchor | `composite::anchor`: the first force of a cell mints it, every read after is the constant it produced | built | `EvalState::bodyOf`, the body of a deferred lambda |
| a list that is mutated says so in its type | `composite::MutableSeries`: `append`, `drain`, `view` | built (the accumulate half) | the columns of `nixfe::FilePool`: rows accumulate as lowering defers lambdas, drain as evaluation mints them |
| `Cursor`, `RowVec`, `ColumnMeta` | `composite::Cursor<T...>`: a MutableSeries per column plus the column names | columns built; the `Series<RowVec>` face **not built** | `nixfe::FilePool`, the pool of deferred lambdas; `MLNIX_STATS` prints it by column name |
| Confix index, JSON as a tree of cursors | none; `fromJSON` still builds the whole value | **not built** | a lazy `fromJSON` needs a lazy value; no benchmark workload spends measurable time in it |
| userspace uring, mapped memory kept apart from I/O | `nixprefetch`: record the files an evaluation touches, replay them through one ring; imports are mapped read-only | built (not CCEK) | cold start -19.5% / -16.8% on Linux, `docs/IO.md` |

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
