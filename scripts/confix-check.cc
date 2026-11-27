// builtins.fromJSON's reader (lowered/nixeval/JsonRead.mlir: the confix dialect's confix.checked scan and the reification of its rows)
// against the reader it replaced, which is copied here as the oracle (lib/Eval/Formats.cpp before the port to an index, then
// include/Composite/Confix.h, now gone): the same document gives the same value, and the same fault at the same offset with the same
// words, on
//   - every string of 12 bytes up to length 6, and every sequence of up to 5 tokens (a word, a number, a string, an escape, a delimiter),
//   - every escape \uXXXX (both cases of the digits) and every low half after a high surrogate, every byte (and every two) where it can matter,
//     numbers of one to 25 digits at several offsets, the number that ends the text,
//   - random documents (nesting, whitespace, escapes, surrogate pairs, integers at every boundary of 64 bits, floats, duplicate keys) and
//     random mutations of them (a byte deleted, inserted, replaced, a cut),
//   - the .json files under the directories given on the command line.
// The library is the oracle for the numbers (strtoll, strtoull, strtod), as in numbers-check.cc; the index the scan fills is also held to
// its own laws (rows in the order they open, every row but the first inside one row after which it comes, a child inside its parent, an
// object's children in pairs whose first is a string, each row's span holding what its tag says).  The index is a lane (TrikeShed.td,
// !trikeshed.lane: a MutableSeries in LaneTrie's shape) that the entry makes and frees, so the laws are read off a second scan into a lane
// this file owns, laid out as trikeshed-lower-cursors lays one out (Index, below).  The values are made by
// the lowered entry itself (nixev_json_read) through the callbacks below, which stand in for the evaluator's arena: a Value here has the
// evaluator's layout (type u8 @0, payload @8), and EvalState::mkList is defined here under the evaluator's mangled name.  The text is read
// from a buffer whose end is the end of a page followed by an unmapped one, so that a read past its end is a fault (the lowered object is not
// instrumented by AddressSanitizer).  A document nested a million deep must not need the stack.
// Build after `ninja -C build` (which lowers JsonRead.mlir), with undefined behaviour fatal, e.g.
//   c++ -std=c++20 -O2 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined scripts/confix-check.cc build/lib/lowered/JsonRead.o -o build/confix-check
// and run it with optional counts: confix-check [random documents (200000)] [max length of a string (6)] [max tokens (5)] [dir...]
// or with --emit DIR N to write N random documents and mutations of them to DIR, for a run of two evaluators over the same texts.

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <memory>
#include <random>
#include <string>
#include <string_view>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <csignal>
#include <deque>
#include <vector>

using std::string;

static long long cases = 0, failures = 0;
static void report(const string &input, const string &want, const string &got, const char *what) {
  if (++failures > 12) return;
  string shown;
  for (unsigned char c : input.substr(0, 120)) {
    char b[8];
    if (c >= 0x20 && c < 0x7f && c != '\\') shown += char(c);
    else { std::snprintf(b, sizeof b, "\\x%02x", c); shown += b; }
  }
  std::printf("MISMATCH (%s) on [%s]\n  old: %s\n  new: %s\n", what, shown.c_str(), want.c_str(), got.c_str());
}

static string quote(const string &s) {
  string r = "\"";
  for (unsigned char c : s) {
    char b[8];
    if (c >= 0x20 && c < 0x7f && c != '\\' && c != '"') r += char(c);
    else { std::snprintf(b, sizeof b, "\\x%02x", c); r += b; }
  }
  return r + "\"";
}
static string number(double d) {
  char b[64];
  std::snprintf(b, sizeof b, "f%.17g", d);
  return b;
}
static string shownNul(const string &decoded) {
  string r;
  for (char c : decoded) { if (c == '\0') r += "\xe2\x90\x80"; else r += c; }
  return r;
}

//===----------------------------------------------------------------------===//
// The oracle: the reader that was in Formats.cpp, with a dump for the values it made
//===----------------------------------------------------------------------===//

