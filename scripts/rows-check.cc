// Rows: find, stable sort, unique-first and union against the standard library as the oracle, on random runs of every length up to 300.
// Build like minmax-check.cc.
#include "Composite/Rows.h"
#include "Composite/Series.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <random>
#include <string>
#include <vector>
using namespace composite;
static long live = 0; // blocks from operator new not yet given back: the unwind of a throwing comparator must leave it where it was
void *operator new(std::size_t n) { ++live; if (void *p = std::malloc(n ? n : 1)) return p; throw std::bad_alloc(); }
void *operator new(std::size_t n, const std::nothrow_t &) noexcept { ++live; return std::malloc(n ? n : 1); } // the oracle's stable_sort buffer
void operator delete(void *p) noexcept { if (p) { --live; std::free(p); } }
void operator delete(void *p, std::size_t) noexcept { operator delete(p); }
void operator delete(void *p, const std::nothrow_t &) noexcept { operator delete(p); }
struct Row { uint32_t key; uint32_t tag; };
static void require(bool ok, const char *what) { if (!ok) { std::printf("FAIL %s\n", what); std::exit(1); } }
int main() {
  std::mt19937 rng(7);
  auto key = [](const Row &r) { return r.key; };
  auto less = [](const Row &a, const Row &b) { return a.key < b.key; };
  for (int round = 0; round < 4000; round++) {
    size_t n = rng() % 300; uint32_t span = 1 + rng() % 400;
    std::vector<Row> v(n); for (size_t i = 0; i < n; i++) v[i] = {uint32_t(rng() % span), uint32_t(i)};
    std::vector<Row> ref = v, mine = v;
    std::stable_sort(ref.begin(), ref.end(), less);
    sortRows(mine.data(), n, less);
    for (size_t i = 0; i < n; i++) require(mine[i].key == ref[i].key && mine[i].tag == ref[i].tag, "stable sort");
    std::vector<Row> into(n);                                              // out of place: the source is read where it lies and left as it was
    sortRows(static_cast<const Row *>(v.data()), into.data(), n, less);
    for (size_t i = 0; i < n; i++) require(into[i].key == ref[i].key && into[i].tag == ref[i].tag && v[i].tag == uint32_t(i), "stable sort into");
    if (n > 30) { // a comparator that throws mid-sort: the temporary run is released by the unwind (run under a leak checker to see it)
      size_t calls = 0;
      long before = live;
      try { sortRows(mine.data(), n, [&](const Row &a, const Row &b) { if (++calls == n) throw 1; return a.key < b.key; }); require(false, "throws"); }
      catch (int) {}
      require(live == before, "the temporary run is released when the comparator throws");
      sortRows(mine.data(), n, less);
    }
    size_t m = uniqueFirst(mine.data(), n, key);
    std::vector<Row> uniq; for (size_t i = 0; i < n; i++) if (uniq.empty() || uniq.back().key != ref[i].key) uniq.push_back(ref[i]);
    require(m == uniq.size(), "unique count");
    for (size_t i = 0; i < m; i++) require(mine[i].key == uniq[i].key && mine[i].tag == uniq[i].tag, "first of each key kept");
    for (uint32_t k = 0; k < span + 2; k++) {
      const Row *f = findRow(mine.data(), m, k, key);
      auto it = std::lower_bound(uniq.begin(), uniq.end(), k, [](const Row &r, uint32_t kk) { return r.key < kk; });
      bool has = it != uniq.end() && it->key == k;
      require((f != nullptr) == has && (!has || f->tag == it->tag), "find");
    }
    // union, y wins
    std::vector<Row> y(rng() % 200); for (size_t i = 0; i < y.size(); i++) y[i] = {uint32_t(rng() % span), 1000000 + uint32_t(i)};
    std::stable_sort(y.begin(), y.end(), less);
    std::vector<Row> yu; for (auto &r : y) if (yu.empty() || yu.back().key != r.key) yu.push_back(r);
    size_t un = unionSize(mine.data(), m, yu.data(), yu.size(), key);
    std::vector<Row> out(un);
    require(unionRows(mine.data(), m, yu.data(), yu.size(), out.data(), key) == un, "union size agrees with the fill");
    std::vector<Row> want;
    for (auto &r : uniq) want.push_back(r);
    for (auto &r : yu) { auto it = std::find_if(want.begin(), want.end(), [&](const Row &q) { return q.key == r.key; }); if (it != want.end()) *it = r; else want.push_back(r); }
    std::sort(want.begin(), want.end(), less);
    require(want.size() == un, "union count");
    for (size_t i = 0; i < un; i++) require(out[i].key == want[i].key && out[i].tag == want[i].tag, "union rows, y wins");
  }
  // lessChars over Series<char> (Series.h) against std::string's order: memcmp's, unsigned bytes, then the shorter first
  for (int round = 0; round < 20000; round++) {
    std::string a(rng() % 6, '\0'), b(rng() % 6, '\0');
    for (auto &ch : a) ch = char(rng() % 4 == 0 ? 0x80 + rng() % 4 : 'a' + rng() % 3);
    for (auto &ch : b) ch = char(rng() % 4 == 0 ? 0x80 + rng() % 4 : 'a' + rng() % 3);
    auto sa = series(a.data(), uint32_t(a.size())), sb = series(b.data(), uint32_t(b.size()));
    require(lessChars(sa, sb) == (a < b) && lessChars(sb, sa) == (b < a), "lessChars is std::string's order");
  }
  std::printf("PASS rows: findRow, stable sortRows (in place, into, and unwound by a throwing comparator with nothing left allocated), uniqueFirst, union and lessChars against the standard library on 4000 random runs of up to 300 rows\n");
  return 0;
}
