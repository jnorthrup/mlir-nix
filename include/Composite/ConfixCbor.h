//===- ConfixCbor.h - a CBOR item indexed: TrikeShed's Confix, Syntax.CBOR, and deterministic encoding --------------===//
//
// TrikeShed's Syntax.CBOR (parse/confix/Confix.kt `scanCbor0`, read here from the LLVM IR the Kotlin/Native compiler makes of it, with
// `-Xsave-llvm-ir-after=MandatoryBitcodeLLVMPostprocessingPhase`) indexes an item by the spans of its elements.  This is that scan on the
// index of Confix.h: the same Cursor (a row for each element, in the order they open; columns span, tag, kids), so a consumer reads a JSON
// index and a CBOR index alike.  It differs from the Kotlin scan where the IR shows the Kotlin one wrong or loose, and says where:
//
//   - A length of four bytes (additional information 26) is read as an unsigned 32-bit number.  The Kotlin readLength sign-extends it
//     (`sext i32 to i64` in the IR), so a length from 2^31 up reads as negative, which the scan takes for an indefinite length.
//   - A length that does not fit in the text is a fault (EndOfInput), not a read past the end; a length is never truncated to 32 bits.
//   - An indefinite string is a row of its own, from its head to its break byte, its chunks checked (Chunk).  The Kotlin scan adds no row for
//     the head, parses the chunks as items of the level above and the break as a Nothing row.
//   - The rows are made in the order the elements open, with the children of a container set as it closes (the Kotlin scan adds a row after
//     its children and sorts them by offset).  No recursion: the open containers are a stack, so any depth takes the space of its index.
//   - One data item and then the end of the text (Trailing otherwise).  The Kotlin scan reads items until the text is used up.
//   - A tag (major type 6) makes no row: the row is of the item inside it, as in the Kotlin scan.
//   - A text string is checked to be UTF-8 (InvalidUtf8), a break outside an indefinite container is a fault (Break) and so is a simple value
//     under 32 in two bytes or an additional information from 28 to 30 (Reserved).
//
// `deterministic` is RFC 8949 section 4.2.1: every head and every float in its shortest form (NonShortest), no indefinite length
// (Indefinite), the keys of a map in bytewise order of their encodings and none twice (KeyOrder).  A NaN is only the half 0x7e00.
// `encodeJson` writes the deterministic encoding of a JSON index, so equal documents give equal bytes (a content address).
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_CONFIX_CBOR_H
#define COMPOSITE_CONFIX_CBOR_H

#include "Composite/Confix.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace composite::confix {

/// The head of a CBOR item: its major type, its additional information, the number it holds (a length, a count, an integer, a float's
/// bits, a simple value) and the offset where its payload starts.
struct CborHead {
  uint8_t major = 0, info = 0;
  uint64_t value = 0;
  uint32_t payload = 0;
};

/// The head at p, in a text of n bytes.  None, EndOfInput (the head is cut off), or Reserved (additional information 28 to 30).  Additional
/// information 31 is an indefinite length or a break: `value` is 0 and the caller says which.
inline Fault cborHead(const uint8_t *s, uint32_t n, uint32_t p, CborHead &h) {
  if (p >= n) return Fault::EndOfInput;
  h.major = s[p] >> 5;
  h.info = s[p] & 31;
  uint32_t q = p + 1;
  if (h.info < 24) {
    h.value = h.info;
  } else if (h.info <= 27) {
    uint32_t width = 1u << (h.info - 24);
    if (n - q < width) return Fault::EndOfInput;
    uint64_t v = 0;
    for (uint32_t i = 0; i < width; i++) v = (v << 8) | s[q + i];
    h.value = v;
    q += width;
  } else if (h.info == 31) {
    h.value = 0;
  } else {
    return Fault::Reserved;
  }
  h.payload = q;
  return Fault::None;
}

