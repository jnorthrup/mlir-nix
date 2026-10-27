//===- TrikeShed.td - TrikeShed's kernel algebra as a dialect ----*- tablegen -*-===//
//
// ../TrikeShed/PRELOAD.md: most shapes collapse back to Join; Series is the default indexed abstraction, size j
// index-function; Cursor is its dataframe form, a column per field plus the ColumnMeta; α projects lazily; ↺ anchors a
// constant; a list that is mutated says so in its type (MutableSeries).  The C++ of the kernel is
// include/Composite/Series.h and include/Composite/Pack.h.  This file declares the same algebra in MLIR's terms (types
// and ops, the laws as each op's description) and the schemas of the Cursors mlnix keeps: their columns are the cases
// of the enums below, generated for the C++ (TrikeShedEnums.h.inc), so a Cursor takes its ColumnMeta from its enum and
// is indexed by its cases.
//
//   Join<A, B>        two values composed                    !trikeshed.join<A, B>
//   Twin<T>           Join<T, T>                             !trikeshed.join<T, T>
//   a j b             the infix constructor                  trikeshed.j
//   a, b              the two components                     trikeshed.first / trikeshed.second
//   TwInt             Twin<Int> collapsed to one Long        Pack.h: Twin<i32> is an i64, the first side high
//   Series<T>         Join<Int, (Int) -> T>                  !trikeshed.series<T>, trikeshed.series / size / at
//   xs α f            the lazy projection                    trikeshed.alpha
//   joins, combine    side by side, one after the other      trikeshed.joins / trikeshed.combine
//   ↺                 the constant anchor                    trikeshed.anchor
//   Cursor            Series<RowVec> over MutableSeries      !trikeshed.cursor<schema, [columns]>
//
// The ops are the documentation of the algebra, not what is allocated: a Series is a size and an index function, a
// view by position over cells some MutableSeries owns, never a copy (Cliff Click: parse results go into a fixed buffer).
//
//===----------------------------------------------------------------------===//

#ifndef TRIKESHED_TD
#define TRIKESHED_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def TS_Dialect : Dialect {
  let name = "trikeshed";
  let cppNamespace = "::composite";
  let summary = "Series, Cursor, α and ↺: TrikeShed's kernel over Join";
  let description = [{
    `!trikeshed.series<T>` is `Join<Int, (Int) -> T>`: a size and an index function.  Reading element i calls the
    function; nothing is stored but what the function closes over.  `trikeshed.alpha` projects a series into
    another of the same size without reading it; `trikeshed.joins` puts two side by side (row i is a[i] j b[i]);
    `trikeshed.combine` puts one after the other.  `trikeshed.cursor` is a series of rows over columns that are
    each a MutableSeries, named by an enum of this file.
  }];
}

class TS_Type<string name, string typeMnemonic> : TypeDef<TS_Dialect, name> {
  let mnemonic = typeMnemonic;
}

