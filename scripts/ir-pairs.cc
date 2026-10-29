// Pairs are two scalars: LLVM should keep them in registers.  Each function below is a small slicing/dicing operation on windows, cursors and
// Series; scripts/ir-pairs.sh compiles them to LLVM IR at -O2 and counts what survives (alloca / load / store / call).  A pair that stays a
// pair has none; a pair whose address escaped into a closure keeps loads.
#include "Composite/CharSeries.h"
using namespace composite;
#define F extern "C" __attribute__((noinline))

// the slicing and dicing: values in, values out
F CharWindow slice(CharWindow w, uint32_t a, uint32_t b) { return w[join::TwInt(a, b)]; }
F CharWindow sliceOfSlice(CharWindow w, uint32_t a, uint32_t b, uint32_t c, uint32_t d) { return w[join::TwInt(a, b)][join::TwInt(c, d)]; }
F uint32_t trimmedLength(CharSeries s) { s.trim(); return s.rem(); }                       // a cursor mutated through references, then dropped
F uint32_t cursorWalk(CharSeries s, char target) { return s.seekTo(target) ? s.pos : ~0u; }  // the cursor verbs
F uint64_t pack(uint32_t a, uint32_t b) { return (a |j| b).raw; }                           // a pair of ints is one integer
F uint32_t unpack(uint64_t r) { auto [x, y] = join::TwInt(join::TwInt::Raw(r)); return x + y; }
F uint32_t joinsSum(const uint32_t *p, uint32_t n) { return fold(n |j| [p](uint32_t i) { return p[i]; }, 0u, [](uint32_t a, uint32_t x) { return a + x; }); }

// the same sum three ways, differing only in what the closure captured
F uint64_t sumByValue(CharWindow w) {
  auto s = w.len |j| [b = w.base](uint32_t i) { return b[i]; };
  return fold(s, uint64_t(0), [](uint64_t a, char c) { return a + uint8_t(c); });
}
F uint64_t sumThis(const CharSeries &w, char *clobber) {                                     // a store through a char* between reads
  auto s = w.size() |j| [p = &w](uint32_t i) { return (*p)[i]; };
  uint64_t t = 0; for (uint32_t i = 0; i < s.size(); i++) { t += uint8_t(s[i]); clobber[i & 7] = 1; }
  return t;
}
F uint64_t sumValueClobber(CharWindow w, char *clobber) {
  auto s = w.len |j| [b = w.base](uint32_t i) { return b[i]; };
  uint64_t t = 0; for (uint32_t i = 0; i < s.size(); i++) { t += uint8_t(s[i]); clobber[i & 7] = 1; }
  return t;
}
