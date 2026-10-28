#pragma once

// The btrfs inode block compressor's ordering cluster (docs/BTRFS-COMPRESSOR.md).
//
// Register math is cheap; memory is the chasm.  A cluster is a block count small
// enough to keep registers and cache lines on tap: 15 rows of 16 B is 240 B,
// under two 128 B lines on the Mac's performance cores, four 64 B lines on
// kali.  The heap is a min-max heap, so the min and the max sit at the edges;
// every swap settles at an edge.  A ring of spare pegs absorbs what an edge
// swap displaces -- the slop cache.  Nothing here allocates; nothing leaves L1.

#include <array>
#include <cstdint>

namespace composite {

/// The 96-bit block index, carried flat so a row is 16 B with no padding.
/// A btrfs disk key is objectid(64) + type(8) + offset(64), 17 B on disk,
/// ordered (objectid, type, offset).  Inside one block window the objectid
/// tail is small, so the index a cluster orders is 96 bits: objectid tail
/// (24) + type (8) in `hi`, the whole offset in `lo`, and a 32-bit payload
/// handle in `val`.  Compare is register math: two loads, two compares, no
/// memory.
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

/// A min-max heap over a fixed array (Atkinson, Sack, Santoro, Strothotte 1986).
/// Even levels are min levels, odd levels are max levels.  The minimum is the
/// root; the maximum is a child of the root -- both edges are O(1) reads, and
/// every removal swaps an edge row with the last row and sifts it down.
template <class Row, unsigned N>
struct MinMaxHeap {
  static_assert((N & (N + 1)) == 0, "N is one less than a power of two (level-clean)");
  std::array<Row, N> a{};
  uint32_t n = 0;

  constexpr uint32_t size() const { return n; }
  constexpr bool full() const { return n == N; }

  constexpr void push(Row r) {
    uint32_t i = n++;
    a[i] = r;
    if (i == 0) return;
    // level(i) = floor(log2(i + 1)); a min level is an even level.
    bool minLevel = ((63 - __builtin_clz(i + 1)) & 1) == 0;
    uint32_t p = (i - 1) / 2;
    if (minLevel ? a[p] < a[i] : a[i] < a[p]) {
      Row t = a[i]; a[i] = a[p]; a[p] = t;  // settle at the parent edge
      minLevel ? upMax(p) : upMin(p);
    } else {
      minLevel ? upMin(i) : upMax(i);
    }
  }

  constexpr Row min() const { return a[0]; }
  constexpr Row max() const {
    if (n == 1) return a[0];
    uint32_t m = 1;
    if (n > 2 && a[1] < a[2]) m = 2;
    return a[m];
  }

  constexpr Row popMin() {
    Row r = a[0];
    a[0] = a[--n];
    if (n > 1) downMin(0);
    return r;
  }
  constexpr Row popMax() {
    if (n == 1) return popMin();
    uint32_t m = 1;
    if (n > 2 && a[1] < a[2]) m = 2;
    Row r = a[m];
    a[m] = a[--n];
    if (m < n) downMax(m);
    return r;
  }

private:
  constexpr void upMin(uint32_t i) {
    while (i >= 3) {
      uint32_t g = (i - 3) / 4;
      if (a[i] < a[g]) { Row t = a[i]; a[i] = a[g]; a[g] = t; i = g; } else break;
    }
  }
  constexpr void upMax(uint32_t i) {
    while (i >= 3) {
      uint32_t g = (i - 3) / 4;
      if (a[g] < a[i]) { Row t = a[i]; a[i] = a[g]; a[g] = t; i = g; } else break;
    }
  }
  constexpr void downMin(uint32_t i) {
    for (;;) {
      uint32_t l = 2 * i + 1;
      if (l >= n) break;
      uint32_t m = l;
      if (l + 1 < n && a[l + 1] < a[m]) m = l + 1;
      for (uint32_t g = 4 * i + 3; g < n && g <= 4 * i + 6; ++g)
        if (a[g] < a[m]) m = g;
      if (!(a[m] < a[i])) break;
      Row t = a[i]; a[i] = a[m]; a[m] = t;
      if (m >= 4 * i + 3) {  // a grandchild: it may exceed its parent
        uint32_t p = (m - 1) / 2;
        if (a[p] < a[m]) { Row u = a[m]; a[m] = a[p]; a[p] = u; }
      }
      i = m;
    }
  }
  constexpr void downMax(uint32_t i) {
    for (;;) {
      uint32_t l = 2 * i + 1;
      if (l >= n) break;
      uint32_t m = l;
      if (l + 1 < n && a[m] < a[l + 1]) m = l + 1;
      for (uint32_t g = 4 * i + 3; g < n && g <= 4 * i + 6; ++g)
        if (a[m] < a[g]) m = g;
      if (!(a[i] < a[m])) break;
      Row t = a[i]; a[i] = a[m]; a[m] = t;
      if (m >= 4 * i + 3) {
        uint32_t p = (m - 1) / 2;
        if (a[m] < a[p]) { Row u = a[m]; a[m] = a[p]; a[p] = u; }
      }
      i = m;
    }
  }
};

/// The slop cache: a fixed ring of spare pegs, mask indexed, that settles edge
/// swaps.  A full heap that takes a row swaps its max edge out to a peg; a row
/// beyond the edge parks on a peg without touching the heap.  Pegs drain back
/// through the cluster, so a pegged row is ordered with the heap's rows, not
/// deferred past them.
template <class Row, unsigned P>
struct Pegs {
  static_assert((P & (P - 1)) == 0, "peg ring is a power of two (mask indexing)");
  std::array<Row, P> a{};
  uint32_t head = 0, cnt = 0;

