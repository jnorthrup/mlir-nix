#pragma once

// The O(1) table whose buckets are ordering clusters (docs/BTRFS-COMPRESSOR.md, "the sea-of-nodes client").
//
// A bucket is a Cluster: a min-max heap and its loose pegs, 23 rows in 384 B.  A full bucket says so (insert returns 2)
// and the row reroutes to its bucket one level down, where the bucket count halves -- the funnel of Krapivin's table.
// The pegs are the cure for the collision tail: a bucket absorbs a burst past its heap without a probe sequence, so a
// key lands in the first bucket that had room.  With no deletes a full bucket stays full, so a lookup that reaches a
// bucket with room and does not find the key there has proved the key absent; that early exit bounds the probe count.
// Each bucket drains in key order, so the table is also the dense sort's unit.
//
// Nothing here is btrfs: a bucket holds any Row with `<` and `==`, and the hash is a parameter.
//
// Levels are Series views over storage the caller owns; nothing here allocates.

#include "Composite/MinMaxHeap.h"
#include "Composite/Series.h"

namespace composite {

/// The mix of a row's key words: the default hash of a Funnel, for any Row exposing `lo` and `hi` words.  A row of another
/// shape passes its own functor `uint64_t(const Row &)`; the table needs only `<`, `==` and this.
struct WordHash {
  template <class Row> constexpr uint64_t operator()(const Row &r) const { return r.lo ^ (uint64_t(r.hi) << 32 | r.hi); }
};

template <class Row, unsigned N, unsigned P, unsigned Levels, class Hash = WordHash>
struct Funnel {
  static_assert(Levels >= 1 && Levels <= 16);
  using Bucket = Cluster<Row, N, P>;

  Bucket *cells;
  uint32_t top;  // bucket count of level 0, a power of two >= 2^(Levels-1); level l has top >> l
  uint32_t rows = 0;

  /// Buckets the caller must supply for `top`.
  static constexpr uint32_t cellsFor(uint32_t top) { return 2 * top - (top >> (Levels - 1)); }
  constexpr Funnel(Bucket *cells, uint32_t top) : cells(cells), top(top) {}

  /// Level l as a Series of buckets; the offset of level l is the sum of the levels above it.
  constexpr auto level(uint32_t l) const {
    return series(cells + 2 * (top - (top >> l)), top >> l);
  }

  static constexpr uint64_t mix(uint64_t x) {
    x += 0x9E3779B97F4A7C15ull;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
    return x ^ (x >> 31);
  }
  /// The bucket of `r` at level l: a salted mix, so a collision at one level does not repeat at the next.
  constexpr uint32_t slot(const Row &r, uint32_t l) const {
    return uint32_t(mix(Hash{}(r) ^ (uint64_t(l) * 0xD6E8FEB86659FD93ull))) & ((top >> l) - 1);
  }

  /// Inserts `r` if its key is absent.  Returns the level it landed on, 0xFF if the key was already stored, or 0xFE
  /// when every level's bucket was full (the sea-of-nodes client then falls back to the sparse path).
  constexpr uint32_t put(const Row &r) {
    for (uint32_t l = 0; l < Levels; ++l) {
      auto lv = level(l);
      Bucket &b = lv[slot(r, l)];
      if (b.find(r)) return 0xFF;
      if (b.insert(r) != 2) { ++rows; return l; }
    }
    return 0xFE;
  }

  /// The stored row for the key, or null.  `probes` counts buckets touched.
  constexpr const Row *get(const Row &r, uint32_t *probes = nullptr) const {
    for (uint32_t l = 0; l < Levels; ++l) {
      const Bucket &b = level(l)[slot(r, l)];
      if (probes) ++*probes;
      if (const Row *f = b.find(r)) return f;
      if (!b.full()) return nullptr;  // no deletes: a key past this bucket would have found room here
    }
    return nullptr;
  }
};

}  // namespace composite
