//===- Pos.h - A source position in one 64-bit word ------------------------===//
//
// What an op carries in its `pos` property and what the evaluator passes as a PosPtr, in place of a
// FileLineColLoc.  (file, line, column) are packed into 64 bits, the width of join::TwInt, with bit 63
// set so that a decoder can tell the word from a Location pointer (no user-space pointer has it).
// Making one is a few shifts.  The Location it replaces is hashed, probed for and allocated by the
// context's uniquer once per distinct position, and on the real workloads that was a tenth of the
// evaluation (docs/SEA-OF-NODES.md).
//
// 0 is "no position".  A line or a column past its field saturates: the message then points at the
// field's last line or column, near enough for a Nix source line a million columns wide.  A file past
// the table's 19 bits has no position.
//
// Plain C++, no MLIR.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_POS_H
#define NIX_POS_H

#include <cstdint>
#include "Composite/Mutable.h"
#include <deque>
#include <mutex>
#include <string>
#include <unordered_map>

namespace nixfe {

struct PackedPos {
  static constexpr unsigned colBits = 20, lineBits = 24, fileBits = 19;
  static constexpr uint64_t tag = uint64_t(1) << 63;
  static constexpr uint32_t maxCol = (1u << colBits) - 1, maxLine = (1u << lineBits) - 1, maxFile = (1u << fileBits) - 1;

  static constexpr uint64_t pack(uint32_t file, uint32_t line, uint32_t col) {
    if (file == 0 || file > maxFile || line == 0) return 0;
    if (line > maxLine) line = maxLine;
    if (col > maxCol) col = maxCol;
    return tag | (uint64_t(file) << (lineBits + colBits)) | (uint64_t(line) << colBits) | col;
  }
  static constexpr bool is(uint64_t raw) { return (raw & tag) != 0; }
  static constexpr uint32_t file(uint64_t raw) { return uint32_t(raw >> (lineBits + colBits)) & maxFile; }
  static constexpr uint32_t line(uint64_t raw) { return uint32_t(raw >> colBits) & maxLine; }
  static constexpr uint32_t col(uint64_t raw) { return uint32_t(raw) & maxCol; }
};

static_assert(PackedPos::file(PackedPos::pack(7, 11, 13)) == 7 && PackedPos::line(PackedPos::pack(7, 11, 13)) == 11 &&
              PackedPos::col(PackedPos::pack(7, 11, 13)) == 13 && PackedPos::is(PackedPos::pack(7, 11, 13)));
static_assert(PackedPos::pack(0, 1, 1) == 0 && PackedPos::pack(1, 0, 1) == 0, "no file or no line is no position");

/// The names of the files positions refer to, by number (1-based).  Append-only, one process-wide table:
/// a position is a number, so the name is looked up only when a message prints it.
struct FileTable {
  static FileTable &get() {
    static FileTable t;
    return t;
  }
  uint32_t add(const std::string &name) {
    std::lock_guard<std::mutex> g(m);
    auto [it, fresh] = ids.try_emplace(name, uint32_t(names.size() + 1));
    if (fresh) names.append(name);
    return it->second;
  }
  std::string name(uint32_t id) const {
    std::lock_guard<std::mutex> g(m);
    return id >= 1 && id <= names.size() ? names[id - 1] : std::string();
  }

  mutable std::mutex m;
  std::unordered_map<std::string, uint32_t> ids;
  composite::MutableSeries<std::string, composite::Chunked<std::string>> names;
};

} // namespace nixfe

#endif