struct Fail { string msg; };
struct Old {
  std::string_view s;
  size_t p = 0;
  [[noreturn]] void fail(const char *what) { throw Fail{"col " + std::to_string(p + 1) + ": " + what}; }
  void ws() { while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) p++; }
  static void utf8(string &out, uint32_t cp) {
    if (cp < 0x80) out += char(cp);
    else if (cp < 0x800) { out += char(0xC0 | (cp >> 6)); out += char(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += char(0xE0 | (cp >> 12)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
    else { out += char(0xF0 | (cp >> 18)); out += char(0x80 | ((cp >> 12) & 0x3F)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
  }
  uint32_t hex4() {
    if (p + 4 > s.size()) fail("invalid string: '\\u' must be followed by 4 hex digits");
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
      char c = s[p++];
      v <<= 4;
      if (c >= '0' && c <= '9') v |= c - '0';
      else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
      else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
      else fail("invalid string: '\\u' must be followed by 4 hex digits");
    }
    return v;
  }
  string stringRaw() {
    p++;
    string out;
    while (true) {
      if (p >= s.size()) fail("invalid string: missing closing quote");
      char c = s[p++];
      if (c == '"') break;
      if ((unsigned char)c < 0x20) fail("invalid string: control character must be escaped");
      if (c != '\\') { out += c; continue; }
      if (p >= s.size()) fail("invalid string");
      char e = s[p++];
      switch (e) {
      case '"': out += '"'; break;
      case '\\': out += '\\'; break;
      case '/': out += '/'; break;
      case 'b': out += '\b'; break;
      case 'f': out += '\f'; break;
      case 'n': out += '\n'; break;
      case 'r': out += '\r'; break;
      case 't': out += '\t'; break;
      case 'u': {
        uint32_t cp = hex4();
        if (cp >= 0xD800 && cp <= 0xDBFF) {
          if (p + 2 <= s.size() && s[p] == '\\' && s[p + 1] == 'u') {
            p += 2;
            uint32_t lo = hex4();
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          } else fail("invalid string: surrogate U+D800..U+DBFF must be followed by U+DC00..U+DFFF");
        }
        utf8(out, cp);
        break;
      }
      default: fail("invalid string: forbidden character after backslash");
      }
    }
    return out;
  }
  string str() {
    string r = stringRaw();
    if (r.find('\0') != string::npos) throw Fail{"nul " + shownNul(r)};
    return r;
  }
  static string object(std::vector<std::pair<string, string>> kv) {
    std::stable_sort(kv.begin(), kv.end(), [](auto &a, auto &b) { return a.first < b.first; });
    string r = "{";
    bool first = true;
    for (size_t i = 0; i < kv.size(); i++) {
      if (i + 1 < kv.size() && kv[i].first == kv[i + 1].first) continue; // of equal keys the last in the text wins
      if (!first) r += ",";
      first = false;
      r += quote(kv[i].first) + ":" + kv[i].second;
    }
    return r + "}";
  }
  string value() {
    ws();
    if (p >= s.size()) fail("unexpected end of input; expected '[', '{', or a literal");
    char c = s[p];
    if (c == '{') {
      p++;
      std::vector<std::pair<string, string>> kv;
      ws();
      if (p < s.size() && s[p] == '}') { p++; return "{}"; }
      while (true) {
        ws();
        if (p >= s.size() || s[p] != '"') fail("invalid literal; expected string literal");
        string k = str();
        ws();
        if (p >= s.size() || s[p] != ':') fail("syntax error; expected ':'");
        p++;
        string e = value();
        kv.emplace_back(k, e);
        ws();
        if (p < s.size() && s[p] == ',') { p++; continue; }
        if (p < s.size() && s[p] == '}') { p++; break; }
        fail("syntax error; expected '}'");
      }
      return object(kv);
    }
    if (c == '[') {
      p++;
      string r = "[";
      ws();
      if (p < s.size() && s[p] == ']') { p++; return "[]"; }
      bool first = true;
      while (true) {
        string e = value();
        r += (first ? "" : ",") + e;
        first = false;
        ws();
        if (p < s.size() && s[p] == ',') { p++; continue; }
        if (p < s.size() && s[p] == ']') { p++; break; }
        fail("syntax error; expected ']'");
      }
      return r + "]";
    }
    if (c == '"') return quote(str());
    if (s.substr(p, 4) == "true") { p += 4; return "true"; }
    if (s.substr(p, 5) == "false") { p += 5; return "false"; }
    if (s.substr(p, 4) == "null") { p += 4; return "null"; }
    if (c == '-' || (c >= '0' && c <= '9')) {
      size_t start = p;
      if (s[p] == '-') p++;
      bool isFloat = false;
      while (p < s.size() && s[p] >= '0' && s[p] <= '9') p++;
      if (p < s.size() && s[p] == '.') { isFloat = true; p++; while (p < s.size() && s[p] >= '0' && s[p] <= '9') p++; }
      if (p < s.size() && (s[p] == 'e' || s[p] == 'E')) {
        isFloat = true;
        p++;
        if (p < s.size() && (s[p] == '+' || s[p] == '-')) p++;
        while (p < s.size() && s[p] >= '0' && s[p] <= '9') p++;
      }
      string num(s.substr(start, p - start));
      if (!isFloat) {
        errno = 0;
        if (num[0] == '-') {
          long long v = std::strtoll(num.c_str(), nullptr, 10);
          if (errno == ERANGE) return number(std::strtod(num.c_str(), nullptr));
          return "i" + std::to_string(v);
        }
        unsigned long long v = std::strtoull(num.c_str(), nullptr, 10);
        if (errno == ERANGE) return number(std::strtod(num.c_str(), nullptr));
        if (v > (unsigned long long)INT64_MAX) throw Fail{"unsigned " + num};
        return "i" + std::to_string((long long)v);
      }
      return number(std::strtod(num.c_str(), nullptr));
    }
    fail("invalid literal");
  }
};
static string oldRead(const string &text) {
  try {
    Old o{text};
    string r = o.value();
    o.ws();
    if (o.p != text.size()) o.fail("syntax error while parsing value - unexpected trailing content; expected end of input");
    return r;
  } catch (Fail &f) { return "ERROR " + f.msg; }
}

//===----------------------------------------------------------------------===//
// The new reader: the lowered entry, its values made through these callbacks
//===----------------------------------------------------------------------===//

namespace nixev {
struct Value {
  uint8_t type = 0; // VType: Int 5, Float 6, Bool 7, Null 8, String 9, Attrs 11, List 12
  uint32_t aux = 0;
  union {
    int64_t integer;
    double fpoint;
    bool boolean;
    const char *s;
    Value **elems;
    void *attrs;
  };
  Value() : integer(0) {}
};
struct Members { std::vector<std::pair<string, Value *>> rows; };
struct EvalState {
  std::deque<Value> values;
  std::deque<string> strings;
  std::deque<std::vector<Value *>> lists;
  std::deque<Members> sets;
  void mkList(Value &v, size_t n);
};
void EvalState::mkList(Value &v, size_t n) {
  lists.emplace_back(n, nullptr);
  v.type = 12, v.aux = uint32_t(n), v.elems = lists.back().data();
}
} // namespace nixev
using nixev::EvalState;
using nixev::Value;
// A lane as trikeshed-lower-cursors lays one out: its count, and for each column a box, the one cell that holds the directory in force,
// whose slots are the pages; the count, a box, a directory and a page are each a rank-one memref, and a function is handed a memref as the
// five words of its descriptor.  All zero is an empty lane over cells this side owns: the scan opens its pages (4096 rows of one to four
// bytes) and replaces its directory, and they are freed here, the pages the count needed and a directory longer than four slots.
struct Cells { void *alloc, *data; int64_t offset, size, stride; };
#define MEMREF void *, void *, int64_t, int64_t, int64_t
#define CELLS(x) (void *)(x), (void *)(x), int64_t(0), int64_t(1), int64_t(1)
template <class T> struct Column {
  Cells dir{};
  T operator[](uint32_t i) const { return static_cast<T *>(static_cast<Cells *>(dir.data)[i >> 12].data)[i & 4095]; }
  void release(uint64_t rows) {
    for (uint64_t at = 0; at < rows; at += 4096) std::free(static_cast<Cells *>(dir.data)[at >> 12].alloc);
    if (dir.size > 4) std::free(dir.alloc);
  }
};
// confix.checked's rows (Confix.td): open, close, tag and up, the row of the container an element is in.
struct Index {
  uint64_t n = 0;
  Column<uint32_t> open, close;
  Column<uint8_t> tag;
  Column<int32_t> up;
  ~Index() { open.release(n), close.release(n), tag.release(n), up.release(n); }
};
struct Chars { uint32_t n; const char *p; }; // composite::Chars: u32 count @0, ptr @8
extern "C" {
int32_t confix_scan_checked(uint64_t *rec, MEMREF, MEMREF, MEMREF, MEMREF, MEMREF); // the record (src, n, at, end), the count, a box a column
int32_t nixev_json_read(uint64_t *rec, EvalState *st, Value *root);
uint64_t nixev_json_decode(const char *s, uint64_t from, uint64_t to, char *into, int64_t shown);
const char *nixev_json_what(int64_t fault, uint64_t *len);
Value *nixev_json_value(EvalState *st) { return &st->values.emplace_back(); }
void nixev_json_string(EvalState *st, Value *v, const char *p, uint64_t n) {
  st->strings.emplace_back(p, n);
  v->type = 9, v->aux = uint32_t(n), v->s = st->strings.back().data();
}
void nixev_json_attrs(EvalState *st, Value *v, const Chars *keys, Value **vals, uint64_t n) {
  nixev::Members &m = st->sets.emplace_back();
  for (uint64_t k = 0; k < n; k++) m.rows.emplace_back(string(keys[k].p, keys[k].n), vals[k]);
  v->type = 11, v->attrs = &m;
}
}

// A Value as the oracle writes one: an object's members in the order the entry gave them (it sorts and keeps the last of equal keys).
static string dump(const Value &v) {
  switch (v.type) {
  case 8: return "null";
  case 7: return v.boolean ? "true" : "false";
  case 5: return "i" + std::to_string((long long)v.integer);
  case 6: return number(v.fpoint);
  case 9: return quote(string(v.s, v.aux));
  case 12: {
    string out = "[";
    for (uint32_t i = 0; i < v.aux; i++) out += (i ? "," : "") + dump(*v.elems[i]);
    return out + "]";
  }
  case 11: {
    string out = "{";
    auto &rows = static_cast<nixev::Members *>(v.attrs)->rows;
    for (size_t i = 0; i < rows.size(); i++) out += (i ? "," : "") + quote(rows[i].first) + ":" + dump(*rows[i].second);
    return out + "}";
  }
  }
  return "?";
}
enum Tag : uint8_t { Nothing, Boolean, Long, Double, String, Object, Array };
// What a row's span holds, by its tag: the bytes the element is written in, read here with no help from the scan.
static bool spells(const char *s, uint32_t from, uint32_t to, const char *w) {
  uint32_t len = uint32_t(std::strlen(w));
  return to - from + 1 == len && !std::memcmp(s + from, w, len);
}
static string spanLaw(const char *s, Tag t, uint32_t from, uint32_t to) {
  switch (t) {
  case Nothing: return spells(s, from, to, "null") ? "" : "a null that is not spelled null";
  case Boolean: return spells(s, from, to, "true") || spells(s, from, to, "false") ? "" : "a boolean that is not spelled true or false";
  case String: return to > from && s[from] == '"' && s[to] == '"' ? "" : "a string not from quote to quote";
  case Object: return s[from] == '{' && s[to] == '}' ? "" : "an object not from brace to brace";
  case Array: return s[from] == '[' && s[to] == ']' ? "" : "an array not from bracket to bracket";
  case Long: // an optional minus and digits (a lone minus is a Long that reads 0, as it did)
    for (uint32_t i = from + (s[from] == '-'); i <= to; i++)
      if (s[i] < '0' || s[i] > '9') return "a long with a byte that is not a digit";
    return "";
  case Double: // the bytes a number is written in, beginning as one does
    if (s[from] != '-' && (s[from] < '0' || s[from] > '9')) return "a double that does not begin as a number";
    for (uint32_t i = from; i <= to; i++)
      if (!((s[i] >= '0' && s[i] <= '9') || s[i] == '-' || s[i] == '+' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) return "a double with a byte a number does not have";
    return "";
  }
  return "a row with no tag";
}
// The laws of the index of a text of `size` bytes that scanned.
static string laws(const char *s, uint32_t size, const Index &ix) {
  uint32_t n = uint32_t(ix.n);
  if (n == 0) return "no rows";
  if (ix.up[0] != -1) return "a first row inside another";
  std::vector<uint32_t> kids(n, 0);
  for (uint32_t i = 0; i < n; i++) {
    Tag t = Tag(ix.tag[i]);
    if (i + 1 < n && ix.open[i] >= ix.open[i + 1]) return "rows not in the order they open";
    if (ix.open[i] > ix.close[i]) return "span reversed";
    if (ix.close[i] >= size) return "a span past the end of the text";
    if (string l = spanLaw(s, t, ix.open[i], ix.close[i]); !l.empty()) return l; // a container left open has no closer at its close
    if (i == 0) continue;
    int32_t p = ix.up[i];
    if (p < 0) return "a row with no parent";
    if (uint32_t(p) >= i) return "a child not after its parent";
    Tag pt = Tag(ix.tag[p]);
    if (pt != Object && pt != Array) return "a leaf with children";
    if (!(ix.open[p] < ix.open[i] && ix.close[i] < ix.close[p])) return "a child not inside its parent";
    if (pt == Object && kids[p]++ % 2 == 0 && t != String) return "a key that is not a string";
  }
  for (uint32_t i = 0; i < n; i++)
    if (Tag(ix.tag[i]) == Object && kids[i] % 2) return "an object with an odd number of children";
  return "";
}
// The text at the end of a mapping whose next page is unmapped: a read past its end faults.
static const char *fenced(const string &text) {
  static char *base = nullptr;
  static size_t mapped = 0;
  static long page = sysconf(_SC_PAGESIZE);
  size_t need = (text.size() + page - 1) / page * page + page;
  if (need > mapped) {
    if (base) munmap(base, mapped);
    base = static_cast<char *>(mmap(nullptr, need, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0));
    mapped = need;
    mprotect(base + need - page, page, PROT_NONE);
  }
  char *at = base + (mapped - page) - text.size();
  std::memcpy(at, text.data(), text.size());
  return at;
}
static int32_t scan(const char *s, uint64_t size, Index &ix) {
  uint64_t r[4] = {uint64_t(s), size};
  return confix_scan_checked(r, CELLS(&ix.n), CELLS(&ix.open.dir), CELLS(&ix.close.dir), CELLS(&ix.tag.dir), CELLS(&ix.up.dir));
}
static string newRead(const string &text) {
  uint32_t size = uint32_t(text.size());
  const char *s = fenced(text);
  uint64_t r[4] = {uint64_t(s), size};
  EvalState st;
  Value root;
  int32_t f = nixev_json_read(r, &st, &root);
  uint32_t at = uint32_t(r[2]), end = uint32_t(r[3]);
  if (f == 14) return "ERROR unsigned " + string(s + at, end - at);
  if (f == 15) {
    string k(end - at, '\0');
    k.resize(nixev_json_decode(s, at, end - 1, k.data(), 1));
    return "ERROR nul " + k;
  }
  if (f) {
    uint64_t len;
    const char *w = nixev_json_what(f, &len);
    return "ERROR col " + std::to_string(at + 1) + ": " + string(w, len);
  }
  Index ix;
  if (scan(s, size, ix)) return "LAW a text that reads and does not scan";
  if (string l = laws(s, size, ix); !l.empty()) return "LAW " + l;
  return dump(root);
}
// A reading that does not end is a mismatch too: the old reader ends on every text, so each new reading gets 10 seconds.
static const string *reading = nullptr;
static void stuck(int) {
  report(*reading, "a reading that ends", "a reading still going after 10 s", "reader");
  std::printf("%lld cases, %lld mismatches\n", cases, failures);
  std::_Exit(1);
}
static void both(const string &text) {
  string a = oldRead(text);
  reading = &text;
  signal(SIGALRM, stuck);
  alarm(10);
  string b = newRead(text);
  alarm(0);
  cases++;
  if (a != b) report(text, a, b, "reader");
}

//===----------------------------------------------------------------------===//
// Inputs
//===----------------------------------------------------------------------===//

static void odometer(const std::vector<string> &tokens, int maxLen) {
  std::vector<int> at;
  string text;
  std::vector<size_t> pieces;
  for (int len = 0; len <= maxLen; len++) {
    at.assign(len, 0);
    while (true) {
      text.clear();
      for (int i = 0; i < len; i++) text += tokens[at[i]];
      both(text);
      int i = len - 1;
      while (i >= 0 && ++at[i] == int(tokens.size())) at[i--] = 0;
      if (i < 0) break;
    }
  }
}

static std::mt19937_64 rng(11);
static int pick(int n) { return int(rng() % n); }
static string randomString() {
  static const char *pool[] = {"a", "b", "key", " ", "\\n", "\\\"", "\\\\", "\\/", "\\u0041", "\\u00e9", "\\u20ac", "\\ud83d\\ude00", "é", "€", "\xf0\x9f\x98\x80", "\\ud800\\udc00", "\\udbff\\udfff", "\\ud800\\u0041", "\\ud83d\\u00e9", "\\udbff\\ud800", "\\ud800\\ud800", "\\udc00", "\\ud800", "\\u0000", "\\u007f", "\\u0080", "\\u07ff", "\\u0800", "\\uffff", "\\ud7ff", "\\ue000", "\\udfff", "\\uAbCd", "\xc2\x80", "\x7f", "\xff", "\\t", "\\b", "\\f", "\\r"};
  string r = "\"";
  for (int i = 0, n = pick(6); i < n; i++) r += pool[pick(int(sizeof pool / sizeof *pool))];
  return r + "\"";
}
static const char *numberPool[] = {"0", "-0", "1", "-1", "42", "007", "123456789012345678", "999999999999999999", "1000000000000000000", "9223372036854775807",
                               "9223372036854775808", "9223372036854775809", "18446744073709551615", "18446744073709551616", "-9223372036854775808",
                               "-9223372036854775809", "-18446744073709551616", "99999999999999999999999", "1.5", "-0.0", "0.1", "1e3", "1E-3", "2.5e+10", "1.", "1e",
                               "3.141592653589793", "123456789.123456789e-5", "-", "1e400", "5e-324"};
static string randomNumber() { return numberPool[pick(int(sizeof numberPool / sizeof *numberPool))]; }
static string randomDoc(int depth) {
  static const char *ws[] = {"", "", "", " ", "\n", "\t", " \r\n "};
  auto w = [&] { return string(ws[pick(7)]); };
  int k = depth > 4 ? 2 + pick(4) : pick(7);
  switch (k) {
  case 0: {
    string r = "{" + w();
    for (int i = 0, n = pick(5); i < n; i++) r += (i ? "," + w() : "") + randomString() + w() + ":" + w() + randomDoc(depth + 1) + w();
    return r + "}";
  }
  case 1: {
    string r = "[" + w();
    for (int i = 0, n = pick(5); i < n; i++) r += (i ? "," + w() : "") + randomDoc(depth + 1) + w();
    return r + "]";
  }
  case 2: return randomString();
  case 3: return randomNumber();
  case 4: return "true";
  case 5: return "false";
  default: return "null";
  }
}
static string mutate(string t) {
  static const char alphabet[] = "{}[],:\"\\ 0123456789-+.eEtrufalsn\n\x01\x80";
  for (int m = 1 + pick(3); m > 0 && !t.empty(); m--) {
    size_t at = rng() % t.size();
    switch (pick(5)) {
    case 0: t.erase(at, 1); break;
    case 1: t.insert(at, 1, alphabet[pick(sizeof alphabet - 1)]); break;
    case 2: t[at] = alphabet[pick(sizeof alphabet - 1)]; break;
    case 3: t.resize(at); break;
    default: { size_t to = at + 1 + rng() % 8; t.erase(at, to - at); }
    }
  }
  return t;
}

// Every escape: each code point four hex digits spell (the digits in both cases), and each low half after a high surrogate, over its whole
// range for the ends and the middle of the high ones, so the arithmetic of a pair is held to the old reader's at every value.
static void escapes() {
  char b[64];
  for (uint32_t cp = 0; cp <= 0xFFFF; cp++) {
    std::snprintf(b, sizeof b, "\"\\u%04x\"", cp);
    both(b);
    std::snprintf(b, sizeof b, "\"a\\u%04X\"", cp);
    both(b);
  }
  static const uint32_t highs[] = {0xD800, 0xD801, 0xD83D, 0xDBFE, 0xDBFF};
  for (uint32_t hi : highs)
    for (uint32_t lo = 0; lo <= 0xFFFF; lo++) {
      std::snprintf(b, sizeof b, "\"\\u%04x\\u%04x\"", hi, lo);
      both(b);
    }
  for (uint32_t hi = 0xD800; hi <= 0xDBFF; hi++)
    for (uint32_t lo : {0xDC00u, 0xDFFFu, 0x0041u, 0xD800u, 0xE000u}) {
      std::snprintf(b, sizeof b, "\"\\u%04x\\u%04X\"", hi, lo);
      both(b);
    }
}

// Every byte where a byte can matter (in a string, after a backslash, at each of the four digits of an escape and of the second escape of a
// pair, where a value, a key, a colon or a comma may begin, after a number, in a literal), and every two bytes in the places that read two.
static void everyByte() {
  static const char *around[][2] = {
      {"\"", "\""}, {"[\"", "\"]"}, {"{\"", "\":0}"}, {"\"\\", "\""}, {"\"a\\", "b\""},
      {"\"\\u", "000\""}, {"\"\\u0", "00\""}, {"\"\\u00", "0\""}, {"\"\\u000", "\""},
      {"\"\\ud800\\u", "000\""}, {"\"\\ud800\\u0", "00\""}, {"\"\\ud800\\u00", "0\""}, {"\"\\ud800\\u000", "\""}, {"\"\\ud800", "\""}, {"\"\\ud800\\", "\""},
      {"", ""}, {"[", "]"}, {"[1,", "]"}, {"[1", "]"}, {"{", "}"}, {"{\"a\"", "0}"}, {"{\"a\":", "}"}, {"{\"a\":0", "}"}, {"{\"a\":0,", "}"},
      {"1", ""}, {"-", ""}, {"0.", ""}, {"1e", ""}, {"1e+", ""}, {"1.5", ""}, {"tru", ""}, {"nul", ""}, {"fals", ""}, {"t", "rue"}, {"[1]", ""}, {"[]", ""}, {"{}", ""}, {"\"\"", ""},
  };
  for (auto &a : around)
    for (int x = 0; x < 256; x++) both(string(a[0]) + char(x) + a[1]);
  static const char *pairs[][2] = {{"\"", "\""}, {"\"\\", "\""}, {"", ""}, {"[", "]"}, {"1", ""}};
  for (auto &a : pairs)
    for (int x = 0; x < 256; x++)
      for (int y = 0; y < 256; y++) both(string(a[0]) + char(x) + char(y) + a[1]);
}

// Each number of the pool, and numbers of every length from one digit to 25, after each of several beginnings and before each of several
// endings, among them none: the number at the offset it is read from and the number that ends the text.
static void numbersAround() {
  std::vector<string> nums(std::begin(numberPool), std::end(numberPool));
  for (int len = 1; len <= 25; len++) {
    nums.push_back("1" + string(len - 1, '0'));
    nums.push_back(string(len, '9'));
    nums.push_back("-1" + string(len - 1, '0'));
    nums.push_back("-" + string(len, '9'));
  }
  static const char *before[] = {"", " ", "[", "[1,", "{\"a\":", " \n\t ", "[[[[[[[[[["};
  static const char *after[] = {"", " ", "]", ",1]", "}", "e", "."};
  for (const string &n : nums)
    for (const char *b : before)
      for (const char *a : after) both(string(b) + n + a);
}

static void files(const string &dir, int &count) {
  DIR *d = opendir(dir.c_str());
  if (!d) return;
  while (dirent *e = readdir(d)) {
    string name = e->d_name;
    if (name == "." || name == "..") continue;
    string path = dir + "/" + name;
    struct stat st;
    if (lstat(path.c_str(), &st) != 0) continue;
    if (S_ISDIR(st.st_mode)) files(path, count);
    else if (S_ISREG(st.st_mode) && name.size() > 5 && name.substr(name.size() - 5) == ".json" && st.st_size < (8 << 20)) {
      FILE *f = std::fopen(path.c_str(), "rb");
      if (!f) continue;
      string t;
      char buf[65536];
      size_t k;
      while ((k = std::fread(buf, 1, sizeof buf, f)) > 0) t.append(buf, k);
      std::fclose(f);
      both(t);
      count++;
    }
  }
  closedir(d);
}

// confix-check --emit DIR N: write N random documents and mutations of them to DIR/000000.json ..., for a run of two evaluators over the same texts.
static int emit(const char *dir, int count) {
  for (int i = 0; i < count; i++) {
    string d = randomDoc(0);
    string t = i % 3 == 0 ? d : i % 3 == 1 ? mutate(d) : mutate(mutate(d));
    char path[512];
    std::snprintf(path, sizeof path, "%s/%06d.json", dir, i);
    FILE *f = std::fopen(path, "wb");
    if (!f) { std::printf("cannot write %s\n", path); return 1; }
    std::fwrite(t.data(), 1, t.size(), f);
    std::fclose(f);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 4 && !std::strcmp(argv[1], "--emit")) return emit(argv[2], std::atoi(argv[3]));
  int randoms = argc > 1 ? std::atoi(argv[1]) : 200000, maxChars = argc > 2 ? std::atoi(argv[2]) : 6, maxTokens = argc > 3 ? std::atoi(argv[3]) : 5;
  std::vector<string> chars = {"{", "}", "[", "]", ",", ":", "\"", "\\", " ", "0", "-", "u"};
  odometer(chars, maxChars);
  std::printf("%lld cases over 12 bytes up to length %d\n", cases, maxChars);
  long long before = cases;
  std::vector<string> tokens = {"{", "}", "[", "]", ",", ":", " ", "true", "false", "null", "tru", "12", "-", "1.5e3", "9223372036854775808", "\"a\"", "\"\\u0041\"",
                                "\"\\ud83d\\ude00\"", "\"\\ud83d\"", "\"\\ud83d\\u0041\"", "\"\\udc00\"", "\"\\ud83d\\ud83d\"", "\"\\u00\"", "\"\\x\"", "\"\\u0000\"", "\"a"};
  odometer(tokens, maxTokens);
  std::printf("%lld cases over %zu tokens up to %d\n", cases - before, tokens.size(), maxTokens);
  before = cases;
  escapes();
  std::printf("%lld cases over every escape, and every pair of them with a high surrogate first\n", cases - before);
  before = cases;
  everyByte();
  std::printf("%lld cases over every byte, and every two, where they can matter\n", cases - before);
  before = cases;
  numbersAround();
  std::printf("%lld cases over numbers at every offset, at the end of the text and not\n", cases - before);
  before = cases;
  for (int i = 0; i < randoms; i++) {
    string d = randomDoc(0);
    both(d);
    both(mutate(d));
    both(mutate(mutate(d)));
  }
  std::printf("%lld cases over %d random documents and two mutations of each\n", cases - before, randoms);
  int nfiles = 0;
  for (int i = 4; i < argc; i++) files(argv[i], nfiles);
  if (nfiles) std::printf("%d files\n", nfiles);
  // A document nested a million deep: the open containers are rows of the index, and the values are made in one walk, not on the machine's stack.
  {
    string deep = string(1000000, '[') + "1" + string(1000000, ']');
    uint64_t r[4] = {uint64_t(deep.data()), deep.size()};
    EvalState st;
    Value root;
    int32_t f = nixev_json_read(r, &st, &root);
    const Value *v = &root;
    uint32_t depth = 0;
    while (v->type == 12 && v->aux == 1) v = v->elems[0], depth++;
    Index ix;
    if (f || scan(deep.data(), deep.size(), ix) || ix.n != 1000001 || depth != 1000000 || v->type != 5 || v->integer != 1) {
      std::printf("MISMATCH: a million deep did not read (%d)\n", f);
      failures++;
    }
    cases++;
    string unclosed(1000000, '[');
    uint64_t u[4] = {uint64_t(unclosed.data()), unclosed.size()};
    if (nixev_json_read(u, &st, &root) != 1 || u[2] != 1000000) { std::printf("MISMATCH: a million brackets, never closed\n"); failures++; }
    cases++;
  }
  std::printf("%lld cases, %lld mismatches\n", cases, failures);
  return failures ? 1 : 0;
}
