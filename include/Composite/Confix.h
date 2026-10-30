//===- Confix.h - a JSON text indexed, then reified: TrikeShed's Confix, Syntax.JSON ---------------------------------===//
//
// TrikeShed's parse/confix (CCEKCMMKPlatform src/commonMain/kotlin/borg/trikeshed/parse/confix: Confix.kt, ConfixKit.kt) reads a text once
// into an index and makes the values when something asks: index first, reify later (PRELOAD.md, JSON scan / path algebra).  The index is a
// Cursor, a row for each element, its columns the ones of a RowVec:
//
//   Span   open j close: the offsets of the first and the last byte of the element (a string's quotes included)
//   Tag    what the element is (IOMemento's cases a JSON text has)
//   Kids   first j count into `kids`: the rows of its direct children, in order.  An object's are its keys and its values alternating,
//          as RowVec.kids has them.
//
// The rows are in the order the elements open, so a row's children are after it.  Nothing in the index holds text: the source is read where it
// lies, and a string is decoded, a number read, only when a caller asks (decode, readLong).
//
// ConfixKit.kt scans without checking: a stray `]` pops nothing, `-+-` is a number.  This scan checks as the reader of builtins.fromJSON
// does, with its faults at its offsets (the offset is where the reading had got to, so the column of the old message is `at + 1`), because
// an index is only worth having of a text that is one.  No recursion: the open containers are a stack of rows, so a document as deep as it
// is long is scanned in the space it takes to hold its index.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_CONFIX_H
#define COMPOSITE_CONFIX_H

#include "Composite/CharSeries.h"
#include "Composite/Pool.h"

namespace composite::confix {

/// What an element is: IOMemento's IoNothing, IoBoolean, IoLong, IoDouble, IoString, IoObject and IoArray.  A number written without a
/// fraction or an exponent that fits 64 bits is a Long; any other number is a Double (one past 64 bits too).
enum class Tag : uint8_t { Nothing, Boolean, Long, Double, String, Object, Array };

/// The columns of an Index.
enum class Col : uint8_t { Span, Tag, Kids };

/// Why a scan stopped.  The first twelve are faults of the syntax and are said by `what`; Unsigned and Nul are a number and a string the
/// text spells and a Nix value cannot be.
enum class Fault : uint8_t {
  None,
  EndOfInput,    // a value was expected and the text ended
  InvalidLiteral, // a value was expected and this is not the start of one
  ExpectedKey,   // a key was expected after `{` or `,`
  ExpectedColon,
  ExpectedBrace, // `,` or `}` was expected after a member
  ExpectedBracket, // `,` or `]` was expected after an element
  Trailing,      // the document ended and the text did not
  MissingQuote,
  ControlChar,   // a byte under 0x20 in a string
  InvalidString, // a backslash at the very end of the text
  Hex4,          // `\u` without four hex digits
  Surrogate,     // a high surrogate not followed by `\u`
  Backslash,     // a backslash before a character that is not an escape
  Unsigned,      // an integer from 2^63 to 2^64 - 1: JSON has it, an int64 does not
  Nul,           // a string with a `\u0000`: a text with a NUL in it
};

/// The words of a fault of the syntax, those of the reader that scanned before this one; null for the others.
constexpr const char *what(Fault f) {
  switch (f) {
  case Fault::EndOfInput: return "unexpected end of input; expected '[', '{', or a literal";
  case Fault::InvalidLiteral: return "invalid literal";
  case Fault::ExpectedKey: return "invalid literal; expected string literal";
  case Fault::ExpectedColon: return "syntax error; expected ':'";
  case Fault::ExpectedBrace: return "syntax error; expected '}'";
  case Fault::ExpectedBracket: return "syntax error; expected ']'";
  case Fault::Trailing: return "syntax error while parsing value - unexpected trailing content; expected end of input";
  case Fault::MissingQuote: return "invalid string: missing closing quote";
  case Fault::ControlChar: return "invalid string: control character must be escaped";
  case Fault::InvalidString: return "invalid string";
  case Fault::Hex4: return "invalid string: '\\u' must be followed by 4 hex digits";
  case Fault::Surrogate: return "invalid string: surrogate U+D800..U+DBFF must be followed by U+DC00..U+DFFF";
  case Fault::Backslash: return "invalid string: forbidden character after backslash";
  default: return nullptr;
  }
}

/// The index of one text: a row for each element, and the children of each row together.
struct Index {
  Cursor<join::TwInt, Tag, join::TwInt> rows{Arr<const char *, 3>{{"span", "tag", "kids"}}};
  MutableSeries<uint32_t> kids;

