//===- Series.h - PRELOAD's Join, Series, α, ↺ and MutableSeries, in C++ -------===//
//
// The kernel algebra of ../TrikeShed/PRELOAD.md as plain C++, and only what the sea of nodes
// (docs/SEA-OF-NODES.md) calls.  Header-only, no MLIR, no LLVM: every type is a value the optimizer
// sees through.  Each name below has a caller outside this file, except the `Series` alias (it names
// what `series`, `α` and `view` return) and the gap said under Cursor.
//
//   a |j| b            Join<A,B>, the base binary composition; `j` is the infix constructor.
//   Series<F>          Join<uint32_t, F>, as PRELOAD aliases it: size j index-function.  xs[i] is NOT
//                      bounds-checked: the index came from the builder that issued it, never from the user.
//   xs |α| f           lazy projection, still a Series: size j { i -> f(xs[i]) }.  Over a named xs (a vector, a range of
//                      operands) it reads xs in place, as a view, so xs must outlive it; over a temporary it keeps it.
//   joins(a, b)        row i is a[i] j b[i]: two series side by side, across the rows (TrikeShed's `joins`).
//   a + b, combine     the rows of a, then of b: along the rows (TrikeShed's combine).  drain() copies one part by part.
//   MutableSeries<T>   a list that is mutated says so in its type.  It accumulates (append), then drains.
//   anchor             ↺, the constant anchor: the first force of a cell mints it, every read after is
//                      the constant it produced.
//   Cursor<T...>       the instance pool of one type: a MutableSeries per column, plus the column names, which are the
//                      cases of its enum in TrikeShed.td (the dialect of this algebra).
//                      PRELOAD's Cursor is Series<RowVec>, the row-shaped face of the same columns: `row(i)` reads
//                      one out as a tuple, column by column (a mint reads its pool row so); the Series face is not built.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_SERIES_H
#define COMPOSITE_SERIES_H

#include <algorithm>
#include <array>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <ranges>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#include "Composite/Pack.h" // TwInt: the `row j side` word of a selection

