//===- Folds.h - the transforms built on fold: iota, vec, firstWhere, argMin ---===//

#ifndef COMPOSITE_FOLDS_H
#define COMPOSITE_FOLDS_H

#include "Composite/Series.h"

namespace composite {

/// iota(n): the Series 0..n-1, the domain every index transform ranges over.
constexpr auto iota(uint32_t n) { return n |j| [](uint32_t i) { return i; }; }
/// iotaN<N>(): the indices 0..N-1 as a constant-size Series.
template <uint32_t N> constexpr auto iotaN() { return Size<N>{} |j| [](uint32_t i) { return i; }; }

/// vec<N>(f): Kotlin's `List(N) { f(it) }`.  The size is a constant, the generator is called once per index, and the layout is the flat
/// array of N cells -- nothing to discover.  The indices are walked by recursion in the type, so it is straight-line code.
template <uint32_t K, uint32_t N, class A, class F> constexpr void fillVec(A &out, F &f) {
  if constexpr (K < N) {
    out.a[K] = f(K);
    fillVec<K + 1, N>(out, f);
  }
}
template <uint32_t N, class F> constexpr auto vec(F f) {
  Arr<bare_t<decltype(f(0u))>, N> out{};
  fillVec<0, N>(out, f);
  return out;
}


/// The index of the first element satisfying p, or size when none does (the Series' own bisect convention).
template <class S, class P> constexpr uint32_t firstWhere(const S &xs, P p) {
  struct At { uint32_t i; bool hit; };
  At r = fold(iota(uint32_t(xs.size())), At{uint32_t(xs.size()), false},
              [&](At a, uint32_t k) { return p(xs[k]) ? At{k, true} : a; }, [](const At &a) { return a.hit; });
  return r.i;
}
template <class S, class P> constexpr bool anyOf(const S &xs, P p) { return firstWhere(xs, mv(p)) < uint32_t(xs.size()); }

/// The index of the least element under less (the first of equals); 0 when xs is empty.  Seeded from element 0, so a
/// Series of n elements costs n-1 comparisons.
template <class S, class L> constexpr uint32_t argMin(const S &xs, L less) {
  uint32_t n = uint32_t(xs.size());
  return fold(iota(n ? n - 1 : 0), 0u, [&](uint32_t m, uint32_t k) { return less(xs[k + 1], xs[m]) ? k + 1 : m; });
}

} // namespace composite

#endif
