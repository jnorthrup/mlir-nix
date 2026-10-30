// The pure zone's vocabulary against the standard library it replaces: Fn (std::function), Maybe (std::optional), Text (ostringstream,
// std::to_string), the Spill body (llvm::SmallVector, checked against std::vector) and WordTable (DenseMap, checked against
// std::unordered_map).
//   clang++ -std=c++20 -O1 -g -fsanitize=address,undefined -I include scripts/vocab-check.cc -o /tmp/vocab-check && /tmp/vocab-check
#include "Composite/Table.h"
#include "Composite/Text.h"
#include "Composite/Vocab.h"
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unordered_map>
#include <vector>

using namespace composite;

static uint64_t s = 0x9E3779B97F4A7C15ull;
static uint64_t rng() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
static void require(bool ok, const char *what) {
  if (!ok) { std::printf("FAIL: %s\n", what); std::exit(1); }
}

static int apply(Fn<int(int)> f, int x) { return f ? f(x) : -1; }

int main() {
  // Fn: a lambda with captures, by reference; a null one is false.
  int k = 7;
  auto add = [&](int x) { return x + k; };
  require(apply(add, 5) == 12, "Fn calls its callable");
  k = 10;
  require(apply(add, 5) == 15, "Fn refers to the callable, not a copy");
  require(apply(nullptr, 5) == -1, "a null Fn is false");

  // Maybe.
  Maybe<std::string> none, some(std::string("x"));
  require(!none && some && *some == "x" && none.or_("d") == "d", "Maybe holds a value or nothing");

  // Text: integers, hex, C strings, against snprintf.
  for (int i = 0; i < 100000; i++) {
    int64_t x = int64_t(rng());
    if (i % 3 == 0) x >>= rng() % 63;
    if (i == 0) x = INT64_MIN;
    if (i == 1) x = 0;
    char want[64];
    std::snprintf(want, sizeof want, "%" PRId64 " %" PRIx64 " %08" PRIx64, x, uint64_t(x), uint64_t(x) & 0xffff);
    Text t;
    t.putInt(x).put(' ').putHex(uint64_t(x)).put(' ').putHex(uint64_t(x) & 0xffff, 8);
    require(std::string(t.cstr()) == want, "Text writes integers as printf does");
  }
  Text u;
  u.put("ab").put(Text("cd", 2)).put('e');
  require(u.size() == 5 && std::string(u.cstr()) == "abcde" && u.size() == 5, "Text appends runs, and cstr() adds an uncounted NUL");

  // Spill: inline, then the heap; moves of an inline and of a spilled series; non-plain cells.
  for (int round = 0; round < 2000; round++) {
    MutableSeries<std::string, Spill<std::string, 4>> a;
    std::vector<std::string> ref;
    uint32_t m = uint32_t(rng() % 40);
    for (uint32_t i = 0; i < m; i++) {
      std::string v = std::to_string(rng()) + std::string(rng() % 30, 'x');
      a.append(v);
      ref.push_back(v);
      if (rng() % 7 == 0 && !ref.empty()) { a.pop(); ref.pop_back(); }
    }
    MutableSeries<std::string, Spill<std::string, 4>> b(mv(a));
    require(a.size() == 0 && b.size() == ref.size(), "a moved spill leaves the source empty");
    for (uint32_t i = 0; i < b.size(); i++) require(b[i] == ref[i], "a moved spill keeps its cells, inline or not");
    MutableSeries<std::string, Spill<std::string, 4>> c;
    c.append("z");
    c = mv(b);
    require(c.size() == ref.size(), "move-assignment takes the cells");
    for (uint32_t i = 0; i < c.size(); i++) require(c[i] == ref[i], "move-assignment keeps them in order");
  }
  MutableSeries<uint32_t, Spill<uint32_t, 8>> p;
  for (uint32_t i = 0; i < 1000; i++) p.append(i * 3);
  for (uint32_t i = 0; i < 1000; i++) require(p[i] == i * 3, "a plain spill grows past its inline cells");

  // WordTable against unordered_map: random words, repeated inserts, misses.
  WordTable<uint64_t> w;
  std::unordered_map<uint64_t, uint64_t> wr;
  for (int i = 0; i < 200000; i++) {
    uint64_t key = (rng() % 50000) + 1, v = rng();
    bool fresh = !wr.count(key);
    require(w.insert(key, v) == fresh, "insert says whether the key was new");
    if (fresh) wr[key] = v;
  }
  require(w.size() == wr.size(), "one cell a key");
  for (auto &[key, v] : wr) require(w.find(key) && *w.find(key) == v, "every key found with its first value");
  for (int i = 0; i < 100000; i++) {
    uint64_t key = rng() | (uint64_t(1) << 63);
    require(!w.find(key) == !wr.count(key), "a key never stored misses");
  }
  w.at(123456789) = 5;
  require(*w.find(123456789) == 5, "at() makes the value when absent");
  uint64_t visited = 0;
  w.each([&](uint64_t, uint64_t) { visited++; });
  require(visited == w.size(), "each visits every cell once");
  w.clear();
  require(w.size() == 0 && !w.find(123456789), "clear empties the table");
  require(w.insert(77, 1) && *w.find(77) == 1, "a cleared table takes keys again");

  // TextTable and Bump against unordered_map<string>: names of every length, values replaced, misses.
  Bump bump;
  TextTable<uint32_t> tt;
  std::unordered_map<std::string, uint32_t> tr;
  for (int i = 0; i < 100000; i++) {
    std::string k = "name" + std::to_string(rng() % 30000) + std::string(rng() % 3 ? 0 : rng() % 200000, 'q');
    uint32_t v = uint32_t(rng());
    tt.set(k.data(), uint32_t(k.size()), v, [&] { return bump.copy(k.data(), uint32_t(k.size())); });
    tr[k] = v;
  }
  require(tt.size() == tr.size(), "one row a byte string");
  for (auto &[k, v] : tr) require(tt.find(k.data(), uint32_t(k.size())) && *tt.find(k.data(), uint32_t(k.size())) == v, "found with its last value");
  for (int i = 0; i < 50000; i++) {
    std::string k = "other" + std::to_string(rng());
    require(!tt.find(k.data(), uint32_t(k.size())), "bytes never stored miss");
  }
  require(tt.find("", 0) == nullptr && *tt.set("", 0, 9, [&] { return bump.copy("", 0); }) == 9 && *tt.find("", 0) == 9, "the empty string is a key");
  std::printf("vocabulary: Fn, Maybe, Text (100000 numbers), Spill (2000 rounds of moves), WordTable, TextTable (%u names) PASS\n", tt.size());
}
