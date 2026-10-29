// Kursive.h against std::regex::extended: regex_match (builtins.match) and the regex_iterator walk builtins.split makes, on every pattern the
// two benchmark workloads use, on patterns that probe libstdc++'s corners (loops that may match empty, anchors, alternations), and on random
// patterns, where it must also agree on which patterns are errors.  libstdc++ (Kali, g++-16) is the reference: Nix on Linux answers with it.
// Build: c++ -std=c++20 -O2 -Iinclude scripts/kursive-check.cc
#include "Composite/Kursive.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <regex>
#include <string>
#include <vector>
using namespace composite::kursive;

static const char *patterns[] = {
    R"([[:alnum:]+_?=-][[:alnum:]+._?=-]*)", R"([a-zA-Z_][a-zA-Z0-9_'-]*)", R"(<(.*)>)", R"(^\.sw[a-z]$)", R"(^\..*\.sw[a-z]$)",
    R"([[:alnum:],._+:@%/-]+)", R"(mirror://([a-z]+)/(.*))", R"(/bin/([^/]+))", R"(.*/.*)", R"(.*:.*)", R"(.*)", R"((.*)e?abi.*)",
    R"([a-zA-Z0-9@%:_.\-]+[.](service|socket|device|mount|automount|swap|target|path|timer|scope|slice))", R"(.* .*)",
    R"(5\.[0-9]*[13579]\..+)", R"([[:alpha:]_][[:alnum:]_]*(\.[[:alpha:]_][[:alnum:]_]*)*)", R"([a-zA-Z0-9_.][a-zA-Z0-9_.-]*)",
    R"([0-7]{1,5})", R"([a-zA-Z0-9]+)", R"([a-f0-9]*)", R"((.*)\.git)",
    R"((([ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+)(,[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+)*)|([-+=]?[0-7]{0,4}))",
    R"(.*-polly.*)", R"(([0-9A-Za-z._])[0-9A-Za-z._-]*)", R"(.+/)", R"(/[0-9a-z]{52})", R"(\.*(.*))", R"(.*\\([nrt]|x[0-9A-Fa-f]{2}).*)",
    R"(git\+([^?]+)(\?(rev|tag|branch)=(.*))?#(.*))", R"(([^"[:space:]]|"[^"]*")+)", R"(^$|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$)",
    R"([a-zA-Z0-9:_\.-]*)", R"([0-9]{2}\.[0-9]{2})", R"(([^ ]*/)?([^ ]+).*)", R"((.+)+(.+))", R"(.{32}-.+)", "[^\n]*", "[ \t\n]*",
    // split's patterns in nixpkgs, and libstdc++'s corners
    R"( )", R"(,)", R"(\.)", R"(-)", R"([ ]+)", R"(\n)", R"(:)", R"(/)", R"(([0-9]+))", R"((a*))", R"(a*)", R"(x*)", R"(b|)", R"(|b)",
    R"((a|ab)(c|bcd)(d*))", R"((a*)(a*))", R"((a|b)*c)", R"(x{2,4}y?)", R"((a|ab)(bc|c))", R"((a*)*)", R"((a|)*b)", R"((a*)+)", R"(()*)",
    R"((a?)*?)", R"((a*|b)*)", R"(^a|b$)", R"([[:w:]]+)", R"([[.a.]-c]+)", R"(()+x)", R"((a|b|)+)", R"(a{0,3}b)", R"(((a)|b)+)",
};
static const char alphabet[] = "abcdeiopsuwxyzrgtABXZ0123579./-_:@%<>+=,?#\" \\\nrtvuoign";

struct Engine {
  std::vector<Step> steps = std::vector<Step>(1 << 16);
  std::vector<Set> sets = std::vector<Set>(4096);
  std::vector<detail::Node> pool = std::vector<detail::Node>(1 << 16);
  std::vector<uint32_t> caps = std::vector<uint32_t>(256), best = std::vector<uint32_t>(256);
  std::vector<LoopState> loops = std::vector<LoopState>(1 << 16);
  std::vector<Entry> stack = std::vector<Entry>(1 << 18);
  Program prog;
  bool compile(const std::string &pat) {
    prog = Program{steps.data(), 0, uint32_t(steps.size()), sets.data(), 0, uint32_t(sets.size())};
    composite::kursive::compile(pat.data(), uint32_t(pat.size()), prog, pool.data(), uint32_t(pool.size()));
    return prog.error == Error::None && prog.groups < 120;
  }
  Scratch scratch() { return Scratch{caps.data(), best.data(), loops.data(), stack.data(), uint32_t(stack.size()), uint64_t(1) << 26}; }
};

