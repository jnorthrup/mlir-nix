# Fill and drain

A container that is filled (append) and then drained into its final shape is a MutableSeries in PRELOAD's words: "a list that is
mutated says so in its type; it accumulates, then drains".  Written as `std::vector`, `std::string` or `std::map` the pair is invisible
to the reader and to the optimizer.  This is the map of where the code does it by hand, what each pair costs when it runs, and what
the translation is.  Static part: `scripts/fill-drain-map.py [--sites|--md]`.  Dynamic part: a build configured with
`-DMLNIX_FILL_STATS=ON` (the hooks sit in hot functions, so the default build has none) prints "== fill/drain sites" under
`MLNIX_STATS=1` (Eval.cpp, `kFill`).  Numbers below are the demand schedule on the Mac, toplevel | nixpkgs-73.

> The counters this document's tables came from (`-DMLNIX_FILL_STATS=ON`, `statFill`, `MLNIX_FILL`) were cut once the rows were decided;
> they are in history (`git log -S MLNIX_FILL`).

## 1. The vocabulary, and what is built

| TrikeShed (`src/commonMain/.../collections`) | what it is | C++ here |
|---|---|---|
| `MutableSeries` | a Series that takes writes: `append`, `insert`, `set`, `removeAt`, `clear`, `snapshot()` | `composite::MutableSeries` (a `std::vector`; `FilePool`), `Grow` (a Slice still being filled, in a region) |
| `RingSeries` | fixed capacity, a power of two, mask indexing; `append` into a full ring displaces the oldest and fires `evict`; a null listener is a drain to nowhere; `copyInto` drains in at most two runs; `clear` is two fills | not built |
| `ChunkedMutableSeries` | a table of fixed-size chunks (4096 by default), no copy on growth, one division per index while uniform | not built |
| `COWArrayBackend` | growable, `snapshot()` shares the array, `subscribe` observers see (before, after) | not built |

A ring that nobody drains still wraps, and a wrap is an event: `evict` fires with the displaced element whether or not anything listens.
Counting those events is a spiking unit: it integrates appends up to its capacity and fires on overflow.  TrikeShed's monitor does the
same with bins ("explicit spiking retains the first observation per bin and counts the rest").  In an evaluator the natural unit is
a call counter or a recent-callee ring per site: the spike is the signal that buys the next rung of resolution.

## 2. Rules that apply to every translation

- Zeroing.  A ring or a fill buffer is raw storage: its window `[head, head + count)` is the only part any operation can name, so the
  tail is unobservable and nothing writes zeros into it, at construction or at `clear` (which resets two integers).  Zeroing is for a
  cell whose null is state: `anchor` cells, `Frame::slots`, the Body column of `FilePool`.  Those take it from the arena, whose fresh
  pages the kernel already zeroed.
- Cache.  A fill buffer lives inside L1 (its capacity times the cell size is a fraction of L1d), and a log or a chunk is sized to a
  fraction of L2.  The sizes differ by a factor of eight between the two hosts, so they are read once and kept (section 7).
- Spans.  The drain of a fill is a `Slice`: pointer and count, bounds set when the arena allocates.  On a capability machine (CHERI) the
  bounds are enforced by the hardware, which makes a Series that does not check its index safe for free.  Nothing may hide pointer
  bits above the address (section 8).

## 3. Recognized today

- `BindingsBuilder` (`SmallVector<Attr, 12>` filled by `insert`, drained by `finish`: sort, copy into the arena).
- `Grow` / `Slice`: the whole AST region (parser).
- `FilePool`: a Cursor of MutableSeries rows, one per deferred lambda, filled at lowering and read in place.
- The arena itself: a fill with no drain, 4 MiB slabs that are touched one slab ahead.

## 4. The map, static

269 local containers that are filled or drained, in 32 files (`fill-drain-map.py`; a heuristic scan of text, read the sites before
believing a class):

| class | sites |
|---|---|
| text built, then used (strings, ostringstream) | 81 |
| vector filled, then walked | 61 |
| map/set filled, then walked | 50 |
| text -> arena string (`mkString`) | 37 |
| vector -> copied / returned | 17 |
| vector -> op operands (MLIRGen: `SmallVector<Value>` into `Op::create`) | 12 |
| vector -> arena list (`mkList` + copy loop) | 10 |
| set -> string context | 1 |

## 5. The map, dynamic

