// Replays a recorded attrset trace (see trace.patch) against lookup structures.
//   c++ -std=c++20 -O2 -isysroot $(xcrun --show-sdk-path) -o /tmp/replay experiments/attrs/replay.cpp
//   /tmp/replay /tmp/attr2-toplevel.trace
//
// Measures the structures on the real sequence of lookups (hot: original order, cold:
// shuffled, which defeats temporal locality; the evaluator lies between the two).
// Index builds are done before timing and reported separately, so a structure is
// judged on its best case: if it cannot win with free builds, it cannot win.
#include "krapivin.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <random>
#include <vector>

using namespace krapivin;
using clk = std::chrono::steady_clock;
static double msSince(clk::time_point t) { return std::chrono::duration<double, std::milli>(clk::now() - t).count(); }

struct Attr {  // same shape as nixev::Attr: 24 bytes
  uint32_t name, pad;
  void *value;
  const void *pos;
};
struct Hdr {   // stands in for nixev::Bindings (+ a few words of per-set state)
  uint32_t n, lookups;
  uint64_t mask;
  void *idx;
  Attr attrs[1];
};

struct Arena {
  std::vector<char *> chunks;
  char *cur = nullptr, *end = nullptr;
  Hdr *alloc(uint32_t n) {
    size_t bytes = offsetof(Hdr, attrs) + (size_t)n * sizeof(Attr);
    bytes = (bytes + 7) & ~size_t(7);
    if (cur + bytes > end) {
      size_t sz = std::max<size_t>(bytes, 64u << 20);
      cur = (char *)malloc(sz);
      end = cur + sz;
      chunks.push_back(cur);
    }
    Hdr *h = (Hdr *)cur;
    cur += bytes;
    memset(h, 0, offsetof(Hdr, attrs));
    h->n = n;
    return h;
  }
};

static uint32_t gNmin = 16, gKmin = 4;
static uint64_t gOverflow = 0;

static inline const Attr *bsearch(const Hdr *h, uint32_t s) {
  size_t lo = 0, hi = h->n;
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (h->attrs[mid].name < s) lo = mid + 1;
    else hi = mid;
  }
  return lo < h->n && h->attrs[lo].name == s ? &h->attrs[lo] : nullptr;
}

// ---- strategies ------------------------------------------------------------------------
struct StNull {
  static constexpr const char *name = "loop overhead only";
  static void prepare(Hdr *) {}
  static void release(Hdr *) {}
  static size_t extra(const Hdr *) { return 0; }
  static const Attr *find(const Hdr *h, uint32_t) { return h->n > 0x7fffffffu ? h->attrs : nullptr; }
};
struct StBinary : StNull {
  static constexpr const char *name = "binary search (today)";
  static const Attr *find(const Hdr *h, uint32_t s) { return bsearch(h, s); }
};
struct StMask32 : StNull {
  static constexpr const char *name = "32-bit key mask + binary search";
  static void prepare(Hdr *h) {
    uint32_t m = 0;
    for (uint32_t i = 0; i < h->n; i++) m |= 1u << (h->attrs[i].name & 31);
    h->mask = m;
  }
  static const Attr *find(const Hdr *h, uint32_t s) { return (h->mask >> (s & 31)) & 1 ? bsearch(h, s) : nullptr; }
};
struct StMask64 : StNull {
  static constexpr const char *name = "64-bit key mask + binary search";
  static void prepare(Hdr *h) {
    uint64_t m = 0;
    for (uint32_t i = 0; i < h->n; i++) m |= 1ull << (h->attrs[i].name & 63);
    h->mask = m;
  }
  static const Attr *find(const Hdr *h, uint32_t s) { return (h->mask >> (s & 63)) & 1 ? bsearch(h, s) : nullptr; }
};
struct StScan : StNull {  // contiguous names (4 B/key) scanned linearly for small sets
  static constexpr const char *name = "contiguous names, linear scan (n<=32)";
  static void prepare(Hdr *h) {
    if (h->n > 32) return;
    auto *a = new uint32_t[h->n];
    for (uint32_t i = 0; i < h->n; i++) a[i] = h->attrs[i].name;
    h->idx = a;
  }
  static void release(Hdr *h) { delete[] (uint32_t *)h->idx, h->idx = nullptr; }
  static size_t extra(const Hdr *h) { return h->idx ? h->n * 4 : 0; }
  static const Attr *find(const Hdr *h, uint32_t s) {
    if (!h->idx) return bsearch(h, s);
    const uint32_t *a = (const uint32_t *)h->idx;
    for (uint32_t i = 0; i < h->n; i++) {
      if (a[i] >= s) return a[i] == s ? &h->attrs[i] : nullptr;
    }
    return nullptr;
  }
};
struct StMaskScan : StScan {  // the mask first (rejects ~75% of misses), then the scan
  static constexpr const char *name = "32-bit mask + contiguous scan";
  static void prepare(Hdr *h) {
    StScan::prepare(h);
    StMask32::prepare(h);
  }
  static const Attr *find(const Hdr *h, uint32_t s) { return (h->mask >> (s & 31)) & 1 ? StScan::find(h, s) : nullptr; }
};