static long tests = 0, mismatches = 0;
static int shownTotal = 0;

static bool sameGroups(const std::cmatch &m, const uint32_t *best, uint32_t groups) {
  if (m.size() != groups + 1) return false;
  for (uint32_t g = 0; g <= groups; g++) {
    bool took = best[2 * g] != ~0u && best[2 * g + 1] != ~0u;
    if (took != m[g].matched) return false;
    if (took && (uint32_t(m.position(g)) != best[2 * g] || uint32_t(m.length(g)) != best[2 * g + 1] - best[2 * g])) return false;
  }
  return true;
}

// builtins.match: regex_match.
static void checkMatch(Engine &k, const std::regex &re, const std::string &pat, const std::string &s) {
  Scratch sc = k.scratch();
  Result r = matchAll(k.prog, s.data(), uint32_t(s.size()), sc);
  if (r == Result::GaveUp) return;
  std::cmatch m;
  const char *b = s.c_str();
  bool want = std::regex_match(b, b + s.size(), m, re);
  tests++;
  bool same = (r == Result::Match) == want && (!want || sameGroups(m, k.best.data(), k.prog.groups));
  if (!same) {
    mismatches++;
    if (shownTotal++ < 12) std::printf("  MATCH MISMATCH /%s/ on \"%s\": std %s, kursive %s\n", pat.c_str(), s.c_str(), want ? "match" : "no match",
                                       r == Result::Match ? "match" : "no match");
  }
}

// builtins.split: the walk of std::cregex_iterator (its rule after an empty match: a non-empty match at the same place, else one byte on).
static void checkSplit(Engine &k, const std::regex &re, const std::string &pat, const std::string &s) {
  const char *b = s.c_str();
  std::vector<std::vector<long>> want;
  int guard = 0;
  for (auto it = std::cregex_iterator(b, b + s.size(), re); it != std::cregex_iterator() && guard++ < 1000; ++it) {
    std::vector<long> row;
    for (size_t g = 0; g < it->size(); g++) { row.push_back((*it)[g].matched ? long(it->position(g)) : -1); row.push_back((*it)[g].matched ? long(it->length(g)) : -1); }
    want.push_back(row);
  }
  std::vector<std::vector<long>> got;
  uint32_t n = uint32_t(s.size()), from = 0;
  Scratch sc = k.scratch();
  Result r = search(k.prog, b, n, 0, false, false, sc);
  guard = 0;
  while (r == Result::Match && guard++ < 1000) {
    std::vector<long> row;
    for (uint32_t g = 0; g <= k.prog.groups; g++) {
      bool took = k.best[2 * g] != ~0u && k.best[2 * g + 1] != ~0u;
      row.push_back(took ? long(k.best[2 * g]) : -1);
      row.push_back(took ? long(k.best[2 * g + 1] - k.best[2 * g]) : -1);
    }
    got.push_back(row);
    uint32_t ms = k.best[0], me = k.best[1];
    if (ms == me) {
      if (me == n) break;
      sc = k.scratch();
      r = search(k.prog, b, n, me, true, true, sc);
      if (r == Result::Match) continue;
      if (r == Result::GaveUp) return;
      from = me + 1;
    } else from = me;
    sc = k.scratch();
    r = search(k.prog, b, n, from, false, false, sc);
  }
  if (r == Result::GaveUp) return;
  tests++;
  if (got != want) {
    mismatches++;
    if (shownTotal++ < 12) std::printf("  SPLIT MISMATCH /%s/ on \"%s\": std %zu matches, kursive %zu\n", pat.c_str(), s.c_str(), want.size(), got.size());
  }
}

static std::string randomInput(std::mt19937 &rng, int r) {
  std::string s;
  int n = rng() % 24;
  for (int i = 0; i < n; i++) s += alphabet[rng() % (sizeof alphabet - 1)];
  if (r % 7 == 0 && n > 2) s = std::string("mirror://gnu/") + s;
  if (r % 11 == 0) s = "a-" + s + ".service";
  if (r % 13 == 0) { std::string t; for (int i = 0; i < 1 + int(rng() % 8); i++) t += "abcdx"[rng() % 5]; s = t; }
  return s;
}