  constexpr uint32_t size() const { return cnt; }
  constexpr bool full() const { return cnt == P; }
  constexpr void push(Row r) { a[(head + cnt++) & (P - 1)] = r; }

  /// The smallest peg, by a scan of the ring: P is register scale.
  constexpr Row min() const {
    Row r = a[head & (P - 1)];
    for (uint32_t i = 1; i < cnt; ++i) {
      Row c = a[(head + i) & (P - 1)];
      if (c < r) r = c;
    }
    return r;
  }
  constexpr Row popMin() {
    uint32_t m = 0;
    for (uint32_t i = 1; i < cnt; ++i)
      if (a[(head + i) & (P - 1)] < a[(head + m) & (P - 1)]) m = i;
    Row r = a[(head + m) & (P - 1)];
    a[(head + m) & (P - 1)] = a[(head + cnt - 1) & (P - 1)];
    --cnt;
    return r;
  }
};

/// A cluster: the heap and its pegs.  `insert` returns 0 when the heap took the
/// row, 1 when it parked on a peg (the slop path), and 2 when the cluster is
/// full -- the caller reroutes, and in the compressor the sea-of-nodes client
/// sends the row to the next cluster or to the sparing hash table.  A full
/// cluster takes nothing and stays intact.
template <class Row, unsigned N, unsigned P>
struct Cluster {
  MinMaxHeap<Row, N> heap;
  Pegs<Row, P> pegs;

  constexpr uint32_t size() const { return heap.size() + pegs.size(); }
  constexpr bool full() const { return heap.full() && pegs.full(); }

  constexpr uint32_t insert(Row r) {
    if (heap.full() && pegs.full()) return 2;
    if (!heap.full()) { heap.push(r); return 0; }
    if (!(heap.max() < r)) {
      // the new row belongs inside: settle the max edge out to a peg
      pegs.push(heap.popMax());
      heap.push(r);
    } else {
      pegs.push(r);  // beyond the edge: park on a peg, heap untouched
    }
    return 1;
  }

  /// Emits every row in key order: the min edge of the heap and the min peg
  /// race, and the smaller leaves.  The drain of a fill -- no search, one pop
  /// a row, locally dispatched.
  template <class Emit>
  constexpr void drain(Emit &&emit) {
    while (heap.size() && pegs.size()) {
      if (heap.min() < pegs.min()) emit(heap.popMin());
      else emit(pegs.popMin());
    }
    while (heap.size()) emit(heap.popMin());
    while (pegs.size()) emit(pegs.popMin());
  }
};

namespace law {
/// The law of the cluster, held at compile time: a cluster filled out of order
/// and drained emits the same stream a sort of the same rows emits; a full
/// cluster says so and stays intact; and the edges never move more than one
/// row.
constexpr bool clusterSorts() {
  const uint32_t seed[23] = {7, 3, 9, 1, 8, 12, 5, 14, 0, 11, 6, 13, 2, 10, 4,
                             20, 16, 18, 15, 19, 17, 22, 21};
  InodeRow rows[23];
  for (uint32_t i = 0; i < 23; ++i)
    rows[i] = InodeRow::pack(100 + (seed[i] >> 3), uint8_t(1 + (seed[i] & 3)), seed[i] * 11,
                             100, seed[i]);
  Cluster<InodeRow, 15, 8> c;
  for (uint32_t i = 0; i < 23; ++i) c.insert(rows[i]);
  // the 24th row spills: the cluster is full, intact, and says so
  InodeRow extra = InodeRow::pack(999, 1, 0, 100, 999);
  if (c.insert(extra) != 2 || c.size() != 23) return false;
  InodeRow out[23];
  uint32_t k = 0;
  c.drain([&](InodeRow r) { out[k++] = r; });
  if (k != 23 || c.size() != 0) return false;
  // insertion sort of the same rows, as the reference order
  InodeRow ref[23];
  for (uint32_t i = 0; i < 23; ++i) ref[i] = rows[i];
  for (uint32_t i = 1; i < 23; ++i)
    for (uint32_t j = i; j > 0 && ref[j] < ref[j - 1]; --j) {
      InodeRow t = ref[j]; ref[j] = ref[j - 1]; ref[j - 1] = t;
    }
  for (uint32_t i = 0; i < 23; ++i)
    if (!(out[i] == ref[i] && out[i].val == ref[i].val)) return false;
  return true;
}
static_assert(clusterSorts(), "a drained cluster emits the sorted stream, and a full cluster spills");
}  // namespace law

static_assert(sizeof(MinMaxHeap<InodeRow, 15>) <= 2 * 128,
              "the heap keeps two 128 B lines on tap (register and cache line capacity)");
static_assert(sizeof(Pegs<InodeRow, 8>) <= 2 * 128, "the peg ring stays in the lines around the heap");
static_assert(sizeof(Cluster<InodeRow, 15, 8>) <= 4 * 128,
              "a cluster is four 128 B lines: the block count keeps cache line capacity on tap");

}  // namespace composite
