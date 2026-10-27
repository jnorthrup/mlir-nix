//===- Pack.h - Hard densification: a Join of scalars is one integer ---------===//
//
// The layout of !trikeshed.join<A, B> (include/Composite/TrikeShed.td), for C++: a Join of fixed-width
// scalars is ONE unsigned integer, the first component in the high bits, so that building it is
// shifts and ors, taking it apart is shifts and masks, and comparing two of them is comparing two
// integers, which orders them by their first component, then the second.  Joins nest, and a nest
// is one integer too (<i32, <i32, i32>> is an i96).  The constructor is a
// combinator: `dense(a, b, c)` is `Dense<A, Dense<B, C>>(a, Dense<B, C>(b, c))`, built from the types
// of its arguments, so no record of scalars needs hand-written packing.
//
//   Dense<A, B>   A and B are unsigned integers, float, double, `Bits<N>`, or a Dense; at most 128 bits in all.
//                 Ordering and equality are those of the integer, so a float orders by its bits.
//   TwInt         Twin<Int> collapsed to a Long: Dense<uint32_t, uint32_t>, the frontend's currency
//                 for segments of an immutable buffer (the lexer stores (start, end) and never
//                 touches the input), and the `file j row` of a deferred lambda
//   Bits<N>       a field of N bits that is not a whole number of bytes (a tag, a 19-bit file number)
//
// Plain C++, no MLIR.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_PACK_H
#define COMPOSITE_PACK_H

#include <bit>
#include <compare>
#include <concepts>
#include <cstdint>
#include <type_traits>

