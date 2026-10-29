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
//   fold               the one loop; Marks<S> is the premark it dispatches on.
//
// Only the hot aliases live here.  The mix-ins that need them are separate headers, so none of them sits on the include path of the
// types every file names: Folds.h (iota, vec, foldN, firstWhere, argMin), Views.h (take/drop/... and joins/combine/drain), Mutable.h
// (MutableSeries and its bodies), Pool.h (select, Sel, Cursor, anchor), Laws.h (the self-tests); All.h includes the lot.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_SERIES_H
#define COMPOSITE_SERIES_H

#include "Composite/Core.h" // nothing else: no standard header, no libc
#include "Composite/Pack.h"  // TwInt: the `row j side` word of a selection

namespace composite {

//===----------------------------------------------------------------------===//
// Join, and Series as the Join whose first side is a size
//===----------------------------------------------------------------------===//

/// A size that is a type: Join<Size<N>, F> is a Series whose length is a compile-time fact.  The algorithms read it through
/// Marks (below) and take the straight-line path; a Join<uint32_t, F> keeps the loop.
template <uint32_t N> using Size = Const<uint32_t, N>;
/// The domains that are a count: a runtime one (uint32_t) or a constant one (Size<N>).
template <class A> inline constexpr bool kSized = same<A, uint32_t>;
template <uint32_t N> inline constexpr bool kSized<Size<N>> = true;

/// The index function of contiguous memory: the pointer is all of it.  So a Series over memory (series(p, n), below) is a pointer and a
/// count, and reads both back: data() and size().
template <class T> struct Ptr {
  T *p;
  constexpr T &operator()(uint32_t i) const { return p[i]; }
};
template <class B> inline constexpr bool kPtr = false;
template <class T> inline constexpr bool kPtr<Ptr<T>> = true;

template <class A, class B> struct Join {
  A a;
  B b;

  // A Join<uint32_t, F> is a Series (PRELOAD: typealias Series<T> = Join<Int, (Int) -> T>).  The domain is `a` and the
  // oracle `b`, for ANY domain: a count, a span (TwInt), a line and column, an enum case -- Join.kt's MetaSeries<I, T>.
  constexpr uint32_t size() const requires kSized<A> { return uint32_t(a); }
  constexpr const A &domain() const { return a; }
  constexpr const A &first() const { return a; }   // the accessors a packed Dense has, so a pair reads the same either way
  constexpr const B &second() const { return b; }
  /// A Series over memory gives its pointer back.
  constexpr auto data() const requires kPtr<B> { return b.p; }
  constexpr decltype(auto) operator[](const A &k) const {
    return b(k);
  }
  /// A constant-size Series is indexed by a plain integer, as a Series is.
  constexpr decltype(auto) operator[](uint32_t i) const requires(kSized<A> && !same<A, uint32_t>) { return b(i); }

  // Range-for over a Series: an iterator whose operator* is the index function: a value, not a cell.
  struct iterator {
    using value_type = bare_t<decltype(declval<const B &>()(declval<uint32_t>()))>;
    using difference_type = __PTRDIFF_TYPE__;
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
template <class A> constexpr JoinLeft<A> operator|(A a, JoinTag) { return {mv(a)}; }
template <class A, class B> requires(!join::PacksInARegister<A, B>) constexpr Join<A, B> operator|(JoinLeft<A> l, B b) {
  return {mv(l.a), mv(b)};
}
/// Two scalars that fit one register are the packed word (Pack.h): `7u |j| 9u` is a TwInt, one integer, ordered as the pair is.
template <class A, class B> requires(join::PacksInARegister<A, B>) constexpr auto operator|(JoinLeft<A> l, B b) {
  return join::Dense<A, B>(l.a, b);
}

/// A Series over contiguous memory.  The pointer must outlive the Series, and `n` is the caller's word.
template <class T> constexpr Series<Ptr<T>> series(T *p, uint32_t n) { return {n, {p}}; }
/// The cells from..to of a Series over memory, over the same memory: a window of a window is a window of the same cells.
template <class T> constexpr Series<Ptr<T>> slice(const Series<Ptr<T>> &s, uint32_t from, uint32_t to) {
  if (from > to || to > s.a) TODO("a slice outside its series");
  return {to - from, {s.b.p + from}};
}
/// Series<Char>: characters over memory, never owned, never copied, the weight of a string_view.  Text with a cursor (CharSeries) is one
/// of these and casts down to it when the cursor's work is done: what reads the characters then needs nothing past this header.
using Chars = Series<Ptr<const char>>;
constexpr Chars chars(const char *p, uint32_t n) { return series(p, n); }

//===----------------------------------------------------------------------===//
// α: lazy projection
//===----------------------------------------------------------------------===//

struct AlphaTag {};
inline constexpr AlphaTag α{};
/// A series as it was given: a reference to a named one, the value of a temporary.  α and joins keep their sides in one.
template <class S> struct Held {
  S s;
};
template <class S> constexpr Held<S> operator|(S &&s, AlphaTag) { return {fw<S>(s)}; }
template <class S, class G> constexpr auto operator|(Held<S> l, G g) {
  uint32_t n = uint32_t(l.s.size());
  return n |j| [l = mv(l), g = mv(g)](uint32_t i) -> decltype(auto) { return g(l.s[i]); };
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

/// fold(xs, init, f, halt): left reduction, f(state, x) -> state, stopping once halt(state).  This is the only loop the
/// algebra owns; first-match, contains, argmin, drain and the level walks of the funnel are folds with a state.
/// The straight-line walk of a constant-size Series: step K, then K+1, halted step by step; the recursion is the unrolling.
template <uint32_t K, uint32_t N, class S, class T, class F, class H>
constexpr void unroll(const S &xs, T &acc, F &f, H &halt) {
  if constexpr (K < N) {
    if (!halt(acc)) {
      acc = f(mv(acc), xs[K]);
      unroll<K + 1, N>(xs, acc, f, halt);
    }
  }
}
template <class S, class T, class F, class H>
constexpr T fold(const S &xs, T init, F f, H halt) {
  if constexpr (Marks<S>::constant) {
    unroll<0, Marks<S>::size>(xs, init, f, halt); // a constant size: the walk is straight-line code
  } else {
    for (uint32_t i = 0, n = uint32_t(xs.size()); i < n && !halt(init); ++i) init = f(mv(init), xs[i]);
  }
  return init;
}
template <class S, class T, class F> constexpr T fold(const S &xs, T init, F f) {
  return fold(xs, mv(init), mv(f), [](const T &) { return false; });
}

/// The order of two Series<char> as memcmp has it (unsigned bytes, then the shorter first): a fold to the first difference.  Text with a
/// cursor (CharSeries) is cast down to its Series<char> first, so an ordering needs nothing past this header and the cursor is dead.
template <class A, class B> constexpr bool lessChars(const A &a, const B &b) {
  uint32_t na = uint32_t(a.size()), nb = uint32_t(b.size());
  auto diffs = (na < nb ? na : nb) |j| [&](uint32_t i) { return int(uint8_t(a[i])) - int(uint8_t(b[i])); };
  int d = fold(diffs, 0, [](int, int x) { return x; }, [](int x) { return x != 0; });
  return d != 0 ? d < 0 : na < nb;
}

} // namespace composite

#endif
