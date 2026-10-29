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
#include <initializer_list>
#include <iterator>
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

/// A size that is a type: Join<Size<N>, F> is a Series whose length is a compile-time fact.  The algorithms read it through
/// Marks (below) and take the straight-line path; a Join<uint32_t, F> keeps the loop.
template <uint32_t N> using Size = std::integral_constant<uint32_t, N>;
/// The domains that are a count: a runtime one (uint32_t) or a constant one (Size<N>).
template <class A> inline constexpr bool kSized = std::same_as<A, uint32_t>;
template <uint32_t N> inline constexpr bool kSized<Size<N>> = true;

template <class A, class B> struct Join {
  A a;
  B b;

  // A Join<uint32_t, F> is a Series (PRELOAD: typealias Series<T> = Join<Int, (Int) -> T>).  The domain is `a` and the
  // oracle `b`, for ANY domain: a count, a span (TwInt), a line and column, an enum case -- Join.kt's MetaSeries<I, T>.
  constexpr uint32_t size() const requires kSized<A> { return uint32_t(a); }
  constexpr const A &domain() const { return a; }
  constexpr const A &first() const { return a; }   // the accessors a packed Dense has, so a pair reads the same either way
  constexpr const B &second() const { return b; }
  constexpr decltype(auto) operator[](const A &k) const requires std::invocable<const B &, const A &> {
    return b(k);
  }
  /// A constant-size Series is indexed by a plain integer, as a Series is.
  constexpr decltype(auto) operator[](uint32_t i) const requires(kSized<A> && !std::same_as<A, uint32_t>) { return b(i); }

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
  constexpr iterator begin() const requires kSized<A> { return {this, 0}; }
  constexpr iterator end() const requires kSized<A> { return {this, uint32_t(a)}; }
};
template <class A, class B> Join(A, B) -> Join<A, B>;
template <class F> using Series = Join<uint32_t, F>;
/// The constant-size Series: the size is in the type.
template <uint32_t N, class F> using SeriesN = Join<Size<N>, F>;

