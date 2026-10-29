//===- Views.h - surgery without mutation, and joins and combine ---===//

#ifndef COMPOSITE_VIEWS_H
#define COMPOSITE_VIEWS_H

#include "Composite/Series.h"

namespace composite {

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
  return m |j| [h = Held<S>{fw<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
/// All but the first n rows.
template <class S> constexpr auto drop(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? sz - n : 0u, k = n < sz ? n : sz;
  return m |j| [h = Held<S>{fw<S>(s)}, k](uint32_t i) -> decltype(auto) { return h.s[i + k]; };
}
/// The last n rows.
template <class S> constexpr auto takeLast(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? n : sz, off = sz - m;
  return m |j| [h = Held<S>{fw<S>(s)}, off](uint32_t i) -> decltype(auto) { return h.s[i + off]; };
}
/// All but the last n rows.
template <class S> constexpr auto dropLast(S &&s, uint32_t n) {
  uint32_t sz = uint32_t(s.size()), m = n < sz ? sz - n : 0u;
  return m |j| [h = Held<S>{fw<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
/// The rows in the opposite order.
template <class S> constexpr auto reversed(S &&s) {
  uint32_t sz = uint32_t(s.size());
  return sz |j| [h = Held<S>{fw<S>(s)}, sz](uint32_t i) -> decltype(auto) { return h.s[sz - 1 - i]; };
}
/// The Series with row `at` skipped (all of it if `at` is past the end).
template <class S> constexpr auto erased(S &&s, uint32_t at) {
  uint32_t sz = uint32_t(s.size()), m = at < sz ? sz - 1 : sz;
  return m |j| [h = Held<S>{fw<S>(s)}, at](uint32_t i) -> decltype(auto) { return h.s[i < at ? i : i + 1]; };
}
/// The Series with `v` as its row `at` (the rows from `at` on move one place up; `at` past the end appends).
template <class S, class V> constexpr auto inserted(S &&s, uint32_t at, V v) {
  uint32_t sz = uint32_t(s.size()), pos = at < sz ? at : sz;
  using Row = bare_t<decltype(s[0u])>;
  return (sz + 1) |j| [h = Held<S>{fw<S>(s)}, pos, v = Row(mv(v))](uint32_t i) -> Row {
    return i < pos ? Row(h.s[i]) : i == pos ? v : Row(h.s[i - 1]);
  };
}

/// The constant-size forms: N rows, with N in the type, so the result is premarked and takes the straight-line paths.  The
/// caller's word is that the Series has the rows (a constant-size Series is checked).
template <uint32_t N, class S> constexpr auto take(S &&s) {
  if constexpr (Marks<bare_t<S>>::constant) static_assert(N <= Marks<bare_t<S>>::size, "take<N> of fewer rows");
  return Size<N>{} |j| [h = Held<S>{fw<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i]; };
}
template <uint32_t N, class S> constexpr auto drop(S &&s) {
  static_assert(Marks<bare_t<S>>::constant && N <= Marks<bare_t<S>>::size,
                "drop<N> needs a constant-size Series of at least N rows");
  return Size<Marks<bare_t<S>>::size - N>{} |j| [h = Held<S>{fw<S>(s)}](uint32_t i) -> decltype(auto) { return h.s[i + N]; };
}

//===----------------------------------------------------------------------===//
// joins and combine: across the rows and along them (TrikeShed lib/Join.kt, lib/Combine.kt, cursor/CursorOps.kt)
//===----------------------------------------------------------------------===//

/// a joins b: row i is a[i] j b[i], as many rows as a has; that b has as many is the caller's word (TrikeShed's zip).
template <class A, class B> constexpr auto joins(A &&a, B &&b) {
  uint32_t n = uint32_t(a.size());
  return n |j| [l = Held<A>{fw<A>(a)}, r = Held<B>{fw<B>(b)}](uint32_t i) { return l.s[i] |j| r.s[i]; };
}

/// combine(parts): the rows of each series of `parts`, one part after another, and a + b is the combine of two.  The size is
/// counted once, when it is made, in 64 bits.  Nothing indexes a combine: it is drained, part by part (TrikeShed materializes).
template <class Parts> struct Combine {
  Parts parts;
  size_t n = 0;
  constexpr explicit Combine(Parts p) : parts(mv(p)) { for (auto &&s : parts) n += s.size(); }
  constexpr size_t size() const { return n; }
};
template <class F> constexpr auto operator+(Series<F> a, Series<F> b) { return Combine(Arr<Series<F>, 2>{{mv(a), mv(b)}}); }

/// Copy a series into cells; the end of what was written.  A combine is copied part by part, each part in one loop.
template <class S, class T> constexpr T *drain(const S &s, T *out) {
  for (uint32_t i = 0, n = uint32_t(s.size()); i < n; ++i) *out++ = s[i];
  return out;
}
template <class Parts, class T> constexpr T *drain(const Combine<Parts> &c, T *out) {
  for (auto &&s : c.parts) out = drain(s, out);
  return out;
}

} // namespace composite

#endif
