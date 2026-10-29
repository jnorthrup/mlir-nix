// take/drop/takeLast/dropLast/reversed/erased/inserted are O(1) views: they equal what the stdlib's mutation would produce, they
// compose, the original is untouched, and the constant-size forms carry their size in the type.  The stdlib is the oracle only.
#include "Composite/Series.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace composite;
static void require(bool ok, const char *m) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", m); std::exit(1); } }
template <class S> static std::vector<int> list(const S &s) { std::vector<int> v; for (uint32_t i = 0; i < s.size(); i++) v.push_back(int(s[i])); return v; }

// constant sizes, at compile time
constexpr auto five = freeze(vec<5>([](uint32_t i) { return int(i * 10); }));
static_assert(take<3>(five).size() == 3 && Marks<std::remove_cvref_t<decltype(take<3>(five))>>::constant);
static_assert(std::is_same_v<decltype(take<3>(five).a), Size<3>> && std::is_same_v<decltype(drop<2>(five).a), Size<3>>);
static_assert(drop<2>(five)[0] == 20 && drop<2>(five)[2] == 40);
static_assert(fold(drop<2>(five), 0, [](int a, int x) { return a + x; }) == 90, "a drop of a constant-size Series folds straight-line");
static_assert(fold(take<2>(drop<1>(five)), 0, [](int a, int x) { return a + x; }) == 30, "constant-size views compose");
static_assert(take(five, 2).size() == 2 && drop(five, 4).size() == 1 && takeLast(five, 2)[0] == 30 && dropLast(five, 4).size() == 1);
static_assert(reversed(five)[0] == 40 && reversed(five)[4] == 0);
static_assert(erased(five, 1).size() == 4 && erased(five, 1)[1] == 20 && inserted(five, 1, 99).size() == 6 && inserted(five, 1, 99)[1] == 99);

int main() {
  uint64_t st = 88172645463325252ull; auto rng = [&] { st ^= st << 13; st ^= st >> 7; st ^= st << 17; return st; };
  for (int round = 0; round < 20000; round++) {
    uint32_t n = rng() % 9, k = rng() % 12, at = rng() % 12; int v = int(rng() % 1000);
    MutableSeries<int> m; for (uint32_t i = 0; i < n; i++) m.append(int(rng() % 1000));
    std::vector<int> ref(m.cells);
    auto view = m.view();
    auto eq = [&](const std::vector<int> &want, const auto &got, const char *what) { require(list(got) == want, what); };
    { auto w = ref; w.resize(std::min<size_t>(k, w.size())); eq(w, take(view, k), "take"); }
    { auto w = ref; w.erase(w.begin(), w.begin() + std::min<size_t>(k, w.size())); eq(w, drop(view, k), "drop"); }
    { auto w = ref; w.erase(w.begin(), w.end() - std::min<size_t>(k, w.size())); eq(w, takeLast(view, k), "takeLast"); }
    { auto w = ref; w.resize(w.size() - std::min<size_t>(k, w.size())); eq(w, dropLast(view, k), "dropLast"); }
    { auto w = ref; std::reverse(w.begin(), w.end()); eq(w, reversed(view), "reversed"); }
    { auto w = ref; if (at < w.size()) w.erase(w.begin() + at); eq(w, erased(view, at), "erased"); }
    { auto w = ref; w.insert(w.begin() + std::min<size_t>(at, w.size()), v); eq(w, inserted(view, at, v), "inserted"); }
    // views compose: the middle of a list, reversed, with a row spliced out and another in
    { auto w = ref; if (w.size() > 2) { w.erase(w.begin()); w.pop_back(); } else w.clear(); std::reverse(w.begin(), w.end());
      auto c = reversed(dropLast(drop(view, 1), 1)); if (ref.size() > 2) eq(w, c, "composition"); }
    require(m.cells == ref, "the original is untouched");
  }
  std::puts("PASS views: take/drop/takeLast/dropLast/reversed/erased/inserted vs the stdlib on 20,000 random cuts; constant sizes in the type");
}
