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

#include "Composite/Folds.h"
#include "Composite/Mutable.h"

// COMPOSITE_PEDANTIC selects how the kernels below are written; the algorithm, its comparisons and its output are the same.
//   1  pedantic: every walk is a transform over a Series (fold, foldN, argMin, vec<N>): PRELOAD's form, no loop written.
//   0  pragmatic: the plain loop each of those transforms replaces, for the optimizer that does better with a loop.
// The default is pedantic: on Kali (docs/OPTIMIZER-LADDER.md) clang -O3 runs it fastest and g++ runs it faster than the pragmatic form on
// every row; pragmatic is the escape hatch (it measured better under clang -O2 and ThinLTO).  -DCOMPOSITE_PEDANTIC=0|1 overrides it.
// Both are checked by scripts/minmax-check.cc and funnel-check.cc, and compared by scripts/optimizer-ladder.sh.
#ifndef COMPOSITE_PEDANTIC
#define COMPOSITE_PEDANTIC 1
#endif

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

/// A min-max heap over a fixed array (Atkinson, Sack, Santoro, Strothotte 1986).
/// Even levels are min levels, odd levels are max levels.  The minimum is the
/// root; the maximum is a child of the root -- both edges are O(1) reads, and
/// every removal swaps an edge row with the last row and sifts it down.
/// The caller must not push when full or read/pop when empty.
/// No loop is written here: a sift is a fold over the levels with a (position, live) state, and a scan is a transform.
template <class Row, unsigned N>
struct MinMaxHeap {
  static_assert((N & (N + 1)) == 0, "N is one less than a power of two (level-clean)");
  static constexpr uint32_t kLevels = (N ? 32 - __builtin_clz(N) : 0);
  MutableSeries<Row, Inline<Row, N>> a;  // the rows in heap order: an inline body, no heap

  constexpr uint32_t size() const { return a.size(); }
  constexpr bool full() const { return a.size() == N; }
  /// The rows in heap order, as a Series.
  constexpr auto rows() const { return series(a.data(), a.size()); }

  constexpr void push(Row r) {
    uint32_t i = a.append(r);
    if (i == 0) return;
    // level(i) = floor(log2(i + 1)); a min level is an even level.
    bool minLevel = ((31 - __builtin_clz(i + 1)) & 1) == 0;
    uint32_t p = (i - 1) / 2;
    if (minLevel ? a[p] < a[i] : a[i] < a[p]) {
      swap(i, p);  // settle at the parent edge
      minLevel ? climb(p, kMaxFirst) : climb(p, kMinFirst);
    } else {
      minLevel ? climb(i, kMinFirst) : climb(i, kMaxFirst);
    }
  }

  constexpr Row min() const { return a[0]; }
  constexpr Row max() const { return a[maxAt()]; }

  constexpr Row popMin() {
    Row r = a[0];
    a[0] = a[a.size() - 1];
    a.pop();
    if (a.size() > 1) sift(0, kMinFirst);
    return r;
  }
  constexpr Row popMax() {
    if (a.size() == 1) return popMin();
    uint32_t m = maxAt();
    Row r = a[m];
    a[m] = a[a.size() - 1];
    a.pop();
    if (m < a.size()) sift(m, kMaxFirst);
    return r;
  }

private:
  /// before(x, y): x belongs nearer the edge than y.  Min levels put the smaller first, max levels the larger.
  static constexpr auto kMinFirst = [](const Row &x, const Row &y) { return x < y; };
  static constexpr auto kMaxFirst = [](const Row &x, const Row &y) { return y < x; };
  struct Walk { uint32_t i; bool live; };

  constexpr void swap(uint32_t x, uint32_t y) { Row t = a[x]; a[x] = a[y]; a[y] = t; }
  constexpr uint32_t maxAt() const { return a.size() == 1 ? 0u : a.size() > 2 && a[1] < a[2] ? 2u : 1u; }

