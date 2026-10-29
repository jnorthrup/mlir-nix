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
//                      one out as a tuple, column by column (a mint reads its pool row so), and `rows()` is the same
//                      columns as one Series of row tuples.  The row is copied whole and a use that reads one member
//                      dissolves the copies of the others as dead code, so there is no lazy projection to build.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_SERIES_H
#define COMPOSITE_SERIES_H

#include <algorithm>
#include <array>
#include <bit>
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

  // A Join<uint32_t, F> is a Series (PRELOAD: typealias Series<T> = Join<Int, (Int) -> T>).  The domain is `a` and the
  // oracle `b`, for ANY domain: a count, a span (TwInt), a line and column, an enum case -- Join.kt's MetaSeries<I, T>.
  constexpr uint32_t size() const requires std::same_as<A, uint32_t> { return a; }
  constexpr const A &domain() const { return a; }
  constexpr decltype(auto) operator[](const A &k) const requires std::invocable<const B &, const A &> {
    return b(k);
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
// fold: the one loop.  Everything that walks a Series is a transform over it.
//===----------------------------------------------------------------------===//

/// A transform over a handful of registers must dissolve into its caller: a call per fold step costs more than the step.
#define COMPOSITE_INLINE [[gnu::always_inline]] inline

/// iota(n): the Series 0..n-1, the domain every index transform ranges over.
COMPOSITE_INLINE constexpr auto iota(uint32_t n) { return n |j| [](uint32_t i) { return i; }; }

/// fold(xs, init, f, halt): left reduction, f(state, x) -> state, stopping once halt(state).  This is the only loop the
/// algebra owns; first-match, contains, argmin, drain and the level walks of the funnel are folds with a state.
template <class S, class T, class F, class H>
COMPOSITE_INLINE constexpr T fold(const S &xs, T init, F f, H halt) {
  for (uint32_t i = 0, n = uint32_t(xs.size()); i < n && !halt(init); ++i) init = f(std::move(init), xs[i]);
  return init;
}
template <class S, class T, class F> COMPOSITE_INLINE constexpr T fold(const S &xs, T init, F f) {
  return fold(xs, std::move(init), std::move(f), [](const T &) { return false; });
}

/// vec<N>(f): Kotlin's `List(N) { f(it) }`.  The size is a constant, the generator is called once per index, and the layout
/// is the flat array of N cells -- nothing to discover.  No loop: the indices are an integer sequence, expanded at compile time.
template <uint32_t N, class F> COMPOSITE_INLINE constexpr auto vec(F f) {
  return [&]<uint32_t... K>(std::integer_sequence<uint32_t, K...>) __attribute__((always_inline)) {
    return std::array<std::remove_cvref_t<decltype(f(0u))>, N>{f(K)...};
  }(std::make_integer_sequence<uint32_t, N>{});
}

/// foldN<N>(init, f): the fold of f over the indices 0..N-1 with N a constant, so the whole walk is straight-line code.
template <uint32_t N, class T, class F> COMPOSITE_INLINE constexpr T foldN(T init, F f) {
  [&]<uint32_t... K>(std::integer_sequence<uint32_t, K...>) __attribute__((always_inline)) { ((init = f(std::move(init), K)), ...); }(std::make_integer_sequence<uint32_t, N>{});
  return init;
}

/// The index of the first element satisfying p, or size when none does (the Series' own bisect convention).
template <class S, class P> COMPOSITE_INLINE constexpr uint32_t firstWhere(const S &xs, P p) {
  struct At { uint32_t i; bool hit; };
  At r = fold(iota(uint32_t(xs.size())), At{uint32_t(xs.size()), false},
              [&](At a, uint32_t k) { return p(xs[k]) ? At{k, true} : a; }, [](const At &a) { return a.hit; });
  return r.i;
}
template <class S, class P> constexpr bool anyOf(const S &xs, P p) { return firstWhere(xs, std::move(p)) < uint32_t(xs.size()); }

/// The index of the least element under less (the first of equals); 0 when xs is empty.  Seeded from element 0, so a
/// Series of n elements costs n-1 comparisons.
template <class S, class L> COMPOSITE_INLINE constexpr uint32_t argMin(const S &xs, L less) {
  uint32_t n = uint32_t(xs.size());
  return fold(iota(n ? n - 1 : 0), 0u, [&](uint32_t m, uint32_t k) { return less(xs[k + 1], xs[m]) ? k + 1 : m; });
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
  constexpr uint32_t size() const { return uint32_t(cells.size()); }
  T &operator[](uint32_t i) { return cells[i]; }
  constexpr const T &operator[](uint32_t i) const { return cells[i]; }
  /// Accumulate.  The result is the index of the new cell: the `b` of whatever refers back to it.
  constexpr uint32_t append(T v) {
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
  constexpr uint32_t size() const { return std::get<0>(cols).size(); }
  template <auto K> auto &col() { return std::get<size_t(K)>(cols); }
  template <auto K> const auto &col() const { return std::get<size_t(K)>(cols); }
  /// Accumulate one row; the result is its index.
  uint32_t append(T... cell) {
    std::apply([&](auto &...c) { (c.append(std::move(cell)), ...); }, cols);
    return size() - 1;
  }
  /// Row i, its cells copied out (a row is read before an append can move the cells), column by column.
  constexpr auto row(uint32_t i) const { return std::apply([i](const auto &...c) { return std::tuple(c[i]...); }, cols); }
  /// The Series<RowVec> face: the same columns as one Series, a row a position.  Every combinator works over rows
  /// (`a + b` appends, α projects, fold reduces, where picks); the row is copied whole, and a use that reads one
  /// member dissolves the copies of the rest as dead code, which is why there is no lazy projection beside this.
  auto rows() const { return size() |j| [this](uint32_t i) { return row(i); }; }
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
constexpr bool rowSeriesHolds() {
  int i0[] = {10, 20};
  char c0[] = {'a', 'b'};
  auto rs = 2u |j| [i0, c0](uint32_t i) { return std::tuple(i0[i], c0[i]); }; // the shape rows() yields
  bool same = rs.size() == 2 && rs[1] == std::tuple(20, 'b');
  auto firsts = rs |α| [](std::tuple<int, char> r) { return std::get<0>(r); };
  bool project = firsts.size() == 2 && firsts[0] == 10 && firsts[1] == 20;
  int sum = 0;
  for (auto r : rs) sum += std::get<0>(r);
  return same && project && sum == 30;
}
// The law runs on the shape because C++20 cannot constant-evaluate a Cursor: a std::vector member is not a
// literal type before C++23.  These two pin rows() itself: it returns a Series whose element is the row tuple.
static_assert(std::is_same_v<decltype(std::declval<const Cursor<int, char> &>().rows()[0]), std::tuple<int, char>>);
static_assert(std::is_same_v<decltype(std::declval<const Cursor<int, char> &>().rows().size()), uint32_t>);
static_assert(rowSeriesHolds(), "the Series<RowVec> face does not hold: a cursor is a Series of its rows");
static_assert(lawsHold(), "the Series laws do not hold");
static_assert(selectHolds(), "the select law does not hold: a row is read where it lies, by row j side");


} // namespace composite

#endif