namespace join {

template <unsigned N> struct Bits {
  static_assert(N >= 1 && N <= 64, "a field is one machine word at most");
  static constexpr uint64_t mask = N == 64 ? ~uint64_t(0) : (uint64_t(1) << N) - 1;
  uint64_t v = 0;
  constexpr Bits() = default;
  constexpr explicit Bits(uint64_t x) : v(x & mask) {}
  constexpr auto operator<=>(const Bits &) const = default;
};

template <class T> struct Width;
template <std::unsigned_integral T> struct Width<T> {
  static constexpr unsigned value = sizeof(T) * 8;
};
template <unsigned N> struct Width<Bits<N>> {
  static constexpr unsigned value = N;
};
template <> struct Width<float> {
  static constexpr unsigned value = 32;
};
template <> struct Width<double> {
  static constexpr unsigned value = 64;
};
template <class T> inline constexpr unsigned width = Width<T>::value;

template <class A, class B> struct Dense;
template <class A, class B> struct Width<Dense<A, B>> {
  static constexpr unsigned value = width<A> + width<B>;
};

namespace detail {
using u128 = unsigned __int128;
template <unsigned W> using RawOf = std::conditional_t<(W <= 64), uint64_t, u128>;

/// How a field goes into a raw word and comes back out of it.
template <class T> struct Field;
template <std::unsigned_integral T> struct Field<T> {
  template <class R> static constexpr R put(T x) { return R(x); }
  template <class R> static constexpr T get(R r) { return T(r); }
};
template <unsigned N> struct Field<Bits<N>> {
  template <class R> static constexpr R put(Bits<N> x) { return R(x.v); }
  template <class R> static constexpr Bits<N> get(R r) { return Bits<N>(uint64_t(r)); }
};
/// Floats travel as their bits.
template <> struct Field<float> {
  template <class R> static constexpr R put(float x) { return R(std::bit_cast<uint32_t>(x)); }
  template <class R> static constexpr float get(R r) { return std::bit_cast<float>(uint32_t(r)); }
};
template <> struct Field<double> {
  template <class R> static constexpr R put(double x) { return R(std::bit_cast<uint64_t>(x)); }
  template <class R> static constexpr double get(R r) { return std::bit_cast<double>(uint64_t(r)); }
};
template <class A, class B> struct Field<Dense<A, B>> {
  template <class R> static constexpr R put(Dense<A, B> x) { return R(x.raw); }
  template <class R> static constexpr Dense<A, B> get(R r) { return Dense<A, B>(typename Dense<A, B>::Raw(r)); }
};
} // namespace detail

template <class A, class B> struct Dense {
  static constexpr unsigned bits = width<A> + width<B>;
  static_assert(bits <= 128, "wider than the i128 of the dialect's test");
  using Raw = detail::RawOf<bits>;
  static constexpr Raw mask = bits >= 8 * sizeof(Raw) ? ~Raw(0) : (Raw(1) << bits) - 1;

  Raw raw = 0;
  constexpr Dense() = default;
  constexpr Dense(A a, B b)
      : raw((detail::Field<A>::template put<Raw>(a) << width<B>) | detail::Field<B>::template put<Raw>(b)) {}
  constexpr explicit Dense(Raw r) : raw(r & mask) {}
  constexpr A first() const { return detail::Field<A>::template get<Raw>(raw >> width<B>); }
  constexpr B second() const { return detail::Field<B>::template get<Raw>(raw); }
  constexpr auto operator<=>(const Dense &) const = default;
};

/// The constructor combinator: the fields in order, the first in the high bits, nested to the right.
template <class A> constexpr A dense(A a) { return a; }
template <class A, class B, class... Rest> constexpr auto dense(A a, B b, Rest... rest) {
  if constexpr (sizeof...(Rest) == 0) {
    return Dense<A, B>(a, b);
  } else {
    auto tail = dense(b, rest...);
    return Dense<A, decltype(tail)>(a, tail);
  }
}

using TwInt = Dense<uint32_t, uint32_t>;

// The layout TrikeShed.td states: (7 j 9) : !trikeshed.join<i32, i32> is this i64.
static_assert(TwInt(7, 9).raw == 30064771081ull, "TwInt and TrikeShed.td disagree on the layout");
static_assert(TwInt(7, 9).first() == 7 && TwInt(7, 9).second() == 9);
// A segment: (3, (10, 17)) : !trikeshed.join<i32, !trikeshed.join<i32, i32>> is the i96 55340232264078327825
// = 3 * 2^64 + 42949672977.  C++ has no 96-bit literal, so the two halves are compared.
static_assert((dense(uint32_t(3), uint32_t(10), uint32_t(17)).raw >> 64) == 3 &&
              uint64_t(dense(uint32_t(3), uint32_t(10), uint32_t(17)).raw) == 42949672977ull);
// Twin<i64>: (1, 2) : !trikeshed.join<i64, i64> is the i128 18446744073709551618 = 2^64 + 2.
static_assert(dense(uint64_t(1), uint64_t(2)).raw == ((detail::u128(1) << 64) | 2));
// (1.0f, 5) : !trikeshed.join<f32, i32> is the i64 4575657221408423941 (1.0f = 0x3F800000).
static_assert(dense(1.0f, uint32_t(5)).raw == 4575657221408423941ull);
static_assert(dense(1.0f, uint32_t(5)).first() == 1.0f && dense(1.0f, uint32_t(5)).second() == 5);
// A segment <i32, <i32, i32>> is the dialect's i96: the first component in the high 32 bits of 96.
static_assert(dense(uint32_t(1), uint32_t(2), uint32_t(3)).raw == ((detail::u128(1) << 64) | (detail::u128(2) << 32) | 3));
static_assert(dense(uint32_t(1), uint32_t(2), uint32_t(3)).bits == 96 && sizeof(dense(uint32_t(1), uint32_t(2), uint32_t(3))) == 16);
static_assert(dense(uint32_t(1), uint32_t(2), uint32_t(3)).second().first() == 2);
// Comparing the words is comparing the pairs: first component, then second.
static_assert(TwInt(1, 9) < TwInt(2, 0) && TwInt(2, 0) < TwInt(2, 1));
// A field that is not a whole number of bytes: a 1 + 19 + 24 + 20 bit word.
static_assert(dense(Bits<1>(1), Bits<19>(7), Bits<24>(11), Bits<20>(13)).raw ==
              ((uint64_t(1) << 63) | (uint64_t(7) << 44) | (uint64_t(11) << 20) | 13));
static_assert(dense(Bits<1>(1), Bits<19>(7), Bits<24>(11), Bits<20>(13)).second().second().second().v == 13);

} // namespace join

#endif
