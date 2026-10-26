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
| `Series<T>` = size + index function | runtime only: `a // b` is a `Bindings::Layer` view, flattened on first iteration | built (runtime) | -3.7% / -8.3% footprint, `docs/COLLECTIONS.md` 6b |
| `MetaSeries` | the meta is "sorted by symbol, unique": a property of `Bindings`, not a type | not a type | |
| `α`, `get(range)`, fusion | none | **not built** | a `series` dialect would have no IR consumer yet: lists are `Value**` arrays read directly in ~100 places |
| `Cursor`, `RowVec`, `ColumnMeta` | none | **not built** | |
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
