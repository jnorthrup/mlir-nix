// Pack.h: every primitive shape unitizes into a Dense, the packed word compares as the tuple does, and a nest reads back.
// Build like minmax-check.cc.
#include "Composite/Pack.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
using namespace join;
enum class Kind : uint8_t { A = 1, B = 2, C = 200 };
static void require(bool ok, const char *m) { if (!ok) { std::fprintf(stderr, "FAIL: %s\n", m); std::exit(1); } }

// signed fields: the numeric order survives packing, for every width
static_assert(Dense<int8_t, int8_t>(-1, 5) < Dense<int8_t, int8_t>(0, -5), "-1 sorts below 0 in the first field");
static_assert(Dense<int8_t, int8_t>(0, -5) < Dense<int8_t, int8_t>(0, -4), "and in the second");
static_assert(Dense<int32_t, int32_t>(-2147483647 - 1, 0) < Dense<int32_t, int32_t>(-1, 0));
static_assert(Dense<int64_t, int64_t>(-1, -1).first() == -1 && Dense<int64_t, int64_t>(-1, -1).second() == -1);
static_assert(Dense<int16_t, int32_t>(-300, 70000).first() == -300 && Dense<int16_t, int32_t>(-300, 70000).second() == 70000);
static_assert(Dense<int16_t, int32_t>::bits == 48);
// bool is one bit, an enum its underlying width
static_assert(Dense<bool, uint32_t>::bits == 33);
static_assert(Dense<bool, uint32_t>(true, 7).first() && Dense<bool, uint32_t>(true, 7).second() == 7);
static_assert(Dense<bool, uint32_t>(false, 9) < Dense<bool, uint32_t>(true, 0));
static_assert(Dense<Kind, uint32_t>::bits == 40 && Dense<Kind, uint32_t>(Kind::C, 3).first() == Kind::C);
static_assert(Dense<Kind, uint32_t>(Kind::A, 9) < Dense<Kind, uint32_t>(Kind::B, 0));
// a nest of every shape: a twin of twins in one integer
using Mixed = Dense<Dense<int16_t, bool>, Dense<Kind, uint32_t>>;
static_assert(Mixed::bits == 16 + 1 + 8 + 32 && sizeof(Mixed) == 8, "57 bits, one word");
static_assert(Mixed(Dense<int16_t, bool>(-7, true), Dense<Kind, uint32_t>(Kind::B, 123)).first().first() == -7);
static_assert(Mixed(Dense<int16_t, bool>(-7, true), Dense<Kind, uint32_t>(Kind::B, 123)).second().second() == 123);
// a combinator over the shapes, in order
constexpr auto packed = dense(int8_t(-3), true, Kind::C, uint16_t(500), int32_t(-70000));
static_assert(packed.bits == 8 + 1 + 8 + 16 + 32);
static_assert(packed.first() == -3 && packed.second().first() == true && packed.second().second().first() == Kind::C);
static_assert(packed.second().second().second().second() == -70000);

int main() {
  // a pointer travels as a word and comes back
  int x = 0; Dense<uint32_t, int *> p(7, &x);
  require(p.first() == 7 && p.second() == &x, "pointer round trip");
  // randomized: the packed compare equals the tuple compare, for signed fields of three widths
  uint64_t s = 88172645463325252ull; auto rng = [&] { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; };
  for (int i = 0; i < 2000000; i++) {
    int8_t a1 = int8_t(rng()), a2 = int8_t(rng()); int32_t b1 = int32_t(rng()), b2 = int32_t(rng());
    Dense<int8_t, int32_t> u(a1, b1), v(a2, b2);
    bool tuple = a1 != a2 ? a1 < a2 : b1 < b2;
    require((u < v) == tuple, "packed order equals tuple order");
    require(u.first() == a1 && u.second() == b1, "round trip");
  }
  std::puts("PASS dense: signed, bool, enum, pointer, nests; 2,000,000 random orderings");
}