template <class Tab, class Make> struct StIndex : StNull {
  static void prepare(Hdr *h) {
    if (h->n < gNmin || h->lookups < gKmin) return;
    Tab *t = Make::make(h->n);
    for (uint32_t i = 0; i < h->n; i++)
      if (!t->insert(h->attrs[i].name, i)) {  // overflow: this set keeps binary search
        gOverflow++;
        delete t;
        return;
      }
    h->idx = t;
  }
  static void release(Hdr *h) { delete (Tab *)h->idx, h->idx = nullptr; }
  static size_t extra(const Hdr *h) { return h->idx ? ((Tab *)h->idx)->bytes() : 0; }
  static const Attr *find(const Hdr *h, uint32_t s) {
    if (!h->idx) return bsearch(h, s);
    const Slot *p = ((const Tab *)h->idx)->find(s);
    return p ? &h->attrs[p->val] : nullptr;
  }
};
struct MakeLin2 { static LinearTable *make(uint32_t n) { return new LinearTable(2 * n); } };
struct MakeLin87 { static LinearTable *make(uint32_t n) { return new LinearTable(capacityFor(n, 8)); } };
struct MakeFunnel { static Funnel *make(uint32_t n) { return new Funnel(capacityFor(n, 8), 8); } };
struct MakeElastic { static Elastic *make(uint32_t n) { return new Elastic(capacityFor(n, 8), 8); } };
struct StLin2 : StIndex<LinearTable, MakeLin2> { static constexpr const char *name = "linear probing, load 50%"; };
struct StLin87 : StIndex<LinearTable, MakeLin87> { static constexpr const char *name = "linear probing, load 87.5% (same slots as below)"; };
struct StFunnel : StIndex<Funnel, MakeFunnel> { static constexpr const char *name = "funnel hashing, delta=1/8"; };
struct StElastic : StIndex<Elastic, MakeElastic> { static constexpr const char *name = "elastic hashing, delta=1/8"; };

// ---- harness ---------------------------------------------------------------------------
struct Workload {
  std::vector<Hdr *> sets;             // all sets, in creation order
  std::vector<Hdr *> hs;               // per lookup: the set
  std::vector<uint32_t> syms;          // per lookup: the symbol
  std::vector<Hdr *> hsCold;
  std::vector<uint32_t> symsCold;
  uint64_t entries = 0, merged = 0, mergedEntries = 0;
};

