#pragma once

// The btrfs inode block compressor's ordering cluster (docs/BTRFS-COMPRESSOR.md).
//
// Register math is cheap; memory is the chasm.  A cluster is a block count small
// enough to keep registers and cache lines on tap: 15 rows of 16 B is 240 B,
// under two 128 B lines on the Mac's performance cores, four 64 B lines on
// kali.  The heap is a min-max heap, so the min and the max sit at the edges;
// every swap settles at an edge.  A bag of spare pegs absorbs what an edge
// swap displaces -- the slop cache.  Nothing here allocates.  The size bounds
// below cover each unit, not the residency of a whole bucket array in L1.
//
// The algorithms are MLIR (lowered/composite/ClusterOps.mlir, linked into NixStore and TrikeShedRuntime): the heap's
// push/climb/sift and edge pops, the pegs' argMin, the cluster's insert routing, min race, find and drain.  These types
// keep the storage (inline bodies, no heap) and are bridges: a row crosses as sizeof(Row) bytes, its `<` and `==` as
// C callbacks, so any plain-data Row with those operators works.  The laws the C++ held at compile time are checked
// by scripts/minmax-check.cc.

#include "Composite/Folds.h"
#include "Composite/Mutable.h"

namespace composite {

/// The 96-bit block index, carried flat so a row is 16 B with no padding.
/// A btrfs disk key is objectid(64) + type(8) + offset(64), 17 B on disk,
/// ordered (objectid, type, offset).  Inside one block window the objectid
/// tail is small, so the index a cluster orders is 96 bits: objectid tail
/// (24) + type (8) in `hi`, the whole offset in `lo`, and a 32-bit payload
/// handle in `val`.  The caller must keep objectid in [base, base + 2^24).
/// Comparison uses the packed words, with no pointer lookup.
struct InodeRow {
  uint64_t lo;   // offset
  uint32_t hi;   // (objectid - window base) << 8 | type
  uint32_t val;  // payload handle

  /// Pack a disk key into the window's 96-bit address space.
  static constexpr InodeRow pack(uint64_t objectid, uint8_t type, uint64_t offset,
                                 uint64_t base, uint32_t payload) {
    return InodeRow{offset, uint32_t(((objectid - base) << 8) | type), payload};
  }