  uint32_t size() const { return rows.size(); }
  void clear() {
    rows.clear();
    kids.clear();
  }
  join::TwInt span(uint32_t i) const { return rows.col<Col::Span>()[i]; }
  uint32_t open(uint32_t i) const { return span(i).first(); }
  uint32_t close(uint32_t i) const { return span(i).second(); }
  Tag tag(uint32_t i) const { return rows.col<Col::Tag>()[i]; }
  /// The rows of the direct children of row i, in order: a view of `kids`.
  auto kidsOf(uint32_t i) const {
    join::TwInt k = rows.col<Col::Kids>()[i];
    return series(kids.data() + k.first(), k.second());
  }
};

/// How a scan ended: no fault, or which and where.  `at` is the offset the reading had reached; for Unsigned and Nul it is the offset where
/// the number or the string opens, and `end` is one past it.
struct Scan {
  Fault fault = Fault::None;
  uint32_t at = 0, end = 0;
  constexpr explicit operator bool() const { return fault != Fault::None; }
};

constexpr bool isHexDigit(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
constexpr uint32_t hexValue(char c) { return c <= '9' ? uint32_t(c - '0') : c >= 'a' ? uint32_t(c - 'a' + 10) : uint32_t(c - 'A' + 10); }

/// Scan a JSON text into `ix` (cleared first and its storage kept).  The scan is one pass and a stack: a row is made as its element opens,
/// its end and its children are set as it closes.
inline Scan scan(Chars src, Index &ix) {
  ix.clear();
  const char *s = src.data();
  const uint32_t n = src.size();
  uint32_t p = 0;
  MutableSeries<join::TwInt> open; // the containers still open: their row j where their children start in `pend`
  MutableSeries<uint32_t> pend;    // the rows finished inside them, each container's after its start
  auto ws = [&] {
    while (p < n && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) p++;
  };
  auto bad = [&](Fault f, uint32_t at) { return Scan{f, at, 0}; };
  // A row, and its place among the children of the container it is in.
  auto row = [&](Tag t, uint32_t from, uint32_t to) {
    uint32_t r = ix.rows.append(join::TwInt(from, to), t, join::TwInt(0, 0));
    if (open.size()) pend.append(r);
    return r;
  };
  // The container on top ends at offset `at`: its end, and its children, which leave `pend` for `kids`.
  auto shut = [&](uint32_t at) {
    join::TwInt top = open.back();
    open.pop();
    uint32_t r = top.first(), from = top.second(), count = pend.size() - from, first = ix.kids.size();
    for (uint32_t i = 0; i < count; i++) ix.kids.append(pend[from + i]);
    pend.resize(from);
    ix.rows.col<Col::Span>()[r] = join::TwInt(ix.rows.col<Col::Span>()[r].first(), at);
    ix.rows.col<Col::Kids>()[r] = join::TwInt(first, count);
  };
  auto word = [&](const char *w, uint32_t len) {
    if (n - p < len) return false;
    for (uint32_t i = 0; i < len; i++)
      if (s[p + i] != w[i]) return false;
    return true;
  };
  // Four hex digits at p; on a fault p has moved past the digits it read, as the reader that took the text before did.
  auto hex4 = [&](uint32_t &v) {
    if (p + 4 > n) return Fault::Hex4;
    v = 0;
    for (int i = 0; i < 4; i++) {
      char c = s[p++];
      if (!isHexDigit(c)) return Fault::Hex4;
      v = (v << 4) | hexValue(c);
    }
    return Fault::None;
  };
  // A string from the quote at p, as a row.
  auto string = [&]() -> Scan {
    uint32_t from = p++;
    bool nul = false;
    for (;;) {
      while (p < n && s[p] != '"' && s[p] != '\\' && uint8_t(s[p]) >= 0x20) p++; // the run of plain bytes
      if (p >= n) return bad(Fault::MissingQuote, p);
      char c = s[p++];
      if (c == '"') break;
      if (uint8_t(c) < 0x20) return bad(Fault::ControlChar, p);
      if (p >= n) return bad(Fault::InvalidString, p);
      switch (s[p++]) {
      case '"': case '\\': case '/': case 'b': case 'f': case 'n': case 'r': case 't': break;
      case 'u': {
        uint32_t cp;
        if (Fault f = hex4(cp); f != Fault::None) return bad(f, p);
        if (cp >= 0xD800 && cp <= 0xDBFF) { // a high surrogate takes the escape after it, whatever that is
          if (p + 2 <= n && s[p] == '\\' && s[p + 1] == 'u') {
            p += 2;
            uint32_t lo;
            if (Fault f = hex4(lo); f != Fault::None) return bad(f, p);
          } else {
            return bad(Fault::Surrogate, p);
          }
        }
        if (cp == 0) nul = true; // the only way a decoded string holds a NUL: a raw one is a control character, a pair is over 0xFFFF
        break;
      }
      default: return bad(Fault::Backslash, p);
      }
    }
    if (nul) return Scan{Fault::Nul, from, p};
    row(Tag::String, from, p - 1);
    return {};
  };

  enum class At : uint8_t { Value, Key, After };
  At at = At::Value;
  for (;;) {
    if (at == At::Value) {
      ws();
      if (p >= n) return bad(Fault::EndOfInput, p);
      char c = s[p];
      if (c == '{' || c == '[') {
        uint32_t r = row(c == '{' ? Tag::Object : Tag::Array, p, p);
        open.append(join::TwInt(r, pend.size()));
        p++;
        ws();
        if (p < n && s[p] == (c == '{' ? '}' : ']')) {
          shut(p++);
          at = At::After;
        } else {
          at = c == '{' ? At::Key : At::Value;
        }
      } else if (c == '"') {
        if (Scan e = string()) return e;
        at = At::After;
      } else if (word("true", 4)) {
        row(Tag::Boolean, p, p + 3);
        p += 4;
        at = At::After;
      } else if (word("false", 5)) {
        row(Tag::Boolean, p, p + 4);
        p += 5;
        at = At::After;
      } else if (word("null", 4)) {
        row(Tag::Nothing, p, p + 3);
        p += 4;
        at = At::After;
      } else if (c == '-' || isAsciiDigit(c)) {
        uint32_t from = p;
        bool fractional = false;
        if (s[p] == '-') p++;
        uint32_t digits = p;
        while (p < n && isAsciiDigit(s[p])) p++;
        digits = p - digits;
        if (p < n && s[p] == '.') {
          fractional = true;
          p++;
          while (p < n && isAsciiDigit(s[p])) p++;
        }
        if (p < n && (s[p] == 'e' || s[p] == 'E')) {
          fractional = true;
          p++;
          if (p < n && (s[p] == '+' || s[p] == '-')) p++;
          while (p < n && isAsciiDigit(s[p])) p++;
        }
        Tag t = Tag::Double;
        if (!fractional) {
          t = Tag::Long; // up to 18 digits cannot overflow; longer ones are read by the facets, as strtoll and strtoull read them
          if (digits > 18) {
            CharSeries all(s + from, p - from);
            if (s[from] == '-') {
              if (facet<text::Integer<10, true>>(all).overflow) t = Tag::Double;
            } else {
              text::Reading r = facet<text::Integer<10, false>>(all);
              if (r.overflow) t = Tag::Double;
              else if (r.value > uint64_t(0x7FFFFFFFFFFFFFFFull)) return Scan{Fault::Unsigned, from, p};
            }
          }
        }
        row(t, from, p - 1);
        at = At::After;
      } else {
        return bad(Fault::InvalidLiteral, p);
      }
    } else if (at == At::Key) {
      ws();
      if (p >= n || s[p] != '"') return bad(Fault::ExpectedKey, p);
      if (Scan e = string()) return e;
      ws();
      if (p >= n || s[p] != ':') return bad(Fault::ExpectedColon, p);
      p++;
      at = At::Value;
    } else {
      if (open.empty()) break;
      ws();
      bool object = ix.tag(open.back().first()) == Tag::Object;
      if (p < n && s[p] == ',') {
        p++;
        at = object ? At::Key : At::Value;
      } else if (p < n && s[p] == (object ? '}' : ']')) {
        shut(p++);
      } else {
        return bad(object ? Fault::ExpectedBrace : Fault::ExpectedBracket, p);
      }
    }
  }
  ws();
  if (p != n) return bad(Fault::Trailing, p);
  return {};
}

/// The bytes of cp as UTF-8, `put` into out: a lone surrogate gets its three bytes, as it did in the reader before this one.
template <class Out> void utf8(Out &out, uint32_t cp) {
  if (cp < 0x80) {
    out.put(char(cp));
  } else if (cp < 0x800) {
    out.put(char(0xC0 | (cp >> 6)));
    out.put(char(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    out.put(char(0xE0 | (cp >> 12)));
    out.put(char(0x80 | ((cp >> 6) & 0x3F)));
    out.put(char(0x80 | (cp & 0x3F)));
  } else {
    out.put(char(0xF0 | (cp >> 18)));
    out.put(char(0x80 | ((cp >> 12) & 0x3F)));
    out.put(char(0x80 | ((cp >> 6) & 0x3F)));
    out.put(char(0x80 | (cp & 0x3F)));
  }
}

/// The text of the String row from..to (its quotes), the escapes decoded, `put` into out.  For a span `scan` accepted.
template <class Out> void decode(const char *s, uint32_t from, uint32_t to, Out &out) {
  auto hex4 = [&](uint32_t at) {
    uint32_t v = 0;
    for (uint32_t i = 0; i < 4; i++) v = (v << 4) | hexValue(s[at + i]);
    return v;
  };
  for (uint32_t p = from + 1; p < to;) {
    char c = s[p++];
    if (c != '\\') {
      out.put(c);
      continue;
    }
    switch (char e = s[p++]) {
    case 'b': out.put('\b'); break;
    case 'f': out.put('\f'); break;
    case 'n': out.put('\n'); break;
    case 'r': out.put('\r'); break;
    case 't': out.put('\t'); break;
    case 'u': {
      uint32_t cp = hex4(p);
      p += 4;
      if (cp >= 0xD800 && cp <= 0xDBFF) {
        uint32_t lo = hex4(p + 2);
        p += 6;
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
      }
      utf8(out, cp);
      break;
    }
    default: out.put(e); break; // `"`, `\` and `/`
    }
  }
}

/// The value of a Long row from..to (inclusive): the digits summed when they cannot overflow, else read by the facets of CharSeries as
/// strtoll and strtoull read them.  A `-` with no digit is 0, as the reader before this one made it.
inline int64_t readLong(const char *s, uint32_t from, uint32_t to) {
  bool negative = s[from] == '-';
  uint32_t first = from + (negative ? 1 : 0);
  if (to + 1 - first <= 18) {
    int64_t v = 0;
    for (uint32_t i = first; i <= to; i++) v = v * 10 + (s[i] - '0');
    return negative ? -v : v;
  }
  CharSeries all(s + from, to + 1 - from);
  return negative ? int64_t(facet<text::Integer<10, true>>(all).value) : int64_t(facet<text::Integer<10, false>>(all).value);
}

} // namespace composite::confix

#endif
