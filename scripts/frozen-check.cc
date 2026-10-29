// MutableSeries::freeze: the handle is promoted to a const Series by a move (same buffer, source left empty); a copy of the frozen
// body and the freeze of a named series are compile errors; a known-size array freezes with no heap.  Build like minmax-check.cc.
#include "Composite/Series.h"
#include <cstdio>
#include <cstdlib>
#include <type_traits>
using namespace composite;
static_assert(!std::is_copy_constructible_v<Cells<int>>, "a frozen body must not be copyable");
static_assert(std::is_move_constructible_v<Cells<int>>, "a frozen body moves");
template <class T> concept CanFreezeLvalue = requires(MutableSeries<T> &m) { m.freeze(); };
static_assert(!CanFreezeLvalue<int>, "freezing a named series is a compile error: write std::move(x).freeze()");
static_assert(freeze(vec<4>([](uint32_t i) { return int(i * i); }))[3] == 9, "a known-size body freezes as a Series, constexpr");
static_assert(freeze(vec<4>([](uint32_t i) { return int(i * i); })).size() == 4);
int main() {
  MutableSeries<int> m; for (int i = 0; i < 1000; i++) m.append(i);
  const int *before = m.data();
  auto f = std::move(m).freeze();
  bool ok = f.size() == 1000 && f[999] == 999 && m.empty() && &f[0] == before;  // same buffer: a move, not a copy
  int sum = 0; for (int x : f) sum += x;
  std::printf("%s size=%u sum=%d moved-from-empty=%d same-buffer=%d\n", ok && sum == 499500 ? "PASS" : "FAIL", f.size(), sum, int(m.empty()), int(&f[0] == before));
  return ok && sum == 499500 ? 0 : 1;
}
