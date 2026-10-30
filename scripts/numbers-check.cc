// Nix/Numbers.h against the C and C++ library functions it stands in for, case by case: the value, the exception type and its what().
// readUnsigned and readSigned (the Integer facets of CharSeries) against strtoul, strtoull, strtoll, atoll and atoi; stoValue against
// stoul, stoull and stoll; and the logic of each place that used them (the lexer's integer, the JIT threshold, the list index of a
// selection path, the components of compareVersions, the exponent of jsonFloat, the minted-body count of a prefetch list) against what
// that place did with the library.  The library is the oracle, so std::string and <charconv> are used on purpose here.
// Build like scripts/minmax-check.cc, e.g. g++-16 -std=c++20 -O2 -g -fsanitize=address,undefined -I include scripts/numbers-check.cc -o build/numbers-check
// and run it with an optional count of random inputs (2,000,000 by default, 31 million comparisons).  libc++ and libstdc++ word the
// exceptions differently; the check compares against whichever library it is built with.
#include "Nix/Numbers.h"

#include <cerrno>
#include <charconv>
#include <climits>
#include <cstdio>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <string_view>
#include <vector>

using std::string;
using std::string_view;
namespace cp = composite;

static long long failures = 0, cases = 0;
#define CHECK(cond, ...)                                                                \
  do {                                                                                  \
    ++cases;                                                                            \
    if (!(cond)) {                                                                      \
      if (++failures <= 25) {                                                           \
        std::printf("MISMATCH %s: ", __func__);                                         \
        std::printf(__VA_ARGS__);                                                       \
        std::printf("\n");                                                              \
      }                                                                                 \
    }                                                                                   \
  } while (0)

static string show(const string &s) {
  string o = "\"";
  for (unsigned char c : s) {
    if (c >= 0x20 && c < 0x7f && c != '"' && c != '\\') o += char(c);
    else { char b[8]; std::snprintf(b, sizeof b, "\\x%02x", c); o += b; }
  }
  return o + "\"";
}

struct Outcome {
  int kind = 0; // 0 a value, 1 invalid_argument, 2 out_of_range, 3 anything else
  uint64_t value = 0;
  string what;
  bool operator==(const Outcome &o) const { return kind == o.kind && value == o.value && what == o.what; }
};
template <class F> static Outcome run(F f) {
  Outcome o;
  try { o.value = uint64_t(f()); }
  catch (std::invalid_argument &e) { o.kind = 1; o.what = e.what(); }
  catch (std::out_of_range &e) { o.kind = 2; o.what = e.what(); }
  catch (...) { o.kind = 3; }
  return o;
}
static string describe(const Outcome &o) {
  char b[200];
  std::snprintf(b, sizeof b, "kind %d value %llu what '%s'", o.kind, (unsigned long long)o.value, o.what.c_str());
  return b;
}

// ---- the inputs ---------------------------------------------------------------------------------------------------------------------------
static std::mt19937_64 rng(0x5eedf00d);
static string randomText() {
  static const char alphabet[] = "0123456789 \t\n\v\f\r+-xXabcdefgABCDEFG.eE_,\xff";
  string s;
  size_t n = rng() % 27;
  int mode = rng() % 6;
  for (size_t i = 0; i < n; i++) {
    if (mode == 0) s += char('0' + rng() % 10);                                       // only digits
    else if (mode == 1) s += i == 0 && rng() % 2 ? "+-"[rng() % 2] : char('0' + rng() % 10); // a sign and digits
    else if (mode == 2) s += rng() % 10 < 8 ? char('0' + rng() % 10) : alphabet[rng() % (sizeof alphabet - 1)];
    else if (mode == 3) s += alphabet[rng() % (sizeof alphabet - 1)];
    else if (mode == 4 && rng() % 25 == 0) s += '\0';                                  // an embedded NUL
    else s += rng() % 10 < 9 ? char('0' + rng() % 10) : " \t+-x"[rng() % 5];
  }
  return s;
}
static std::vector<string> corpus(int randoms) {
  std::vector<string> v = {"", " ", "+", "-", "0", "00", "-0", "+0", " -5", "+5", "5 ", "5x", "0x10", "0X1f", "0x", "1e5", "1.5", ".5", "1_000",
                           "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "9223372036854775806",
                           "18446744073709551615", "18446744073709551616", "-1", "-18446744073709551615", "-18446744073709551616",
                           "99999999999999999999999", "\t\n 42abc", "\v\f\r7", " \t", "12 34", "007", "0000000000000000000000000001",
                           "2147483647", "2147483648", "-2147483648", "-2147483649", "4294967295", "4294967296", "1000000", "1000001", "0", "1"};
  const char *edges[] = {"9223372036854775807", "9223372036854775808", "18446744073709551615", "18446744073709551616", "1000000", "1000001"};
  for (const char *e : edges)
    for (const char *pre : {"", " ", "+", "-", "\t-", "0"})
      for (const char *post : {"", "x", " ", "\n", "0", "e1"}) v.push_back(string(pre) + e + post);
  for (int i = 0; i < randoms; i++) v.push_back(randomText());
  return v;
}

