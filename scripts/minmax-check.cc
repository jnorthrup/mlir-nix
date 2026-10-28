// Recovered heap checks: exhaustive duplicate keys, mixed edge removal,
// signed limits, and reused/full clusters. The stdlib is the reference only.
// Build like scripts/inode-bench.cc, optionally with -fsanitize=address,undefined.
#include "Composite/MinMaxHeap.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <limits>
#include <set>
#include <vector>
using namespace composite;

static void require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
static uint32_t state;
static uint32_t rng() { state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state; }

static void binary() {
  for (unsigned policy = 0; policy < 3; ++policy) {
    uint64_t tested = 0;
    for (unsigned n = 1; n <= 15; ++n) {
      for (unsigned enc = 0; enc < (1u << n); ++enc) {
        MinMaxHeap<int64_t, 15> h;
        std::multiset<int64_t> ref;
        for (unsigned j = 0; j < n; ++j) { int64_t v = (enc >> j) & 1; h.push(v); ref.insert(v); }
        while (!ref.empty()) {
          bool low = policy == 0 || (policy == 2 && ref.size() % 2);
          auto it = low ? ref.begin() : std::prev(ref.end());
          auto expected = *it;
          ref.erase(it);
          require((low ? h.popMin() : h.popMax()) == expected, "exhaustive duplicate-key edge removal");
        }
        ++tested;
      }
    }
    std::printf("binary policy=%u: PASS, tested=%llu\n", policy, (unsigned long long)tested);
  }
}
static void mixed(bool duplicates) {
  state = 0x31415926;
  uint64_t serial = 0, steps = 0;
  for (unsigned t = 0; t < 10000; ++t) {
    MinMaxHeap<int64_t, 15> h;
    std::multiset<int64_t> ref;
    for (unsigned k = 0; k < 200; ++k) {
      unsigned choice = rng() % 100;
      if (ref.empty() || (ref.size() < 15 && choice < 62)) {
        int64_t v = duplicates ? int64_t(rng() % 5) : int64_t(++serial) * ((rng() & 1) ? 1 : -1);
        h.push(v); ref.insert(v);
      } else {
        bool low = rng() & 1;
        auto it = low ? ref.begin() : std::prev(ref.end());
        auto expected = *it;
        ref.erase(it);
        require((low ? h.popMin() : h.popMax()) == expected, "mixed push/pop result");
      }
      require(h.size() == ref.size(), "mixed push/pop size");
      require(ref.empty() || (h.min() == *ref.begin() && h.max() == *ref.rbegin()), "mixed push/pop edges");
      ++steps;
    }
  }
  std::printf("mixed duplicates=%d: PASS, steps=%llu\n", duplicates, (unsigned long long)steps);
}
static void clusters(bool duplicates) {
  state = 0x541dbeef;
  Cluster<int64_t, 15, 8> c;
  for (unsigned t = 0; t < 100000; ++t) {
    std::vector<int64_t> ref, out;
    unsigned n = 1 + rng() % 23;
    for (unsigned i = 0; i < n; ++i) {
      int64_t v = duplicates ? int64_t(rng() % 4) : int64_t(i) * ((rng() & 1) ? 1 : -1);
      ref.push_back(v);
      require(c.insert(v) != 2, "cluster admission");
    }
    require(n != 23 || (c.insert(9999) == 2 && c.size() == 23), "full cluster stays intact");
    std::sort(ref.begin(), ref.end());
    require(c.min() == ref.front(), "cluster min");
    c.drain([&](int64_t v) { out.push_back(v); });
    require(ref == out && c.size() == 0, "cluster ordered drain and reuse");
  }
  std::printf("clusters duplicates=%d: PASS, batches=100000\n", duplicates);
}
int main() {
  binary(); mixed(false); mixed(true); clusters(false); clusters(true);
  Cluster<int64_t, 15, 8> c;
  std::vector<int64_t> ref = {std::numeric_limits<int64_t>::min(), 0, std::numeric_limits<int64_t>::max(), -1, 1}, out;
  for (auto v : ref) c.insert(v);
  std::sort(ref.begin(), ref.end());
  c.drain([&](int64_t v) { out.push_back(v); });
  require(ref == out, "signed integer limits");
  std::puts("signed limits: PASS");
}
