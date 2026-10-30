// Composite/Patricia.h against std::map: path-shaped keys with long shared prefixes, every key found, a value replaced, a key never
// stored missed, the rows in byte order, and each prefix's rows exactly the map's range for it.
//   clang++ -std=c++20 -O2 -g -fsanitize=address,undefined -I include scripts/patricia-check.cc -o /tmp/patricia-check && /tmp/patricia-check
#include "Composite/Patricia.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <map>
#include <string>

using namespace composite;

static uint64_t s = 0x2545F4914F6CDD1Dull;
static uint64_t rng() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
static void require(bool ok, const char *what) {
  if (!ok) { std::printf("FAIL: %s\n", what); std::exit(1); }
}

static std::string path() {
  static const char *parts[] = {"nix", "store", "pkgs", "lib", "by-name", "development", "default.nix", "a", "ab", "abc", "b", "x-1.2",
                                "x-1.2.3", "glibc", "2.40-master.patch", "setup.sh", "nixos", "modules", "services"};
  std::string p = "/Users/jim/work/mlir-nix/.cache/nixpkgs";
  for (uint32_t d = 0, n = 1 + rng() % 6; d < n; d++) p += "/" + std::string(parts[rng() % 19]);
  if (rng() % 4 == 0) p += std::to_string(rng() % 100);
  return p;
}

int main() {
  std::deque<std::string> keys; // the copies the trie holds: they outlive it, and are freed with the test
  Patricia<uint64_t> t;
  std::map<std::string, uint64_t> ref;
  for (uint32_t i = 0; i < 40000; i++) {
    std::string k = path();
    uint64_t v = rng();
    bool fresh = !ref.count(k);
    bool copied = false;
    uint64_t *got = t.set(k.data(), uint32_t(k.size()), v, [&] { copied = true; return keys.emplace_back(k).c_str(); });
    require(copied == fresh, "a key's bytes are copied once, when it is new");
    require(got && *got == v, "set hands back the value");
    ref[k] = v;
  }
  require(t.size() == ref.size(), "one row a key");
  for (auto &[k, v] : ref) {
    uint64_t *f = t.find(k.data(), uint32_t(k.size()));
    require(f && *f == v, "every key found with its last value");
  }
  for (uint32_t i = 0; i < 20000; i++) {
    std::string k = path() + "/never";
    if (!ref.count(k)) require(!t.find(k.data(), uint32_t(k.size())), "a key never stored misses");
    std::string cut = k.substr(0, k.size() / 2);
    if (!ref.count(cut)) require(!t.find(cut.data(), uint32_t(cut.size())), "a prefix of keys is not a key");
  }
  // Byte order: the whole trie is the empty prefix's subtree.
  auto it = ref.begin();
  uint32_t seen = 0;
  t.prefix("", 0, [&](const Patricia<uint64_t>::Row &r) {
    require(it != ref.end() && std::string(r.key, r.len) == it->first && r.v == it->second, "rows in byte order");
    ++it, ++seen;
  });
  require(seen == ref.size(), "the walk reaches every row");
  for (uint32_t i = 0; i < 2000; i++) {
    std::string k = path();
    std::string pre = k.substr(0, rng() % (k.size() + 1));
    auto lo = ref.lower_bound(pre);
    uint32_t n = 0;
    t.prefix(pre.data(), uint32_t(pre.size()), [&](const Patricia<uint64_t>::Row &r) {
      require(lo != ref.end() && lo->first.compare(0, pre.size(), pre) == 0 && std::string(r.key, r.len) == lo->first, "a prefix's rows, in order");
      ++lo, ++n;
    });
    require(lo == ref.end() || lo->first.compare(0, pre.size(), pre) != 0, "a prefix's walk misses none of its rows");
  }
  std::printf("patricia: %u paths, byte order, prefix walks PASS\n", t.size());
}