namespace composite {

//===----------------------------------------------------------------------===//
// Join, and Series as the Join whose first side is a size
//===----------------------------------------------------------------------===//

template <class A, class B> struct Join {
  A a;
  B b;

  // A Join<uint32_t, F> is a Series (PRELOAD: typealias Series<T> = Join<Int, (Int) -> T>).
  constexpr uint32_t size() const requires std::same_as<A, uint32_t> { return a; }
  constexpr decltype(auto) operator[](uint32_t i) const
    requires std::same_as<A, uint32_t> && std::invocable<const B &, uint32_t> {
    return b(i);
  }

  // The `.view` bridge: range-for, and every loop op of the STL (std::ranges::copy, any_of, find_if, ...) over a Series.
  // A std::forward_iterator whose operator* is the index function: a value, not a cell.
  struct iterator {
    using value_type = std::remove_cvref_t<std::invoke_result_t<const B &, uint32_t>>;
    using difference_type = std::ptrdiff_t;
    const Join *s = nullptr;
    uint32_t i = 0;
    constexpr decltype(auto) operator*() const { return (*s)[i]; }
    constexpr iterator &operator++() {
      ++i;
      return *this;
    }
    constexpr iterator operator++(int) { return {s, i++}; }
    constexpr bool operator==(const iterator &o) const { return i == o.i; }
  };
  constexpr iterator begin() const requires std::same_as<A, uint32_t> { return {this, 0}; }
  constexpr iterator end() const requires std::same_as<A, uint32_t> { return {this, a}; }
};
template <class A, class B> Join(A, B) -> Join<A, B>;
template <class F> using Series = Join<uint32_t, F>;

struct JoinTag {};
inline constexpr JoinTag j{};
template <class A> struct JoinLeft {
  A a;
};
template <class A> constexpr JoinLeft<A> operator|(A a, JoinTag) { return {std::move(a)}; }
template <class A, class B> constexpr Join<A, B> operator|(JoinLeft<A> l, B b) {
  return {std::move(l.a), std::move(b)};
}

/// A Series over contiguous memory.  The pointer must outlive the Series, and `n` is the caller's word.
template <class T> constexpr auto series(T *p, uint32_t n) {
  return n |j| [p](uint32_t i) -> T & { return p[i]; };
}

//===----------------------------------------------------------------------===//
// α: lazy projection
//===----------------------------------------------------------------------===//

struct AlphaTag {};
inline constexpr AlphaTag α{};
/// A series as it was given: a reference to a named one, the value of a temporary.  α and joins keep their sides in one.
template <class S> struct Held {
  S s;
};
template <class S> constexpr Held<S> operator|(S &&s, AlphaTag) { return {std::forward<S>(s)}; }
template <class S, class G> constexpr auto operator|(Held<S> l, G g) {
  uint32_t n = uint32_t(l.s.size());
  return n |j| [l = std::move(l), g = std::move(g)](uint32_t i) -> decltype(auto) { return g(l.s[i]); };
}

//===----------------------------------------------------------------------===//
// joins and combine: across the rows and along them (TrikeShed lib/Join.kt, lib/Combine.kt, cursor/CursorOps.kt)
//===----------------------------------------------------------------------===//

/// a joins b: row i is a[i] j b[i], as many rows as a has; that b has as many is the caller's word (TrikeShed's zip).
template <class A, class B> constexpr auto joins(A &&a, B &&b) {
  uint32_t n = uint32_t(a.size());
  return n |j| [l = Held<A>{std::forward<A>(a)}, r = Held<B>{std::forward<B>(b)}](uint32_t i) { return l.s[i] |j| r.s[i]; };
}

/// combine(parts): the rows of each series of `parts`, one part after another, and a + b is the combine of two.  The size is
/// counted once, when it is made, in 64 bits.  Nothing indexes a combine: it is drained, part by part (TrikeShed materializes).
template <class Parts> struct Combine {
  Parts parts;
  size_t n = 0;
  constexpr explicit Combine(Parts p) : parts(std::move(p)) { for (auto &&s : parts) n += s.size(); }
  constexpr size_t size() const { return n; }
};
template <class F> constexpr auto operator+(Series<F> a, Series<F> b) { return Combine(std::array{std::move(a), std::move(b)}); }

/// Copy a series into cells; the end of what was written.  A combine is copied part by part, each part in one loop.
template <std::ranges::input_range S, class T> constexpr T *drain(const S &s, T *out) { return std::ranges::copy(s, out).out; }
template <class Parts, class T> constexpr T *drain(const Combine<Parts> &c, T *out) {
  for (auto &&s : c.parts) out = drain(s, out);
  return out;
}

//===----------------------------------------------------------------------===//
// select: a series of the rows of two series, chosen by a third
//===----------------------------------------------------------------------===//

/// The rows of `a` and `b` chosen by `sel`: word i is `row j side` (TwInt), side 0 for a's row and 1 for b's.  This is a
/// shadowing top read where its rows lie -- `base // top` -- and it costs 8 bytes a row of selection against a row apiece
/// for a copy.  Between `joins` (side by side) and `combine` (one after the other): the rows of two series in one order,
/// chosen by a third.  Both sides must yield the same type; size(select(a, b, sel)) is size(sel).
template <class A, class B, class S> constexpr auto select(A &&a, B &&b, S &&sel) {
  uint32_t n = uint32_t(sel.size());
  return n |j| [l = Held<A>{std::forward<A>(a)}, r = Held<B>{std::forward<B>(b)},
                s = Held<S>{std::forward<S>(sel)}](uint32_t i) -> decltype(auto) {
    join::TwInt w = s.s[i];
    return w.second() ? r.s[w.first()] : l.s[w.first()];
  };
}

//===----------------------------------------------------------------------===//
// MutableSeries, ↺ and Cursor: where a Series is mutated, and says so
//===----------------------------------------------------------------------===//

template <class T> struct MutableSeries {
  std::vector<T> cells;
  bool operator==(const MutableSeries &) const = default;
  uint32_t size() const { return uint32_t(cells.size()); }
  T &operator[](uint32_t i) { return cells[i]; }
  const T &operator[](uint32_t i) const { return cells[i]; }
  /// Accumulate.  The result is the index of the new cell: the `b` of whatever refers back to it.
  uint32_t append(T v) {
    cells.push_back(std::move(v));
    return size() - 1;
  }
  /// Drain a cell: its value leaves and a default cell stays, so the indices of the others do not move.
  T drain(uint32_t i) { return std::exchange(cells[i], T{}); }
  /// The Series over the cells, as many as there are now.  It indexes through this series and holds no
  /// pointer into the cells, so an append that moves them does not leave it dangling.
  auto view() const {
    return size() |j| [this](uint32_t i) -> const T & { return cells[i]; };
  }
};

/// ↺, the constant anchor.  A null cell has not been forced: the first force runs `mint(i)` and the cell
/// is from then on the constant it produced.  The cell is addressed by index again after the mint,
/// because a mint may append to the very series it anchors in (a lambda nested in the body defers a
/// row) and an append moves the cells.
template <class T, class Mint> T anchor(MutableSeries<T> &cells, uint32_t i, Mint mint) {
  static_assert(std::is_pointer_v<T>, "a cell that was never forced is null");
  if (T v = cells[i]) return v;
  T v = mint(i);
  cells[i] = v;
  return v;
}

/// The instance pool of one type: a column per field (the names are its ColumnMeta), rows addressed by index.
template <class... T> struct Cursor {
  static constexpr size_t width = sizeof...(T);
  std::array<const char *, width> meta;
  std::tuple<MutableSeries<T>...> cols;

  explicit Cursor(std::array<const char *, width> names) : meta(names) {}
  /// The columns are the cases of an enum generated from include/Composite/TrikeShed.td: stringifyEnum names them.
  template <class E> requires std::is_enum_v<E> explicit Cursor(E) {
    for (size_t i = 0; i < width; i++) meta[i] = stringifyEnum(E(i)).data();
  }
  uint32_t size() const { return std::get<0>(cols).size(); }
  template <auto K> auto &col() { return std::get<size_t(K)>(cols); }
  template <auto K> const auto &col() const { return std::get<size_t(K)>(cols); }
  /// Accumulate one row; the result is its index.
  uint32_t append(T... cell) {
    std::apply([&](auto &...c) { (c.append(std::move(cell)), ...); }, cols);
    return size() - 1;
  }
  /// Row i, its cells copied out (a row is read before an append can move the cells), column by column.
  auto row(uint32_t i) const { return std::apply([i](const auto &...c) { return std::tuple(c[i]...); }, cols); }
  void clear() { std::apply([](auto &...c) { (c.cells.clear(), ...); }, cols); }
  void reserve(size_t n) { std::apply([n](auto &...c) { (c.cells.reserve(n), ...); }, cols); }
};

//===----------------------------------------------------------------------===//
// The laws, checked wherever this header is included
//===----------------------------------------------------------------------===//

constexpr bool lawsHold() {
  auto at = [](uint32_t i) { return int(i) * 10; };
  Series<decltype(at)> xs = 3u |j| at;
  auto inc = [](int x) { return x + 1; };
  auto dbl = [](int x) { return x * 2; };
  bool project = (xs |α| inc)[2] == 21;
  bool fuse = ((xs |α| inc) |α| dbl)[1] == 22; // α of α reads as α of the composition
  auto [lo, hi] = 1 |j| 2;                      // a Join destructures into its two sides
  int sum = 0;
  for (int x : xs) sum += x;
  return project && fuse && lo == 1 && hi == 2 && sum == 30 && (xs |α| inc).size() == 3;
}
constexpr bool selectHolds() {
  int a[] = {10, 30, 50}, b[] = {20};
  join::TwInt sel[] = {join::TwInt(0, 0), join::TwInt(0, 1), join::TwInt(1, 0)}; // a[0], b[0], a[1]
  auto m = select(series(a, 3), series(b, 1), series(sel, 3));
  int sum = 0;
  for (int x : m) sum += x;
  return m.size() == 3 && m[0] == 10 && m[1] == 20 && m[2] == 30 && sum == 60;
}
static_assert(lawsHold(), "the Series laws do not hold");
static_assert(selectHolds(), "the select law does not hold: a row is read where it lies, by row j side");


} // namespace composite

#endif