static bool rawOut = false;
template <class S> void run(const Workload &w, uint64_t refHits, double nullHot, double nullCold, double nullTp) {
  clk::time_point t = clk::now();
  for (Hdr *h : w.sets) S::prepare(h);
  double build = msSince(t);
  size_t extra = 0;
  for (Hdr *h : w.sets) extra += S::extra(h);
  // Dependent chain: the next lookup's index depends on this lookup's result (adds 0: the top
  // bit of a user-space pointer is never set), so loads cannot overlap across lookups.  That is
  // how the evaluator experiences them; the throughput loop shows what overlap would hide.
  auto chain = [&](const std::vector<Hdr *> &hs, const std::vector<uint32_t> &sy, uint64_t &hits) {
    double best = 1e18;
    for (int rep = 0; rep < 3; rep++) {
      hits = 0;
      size_t i = 0, N = hs.size();
      clk::time_point t0 = clk::now();
      while (i < N) {
        const Attr *p = S::find(hs[i], sy[i]);
        hits += p != nullptr;
        i += 1 + (reinterpret_cast<uintptr_t>(p) >> 63);
      }
      best = std::min(best, msSince(t0));
    }
    return best;
  };
  auto tput = [&](const std::vector<Hdr *> &hs, const std::vector<uint32_t> &sy) {
    double best = 1e18;
    for (int rep = 0; rep < 3; rep++) {
      uint64_t hits = 0;
      clk::time_point t0 = clk::now();
      for (size_t i = 0; i < hs.size(); i++) hits += S::find(hs[i], sy[i]) != nullptr;
      best = std::min(best, msSince(t0));
      if (hits > hs.size()) abort();
    }
    return best;
  };
  uint64_t hits1, hits2;
  double hot = chain(w.hs, w.syms, hits1), cold = chain(w.hsCold, w.symsCold, hits2), tp = tput(w.hs, w.syms);
  double n = w.hs.size();
  if (rawOut) printf("   [raw ms: chain-hot %.1f chain-cold %.1f throughput %.1f]\n", hot, cold, tp);
  printf("%-46s chain: hot %5.1f cold %6.1f | throughput %5.1f ns/lookup | build %6.1f ms | +%6.1f MB | %s\n", S::name, (hot - nullHot) * 1e6 / n, (cold - nullCold) * 1e6 / n,
         (tp - nullTp) * 1e6 / n, build, extra / 1e6, (hits1 == refHits && hits2 == refHits) ? "ok" : "WRONG HIT COUNT");
  for (Hdr *h : w.sets) S::release(h);
}


// ---- per-size breakdown ----------------------------------------------------------------
static int bucketOf(uint32_t n) { return n < 8 ? 0 : n < 32 ? 1 : n < 128 ? 2 : 3; }
static const char *kBucketName[4] = {"<8", "8-31", "32-127", ">=128"};
struct Buckets {
  std::vector<Hdr *> hs[4], hsCold[4];
  std::vector<uint32_t> sy[4], syCold[4];
};
template <class S> double chainTime(const std::vector<Hdr *> &hs, const std::vector<uint32_t> &sy, int reps = 5) {
  double best = 1e18;
  for (int rep = 0; rep < reps; rep++) {
    size_t i = 0, N = hs.size();
    uint64_t hits = 0;
    clk::time_point t0 = clk::now();
    while (i < N) {
      const Attr *p = S::find(hs[i], sy[i]);
      hits += p != nullptr;
      i += 1 + (reinterpret_cast<uintptr_t>(p) >> 63);
    }
    best = std::min(best, msSince(t0));
    if (hits > N) abort();
  }
  return best;
}
template <class S> void runBuckets(const Workload &w, const Buckets &b, const char *label) {
  for (Hdr *h : w.sets) S::prepare(h);
  printf("%-40s", label);
  double tot = 0, totc = 0;
  for (int k = 0; k < 4; k++) {
    double hot = chainTime<S>(b.hs[k], b.sy[k]), cold = chainTime<S>(b.hsCold[k], b.syCold[k]);
    tot += hot, totc += cold;
    printf(" | %6.1f %6.1f", hot * 1e6 / std::max<size_t>(1, b.hs[k].size()), cold * 1e6 / std::max<size_t>(1, b.hs[k].size()));
  }
  printf(" | total %6.1f %6.1f ms\n", tot, totc);
  for (Hdr *h : w.sets) S::release(h);
}

