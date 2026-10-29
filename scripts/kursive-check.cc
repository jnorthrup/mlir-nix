// Kursive.h against std::regex (extended, regex_match) on every pattern the two benchmark workloads give builtins.match, plus a few that are
// ambiguous on purpose, over random inputs: whether it matches, and each group's span.  libstdc++ (Kali, g++-16) is the reference: Nix on
// Linux answers with it.  libc++ (the Mac) applies POSIX's leftmost-longest rule to the groups, so the ambiguous patterns may differ there.
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
    // ambiguous on purpose: where leftmost-first and leftmost-longest group spans part
    R"((a|ab)(c|bcd)(d*))", R"((a*)(a*))", R"((a|b)*c)", R"(x{2,4}y?)", R"((a|ab)(bc|c))",
};
static const char alphabet[] = "abcdeiopsuwxyzrgtABXZ0123579./-_:@%<>+=,?#\" \\\nrtvuoign";

int main() {
  std::mt19937 rng(42);
  int failedPatterns = 0, taken = 0;
  long tests = 0, mismatches = 0;
  for (const char *pat : patterns) {
    uint32_t len = uint32_t(std::strlen(pat));
    std::vector<Step> steps(4096);
    std::vector<Set> sets(512);
    std::vector<detail::Node> pool(4096);
    Program prog{steps.data(), 0, uint32_t(steps.size()), sets.data(), 0, uint32_t(sets.size())};
    compile(pat, len, prog, pool.data(), uint32_t(pool.size()));
    if (!prog.ok) { std::printf("  not taken (std::regex answers): %s\n", pat); continue; }
    taken++;
    std::regex re(pat, std::regex::extended);
    std::vector<Entry> stack(1 << 16);
    std::vector<uint32_t> caps(2 * (prog.groups + 1));
    int shown = 0, bad = 0;
    static const char *crafted[] = {"abcd", "abc", "aaa", "aa", "a", "", "ababc", "abbbc", "xxxy", "xxxxy", "xxxxxy", "abcbcd", "u+rwx,g-w",
                                    "755", "+x", "a.b.c", "git+https://x?rev=1#y", "git+a#b", "\"a b\"c", "foo.service", ".swp", ".x.swp",
                                    "5.11.2", "5.10.2", "<a<b>c>", "mirror://gnu/hello/x.tar", "/bin/sh", "a/b/c", "x86_64-linux-gnuabi64"};
    int nCrafted = int(sizeof crafted / sizeof *crafted);
    for (int r = 0; r < 4000 + nCrafted; r++) {
      std::string s;
      if (r < nCrafted) s = crafted[r];
      else {
        int n = rng() % 24;
        for (int i = 0; i < n; i++) s += alphabet[rng() % (sizeof alphabet - 1)];
        if (r % 7 == 0 && n > 2) { s = std::string("mirror://gnu/") + s; } // reach the long literal prefixes now and then
        if (r % 11 == 0) s = "a-" + s + ".service";
        if (r % 13 == 0) { std::string t; for (int i = 0; i < 2 + int(rng() % 6); i++) t += "abcdx"[rng() % 5]; s = t; } // the ambiguous ones' alphabet
      }
      Result k = matchAll(prog, s.data(), uint32_t(s.size()), caps.data(), stack.data(), uint32_t(stack.size()));
      if (k == Result::GaveUp) continue;
      std::cmatch m;
      const char *b = s.c_str();
      bool want = std::regex_match(b, b + s.size(), m, re);
      tests++;
      bool same = (k == Result::Match) == want;
      if (same && want) {
        if (m.size() != prog.groups + 1) same = false;
        for (uint32_t g = 1; same && g <= prog.groups; g++) {
          bool took = caps[2 * g] != ~0u && caps[2 * g + 1] != ~0u;
          if (took != m[g].matched) same = false;
          else if (took && (uint32_t(m.position(g)) != caps[2 * g] || uint32_t(m.length(g)) != caps[2 * g + 1] - caps[2 * g])) same = false;
        }
      }
      if (!same) {
        mismatches++;
        bad++;
        if (shown++ < 3) {
          std::printf("  MISMATCH %s on \"%s\": std %s", pat, s.c_str(), want ? "match" : "no match");
          if (want) for (size_t g = 1; g < m.size(); g++) std::printf(" [%d:%ld+%ld]", m[g].matched ? 1 : 0, long(m.position(g)), long(m.length(g)));
          std::printf("; kursive %s", k == Result::Match ? "match" : "no match");
          if (k == Result::Match) for (uint32_t g = 1; g <= prog.groups; g++) std::printf(" [%u:%u]", caps[2 * g], caps[2 * g + 1]);
          std::printf("\n");
        }
      }
    }
    if (bad) failedPatterns++;
  }
  std::printf("%s kursive: %d of %zu patterns taken, %ld inputs, %ld mismatches with std::regex in %d patterns\n",
              mismatches ? "FAIL" : "PASS", taken, sizeof patterns / sizeof *patterns, tests, mismatches, failedPatterns);
  return mismatches ? 1 : 0;
}
