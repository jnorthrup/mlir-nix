//===- TrikeShed.td - borg.trikeshed.lib as an MLIR dialect ------*- tablegen -*-===//
//
// ../TrikeShed/src/commonMain/kotlin/borg/trikeshed/{lib,cursor}/ is the kernel of this compiler, and this file is that
// package as IR.  Join is the one binary composition; MetaSeries<I, T> is a bound and an index oracle; Series<T> is the
// Int-indexed one; Series2 is a series of pairs with two projections; Cursor is its dataframe form; α projects lazily;
// ↺ anchors a constant; a list that is mutated says so in its type.
//
// The dialect is generated (TrikeShed.h.inc / TrikeShed.cpp.inc): `!trikeshed.series<!nix.value>` and `trikeshed.j`,
// `trikeshed.alpha`, `trikeshed.joins`, `trikeshed.select`, `trikeshed.slice`, `trikeshed.bisect` are ops a module can
// hold, print, parse and verify.  The runtime that interprets them is include/Composite/Series.h.  That is the point:
// the geometry of this compiler's data is declarable rather than implied by C++.
//
//   lib/Join.kt        Join<A,B>                  !trikeshed.join<A, B>        j, first, second
//                      Twin<T>                    !trikeshed.twin<T>           (Join<T,T>)
//                      TwinPacked, Twin8           !trikeshed.twinpacked / twin8   Pack.h's TwInt and its 8-bit form
//                      MetaSeries<I,T>             !trikeshed.metaseries<I, T>  domain
//                      Series<T>                   !trikeshed.series<T>         series, size, at
//                      Series2<A,B>                !trikeshed.series2<A, B>     joins, leftOf, rightOf
//                      α, ↺, range get             alpha, anchor, slice
//   lib/Series.kt      get(IntArray), filter       project, where               fancy indexing and K's where-vector
//                      binarySearch, fold          bisect, fold                 K's contract; a typed reducer
//                      drop/take/reversed          slice, reversed
//                      zipWithNext, contains       zipnext, contains
//                      sortedWith, compareTo       sorted, compare
//   lib/ReifiedSplitSeries2.kt   split            !trikeshed.split<A, B>       reify, splitSelect, take
//   lib/Either.kt      Either<L,R>                !trikeshed.either<L, R>      eitherLeft, eitherRight, eitherFold
//   lib/MutableSeries.kt, cursor/Cursor.kt       !trikeshed.cursor<schema, [columns]>  append, anchor, drain
//
// A Join of fixed-width scalars is ONE integer (Pack.h: Twin<i32> is an i64, Join<i32, Twin<i32>> an i96), so those
// types are declared with their layout in the description and their C++ representation in Pack.h.  The Kotlin literals
// (_l, _a, _s, s_) are syntax, not IR; the builder is their IR equivalent.
//
//===----------------------------------------------------------------------===//

#ifndef TRIKESHED_TD
#define TRIKESHED_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def TrikeShed_Dialect : Dialect {
  let name = "trikeshed";
  let cppNamespace = "::composite";
  let summary = "Join, MetaSeries, Series, Cursor, α and ↺: TrikeShed's kernel as IR";
  let description = [{
    `!trikeshed.metaseries<I, T>` is `Join<I, (I) -> T>`: a bound and an index oracle.  `!trikeshed.series<T>` is the
    Int-indexed one.  Reading element k calls the oracle; nothing is stored but what it closes over.

    Every op carries its law in its description: the C++ in Series.h implements them, TrikeShed.kt implements them, and
    either one may be checked against the text rather than against the other.
  }];
  let useDefaultTypePrinterParser = 1;
}

class TS_Type<string name, string typeMnemonic> : TypeDef<TrikeShed_Dialect, name> {
  let mnemonic = typeMnemonic;
}

class TS_Op<string mnemonic, list<Trait> traits = []> : Op<TrikeShed_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Types
//===----------------------------------------------------------------------===//

