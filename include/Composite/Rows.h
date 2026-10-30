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

/// Sort n rows read from `src` into `dst`, stable: equal rows keep their order.  `src` is only read, and is either `dst` itself or apart from
/// it: a const source is not copied first, the first pass reads it where it lies.  That pass insertion-sorts runs of kRun rows, the short
/// sets nearly every set is; longer ones are merged bottom-up through one temporary run of the same length, and the runs are written to
/// whichever side makes the last merge land in `dst`, so nothing is copied back.
template <class Row, class Less> void sortRows(const Row *src, Row *dst, size_t n, Less less) {
  static_assert(plainData<Row>, "rows are moved by copy");
  constexpr size_t kRun = 24;
  size_t passes = 0;
  for (size_t w = kRun; w < n; w *= 2) passes++;
  struct Temp { // the other side of the merges, released when this leaves scope, a comparator that throws included
    Row *p;
    explicit Temp(size_t m) : p(m ? static_cast<Row *>(::operator new(m * sizeof(Row))) : nullptr) {}
    ~Temp() { ::operator delete(p); }
  } temp(passes ? n : 0);
  Row *a = passes % 2 ? temp.p : dst, *b = passes % 2 ? dst : temp.p;
  for (size_t lo = 0; lo < n; lo += kRun) {
    size_t hi = lo + kRun < n ? lo + kRun : n;
    for (size_t i = lo; i < hi; i++) { // src[i] is read before a[i] is written, so src may be a
      Row x = src[i];
      size_t k = i;
      while (k > lo && less(x, a[k - 1])) { a[k] = a[k - 1]; --k; }
      a[k] = x;
    }
  }
  for (size_t w = kRun; w < n; w *= 2) {
    for (size_t lo = 0; lo < n; lo += 2 * w) {
      size_t mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n;
      size_t i = lo, j = mid, k = lo;
      while (i < mid && j < hi) b[k++] = less(a[j], a[i]) ? a[j++] : a[i++]; // the right run only when strictly less: stable
      while (i < mid) b[k++] = a[i++];
      while (j < hi) b[k++] = a[j++];
    }
    Row *t = a; a = b; b = t;
  }
}
/// Sort rows in place, stable.
template <class Row, class Less> void sortRows(Row *rows, size_t n, Less less) { sortRows(static_cast<const Row *>(rows), rows, n, less); }

/// Rows sorted by key, the first of each run of equal keys kept: the rows left, packed at the front.
/// How many distinct keys n rows sorted by key hold: the size uniqueFirst would leave, without moving a row.
template <class Row, class Key> constexpr size_t uniqueCount(const Row *rows, size_t n, Key key) {
  size_t m = 0;
  for (size_t i = 0; i < n; i++) m += i == 0 || !(key(rows[i - 1]) == key(rows[i]));
  return m;
}

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

/// unionRows in one pass, into room for nx + ny rows: the rows written.  When `y` is much the smaller (an override over a large set), each
/// of its rows finds its place in `x` by a search and the run of `x` before it is copied whole, not compared row by row.
template <class Row, class Key> constexpr size_t unionInto(const Row *x, size_t nx, const Row *y, size_t ny, Row *out, Key key) {
  if (ny * 16 >= nx) return unionRows(x, nx, y, ny, out, key);
  size_t i = 0, k = 0;
  for (size_t j = 0; j < ny; j++) {
    auto b = key(y[j]);
    size_t lo = i, hi = nx; // the first row of x from i on whose key is not below b
    while (lo < hi) {
      size_t mid = lo + (hi - lo) / 2;
      if (key(x[mid]) < b) lo = mid + 1;
      else hi = mid;
    }
    for (; i < lo; i++) out[k++] = x[i];
    out[k++] = y[j];
    if (i < nx && key(x[i]) == b) i++; // the row y shadows
  }
  for (; i < nx; i++) out[k++] = x[i];
  return k;
}

} // namespace composite

#endif