int main(int argc, char **argv) {
  if (argc < 2) return fprintf(stderr, "usage: replay trace\n"), 2;
  FILE *f = fopen(argv[1], "rb");
  if (!f) return perror("trace"), 2;
  fseek(f, 0, SEEK_END);
  size_t words = ftell(f) / 4;
  fseek(f, 0, SEEK_SET);
  std::vector<uint32_t> ev(words);
  if (fread(ev.data(), 4, words, f) != words) return 2;
  fclose(f);

  Workload w;
  Arena arena;
  std::vector<Hdr *> byId(1);
  for (size_t i = 0; i < words;) {
    uint32_t x = ev[i];
    if (x & 0x80000000u) {  // define
      uint32_t n = x & 0x7fffffffu, id = ev[i + 1];
      Hdr *h = arena.alloc(n);
      for (uint32_t k = 0; k < n; k++) h->attrs[k].name = ev[i + 2 + k];
      if (byId.size() <= id) byId.resize(id + 1);
      byId[id] = h;
      w.sets.push_back(h);
      w.entries += n;
      i += 2 + n;
    } else if (x == 0x40000000u) {  // update: R wins on equal names
      Hdr *l = byId[ev[i + 1]], *r = byId[ev[i + 2]];
      uint32_t id = ev[i + 3];
      Hdr *h = arena.alloc(l->n + r->n);
      uint32_t a = 0, b = 0, n = 0;
      while (a < l->n && b < r->n) {
        if (l->attrs[a].name == r->attrs[b].name) h->attrs[n++] = r->attrs[b++], a++;
        else if (l->attrs[a].name < r->attrs[b].name) h->attrs[n++] = l->attrs[a++];
        else h->attrs[n++] = r->attrs[b++];
      }
      while (a < l->n) h->attrs[n++] = l->attrs[a++];
      while (b < r->n) h->attrs[n++] = r->attrs[b++];
      h->n = n;
      if (byId.size() <= id) byId.resize(id + 1);
      byId[id] = h;
      w.sets.push_back(h);
      w.merged++, w.mergedEntries += n;
      i += 4;
    } else {  // lookup
      Hdr *h = byId[x];
      h->lookups++;
      w.hs.push_back(h);
      w.syms.push_back(ev[i + 1]);
      i += 2;
    }
  }
  ev.clear();
  ev.shrink_to_fit();
  std::vector<size_t> perm(w.hs.size());
  std::iota(perm.begin(), perm.end(), 0);
  std::shuffle(perm.begin(), perm.end(), std::mt19937_64(7));
  for (size_t p : perm) w.hsCold.push_back(w.hs[p]), w.symsCold.push_back(w.syms[p]);

  uint64_t big = 0, small = 0;
  for (size_t i = 0; i < w.hs.size(); i++) (w.hs[i]->n >= 64 ? big : small)++;
  printf("trace %s: %zu sets (%llu entries, %llu from //), %zu lookups (%.1f%% in sets of >=64 entries)\n", argv[1], w.sets.size(), (unsigned long long)w.entries,
         (unsigned long long)w.merged, w.hs.size(), 100.0 * big / w.hs.size());

  // reference hit count and loop overhead
  uint64_t refHits = 0;
  for (size_t i = 0; i < w.hs.size(); i++) refHits += bsearch(w.hs[i], w.syms[i]) != nullptr;
  auto nullChain = [&](const std::vector<Hdr *> &hs, const std::vector<uint32_t> &sy) {
    double best = 1e18;
    for (int rep = 0; rep < 3; rep++) {
      size_t i = 0, N = hs.size();
      clk::time_point t0 = clk::now();
      while (i < N) {
        const Attr *p = StNull::find(hs[i], sy[i]);
        i += 1 + (reinterpret_cast<uintptr_t>(p) >> 63);
      }
      best = std::min(best, msSince(t0));
    }
    return best;
  };
  auto nullTput = [&]() {
    double best = 1e18;
    for (int rep = 0; rep < 3; rep++) {
      uint64_t h = 0;
      clk::time_point t0 = clk::now();
      for (size_t i = 0; i < w.hs.size(); i++) h += StNull::find(w.hs[i], w.syms[i]) != nullptr;
      best = std::min(best, msSince(t0));
      if (h) abort();
    }
    return best;
  };
  double nh = nullChain(w.hs, w.syms), nc = nullChain(w.hsCold, w.symsCold), nt = nullTput();
  rawOut = true;
  printf("loop overhead (subtracted): chain-hot %.1f ms, chain-cold %.1f ms, throughput %.1f ms;  reference hits %llu (%.1f%%)\n\n", nh, nc, nt, (unsigned long long)refHits,
         100.0 * refHits / w.hs.size());

  run<StBinary>(w, refHits, nh, nc, nt);
  rawOut = false;
  run<StMask32>(w, refHits, nh, nc, nt);
  run<StMask64>(w, refHits, nh, nc, nt);
  run<StScan>(w, refHits, nh, nc, nt);
  run<StMaskScan>(w, refHits, nh, nc, nt);
  for (uint32_t nmin : {8u, 32u, 128u}) {
    gNmin = nmin;
    printf("-- index for sets with >= %u entries and >= %u lookups\n", nmin, gKmin);
    run<StLin2>(w, refHits, nh, nc, nt);
    run<StLin87>(w, refHits, nh, nc, nt);
    run<StFunnel>(w, refHits, nh, nc, nt);
    run<StElastic>(w, refHits, nh, nc, nt);
  }
  printf("(index overflows, sets that fell back to binary search: %llu)\n", (unsigned long long)gOverflow);

  // Per set size: ns per lookup (dependent chain), hot and cold.  The baseline is repeated to expose drift.
  Buckets b;
  for (size_t i = 0; i < w.hs.size(); i++) b.hs[bucketOf(w.hs[i]->n)].push_back(w.hs[i]), b.sy[bucketOf(w.hs[i]->n)].push_back(w.syms[i]);
  for (size_t i = 0; i < w.hsCold.size(); i++) b.hsCold[bucketOf(w.hsCold[i]->n)].push_back(w.hsCold[i]), b.syCold[bucketOf(w.hsCold[i]->n)].push_back(w.symsCold[i]);
  printf("\n== by set size: ns/lookup (hot cold) per bucket, dependent chain;  lookups per bucket:");
  for (int k = 0; k < 4; k++) printf("  %s: %zu (%.1f%%)", kBucketName[k], b.hs[k].size(), 100.0 * b.hs[k].size() / w.hs.size());
  printf("\n%-40s", "");
  for (int k = 0; k < 4; k++) printf(" | %-13s", kBucketName[k]);
  printf("\n");
  gNmin = 8;
  runBuckets<StBinary>(w, b, "binary search (today) #1");
  runBuckets<StMask32>(w, b, "32-bit mask + binary");
  runBuckets<StLin2>(w, b, "linear probing 50% (n>=8)");
  runBuckets<StFunnel>(w, b, "funnel 1/8 (n>=8)");
  runBuckets<StElastic>(w, b, "elastic 1/8 (n>=8)");
  runBuckets<StBinary>(w, b, "binary search (today) #2 (drift check)");
  gNmin = 128;
  runBuckets<StLin2>(w, b, "linear probing 50% (n>=128)");
  runBuckets<StFunnel>(w, b, "funnel 1/8 (n>=128)");
  runBuckets<StBinary>(w, b, "binary search (today) #3 (drift check)");
  return 0;
}