  friend constexpr bool operator<(const InodeRow &a, const InodeRow &b) {
    return a.hi != b.hi ? a.hi < b.hi : a.lo < b.lo;
  }
  friend constexpr bool operator==(const InodeRow &a, const InodeRow &b) {
    return a.hi == b.hi && a.lo == b.lo;
  }
};
static_assert(sizeof(InodeRow) == 16);

// ClusterOps.mlir's entries: rows are rs-byte cells, `n` the u32 count of an Inline body, less/eq a Row's operators.
extern "C" {
using MmxCmp = int (*)(const void *, const void *);
using MmxEmit = void (*)(void *, const void *);
void mmx_heap_push(void *cells, uint32_t *n, uint64_t rs, MmxCmp less, const void *row);
void mmx_heap_pop_min(void *cells, uint32_t *n, uint64_t rs, MmxCmp less, void *out);
void mmx_heap_pop_max(void *cells, uint32_t *n, uint64_t rs, MmxCmp less, void *out);
uint32_t mmx_max_at(const void *cells, uint32_t n, uint64_t rs, MmxCmp less);
uint32_t mmx_arg_min(const void *cells, uint32_t n, uint64_t rs, MmxCmp less);
void mmx_peg_pop(void *cells, uint32_t *n, uint64_t rs, MmxCmp less, void *out);
uint32_t mmx_cluster_insert(void *heap, uint32_t *hn, uint32_t capN, void *pegs, uint32_t *pn, uint32_t capP, uint64_t rs, MmxCmp less,
                            const void *row);
void mmx_cluster_min(const void *heap, uint32_t hn, const void *pegs, uint32_t pn, uint64_t rs, MmxCmp less, void *out);
void mmx_cluster_pop_min(void *heap, uint32_t *hn, void *pegs, uint32_t *pn, uint64_t rs, MmxCmp less, void *out);
const void *mmx_cluster_find(const void *heap, uint32_t hn, const void *pegs, uint32_t pn, uint64_t rs, MmxCmp less, MmxCmp eq,
                             const void *row);
void mmx_cluster_drain(void *heap, uint32_t *hn, void *pegs, uint32_t *pn, uint64_t rs, MmxCmp less, void *ctx, MmxEmit emit);
void mmx_order(void *heap, uint32_t *hn, uint32_t capN, void *pegs, uint32_t *pn, uint32_t capP, uint64_t rs, MmxCmp less,
               const void *rows, uint32_t n, void *ctx, MmxEmit emit);
}
template <class Row> int mmxLess(const void *x, const void *y) { return *static_cast<const Row *>(x) < *static_cast<const Row *>(y); }
template <class Row> int mmxEq(const void *x, const void *y) { return *static_cast<const Row *>(x) == *static_cast<const Row *>(y); }
/// emit(row) as a C callback over the functor ctx points at (F: its pointer type).
template <class Row, class F> void mmxEmit(void *ctx, const void *row) { (*static_cast<F>(ctx))(*static_cast<const Row *>(row)); }

/// A min-max heap over a fixed array (Atkinson, Sack, Santoro, Strothotte 1986).
/// Even levels are min levels, odd levels are max levels.  The minimum is the
/// root; the maximum is a child of the root -- both edges are O(1) reads, and
/// every removal swaps an edge row with the last row and sifts it down.
/// The caller must not push when full or read/pop when empty.
template <class Row, unsigned N>
struct MinMaxHeap {
  static_assert((N & (N + 1)) == 0 && N <= 256, "N is one less than a power of two, at most 255 (the sift walks the index table of 256)");
  static_assert(plainData<Row> && (sizeof(Row) % 8 != 0 || alignof(Row) >= 8),
                "a row crosses into ClusterOps.mlir as its bytes, 8-aligned when it is whole words (the word lane)");
  MutableSeries<Row, Inline<Row, N>> a;  // the rows in heap order: an inline body, no heap

  constexpr uint32_t size() const { return a.size(); }
  constexpr bool full() const { return a.size() == N; }
  /// The rows in heap order, as a Series.
  constexpr auto rows() const { return series(a.data(), a.size()); }

  void push(Row r) {
    if (full()) TODO("append past the capacity of a fixed body");
    mmx_heap_push(a.cells, &a.n, sizeof(Row), mmxLess<Row>, &r);
  }
  constexpr Row min() const { return a[0]; }
  Row max() const { return a[mmx_max_at(a.cells, a.n, sizeof(Row), mmxLess<Row>)]; }
  Row popMin() { Row r; mmx_heap_pop_min(a.cells, &a.n, sizeof(Row), mmxLess<Row>, &r); return r; }
  Row popMax() { Row r; mmx_heap_pop_max(a.cells, &a.n, sizeof(Row), mmxLess<Row>, &r); return r; }
};

/// The slop cache: a fixed bag of spare pegs that settles edge swaps.  A full heap that takes a row swaps its max edge out to
/// a peg; a row beyond the edge parks on a peg without touching the heap.  Pegs drain back through the cluster, so a pegged row
/// is ordered with the heap's rows, not deferred past them.  A bag, not a ring: a removal fills its hole with the last peg, so
/// the cells are always 0..cnt and nothing is indexed through a head or a mask.
template <class Row, unsigned P>
struct Pegs {
  MutableSeries<Row, Inline<Row, P>> bag;

  constexpr uint32_t size() const { return bag.size(); }
  constexpr bool full() const { return bag.size() == P; }
  constexpr void push(Row r) { bag.append(r); }
  /// The pegs, as a Series over the cells.
  constexpr auto rows() const { return series(bag.data(), bag.size()); }

