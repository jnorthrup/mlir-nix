// Rows: find, stable sort, unique-first and union against the standard library as the oracle, on random runs of every length up to 300.
// Build like minmax-check.cc.
#include "Composite/Rows.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>
using namespace composite;
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
  std::printf("PASS rows: findRow, stable sortRows, uniqueFirst and union against the standard library on 4000 random runs of up to 300 rows\n");
  return 0;
}
