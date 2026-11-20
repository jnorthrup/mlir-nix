//===- Rows.h - kernels over rows kept sorted by a key: find, sort, union ---===//
//
// The bridge to lowered/composite/Rows.mlir, where the algorithms are: findRow's branchless search, sortRows' runs of 24 insertion-sorted
// rows merged bottom-up (stable: the right run only when strictly less), uniqueFirst, and the union of two sorted runs, `y` winning on an
// equal key.  The keyed kernels read each row's leading uint32_t as its key (Attr::name, an attrs shape's symbol); the sort calls `less`
// back for each comparison, in the same order as ever, so a comparator that throws leaves by the same comparison.  No standard header.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_ROWS_H
#define COMPOSITE_ROWS_H

#include "Composite/Core.h"

namespace composite {

extern "C" {
const void *mlnix_rows_find(const void *rows, int64_t rowBytes, int64_t n, int64_t k);
int64_t mlnix_rows_unique_first(void *rows, int64_t rowBytes, int64_t n);
int64_t mlnix_rows_union_size(const void *x, int64_t rowBytes, int64_t nx, const void *y, int64_t ny);
int64_t mlnix_rows_union_into(const void *x, int64_t rowBytes, int64_t nx, const void *y, int64_t ny, void *out);
void mlnix_rows_sort(const void *src, void *dst, void *temp, int64_t n, int64_t rowBytes, int32_t (*less)(void *, const void *, const void *), void *ctx);
void mlnix_rows_sort_u32(const void *src, void *dst, void *temp, int64_t n, int64_t rowBytes);
}

template <class Row> constexpr bool keyedRow = plainData<Row> && sizeof(Row) >= 4 && alignof(Row) >= 4; // a leading uint32_t key
/// The row whose key is k among rows sorted by key, or null.
template <class Row> const Row *findRow(const Row *rows, size_t n, uint32_t k) {
  static_assert(keyedRow<Row>);
  return static_cast<const Row *>(mlnix_rows_find(rows, sizeof(Row), int64_t(n), k));
}

/// Sort n rows read from `src` into `dst`, stable: equal rows keep their order.  `src` is only read, and is either `dst` itself or apart from
/// it.  The other side of the merges (sets of more than 24 rows) is released when this leaves scope, a comparator that throws included.
struct RowsTemp {
  void *p;
  explicit RowsTemp(size_t bytes) : p(bytes ? ::operator new(bytes) : nullptr) {}
  ~RowsTemp() { ::operator delete(p); }
};
template <class Row, class Less> void sortRows(const Row *src, Row *dst, size_t n, Less less) {
  static_assert(plainData<Row>, "rows are moved by copy");
  RowsTemp temp(n > 24 ? n * sizeof(Row) : 0);
  auto call = [](void *c, const void *a, const void *b) -> int32_t { return (*static_cast<Less *>(c))(*static_cast<const Row *>(a), *static_cast<const Row *>(b)); };
  mlnix_rows_sort(src, dst, temp.p, int64_t(n), sizeof(Row), call, &less);
}
template <class Row, class Less> void sortRows(Row *rows, size_t n, Less less) { sortRows(static_cast<const Row *>(rows), rows, n, less); }
/// sortRows in place by the leading uint32_t key, ascending: the comparison is made where the rows are, no call back.
template <class Row> void sortRowsByKey(Row *rows, size_t n) {
  static_assert(keyedRow<Row>);
  RowsTemp temp(n > 24 ? n * sizeof(Row) : 0);
  mlnix_rows_sort_u32(rows, rows, temp.p, int64_t(n), sizeof(Row));
}

/// Rows sorted by key, the first of each run of equal keys kept: the rows left, packed at the front.
template <class Row> size_t uniqueFirst(Row *rows, size_t n) { static_assert(keyedRow<Row>); return size_t(mlnix_rows_unique_first(rows, sizeof(Row), int64_t(n))); }

/// The union of two runs sorted by key, `y` winning on an equal key: how many rows it has, then the rows themselves, written into room for
/// nx + ny rows.  When `y` is a sixteenth of `x` or less (an override over a large set), each of its rows is searched for in `x` and the run
/// of `x` before it copied whole: |y| log |x|, not |x| + |y|.
template <class Row> size_t unionSize(const Row *x, size_t nx, const Row *y, size_t ny) {
  static_assert(keyedRow<Row>);
  return size_t(mlnix_rows_union_size(x, sizeof(Row), int64_t(nx), y, int64_t(ny)));
}
template <class Row> size_t unionInto(const Row *x, size_t nx, const Row *y, size_t ny, Row *out) {
  static_assert(keyedRow<Row>);
  return size_t(mlnix_rows_union_into(x, sizeof(Row), int64_t(nx), y, int64_t(ny), out));
}

} // namespace composite

#endif
