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

#include "Composite/Funnel.h"
#include "Composite/Mutable.h"

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
  /// Every cell empty again; the cells stay (a scratch table cleared for each block it indexes).
  void clear() {
    for (uint64_t i = 0; cells && i <= mask; i++) cells[i].k = 0;
    n = 0;
  }
  /// The filled cells, in no order: `for (auto &c : table)` reads c.k and c.v.
  struct Iter {
    Cell *c, *e;
    void skip() {
      while (c != e && !c->k) ++c;
    }
    Cell &operator*() const { return *c; }
    Iter &operator++() {
      ++c;
      skip();
      return *this;
    }
    bool operator!=(const Iter &o) const { return c != o.c; }
  };
  Iter begin() const {
    Iter i{cells, cells ? cells + mask + 1 : cells};
    i.skip();
    return i;
  }
  Iter end() const {
    Cell *e = cells ? cells + mask + 1 : cells;
    return {e, e};
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

/// Bytes copied where they never move: blocks from the language's operator new, filled from the front, never freed while the Bump lives
/// (the names of a symbol table, the keys of a table by bytes).  A copy is NUL-terminated.
struct Bump {
  Bump() = default;
  Bump(const Bump &) = delete;
  Bump &operator=(const Bump &) = delete;
  ~Bump() {
    for (char *b : blocks) ::operator delete(b);
  }
  const char *copy(const char *p, uint32_t n) {
    if (uint64_t(end - cur) < uint64_t(n) + 1) {
      uint64_t size = n + 1 > kBlock / 4 ? uint64_t(n) + 1 : kBlock; // a long string gets a block of its own
      char *b = static_cast<char *>(::operator new(size));
      blocks.append(b);
      if (size == kBlock) cur = b, end = b + size;
      else { __builtin_memcpy(b, p, n); b[n] = 0; return b; }
    }
    char *r = cur;
    __builtin_memcpy(r, p, n);
    r[n] = 0;
    cur += n + 1;
    return r;
  }

private:
  static constexpr uint64_t kBlock = 64 * 1024;
  MutableSeries<char *> blocks;
  char *cur = nullptr, *end = nullptr;
};

/// Values found by bytes, fast (a name, a pattern and its input): a WordTable by the bytes' hash, the bytes kept with the value where they
/// outlive the table so a hit is checked against them, one probe and one compare.  Two byte strings of one hash (none yet seen) share a
/// spill.  Patricia keys by bytes too, in order and by prefix; this one is for a hot lookup, where order is not asked.
template <class V> struct TextTable {
  struct Row {
    const char *p;
    uint32_t n;
    V v;
  };
  uint32_t size() const { return rows.size(); }
  bool empty() const { return rows.empty(); }
  const Row &row(uint32_t i) const { return rows[i]; }
  /// The rows in the order they were made: `for (auto &r : table)` reads r.p, r.n and r.v.
  Row *begin() { return rows.data(); }
  Row *end() { return rows.data() + rows.size(); }
  const Row *begin() const { return rows.data(); }
  const Row *end() const { return rows.data() + rows.size(); }
  /// The value stored for the bytes, or null.  Its address holds until the next set.
  V *find(const char *p, uint32_t n) {
    uint32_t i = indexOf(p, n);
    return i == kNone ? nullptr : &rows[i].v;
  }
  const V *find(const char *p, uint32_t n) const {
    uint32_t i = indexOf(p, n);
    return i == kNone ? nullptr : &rows[i].v;
  }
  /// The bytes now stand for v; `copy()` makes the bytes where they outlive the table, called only for bytes not stored yet.
  template <class Copy> V *set(const char *p, uint32_t n, V v, Copy copy) {
    if (V *old = find(p, n)) {
      *old = v;
      return old;
    }
    return &rows[make(p, n, v, copy)].v;
  }
  /// The value stored for the bytes, made V() first when there is none (a count to add to).
  template <class Copy> V &at(const char *p, uint32_t n, Copy copy) {
    if (V *old = find(p, n)) return *old;
    return rows[make(p, n, V(), copy)].v;
  }

private:
  static constexpr uint32_t kNone = ~0u;
  uint32_t indexOf(const char *p, uint32_t n) const {
    if (const uint32_t *i = byHash.find(key(p, n))) {
      if (same(rows[*i], p, n)) return *i;
      for (uint32_t j : spill)
        if (same(rows[j], p, n)) return j;
    }
    return kNone;
  }
  template <class Copy> uint32_t make(const char *p, uint32_t n, V v, Copy copy) {
    uint32_t i = rows.append(Row{copy(), n, v});
    if (!byHash.insert(key(p, n), i)) spill.append(i);
    return i;
  }
  static uint64_t key(const char *p, uint32_t n) {
    uint64_t h = hashBytes(p, n);
    return h ? h : 1;
  }
  static bool same(const Row &r, const char *p, uint32_t n) { return r.n == n && (!n || __builtin_memcmp(r.p, p, n) == 0); }
  WordTable<uint32_t> byHash;
  MutableSeries<Row> rows;
  MutableSeries<uint32_t> spill;
};

} // namespace composite

#endif // COMPOSITE_TABLE_H