  /// The smallest peg (the first of equals): P is register scale, so this is an argMin over the cells.
  uint32_t least() const { return mmx_arg_min(bag.cells, bag.n, sizeof(Row), mmxLess<Row>); }
  Row min() const { return bag[least()]; }
  Row popMin() { Row r; mmx_peg_pop(bag.cells, &bag.n, sizeof(Row), mmxLess<Row>, &r); return r; }
};

/// A cluster: the heap and its pegs.  `insert` returns 0 when the heap took the
/// row, 1 when it parked on a peg (the slop path), and 2 when the cluster is
/// full -- the caller reroutes, and in the compressor the sea-of-nodes client
/// sends the row to the next cluster or to the sparing hash table.  A full
/// cluster takes nothing and stays intact.  `min`/`popMin` race the heap's min
/// edge against the least peg; `find` skips the heap for a key outside its
/// [min, max] edges and always searches the pegs; `drain` emits every row in
/// key order, one popMin a row.
template <class Row, unsigned N, unsigned P>
struct Cluster {
  static_assert(N + P <= 256, "a cluster's rows index the table of 256 (its drain and its pegs' argMin)");
  MinMaxHeap<Row, N> heap;
  Pegs<Row, P> pegs;

  constexpr uint32_t size() const { return heap.size() + pegs.size(); }
  constexpr bool full() const { return heap.full() && pegs.full(); }

  Row min() const { Row r; mmx_cluster_min(heap.a.cells, heap.a.n, pegs.bag.cells, pegs.bag.n, sizeof(Row), mmxLess<Row>, &r); return r; }
  Row popMin() { Row r; mmx_cluster_pop_min(heap.a.cells, &heap.a.n, pegs.bag.cells, &pegs.bag.n, sizeof(Row), mmxLess<Row>, &r); return r; }
  uint32_t insert(Row r) {
    return mmx_cluster_insert(heap.a.cells, &heap.a.n, N, pegs.bag.cells, &pegs.bag.n, P, sizeof(Row), mmxLess<Row>, &r);
  }
  /// The stored row equal to `r`, or null.
  const Row *find(const Row &r) const {
    return static_cast<const Row *>(
        mmx_cluster_find(heap.a.cells, heap.a.n, pegs.bag.cells, pegs.bag.n, sizeof(Row), mmxLess<Row>, mmxEq<Row>, &r));
  }
  template <class Emit> void drain(Emit &&emit) {
    mmx_cluster_drain(heap.a.cells, &heap.a.n, pegs.bag.cells, &pegs.bag.n, sizeof(Row), mmxLess<Row>, (void *)&emit,
                      mmxEmit<Row, decltype(&emit)>);
  }
};

/// Stable permutation of one cluster. Read the whole input before any output,
/// so the caller can reuse its key buffer for the permutation.  A row is (key, index), ordered by key then index: the
/// order ClusterOps.mlir builds in when it is handed no `<` (a null callback), so no comparison leaves the MLIR.
template <class Keys, class Emit>
bool clusterOrder(const Keys &keys, Emit emit) {
  if (uint64_t(keys.size()) > 23) return false;
  struct Row { int64_t key; uint32_t index; };
  Row rows[23];
  fold(iota(uint32_t(keys.size())), 0u, [&](uint32_t, uint32_t i) { rows[i] = {int64_t(keys[i]), i}; return 0u; });
  Cluster<Row, 15, 8> c;
  auto out = [&](const Row &r) { emit(r.index); };
  mmx_order(c.heap.a.cells, &c.heap.a.n, 15, c.pegs.bag.cells, &c.pegs.bag.n, 8, sizeof(Row), nullptr, rows, uint32_t(keys.size()), &out,
            mmxEmit<Row, decltype(&out)>);
  return true;
}

static_assert(sizeof(MinMaxHeap<InodeRow, 15>) <= 2 * 128,
              "the heap keeps two 128 B lines on tap (register and cache line capacity)");
static_assert(sizeof(Pegs<InodeRow, 8>) <= 2 * 128, "the peg bag stays in the lines around the heap");
static_assert(sizeof(Cluster<InodeRow, 15, 8>) <= 4 * 128,
              "a cluster is four 128 B lines: the block count keeps cache line capacity on tap");

}  // namespace composite