struct JoinTag {};
inline constexpr JoinTag j{};
template <class A> struct JoinLeft {
  A a;
};
template <class A> constexpr JoinLeft<A> operator|(A a, JoinTag) { return {std::move(a)}; }
template <class A, class B> requires(!join::PacksInARegister<A, B>) constexpr Join<A, B> operator|(JoinLeft<A> l, B b) {
  return {std::move(l.a), std::move(b)};
}
/// Two scalars that fit one register are the packed word (Pack.h): `7u |j| 9u` is a TwInt, one integer, ordered as the pair is.
template <class A, class B> requires(join::PacksInARegister<A, B>) constexpr auto operator|(JoinLeft<A> l, B b) {
  return join::Dense<A, B>(l.a, b);
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

/// Marks<S>: what a Series is known to be at compile time, the premark an algorithm dispatches on (the shape of the Series
/// against the operation: fold, argMin and firstWhere ask, and a constant size takes the straight-line path).  A new shape
/// is one specialization, and an algorithm that does not ask gets the loop.
template <class S> struct Marks {
  static constexpr bool constant = false;
  static constexpr uint32_t size = 0;
};
template <uint32_t N, class F> struct Marks<Join<Size<N>, F>> {
  static constexpr bool constant = true;
  static constexpr uint32_t size = N;
};

/// A transform over a handful of registers must dissolve into its caller: a call per fold step costs more than the step.
#define COMPOSITE_INLINE [[gnu::always_inline]] inline

/// iota(n): the Series 0..n-1, the domain every index transform ranges over.
COMPOSITE_INLINE constexpr auto iota(uint32_t n) { return n |j| [](uint32_t i) { return i; }; }
/// iotaN<N>(): the indices 0..N-1 as a constant-size Series.
template <uint32_t N> COMPOSITE_INLINE constexpr auto iotaN() { return Size<N>{} |j| [](uint32_t i) { return i; }; }

/// fold(xs, init, f, halt): left reduction, f(state, x) -> state, stopping once halt(state).  This is the only loop the
/// algebra owns; first-match, contains, argmin, drain and the level walks of the funnel are folds with a state.
template <class S, class T, class F, class H>
COMPOSITE_INLINE constexpr T fold(const S &xs, T init, F f, H halt) {
  if constexpr (Marks<S>::constant) {
    // a constant size: the walk is straight-line code, halted step by step
    [&]<uint32_t... K>(std::integer_sequence<uint32_t, K...>) __attribute__((always_inline)) {
      ((halt(init) ? void() : void(init = f(std::move(init), xs[K]))), ...);
    }(std::make_integer_sequence<uint32_t, Marks<S>::size>{});
  } else {
    for (uint32_t i = 0, n = uint32_t(xs.size()); i < n && !halt(init); ++i) init = f(std::move(init), xs[i]);
  }
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

/// foldN<N>(init, f): the fold of f over the indices 0..N-1, with N a constant.  It is the fold of iotaN<N>(), so the premark
/// (Marks) sends it down the straight-line path: there is one unroller, in fold.
template <uint32_t N, class T, class F> COMPOSITE_INLINE constexpr T foldN(T init, F f) {
  return fold(iotaN<N>(), std::move(init), [&](T state, uint32_t k) __attribute__((always_inline)) -> T { return f(std::move(state), k); });
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
// Surgery without mutation: take, drop and their kin are views, and views compose
//===----------------------------------------------------------------------===//

// Each is O(1) and copies nothing: a Series whose index function reads the Series it was cut from, as `α` does (a named
// Series is read in place and must outlive the view; a temporary is kept).  take/drop/takeLast/dropLast are Kotlin's and
// range-v3's, `reversed` is the dialect's, and `erased` and `inserted` are the splice: the Series with one row skipped or one
// row added, which is what an erase or an insert on a list is when nothing needs to change in place.

/// The first n rows (fewer if the Series is shorter).
template <class S> constexpr auto take(S &&s, uint32_t n) {
  uint32_t m = n < uint32_t(s.size()) ? n : uint32_t(s.size());
  return m |j| [h = Held<S>{std::forward<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
/// All but the first n rows.
template <class S> constexpr auto drop(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? sz - n : 0u, k = n < sz ? n : sz;
  return m |j| [h = Held<S>{std::forward<S>(s)}, k](uint32_t i) -> decltype(auto) { return h.s[i + k]; };
}
/// The last n rows.
template <class S> constexpr auto takeLast(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? n : sz, off = sz - m;
  return m |j| [h = Held<S>{std::forward<S>(s)}, off](uint32_t i) -> decltype(auto) { return h.s[i + off]; };
}
/// All but the last n rows.
template <class S> constexpr auto dropLast(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? sz - n : 0u;
  return m |j| [h = Held<S>{std::forward<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
/// The rows in the opposite order.
template <class S> constexpr auto reversed(S &&s) {
  uint32_t sz = uint32_t(s.size());
  return sz |j| [h = Held<S>{std::forward<S>(s)}, sz](uint32_t i) -> decltype(auto) { return h.s[sz - 1 - i]; };
}
/// The Series with row `at` skipped (all of it if `at` is past the end).
template <class S> constexpr auto erased(S &&s, uint32_t at) {
  uint32_t sz = uint32_t(s.size()), m = at < sz ? sz - 1 : sz;
  return m |j| [h = Held<S>{std::forward<S>(s)}, at](uint32_t i) -> decltype(auto) { return h.s[i < at ? i : i + 1]; };
}
/// The Series with `v` as its row `at` (the rows from `at` on move one place up; `at` past the end appends).
template <class S, class V> constexpr auto inserted(S &&s, uint32_t at, V v) {
  uint32_t sz = uint32_t(s.size()), pos = at < sz ? at : sz;
  using Row = std::remove_cvref_t<decltype(s[0u])>;
  return (sz + 1) |j| [h = Held<S>{std::forward<S>(s)}, pos, v = Row(std::move(v))](uint32_t i) -> Row {
    return i < pos ? Row(h.s[i]) : i == pos ? v : Row(h.s[i - 1]);
  };
}

/// The constant-size forms: N rows, with N in the type, so the result is premarked and takes the straight-line paths.  The
/// caller's word is that the Series has the rows (a constant-size Series is checked).
template <uint32_t N, class S> constexpr auto take(S &&s) {
  if constexpr (Marks<std::remove_cvref_t<S>>::constant) static_assert(N <= Marks<std::remove_cvref_t<S>>::size, "take<N> of fewer rows");
  return Size<N>{} |j| [h = Held<S>{std::forward<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
template <uint32_t N, class S> constexpr auto drop(S &&s) {
  static_assert(Marks<std::remove_cvref_t<S>>::constant && N <= Marks<std::remove_cvref_t<S>>::size,
                "drop<N> needs a constant-size Series of at least N rows");
  return Size<Marks<std::remove_cvref_t<S>>::size - N>{} |j| [h = Held<S>{std::forward<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i + N]; };
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

/// The body of a frozen Series: cells that were built and are now only read.  Move-only, so the promotion from MutableSeries
/// is a move and a stray copy is a compile error, not a quiet materialization.
template <class T> struct Cells {
  std::vector<T> c;
  Cells(std::vector<T> &&v) : c(std::move(v)) {}
  Cells(Cells &&) = default;
  Cells &operator=(Cells &&) = default;
  Cells(const Cells &) = delete;
  Cells &operator=(const Cells &) = delete;
  const T &operator()(uint32_t i) const { return c[i]; }
};
template <class T> using Frozen = Series<Cells<T>>;

/// A known-size body: the array is the storage, on the stack, with no heap.
template <class T, size_t N> struct Slab {
  std::array<T, N> a;
  constexpr const T &operator()(uint32_t i) const { return a[i]; }
};
/// freeze(array): the handle for a body whose size is a constant.  vec<N>(f) builds one, freeze keeps it as a Series.
template <class T, size_t N> constexpr auto freeze(std::array<T, N> a) { return Size<uint32_t(N)>{} |j| Slab<T, N>{std::move(a)}; }

/// TrikeShed's TODO(): the operation a body cannot do yet, said out loud instead of done wrongly.  The algebra owns no I/O and no libc: the
/// host installs a sink that says it (the evaluator prints through LLVM's stream; a test prints through stdio), and the trap that follows is a
/// compiler builtin.  With no sink it traps silently.
using TodoSink = void (*)(const char *what);
inline TodoSink todoSink = nullptr;
[[noreturn, gnu::cold, gnu::noinline]] inline void TODO(const char *what) {
  if (todoSink) todoSink(what);
  __builtin_trap();
}

// The bodies of a MutableSeries: where the cells live.  Each is a handful of lines and gives the same five primitives
// (base, count, room, put, dropLast); the one algorithm below is written against those, and what a body cannot do (grow, be
// reserved, be frozen) is not there to call.

/// The growable body: the one std::vector.
template <class T> struct Growable {
  static constexpr bool growable = true;
  std::vector<T> cells;
  constexpr T *base() { return cells.data(); }
  constexpr const T *base() const { return cells.data(); }
  constexpr uint32_t count() const { return uint32_t(cells.size()); }
  constexpr bool room() const { return true; }
  constexpr void put(T v) { cells.push_back(std::move(v)); }
  constexpr void dropLast() { cells.pop_back(); }
};
/// The inline body: N cells and a count, on the stack, no heap.  Full is full.
template <class T, uint32_t N> struct Inline {
  static constexpr bool growable = false;
  std::array<T, N> cells{};
  uint32_t n = 0;
  constexpr T *base() { return cells.data(); }
  constexpr const T *base() const { return cells.data(); }
  constexpr uint32_t count() const { return n; }
  constexpr bool room() const { return n < N; }
  constexpr void put(T v) { cells[n++] = std::move(v); }
  constexpr void dropLast() { --n; }
};

template <class T, class Body = Growable<T>> struct MutableSeries : Body {
  constexpr MutableSeries() = default;
  explicit MutableSeries(size_t n) requires Body::growable : Body{std::vector<T>(n)} {}
  MutableSeries(size_t n, const T &v) requires Body::growable : Body{std::vector<T>(n, v)} {}
  template <class It> requires(!std::is_integral_v<It> && Body::growable) MutableSeries(It b, It e) : Body{std::vector<T>(b, e)} {}
  constexpr MutableSeries(std::initializer_list<T> il) { for (const T &x : il) append(x); }
  constexpr bool operator==(const MutableSeries &o) const {
    if (size() != o.size()) return false;
    for (uint32_t i = 0; i < size(); ++i) if (!((*this)[i] == o[i])) return false;
    return true;
  }
  constexpr uint32_t size() const { return this->count(); }
  constexpr T &operator[](uint32_t i) { return this->base()[i]; }
  constexpr const T &operator[](uint32_t i) const { return this->base()[i]; }
  /// Accumulate.  The result is the index of the new cell: the `b` of whatever refers back to it.  A body with no room says TODO.
  constexpr uint32_t append(T v) {
    if (!this->room()) [[unlikely]] TODO("append past the capacity of a fixed body");
    this->put(std::move(v));
    return size() - 1;
  }
  /// Accumulate a cell built in place.
  template <class... A> constexpr uint32_t emplace(A &&...a) { return append(T(std::forward<A>(a)...)); }
  constexpr void pop() { this->dropLast(); }
  constexpr void clear() { while (size()) pop(); }
  /// Remove cell i by moving the last cell into its place: the order of the others is not kept.  A bag's algorithm, for any body.
  constexpr void removeSwap(uint32_t i) { (*this)[i] = std::move((*this)[size() - 1]); pop(); }
  /// Drain a cell: its value leaves and a default cell stays, so the indices of the others do not move.
  constexpr T drain(uint32_t i) { return std::exchange((*this)[i], T{}); }
  // The container surface of a list that is built and then read: iteration, the ends, the raw cells.
  constexpr T *begin() { return this->base(); }
  constexpr T *end() { return this->base() + size(); }
  constexpr const T *begin() const { return this->base(); }
  constexpr const T *end() const { return this->base() + size(); }
  constexpr auto rbegin() { return std::reverse_iterator<T *>(end()); }
  constexpr auto rend() { return std::reverse_iterator<T *>(begin()); }
  constexpr auto rbegin() const { return std::reverse_iterator<const T *>(end()); }
  constexpr auto rend() const { return std::reverse_iterator<const T *>(begin()); }
  constexpr bool empty() const { return size() == 0; }
  constexpr T &back() { return (*this)[size() - 1]; }
  constexpr const T &back() const { return (*this)[size() - 1]; }
  constexpr T &front() { return (*this)[0]; }
  constexpr const T &front() const { return (*this)[0]; }
  constexpr T *data() { return this->base(); }
  constexpr const T *data() const { return this->base(); }
  // Only a growable body can be sized, reserved or frozen: for the others these are not there.
  constexpr void reserve(size_t n) requires Body::growable { this->cells.reserve(n); }
  constexpr void resize(size_t n) requires Body::growable { this->cells.resize(n); }
  constexpr void assign(size_t n, const T &v) requires Body::growable { this->cells.assign(n, v); }
  /// The promotion of the handle to its body: the cells move into a const Series.  Only an rvalue can be frozen, so the hand-over
  /// is written out (`std::move(x).freeze()`), costs a pointer, and leaves this series valid and empty.
  Frozen<T> freeze() && requires Body::growable { uint32_t n = size(); return n |j| Cells<T>(std::move(this->cells)); }
  Frozen<T> freeze() & = delete;
  /// The Series over the cells, as many as there are now.  It indexes through this series and holds no
  /// pointer into the cells, so an append that moves them does not leave it dangling.
  auto view() const {
    return size() |j| [this](uint32_t i) -> const T & { return (*this)[i]; };
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
