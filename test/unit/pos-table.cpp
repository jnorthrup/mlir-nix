// Unit test of nixfe::PosTable (include/Nix/Pos.h): the rows an attribute cell's position refers to.  Header-only, no LLVM: built and run
// by scripts/check-pos-table.py.  The table keeps rows in chunks of 16384; the lang tests cannot reach a chunk boundary (a source file
// would need 16384 definitions, and the reference evaluator cannot answer unsafeGetAttrPos for code that does not come from a checkout),
// so the boundaries are checked here, together with the other things a wrong row number would break silently.
#include "Nix/Pos.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

using nixfe::PosTable;

static int checks = 0;
#define CHECK(cond)                                                                                                    \
  do {                                                                                                                 \
    checks++;                                                                                                          \
    if (!(cond)) {                                                                                                     \
      std::fprintf(stderr, "pos-table: FAILED line %d: %s\n", __LINE__, #cond);                                        \
      std::exit(1);                                                                                                    \
    }                                                                                                                  \
  } while (0)

// A word that is never 0 and is different for every i, with bit 63 set as a packed position has it.
static uint64_t word(uint64_t i) { return (i + 1) * 0x9E3779B97F4A7C15ull | (uint64_t(1) << 63); }

int main() {
  PosTable t;
  CHECK(t.size() == 0);
  CHECK(t.word(0) == 0 && t.word(1) == 0 && t.word(12345) == 0); // no rows yet
  CHECK(t.addRange(nullptr, 0) == 0 && t.size() == 0);           // nothing added is no first row

  // Ranges of every kind of size, one after the other: the first row is always the next number, the rows read back, and the ones that
  // sit on each side of a chunk boundary (16384, 32768, 49152) are all checked.
  const size_t sizes[] = {1, 3, 16380, 1, 2, 16384, 16385, 7, 20000, 1};
  std::vector<int64_t> src;
  uint64_t next = 0, rows = 0;
  std::vector<std::pair<uint32_t, uint64_t>> placed; // (first row, count)
  for (size_t n : sizes) {
    src.clear();
    for (size_t k = 0; k < n; k++) src.push_back(int64_t(word(next + k)));
    uint32_t first = t.addRange(src.data(), n);
    CHECK(first == rows + 1);
    CHECK(t.size() == rows + n);
    for (size_t k = 0; k < n; k++) CHECK(t.word(first + uint32_t(k)) == word(next + k));
    placed.push_back({first, n});
    next += n;
    rows += n;
  }
  CHECK(rows > 3 * 16384); // three boundaries were crossed
  // Everything is still there after all the growth: nothing moved, nothing was overwritten.
  next = 0;
  for (auto [first, n] : placed)
    for (size_t k = 0; k < n; k++) CHECK(t.word(first + uint32_t(k)) == word(next++));
  // The last row is readable, the one after it is not, and neither is row 0 or a number far past the end.
  CHECK(t.word(t.size()) == word(rows - 1));
  CHECK(t.word(t.size() + 1) == 0 && t.word(0) == 0 && t.word(0xFFFFFFFFu) == 0);
  // The rows at each boundary, by number.
  for (uint32_t b : {16384u, 32768u, 49152u})
    for (uint32_t r = b - 1; r <= b + 2; r++) CHECK(t.word(r) == word(r - 1));

  // A zero in a range is a row of its own (name i stays at first + i), and reads back as no position.
  const int64_t withZero[] = {int64_t(word(1)), 0, int64_t(word(2))};
  uint32_t z = t.addRange(withZero, 3);
  CHECK(z == rows + 1 && t.word(z) == word(1) && t.word(z + 1) == 0 && t.word(z + 2) == word(2));

  // intern: one row per distinct value, made on first use, 0 for 0, and it reads back through word().
  uint32_t before = t.size();
  uint32_t a = t.intern(word(100000)), b = t.intern(word(100001));
  CHECK(a != 0 && b != 0 && a != b && a == before + 1 && b == before + 2);
  CHECK(t.intern(word(100000)) == a && t.intern(word(100001)) == b && t.size() == before + 2);
  CHECK(t.intern(0) == 0 && t.size() == before + 2);
  CHECK(t.word(a) == word(100000) && t.word(b) == word(100001));
  // a value that is also in a range is interned apart, and the range is untouched
  uint32_t c = t.intern(word(5));
  CHECK(c != 0 && t.word(c) == word(5) && t.word(7) == word(6));

  std::printf("pos-table: %d checks passed (%llu rows)\n", checks, (unsigned long long)t.size());
  return 0;
}
