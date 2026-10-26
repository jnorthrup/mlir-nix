// Correctness and probe-count behaviour of the funnel / elastic tables.
//   c++ -std=c++20 -O2 -o /tmp/test_krapivin experiments/attrs/test_krapivin.cpp && /tmp/test_krapivin
#define KRAPIVIN_COUNT
#include "krapivin.h"

#include <cstdio>
#include <cstdlib>
#include <random>
#include <unordered_set>

using namespace krapivin;

struct Stat {
  double hit = 0, miss = 0, bytesPerKey = 0;
  uint32_t fails = 0, wrong = 0;
};

// Insert `fill * n` random keys into a table with n slots; verify; count probes.
template <class T> Stat measure(uint32_t n, double fill, uint32_t seed, uint32_t den = 8) {
  T t = [&] {
    if constexpr (std::is_same_v<T, LinearTable>) return LinearTable(n);
    else return T(n, den);
  }();
  std::mt19937_64 rng(seed);
  uint32_t m = (uint32_t)(fill * n);
  std::unordered_set<uint32_t> present;
  std::vector<uint32_t> keys;
  Stat s;
  while (keys.size() < m) {
    uint32_t k = (uint32_t)rng();
    if (k == EMPTY || !present.insert(k).second) continue;
    if (t.insert(k, k ^ 0x5bd1e995u)) keys.push_back(k);
    else s.fails++, present.erase(k), m--;  // table overflowed: stop counting this key
  }
  t.probes_ = 0;
  for (uint32_t k : keys) {
    const Slot *p = t.find(k);
    if (!p || p->val != (k ^ 0x5bd1e995u)) s.wrong++;
  }
  s.hit = keys.empty() ? 0 : double(t.probes_) / keys.size();
  t.probes_ = 0;
  const uint32_t Q = 50000;
  uint32_t q = 0;
  while (q < Q) {
    uint32_t k = (uint32_t)rng();
    if (k == EMPTY || present.count(k)) continue;
    if (t.find(k)) s.wrong++;
    q++;
  }
  s.miss = double(t.probes_) / Q;
  s.bytesPerKey = keys.empty() ? 0 : double(t.bytes()) / keys.size();
  return s;
}

int main() {
  int bad = 0;
  printf("== large tables (the paper's regime): slots examined per lookup; fill is a fraction of the slots\n");
  printf("%-9s %9s %6s | %-24s | %-24s | %-24s\n", "", "slots", "fill", "linear probing", "funnel (delta=1/8)", "elastic (delta=1/8)");
  printf("%-9s %9s %6s | %7s %7s %7s | %7s %7s %7s | %7s %7s %7s\n", "", "", "", "hit", "miss", "fails", "hit", "miss", "fails", "hit", "miss", "fails");
  for (uint32_t n : {10000u, 1000000u})
    for (double fill : {0.50, 0.75, 0.875}) {
      Stat l = measure<LinearTable>(n, fill, 1), f = measure<Funnel>(n, fill, 1), e = measure<Elastic>(n, fill, 1);
      printf("%-9s %9u %5.1f%% | %7.2f %7.2f %7u | %7.2f %7.2f %7u | %7.2f %7.2f %7u\n", "", n, fill * 100, l.hit, l.miss, l.fails, f.hit, f.miss, f.fails, e.hit, e.miss, e.fails);
      bad += l.wrong + f.wrong + e.wrong;
    }
  // Where the asymptotics start to pay: delta = 1/den, fill = 1 - delta, n = 10^6 slots.
  printf("\n== crossover: fill = 1 - delta, 10^6 slots\n");
  printf("%6s %8s | %-15s | %-15s | %-15s\n", "delta", "fill", "linear", "funnel", "elastic");
  printf("%6s %8s | %7s %7s | %7s %7s | %7s %7s\n", "", "", "hit", "miss", "hit", "miss", "hit", "miss");
  for (uint32_t den : {8u, 16u, 32u, 64u, 128u, 256u}) {
    double fill = 1.0 - 1.0 / den;
    Stat l = measure<LinearTable>(1000000, fill, 1), f = measure<Funnel>(1000000, fill, 1, den), e = measure<Elastic>(1000000, fill, 1, den);
    printf("1/%-4u %7.2f%% | %7.2f %7.1f | %7.2f %7.1f | %7.2f %7.1f   fails %u/%u/%u\n", den, fill * 100, l.hit, l.miss, f.hit, f.miss, e.hit, e.miss, l.fails, f.fails, e.fails);
    bad += l.wrong + f.wrong + e.wrong;
  }
  printf("\n== Nix-sized tables: m keys in capacityFor(m, 8) slots, mean of 400 random trials\n");
  printf("%5s %6s | %-22s | %-22s | %-22s\n", "m", "slots", "linear (same slots)", "funnel", "elastic");
  printf("%5s %6s | %7s %7s %6s | %7s %7s %6s | %7s %7s %6s\n", "", "", "hit", "miss", "ovfl%", "hit", "miss", "ovfl%", "hit", "miss", "ovfl%");
  for (uint32_t m : {4u, 8u, 16u, 32u, 64u, 256u, 1024u}) {
    uint32_t n = capacityFor(m, 8);
    double fill = double(m) / n, h[3] = {}, ms[3] = {}, ov[3] = {};
    const int T = 400;
    for (int trial = 0; trial < T; trial++) {
      Stat a = measure<LinearTable>(n, fill, 100 + trial), b = measure<Funnel>(n, fill, 100 + trial), c = measure<Elastic>(n, fill, 100 + trial);
      Stat* r[3] = {&a, &b, &c};
      for (int i = 0; i < 3; i++) h[i] += r[i]->hit, ms[i] += r[i]->miss, ov[i] += r[i]->fails > 0;
      bad += a.wrong + b.wrong + c.wrong;
    }
    printf("%5u %6u | %7.2f %7.2f %5.1f%% | %7.2f %7.2f %5.1f%% | %7.2f %7.2f %5.1f%%\n", m, n, h[0] / T, ms[0] / T, 100 * ov[0] / T, h[1] / T, ms[1] / T, 100 * ov[1] / T,
           h[2] / T, ms[2] / T, 100 * ov[2] / T);
  }
  printf("\nincorrect results: %d\n", bad);
  return bad != 0;
}
