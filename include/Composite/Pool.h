//===- Pool.h - what the evaluator and the front end pool rows with: select, Sel, Cursor, anchor ---===//

#ifndef COMPOSITE_POOL_H
#define COMPOSITE_POOL_H

#include "Composite/Mutable.h"
#include "Composite/Pack.h"

namespace composite {

//===----------------------------------------------------------------------===//
// select: a series of the rows of two series, chosen by a third
//===----------------------------------------------------------------------===//

/// The rows of `a` and `b` chosen by `sel`: word i is `row j side` (TwInt), side 0 for a's row and 1 for b's.  This is a
/// shadowing top read where its rows lie -- `base // top` -- and it costs 8 bytes a row of selection against a row apiece
/// for a copy.  Between `joins` (side by side) and `combine` (one after the other): the rows of two series in one order,
/// chosen by a third.  Both sides must yield the same type; size(select(a, b, sel)) is size(sel).
template <class A, class B, class S> constexpr auto select(A &&a, B &&b, S &&sel) {
  uint32_t n = uint32_t(sel.size());
  return n |j| [l = Held<A>{fw<A>(a)}, r = Held<B>{fw<B>(b)},
                s = Held<S>{fw<S>(sel)}](uint32_t i) -> decltype(auto) {
    join::TwInt w = s.s[i];
    return w.second() ? r.s[w.first()] : l.s[w.first()];
  };
}

/// ↺, the constant anchor.  A null cell has not been forced: the first force runs `mint(i)` and the cell
/// is from then on the constant it produced.  The cell is addressed by index again after the mint,
/// because a mint may append to the very series it anchors in (a lambda nested in the body defers a
/// row) and an append moves the cells.
template <class T, class Mint> T anchor(MutableSeries<T> &cells, uint32_t i, Mint mint) {
  static_assert(isPointer<T>, "a cell that was never forced is null");
  if (T v = cells[i]) return v;
  T v = mint(i);
  cells[i] = v;
  return v;
}

//===----------------------------------------------------------------------===//
// Sel: a selection word, four bytes a row
//===----------------------------------------------------------------------===//

/// A selection word: one bit the side, 31 bits the row.  A layer of a set uses this to say which set each row came
/// from and where it lies.  Four bytes a row, against the eight a TwInt costs, and one load reads it; the rows a top
/// shadowed are simply not in it, so a shadow costs nothing at read time.
///
/// One bit a row was tried and measured: it cut 28 MB of peak from the toplevel, and the rank over the ones -- a
/// bisection over the shadowed rows for every base row it shifts, tamed to a load and an add by a one-row memo on
/// sequential reads -- still left the run 7% slower than this form.  The bit is the wrong side of the trade while the
/// rows are read one at a time.
struct Sel {
  MutableSeries<uint32_t> words; // `row << 1 | side`
  uint32_t rows = 0;

  uint32_t size() const { return rows; }
  /// Accumulate one row: where it lies, and which set it comes from.
  uint32_t append(uint32_t row, bool side) {
    words.append((row << 1) | (side ? 1u : 0u));
    return rows++;
  }
  /// Row i as `row j side` (Pack.h).
  join::TwInt at(uint32_t i) const {
    uint32_t w = words[i];
    return join::TwInt(w >> 1, w & 1);
  }
  bool operator==(const Sel &o) const { return words == o.words && rows == o.rows; }
};

/// The columns of a Cursor, one MutableSeries each, in a chain of structs (a tuple, with nothing to include).
template <class... T> struct Columns {
  constexpr bool operator==(const Columns &) const { return true; }
};
template <class H, class... T> struct Columns<H, T...> {
  MutableSeries<H> c;
  Columns<T...> rest;
  bool operator==(const Columns &o) const { return c == o.c && rest == o.rest; }
};
template <size_t K, class H, class... T> constexpr auto &columnAt(Columns<H, T...> &cs) {
  if constexpr (K == 0) return cs.c; else return columnAt<K - 1>(cs.rest);
}
template <size_t K, class H, class... T> constexpr const auto &columnAt(const Columns<H, T...> &cs) {
  if constexpr (K == 0) return cs.c; else return columnAt<K - 1>(cs.rest);
}
template <class H, class... T, class A, class... As> void appendColumns(Columns<H, T...> &cs, A &&a, As &&...as) {
  cs.c.append(fw<A>(a));
  if constexpr (sizeof...(T) > 0) appendColumns(cs.rest, fw<As>(as)...);
}
template <class... T> void clearColumns(Columns<T...> &) {}
template <class H, class... T> void clearColumns(Columns<H, T...> &cs) { cs.c.clear(); clearColumns(cs.rest); }
template <class... T> void reserveColumns(Columns<T...> &, size_t) {}
template <class H, class... T> void reserveColumns(Columns<H, T...> &cs, size_t n) { cs.c.reserve(n); reserveColumns(cs.rest, n); }

/// The instance pool of one type: a column per field (the names are its ColumnMeta), rows addressed by index.  A row is read column by column,
/// `col<K>()[i]`: a use that reads one member touches one column.
template <class... T> struct Cursor {
  static constexpr size_t width = sizeof...(T);
  Arr<const char *, width> meta;
  Columns<T...> cols;

  explicit Cursor(Arr<const char *, width> names) : meta(names) {}
  /// The columns are the cases of an enum generated from include/Composite/TrikeShed.td: stringifyEnum names them.
  template <Enum E> explicit Cursor(E) {
    for (size_t i = 0; i < width; i++) meta.a[i] = stringifyEnum(E(i)).data();
  }
  constexpr uint32_t size() const { return columnAt<0>(cols).size(); }
  template <auto K> auto &col() { return columnAt<size_t(K)>(cols); }
  template <auto K> const auto &col() const { return columnAt<size_t(K)>(cols); }
  /// Accumulate one row; the result is its index.
  uint32_t append(T... cell) {
    appendColumns(cols, mv(cell)...);
    return size() - 1;
  }
  void clear() { clearColumns(cols); }
  void reserve(size_t n) { reserveColumns(cols, n); }
};

} // namespace composite

#endif
