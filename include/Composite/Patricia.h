//===- Patricia.h - rows found by a byte string: the crit-bit trie of the pure zone ---===//
//
// Paths share long prefixes, so a row found by its path is kept in a crit-bit (Patricia) trie.  An inner node is the one bit at which the
// keys under it first differ: a lookup tests one bit a node on its way down and compares the key once, at the leaf it reaches.  There is no
// hash and no key read twice, the rows are in byte order, and the keys under a prefix are one subtree.  Nodes and rows are series addressed
// by index, so an insert that grows them moves nothing anyone holds.
//
// A key is read as if a 0 byte followed it.  Keys hold no 0 byte (paths do not), so no key is another's prefix in the trie's eyes.
//
// The algorithms (the leaf walk, the key compare, set's crit-bit plan and link, prefix's descent and byte-order walk) are lowered MLIR,
// lowered/nixstore/Patricia.mlir, over the arrays where they lie.  This bridge keeps what is generic in V: the storage, the value, copy, emit.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_PATRICIA_H
#define COMPOSITE_PATRICIA_H

#include "Composite/Mutable.h"

namespace composite {

extern "C" {
uint32_t mlnix_patricia_find(const void *nodes, const void *rows, size_t rs, uint32_t root, const char *k, uint32_t n);
uint32_t mlnix_patricia_set(const void *nodes, const void *rows, size_t rs, uint32_t root, const char *k, uint32_t n, uint32_t *plan);
uint32_t mlnix_patricia_link(void *nodes, uint32_t ni, uint32_t root, uint32_t ri, const uint32_t *plan);
uint32_t mlnix_patricia_prefix(const void *nodes, const void *rows, size_t rs, uint32_t root, const char *k, uint32_t n, uint32_t *stack,
                               uint32_t *out);
}

template <class V> struct Patricia {
  struct Row {
    const char *key; // outlives the trie: an arena copy, or a literal
    uint32_t len;
    V v;
  };

  uint32_t size() const { return rows.size(); }
  bool empty() const { return rows.empty(); }

  /// The value stored for the key, or null.
  V *find(const char *k, uint32_t n) { return const_cast<V *>(static_cast<const Patricia &>(*this).find(k, n)); }
  const V *find(const char *k, uint32_t n) const {
    if (rows.empty()) return nullptr;
    uint32_t bi = mlnix_patricia_find(nodes.data(), rows.data(), sizeof(Row), root, k, n);
    return bi == kNone ? nullptr : &rows[bi].v;
  }
  /// Every row, in byte order: `emit(const Row &)`.
  template <class Emit> void each(Emit &&emit) const { prefix("", 0, emit); }

  /// The key now stands for v.  `copy()` makes the key's bytes where they outlive the trie; it is called only for a key not stored yet.
  /// The value's address holds until the next set.
  template <class Copy> V *set(const char *k, uint32_t n, V v, Copy copy) {
    if (rows.empty()) {
      rows.append(Row{copy(), n, v});
      root = kLeaf;
      return &rows[0].v;
    }
    uint32_t plan[7]; // the leaf reached, then the new node's byte, other, direction, parent, side and the child it replaces
    if (mlnix_patricia_set(nodes.data(), rows.data(), sizeof(Row), root, k, n, plan) == 0) return &(rows[plan[0]].v = v);
    uint32_t ri = rows.append(Row{copy(), n, v}), ni = nodes.append(Node{});
    root = mlnix_patricia_link(nodes.data(), ni, root, ri, plan);
    return &rows[ri].v;
  }

  /// Each row whose key starts with the prefix, in byte order: `emit(const Row &)`.  The walk is done before the first emit.
  template <class Emit> void prefix(const char *k, uint32_t n, Emit &&emit) const {
    if (rows.empty()) return;
    MutableSeries<uint32_t> cells; // the walk's stack (as deep as the nodes, at most), then the rows found
    cells.reserve(size_t(nodes.size()) + 1 + rows.size());
    uint32_t *found = cells.data() + nodes.size() + 1;
    for (uint32_t i = 0, m = mlnix_patricia_prefix(nodes.data(), rows.data(), sizeof(Row), root, k, n, cells.data(), found); i < m; i++)
      emit(rows[found[i]]);
  }
  struct Node {
    uint32_t child[2]; // a node's index, or a row's index with kLeaf set
    uint32_t byte;
    uint8_t other;
  };
  static_assert(sizeof(Node) == 16 && __builtin_offsetof(Node, byte) == 8 && __builtin_offsetof(Node, other) == 12, "Patricia.mlir's !node");
  static_assert(__builtin_offsetof(Row, len) == 8, "Patricia.mlir's row: key@0, len@8");
  static constexpr uint32_t kLeaf = 0x80000000u, kNone = 0xFFFFFFFFu;

  MutableSeries<Node> nodes;
  MutableSeries<Row> rows;
  uint32_t root = 0;
};

} // namespace composite

#endif // COMPOSITE_PATRICIA_H
