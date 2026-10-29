// CharSeries, as ../TrikeShed/src/commonMain/kotlin/borg/trikeshed/lib/CharSeries.kt specifies it: windows that never copy and flatten,
// the cursor verbs, equality by the content of pos..limit, no hash, and the lazy split.  Build like minmax-check.cc.
#include "Composite/CharSeries.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <type_traits>
#include <unordered_set>
using namespace composite;
static void require(bool ok, const char *m) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", m); std::exit(1); } }

// a window of a window reads the same root: nothing is copied and nothing stacks
constexpr const char sample[] = "  hello, world  ";
static_assert(CharSeries(sample, 16)[join::TwInt(2, 14)][join::TwInt(0, 5)].base == sample + 2, "a window of a window is a window of the same bytes");
static_assert(sizeof(CharWindow) == 16 && sizeof(CharSeries) == 24, "the window weighs a string_view; the cursor is the rest");
static_assert(CharSeries(sample, 16)[join::TwInt(2, 14)][join::TwInt(0, 5)].view() == "hello");
static_assert(CharSeries(sample, 16).trim().view() == "hello, world", "skipWs and rtrim");
static_assert(CharSeries(std::string_view("a,b,,c")).size() == 6);
constexpr bool cursor() {
  CharSeries s(std::string_view("key=value;rest"));
  if (!s.seekTo('=')) return false;
  CharSeries v = s; v.lim(v.pos + 5);
  if (v.slice().view() != "value") return false;
  s.mk(); s.get(); s.get(); s.res();              // reset to the mark
  if (s.get() != 'v') return false;
  CharSeries q(std::string_view(R"(a\"b"c)"));
  return q.seekTo('"', '\\') && q.slice().view() == "c";
}
static_assert(cursor(), "get, mk, res, lim, slice, seekTo with an escape");
// equality is the characters, not the cursor or the root
constexpr bool equality() {
  CharSeries a(std::string_view("xxabc")), b(std::string_view("abcyy"));
  a.at(2); b.lim(3);
  return a == b && !(CharSeries(std::string_view("ab")) == CharSeries(std::string_view("abc")));
}
static_assert(equality(), "content equality over pos..limit");
// a cursor is not a key
template <class T> concept Hashable = requires(T t) { std::hash<T>{}(t); };
static_assert(!Hashable<CharSeries>, "no hash: reify at the gate with view() and key on that");

static void integerFacetsAgreeWithLibc();
int main() {
  auto parts = split(CharSeries(std::string_view("a,b,,c")), ',');
  require(parts.size() == 4, "four parts");
  require(parts[0].view() == "a" && parts[1].view() == "b" && parts[2].view() == "" && parts[3].view() == "c", "the parts");
  // randomized: windows and splits agree with std::string
  uint64_t st = 88172645463325252ull; auto rng = [&] { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; };
  for (int r = 0; r < 20000; r++) {
    std::string s; for (unsigned i = 0, n = rng() % 24; i < n; i++) s += "ab ,\t"[rng() % 5];
    CharSeries c(s);
    uint32_t a = rng() % (s.size() + 1), b = a + rng() % (s.size() - a + 1);
    require(c[join::TwInt(a, b)].view() == std::string_view(s).substr(a, b - a), "window");
    CharSeries t = c; t.trim();
    size_t f = s.find_first_not_of(" \t"), l = s.find_last_not_of(" \t");
    require(t.view() == (f == std::string::npos ? std::string_view() : std::string_view(s).substr(f, l - f + 1)), "trim");
    auto ps = split(c, ',');
    std::string joined; for (uint32_t k = 0; k < ps.size(); k++) { if (k) joined += ','; joined += ps[k].view(); }
    require(joined == s, "split then join is the identity");
  }
  integerFacetsAgreeWithLibc();
  std::puts("PASS charseries: flattened windows, cursor verbs, content equality, no hash, split; 20,000 random windows, trims and splits");
}

// ── facets ──
namespace facets {
static_assert(facet<text::Bytes>(CharSeries(std::string_view("héllo"))) == 6 && facet<text::Codepoints>(CharSeries(std::string_view("héllo"))) == 5);
static_assert(facet<text::FNV1a>(CharSeries(std::string_view("a"))) == 0xaf63dc4c8601ec8cull, "FNV-1a of \"a\"");
static_assert(facet<text::Deduced>(CharSeries(std::string_view("-42"))) == text::Memento::Int);
static_assert(facet<text::Deduced>(CharSeries(std::string_view("1.5e3"))) == text::Memento::Float);
static_assert(facet<text::Deduced>(CharSeries(std::string_view("true"))) == text::Memento::Bool);
static_assert(facet<text::Deduced>(CharSeries(std::string_view("4a"))) == text::Memento::String);
static_assert(facet<text::Deduced>(CharSeries(std::string_view(""))) == text::Memento::Empty);
static_assert(facet<text::Integer<10, true>>(CharSeries(std::string_view("-9223372036854775808"))).value == uint64_t(1) << 63);
static_assert(facet<text::Integer<10, true>>(CharSeries(std::string_view("9223372036854775808"))).overflow);
static_assert(facet<text::Integer<16, false>>(CharSeries(std::string_view("0xff"))).value == 255);
} // namespace facets

#include <cerrno>
static void integerFacetsAgreeWithLibc() {
  uint64_t st = 0x9E3779B97F4A7C15ull; auto rng = [&] { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; };
  const char *alphabet = "0123456789abcdefxX+- \t";
  for (int r = 0; r < 400000; r++) {
    std::string t;
    unsigned n = rng() % 26;
    for (unsigned i = 0; i < n; i++) t += alphabet[rng() % 22];
    if (rng() % 3 == 0) t = std::to_string((long long)rng()) + (rng() % 2 ? "9" : "");
    CharSeries c(t);
    auto check = [&](auto reading, auto libc, const char *what) {
      char *end; errno = 0;
      auto v = libc(t.c_str(), &end);
      bool erange = errno == ERANGE;
      require(reading.value == (uint64_t)v && reading.overflow == erange && reading.consumed == uint32_t(end == t.c_str() ? 0 : end - t.c_str()), what);
    };
    check(facet<text::Integer<10, true>>(c), [](const char *p, char **e) { return strtoll(p, e, 10); }, "strtoll base 10");
    check(facet<text::Integer<10, false>>(c), [](const char *p, char **e) { return strtoull(p, e, 10); }, "strtoull base 10");
    check(facet<text::Integer<16, false>>(c), [](const char *p, char **e) { return strtoull(p, e, 16); }, "strtoull base 16");
    check(facet<text::Integer<8, false>>(c), [](const char *p, char **e) { return strtoull(p, e, 8); }, "strtoull base 8");
    // glibc 2.38 and later read a "0b" prefix in base 2 (C23); the facet is the C11 reading, the same on every host, and the evaluator strips
    // a TOML "0b" itself before it asks.  So base 2 is compared where the string has no such prefix.
    {
      const char *q = t.c_str();
      while (*q == ' ' || *q == '\t') ++q;
      if (*q == '+' || *q == '-') ++q;
      bool binaryPrefix = q[0] == '0' && (q[1] == 'b' || q[1] == 'B');
      if (!binaryPrefix) check(facet<text::Integer<2, false>>(c), [](const char *p, char **e) { return strtoull(p, e, 2); }, "strtoull base 2");
    }
  }
  std::puts("PASS facets: sizes, FNV-1a, evidence, deduction; the integer readings agree with strtoll/strtoull on 400,000 random strings in 5 bases (base 2 except glibc's C23 0b prefix)");
}
