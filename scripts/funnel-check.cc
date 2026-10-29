// The funnel table of clusters: correctness against a reference set, and the probe counts that make it O(1).
// The stdlib is the oracle only.  Build like scripts/minmax-check.cc; -fsanitize=address,undefined works.
#include "Composite/Funnel.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <set>
#include <utility>
using namespace composite;

static void require(bool ok, const char *m) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", m); std::exit(1); } }
static uint64_t st = 88172645463325252ull;
static uint64_t rng() { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; }

constexpr unsigned L = 6;
using F = Funnel<InodeRow, 15, 8, L>;
constexpr uint32_t TOP = 1024;
static Cluster<InodeRow, 15, 8> cells[F::cellsFor(TOP)];

static InodeRow key(uint32_t serial) {  // dense window keys: small objectid tail, few types, spread offsets
  uint64_t r = rng();
  return InodeRow::pack(1000 + (r & 0xFFFFF), uint8_t(r >> 20 & 3), (r >> 24) & 0xFFFFFF, 1000, serial);
}

static void run(double load) {
  for (auto &c : cells) c = {};
  F t(cells, TOP);
  const uint32_t cap = TOP * 23 * 2 - 0;  // upper bound; report load against actual cell capacity below
  uint32_t slots = 0;
  for (uint32_t l = 0; l < L; ++l) slots += (TOP >> l) * 23;
  uint32_t want = uint32_t(slots * load);
  (void)cap;
  std::set<std::pair<uint32_t, uint64_t>> ref;
  InodeRow kept[1 << 16];
  uint32_t nk = 0, lost = 0, dup = 0, depth[L + 2] = {};
  while (nk + lost < want) {
    InodeRow r = key(nk);
    uint32_t p = t.put(r);
    bool fresh = ref.insert({r.hi, r.lo}).second;
    if (!fresh) { require(p == 0xFF, "duplicate key must be refused"); ++dup; continue; }
    if (p == 0xFE) { ++lost; continue; }
    require(p < L, "placed on a level");
    ++depth[p];
    if (nk < (1u << 16)) kept[nk] = r;
    ++nk;
  }
  uint64_t probes = 0; uint32_t worst = 0;
  for (uint32_t i = 0; i < nk && i < (1u << 16); ++i) {
    uint32_t pr = 0;
    const InodeRow *f = t.get(kept[i], &pr);
    require(f && f->val == kept[i].val, "stored key must be found with its payload");
    probes += pr; worst = pr > worst ? pr : worst;
  }
  uint64_t mprobes = 0; uint32_t mworst = 0, misses = 0;
  for (uint32_t i = 0; i < 100000; ++i) {
    InodeRow r = key(0);
    if (ref.count({r.hi, r.lo})) continue;
    uint32_t pr = 0;
    require(!t.get(r, &pr), "absent key must miss");
    mprobes += pr; mworst = pr > mworst ? pr : mworst; ++misses;
  }
  uint32_t checked = nk < (1u << 16) ? nk : (1u << 16);
  std::printf("load %.2f: stored=%u refused-full=%u dup=%u | hit probes avg %.3f max %u | miss probes avg %.3f max %u | levels:",
              load, nk, lost, dup, double(probes) / checked, worst, double(mprobes) / misses, mworst);
  for (uint32_t l = 0; l < L; ++l) std::printf(" %u", depth[l]);
  std::printf("\n");
}

// A row of another shape entirely: a 64-bit key and a 64-bit payload, hashed by its own functor.
struct KV {
  uint64_t k, v;
  friend constexpr bool operator<(const KV &a, const KV &b) { return a.k < b.k; }
  friend constexpr bool operator==(const KV &a, const KV &b) { return a.k == b.k; }
};
struct KVHash { constexpr uint64_t operator()(const KV &r) const { return r.k; } };

static void generic() {
  using G = Funnel<KV, 15, 8, 5, KVHash>;
  static Cluster<KV, 15, 8> kc[G::cellsFor(256)];
  G t(kc, 256);
  std::set<uint64_t> ref;
  uint32_t stored = 0;
  for (uint32_t i = 0; i < 5000; ++i) {
    KV r{rng(), i};
    uint32_t p = t.put(r);
    if (ref.insert(r.k).second) { require(p < 5, "generic row placed"); ++stored; } else require(p == 0xFF, "generic duplicate refused");
  }
  for (uint64_t k : ref) { const KV *f = t.get({k, 0}); require(f && f->k == k, "generic key found"); }
  for (uint32_t i = 0; i < 10000; ++i) { KV r{rng(), 0}; if (!ref.count(r.k)) require(!t.get(r), "generic absent key misses"); }
  std::printf("generic KV row: stored=%u PASS\n", stored);
}

int main() {
  generic();
  for (double load : {0.5, 0.8, 0.9, 0.95, 0.99}) run(load);
  std::puts("PASS");
}