int main() {
  std::mt19937 rng(42);
  static const char *crafted[] = {"abcd", "abc", "aaa", "aa", "a", "", "ababc", "abbbc", "xxxy", "xxxxy", "xxxxxy", "abcbcd", "u+rwx,g-w", "755",
                                  "+x", "a.b.c", "git+https://x?rev=1#y", "git+a#b", "\"a b\"c", "foo.service", ".swp", ".x.swp", "5.11.2",
                                  "<a<b>c>", "mirror://gnu/hello/x.tar", "/bin/sh", "a/b/c", "x86_64-linux-gnuabi64", "a b  c", "b", "ab",
                                  "bab", "aab", "abab", "x"};
  int taken = 0;
  long verdictFixed = 0;
  Engine k;
  { // what nix-instantiate --eval (2.35.4, Kali) answers
    struct Known { const char *pat, *in; bool ok; const char *groups; } known[] = {
        {"()", "", true, ""}, {"(a*)*", "aa", true, ""}, {"[[:w:]]+", "ab_c", true, nullptr}, {"a**", "aa", true, nullptr}};
    for (auto &kn : known) {
      bool c = k.compile(kn.pat);
      Scratch sc = k.scratch();
      bool m = c && matchAll(k.prog, kn.in, uint32_t(std::strlen(kn.in)), sc) == Result::Match;
      bool g = !kn.groups || (k.prog.groups == 1 && k.best[2] != ~0u && std::string(kn.in + k.best[2], k.best[3] - k.best[2]) == kn.groups);
      if (!(c && m == kn.ok && g)) { mismatches++; std::printf("  NIX DIFFERS /%s/ on \"%s\"\n", kn.pat, kn.in); }
    }
    for (const char *bad : {"\\n", "a\\-b", "^*a"})
      if (k.compile(bad)) { mismatches++; std::printf("  NIX REJECTS /%s/, kursive takes it\n", bad); }
  }
  for (const char *pat : patterns) {
    bool stdOk = true;
    std::regex re;
    try { re = std::regex(pat, std::regex::extended); } catch (std::regex_error &) { stdOk = false; }
    if (!k.compile(pat)) {
      if (stdOk) { verdictFixed++; std::printf("  VERDICT /%s/: std takes it, kursive rejects it\n", pat); }
      continue;
    }
    if (!stdOk) { verdictFixed++; std::printf("  VERDICT /%s/: std rejects it, kursive takes it\n", pat); continue; }
    taken++;
    for (const char *c : crafted) { checkMatch(k, re, pat, c); checkSplit(k, re, pat, c); }
    for (int r = 0; r < 3000; r++) { std::string s = randomInput(rng, r); checkMatch(k, re, pat, s); if (r % 3 == 0) checkSplit(k, re, pat, s); }
  }
  // random patterns: the same verdict on errors, and the same answers where both take the pattern
  static const char meta[] = "ab()|*+?{}[]^$.\\-,12:"; // counts of one or two: libstdc++ explores every path, and a{3333} would take it hours
  long agreeErr = 0, bothOk = 0, verdict = 0;
  for (int i = 0; i < 6000; i++) {
    if (i % 1000 == 0) { std::printf("  ... %d random patterns: %ld checks, %ld mismatches, %ld verdicts differ\n", i, tests, mismatches, verdict); std::fflush(stdout); }
    std::string pat;
    int n = 1 + rng() % 9;
    for (int j = 0; j < n; j++) pat += meta[rng() % (sizeof meta - 1)];
    if (rng() % 4 == 0) pat = "[" + pat.substr(0, 3) + "]" + pat;
    bool stdOk = true;
    std::regex re;
    try { re = std::regex(pat, std::regex::extended); } catch (std::regex_error &) { stdOk = false; }
    bool kOk = k.compile(pat);
    if (stdOk != kOk) {
      verdict++;
      if (shownTotal++ < 12) std::printf("  VERDICT /%s/: std %s, kursive %s\n", pat.c_str(), stdOk ? "takes it" : "rejects it", kOk ? "takes it" : "rejects it");
      continue;
    }
    if (!stdOk) { agreeErr++; continue; }
    bothOk++;
    for (const char *c : crafted) checkMatch(k, re, pat, c);
    for (int r = 0; r < 20; r++) { std::string s = randomInput(rng, r); checkMatch(k, re, pat, s); if (r % 4 == 0) checkSplit(k, re, pat, s); }
  }
  verdict += verdictFixed;
  std::printf("%s kursive: %d of %zu patterns taken; %ld match/split checks, %ld mismatches; random patterns: %ld both take, %ld both reject, "
              "%ld verdicts differ\n", mismatches || verdict ? "FAIL" : "PASS", taken, sizeof patterns / sizeof *patterns, tests, mismatches,
              bothOk, agreeErr, verdict);
  return mismatches || verdict ? 1 : 0;
}
