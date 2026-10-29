// Does CharSeries (32 bytes: root, TwInt bounds, cursor) compete with std::string_view (16 bytes) where the evaluator uses it: building a
// string from a handful of pieces (concatenation, concatStringsSep).  Same pool, same piece counts, the same fold copy into a bump buffer.
#include "Composite/CharSeries.h"
#include <chrono>
#include <cstdio>
#include <string>
#include <vector>
using namespace composite;
template <class Piece, class Make, class View>
static double run(const std::vector<std::string> &pool, const std::vector<uint32_t> &picks, char *arena, Make make, View view, uint64_t &sink) {
  auto t0 = std::chrono::steady_clock::now();
  char *top = arena;
  for (size_t k = 0; k + 6 < picks.size(); k += 6) {
    Piece pieces[6];
    unsigned n = 2 + picks[k] % 5;
    for (unsigned i = 0; i < n; i++) pieces[i] = make(pool[picks[k + i] % pool.size()]);
    size_t total = fold(series(pieces, n), size_t(0), [&](size_t t, const Piece &p) { return t + view(p).size(); });
    char *at = fold(series(pieces, n), top, [&](char *to, const Piece &p) { auto w = view(p); return std::copy(w.begin(), w.end(), to); });
    *at = 0;
    sink += total + uint8_t(top[0]);
    top = at + 1;
    if (top - arena > (64 << 20)) top = arena;
  }
  return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
}
int main() {
  std::vector<std::string> pool;
  uint64_t st = 88172645463325252ull; auto rng = [&] { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; };
  for (int i = 0; i < 4096; i++) { std::string s; for (unsigned j = 0, n = 1 + rng() % 24; j < n; j++) s += char('a' + rng() % 26); pool.push_back(s); }
  std::vector<uint32_t> picks(18'000'000); for (auto &p : picks) p = uint32_t(rng());
  std::vector<char> arena(80 << 20);
  uint64_t sink = 0; double cs = 1e9, sv = 1e9, cw = 1e9;
  // the three arms rotate within each round, so no arm always runs first
  auto armSv = [&] { sv = std::min(sv, run<std::string_view>(pool, picks, arena.data(), [](const std::string &s) { return std::string_view(s); }, [](std::string_view v) { return v; }, sink)); };
  auto armCw = [&] { cw = std::min(cw, run<CharWindow>(pool, picks, arena.data(), [](const std::string &s) { return CharWindow(std::string_view(s)); }, [](const CharWindow &c) { return c.view(); }, sink)); };
  auto armCs = [&] { cs = std::min(cs, run<CharSeries>(pool, picks, arena.data(), [](const std::string &s) { return CharSeries(std::string_view(s)); }, [](const CharSeries &c) { return c.view(); }, sink)); };
  for (int r = 0; r < 9; r++) {
    if (r % 3 == 0) { armSv(); armCw(); armCs(); }
    else if (r % 3 == 1) { armCw(); armCs(); armSv(); }
    else { armCs(); armSv(); armCw(); }
  }
  std::printf("3,000,000 strings from 2-6 pieces, min of 9, rotated: string_view (16 B) %.3f s; CharWindow (%zu B) %.3f s %+.1f%%; CharSeries (%zu B) %.3f s %+.1f%%  [%llu]\n",
              sv, sizeof(CharWindow), cw, 100 * (cw - sv) / sv, sizeof(CharSeries), cs, 100 * (cs - sv) / sv, (unsigned long long)sink);
}
