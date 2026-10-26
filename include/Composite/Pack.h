//===- Pack.h - Twin<Int> collapsed to one 64-bit word ----------------------===//
//
// The layout `join-densify` gives !join.pair<i32, i32> (see JoinOps.td): the first component
// in the high half, the second in the low half, one shift and one mask per access.  It is
// TrikeShed's TwInt, and the frontend's currency for segments of an immutable buffer: the
// lexer stores (start, end) pairs and never touches the input.  Plain C++, no MLIR.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_PACK_H
#define COMPOSITE_PACK_H

#include <cstdint>

namespace join {

struct TwInt {
  uint64_t raw = 0;
  constexpr TwInt() = default;
  constexpr TwInt(uint32_t a, uint32_t b) : raw((uint64_t(a) << 32) | b) {}
  constexpr explicit TwInt(uint64_t r) : raw(r) {}
  constexpr uint32_t first() const { return uint32_t(raw >> 32); }
  constexpr uint32_t second() const { return uint32_t(raw); }
  constexpr bool operator==(TwInt o) const { return raw == o.raw; }
};

// The constant test/mlir/join.mlir folds `join.make 7, 9 : !join.pair<i32, i32>` to.
static_assert(TwInt(7, 9).raw == 30064771081ull, "TwInt and join-densify disagree on the layout");
static_assert(TwInt(7, 9).first() == 7 && TwInt(7, 9).second() == 9);

} // namespace join

#endif
