// MutableSeries::freeze: the handle is promoted to a const Series by a move (same buffer, source left empty); a copy of the frozen
// body and the freeze of a named series are compile errors; a known-size array freezes with no heap.  Build like minmax-check.cc.
#include "Composite/Folds.h"
#include "Composite/Mutable.h"
#include <cstdio>
#include <cstdlib>
#include <type_traits>
#include <utility>
using namespace composite;
static_assert(!std::is_copy_constructible_v<Cells<int>>, "a frozen body must not be copyable");
static_assert(std::is_move_constructible_v<Cells<int>>, "a frozen body moves");
template <class T> concept CanFreezeLvalue = requires(MutableSeries<T> &m) { m.freeze(); };
static_assert(!CanFreezeLvalue<int>, "freezing a named series is a compile error: write std::move(x).freeze()");
static_assert(freeze(vec<4>([](uint32_t i) { return int(i * i); }))[3] == 9, "a known-size body freezes as a Series, constexpr");
static_assert(freeze(vec<4>([](uint32_t i) { return int(i * i); })).size() == 4);
int main() {  // (the premark checks above are static_asserts)
  MutableSeries<int> m; for (int i = 0; i < 1000; i++) m.append(i);
  const int *before = m.data();
  auto f = std::move(m).freeze();
  bool ok = f.size() == 1000 && f[999] == 999 && m.empty() && &f[0] == before;  // same buffer: a move, not a copy
  int sum = 0; for (int x : f) sum += x;
  std::printf("%s size=%u sum=%d moved-from-empty=%d same-buffer=%d\n", ok && sum == 499500 ? "PASS" : "FAIL", f.size(), sum, int(m.empty()), int(&f[0] == before));
  return ok && sum == 499500 ? 0 : 1;
}

// The premark: the size of a constant-size Series is in its type, and fold takes the straight-line path on it.
namespace premark {
constexpr auto four = freeze(vec<4>([](uint32_t i) { return int(i + 1); }));
static_assert(Marks<std::remove_cvref_t<decltype(four)>>::constant && Marks<std::remove_cvref_t<decltype(four)>>::size == 4);
static_assert(!Marks<Series<int (*)(uint32_t)>>::constant, "a runtime-size Series keeps the loop");
static_assert(fold(four, 0, [](int a, int x) { return a + x; }) == 10, "fold over a constant size, evaluated at compile time");
static_assert(fold(four, 0, [](int a, int x) { return a + x; }, [](int a) { return a >= 3; }) == 3, "halt works on the straight-line path");
static_assert(fold(iotaN<5>(), 0u, [](uint32_t a, uint32_t k) { return a + k; }) == 10);
static_assert(four.size() == 4 && four[2] == 3 && std::is_same_v<decltype(four.a), Size<4>>);
static_assert(argMin(four, [](int x, int y) { return x < y; }) == 0 && firstWhere(four, [](int x) { return x == 3; }) == 2);
} // namespace premark
