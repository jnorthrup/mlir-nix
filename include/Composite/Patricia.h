//===- Patricia.h - rows found by a byte string: the crit-bit trie of the pure zone ---===//
//
// Paths share long prefixes, so a row found by its path is kept in a crit-bit (Patricia) trie.  An inner node is the one bit at which the
// keys under it first differ: a lookup tests one bit a node on its way down and compares the key once, at the leaf it reaches.  There is no
// hash and no key read twice, the rows are in byte order, and the keys under a prefix are one subtree.  Nodes and rows are series addressed
// by index, so an insert that grows them moves nothing anyone holds.
//
// A key is read as if a 0 byte followed it.  Keys hold no 0 byte (paths do not), so no key is another's prefix in the trie's eyes.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_PATRICIA_H
#define COMPOSITE_PATRICIA_H

#include "Composite/Mutable.h"

namespace composite {

template <class V> struct Patricia {
  struct Row {
    const char *key; // outlives the trie: an arena copy, or a literal
    uint32_t len;
    V v;
  };

  uint32_t size() const { return rows.size(); }

  /// The value stored for the key, or null.
  V *find(const char *k, uint32_t n) {
    if (rows.empty()) return nullptr;
    Row &r = rows[leafOf(k, n)];
    return r.len == n && __builtin_memcmp(r.key, k, n) == 0 ? &r.v : nullptr;
  }

  /// The key now stands for v.  `copy()` makes the key's bytes where they outlive the trie; it is called only for a key not stored yet.
  /// The value's address holds until the next set.
  template <class Copy> V *set(const char *k, uint32_t n, V v, Copy copy) {
    if (rows.empty()) {
      rows.append(Row{copy(), n, v});
      root = kLeaf;
      return &rows[0].v;
    }
    uint32_t bi = leafOf(k, n);
    const Row &best = rows[bi];
    // The first byte where the key and the leaf it reached differ (the 0 past either end counts): the new node tests a bit of it.
    uint32_t m = n > best.len ? n : best.len, b = 0;
    uint32_t x = 0;
    for (; b <= m; b++)
      if ((x = uint32_t(byteAt(k, n, b) ^ byteAt(best.key, best.len, b))) != 0) break;
    if (x == 0) {
      rows[bi].v = v;
      return &rows[bi].v;
    }
    // The highest bit that differs, as the mask of the other bits: a node's direction is (1 + (other | byte)) >> 8.
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    uint8_t other = uint8_t((x & ~(x >> 1)) ^ 0xFF);
    uint32_t dir = (1 + (other | byteAt(k, n, b))) >> 8;
    uint32_t ri = rows.append(Row{copy(), n, v});
    // Down from the root to the first node whose bit comes after the new one (a later byte, or a lower bit of the same byte): the new
    // node takes its place and it becomes the new node's other side.
    uint32_t parent = kNone, side = 0, p = root;
    while (!(p & kLeaf)) {
      const Node &q = nodes[p];
      if (q.byte > b || (q.byte == b && q.other > other)) break;
      parent = p;
      side = (1 + (q.other | byteAt(k, n, q.byte))) >> 8;
      p = q.child[side];
    }
    Node nn;
    nn.byte = b;
    nn.other = other;
    nn.child[dir] = ri | kLeaf;
    nn.child[1 - dir] = p;
    uint32_t ni = nodes.append(nn);
    if (parent == kNone) root = ni;
    else nodes[parent].child[side] = ni;
    return &rows[ri].v;
  }

  /// Each row whose key starts with the prefix, in byte order: `emit(const Row &)`.
  template <class Emit> void prefix(const char *k, uint32_t n, Emit &&emit) const {
    if (rows.empty()) return;
    // Down while a node tests a byte of the prefix: past it, every key of the subtree agrees on the prefix or none does.
    uint32_t p = root;
    while (!(p & kLeaf) && nodes[p].byte < n) {
      const Node &q = nodes[p];
      p = q.child[(1 + (q.other | byteAt(k, n, q.byte))) >> 8];
    }
    const Row &any = rows[leafOf(p)];
    if (any.len < n || __builtin_memcmp(any.key, k, n) != 0) return;
    walk(p, emit);
  }

private:
  struct Node {
    uint32_t child[2]; // a node's index, or a row's index with kLeaf set
    uint32_t byte;
    uint8_t other;
  };
  static constexpr uint32_t kLeaf = 0x80000000u, kNone = 0xFFFFFFFFu;

  static uint8_t byteAt(const char *k, uint32_t n, uint32_t i) { return i < n ? uint8_t(k[i]) : 0; }
  uint32_t leafOf(const char *k, uint32_t n) const {
    uint32_t p = root;
    while (!(p & kLeaf)) {
      const Node &q = nodes[p];
      p = q.child[(1 + (q.other | byteAt(k, n, q.byte))) >> 8];
    }
    return p & ~kLeaf;
  }
  /// The first row of the subtree at p.
  uint32_t leafOf(uint32_t p) const {
    while (!(p & kLeaf)) p = nodes[p].child[0];
    return p & ~kLeaf;
  }
  /// The rows of the subtree at p in byte order: side 0 first.  An explicit stack, as deep as the trie (a bit of each byte, at most).
  template <class Emit> void walk(uint32_t p, Emit &emit) const {
    MutableSeries<uint32_t> todo;
    todo.append(p);
    while (!todo.empty()) {
      uint32_t q = todo.back();
      todo.pop();
      if (q & kLeaf) {
        emit(rows[q & ~kLeaf]);
        continue;
      }
      todo.append(nodes[q].child[1]);
      todo.append(nodes[q].child[0]);
    }
  }

  MutableSeries<Node> nodes;
  MutableSeries<Row> rows;
  uint32_t root = 0;
};

} // namespace composite

#endif // COMPOSITE_PATRICIA_H