def TS_JoinType : TS_Type<"Join", "join"> {
  let summary = "Join<A, B>: the one binary composition the other shapes collapse to";
  let parameters = (ins "::mlir::Type":$a, "::mlir::Type":$b);
  let assemblyFormat = "`<` $a `,` $b `>`";
  let description = [{
    Join.kt: two properties and nothing else.  Series.h: `composite::Join<A, B>`, made by `a |j| b`, destructured as
    `auto [x, y]`.  A Join of fixed-width scalars is ONE integer, first side high: Twin<i32> an i64, Join<i32,
    Twin<i32>> an i96, Twin<i64> an i128 (Pack.h's `static_assert`s: TwInt(7, 9) is 30064771081).
  }];
}

def TS_TwinType : TS_Type<"Twin", "twin"> {
  let summary = "Twin<T> = Join<T, T>";
  let parameters = (ins "::mlir::Type":$element);
  let assemblyFormat = "`<` $element `>`";
  let description = [{ Join.kt's `Twin<T>`, routed to the densest representation: `!trikeshed.twinpacked` for 32-bit pairs. }];
}

def TS_TwinPackedType : TS_Type<"TwinPacked", "twinpacked"> {
  let summary = "a (start, len) pair in one 64-bit word: TwinPacked, Pack.h's TwInt, a token's span";
  let parameters = (ins "::mlir::Type":$element);
  let assemblyFormat = "`<` $element `>`";
  let description = [{
    Twin.kt: `TwinPacked.of(start, len)`, both halves 32-bit, start high.  Pack.h's `TwInt`: one shift and one mask per
    access.  A token's span, a body_index, a packed position, and the `row j side` word of `trikeshed.select`.
  }];
}

def TS_Twin8Type : TS_Type<"Twin8", "twin8"> {
  let summary = "a small offset and an 8-bit length in one 32-bit word";
  let description = [{
    Twin.kt: `Twin8.of(offset, len)`, len in 0..0xFF, widened to a TwinPacked relative to a base when it is reified.
  }];
}

def TS_MetaSeriesType : TS_Type<"MetaSeries", "metaseries"> {
  let summary = "MetaSeries<I, T> = Join<I, (I) -> T>: a bound and an index oracle";
  let parameters = (ins "::mlir::Type":$domain, "::mlir::Type":$element);
  let assemblyFormat = "`<` $domain `,` $element `>`";
  let description = [{
    Join.kt.  The domain is ANY index type -- a count, a span, a line and column, an enum case -- and reading is
    `xs[k]` for a k of that domain.  Series.h: `Join<I, F>` with `operator[](const I &)` and `domain()`.
  }];
}

def TS_SeriesType : TS_Type<"Series", "series"> {
  let summary = "Series<T> = MetaSeries<Int, T>: size j index-function";
  let parameters = (ins "::mlir::Type":$element);
  let assemblyFormat = "`<` $element `>`";
  let description = [{
    Series.h: `Series<F>` is `Join<uint32_t, F>`; `xs[i]` is the oracle, unchecked (the index came from the builder).
    Range-for and the STL loop ops walk it through an iterator that carries the index function.
  }];
}

def TS_Series2Type : TS_Type<"Series2", "series2"> {
  let summary = "Series2<A, B> = Series<Join<A, B>>, with left and right projections";
  let parameters = (ins "::mlir::Type":$a, "::mlir::Type":$b);
  let assemblyFormat = "`<` $a `,` $b `>`";
  let description = [{ Join.kt: `joins` makes one, `left`/`right` project a side without a Join per element. }];
}

def TS_SplitType : TS_Type<"Split", "split"> {
  let summary = "ReifiedSplitSeries2<A, B>: the two sides stored apart, so a column scan allocates nothing";
  let parameters = (ins "::mlir::Type":$a, "::mlir::Type":$b);
  let assemblyFormat = "`<` $a `,` $b `>`";
  let description = [{
    ReifiedSplitSeries2.kt.  `valueAt(col)`, `select(indices)`, `mapLeft`, `mapRight`, `swap` bypass the Join: one
    array load.  The shape of a Cursor row (values j metadata) and of an attribute set's rows (name j value j pos).
  }];
}

def TS_CursorType : TS_Type<"Cursor", "cursor"> {
  let summary = "Cursor = Series<RowVec>: columns, each a MutableSeries, and their ColumnMeta";
  let parameters = (ins ArrayRefParameter<"::mlir::Type">:$columns, "::mlir::StringAttr":$schema);
  let assemblyFormat = "`<` $schema `,` `[` $columns `]` `>`";
  let description = [{
    Series.h: `composite::Cursor<T...>`, a tuple of MutableSeries and `meta`.  `schema` names the enum of this file
    whose cases are the columns: ColumnMeta is `stringifyEnum` of each case, `col<Case>()` the typed column.
  }];
}

def TS_EitherType : TS_Type<"Either", "either"> {
  let summary = "Either<L, R>: one side of two, and the fold over it";
  let parameters = (ins "::mlir::Type":$left, "::mlir::Type":$right);
  let assemblyFormat = "`<` $left `,` $right `>`";
  let description = [{ Either.kt: a failure without an exception; the element of a path selection. }];
}

//===----------------------------------------------------------------------===//
// Join: construction, the two halves, and the domain
//===----------------------------------------------------------------------===//

def TS_JOp : TS_Op<"j", [Pure]> {
  let summary = "`a j b`: the infix constructor";
  let arguments = (ins AnyType:$a, AnyType:$b);
  let results = (outs TS_JoinType:$result);
  let assemblyFormat = "$a `,` $b attr-dict `:` type($a) `,` type($b) `->` type($result)";
  let description = [{
    Laws: first(a j b) = a; second(a j b) = b; first(p) j second(p) = p.  Series.h: `a |j| b`.
  }];
}

def TS_FirstOp : TS_Op<"first", [Pure]> {
  let summary = "the `a` of a Join";
  let arguments = (ins TS_JoinType:$join);
  let results = (outs AnyType:$a);
  let assemblyFormat = "$join attr-dict `:` type($join) `->` type($a)";
}

def TS_SecondOp : TS_Op<"second", [Pure]> {
  let summary = "the `b` of a Join";
  let arguments = (ins TS_JoinType:$join);
  let results = (outs AnyType:$b);
  let assemblyFormat = "$join attr-dict `:` type($join) `->` type($b)";
}

def TS_DomainOp : TS_Op<"domain", [Pure]> {
  let summary = "the bound of a MetaSeries: its `a`, the only key its oracle accepts";
  let arguments = (ins TS_MetaSeriesType:$series);
  let results = (outs AnyType:$domain);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($domain)";
  let description = [{ Law: domain(n j f) = n.  Over a Series this is `size`. }];
}

//===----------------------------------------------------------------------===//
// Series
//===----------------------------------------------------------------------===//

def TS_SeriesOp : TS_Op<"series", [Pure]> {
  let summary = "`n j { k -> x }`: the series of n elements whose element k is x";
  let arguments = (ins Index:$size);
  let results = (outs TS_SeriesType:$result);
  let regions = (region SizedRegion<1>:$at);
  let assemblyFormat = "$size attr-dict `:` type($result) $at";
  let description = [{
    Series.h: `n |j| f` and `series(p, n)`.  The region runs each time an element is read: a series costs nothing
    until it is read.
  }];
}

def TS_TextOp : TS_Op<"text", [Pure]> {
  let summary = "a source's bytes as a Series<Char>: what a span indexes into";
  let arguments = (ins AnyType:$witness);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$witness attr-dict `:` type($witness) `->` type($result)";
  let description = [{
    Series.kt's `String.toSeries()` and CharSeries' 4096-byte window.  The witness is the immutable `Source`; a token is
    a `!trikeshed.twinpacked` index into it, never a copy.
  }];
}

def TS_SizeOp : TS_Op<"size", [Pure]> {
  let summary = "the `a` of a series";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs Index:$size);
  let assemblyFormat = "$series attr-dict `:` type($series)";
  let description = [{
    Laws: size(n j f) = n; size(xs α g) = size(xs); size(joins(a, b)) = size(a); size(combine(a, b)) =
    size(a) + size(b); size(xs[r]) = r.count; size(xs[idx]) = size(idx).
  }];
}

def TS_AtOp : TS_Op<"at", [Pure]> {
  let summary = "element k: the oracle applied to k";
  let arguments = (ins TS_SeriesType:$series, AnyType:$index);
  let results = (outs AnyType:$element);
  let assemblyFormat = "$series `[` $index `]` attr-dict `:` type($series) `,` type($index) `->` type($element)";
  let description = [{
    Laws: at(n j f, i) = f(i); at(xs α g, i) = g(at(xs, i)); at(joins(a, b), i) = at(a, i) j at(b, i);
    at(xs[r], i) = at(xs, r.first + i); at(select(a, b, sel), i) = at(sel[i].second ? b : a, sel[i].first).
    No bounds check: the index belongs to whoever built the series.
  }];
}

def TS_AlphaOp : TS_Op<"alpha", [Pure]> {
  let summary = "`xs α g`: the lazy projection";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_SeriesType:$result);
  let regions = (region SizedRegion<1>:$xform);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result) $xform";
  let description = [{
    Laws: size(xs α g) = size(xs); at(xs α g, i) = g(at(xs, i)); α of α is α of the composition.  Nothing is read when
    the projection is made (Series.h `|α|`; the `static_assert` checks the fusion).
  }];
}