/// The offset of the first byte that is not UTF-8 in s[0, n) (the shortest form, no surrogate, nothing over U+10FFFF), or n.
inline uint32_t badUtf8(const uint8_t *s, uint32_t n) {
  for (uint32_t i = 0; i < n;) {
    uint8_t c = s[i];
    if (c < 0x80) {
      i++;
      continue;
    }
    uint32_t len;
    uint8_t lo = 0x80, hi = 0xBF;
    if (c >= 0xC2 && c <= 0xDF) len = 2;
    else if (c == 0xE0) { len = 3; lo = 0xA0; }
    else if (c == 0xED) { len = 3; hi = 0x9F; }
    else if (c >= 0xE1 && c <= 0xEF) len = 3;
    else if (c == 0xF0) { len = 4; lo = 0x90; }
    else if (c == 0xF4) { len = 4; hi = 0x8F; }
    else if (c >= 0xF1 && c <= 0xF3) len = 4;
    else return i;
    if (n - i < len || s[i + 1] < lo || s[i + 1] > hi) return i;
    for (uint32_t k = 2; k < len; k++)
      if ((s[i + k] & 0xC0) != 0x80) return i;
    i += len;
  }
  return n;
}

/// The half-precision float with the value of d, when there is one: the bits in h.  (Any NaN has none.)
inline bool halfOf(double d, uint16_t &h) {
  if (std::isnan(d)) return false;
  uint16_t sign = std::signbit(d) ? 0x8000 : 0;
  double a = std::fabs(d);
  if (std::isinf(d)) { h = sign | 0x7c00; return true; }
  if (a == 0) { h = sign; return true; }
  int e;
  double m = std::frexp(a, &e); // a = m * 2^e with m in [0.5, 1)
  if (e - 1 >= -14) {           // a normal half: 2^-14 up to 2^16
    if (e - 1 > 15) return false;
    double frac = std::ldexp(m * 2 - 1, 10);
    if (frac != std::floor(frac)) return false;
    h = sign | uint16_t(uint32_t(e - 1 + 15) << 10 | uint32_t(frac));
    return true;
  }
  double k = std::ldexp(a, 24); // a subnormal half: k * 2^-24
  if (k != std::floor(k)) return false;
  h = sign | uint16_t(k);
  return true;
}

/// Whether a float holds d as it is: an infinity, or a finite value in range that survives the narrowing.  (A NaN has no value to keep.)
inline bool fitsFloat(double d) { return std::isinf(d) || (std::fabs(d) <= double(FLT_MAX) && double(float(d)) == d); }

/// The value of a half.
inline double halfValue(uint16_t h) {
  int exponent = (h >> 10) & 31;
  int fraction = h & 0x3FF;
  double v = exponent == 0 ? std::ldexp(double(fraction), -24)
             : exponent == 31 ? (fraction == 0 ? HUGE_VAL : std::nan(""))
                              : std::ldexp(double(1024 + fraction), exponent - 25);
  return h & 0x8000 ? -v : v;
}

/// The value of a Double row (a half, a float or a double) at open.
inline double cborDouble(const uint8_t *s, uint32_t open) {
  CborHead h;
  cborHead(s, 0xFFFFFFFFu, open, h);
  if (h.info == 25) return halfValue(uint16_t(h.value));
  if (h.info == 26) {
    uint32_t b = uint32_t(h.value);
    float f;
    std::memcpy(&f, &b, 4);
    return f;
  }
  double d;
  std::memcpy(&d, &h.value, 8);
  return d;
}

/// The value of a Long row at open: an unsigned integer, or -1 - n for a negative one.  (A Long row is within an int64: the scan says
/// Unsigned of one that is not.)
inline int64_t cborLong(const uint8_t *s, uint32_t open) {
  CborHead h;
  cborHead(s, 0xFFFFFFFFu, open, h);
  return h.major == 0 ? int64_t(h.value) : -1 - int64_t(h.value);
}

/// The bytes of a String or Bytes row at open, put into out: the payload of a definite string, the chunks of an indefinite one in turn.
template <class Out> void cborString(const uint8_t *s, uint32_t open, Out &out) {
  CborHead h;
  cborHead(s, 0xFFFFFFFFu, open, h);
  if (h.info != 31) {
    putRun(out, reinterpret_cast<const char *>(s + h.payload), uint32_t(h.value));
    return;
  }
  for (uint32_t q = h.payload; s[q] != 0xFF;) {
    CborHead c;
    cborHead(s, 0xFFFFFFFFu, q, c);
    putRun(out, reinterpret_cast<const char *>(s + c.payload), uint32_t(c.value));
    q = c.payload + uint32_t(c.value);
  }
}

