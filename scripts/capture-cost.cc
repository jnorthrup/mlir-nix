// What a capture costs in the Series algebra: copy N bytes of a CharSeries four ways.
//   copy      std::copy over the window (memcpy): the floor
//   value     a Series whose index function captured the window's pointer BY VALUE:   rem() |j| [r = data() + pos](i) { return r[i]; }
//   this      a Series that captured `this`, as in `a j this::get`:                    rem() |j| [this](i) { return (*this)[pos + i]; }
//   ref       a Series that captured everything by reference:                          rem() |j| [&](i) { return src[src.pos + i]; }
// The Series copy is a fold into the destination.  Bytes per second, min of 9, the arms rotated; sizeof of each closure.
#include "Composite/CharSeries.h"
#include <chrono>
#include <cstdio>
#include <vector>
using namespace composite;
#define NOINLINE __attribute__((noinline))
NOINLINE static void copyStd(const CharSeries &s, char *to) { std::copy(s.data() + s.pos, s.data() + s.limit, to); }
NOINLINE static void copyValue(const CharSeries &s, char *to) {
  auto v = s.rem() |j| [r = s.data() + s.pos](uint32_t i) { return r[i]; };
  fold(v, to, [](char *t, char c) { *t = c; return t + 1; });
}
NOINLINE static void copyThis(const CharSeries &s, char *to) {
  auto v = s.rem() |j| [p = &s](uint32_t i) { return (*p)[p->pos + i]; };
  fold(v, to, [](char *t, char c) { *t = c; return t + 1; });
}
NOINLINE static void copyRef(const CharSeries &s, char *to) {
  auto v = s.rem() |j| [&](uint32_t i) { return s[s.pos + i]; };
  fold(v, to, [](char *t, char c) { *t = c; return t + 1; });
}
template <class F> static double gbps(F f, const CharSeries &s, char *dst, uint64_t &sink, unsigned reps) {
  auto t0 = std::chrono::steady_clock::now();
  for (unsigned r = 0; r < reps; r++) { f(s, dst); sink += uint8_t(dst[r % s.rem()]); }
  double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  return double(s.rem()) * reps / sec / 1e9;
}
int main() {
  std::vector<char> srcBuf(1 << 16), dst(1 << 16);
  for (size_t i = 0; i < srcBuf.size(); i++) srcBuf[i] = char('a' + i % 26);
  uint64_t sink = 0;
  auto v0 = 0u |j| [r = (const char *)nullptr](uint32_t) { return *r; };
  auto this0 = 0u |j| [p = (const CharSeries *)nullptr](uint32_t) { return (*p)[0]; };
  std::printf("closure sizes: value %zu B, this %zu B (one pointer each); CharSeries itself %zu B\n", sizeof(v0), sizeof(this0), sizeof(CharSeries));
  std::printf("%8s  %10s %10s %10s %10s   (GB/s, min time of 9 rounds, arms rotated)\n", "bytes", "copy", "value", "this", "ref");
  for (uint32_t n : {16u, 64u, 256u, 4096u, 65536u}) {
    CharSeries s(srcBuf.data(), n); s.at(0);
    unsigned reps = 200000000u / n;
    double b[4] = {};
    for (int r = 0; r < 9; r++) for (int k = 0; k < 4; k++) {
      int arm = (k + r) % 4;
      double g = arm == 0 ? gbps(copyStd, s, dst.data(), sink, reps) : arm == 1 ? gbps(copyValue, s, dst.data(), sink, reps)
               : arm == 2 ? gbps(copyThis, s, dst.data(), sink, reps) : gbps(copyRef, s, dst.data(), sink, reps);
      if (g > b[arm]) b[arm] = g;
    }
    std::printf("%8u  %10.1f %10.1f %10.1f %10.1f   value %+.0f%%  this %+.0f%%  ref %+.0f%%  vs copy\n", n, b[0], b[1], b[2], b[3],
                100 * (b[1] - b[0]) / b[0], 100 * (b[2] - b[0]) / b[0], 100 * (b[3] - b[0]) / b[0]);
  }
  std::printf("[%llu]\n", (unsigned long long)sink);
}