def TS_JoinsOp : TS_Op<"joins", [Pure]> {
  let summary = "two series side by side: row i is a[i] j b[i]";
  let arguments = (ins TS_SeriesType:$a, TS_SeriesType:$b);
  let results = (outs TS_Series2Type:$result);
  let assemblyFormat = "$a `,` $b attr-dict `:` type($a) `,` type($b) `->` type($result)";
  let description = [{ Series.h `joins(a, b)`: as many rows as `a`, the caller's word that `b` has as many. }];
}

def TS_SelectOp : TS_Op<"select", [Pure]> {
  let summary = "the rows of two series chosen by a series of `row j side` words: a shadowing top, as a view";
  let arguments = (ins TS_SeriesType:$a, TS_SeriesType:$b, TS_SeriesType:$sel);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$a `,` $b `,` $sel attr-dict `:` type($a) `,` type($b) `,` type($sel) `->` type($result)";
  let description = [{
    Series.h `select(a, b, sel)`: word i of `sel` is `row j side`, side 0 reads a's row and 1 b's.  This is how
    `base // top` is read (Nix/Eval.h, Bindings::Layer): 8 bytes a row of selection, never a copy of a row.

    Laws: size(select(a, b, sel)) = size(sel); at(select(a, b, sel), i) = at(sel[i].second ? b : a, sel[i].first).
  }];
}

def TS_CombineOp : TS_Op<"combine", [Pure]> {
  let summary = "the rows of a, then of b: one after the other";
  let arguments = (ins Variadic<TS_SeriesType>:$parts);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$parts attr-dict `:` type($parts) `->` type($result)";
  let description = [{
    Series.h `a + b` and `Combine`: the size counted once in 64 bits, drained part by part, never indexed (an indexed
    combine is the staircase `reify` exists to decide about).
  }];
}

def TS_DrainOp : TS_Op<"drain"> {
  let summary = "copy a series into cells, part by part; the end of what was written";
  let arguments = (ins TS_SeriesType:$series, AnyType:$into);
  let results = (outs AnyType:$end);
  let assemblyFormat = "$series `,` $into attr-dict `:` type($series) `,` type($into) `->` type($end)";
  let description = [{ Series.h `drain`.  Where a lazy composition stops and cells begin. }];
}

def TS_SliceOp : TS_Op<"slice", [Pure]> {
  let summary = "`xs[r]`: a range of a series as a view, not a copy";
  let arguments = (ins TS_SeriesType:$series, Index:$offset, Index:$count);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series `[` $offset `,` $count `]` attr-dict `:` type($series) `->` type($result)";
  let description = [{
    Join.kt's range get: `range.count() j { i -> this[range.first + i] }`.  `drop` and `take` are its cases.
    Laws: size(xs[r]) = r.count; at(xs[r], i) = at(xs, r.first + i); xs[0, size(xs)] = xs.
  }];
}

def TS_ReversedOp : TS_Op<"reversed", [Pure]> {
  let summary = "the same elements in the opposite order, still a view";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
  let description = [{ Law: at(xs.reversed, i) = at(xs, size(xs) - 1 - i); reversed of reversed is xs. }];
}

def TS_ProjectOp : TS_Op<"project", [Pure]> {
  let summary = "`xs[idx]`: the elements at the indices of another series (fancy indexing)";
  let arguments = (ins TS_SeriesType:$series, TS_SeriesType:$index);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series `[` $index `]` attr-dict `:` type($series) `,` type($index) `->` type($result)";
  let description = [{
    Series.kt's `get(IntArray)`.  A reordering, a selection and a `where` vector all compose here without touching an
    element.  Laws: size(xs[idx]) = size(idx); at(xs[idx], i) = at(xs, at(idx, i)).
  }];
}

def TS_WhereOp : TS_Op<"where", [Pure]> {
  let summary = "`xs.filter(p)`: the matching indices, scanned once, then a projection";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_SeriesType:$result);
  let regions = (region SizedRegion<1>:$predicate);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result) $predicate";
  let description = [{
    Series.kt's `filter`: the scan runs on the first access of the size or an element, not at call time, and the
    memoised index vector is K's `&` (where).  The result is `project(xs, where(xs, p))`; the matches are in
    increasing index order.
  }];
}

