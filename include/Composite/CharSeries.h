#pragma once

// TrikeShed's CharSeries (../TrikeShed/src/commonMain/kotlin/borg/trikeshed/lib/CharSeries.kt), in C++.
//
// A window of characters that is never copied, a cursor over it, equality by content, no hash, and text made only at the gate.
//
//   CharWindow       the window: where it starts and how long it is, 16 bytes, the weight of a std::string_view.  Kotlin keeps a root
//                    and TwInt bounds so that a window of a window reads the same root instead of stacking accessors (CharWindow
//                    flattening); in C++ the start is a pointer and the flattening is the pointer arithmetic, base + from.
//   CharSeries       a window and its cursor (pos/limit/mark, relative to the window): get, mk, res, flip, rew, clr, lim, slice, skipWs,
//                    rtrim, trim, seekTo; 24 bytes.  The weight is the cursor's: where only a window is needed (the pieces of a
//                    string being built) a CharWindow is used.
//   ==               the same characters between pos and limit.  The cursor's position is not identity.
//   no hash          a cursor is not a key: there is no std::hash for it.  Reify at the gate (view()) and key on that.
//   view()           the gate: a std::string_view of pos..limit, for an API that wants one.  The window is NOT terminated
//                    (facet<text::Terminated> says whether its bytes are a C string as they stand).
//
// No loop is written here (every walk is a fold or firstWhere over a Series) and no libc is called: whitespace is tested without
// <cctype>, and running past the limit is TODO().

#include "Composite/Pack.h"
#include "Composite/Series.h"

#include <string_view>

