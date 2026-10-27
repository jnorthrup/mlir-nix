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
#include <deque>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

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
class FileTable {
public:
  static FileTable &get() {
    static FileTable t;
    return t;
  }
  uint32_t add(const std::string &name) {
    std::lock_guard<std::mutex> g(m);
    auto [it, fresh] = ids.try_emplace(name, uint32_t(names.size() + 1));
    if (fresh) names.push_back(name);
    return it->second;
  }
  std::string name(uint32_t id) const {
    std::lock_guard<std::mutex> g(m);
    return id >= 1 && id <= names.size() ? names[id - 1] : std::string();
  }

private:
  mutable std::mutex m;
  std::unordered_map<std::string, uint32_t> ids;
  std::deque<std::string> names;
};

/// The positions an attribute cell refers to, by number: a cell (Attr) holds 32 bits where it held a 64-bit PosPtr, so it is 16 bytes,
/// not 24 (docs/FILL-DRAIN.md).  A row is the bits of a PosPtr exactly (NixDialect.h): a packed word, an op, or a Location pointer;
/// it owns nothing.  Row 0 is "no position".  Append only, never freed, written by the one thread that lowers and evaluates.
/// The names of one attribute set are consecutive rows (name i is at first + i), so an op holds the first row, not a list.
///
/// The rows are chunks of fixed size: a row never moves, growth copies nothing, and a chunk is not zeroed, because a row is written
/// before any number for it exists.
class PosTable {
public:
  static PosTable &get() {
    static PosTable t;
    return t;
  }
  /// `n` consecutive rows holding words[0] .. words[n-1] (zeros included, so that name i is at first + i); the number of the first
  /// row, or 0 when n is 0.
  uint32_t addRange(const int64_t *words, size_t n) {
    if (!n) return 0;
    uint32_t first = size_ + 1;
    for (size_t i = 0; i < n; i++) push(uint64_t(words[i]));
    return first;
  }
  /// The row of `bits`, made on its first use: for the positions that are asked for again and again (a dynamic attribute, the formals
  /// of a function).  0 for 0.
  uint32_t intern(uint64_t bits) {
    if (!bits) return 0;
    auto [it, fresh] = interned.try_emplace(bits, 0);
    if (fresh) it->second = push(bits);
    return it->second;
  }
  /// The bits of a row; 0 for row 0 and for a number that is no row.
  uint64_t word(uint32_t row) const {
    return row && row <= size_ ? chunks[(row - 1) >> kChunkBits][(row - 1) & kMask] : 0;
  }
  uint32_t size() const { return size_; }

private:
  static constexpr unsigned kChunkBits = 14; // 16384 words, 128 KiB
  static constexpr uint32_t kMask = (uint32_t(1) << kChunkBits) - 1;
  uint32_t push(uint64_t bits) {
    if (size_ == UINT32_MAX) throw std::length_error("more than 2^32 source positions");
    if ((size_ >> kChunkBits) == chunks.size()) chunks.push_back(std::make_unique_for_overwrite<uint64_t[]>(kMask + 1));
    chunks[size_ >> kChunkBits][size_ & kMask] = bits;
    return ++size_;
  }
  std::vector<std::unique_ptr<uint64_t[]>> chunks;
  uint32_t size_ = 0;
  std::unordered_map<uint64_t, uint32_t> interned;
};

} // namespace nixfe

#endif
