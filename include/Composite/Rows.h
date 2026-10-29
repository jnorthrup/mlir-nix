//===- Rows.h - kernels over rows kept sorted by a key: find, sort, union ---===//
//
// Pure functions over a pointer and a length, with the key a function of the row, written for the optimizer to merge and prove things about:
// no state, no aliasing between inputs and outputs but the one named, a trip count that depends on the length alone.  No standard header.
// The attribute sets of the evaluator are rows of this kind; so is any sorted run (a pool column, a selection).
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_ROWS_H
#define COMPOSITE_ROWS_H

#include "Composite/Core.h"

namespace composite {

/// The row whose key is k among rows sorted by key, or null.  Each step picks its base by arithmetic, so there is no data-dependent branch.
template <class Row, class K, class Key> constexpr const Row *findRow(const Row *rows, size_t n, const K &k, Key key) {
  if (n == 0) return nullptr;
  const Row *base = rows;
  for (size_t half; (half = n / 2) != 0; n -= half) base = key(base[half]) <= k ? base + half : base;
  return key(*base) == k ? base : nullptr;
}

/// Sort rows in place, stable: equal rows keep their order.  An insertion sort for the short runs nearly every set is; a bottom-up merge
/// sort past that, through one temporary run of the same length.
template <class Row, class Less> void sortRows(Row *rows, size_t n, Less less) {
  static_assert(plainData<Row>, "rows are moved by copy");
  constexpr size_t kShort = 24;
  if (n <= kShort) {
    for (size_t i = 1; i < n; i++) {
      Row x = rows[i];
      size_t j = i;
      while (j > 0 && less(x, rows[j - 1])) { rows[j] = rows[j - 1]; --j; }
      rows[j] = x;
    }
    return;
  }
  Row *tmp = static_cast<Row *>(::operator new(n * sizeof(Row)));
  Row *src = rows, *dst = tmp;
  for (size_t w = 1; w < n; w *= 2) {
    for (size_t lo = 0; lo < n; lo += 2 * w) {
      size_t mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n;
      size_t i = lo, j = mid, k = lo;
      while (i < mid && j < hi) dst[k++] = less(src[j], src[i]) ? src[j++] : src[i++]; // the right run only when strictly less: stable
      while (i < mid) dst[k++] = src[i++];
      while (j < hi) dst[k++] = src[j++];
    }
    Row *t = src; src = dst; dst = t;
  }
  if (src != rows) for (size_t i = 0; i < n; i++) rows[i] = src[i];
  ::operator delete(tmp);
}

/// Rows sorted by key, the first of each run of equal keys kept: the rows left, packed at the front.
template <class Row, class Key> constexpr size_t uniqueFirst(Row *rows, size_t n, Key key) {
  size_t m = 0;
  for (size_t i = 0; i < n; i++) {
    if (m && key(rows[m - 1]) == key(rows[i])) continue;
    rows[m++] = rows[i];
  }
  return m;
}

/// The union of two runs sorted by key, `y` winning on an equal key: how many rows it has, and then the rows themselves.
template <class Row, class Key> constexpr size_t unionSize(const Row *x, size_t nx, const Row *y, size_t ny, Key key) {
  size_t i = 0, j = 0, n = 0;
  while (i < nx && j < ny) {
    auto a = key(x[i]), b = key(y[j]);
    if (a == b) { i++; j++; } else if (a < b) i++; else j++;
    n++;
  }
  return n + (nx - i) + (ny - j);
}
template <class Row, class Key> constexpr size_t unionRows(const Row *x, size_t nx, const Row *y, size_t ny, Row *out, Key key) {
  size_t i = 0, j = 0, k = 0;
  while (i < nx && j < ny) {
    auto a = key(x[i]), b = key(y[j]);
    if (a == b) { out[k++] = y[j]; i++; j++; }
    else if (a < b) out[k++] = x[i++];
    else out[k++] = y[j++];
  }
  while (i < nx) out[k++] = x[i++];
  while (j < ny) out[k++] = y[j++];
  return k;
}

} // namespace composite

#endif