// ---- the stoul family -------------------------------------------------------------------------------------------------------------------
static void stoFamily(const std::vector<string> &in) {
  for (const string &s : in) {
    string_view sv = s;
    Outcome a = run([&] { return std::stoul(s); }), b = run([&] { return nixsys::stoValue("stoul", nixsys::readUnsigned(sv)); });
    CHECK(a == b, "stoul %s: library {%s} facet {%s}", show(s).c_str(), describe(a).c_str(), describe(b).c_str());
    a = run([&] { return std::stoull(s); }), b = run([&] { return nixsys::stoValue("stoull", nixsys::readUnsigned(sv)); });
    CHECK(a == b, "stoull %s: library {%s} facet {%s}", show(s).c_str(), describe(a).c_str(), describe(b).c_str());
    a = run([&] { return std::stoll(s); }), b = run([&] { return nixsys::stoValue("stoll", nixsys::readSigned(sv)); });
    CHECK(a == b, "stoll %s: library {%s} facet {%s}", show(s).c_str(), describe(a).c_str(), describe(b).c_str());
  }
}

// ---- the C functions read through c_str(): a NUL ends the text ---------------------------------------------------------------------------
static void cFunctions(const std::vector<string> &in) {
  for (const string &s : in) {
    const char *z = s.c_str();
    CHECK(strtoul(z, nullptr, 10) == nixsys::readUnsigned(z).value, "strtoul %s", show(s).c_str());
    CHECK(strtoull(z, nullptr, 10) == nixsys::readUnsigned(z).value, "strtoull %s", show(s).c_str());
    CHECK((int64_t)atoll(z) == (int64_t)nixsys::readSigned(z).value, "atoll %s: %lld vs %lld", show(s).c_str(), (long long)atoll(z), (long long)nixsys::readSigned(z).value);
    CHECK(atoi(z) == int(nixsys::readSigned(z).value), "atoi %s: %d vs %d", show(s).c_str(), atoi(z), int(nixsys::readSigned(z).value));
    CHECK((int64_t)strtoll(z, nullptr, 10) == (int64_t)nixsys::readSigned(z).value, "strtoll %s", show(s).c_str());
    // on a view over the whole string, NULs and all, the reading is the same as through c_str(): a NUL is neither space nor digit
    CHECK(nixsys::readUnsigned(z).value == nixsys::readUnsigned(string_view(s)).value &&
              nixsys::readUnsigned(z).consumed == nixsys::readUnsigned(string_view(s)).consumed, "view vs c_str %s", show(s).c_str());
  }
}

// ---- Parser.cpp, R_INT: the lexeme is digits only -----------------------------------------------------------------------------------------
static void lexerInt(const std::vector<string> &in) {
  for (const string &raw : in) {
    string s;
    for (char c : raw) if (c >= '0' && c <= '9') s += c; // what the rule matches
    if (s.empty() || s.size() > 30) continue;
    errno = 0;
    char *end;
    unsigned long long old = strtoull(s.c_str(), &end, 10);
    bool oldBad = errno || old > (unsigned long long)INT64_MAX;
    cp::text::Reading n = nixsys::readUnsigned(string_view(s));
    bool newBad = n.overflow || n.value > (uint64_t)INT64_MAX;
    CHECK(oldBad == newBad && (oldBad || old == n.value), "lexer int %s: old bad %d %llu new bad %d %llu", s.c_str(), oldBad, old, newBad, (unsigned long long)n.value);
  }
}

