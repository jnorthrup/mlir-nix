// trikeshed.cluster_order's kernel (composite::clusterOrder: a 15+8 cluster) against the small sorts at the op's own scale, 1..23 keys:
// a stable insertion sort of the indices, and std::stable_sort.  Every way must give the same permutation.  docs/CLUSTER-SCALES.md.
// Build: clang++ -std=c++20 -O3 -I include scripts/cluster-order-scales.cc -o build/cluster-order-scales
#include "Composite/MinMaxHeap.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {
uint32_t rngState = 7;
uint32_t rng() { rngState ^= rngState << 13; rngState ^= rngState >> 17; rngState ^= rngState << 5; return rngState; }

struct Keys {  // the kernel reads keys through a Series-like view
  const int64_t *p; uint32_t n;
  uint64_t size() const { return n; }
  int64_t operator[](uint64_t i) const { return p[i]; }
};

void insertion(const int64_t *k, uint32_t n, uint32_t *out) {
  for (uint32_t i = 0; i < n; ++i) {
    uint32_t j = i;
    while (j > 0 && k[i] < k[out[j - 1]]) { out[j] = out[j - 1]; --j; }  // strict <: equal keys keep their order
    out[j] = i;
  }
}
}  // namespace

int main() {
  const uint32_t kRuns = 400000;
  for (uint32_t n : {4u, 8u, 12u, 16u, 23u}) {
    for (uint32_t distinct : {4u, 1u << 30}) {  // many equal keys (stability matters), or all distinct
      std::vector<int64_t> keys(size_t(kRuns) * n);
      for (auto &k : keys) k = int64_t(rng() % distinct) - int64_t(distinct / 2);
      std::vector<uint32_t> a(size_t(kRuns) * n), b(a.size()), c(a.size());
      double best[3] = {1e9, 1e9, 1e9};
      for (int round = 0; round < 5; ++round) {
        auto t0 = std::chrono::steady_clock::now();
        for (uint32_t r = 0; r < kRuns; ++r) {
          uint32_t *o = a.data() + size_t(r) * n, m = 0;
          composite::clusterOrder(Keys{keys.data() + size_t(r) * n, n}, [&](uint32_t i) { o[m++] = i; });
        }
        auto t1 = std::chrono::steady_clock::now();
        for (uint32_t r = 0; r < kRuns; ++r) insertion(keys.data() + size_t(r) * n, n, b.data() + size_t(r) * n);
        auto t2 = std::chrono::steady_clock::now();
        for (uint32_t r = 0; r < kRuns; ++r) {
          uint32_t *o = c.data() + size_t(r) * n;
          const int64_t *k = keys.data() + size_t(r) * n;
          for (uint32_t i = 0; i < n; ++i) o[i] = i;
          std::stable_sort(o, o + n, [&](uint32_t x, uint32_t y) { return k[x] < k[y]; });
        }
        auto t3 = std::chrono::steady_clock::now();
        best[0] = std::min(best[0], std::chrono::duration<double>(t1 - t0).count());
        best[1] = std::min(best[1], std::chrono::duration<double>(t2 - t1).count());
        best[2] = std::min(best[2], std::chrono::duration<double>(t3 - t2).count());
      }
      const bool same = a == b && b == c;
      const double per = 1e9 / double(kRuns);
      printf("n %2u %-9s cluster %7.1f ns  insertion %7.1f ns  stable_sort %7.1f ns  (a run)  %s\n", n,
             distinct == 4 ? "4 values" : "distinct", best[0] * per, best[1] * per, best[2] * per, same ? "same" : "DIFFER");
    }
  }
  return 0;
}
