// The pure zone's vocabulary against the standard library it replaces: Fn (std::function), Maybe (std::optional), Own (std::unique_ptr), Text (std::string,
// ostringstream, std::to_string), eachWord and eachLine (a stream's >> and getline), the Spill body (llvm::SmallVector, checked against std::vector), WordTable
// (DenseMap, checked against std::unordered_map) and TextSet (std::unordered_set<std::string>).
//   clang++ -std=c++20 -O1 -g -fsanitize=address,undefined -I include scripts/vocab-check.cc -o /tmp/vocab-check && /tmp/vocab-check
#include "Composite/Table.h"
#include "Composite/Text.h"
#include "Composite/Vocab.h"
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <unordered_set>
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

  // Text against std::string: random writes of every kind of piece (C string, run, window, view, char, number, another Text, a part of itself),
  // truncation, erase, insert and resize; after each, every search, comparison and conversion on the result.  The NUL always follows the last byte.
  {
    auto eq = [](const Text &t, const std::string &r) { return t.size() == r.size() && std::string_view(t) == r && t.c_str()[t.size()] == 0; };
    auto piece = [](int maxLen) {
      std::string p(rng() % (maxLen + 1), 'a');
      for (char &c : p) c = "ab/c. \t-x"[rng() % 9];
      return p;
    };
    Text t;
    std::string r;
    for (int op = 0; op < 60000; op++) {
      std::string a = piece(6);
      switch (rng() % 21) {
      case 0: t.put(a.c_str()); r += a.c_str(); break;
      case 1: t.put(a.data(), a.size()); r += a; break;
      case 2: t.put(std::string_view(a)); r += a; break;
      case 3: t.put(chars(a.data(), uint32_t(a.size()))); r += a; break;
      case 4: { char c = "xyz/"[rng() % 4]; t += c; r += c; break; }
      case 5: t += a.c_str(); r += a.c_str(); break;
      case 6: { Text o(a.data(), a.size()); t += o; r += a; break; }
      case 7: { int64_t v = int64_t(rng()) >> (rng() % 60); t.putInt(v); r += std::to_string((long long)v); break; }
      case 8: if (r.size() > 20) { t.clear(); r.clear(); } break;
      case 9: { size_t n = r.empty() ? 0 : rng() % (r.size() + 1); t.truncate(n); r.resize(n); break; }
      case 10: if (!r.empty()) { t.pop_back(); r.pop_back(); } break;
      case 11: { size_t at = r.empty() ? 0 : rng() % (r.size() + 1), n = rng() % 5; t.erase(at, n); r.erase(at, n); break; }
      case 12: { size_t at = r.empty() ? 0 : rng() % (r.size() + 1); t.insert(at, a.c_str()); r.insert(at, a); break; }
      case 13: { size_t n = rng() % 40; t.resize(n, 'q'); r.resize(n, 'q'); break; }
      case 14: { Text c = t.clone(); require(eq(c, r), "clone copies the bytes"); t.put(c); r += std::string(r); break; }
      case 15: if (!r.empty()) { t.put(t); r += std::string(r); } break; // a write of itself, through the window
      case 16: { Text x = a + t; require(eq(x, a + r), "piece + Text"); break; }
      case 17: { Text x = Text(t.clone()) + "/" + a + '!'; require(eq(x, r + "/" + a + '!'), "Text + pieces, one run"); break; }
      case 18: { Text u = cat("n=", 42, ' ', a, -7L, uint64_t(18446744073709551615ull)); require(eq(u, "n=42 " + a + "-718446744073709551615"), "cat writes pieces and decimal numbers"); break; }
      case 19: require(str(12345).size() == 5 && str(-9) == "-9" && str(INT64_MIN) == std::to_string(INT64_MIN), "str is std::to_string"); break;
      default: t.swap(t); break;
      }
      require(eq(t, r), "Text and std::string hold the same bytes");
      std::string n = piece(3);
      char c = "ab/c. \t-x"[rng() % 9];
      size_t from = rng() % (r.size() + 2);
      if (rng() % 5 == 0) from = std::string::npos;
      require(t.find(c, from) == r.find(c, from) && t.find(n.c_str(), from) == r.find(n, from) && t.find(std::string_view(n), from) == r.find(n, from), "find");
      require(t.rfind(c, from) == r.rfind(c, from) && t.rfind(n.c_str(), from) == r.rfind(n, from), "rfind");
      require(t.find_first_of(n.c_str(), from) == r.find_first_of(n, from) && t.find_last_of(n.c_str(), from) == r.find_last_of(n, from), "find_first_of, find_last_of");
      require(t.find_first_not_of(n.c_str(), from) == r.find_first_not_of(n, from) && t.find_last_not_of(n.c_str(), from) == r.find_last_not_of(n, from), "find_first_not_of, find_last_not_of");
      require(t.starts_with(n.c_str()) == r.starts_with(n) && t.ends_with(n.c_str()) == r.ends_with(n) && t.starts_with(c) == r.starts_with(c) && t.ends_with(c) == r.ends_with(c), "starts_with, ends_with");
      require(t.contains(n.c_str()) == (r.find(n) != std::string::npos), "contains");
      size_t sp = r.empty() ? 0 : rng() % (r.size() + 1), sn = rng() % 8;
      Chars w = t.substr(sp, sn);
      require(std::string_view(w) == r.substr(sp, sn), "substr is a window on the same bytes");
      std::string other = piece(5);
      Text o(other.data(), other.size());
      require((t == other.c_str()) == (r == other) && (t < other.c_str()) == (r < other) && (t > other.c_str()) == (r > other), "== < > against a C string");
      require((t <= other.c_str()) == (r <= other) && (t >= other.c_str()) == (r >= other) && (t != other.c_str()) == (r != other), "<= >= != against a C string");
      require((t == o) == (r == other) && (t < o) == (r < other) && (t == std::string_view(other)) == (r == other), "== < against a Text and a view");
      require(compare(t.chars(), o.chars()) == (r < other ? -1 : r > other ? 1 : 0), "compare");
      std::string_view sv = t;
      Chars win = t;
      require(sv == r && win.size() == r.size(), "a Text converts to a view and to a window");
      require(startsWith(win, o.chars()) == r.starts_with(other) && endsWith(win, o.chars()) == r.ends_with(other), "startsWith, endsWith");
      require(find(win, o.chars(), from) == r.find(other, from) && rfind(win, o.chars(), from) == r.rfind(other, from), "find, rfind on a window");
    }
    // a Text that has not held a byte: reads give the NUL, and erase, truncate, clear, insert and a write of nothing leave it empty and usable
    {
      Text e;
      require(e[0] == 0 && e.size() == 0 && e.c_str()[0] == 0, "an unwritten Text reads as empty with a NUL at [0]");
      Text f;
      f.erase(0, 5).truncate(0);
      f.clear();
      f.put("", size_t(0));
      require(f.size() == 0 && f.c_str()[0] == 0 && f == "", "erase, truncate, clear and an empty put on an unwritten Text do nothing");
      Text g;
      g.insert(0, "ab");
      require(g == "ab" && g.c_str()[2] == 0, "insert into an unwritten Text");
    }
    // a series of Texts grows by moving them; Maybe<Text> holds one; nothing is copied, nothing lost
    MutableSeries<Text> many;
    for (int i = 0; i < 3000; i++) many.append(cat("row ", i, std::string(rng() % 40, 'z')));
    bool all = many.size() == 3000;
    for (int i = 0; i < 3000 && all; i++) all = std::string_view(many[uint32_t(i)]).starts_with("row " + std::to_string(i));
    require(all, "MutableSeries<Text> moves its cells when it grows");
    Maybe<Text> mt(Text("held")), nt;
    require(mt && !nt && *mt == "held" && mt->size() == 4, "Maybe<Text> holds a Text");
  }

  // eachWord against a stream's >>, eachLine against getline: every mix of separators, the empty string and a lone separator included.
  for (int round = 0; round < 20000; round++) {
    static const char alphabet[] = "ab \t\n\v\f\r";
    std::string text(rng() % 24, ' ');
    for (char &c : text) c = alphabet[rng() % (sizeof alphabet - 1)];
    std::vector<std::string> want, got;
    std::istringstream words(text);
    for (std::string x; words >> x;) want.push_back(x);
    eachWord(text.data(), uint32_t(text.size()), [&](const char *p, uint32_t n) { got.emplace_back(p, n); });
    require(got == want, "eachWord splits where a stream's >> does");
    want.clear();
    got.clear();
    std::istringstream lines(text);
    for (std::string x; std::getline(lines, x);) want.push_back(x);
    eachLine(text.data(), uint32_t(text.size()), [&](const char *p, uint32_t n) { got.emplace_back(p, n); });
    require(got == want, "eachLine splits where getline does");
  }

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
  // A table mostly empty when cleared is made small first; one mostly full is emptied in place.  Either way it takes keys again.
  for (int round = 0; round < 3; round++) {
    for (uint64_t i = 1; i <= 100000; i++) w.insert(i * 7919, i);
    w.clear();
    for (uint64_t i = 1; i <= 10; i++) w.insert(i, i);
    w.clear(); // ten keys in a table sized for a hundred thousand: the small one
    require(w.size() == 0 && !w.find(3) && !w.find(7919), "a cleared table is empty, made small or not");
    for (uint64_t i = 1; i <= 1000; i++) require(w.insert(i, i * 2), "a table made small takes keys");
    for (uint64_t i = 1; i <= 1000; i++) require(*w.find(i) == i * 2, "and finds them");
    w.clear();
  }

  // Own: one owner, moved, released, converted to a base; destroyed once, never twice, never forgotten.
  static int alive = 0;
  struct Base { virtual ~Base() { --alive; } Base() { ++alive; } };
  struct Derived : Base { int x; explicit Derived(int x) : x(x) {} };
  {
    Own<Derived> a = own<Derived>(5);
    require(alive == 1 && a && a->x == 5, "own makes the object");
    Own<Derived> b(mv(a));
    require(!a && b && alive == 1, "a move hands it over");
    Own<Base> c(mv(b));
    require(!b && c && alive == 1, "an owner of the base takes it");
    Derived *raw = static_cast<Derived *>(c.release());
    require(!c && alive == 1 && raw->x == 5, "release gives it up");
    delete raw;
    require(alive == 0, "and the taker deletes it");
    MutableSeries<Own<Derived>> many;
    for (int i = 0; i < 1000; i++) many.append(own<Derived>(i));
    require(alive == 1000, "a growing series of owners moves them, deleting none");
    for (int i = 0; i < 1000; i++) require(many[i]->x == i, "each keeps its object");
    many[7] = nullptr;
    require(alive == 999, "assigning null deletes");
  }
  require(alive == 0, "every owner deletes its object when it goes");

  // Atomic: four threads add to one word, a compare-exchange takes it only from the value it names.
  {
    Atomic<uint64_t> sum{0};
    std::thread ts[4];
    for (auto &t : ts) t = std::thread([&] { for (int i = 0; i < 250000; i++) sum.fetch_add(1); });
    for (auto &t : ts) t.join();
    require(sum.load() == 1000000, "fetch_add from four threads loses nothing");
    uint64_t want = 5;
    require(!sum.compare_exchange(want, 9) && want == 1000000, "a compare-exchange from the wrong value fails and says the value");
    require(sum.compare_exchange(want, 9) && sum.load() == 9, "and from the right one takes");
  }

  // TextTable and Bump against unordered_map<string>: names of every length (one in 300 up to 200,000 bytes, so a block of its own and a
  // few dozen MB, not seven GB), values replaced, misses.
  Bump bump;
  TextTable<uint32_t> tt;
  std::unordered_map<std::string, uint32_t> tr;
  for (int i = 0; i < 100000; i++) {
    std::string k = "name" + std::to_string(rng() % 30000) + std::string(rng() % 300 ? 0 : rng() % 200000, 'q');
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
  // TextSet against unordered_set<string>: the first of equal strings is the new one, the members come back in the order they came.
  TextSet ts;
  std::unordered_set<std::string> sr;
  std::vector<std::string> arrived;
  for (int i = 0; i < 100000; i++) {
    std::string k = "member" + std::to_string(rng() % 40000) + std::string(rng() % 5 ? 0 : rng() % 3000, 'z');
    bool fresh = sr.insert(k).second;
    require(ts.insert(k.data(), uint32_t(k.size())) == fresh, "insert says whether the bytes were new");
    if (fresh) arrived.push_back(k);
    require(ts.contains(k.data(), uint32_t(k.size())), "a member is found");
  }
  require(ts.size() == sr.size() && ts.size() == arrived.size(), "one member a byte string");
  uint32_t at = 0;
  for (const auto &r : ts) require(std::string(r.p, r.n) == arrived[at++], "members come back in the order they came");
  for (int i = 0; i < 50000; i++) {
    std::string k = "stranger" + std::to_string(rng());
    require(!ts.contains(k.data(), uint32_t(k.size())), "bytes never inserted are not members");
  }
  require(!ts.contains("", 0) && ts.insert("", 0) && ts.contains("", 0) && !ts.insert("", 0), "the empty string is a member");
  std::printf("vocabulary: Fn, Maybe, Text (100000 numbers; 60000 random operations against std::string), eachWord and eachLine (20000 strings), Spill (2000 rounds of moves), WordTable, TextTable (%u names), TextSet (%u members) PASS; Own, Atomic\n", tt.size(), ts.size());
}