namespace cbor_detail {

/// Whether the head h is in its shortest form: the smallest additional information that holds its value.
constexpr bool shortest(const CborHead &h) {
  if (h.info < 24) return true;
  if (h.info == 24) return h.value >= 24;
  if (h.info == 25) return h.value > 0xFF;
  if (h.info == 26) return h.value > 0xFFFF;
  return h.value > 0xFFFFFFFFull;
}

/// Whether a float head (information 25, 26 or 27) holds a value a shorter float holds, or a NaN that is not 0x7e00.
inline bool reducible(const CborHead &h) {
  if (h.info == 25) return h.value != 0x7e00 && (h.value & 0x7c00) == 0x7c00 && (h.value & 0x3ff) != 0;
  if (h.info == 26) {
    uint32_t b = uint32_t(h.value);
    float f;
    std::memcpy(&f, &b, 4);
    uint16_t half;
    return std::isnan(f) || halfOf(f, half);
  }
  double d;
  std::memcpy(&d, &h.value, 8);
  return std::isnan(d) || fitsFloat(d);
}

} // namespace cbor_detail

/// Scan one CBOR data item into `ix` (cleared first).  `deterministic` also holds the item to RFC 8949 section 4.2.1.
/// The row of a string is from its head to its last byte; of a container, from its head to the last byte of its last element (the break
/// byte of an indefinite one); of a number, its head and its payload.  A Boolean is one byte (0xF4 or 0xF5), a Nothing the byte of null,
/// undefined or an unassigned simple value.
inline Scan scanCbor(Chars src, Index &ix, bool deterministic = false) {
  ix.clear();
  const uint8_t *s = reinterpret_cast<const uint8_t *>(src.data());
  const uint32_t n = src.size();
  uint32_t p = 0, itemStart = 0;
  MutableSeries<join::TwInt> open; // the containers still open: their row j where their children start in `pend`
  MutableSeries<uint64_t> left;    // the items a definite container still lacks
  MutableSeries<uint8_t> indef;    // whether the container is indefinite
  MutableSeries<uint32_t> pend;    // the rows finished inside them
  MutableSeries<uint32_t> starts;  // the first byte of each row's item, its tags included
  auto bad = [&](Fault f, uint32_t at) { return Scan{f, at, 0}; };
  auto row = [&](Tag t, uint32_t from, uint32_t to) {
    uint32_t r = ix.rows.append(join::TwInt(from, to), t, join::TwInt(0, 0));
    starts.append(itemStart);
    if (open.size()) pend.append(r);
    return r;
  };
  // The container on top ends at byte `at`: its end, its children (which leave `pend` for `kids`), and in a deterministic reading its keys.
  auto shut = [&](uint32_t at) -> Scan {
    join::TwInt top = open.back();
    open.pop();
    left.pop();
    indef.pop();
    uint32_t r = top.first(), from = top.second(), count = pend.size() - from, first = ix.kids.size();
    for (uint32_t i = 0; i < count; i++) ix.kids.append(pend[from + i]);
    pend.resize(from);
    ix.rows.col<Col::Span>()[r] = join::TwInt(ix.rows.col<Col::Span>()[r].first(), at);
    ix.rows.col<Col::Kids>()[r] = join::TwInt(first, count);
    if (deterministic && ix.tag(r) == Tag::Object) {
      for (uint32_t k = 2; k < count; k += 2) {
        uint32_t a = ix.kids[first + k - 2], b = ix.kids[first + k];
        uint32_t la = ix.close(a) + 1 - starts[a], lb = ix.close(b) + 1 - starts[b];
        int c = std::memcmp(s + starts[a], s + starts[b], la < lb ? la : lb);
        if (c > 0 || (c == 0 && la >= lb)) return bad(Fault::KeyOrder, ix.open(b));
      }
    }
    return {};
  };
  // An item ended before byte `end`: the definite containers it completes close.
  auto finish = [&](uint32_t end) -> Scan {
    while (open.size() && !indef.back()) {
      if (--left.back() > 0) break;
      if (Scan e = shut(end - 1)) return e;
    }
    return {};
  };

  for (;;) {
    itemStart = p;
    uint8_t b;
    for (;;) { // the tags before the item
      if (p >= n) return bad(Fault::EndOfInput, p);
      b = s[p];
      if ((b >> 5) != 6) break;
      CborHead t;
      if (Fault f = cborHead(s, n, p, t); f != Fault::None) return bad(f, p);
      if (t.info == 31) return bad(Fault::Reserved, p);
      if (deterministic && !cbor_detail::shortest(t)) return bad(Fault::NonShortest, p);
      p = t.payload;
    }
    if (b == 0xFF) { // a break: it ends the indefinite container on top
      if (p != itemStart || open.empty() || !indef.back()) return bad(Fault::Break, p);
      if (ix.tag(open.back().first()) == Tag::Object && ((pend.size() - open.back().second()) & 1)) return bad(Fault::Break, p);
      if (Scan e = shut(p)) return e;
      p++;
      if (Scan e = finish(p)) return e;
      if (open.empty()) break;
      continue;
    }
    CborHead h;
    if (Fault f = cborHead(s, n, p, h); f != Fault::None) return bad(f, p);
    const bool indefinite = h.info == 31;
    if (deterministic && indefinite && h.major >= 2 && h.major <= 5) return bad(Fault::Indefinite, p);
    if (deterministic && !indefinite && h.major != 7 && !cbor_detail::shortest(h)) return bad(Fault::NonShortest, p);
    switch (h.major) {
    case 0:
    case 1:
      if (indefinite) return bad(Fault::Reserved, p);
      if (h.value > uint64_t(INT64_MAX)) return Scan{Fault::Unsigned, p, h.payload};
      row(Tag::Long, p, h.payload - 1);
      p = h.payload;
      break;
    case 2:
    case 3: {
      const Tag tag = h.major == 2 ? Tag::Bytes : Tag::String;
      if (indefinite) {
        uint32_t q = h.payload;
        for (;; ) {
          if (q >= n) return bad(Fault::EndOfInput, q);
          if (s[q] == 0xFF) break;
          CborHead c;
          if (Fault f = cborHead(s, n, q, c); f != Fault::None) return bad(f, q);
          if (c.major != h.major || c.info == 31) return bad(Fault::Chunk, q);
          if (c.value > n - c.payload) return bad(Fault::EndOfInput, q);
          if (h.major == 3) {
            uint32_t at = badUtf8(s + c.payload, uint32_t(c.value));
            if (at != c.value) return bad(Fault::InvalidUtf8, c.payload + at);
          }
          q = c.payload + uint32_t(c.value);
        }
        row(tag, p, q);
        p = q + 1;
      } else {
        if (h.value > n - h.payload) return bad(Fault::EndOfInput, p);
        if (h.major == 3) {
          uint32_t at = badUtf8(s + h.payload, uint32_t(h.value));
          if (at != h.value) return bad(Fault::InvalidUtf8, h.payload + at);
        }
        row(tag, p, h.payload + uint32_t(h.value) - 1);
        p = h.payload + uint32_t(h.value);
      }
      break;
    }
    case 4:
    case 5: {
      const Tag tag = h.major == 4 ? Tag::Array : Tag::Object;
      uint32_t r = row(tag, p, p);
      if (indefinite) {
        open.append(join::TwInt(r, pend.size()));
        left.append(0);
        indef.append(1);
        p = h.payload;
        continue;
      }
      uint64_t items = h.major == 5 ? h.value * 2 : h.value;
      if (h.value > (n - h.payload)) return bad(Fault::EndOfInput, p); // each element takes a byte at least
      open.append(join::TwInt(r, pend.size()));
      left.append(items);
      indef.append(0);
      p = h.payload;
      if (items == 0) {
        if (Scan e = shut(p - 1)) return e;
        break;
      }
      continue;
    }
    case 7: {
      if (h.info == 24) {
        if (h.value < 32) return bad(Fault::Reserved, p);
        row(Tag::Nothing, p, h.payload - 1);
      } else if (h.info >= 25) {
        if (deterministic && cbor_detail::reducible(h)) return bad(Fault::NonShortest, p);
        row(Tag::Double, p, h.payload - 1);
      } else {
        row(h.info == 20 || h.info == 21 ? Tag::Boolean : Tag::Nothing, p, p);
      }
      p = h.payload;
      break;
    }
    default: // 6 was taken above
      return bad(Fault::Reserved, p);
    }
    if (Scan e = finish(p)) return e;
    if (open.empty()) break;
  }
  if (p != n) return bad(Fault::Trailing, p);
  return {};
}