def TS_JoinType : TS_Type<"Join", "join"> {
  let summary = "Join<A, B>: the one binary composition the other shapes collapse to";
  let parameters = (ins "::mlir::Type":$a, "::mlir::Type":$b);
  let assemblyFormat = "`<` $a `,` $b `>`";
  let description = [{
    Series.h: `composite::Join<A, B>`, made by `a |j| b`, destructured as `auto [x, y]`.  A Join of fixed-width
    scalars (integers, floats by their bits, and Joins of those) is ONE integer, the first side in the high bits:
    Twin<i32> is an i64 (Pack.h `TwInt`, a token's span, a body_index, a position), a segment of an immutable
    buffer, Join<i32, Twin<i32>>, an i96, and Twin<i64> an i128.  The JVM stops at Long; LLVM has integers of any
    width.  Pack.h's `static_assert`s hold the layout: TwInt(7, 9) is 30064771081, and (3, (10, 17)) is
    3 * 2^64 + 42949672977.  A Join of something with no fixed width (an `index`) stays a Join.
  }];
}

class TS_Op<string mnemonic, list<Trait> traits = []> : Op<TS_Dialect, mnemonic, traits>;

def TS_JOp : TS_Op<"j", [Pure]> {
  let summary = "`a j b`: the infix constructor";
  let arguments = (ins AnyType:$a, AnyType:$b);
  let results = (outs TS_JoinType:$result);
  let description = [{
    Laws: first(a j b) = a; second(a j b) = b; first(p) j second(p) = p.
  }];
}

def TS_FirstOp : TS_Op<"first", [Pure]> {
  let summary = "the `a` of a Join";
  let arguments = (ins TS_JoinType:$join);
  let results = (outs AnyType:$a);
}

def TS_SecondOp : TS_Op<"second", [Pure]> {
  let summary = "the `b` of a Join";
  let arguments = (ins TS_JoinType:$join);
  let results = (outs AnyType:$b);
}

def TS_SeriesType : TS_Type<"Series", "series"> {
  let summary = "Series<T> = Join<Int, (Int) -> T>: size j index-function";
  let parameters = (ins "::mlir::Type":$element);
  let assemblyFormat = "`<` $element `>`";
  let description = [{
    Series.h: `composite::Series<F>` is `Join<uint32_t, F>`, `xs.size()` its `a`, `xs[i]` its `b(i)`.  An index
    comes from whoever built the series and is not checked.  Range-for and the loop ops of the STL walk it through
    a forward iterator whose `*` is the index function (PRELOAD's `.view`).
  }];
}

def TS_CursorType : TS_Type<"Cursor", "cursor"> {
  let summary = "Cursor = Series<RowVec>: columns, each a MutableSeries, and their names";
  let parameters = (ins ArrayRefParameter<"::mlir::Type">:$columns, "::mlir::StringAttr":$schema);
  let assemblyFormat = "`<` $schema `,` `[` $columns `]` `>`";
  let description = [{
    Series.h: `composite::Cursor<T...>`, a tuple of MutableSeries and `meta`, the column names.  `schema` names
    the enum of this file whose cases are the columns, in order: the ColumnMeta is `stringifyEnum` of each case and
    `cursor.col<Case>()` the column.  A row is appended across every column at once and its index is the `b` of
    whatever refers back to it (a body_index, a band, a binding).
  }];
}

def TS_SeriesOp : TS_Op<"series", [Pure]> {
  let summary = "`n j { i -> x }`: the series of n elements whose element i is x";
  let arguments = (ins Index:$size);
  let results = (outs TS_SeriesType:$result);
  let regions = (region SizedRegion<1>:$at);
  let description = [{
    Series.h: `n |j| f`, and `series(p, n)` over contiguous cells.  The region takes the index and yields the
    element; it runs each time the element is read, so a series costs nothing until it is read.
  }];
}

def TS_SizeOp : TS_Op<"size", [Pure]> {
  let summary = "the `a` of a series";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs Index:$size);
  let description = [{
    Laws: size(n j f) = n; size(xs α g) = size(xs); size(joins(a, b)) = size(a); size(combine(a, b)) =
    size(a) + size(b), counted once when the combine is made.
  }];
}

def TS_AtOp : TS_Op<"at", [Pure]> {
  let summary = "element i: the `b` of a series applied to i";
  let arguments = (ins TS_SeriesType:$series, Index:$index);
  let results = (outs AnyType:$element);
  let description = [{
    Laws: at(n j f, i) = f(i); at(xs α g, i) = g(at(xs, i)); at(joins(a, b), i) = at(a, i) j at(b, i).
  }];
}

def TS_AlphaOp : TS_Op<"alpha", [Pure]> {
  let summary = "`xs α g`: the lazy projection, size(xs) j { i -> g(xs[i]) }";
  let arguments = (ins TS_SeriesType:$series);
  let results = (outs TS_SeriesType:$result);
  let regions = (region SizedRegion<1>:$xform);
  let description = [{
    Series.h: `xs |α| g`.  Nothing is read when the projection is made.  α of α is α of the composition
    ((xs α f) α g = xs α (g ∘ f)): the `static_assert` of Series.h checks it.  Over a named series the projection
    reads it in place, as a view; over a temporary it keeps it.
  }];
}

def TS_JoinsOp : TS_Op<"joins", [Pure]> {
  let summary = "two series side by side: row i is a[i] j b[i] (TrikeShed's joins, a zip)";
  let arguments = (ins TS_SeriesType:$a, TS_SeriesType:$b);
  let results = (outs TS_SeriesType:$result);
  let description = [{
    Series.h: `joins(a, b)`, as many rows as `a`; that `b` has as many is the caller's word.  Over a Cursor the same
    composition widens along the columns.
  }];
}

def TS_CombineOp : TS_Op<"combine", [Pure]> {
  let summary = "the rows of a, then the rows of b (TrikeShed's combine)";
  let arguments = (ins Variadic<TS_SeriesType>:$parts);
  let results = (outs TS_SeriesType:$result);
  let description = [{
    Series.h: `a + b` and `Combine`.  The size is counted once, in 64 bits; a combine is not indexed but drained
    part by part (`drain`), each part in one loop.
  }];
}

def TS_AnchorOp : TS_Op<"anchor"> {
  let summary = "↺: the first force of a cell mints it; every read after is the constant it produced";
  let arguments = (ins TS_CursorType:$cells, Index:$index);
  let results = (outs AnyType:$constant);
  let regions = (region SizedRegion<1>:$mint);
  let description = [{
    Series.h: `anchor(cells, i, mint)`.  A null cell has not been forced.  The cell is addressed by index again
    after the mint, because a mint may append to the series it anchors in (a lambda nested in a body defers a row
    of the pool it is minted from) and an append moves the cells.
  }];
}

def TS_YieldOp : TS_Op<"yield", [Pure, Terminator]> {
  let summary = "the element a region of the algebra produces";
  let arguments = (ins Variadic<AnyType>:$values);
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
