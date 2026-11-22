//===- Views.h - joins, and drain ---===//

#ifndef COMPOSITE_VIEWS_H
#define COMPOSITE_VIEWS_H

#include "Composite/Series.h"

namespace composite {

//===----------------------------------------------------------------------===//
// joins across the rows (TrikeShed lib/Join.kt); take, drop, reversed and combine are the trikeshed dialect's slice, take,
// reversed, combine and combineAll (TrikeShed.td), lowered by trikeshed-lower-cursors
//===----------------------------------------------------------------------===//

/// a joins b: row i is a[i] j b[i], as many rows as a has; that b has as many is the caller's word (TrikeShed's zip).
template <class A, class B> constexpr auto joins(A &&a, B &&b) {
  uint32_t n = uint32_t(a.size());
  return n |j| [l = Held<A>{fw<A>(a)}, r = Held<B>{fw<B>(b)}](uint32_t i) { return l.s[i] |j| r.s[i]; };
}

/// Copy a series into cells; the end of what was written.
template <class S, class T> constexpr T *drain(const S &s, T *out) {
  for (uint32_t i = 0, n = uint32_t(s.size()); i < n; ++i) *out++ = s[i];
  return out;
}

} // namespace composite

#endif