namespace cbor_detail {

/// Put a head in its shortest form.
inline void putHead(std::string &o, uint8_t major, uint64_t v) {
  uint8_t m = uint8_t(major << 5);
  auto big = [&](uint8_t info, int bytes) {
    o.push_back(char(m | info));
    for (int i = bytes - 1; i >= 0; i--) o.push_back(char((v >> (8 * i)) & 0xFF));
  };
  if (v < 24) o.push_back(char(m | v));
  else if (v <= 0xFF) big(24, 1);
  else if (v <= 0xFFFF) big(25, 2);
  else if (v <= 0xFFFFFFFFull) big(26, 4);
  else big(27, 8);
}

/// Put a float in its shortest form: a half if one holds it, else a float, else a double.  A NaN is the half 0x7e00.
inline void putDouble(std::string &o, double d) {
  uint16_t h = 0x7e00;
  if (std::isnan(d) || halfOf(d, h)) {
    o.push_back(char(0xF9));
    o.push_back(char(h >> 8));
    o.push_back(char(h & 0xFF));
  } else if (fitsFloat(d)) {
    float f = float(d);
    uint32_t b;
    std::memcpy(&b, &f, 4);
    o.push_back(char(0xFA));
    for (int i = 3; i >= 0; i--) o.push_back(char((b >> (8 * i)) & 0xFF));
  } else {
    uint64_t b;
    std::memcpy(&b, &d, 8);
    o.push_back(char(0xFB));
    for (int i = 7; i >= 0; i--) o.push_back(char((b >> (8 * i)) & 0xFF));
  }
}

struct StrOut {
  std::string &s;
  void put(char c) { s.push_back(c); }
  void append(const char *p, uint32_t n) { s.append(p, n); }
};

} // namespace cbor_detail