def TS_BisectOp : TS_Op<"bisect", [Pure]> {
  let summary = "binary search over a series sorted by its key: K's contract";
  let arguments = (ins TS_SeriesType:$series, AnyType:$key);
  let results = (outs Index:$index);
  let assemblyFormat = "$series `,` $key attr-dict `:` type($series) `,` type($key) `->` type($index)";
  let description = [{
    Series.kt's `binarySearch`: the index when the key is present, else the index of the first greater element
    (`-(insertion) - 1`), the size when it is greater than all of them.  Series.h `lowerBound(xs, less)` is the same
    search, and it is how an attribute set's sorted rows are looked up (`Bindings::get`).
  }];
}

def TS_FoldOp : TS_Op<"fold", [Pure]> {
  let summary = "fold a series with a zero and a combiner, left to right";
  let arguments = (ins TS_SeriesType:$series, AnyType:$zero);
  let results = (outs AnyType:$result);
  let regions = (region SizedRegion<1>:$combine);
  let assemblyFormat = "$series `,` $zero attr-dict `:` type($series) `,` type($zero) `->` type($result) $combine";
  let description = [{ Series.kt's `fold` and typed `Reducer<T, R>`.  Sequential, so a non-associative combiner is legal. }];
}

def TS_ZipNextOp : TS_Op<"zipnext", [Pure]> {
  let summary = "each element with the one after it: size-1 rows of `a j b`";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_Series2Type:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
  let description = [{
    Series.kt's `zipWithNext`.  Laws: size(xs.zipnext) = size(xs) - 1 (0 when empty); at(xs.zipnext, i) =
    at(xs, i) j at(xs, i + 1).
  }];
}

def TS_ContainsOp : TS_Op<"contains", [Pure]> {
  let summary = "does the series hold this element";
  let arguments = (ins TS_SeriesType:$series, AnyType:$element);
  let results = (outs I1:$found);
  let assemblyFormat = "$series `,` $element attr-dict `:` type($series) `,` type($element)";
}

def TS_SortedOp : TS_Op<"sorted", [Pure]> {
  let summary = "fill one buffer, sort it, drain it: an ordered series";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
  let description = [{ Series.kt's `sortedWith`.  A sort is the one place a lazy series must be read to be ordered. }];
}

def TS_CompareOp : TS_Op<"compare", [Pure]> {
  let summary = "the first difference between two series, then the shorter one is less";
  let arguments = (ins TS_SeriesType:$a, TS_SeriesType:$b);
  let results = (outs I32:$order);
  let assemblyFormat = "$a `,` $b attr-dict `:` type($a) `,` type($b)";
  let description = [{
    Join.kt's `CSeries<T : Comparable<T>>`: walk both to the shorter length and return the first non-zero comparison,
    else compare the sizes.  `shortestLength` and `commonPrefixWith` are what that walk gives.
  }];
}

//===----------------------------------------------------------------------===//
// Series2, the split, and the two projections that allocate nothing
//===----------------------------------------------------------------------===//

def TS_LeftOfOp : TS_Op<"leftOf", [Pure]> {
  let summary = "the left projection of a Series2 (a column, read where it lies)";
  let arguments = (ins TS_Series2Type:$series);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
  let description = [{
    Join.kt's `Series2.left`: over a `!trikeshed.split` it reads the stored side, no Join per element and the other
    side never evaluated.
  }];
}

def TS_RightOfOp : TS_Op<"rightOf", [Pure]> {
  let summary = "the right projection of a Series2, as leftOf projects the left";
  let arguments = (ins TS_Series2Type:$series);
  let results = (outs TS_SeriesType:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
}

def TS_ReifyOp : TS_Op<"reify", [Pure]> {
  let summary = "a Series2 as a split: the two sides stored apart";
  let arguments = (ins TS_Series2Type:$series);
  let results = (outs TS_SplitType:$result);
  let assemblyFormat = "$series attr-dict `:` type($series) `->` type($result)";
  let description = [{ ReifiedSplitSeries2.kt's `reify()`: the only shape a column scan reads without allocating a Join. }];
}

def TS_SplitSelectOp : TS_Op<"splitSelect", [Pure]> {
  let summary = "select a subset of a split's columns by index, values and metadata in step";
  let arguments = (ins TS_SplitType:$split, TS_SeriesType:$indices);
  let results = (outs TS_SplitType:$result);
  let assemblyFormat = "$split `[` $indices `]` attr-dict `:` type($split) `,` type($indices) `->` type($result)";
  let description = [{ Column i of the result is column at(indices, i) of the split, both sides. }];
}

def TS_TakeOp : TS_Op<"take", [Pure]> {
  let summary = "one column of a split or a cursor, by column index";
  let arguments = (ins AnyType:$of, Index:$column);
  let results = (outs AnyType:$value);
  let assemblyFormat = "$of `[` $column `]` attr-dict `:` type($of) `->` type($value)";
  let description = [{ ReifiedSplitSeries2's `valueAt` / `rightAt`: one array load, no Join. }];
}

//===----------------------------------------------------------------------===//
// MutableSeries, ↺, Either
//===----------------------------------------------------------------------===//

def TS_AppendOp : TS_Op<"append"> {
  let summary = "accumulate one row; the result is its index, the `b` of whatever refers back to it";
  let arguments = (ins AnyType:$cursor, Variadic<AnyType>:$cells);
  let results = (outs Index:$row);
  let assemblyFormat = "$cursor `,` $cells attr-dict `:` type($cursor) `,` type($cells) `->` type($row)";
  let description = [{
    Series.h `MutableSeries::append` / `Cursor::append`.  A list that is mutated says so in its type, and a pool an
    index refers into is never renumbered: a drained cell stays a default cell.
  }];
}

def TS_AnchorOp : TS_Op<"anchor"> {
  let summary = "↺: the first force of a cell mints it; every read after is the constant it produced";
  let arguments = (ins TS_CursorType:$cells, Index:$index);
  let results = (outs AnyType:$constant);
  let regions = (region SizedRegion<1>:$mint);
  let assemblyFormat = "$cells `[` $index `]` attr-dict `:` type($cells) `->` type($constant) $mint";
  let description = [{
    Series.h `anchor(cells, i, mint)`.  The cell is addressed by index again after the mint, because a mint may append
    to the series it anchors in and an append moves the cells.
  }];
}

def TS_EitherLeftOp : TS_Op<"eitherLeft", [Pure]> {
  let summary = "the left of an Either";
  let arguments = (ins TS_EitherType:$either);
  let results = (outs AnyType:$left);
  let assemblyFormat = "$either attr-dict `:` type($either) `->` type($left)";
}

def TS_EitherRightOp : TS_Op<"eitherRight", [Pure]> {
  let summary = "the right of an Either";
  let arguments = (ins TS_EitherType:$either);
  let results = (outs AnyType:$right);
  let assemblyFormat = "$either attr-dict `:` type($either) `->` type($right)";
}

def TS_EitherFoldOp : TS_Op<"eitherFold", [Pure]> {
  let summary = "fold an Either into one type, one region per side";
  let arguments = (ins TS_EitherType:$either);
  let results = (outs AnyType:$result);
  let regions = (region SizedRegion<1>:$ifLeft, SizedRegion<1>:$ifRight);
  let assemblyFormat = "$either attr-dict `:` type($either) `->` type($result) $ifLeft `,` $ifRight";
  let description = [{ Either.kt's `fold`; `map`, `mapLeft`, `mapRight` and `flatMap` are its cases. }];
}

def TS_YieldOp : TS_Op<"yield", [Pure, Terminator]> {
  let summary = "the element a region of the algebra produces";
  let arguments = (ins Variadic<AnyType>:$values);
  let assemblyFormat = "$values attr-dict `:` type($values)";
}

//===----------------------------------------------------------------------===//
// The cursor: rows, columns, and the combinators of borg.trikeshed.cursor
//===----------------------------------------------------------------------===//

def TS_ColKeyType : TS_Type<"ColKey", "colkey"> {
  let summary = "a typed column key of a Cursor's schema";
  let parameters = (ins "::mlir::StringAttr":$schema);
  let assemblyFormat = "$schema";
  let description = [{
    ColK.kt: a column is addressed by a key that fixes its type, so reading one needs no name lookup and no cast -- the
    case of the schema enum IS the ColumnMeta.  Series.h: `cursor.col<BandCol::Span>()`; the generated enums at the end
    of this file are the case sets.
  }];
}

def TS_RowOp : TS_Op<"row", [Pure]> {
  let summary = "row i of a cursor: a row vector, values j metadata";
  let arguments = (ins TS_CursorType:$cursor, Index:$row);
  let results = (outs TS_Series2Type:$result);
  let description = [{
    Cursor.kt: `cursor[i]`, a RowVec.  Reading a row copies nothing: it is a view by position over the columns of the
    cursor, which is why a row's cost is the same whether the row is read once or a thousand times.
  }];
}

def TS_RowsOp : TS_Op<"rows", [Pure]> {
  let summary = "a cursor's rows as a Series: size j row";
  let arguments = (ins TS_CursorType:$cursor);
  let results = (outs TS_SeriesType:$result);
  let description = [{ Cursor.kt: a Cursor IS `Series<RowVec>`; this is that face of the columns. }];
}

def TS_ColumnOp : TS_Op<"column", [Pure]> {
  let summary = "one column of a cursor, by its typed key";
  let arguments = (ins TS_CursorType:$cursor, TS_ColKeyType:$key);
  let results = (outs TS_SeriesType:$result);
  let description = [{
    ColK.kt / ColumnCursor.kt: a column read by a key that fixes its type.  Laws: size(column(c, k)) = size(rows(c));
    the i-th element of the column is the column's value in row i.
  }];
}

def TS_CursorSelectOp : TS_Op<"cursorSelect", [Pure]> {
  let summary = "a subset of a cursor's columns, by key: a cursor of the same rows";
  let arguments = (ins TS_CursorType:$cursor, Variadic<TS_ColKeyType>:$keys);
  let results = (outs TS_CursorType:$result);
  let description = [{
    CursorOps.kt / ColumnCursor.kt: column selection is composition, not a copy of the rows -- the result reads the same
    cells through fewer keys, so a projection costs the size of its key list.
  }];
}

def TS_CursorCombineOp : TS_Op<"cursorCombine", [Pure]> {
  let summary = "the rows of a, then the rows of b: two cursors of one schema, stacked";
  let arguments = (ins TS_CursorType:$a, TS_CursorType:$b);
  let results = (outs TS_CursorType:$result);
  let description = [{
    cursor/Combine.kt: combine along the rows.  Laws: the size is the sum; row i is row i of a while i < size(a), else
    row (i - size(a)) of b.
  }];
}

def TS_CursorJoinsOp : TS_Op<"cursorJoins", [Pure]> {
  let summary = "two cursors side by side: the columns of b added to the rows of a";
  let arguments = (ins TS_CursorType:$a, TS_CursorType:$b);
  let results = (outs TS_CursorType:$result);
  let description = [{ cursor/Combine.kt's join: widens along the columns; the size is size(a). }];
}

def TS_GroupByOp : TS_Op<"groupBy", [Pure]> {
  let summary = "group a cursor's rows by a column: one row per group, holding its row indices";
  let arguments = (ins TS_CursorType:$cursor, TS_ColKeyType:$key);
  let results = (outs TS_CursorType:$result);
  let description = [{
    GroupBy.kt: a group holds the INDICES of its rows (a Series), not copies of them, so grouping never moves a cell.
    Laws: every input row is in exactly one group; the groups are in first-appearance order.
  }];
}

def TS_PivotOp : TS_Op<"pivot", [Pure]> {
  let summary = "long to wide: a column's values become columns";
  let arguments = (ins TS_CursorType:$cursor, TS_ColKeyType:$keys, TS_ColKeyType:$values);
  let results = (outs TS_CursorType:$result);
  let description = [{ Pivot.kt.  Laws: one row per distinct key, in first-appearance order; the columns are the distinct values. }];
}

def TS_KeyedJoinOp : TS_Op<"keyedJoin", [Pure]> {
  let summary = "join two cursors on a key column";
  let arguments = (ins TS_CursorType:$a, TS_CursorType:$b, TS_ColKeyType:$key);
  let results = (outs TS_CursorType:$result);
  let description = [{
    KeyedJoin.kt.  Laws: one row per matching pair, in a's row order then b's; a key with no match contributes no row.
    The index over the smaller side is built once (a Series of row indices, as GroupBy does).
  }];
}

def TS_FacetOp : TS_Op<"facet", [Pure]> {
  let summary = "a query facet over a column: count, min, max, sum, where";
  let arguments = (ins TS_CursorType:$cursor, TS_ColKeyType:$key);
  let results = (outs AnyType:$facet);
  let regions = (region SizedRegion<1>:$compute);
  let description = [{
    cursor/query/QueryFacets.kt and query/Fusion.kt: a facet is (a column, an operation) and the operation is a fold over
    that column's series, so facets fuse with the projection that feeds them instead of materialising rows.
  }];
}

def TS_TensorOp : TS_Op<"tensor", [Pure]> {
  let summary = "a cursor as a dense tile: row-major, 512-byte tiles";
  let arguments = (ins TS_CursorType:$cursor);
  let results = (outs AnyType:$tile);
  let description = [{
    CursorTensor.kt: the dense face of a cursor, row-major so a row scan is contiguous, in 512-byte tiles so a tile is
    one cache line.  The reification of a cursor into the layout a numeric kernel wants.
  }];
}

//===----------------------------------------------------------------------===//
// The Cursors mlnix keeps: their columns, generated for the C++ (TrikeShedEnums.h.inc)
//===----------------------------------------------------------------------===//

class TS_Column<string sym, int val, string str> : I32EnumAttrCase<sym, val, str>;

// confix::Bands, layers 0 and 1 of NixSyntax.td: the bands of one source in the order they open.
def TS_BandColumns : I32EnumAttr<"BandCol", "the columns of confix::Bands", [
    TS_Column<"Span", 0, "span">,   // opening offset j closing offset
    TS_Column<"Kind", 1, "kind">,   // the BandKind (NixSyntax.td)
    TS_Column<"Stmts", 2, "stmts">  // first j count into the ends: the qualified semicolons and commas of the band
  ]> {
  let cppNamespace = "::nixfe::confix";
  let genSpecializedAttr = 0;
}

// nixfe::FilePool: the lambdas of one source whose bodies wait for their first call.
def TS_PoolColumns : I32EnumAttr<"PoolCol", "the columns of nixfe::FilePool", [
    TS_Column<"At", 0, "at">,        // where the lambda starts: its body is parsed again from there
    TS_Column<"AtPos", 1, "pos">,    // the position of that offset
    TS_Column<"Op", 2, "op">,        // the nix.lambda that waits for its body; drained when the body is minted
    TS_Column<"Withs", 3, "withs">,  // how many leading captures are the `with` chain
    TS_Column<"Names", 4, "names">,  // first j count into the pool's names: the captures after the withs
    TS_Column<"Body", 5, "body">     // ↺: the indexed region of the minted body
  ]> {
  let cppNamespace = "::nixfe";
  let genSpecializedAttr = 0;
}

// The bindings of the scopes of one parse: a scope is a run of rows, first j count, a view by position.
def TS_BindColumns : I32EnumAttr<"BindCol", "the columns of the parser's bindings", [
    TS_Column<"Key", 0, "name">,     // the name, a slice of the source
    TS_Column<"Hash", 1, "hash">,    // its hash, compared before its bytes
    TS_Column<"Val", 2, "value">     // what it is bound to (Gen); nothing in a skim, where only its presence counts
  ]> {
  let cppNamespace = "::nixfe";
  let genSpecializedAttr = 0;
}

#endif // TRIKESHED_TD