```
site                          fills (toplevel | nixpkgs-73)   cells/fill   over the inline capacity
BindingsBuilder                1,126,897 | 743,509             3.0 | 3.6    1.6% | 2.4%   (capacity 12)
callFunction applied           1,234,451 | 506,404             0.2 | 0.1    0.0%           (capacity 6)
callFunction all               1,135,100 | 473,227             1.7 | 1.8    0.0%           (capacity 6), max 3
evalOp apply args              3,214,633 | 2,104,299           1.7 | 1.7    0.1% | 0.0%    (capacity 4), max 13
evalConcatStrings                 67,457 | 76,190              167 | 267 B  57.9% | 73.5% (std::string SSO 15)
mkList, every list             1,213,940 | 776,629             1.5 | 2.0    max 24,884
mkString, every string         2,263,304 | 2,247,748           15 | 19 B    35 MB | 43 MB in all
callPrimOp                     2,486,530 | 1,611,608           arity 1.7 | 1.6
the seven builtins counted that fill a std::vector<Value *> and mkList it:
  concatLists + concatMap + filter + catAttrs + sort + genericClosure + split
                                 144,288 | 32,068              1.3 | 1.7
```

Reading it:

- The inline buffers are the right size.  Only 1.6% | 2.4% of attribute sets, 0.1% of apply argument lists and no partial application
  leave their buffer for malloc.  L1 is not the constraint on these; the number of times each runs is.
- The hand-drained `vector<Value *>` -> `mkList` builtins that the PRELOAD sweep found are cold: the seven counted here (of the 10 sites
  the scan classes that way) fill 144k times in a run with 3.2M apply argument lists.  They are a discipline fix, not a speed one, and are not first.
- A fill buffer with inline storage that stays on the stack is free.  Taking three of them out of the call path (rows 2, 3, 4) read
  as -1.3% to -1.6% over 11 runs and as -0.5% | -0.1% over 25: neutral, and the ceilings written for them (fills times an assumed 10 ns)
  were wrong.  What costs is bytes that reach the arena: attribute cells and lists.
- Lists are tiny: mean 1.5 | 2.0 cells over 1.2M | 0.8M lists.  A list of at most two cells fits in the two payload words of a Value.
- Strings are tiny (mean 15 | 19 B) except the interpolations: 58% | 74% of `evalConcatStrings` results do not fit a `std::string`'s
  inline 15 bytes, so each is a malloc, then a copy into `str`, then a copy into the arena.

## 6. Translations, by evidence

| # | pair | translation | evidence | status |
|---|---|---|---|---|
|  1 | `Attr` cell 24 -> 16 B | the pos in a cell is a 32-bit handle into an append-only table (the WAL of positions); AttrsOp carries a base, not an array | spike: max RSS -6.3%, peak footprint -6.7%, wall -0.7 / -1.2 (demand) -1.7 / -1.0 (eager); hashes identical | spike `exp/dense-attr` f6a8d0b; real change `exp/attr-pos-table`  |
|  2 | `callFunction all` | no fill when `applied` is empty: pass `args + i` | 1.14M / 0.47M copies of mean 1.7 cells | tried with 3 and 4: neutral (`exp/fd-calls`): demand toplevel -0.5%, nixpkgs-73 -0.1%, 25 runs |
|  3 | `evalOp` apply args | a fixed array for up to 4 operands, the SmallVector only past that | 3.2M / 2.1M fills, 0.1% over | tried with 2 and 4: neutral  |
|  4 | `mkString` | an overload without a context: the default argument builds a `std::set` per string | 2.26M / 2.25M calls | tried with 2 and 3: neutral  |
|  5 | lists of at most 2 cells | stored in the Value, behind `std::span<Value *> Value::list()`; the 72 `list.elems` and 54 `listSize()` sites go through the span first | 1.2M / 0.8M lists, mean 1.5 / 2.0 cells | not started; about 0.9% of memory (estimate)  |
|  6 | `evalConcatStrings` | a `SmallString<256>` scratch that string parts append to from `sv()`, drained once into the arena | 67k / 76k fills, 11 / 20 MB | not started; under 0.5% (estimate)  |
|  7 | the derivation path | flat records filled in order, one sorted drain into the ATerm; a `Derivation` moved, not copied | 3.4% of the thread in map/set frames, 1.5% copying a `Derivation` (profile, inlined frames missing, so a lower bound) | not counted dynamically yet  |
|  8 | `PosPtr` | the tag in the low bit of an aligned pointer, not bit 62 | CHERI (section 8) | after 1  |
|  9 | the ring | `Ring<T, N, Evict>` over raw storage; per-site recent-callee and select-index rings whose eviction is the spike that triggers the next rung | the ladder in docs/MLIR.md | not built  |