  /// Grandparent walk upward: while the row is nearer the edge than its grandparent, swap with it.  kLevels is a constant,
  /// so the walk is straight-line code.
  template <class B> constexpr void climb(uint32_t from, B before) {
#if COMPOSITE_PEDANTIC
    foldN<kLevels>(Walk{from, true}, [&](Walk w, uint32_t) __attribute__((always_inline)) -> Walk {
      if (!w.live || w.i < 3) return Walk{w.i, false};
      uint32_t g = (w.i - 3) / 4;
      if (!before(a[w.i], a[g])) return Walk{w.i, false};
      swap(w.i, g);
      return Walk{g, true};
    });
#else
    for (uint32_t i = from; i >= 3;) {
      uint32_t g = (i - 3) / 4;
      if (!before(a[i], a[g])) break;
      swap(i, g);
      i = g;
    }
#endif
  }

  /// Walk downward: the nearest-the-edge of children and grandchildren replaces the row if it is nearer the edge.  Stop
  /// after a child swap (the child is on the opposite level); after a grandchild swap, repair against its parent and go on.
  /// The candidates are the constant vec<6>: two children, then four grandchildren, in index order.
  template <class B> constexpr void sift(uint32_t from, B before) {
    const uint32_t n = a.size();
#if !COMPOSITE_PEDANTIC
    for (uint32_t i = from;;) {
      uint32_t l = 2 * i + 1;
      if (l >= n) break;
      uint32_t m = l;
      if (l + 1 < n && before(a[l + 1], a[m])) m = l + 1;
      for (uint32_t g = 4 * i + 3; g < n && g <= 4 * i + 6; ++g)
        if (before(a[g], a[m])) m = g;
      if (!before(a[m], a[i])) break;
      swap(i, m);
      if (m < 4 * i + 3) break;  // a child is on the opposite level: stop here
      uint32_t p = (m - 1) / 2;
      if (before(a[p], a[m])) swap(m, p);
      i = m;
    }
#else
    foldN<kLevels>(Walk{from, true}, [&](Walk w, uint32_t) __attribute__((always_inline)) -> Walk {
      uint32_t i = w.i, l = 2 * i + 1;
      if (!w.live || l >= n) return Walk{i, false};
      auto kin = vec<6>([&](uint32_t k) __attribute__((always_inline)) { return k < 2 ? l + k : 4 * i + 1 + k; });
      uint32_t m = foldN<5>(l, [&](uint32_t best, uint32_t k) __attribute__((always_inline)) -> uint32_t {
        uint32_t x = kin[k + 1];
        return x < n && before(a[x], a[best]) ? x : best;
      });
      if (!before(a[m], a[i])) return Walk{i, false};
      swap(i, m);
      if (m < 4 * i + 3) return Walk{m, false};
      uint32_t p = (m - 1) / 2;
      if (before(a[p], a[m])) swap(m, p);
      return Walk{m, true};
    });
#endif
  }
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