// ---- ScalarJIT.cpp, threshold(): from_chars over the whole string, 1..1000000 --------------------------------------------------------------
static unsigned thresholdOld(const char *s) {
  unsigned n = 1024;
  unsigned parsed;
  auto result = std::from_chars(s, s + strlen(s), parsed);
  if (result.ec == std::errc() && *result.ptr == '\0' && parsed >= 1 && parsed <= 1000000) n = parsed;
  return n;
}
static unsigned thresholdNew(const char *s) {
  unsigned n = 1024;
  cp::text::Reading r = nixsys::readUnsigned(s);
  if (cp::isAsciiDigit(*s) && s[r.consumed] == '\0' && !r.overflow && r.value >= 1 && r.value <= 1000000) n = unsigned(r.value);
  return n;
}
static void threshold(const std::vector<string> &in) {
  for (const string &s : in) CHECK(thresholdOld(s.c_str()) == thresholdNew(s.c_str()), "threshold %s: %u vs %u", show(s).c_str(), thresholdOld(s.c_str()), thresholdNew(s.c_str()));
}

// ---- mlnix.cpp, the list index of a selection path --------------------------------------------------------------------------------------
static void selectionIndex(const std::vector<string> &in) {
  for (const string &c : in) {
    bool old = !c.empty() && std::all_of(c.begin(), c.end(), [](char ch) { return isdigit((unsigned char)ch); });
    cp::text::Reading index = nixsys::readUnsigned(string_view(c));
    bool now = !c.empty() && cp::isAsciiDigit(c[0]) && index.consumed == c.size();
    CHECK(old == now, "isIndex %s: %d vs %d", show(c).c_str(), old, now);
    if (old) {
      Outcome a = run([&] { return std::stoul(c); }), b = run([&] { return nixsys::stoValue("stoul", index); });
      CHECK(a == b, "index %s: library {%s} facet {%s}", show(c).c_str(), describe(a).c_str(), describe(b).c_str());
    }
  }
}

// ---- Builtins.cpp, componentsLT's toInt: a component of digits only --------------------------------------------------------------------------
static void versionComponent(const std::vector<string> &in) {
  for (const string &s : in) {
    string_view sv = s;
    bool digits = !sv.empty(); // HEAD: nothing but digits, then stoll
    for (char c : sv) if (!isdigit((unsigned char)c)) digits = false;
    cp::text::Reading r = nixsys::readSigned(sv); // now: a reading that starts with a digit and takes every byte
    bool facetDigits = !sv.empty() && cp::isAsciiDigit(sv[0]) && r.consumed == sv.size();
    CHECK(digits == facetDigits, "toInt digits %s: %d vs %d", show(s).c_str(), digits, facetDigits);
    Outcome a = run([&]() -> long long { return digits ? std::stoll(string(sv)) : -1; });
    Outcome b = run([&]() -> long long { return facetDigits ? (long long)nixsys::stoValue("stoll", r) : -1; });
    CHECK(a == b, "toInt %s: HEAD {%s} facet {%s}", show(s).c_str(), describe(a).c_str(), describe(b).c_str());
  }
}

// ---- StorePaths.cpp, jsonFloat: the exponent of "%.*e" ----------------------------------------------------------------------------------------
static void jsonExponent() {
  std::uniform_real_distribution<double> mant(0.5, 10.0);
  for (int i = 0; i < 400000; i++) {
    double d = mant(rng) * std::pow(10.0, int(rng() % 640) - 320) * (rng() % 2 ? 1 : -1);
    if (!std::isfinite(d) || d == 0) continue;
    char buf[64];
    snprintf(buf, sizeof buf, "%.*e", int(rng() % 17), d);
    string_view s = buf;
    if (s[0] == '-') s = s.substr(1);
    auto epos = s.find('e');
    CHECK(atoi(s.data() + epos + 1) == int(nixsys::readSigned(s.substr(epos + 1)).value), "exponent of %s", buf);
  }
}

// ---- Prefetch.cpp: the count after the last space of an "M path count" line -------------------------------------------------------------------
static void prefetchCount(const std::vector<string> &in) {
  for (const string &tail : in) {
    string l = "M /a/b.nix " + tail;
    size_t sp = l.rfind(' ');
    if (sp <= 2) continue;
    uint32_t old = uint32_t(strtoul(l.c_str() + sp + 1, nullptr, 10));
    uint32_t now = uint32_t(nixsys::readUnsigned(string_view(l).substr(sp + 1)).value);
    CHECK(old == now, "mint count %s: %u vs %u", show(l).c_str(), old, now);
  }
}

int main(int argc, char **argv) {
  std::vector<string> in = corpus(argc > 1 ? std::atoi(argv[1]) : 2000000);
  std::printf("%zu inputs\n", in.size());
  stoFamily(in);
  cFunctions(in);
  lexerInt(in);
  threshold(in);
  selectionIndex(in);
  versionComponent(in);
  jsonExponent();
  prefetchCount(in);
  std::printf("%lld comparisons, %lld mismatches\n", cases, failures);
  return failures != 0;
}