Estimates are fills times an assumed cost; none is a measurement until it has been through an interleaved A/B with identical hashes.

## 7. Cache geometry, read once

| host | L1d | L2 | L3 | line |
|---|---|---|---|---|
| Mac, Apple M3 Pro, performance cores (`hw.perflevel0.*`) | 128 KiB | 16 MiB, shared by 6 | - | 128 B |
| Mac, efficiency cores (`hw.perflevel1.*`) | 64 KiB | 4 MiB | - | 128 B |
| Mac, what `hw.l1dcachesize` / `hw.l2cachesize` say | 64 KiB | 4 MiB | - | 128 B |
| kali, i7-6820HK under WSL2 (sysfs and `sysconf` agree) | 32 KiB, 8-way | 256 KiB, 4-way | 8 MiB, 16-way | 64 B |

The plain sysctl names report the efficiency cores on the Mac, so a naive read is wrong by a factor of two and eight for the cores
the evaluator runs on.  The impression is taken once, in this order: environment override, then an rc file (`l1d`, `l2`, `line`,
`source`, `cpu`: it is also the place to correct a wrong reading), then the OS (`hw.perflevel0.*`, sysfs `cache/index*`, `sysconf`),
then a pointer-chasing sweep whose knees are the sizes, written back to the rc file.  Not built.

## 8. Toolchain

- C++23.  LLVM and MLIR are C++17 (`llvm-config --cxxflags` is `-std=c++17` on 23.1.1; the coding standard says "standard C++17"), and the
  installed headers use no `std::span`, `<ranges>`, `<concepts>`, `std::expected`, `consteval` or `std::format`.  A C++23 consumer
  of MLIR was reported to hit header errors in August 2025 (an incomplete `AnalysisState` in `DataFlowFramework.h`).  This tree,
  configured with `-DCMAKE_CXX_STANDARD=23`, builds on the Mac (Apple clang 17, LLVM 23.1.1 headers) with one missing `#include <exception>`
  in Eval.cpp; against the C++20 build, 9 interleaved runs, hashes identical in all four cells: demand wall -1.6% | -0.2%, eager -1.8% | 0.0%,
  rss unchanged.  On kali (clang 22.1.8, libstdc++ 16, MLIR 22) the same configure line builds `mlnix` and `mlnix-opt` with 0 error lines
  (not gated or benchmarked there).  Apple clang 17's libc++ has `std::span`, `std::ranges` (with `ranges::to`, `chunk_by`, `starts_with`),
  `std::expected`, `std::mdspan`, `std::flat_map`, `std::print`; it has **no** `views::zip`, `views::enumerate` or `move_only_function`.
  kali's clang 22 with libstdc++ 16 has all of them.  The portable set is the first list; `llvm::zip` and `llvm::enumerate` cover
  the rest.
- What MLIR has that the standard acquires later: `ArrayRef` / `MutableArrayRef` (`std::span`; no `std::span` constructor in 23.1.1),
  `StringRef` (`string_view`, converting both ways), `function_ref` (C++26 `function_ref`), `unique_function` (`move_only_function`),
  `Expected` / `Error` (`std::expected`), `SmallVector` (C++26 `inplace_vector`, with a heap fallback), `llvm::zip_equal` /
  `enumerate` / `concat` / `map_range` / `make_filter_range` / `drop_begin` / `reverse` (ranges views).
- CHERI.  The only code that does not survive a capability machine is the `PosPtr` scheme: `kOpPosTag` sets bit 62 of an `Operation *`
  (`NixDialect.h:86-88`, decoded at `NixDialect.cpp:164-177`), `PackedPos::tag` is bit 63 of a word cast to `const void *`
  (`posOfWord`, `NixDialect.h:97`), and `static_assert(sizeof(void *) == 8)`.  A capability whose address leaves its bounds loses its tag and
  cannot get it back by clearing the bit.  Row 1 removes it from the cell; row 8 from the rest.  Also `static_assert(sizeof(Value) == 24)`
  should read `3 * sizeof(void *)`.  The arena's `uintptr_t` round-up stays inside its reservation and is fine.