  /// The smallest peg: P is register scale, so this is an argMin over the cells.
  constexpr uint32_t least() const {
#if COMPOSITE_PEDANTIC
    return argMin(rows(), [](const Row &x, const Row &y) { return x < y; });
#else
    uint32_t m = 0;
    for (uint32_t i = 1; i < bag.size(); ++i) if (bag[i] < bag[m]) m = i;
    return m;
#endif
  }
  constexpr Row min() const { return bag[least()]; }
  constexpr Row popMin() {
    uint32_t m = least();
    Row r = bag[m];
    bag.removeSwap(m);
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

  constexpr Row min() const {
    return !heap.size() ? pegs.min() : !pegs.size() || heap.min() < pegs.min() ? heap.min() : pegs.min();
  }
  constexpr Row popMin() {
    return !heap.size() ? pegs.popMin() : !pegs.size() || heap.min() < pegs.min() ? heap.popMin() : pegs.popMin();
  }

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

  /// The stored row equal to `r`, or null.  The heap's edges are O(1) reads, so a key outside [min, max] skips the heap
  /// search; the pegs are unordered and always searched.  Both are firstWhere over a Series.
  constexpr const Row *find(const Row &r) const {
    auto is = [&](const Row &c) { return c == r; };
    if (heap.size() && !(r < heap.min()) && !(heap.max() < r)) {
      uint32_t k = firstWhere(heap.rows(), is);
      if (k < heap.size()) return &heap.a[k];
    }
    uint32_t k = firstWhere(pegs.rows(), is);
    return k < pegs.size() ? &pegs.bag[k] : nullptr;
  }

  /// Emits every row in key order: the min edge of the heap and the min peg
  /// race, and the smaller leaves.  The drain of a fill -- no search, one pop
  /// a row, locally dispatched.  A fold over as many steps as there are rows.
  template <class Emit>
  constexpr void drain(Emit &&emit) {
#if COMPOSITE_PEDANTIC
    fold(iota(size()), 0u, [&](uint32_t done, uint32_t) { emit(popMin()); return done + 1; });
#else
    while (size()) emit(popMin());
#endif
  }
};

/// Stable permutation of one cluster. Read the whole input before any output,
/// so the caller can reuse its key buffer for the permutation.
template <class Keys, class Emit>
constexpr bool clusterOrder(const Keys &keys, Emit emit) {
  if (uint64_t(keys.size()) > 23) return false;
  struct Row {
    int64_t key;
    uint32_t index;
    constexpr bool operator<(const Row &r) const { return key != r.key ? key < r.key : index < r.index; }
  };
  Cluster<Row, 15, 8> c;
  fold(iota(uint32_t(keys.size())), 0u, [&](uint32_t, uint32_t i) { c.insert({int64_t(keys[i]), i}); return 0u; });
  c.drain([&](Row r) { emit(r.index); });
  return true;
}

namespace law {
constexpr bool mixedEdges() {
  constexpr int input[] = {0, 0, 1, 0, 0, 0, 1}, expected[] = {0, 1, 0, 1, 0, 0, 0};
  auto run = [&](uint32_t reverse) {
    MinMaxHeap<int, 7> h;
    fold(series(input, 7), 0, [&](int, int x) { h.push(reverse ? -x : x); return 0; });
    return fold(iota(7), true, [&](bool ok, uint32_t i) {
      int x = ((i & 1) != reverse) ? h.popMax() : h.popMin();
      return ok && x == (reverse ? -expected[i] : expected[i]);
    });
  };
  return run(0) && run(1);
}
static_assert(mixedEdges(), "equal child/grandchild keys preserve both heap edges");

/// The law of the cluster, held at compile time: a cluster filled out of order
/// and drained emits the same stream a sort of the same rows emits; a full
/// cluster says so and stays intact.
constexpr bool clusterSorts() {
  constexpr uint32_t seed[23] = {7, 3, 9, 1, 8, 12, 5, 14, 0, 11, 6, 13, 2, 10, 4,
                                 20, 16, 18, 15, 19, 17, 22, 21};
  auto rowOf = [&](uint32_t i) { return InodeRow::pack(100 + (seed[i] >> 3), uint8_t(1 + (seed[i] & 3)), seed[i] * 11, 100, seed[i]); };
  Cluster<InodeRow, 15, 8> c;
  fold(iota(23), 0u, [&](uint32_t, uint32_t i) { c.insert(rowOf(i)); return 0u; });
  // the 24th row spills: the cluster is full, intact, and says so
  if (c.insert(InodeRow::pack(999, 1, 0, 100, 999)) != 2 || c.size() != 23) return false;
  // the drained stream must equal the sorted order: row k of the drain is the row of rank k
  struct Out { uint32_t k; bool ok; };
  Out out = {0, true};
  c.drain([&](InodeRow r) {
    uint32_t rank = fold(iota(23), 0u, [&](uint32_t below, uint32_t i) { return below + (rowOf(i) < r ? 1u : 0u); });
    out = Out{out.k + 1, out.ok && rank == out.k};
  });
  return out.k == 23 && out.ok && c.size() == 0;
}
static_assert(clusterSorts(), "a drained cluster emits the sorted stream, and a full cluster spills");
}  // namespace law

static_assert(sizeof(MinMaxHeap<InodeRow, 15>) <= 2 * 128,
              "the heap keeps two 128 B lines on tap (register and cache line capacity)");
static_assert(sizeof(Pegs<InodeRow, 8>) <= 2 * 128, "the peg bag stays in the lines around the heap");
static_assert(sizeof(Cluster<InodeRow, 15, 8>) <= 4 * 128,
              "a cluster is four 128 B lines: the block count keeps cache line capacity on tap");

}  // namespace composite