namespace composite {

/// Kotlin's Char.isWhitespace for the ASCII range, without <cctype>.
constexpr bool isWs(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

/// The window: contiguous characters, viewed.  A Series<char> (size and index), and a window of a window is a window of the same bytes.
struct CharWindow {
  const char *base = nullptr;  // the first character of the window: never owned, never copied
  uint32_t len = 0;

  constexpr CharWindow() = default;
  constexpr CharWindow(const char *b, uint32_t n) : base(b), len(n) {}
  constexpr explicit CharWindow(std::string_view s) : base(s.data()), len(uint32_t(s.size())) {}

  constexpr uint32_t size() const { return len; }
  constexpr char operator[](uint32_t i) const { return base[i]; }
  constexpr const char *data() const { return base; }
  constexpr auto series() const { return len |j| [b = base](uint32_t i) { return b[i]; }; }
  constexpr std::string_view view() const { return {base, len}; }
  /// A window of this window: the same bytes, from + base.
  constexpr CharWindow operator[](join::TwInt r) const {
    if (r.first() > r.second() || r.second() > len) TODO("CharWindow outside its bounds");
    return CharWindow(base + r.first(), r.second() - r.first());
  }
};

struct CharSeries : CharWindow {
  uint32_t pos = 0, limit = 0;
  int32_t mark = -1;

  constexpr CharSeries() = default;
  constexpr CharSeries(CharWindow w) : CharWindow(w), limit(w.len) {}
  constexpr CharSeries(const char *b, uint32_t n) : CharSeries(CharWindow(b, n)) {}
  /// Any contiguous characters, viewed: the conversion is the window.
  constexpr explicit CharSeries(std::string_view s) : CharSeries(CharWindow(s)) {}

  /// A window of this window, as a fresh cursor over it.
  constexpr CharSeries operator[](join::TwInt r) const { return CharSeries(CharWindow::operator[](r)); }
  using CharWindow::operator[];
  /// The window between the cursor's position and its limit.
  constexpr CharSeries slice() const { return (*this)[join::TwInt(pos, limit)]; }

// The cursor.
  constexpr uint32_t rem() const { return limit - pos; }
  constexpr bool hasRemaining() const { return pos < limit; }
  constexpr bool isExhausted() const { return pos == limit; }
  /// get, the verb: the character at the position, and advance.
  constexpr char get() {
    if (!hasRemaining()) TODO("CharSeries::get past the limit");
    return (*this)[pos++];
  }
  constexpr CharSeries &mk() { mark = int32_t(pos); return *this; }
  constexpr CharSeries &res() { if (mark >= 0) pos = uint32_t(mark); return *this; }
  constexpr CharSeries &flip() { limit = pos; pos = 0; mark = -1; return *this; }
  constexpr CharSeries &rew() { pos = 0; return *this; }
  constexpr CharSeries &clr() { pos = 0; limit = size(); mark = -1; return *this; }
  constexpr CharSeries &lim(uint32_t l) { limit = l; return *this; }
  constexpr CharSeries &at(uint32_t p) { pos = p; return *this; }

  /// The characters between the cursor's position and its limit, as a Series.
  constexpr auto remaining() const { return rem() |j| [r = data() + pos](uint32_t i) { return r[i]; }; }

  /// Skip whitespace from the position.
  constexpr CharSeries &skipWs() { pos += firstWhere(remaining(), [](char c) { return !isWs(c); }); return *this; }
  /// Drop whitespace before the limit.
  constexpr CharSeries &rtrim() {
    auto back = rem() |j| [this](uint32_t i) { return (*this)[limit - 1 - i]; };
    limit -= firstWhere(back, [](char c) { return !isWs(c); });
    return *this;
  }
  constexpr CharSeries &trim() { return skipWs().rtrim(); }

  /// Move the position past the next `target` and say so; on failure the position is unchanged.
  constexpr bool seekTo(char target) {
    uint32_t k = firstWhere(remaining(), [target](char c) { return c == target; });
    if (k == rem()) return false;
    pos += k + 1;
    return true;
  }
  /// The same, where `escape` hides the character after it.
  constexpr bool seekTo(char target, char escape) {
    struct Scan { uint32_t at; bool escaped, found; };
    Scan s = fold(remaining(), Scan{0, false, false},
                  [&](Scan acc, char c) {
                    ++acc.at;
                    if (acc.escaped) acc.escaped = false;
                    else if (c == target) acc.found = true;
                    else if (c == escape) acc.escaped = true;
                    return acc;
                  },
                  [](const Scan &acc) { return acc.found; });
    if (!s.found) return false;
    pos += s.at;
    return true;
  }

  /// Equality is the same characters between pos and limit.
  friend constexpr bool operator==(const CharSeries &a, const CharSeries &b) {
    if (a.rem() != b.rem()) return false;
    auto ra = a.remaining(), rb = b.remaining();
    return firstWhere(iota(a.rem()), [&](uint32_t i) { return ra[i] != rb[i]; }) == a.rem();
  }

  /// The gate: the characters between pos and limit, as a std::string_view for an API that wants one.
  constexpr std::string_view view() const { return {data() + pos, rem()}; }
  /// The window between pos and limit, without the cursor.
  constexpr CharWindow window() const { return CharWindow(data() + pos, rem()); }
};

/// Lazy split on a delimiter: a Series of windows, the delimiters found once.
inline auto split(const CharSeries &s, char delim) {
  MutableSeries<uint32_t> cuts;
  fold(iota(s.size()), 0u, [&](uint32_t, uint32_t i) { if (s[i] == delim) cuts.append(i); return 0u; });
  uint32_t parts = cuts.size() + 1;
  return parts |j| [s, cuts = std::move(cuts)](uint32_t k) {
    uint32_t from = k == 0 ? 0 : cuts[k - 1] + 1, to = k == cuts.size() ? s.size() : cuts[k];
    return s[join::TwInt(from, to)];
  };
}

// ── Facets: TrikeShed's TextK (../TrikeShed/src/commonMain/kotlin/borg/trikeshed/charstr/TextK.kt) ─────────────────────────────────────────
//
// A string is a point in TextK-space: each facet is a typed projection whose result type the key fixes (TextK's GADT).  Here a key is a
// type carrying its result type R, and facet<K>(chars) is resolved at compile time: TextK keeps its hot set to three for bimorphic JIT
// inlining; C++ dispatch costs nothing at any size.  Each reads the window from pos to limit, as a fold.

namespace text {
/// SizeK.
struct Bytes { using R = uint32_t; };
struct Codepoints { using R = uint32_t; };            // UTF-8: bytes that are not continuation bytes
/// HashK.
struct FNV1a { using R = uint64_t; };
/// EvidenceK: the character-class counts, all in one pass (TrikeShed memoizes them together).
struct Counts { uint16_t digits = 0, periods = 0, exponent = 0, signs = 0, alpha = 0, whitespace = 0, quotes = 0, other = 0; };
struct Evidence { using R = Counts; };
/// The most specific type the text can be read as (DeducedIOMemento): from the evidence, then the shape.
enum class Memento : uint8_t { Empty, Bool, Int, Float, String };
struct Deduced { using R = Memento; };
/// Is the window followed by a NUL?  Then its own bytes are a C string and need no copy.  Reads one byte past the window, which must be
/// readable: true of an arena string (copyString terminates it), a std::string and a literal, all of whose windows this is for.
struct Terminated { using R = bool; };
/// A reading of an integer: the value, whether it overflowed, and how many characters were read (0 when nothing could be).
struct Reading { uint64_t value = 0; bool overflow = false; bool negative = false; uint32_t consumed = 0; };
/// The integer reading C's strtoll (Signed) and strtoull (unsigned) make, in Base, without libc: leading whitespace, an optional sign, for
/// base 16 an optional 0x, then digits; on overflow the value saturates and overflow is set (ERANGE); with no digits nothing is consumed.
/// An unsigned reading of "-n" is the negation of n modulo 2^64, as strtoull's is.
template <unsigned Base, bool Signed> struct Integer { using R = Reading; };
} // namespace text

constexpr bool isDigitIn(char c, unsigned base) {
  unsigned d = c >= '0' && c <= '9' ? unsigned(c - '0') : c >= 'a' && c <= 'z' ? unsigned(c - 'a' + 10) : c >= 'A' && c <= 'Z' ? unsigned(c - 'A' + 10) : 99u;
  return d < base;
}
constexpr unsigned digitValue(char c) {
  return c >= '0' && c <= '9' ? unsigned(c - '0') : c >= 'a' && c <= 'z' ? unsigned(c - 'a' + 10) : unsigned(c - 'A' + 10);
}
constexpr bool isAsciiDigit(char c) { return c >= '0' && c <= '9'; }
constexpr bool isAsciiAlnum(char c) { return isAsciiDigit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }

template <class K> constexpr typename K::R facet(const CharSeries &s);

template <> constexpr uint32_t facet<text::Bytes>(const CharSeries &s) { return s.rem(); }
template <> constexpr bool facet<text::Terminated>(const CharSeries &s) { return s.data()[s.limit] == '\0'; }
template <> constexpr uint32_t facet<text::Codepoints>(const CharSeries &s) {
  return fold(s.remaining(), 0u, [](uint32_t n, char c) { return n + ((static_cast<unsigned char>(c) & 0xC0) != 0x80); });
}
template <> constexpr uint64_t facet<text::FNV1a>(const CharSeries &s) {
  return fold(s.remaining(), uint64_t(0xcbf29ce484222325ull),
              [](uint64_t h, char c) { return (h ^ static_cast<unsigned char>(c)) * 0x100000001b3ull; });
}
template <> constexpr text::Counts facet<text::Evidence>(const CharSeries &s) {
  return fold(s.remaining(), text::Counts{}, [](text::Counts k, char c) {
    if (isAsciiDigit(c)) ++k.digits;
    else if (c == '.') ++k.periods;
    else if (c == 'e' || c == 'E') { ++k.exponent; ++k.alpha; }
    else if (c == '+' || c == '-') ++k.signs;
    else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) ++k.alpha;
    else if (isWs(c)) ++k.whitespace;
    else if (c == '"' || c == '\'') ++k.quotes;
    else ++k.other;
    return k;
  });
}
template <> constexpr text::Memento facet<text::Deduced>(const CharSeries &s) {
  if (s.rem() == 0) return text::Memento::Empty;
  std::string_view v = s.view();
  if (v == "true" || v == "false") return text::Memento::Bool;
  text::Counts k = facet<text::Evidence>(s);
  uint32_t lead = v[0] == '+' || v[0] == '-' ? 1 : 0;
  if (k.digits == 0 || k.whitespace || k.quotes || k.other || k.alpha > k.exponent) return text::Memento::String;
  if (k.periods == 0 && k.exponent == 0 && k.signs == lead) return text::Memento::Int;
  return k.periods <= 1 && k.exponent <= 1 ? text::Memento::Float : text::Memento::String;
}

template <unsigned Base, bool Signed> constexpr text::Reading readInteger(const CharSeries &s) {
  CharSeries c = s;
  c.skipWs();
  text::Reading r;
  if (c.hasRemaining() && (c[c.pos] == '+' || c[c.pos] == '-')) { r.negative = c[c.pos] == '-'; c.at(c.pos + 1); }
  if (Base == 16 && c.rem() >= 3 && c[c.pos] == '0' && (c[c.pos + 1] == 'x' || c[c.pos + 1] == 'X') && isDigitIn(c[c.pos + 2], 16))
    c.at(c.pos + 2);
  uint32_t digits = firstWhere(c.remaining(), [](char ch) { return !isDigitIn(ch, Base); });
  if (digits == 0) return text::Reading{};      // nothing read: strtoll and strtoull return 0 and point at the start
  // the magnitude, saturating: the limit is 2^63 for a negative signed reading, 2^63 - 1 for a positive one, 2^64 - 1 unsigned
  uint64_t limit = Signed ? (r.negative ? uint64_t(1) << 63 : (uint64_t(1) << 63) - 1) : ~uint64_t(0);
  struct Acc { uint64_t v; bool over; };
  Acc a = fold(iota(digits), Acc{0, false}, [&](Acc acc, uint32_t i) {
    uint64_t d = digitValue(c[c.pos + i]);
    if (acc.over || acc.v > (limit - d) / Base) return Acc{limit, true};
    return Acc{acc.v * Base + d, false};
  });
  r.overflow = a.over;
  r.value = Signed ? (r.negative && !a.over ? uint64_t(0) - a.v : (r.negative ? uint64_t(1) << 63 : a.v))
                   : (a.over ? ~uint64_t(0) : (r.negative ? uint64_t(0) - a.v : a.v));
  r.consumed = c.pos + digits - s.pos;
  return r;
}
template <> constexpr text::Reading facet<text::Integer<10, true>>(const CharSeries &s) { return readInteger<10, true>(s); }
template <> constexpr text::Reading facet<text::Integer<10, false>>(const CharSeries &s) { return readInteger<10, false>(s); }
template <> constexpr text::Reading facet<text::Integer<16, false>>(const CharSeries &s) { return readInteger<16, false>(s); }
template <> constexpr text::Reading facet<text::Integer<8, false>>(const CharSeries &s) { return readInteger<8, false>(s); }
template <> constexpr text::Reading facet<text::Integer<2, false>>(const CharSeries &s) { return readInteger<2, false>(s); }

} // namespace composite
