// MutableSeries has one algorithm and several bodies.  This checks the algorithm on each body against the stdlib (the oracle
// only), that a fixed body cannot do what only a growable one can (it is not there to call), and that a full fixed body says TODO.
#include "Composite/Mutable.h"
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>
using namespace composite;
static void require(bool ok, const char *m) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", m); std::exit(1); } }

// what a body can do is a property of its type, not a runtime check
template <class M> concept CanReserve = requires(M m) { m.reserve(8); };
template <class M> concept CanResize = requires(M m) { m.resize(8); };
template <class M> concept CanFreeze = requires(M m) { std::move(m).freeze(); };
using Fixed = MutableSeries<int, Inline<int, 8>>;
static_assert(CanReserve<MutableSeries<int>> && CanResize<MutableSeries<int>> && CanFreeze<MutableSeries<int>>, "a growable body can be sized and frozen");
static_assert(!CanReserve<Fixed> && !CanResize<Fixed> && !CanFreeze<Fixed>, "a fixed body has no reserve, resize or freeze");
static_assert(sizeof(Fixed) == 8 * sizeof(int) + sizeof(uint32_t), "an inline body is its cells and a count: no pointer, no heap");
// a fixed body is a constant expression
constexpr int sumInline() { Fixed f; for (int i = 1; i <= 5; i++) f.append(i * i); f.removeSwap(1); int t = 0; for (int x : f) t += x; return t * 100 + int(f.size()); }
static_assert(sumInline() == (1 + 25 + 9 + 16) * 100 + 4, "append and removeSwap on an inline body, at compile time");

template <class M> static void algorithm(const char *name) {
  uint64_t st = 88172645463325252ull; auto rng = [&] { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; };
  for (int round = 0; round < 20000; round++) {
    M m; std::vector<int> ref;
    for (unsigned k = 0, ops = rng() % 40; k < ops; k++) {
      unsigned op = rng() % 5;
      if (op <= 2 && ref.size() < 8) { int v = int(rng() % 1000); uint32_t idx = m.append(v); ref.push_back(v); require(idx == ref.size() - 1, "append returns the new index"); }
      else if (op == 3 && !ref.empty()) { uint32_t i = rng() % ref.size(); ref[i] = ref.back(); ref.pop_back(); m.removeSwap(i); }
      else if (op == 4 && !ref.empty()) { m.pop(); ref.pop_back(); }
      require(m.size() == ref.size(), "size");
      for (uint32_t i = 0; i < m.size(); i++) require(m[i] == ref[i], "cells");
      require(m.empty() == ref.empty(), "empty");
    }
    { M moved = static_cast<M &&>(m); require(moved.size() == ref.size(), "a move keeps the cells"); m = static_cast<M &&>(moved); } // a series is move-only: a copy does not compile
    m.clear(); require(m.empty(), "clear");
  }
  std::printf("  %-18s the algorithm agrees with the stdlib on 20,000 random op sequences\n", name);
}

int main() {
  composite::todoSink = [](const char *what) { std::fprintf(stderr, "TODO: %s\n", what); };   // the algebra has no I/O: the host says it
  algorithm<MutableSeries<int>>("Growable");
  algorithm<Fixed>("Inline<8>");
  // a full fixed body says TODO, out loud, and does not write past its cells
  std::fflush(stdout);
  pid_t pid = fork();
  if (pid == 0) { Fixed f; for (int i = 0; i < 9; i++) f.append(i); _exit(0); }
  int status = 0; waitpid(pid, &status, 0);
  require(WIFSIGNALED(status) && (WTERMSIG(status) == SIGILL || WTERMSIG(status) == SIGTRAP || WTERMSIG(status) == SIGABRT), "append past a fixed body's capacity is TODO(): it says so and traps");
  std::puts("PASS bodies: one algorithm, Growable and Inline; fixed bodies cannot reserve/resize/freeze; a full fixed body is TODO()");
}