/// The deterministic CBOR (RFC 8949 section 4.2.1) of the JSON document `json`, whose index is `ix`, into `out`.  Integers are major
/// types 0 and 1, any other number a float in its shortest form, an object a map with its keys in bytewise order of their encodings.  Faults:
/// InvalidUtf8 (a string with a lone surrogate, which JSON allows and CBOR does not), KeyOrder (a key twice).  The rows are taken last to
/// first, so every element is made before the container it is in, and no recursion is needed.
inline Scan encodeJson(const char *json, const Index &ix, std::string &out) {
  using namespace cbor_detail;
  std::vector<std::string> enc(ix.size());
  for (uint32_t i = ix.size(); i-- > 0;) {
    std::string &o = enc[i];
    uint32_t from = ix.open(i), to = ix.close(i);
    switch (ix.tag(i)) {
    case Tag::Nothing: o.push_back(char(0xF6)); break;
    case Tag::Boolean: o.push_back(json[from] == 't' ? char(0xF5) : char(0xF4)); break;
    case Tag::Long: {
      int64_t v = readLong(json, from, to);
      if (v >= 0) putHead(o, 0, uint64_t(v));
      else putHead(o, 1, ~uint64_t(v));
      break;
    }
    case Tag::Double: putDouble(o, std::strtod(std::string(json + from, to - from + 1).c_str(), nullptr)); break;
    case Tag::String: {
      std::string text;
      StrOut sink{text};
      decode(json, from, to, sink);
      uint32_t at = badUtf8(reinterpret_cast<const uint8_t *>(text.data()), uint32_t(text.size()));
      if (at != text.size()) return Scan{Fault::InvalidUtf8, from, 0};
      putHead(o, 3, text.size());
      o += text;
      break;
    }
    case Tag::Array: {
      auto kids = ix.kidsOf(i);
      putHead(o, 4, kids.size());
      for (uint32_t k = 0; k < kids.size(); k++) {
        o += enc[kids[k]];
        std::string().swap(enc[kids[k]]);
      }
      break;
    }
    case Tag::Object: {
      auto kids = ix.kidsOf(i);
      std::vector<std::pair<uint32_t, uint32_t>> pairs; // key row, value row
      for (uint32_t k = 0; k + 1 < kids.size(); k += 2) pairs.emplace_back(kids[k], kids[k + 1]);
      std::sort(pairs.begin(), pairs.end(), [&](auto &a, auto &b) { return enc[a.first] < enc[b.first]; });
      for (size_t k = 1; k < pairs.size(); k++)
        if (enc[pairs[k].first] == enc[pairs[k - 1].first]) return Scan{Fault::KeyOrder, ix.open(pairs[k].first), 0};
      putHead(o, 5, pairs.size());
      for (size_t k = 0; k < pairs.size(); k++) {
        o += enc[pairs[k].first];
        o += enc[pairs[k].second];
        std::string().swap(enc[pairs[k].first]);
        std::string().swap(enc[pairs[k].second]);
      }
      break;
    }
    case Tag::Bytes: break; // a JSON index has none
    }
  }
  out = std::move(enc[0]);
  return {};
}

} // namespace composite::confix

#endif
