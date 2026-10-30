//===- Table.h - values found by a word: open addressing over cells that hold the key beside the value ---===//
//
// What llvm::DenseMap and std::unordered_map over a pointer or an id were used for, in the pure zone.  One probe reads one cell, the key
// and its value side by side, and the cells are a power of two, doubled at half load, so a lookup is a mix, a mask and one or two probes:
// the table for a hot lookup by word.  (Krapivin's funnel, Funnel.h, scans a bucket of rows and keeps them in order: the table for a run
// that is drained in key order.  Patricia.h is the table for byte strings.)  The key 0 marks an empty cell, so it is never a key: a table
// by pointer has none, and one by hash maps 0 to 1.  Nothing is removed.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_TABLE_H
#define COMPOSITE_TABLE_H

#include "Composite/Core.h"

namespace composite {

template <class V> struct WordTable {
  static_assert(plainData<V>, "cells are copied when the table grows");
  struct Cell {
    uint64_t k;
    V v;
  };

  WordTable() = default;
  WordTable(const WordTable &) = delete;
  WordTable &operator=(const WordTable &) = delete;
  ~WordTable() { ::operator delete(cells); }

  uint32_t size() const { return n; }
  /// The value stored for k, or null.  Its address holds until the next insert.
  V *find(uint64_t k) const {
    if (!cells) return nullptr;
    for (uint64_t i = mix(k) & mask;; i = (i + 1) & mask) {
      if (cells[i].k == k) return &cells[i].v;
      if (cells[i].k == 0) return nullptr;
    }
  }
  /// The value stored for k, made V() first when there is none.
  V &at(uint64_t k) {
    if (V *v = find(k)) return *v;
    return place(k, V());
  }
  /// Stores v for k unless k is there: false when it was.
  bool insert(uint64_t k, V v) {
    if (find(k)) return false;
    place(k, v);
    return true;
  }
  /// Each (key, value), in no order.
  template <class F> void each(F f) const {
    for (uint64_t i = 0; cells && i <= mask; i++)
      if (cells[i].k) f(cells[i].k, cells[i].v);
  }

private:
  static uint64_t mix(uint64_t x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdull;
    x ^= x >> 33;
    return x;
  }
  V &place(uint64_t k, V v) {
    if (2 * (n + 1) > capacity()) grow();
    uint64_t i = mix(k) & mask;
    while (cells[i].k) i = (i + 1) & mask;
    cells[i].k = k;
    cells[i].v = v;
    n++;
    return cells[i].v;
  }
  uint64_t capacity() const { return cells ? mask + 1 : 0; }
  void grow() {
    uint64_t nc = cells ? 2 * (mask + 1) : 16;
    Cell *q = static_cast<Cell *>(::operator new(nc * sizeof(Cell)));
    for (uint64_t i = 0; i < nc; i++) q[i].k = 0;
    for (uint64_t i = 0; cells && i <= mask; i++)
      if (cells[i].k) {
        uint64_t j = mix(cells[i].k) & (nc - 1);
        while (q[j].k) j = (j + 1) & (nc - 1);
        q[j] = cells[i];
      }
    ::operator delete(cells);
    cells = q;
    mask = nc - 1;
  }
  Cell *cells = nullptr;
  uint64_t mask = 0;
  uint32_t n = 0;
};

} // namespace composite

#endif // COMPOSITE_TABLE_H
