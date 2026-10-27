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
//   Slice<T>           a Series over cells in memory that is never freed: size j (i -> p[i]) with a name, so it can be
//                      a member.  16 bytes, trivially destructible; what the syntax tree holds in place of a vector.
//   MutableSeries<T>   a list that is mutated says so in its type.  It accumulates (append), then drains.
//   Grow<T>            the MutableSeries of a region: a Slice that is still being filled.  `done()` is the Slice.
//   anchor             ↺, the constant anchor: the first force of a cell mints it, every read after is
//                      the constant it produced.
//   Cursor<T...>       the instance pool of one type: a MutableSeries per column, plus the column names.
//                      PRELOAD's Cursor is Series<RowVec>, the row-shaped face of the same columns; no
//                      caller reads a pool row as a RowVec, so that face is a known gap, not built.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_SERIES_H
#define COMPOSITE_SERIES_H

#include <array>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

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

/// The `b` of a Series over contiguous memory, as a type with a name (the lambda of `series` has none).
template <class T> struct At {
  T *p;
  T &operator()(uint32_t i) const { return p[i]; }
};

/// `n j (i -> p[i])` over cells in a region that is never freed.  It is copied by value and never destroys its cells;
/// the cells are as mutable as the region (the parser sorts formals in place).  As in every Series, `n` is the word of
/// whoever built it and `xs[i]` is not checked.  Range-for walks the cells themselves, through pointers.
template <class T> struct Slice : Join<uint32_t, At<T>> {
  using Base = Join<uint32_t, At<T>>;
  constexpr Slice() : Base{0, At<T>{nullptr}} {}
  constexpr Slice(T *p, uint32_t n) : Base{n, At<T>{p}} {}
  constexpr uint32_t size() const { return this->a; }
  constexpr bool empty() const { return this->a == 0; }
  constexpr T *data() const { return this->b.p; }
  constexpr T *begin() const { return this->b.p; }
  constexpr T *end() const { return this->b.p + this->a; }
  constexpr T &front() const { return this->b.p[0]; }
  constexpr T &back() const { return this->b.p[this->a - 1]; }
};

//===----------------------------------------------------------------------===//
// α: lazy projection
//===----------------------------------------------------------------------===//

struct AlphaTag {};
inline constexpr AlphaTag α{};
template <class S> struct AlphaLeft {
  S s;
};
template <class S> constexpr AlphaLeft<S> operator|(S &&s, AlphaTag) { return {std::forward<S>(s)}; }
template <class S, class G> constexpr auto operator|(AlphaLeft<S> l, G g) {
  uint32_t n = uint32_t(l.s.size());
  return n |j| [l = std::move(l), g = std::move(g)](uint32_t i) { return g(l.s[i]); };
}

//===----------------------------------------------------------------------===//
// MutableSeries, ↺ and Cursor: where a Series is mutated, and says so
//===----------------------------------------------------------------------===//

template <class T> struct MutableSeries {
  std::vector<T> cells;
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

/// A Slice that is still being filled: the MutableSeries of a region.  `Region` is anything with `template <class U> U
/// *Allocate(size_t n)` (llvm::BumpPtrAllocator).  An append past the capacity copies the cells to a run of twice the
/// size and leaves the old run in the region, so the region holds at most twice the final size.  Cells are copied, never
/// destroyed: T is trivially copyable.  `done()` is the Slice over what was appended; the capacity is not kept.
template <class T> struct Grow : Slice<T> {
  static_assert(std::is_trivially_copyable_v<T> && std::is_trivially_destructible_v<T>, "cells live in a region that is not freed");
  uint32_t cap = 0;

  Grow() = default;
  /// Reopen a finished Slice: the cells are copied (the Slice's run has no room), with room for `extra` more.
  template <class Region> static Grow from(Region &region, Slice<T> s, uint32_t extra) {
    Grow g;
    g.reserve(region, s.size() + extra);
    if (s.size()) std::memcpy(static_cast<void *>(g.b.p), static_cast<const void *>(s.data()), s.size() * sizeof(T));
    g.a = s.size();
    return g;
  }
  template <class Region> void push(Region &region, const T &v) {
    if (this->a == cap) reserve(region, cap ? cap * 2 : 4);
    new (static_cast<void *>(this->b.p + this->a)) T(v);
    this->a++;
  }
  constexpr Slice<T> done() const { return Slice<T>(this->b.p, this->a); }

private:
  template <class Region> void reserve(Region &region, uint32_t want) {
    if (want <= cap) return;
    T *run = region.template Allocate<T>(want);
    if (this->a) std::memcpy(static_cast<void *>(run), static_cast<const void *>(this->b.p), this->a * sizeof(T));
    this->b.p = run;
    cap = want;
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
  uint32_t size() const { return std::get<0>(cols).size(); }
  template <size_t K> auto &col() { return std::get<K>(cols); }
  template <size_t K> const auto &col() const { return std::get<K>(cols); }
  /// Accumulate one row; the result is its index.
  uint32_t append(T... cell) {
    uint32_t row = size();
    appendFrom<0>(std::move(cell)...);
    return row;
  }
  template <size_t K, class First, class... Rest> void appendFrom(First &&first, Rest &&...rest) {
    std::get<K>(cols).append(std::forward<First>(first));
    if constexpr (sizeof...(Rest) > 0) appendFrom<K + 1>(std::forward<Rest>(rest)...);
  }
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
static_assert(lawsHold(), "the Series laws do not hold");

} // namespace composite

#endif
