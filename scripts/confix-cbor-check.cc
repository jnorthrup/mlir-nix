// Composite/ConfixCbor.h: the scan of a CBOR item, the deterministic reading of it, and the deterministic encoding of a JSON index.
//
// What holds it:
//   - RFC 8949 appendix A: the encodings the RFC lists, each with the value it gives (written here from the RFC, not from this scan),
//     and the indefinite-length ones, which the Kotlin scan does not read right (see ConfixCbor.h);
//   - the faults, each on a text that has only that one;
//   - section 4.2.1: texts that are deterministic and texts that are not, one rule at a time, and the key order of the RFC's own example;
//   - the encoder: JSON texts with the bytes they must give, the same document with its members in any order giving the same bytes, and
//     random documents: encode, then scan deterministically (it must pass), then read back and compare with the JSON index;
//   - the index's laws on random byte strings and on mutations of the vectors (rows in the order they open, a child after its parent and inside
//     it, a map's children in pairs, the rows' spans holding what their tags say), with no read past the text: the text is scanned from a buffer of
//     exactly its size, so a read past the end is a fault under AddressSanitizer.
//   - the same texts as the Kotlin scan (TrikeShed Syntax.CBOR), compiled to a program by Kotlin/Native, reads them: `--rows` prints the
//     rows of a hex text one per line, as scripts/confix-cbor-rows.kt prints them.
// Build with undefined behaviour fatal:
//   c++ -std=c++20 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -I include scripts/confix-cbor-check.cc -o build/confix-cbor-check
// Run: confix-cbor-check [random cases (100000)]    or    confix-cbor-check --rows HEX...
#include "Composite/ConfixCbor.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <random>
#include <string>
#include <vector>

using std::string;
namespace cf = composite::confix;

static long long cases = 0, failures = 0;
static void fail(const string &what, const string &input, const string &want, const string &got) {
  if (++failures > 20) return;
  std::printf("FAIL %s on [%s]\n  want: %s\n  got:  %s\n", what.c_str(), input.c_str(), want.c_str(), got.c_str());
}

static string fromHex(const string &h) {
  string r;
  for (size_t i = 0; i + 1 < h.size(); i += 2) r.push_back(char(std::stoi(h.substr(i, 2), nullptr, 16)));
  return r;
}
static string toHex(const string &b) {
  string r;
  char t[4];
  for (unsigned char c : b) { std::snprintf(t, sizeof t, "%02x", c); r += t; }
  return r;
}

// A text in a buffer of exactly its size.
struct Exact {
  std::unique_ptr<char[]> buf;
  uint32_t n;
  explicit Exact(const string &s) : buf(new char[s.size() ? s.size() : 1]), n(uint32_t(s.size())) { std::memcpy(buf.get(), s.data(), s.size()); }
  composite::Chars chars() const { return composite::series(static_cast<const char *>(buf.get()), n); }
};

static string number(double d) {
  if (d != d) return "fnan";
  if (d == HUGE_VAL) return "finf";
  if (d == -HUGE_VAL) return "f-inf";
  if (d == 0) return std::signbit(d) ? "f-0" : "f0";
  char b[64];
  for (int p = 1; p <= 17; p++) {
    std::snprintf(b, sizeof b, "%.*g", p, d);
    if (std::strtod(b, nullptr) == d) break;
  }
  return string("f") + b;
}
static string quoted(const string &s) {
  string r = "\"";
  for (unsigned char c : s) {
    char t[8];
    if (c >= 0x20 && c < 0x7f && c != '"' && c != '\\') r += char(c);
    else if (c == '"' || c == '\\') { r += '\\'; r += char(c); }
    else { std::snprintf(t, sizeof t, "\\x%02x", c); r += t; }
  }
  return r + "\"";
}

// The notation of a row of a CBOR index.  Maps are written with their entries in the order they come, or sorted by the written key.
static string showCbor(const cf::Index &ix, const uint8_t *s, uint32_t i, bool sorted) {
  using cf::Tag;
  switch (ix.tag(i)) {
  case Tag::Nothing: return "null";
  case Tag::Boolean: return s[ix.open(i)] == 0xF5 ? "true" : "false";
  case Tag::Long: return std::to_string(cf::cborLong(s, ix.open(i)));
  case Tag::Double: return number(cf::cborDouble(s, ix.open(i)));
  case Tag::String:
  case Tag::Bytes: {
    string t;
    struct Out { string &s; void put(char c) { s.push_back(c); } void append(const char *p, uint32_t n) { s.append(p, n); } } o{t};
    cf::cborString(s, ix.open(i), o);
    return ix.tag(i) == Tag::String ? quoted(t) : "h'" + toHex(t) + "'";
  }
  case Tag::Array: {
    string r = "[";
    auto k = ix.kidsOf(i);
    for (uint32_t j = 0; j < k.size(); j++) r += (j ? "," : "") + showCbor(ix, s, k[j], sorted);
    return r + "]";
  }
  case Tag::Object: {
    std::vector<string> e;
    auto k = ix.kidsOf(i);
    for (uint32_t j = 0; j + 1 < k.size(); j += 2) e.push_back(showCbor(ix, s, k[j], sorted) + ":" + showCbor(ix, s, k[j + 1], sorted));
    if (sorted) std::sort(e.begin(), e.end());
    string r = "{";
    for (size_t j = 0; j < e.size(); j++) r += (j ? "," : "") + e[j];
    return r + "}";
  }
  }
  return "?";
}
// The same notation of a row of a JSON index.
static string showJson(const cf::Index &ix, const char *s, uint32_t i) {
  using cf::Tag;
  switch (ix.tag(i)) {
  case Tag::Nothing: return "null";
  case Tag::Boolean: return s[ix.open(i)] == 't' ? "true" : "false";
  case Tag::Long: return std::to_string(cf::readLong(s, ix.open(i), ix.close(i)));
  case Tag::Double: return number(std::strtod(string(s + ix.open(i), ix.close(i) - ix.open(i) + 1).c_str(), nullptr));
  case Tag::String: {
    string t;
    struct Out { string &s; void put(char c) { s.push_back(c); } void append(const char *p, uint32_t n) { s.append(p, n); } } o{t};
    cf::decode(s, ix.open(i), ix.close(i), o);
    return quoted(t);
  }
  case Tag::Array: {
    string r = "[";
    auto k = ix.kidsOf(i);
    for (uint32_t j = 0; j < k.size(); j++) r += (j ? "," : "") + showJson(ix, s, k[j]);
    return r + "]";
  }
  case Tag::Object: {
    std::vector<string> e;
    auto k = ix.kidsOf(i);
    for (uint32_t j = 0; j + 1 < k.size(); j += 2) e.push_back(showJson(ix, s, k[j]) + ":" + showJson(ix, s, k[j + 1]));
    std::sort(e.begin(), e.end());
    string r = "{";
    for (size_t j = 0; j < e.size(); j++) r += (j ? "," : "") + e[j];
    return r + "}";
  }
  case Tag::Bytes: return "?";
  }
  return "?";
}

static const char *faultName(cf::Fault f) {
  switch (f) {
  case cf::Fault::None: return "None";
  case cf::Fault::EndOfInput: return "EndOfInput";
  case cf::Fault::Trailing: return "Trailing";
  case cf::Fault::Unsigned: return "Unsigned";
  case cf::Fault::Reserved: return "Reserved";
  case cf::Fault::Break: return "Break";
  case cf::Fault::InvalidUtf8: return "InvalidUtf8";
  case cf::Fault::Chunk: return "Chunk";
  case cf::Fault::NonShortest: return "NonShortest";
  case cf::Fault::Indefinite: return "Indefinite";
  case cf::Fault::KeyOrder: return "KeyOrder";
  default: return "other";
  }
}

// The laws of an index of bytes (or of JSON text: the same laws).
static bool laws(const cf::Index &ix, uint32_t n, string &why) {
  uint32_t rows = ix.size();
  if (rows == 0) { why = "no rows"; return false; }
  std::vector<int> parent(rows, -1);
  for (uint32_t i = 0; i < rows; i++) {
    if (ix.open(i) > ix.close(i) || ix.close(i) >= n) { why = "span of row " + std::to_string(i) + " outside the text"; return false; }
    auto k = ix.kidsOf(i);
    bool container = ix.tag(i) == cf::Tag::Array || ix.tag(i) == cf::Tag::Object;
    if (!container && k.size()) { why = "a scalar with kids"; return false; }
    if (ix.tag(i) == cf::Tag::Object && (k.size() & 1)) { why = "an object with an odd count of kids"; return false; }
    uint32_t prevEnd = 0;
    for (uint32_t j = 0; j < k.size(); j++) {
      uint32_t c = k[j];
      if (c <= i || c >= rows) { why = "a child not after its parent"; return false; }
      if (parent[c] != -1) { why = "a row the child of two"; return false; }
      parent[c] = int(i);
      if (ix.open(c) < ix.open(i) || ix.close(c) > ix.close(i)) { why = "a child outside its parent"; return false; }
      if (j && ix.open(c) <= prevEnd) { why = "children out of order or overlapping"; return false; }
      prevEnd = ix.close(c);
    }
    if (i && ix.open(i) < ix.open(i - 1)) { why = "rows not in the order they open"; return false; }
  }
  for (uint32_t i = 1; i < rows; i++)
    if (parent[i] == -1) { why = "a row that is nobody's child"; return false; }
  return true;
}

struct Vec { const char *hex, *want; };
// RFC 8949 appendix A: the encoding and the value.  Notation: integers as they are, floats after an `f`, strings quoted, byte strings h'..',
// arrays [..], maps {..:..}.  Tags make no row, so a tagged item is written as the item.
static const Vec rfc[] = {
    {"00", "0"}, {"01", "1"}, {"0a", "10"}, {"17", "23"}, {"1818", "24"}, {"1819", "25"}, {"1864", "100"}, {"1903e8", "1000"},
    {"1a000f4240", "1000000"}, {"1b000000e8d4a51000", "1000000000000"}, {"1b7fffffffffffffff", "9223372036854775807"},
    {"c249010000000000000000", "h'010000000000000000'"}, {"c349010000000000000000", "h'010000000000000000'"},
    {"20", "-1"}, {"29", "-10"}, {"3863", "-100"}, {"3903e7", "-1000"}, {"3b7fffffffffffffff", "-9223372036854775808"},
    {"f90000", "f0"}, {"f98000", "f-0"}, {"f93c00", "f1"}, {"fb3ff199999999999a", "f1.1"}, {"f93e00", "f1.5"}, {"f97bff", "f65504"},
    {"fa47c35000", "f1e+05"}, {"fa7f7fffff", "f3.4028234663852886e+38"}, {"fb7e37e43c8800759c", "f1e+300"},
    {"f90001", "f5.9604644775390625e-08"}, {"f90400", "f6.103515625e-05"}, {"f9c400", "f-4"}, {"fbc010666666666666", "f-4.1"},
    {"f97c00", "finf"}, {"f97e00", "fnan"}, {"f9fc00", "f-inf"}, {"fa7f800000", "finf"}, {"fa7fc00000", "fnan"}, {"faff800000", "f-inf"},
    {"fb7ff0000000000000", "finf"}, {"fb7ff8000000000000", "fnan"}, {"fbfff0000000000000", "f-inf"},
    {"f4", "false"}, {"f5", "true"}, {"f6", "null"}, {"f7", "null"}, {"f0", "null"}, {"f8ff", "null"},
    {"c074323031332d30332d32315432303a30343a30305a", "\"2013-03-21T20:04:00Z\""}, {"c11a514b67b0", "1363896240"},
    {"c1fb41d452d9ec200000", "f1363896240.5"}, {"d74401020304", "h'01020304'"}, {"d818456449455446", "h'6449455446'"},
    {"d82076687474703a2f2f7777772e6578616d706c652e636f6d", "\"http://www.example.com\""},
    {"40", "h''"}, {"4401020304", "h'01020304'"}, {"60", "\"\""}, {"6161", "\"a\""}, {"6449455446", "\"IETF\""}, {"62225c", "\"\\\"\\\\\""},
    {"62c3bc", "\"\\xc3\\xbc\""}, {"63e6b0b4", "\"\\xe6\\xb0\\xb4\""}, {"64f0908591", "\"\\xf0\\x90\\x85\\x91\""},
    {"80", "[]"}, {"83010203", "[1,2,3]"}, {"8301820203820405", "[1,[2,3],[4,5]]"},
    {"98190102030405060708090a0b0c0d0e0f101112131415161718181819",
     "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]"},
    {"a0", "{}"}, {"a201020304", "{1:2,3:4}"}, {"a26161016162820203", "{\"a\":1,\"b\":[2,3]}"}, {"826161a161626163", "[\"a\",{\"b\":\"c\"}]"},
    {"a56161614161626142616361436164614461656145", "{\"a\":\"A\",\"b\":\"B\",\"c\":\"C\",\"d\":\"D\",\"e\":\"E\"}"},
    // the indefinite-length ones
    {"5f42010243030405ff", "h'0102030405'"}, {"7f657374726561646d696e67ff", "\"streaming\""}, {"9fff", "[]"},
    {"9f018202039f0405ffff", "[1,[2,3],[4,5]]"}, {"9f01820203820405ff", "[1,[2,3],[4,5]]"}, {"83018202039f0405ff", "[1,[2,3],[4,5]]"},
    {"83019f0203ff820405", "[1,[2,3],[4,5]]"},
    {"9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
     "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]"},
    {"bf61610161629f0203ffff", "{\"a\":1,\"b\":[2,3]}"}, {"826161bf61626163ff", "[\"a\",{\"b\":\"c\"}]"},
    {"bf6346756ef563416d7421ff", "{\"Fun\":true,\"Amt\":-2}"},
};

int main(int argc, char **argv) {
  if (argc > 1 && string(argv[1]) == "--rows") {
    for (int a = 2; a < argc; a++) {
      string b = fromHex(argv[a]);
      Exact t(b);
      cf::Index ix;
      cf::Scan e = cf::scanCbor(t.chars(), ix);
      if (e) { std::printf("%s fault %s at %u\n", argv[a], faultName(e.fault), e.at); continue; }
      std::printf("%s", argv[a]);
      for (uint32_t i = 0; i < ix.size(); i++) std::printf(" %u:%u:%d", ix.open(i), ix.close(i), int(ix.tag(i)));
      std::printf("\n");
    }
    return 0;
  }
  long long random = argc > 1 ? std::atoll(argv[1]) : 100000;

  auto scanOf = [&](const string &bytes, bool det, cf::Index &ix) {
    Exact t(bytes);
    return cf::scanCbor(t.chars(), ix, det);
  };

  // --- appendix A
  for (const Vec &v : rfc) {
    cases++;
    string b = fromHex(v.hex);
    Exact t(b);
    cf::Index ix;
    cf::Scan e = cf::scanCbor(t.chars(), ix);
    if (e) { fail("rfc scan", v.hex, v.want, string("fault ") + faultName(e.fault) + " at " + std::to_string(e.at)); continue; }
    string why;
    if (!laws(ix, t.n, why)) { fail("rfc laws", v.hex, "an index that holds its laws", why); continue; }
    string got = showCbor(ix, reinterpret_cast<const uint8_t *>(t.buf.get()), 0, false);
    if (got != v.want) fail("rfc value", v.hex, v.want, got);
  }

  // --- faults
  struct F { const char *hex; cf::Fault fault; uint32_t at; };
  static const F fs[] = {
      {"", cf::Fault::EndOfInput, 0}, {"83 01 02", cf::Fault::EndOfInput, 0}, {"1a0001", cf::Fault::EndOfInput, 0},
      {"62 41", cf::Fault::EndOfInput, 0}, {"a1 01", cf::Fault::EndOfInput, 0}, {"9f 01", cf::Fault::EndOfInput, 0},
      {"5f 41 01", cf::Fault::EndOfInput, 0}, {"ff", cf::Fault::Break, 0}, {"9f 01 ff ff", cf::Fault::Trailing, 3},
      {"00 00", cf::Fault::Trailing, 1}, {"bf 01 ff", cf::Fault::Break, 2}, {"82 01 ff", cf::Fault::Break, 2},
      {"c0 ff", cf::Fault::Break, 1}, {"5f 61 61 ff", cf::Fault::Chunk, 1}, {"5f 5f 41 01 ff ff", cf::Fault::Chunk, 1},
      {"7f 41 61 ff", cf::Fault::Chunk, 1}, {"62 c3 28", cf::Fault::InvalidUtf8, 1}, {"63 ed a0 80", cf::Fault::InvalidUtf8, 1},
      {"62 c0 80", cf::Fault::InvalidUtf8, 1}, {"64 f4 90 80 80", cf::Fault::InvalidUtf8, 1}, {"7f 62 c3 ff", cf::Fault::InvalidUtf8, 2},
      {"f8 1f", cf::Fault::Reserved, 0}, {"1c", cf::Fault::Reserved, 0}, {"1f", cf::Fault::Reserved, 0}, {"3d", cf::Fault::Reserved, 0},
      {"dc 00", cf::Fault::Reserved, 0}, {"df 00", cf::Fault::Reserved, 0}, {"1b 8000000000000000", cf::Fault::Unsigned, 0},
      {"1b ffffffffffffffff", cf::Fault::Unsigned, 0}, {"3b 8000000000000000", cf::Fault::Unsigned, 0},
      // a four-byte length with the top bit set is a length, not an indefinite one (the Kotlin scan reads it negative)
      {"5a 80000000", cf::Fault::EndOfInput, 0}, {"7a ffffffff", cf::Fault::EndOfInput, 0},
      {"9b ffffffffffffffff", cf::Fault::EndOfInput, 0}, {"bb 8000000000000000", cf::Fault::EndOfInput, 0}, {"bb ffffffffffffffff", cf::Fault::EndOfInput, 0},
  };
  for (const F &f : fs) {
    cases++;
    string hex;
    for (const char *c = f.hex; *c; c++) if (*c != ' ') hex += *c;
    cf::Index ix;
    cf::Scan e = scanOf(fromHex(hex), false, ix);
    if (e.fault != f.fault) fail("fault", f.hex, faultName(f.fault), faultName(e.fault));
    else if (f.fault != cf::Fault::EndOfInput && f.at != e.at && f.fault != cf::Fault::None && string(f.hex) != "")
      fail("fault offset", f.hex, std::to_string(f.at), std::to_string(e.at));
  }

  // --- section 4.2.1
  static const char *det[] = {
      "00", "17", "1818", "1864", "1903e8", "1a000f4240", "20", "3863", "f90000", "f98000", "f93c00", "f93e00", "f97bff", "fa47c35000",
      "fa7f7fffff", "fa47800000", "fb3ff199999999999a", "fb7e37e43c8800759c", "f90001", "f97c00", "f97e00", "f9fc00", "f4", "f5", "f6", "f7", "40",
      "4401020304", "60", "6449455446", "80", "8301820203820405", "a0", "a201020304", "a26161016162820203", "c074323031332d30332d32315432303a30343a30305a",
      "d818456449455446", "c11a514b67b0",
      // the RFC's example of the order of keys: 10, 100, -1, "z", "aa", [100], [-1], false
      "a8 0a 00 1864 00 20 00 617a 00 626161 00 811864 00 813863 00 f4 00",
  };
  for (const char *h : det) {
    cases++;
    string hex;
    for (const char *c = h; *c; c++) if (*c != ' ') hex += *c;
    cf::Index ix;
    cf::Scan e = scanOf(fromHex(hex), true, ix);
    if (e) fail("deterministic accepted", h, "None", faultName(e.fault));
  }
  struct D { const char *hex; cf::Fault fault; };
  static const D nondet[] = {
      {"1800", cf::Fault::NonShortest}, {"1817", cf::Fault::NonShortest}, {"190001", cf::Fault::NonShortest}, {"1900ff", cf::Fault::NonShortest},
      {"1a0000ffff", cf::Fault::NonShortest}, {"1b00000000ffffffff", cf::Fault::NonShortest}, {"3800", cf::Fault::NonShortest},
      {"5800", cf::Fault::NonShortest}, {"780161", cf::Fault::NonShortest}, {"9800", cf::Fault::NonShortest}, {"b800", cf::Fault::NonShortest},
      {"d80100", cf::Fault::NonShortest}, {"d90001 00", cf::Fault::NonShortest},
      {"fb3ff0000000000000", cf::Fault::NonShortest}, {"fa3f800000", cf::Fault::NonShortest}, {"fa7f800000", cf::Fault::NonShortest},
      {"fb7ff0000000000000", cf::Fault::NonShortest}, {"fa7fc00000", cf::Fault::NonShortest}, {"f97e01", cf::Fault::NonShortest},
      {"f9fe00", cf::Fault::NonShortest}, {"fb7ff8000000000000", cf::Fault::NonShortest}, {"fa38800000", cf::Fault::NonShortest},
      {"fb3f00000000000000", cf::Fault::NonShortest}, // 2^-15, a float64 that a half holds
      {"9fff", cf::Fault::Indefinite}, {"5fff", cf::Fault::Indefinite}, {"7fff", cf::Fault::Indefinite}, {"bfff", cf::Fault::Indefinite},
      {"a2 02 00 01 00", cf::Fault::KeyOrder}, {"a2 01 00 01 00", cf::Fault::KeyOrder}, {"a2 626161 00 6161 00", cf::Fault::KeyOrder},
      {"a2 6162 00 6161 00", cf::Fault::KeyOrder}, {"a2 f4 00 0a 00", cf::Fault::KeyOrder},
      {"a8 0a 00 1864 00 20 00 626161 00 617a 00 811864 00 813863 00 f4 00", cf::Fault::KeyOrder},
      {"a8 0a 00 1864 00 20 00 617a 00 626161 00 813863 00 811864 00 f4 00", cf::Fault::KeyOrder},
      {"81 a2 03 00 02 00", cf::Fault::KeyOrder},
  };
  for (const D &d : nondet) {
    cases++;
    string hex;
    for (const char *c = d.hex; *c; c++) if (*c != ' ') hex += *c;
    cf::Index ix;
    cf::Scan e = scanOf(fromHex(hex), true, ix);
    if (e.fault != d.fault) fail("deterministic", d.hex, faultName(d.fault), faultName(e.fault));
    cf::Index ix2;
    if (cf::Scan w = scanOf(fromHex(hex), false, ix2)) fail("a well-formed text", d.hex, "None", faultName(w.fault));
  }

  // --- the encoder
  struct E { const char *json, *hex; };
  static const E enc[] = {
      {"0", "00"}, {"1", "01"}, {"-1", "20"}, {"10", "0a"}, {"23", "17"}, {"24", "1818"}, {"100", "1864"}, {"1000", "1903e8"}, {"-1000", "3903e7"},
      {"65536", "1a00010000"}, {"4294967296", "1b0000000100000000"}, {"9223372036854775807", "1b7fffffffffffffff"},
      {"-9223372036854775808", "3b7fffffffffffffff"}, {"1.0", "f93c00"}, {"1.5", "f93e00"}, {"-0.0", "f98000"}, {"0.0", "f90000"},
      {"65504.0", "f97bff"}, {"65536.0", "fa47800000"}, {"131072.0", "fa48000000"}, {"100000.0", "fa47c35000"}, {"0.1", "fb3fb999999999999a"}, {"1.1", "fb3ff199999999999a"},
      {"1e300", "fb7e37e43c8800759c"}, {"5.960464477539063e-8", "f90001"}, {"6.103515625e-5", "f90400"}, {"-4.0", "f9c400"},
      {"3.4028234663852886e+38", "fa7f7fffff"}, {"1e999", "f97c00"}, {"-1e999", "f9fc00"},
      {"true", "f5"}, {"false", "f4"}, {"null", "f6"}, {"\"\"", "60"}, {"\"a\"", "6161"}, {"\"IETF\"", "6449455446"}, {"\"\\\"\\\\\"", "62225c"},
      {"\"\\u00fc\"", "62c3bc"}, {"\"\\u6c34\"", "63e6b0b4"}, {"\"\\ud800\\udd51\"", "64f0908591"}, {"\"a\\nb\"", "63610a62"},
      {"[]", "80"}, {"{}", "a0"}, {"[1,2,3]", "83010203"}, {"[1,[2,3],[4,5]]", "8301820203820405"}, {" [ 1 , [ 2 , 3 ] ] ", "8201820203"},
      {"{\"a\":1,\"b\":[2,3]}", "a26161016162820203"}, {"{\"b\":[2,3],\"a\":1}", "a26161016162820203"}, {"{\"b\":1,\"a\":2}", "a2616102616201"},
      {"{\"aa\":1,\"b\":2,\"a\":3}", "a3616103616202626161" "01"}, {"{\"\":0,\"a\":1}", "a2" "60" "00" "6161" "01"},
      {"{\"a\":{\"z\":1,\"y\":2},\"b\":[]}", "a26161a2617902617a0161628" "0"},
  };
  for (const E &e : enc) {
    cases++;
    string js = e.json;
    Exact t(js);
    cf::Index ix;
    if (cf::Scan sc = cf::scan(t.chars(), ix)) { fail("encoder input", js, "a JSON text", faultName(sc.fault)); continue; }
    string out;
    cf::Scan r = cf::encodeJson(t.buf.get(), ix, out);
    if (r) { fail("encoder", js, e.hex, faultName(r.fault)); continue; }
    if (toHex(out) != e.hex) fail("encoder", js, e.hex, toHex(out));
    cf::Index back;
    cf::Scan d = scanOf(out, true, back);
    if (d) fail("encoder output is deterministic", js, "None", faultName(d.fault));
  }
  {
    struct EF { const char *json; cf::Fault fault; };
    static const EF efs[] = {{"\"\\udc00\"", cf::Fault::InvalidUtf8}, {"{\"a\":1,\"a\":2}", cf::Fault::KeyOrder},
                             {"{\"a\":1,\"\\u0061\":2}", cf::Fault::KeyOrder}};
    for (const EF &e : efs) {
      cases++;
      string js = e.json;
      Exact t(js);
      cf::Index ix;
      cf::scan(t.chars(), ix);
      string out;
      cf::Scan r = cf::encodeJson(t.buf.get(), ix, out);
      if (r.fault != e.fault) fail("encoder fault", js, faultName(e.fault), faultName(r.fault));
    }
  }

  // --- random
  std::mt19937_64 rng(20261103);
  auto pick = [&](uint32_t n) { return uint32_t(rng() % n); };
  // A random JSON text (not deep), with its members in the order drawn.
  std::function<string(int)> doc = [&](int depth) -> string {
    switch (pick(depth > 3 ? 6 : 9)) {
    case 0: return "null";
    case 1: return pick(2) ? "true" : "false";
    case 2: { static const long long edge[] = {0, 1, 23, 24, 255, 256, 65535, 65536, 4294967295LL, 4294967296LL, 9223372036854775807LL}; long long v = edge[pick(11)]; return std::to_string(pick(2) ? -v : v); }
    case 3: { static const char *fl[] = {"0.5", "1.0", "-2.5", "0.1", "3.14159", "1e10", "1e-10", "65504.0", "100000.0", "5.960464477539063e-8", "1e300", "-1e-300", "0.0", "-0.0", "16777216.0", "1.0000001"}; return fl[pick(16)]; }
    case 4: case 5: { static const char *st[] = {"\"\"", "\"a\"", "\"hello world\"", "\"\\u00e9\"", "\"\\u6c34\\u0041\"", "\"\\ud83d\\ude00\"", "\"line\\nbreak\"", "\"q\\\"\""}; return st[pick(8)]; }
    case 6: { string r = "["; uint32_t k = pick(5); for (uint32_t i = 0; i < k; i++) r += (i ? "," : "") + doc(depth + 1); return r + "]"; }
    default: { string r = "{"; uint32_t k = pick(5); for (uint32_t i = 0; i < k; i++) { r += (i ? "," : "") + string("\"k") + std::to_string(pick(1000)) + "_" + std::to_string(i) + "\":" + doc(depth + 1); } return r + "}"; }
    }
  };
  for (long long it = 0; it < random; it++) {
    cases++;
    string js = doc(0);
    Exact t(js);
    cf::Index ix;
    if (cf::scan(t.chars(), ix)) { fail("random json", js, "a JSON text", "a fault"); continue; }
    string out;
    if (cf::Scan r = cf::encodeJson(t.buf.get(), ix, out)) { fail("random encode", js, "bytes", faultName(r.fault)); continue; }
    cf::Index back;
    if (cf::Scan d = scanOf(out, true, back)) { fail("random encode is deterministic", js, "None", faultName(d.fault)); continue; }
    string why;
    Exact o(out);
    if (!laws(back, o.n, why)) { fail("random laws", js, "laws", why); continue; }
    string a = showJson(ix, t.buf.get(), 0), b = showCbor(back, reinterpret_cast<const uint8_t *>(o.buf.get()), 0, true);
    if (a != b) fail("random round trip", js, a, b);
  }
  // Mutations of the vectors and random bytes: the laws on whatever scans, and a deterministic scan is a scan.
  std::vector<string> seeds;
  for (const Vec &v : rfc) seeds.push_back(fromHex(v.hex));
  for (long long it = 0; it < random; it++) {
    cases++;
    string b;
    if (pick(4) == 0) { uint32_t n = pick(12); for (uint32_t i = 0; i < n; i++) b.push_back(char(rng())); }
    else {
      b = seeds[pick(uint32_t(seeds.size()))];
      uint32_t m = 1 + pick(3);
      for (uint32_t i = 0; i < m && !b.empty(); i++) {
        switch (pick(4)) {
        case 0: b[pick(uint32_t(b.size()))] = char(rng()); break;
        case 1: b.insert(b.begin() + pick(uint32_t(b.size() + 1)), char(rng())); break;
        case 2: b.erase(b.begin() + pick(uint32_t(b.size()))); break;
        default: b.resize(pick(uint32_t(b.size() + 1))); break;
        }
      }
    }
    cf::Index ix;
    Exact t(b);
    cf::Scan e = cf::scanCbor(t.chars(), ix);
    cf::Index ix2;
    cf::Scan d = cf::scanCbor(t.chars(), ix2, true);
    if (!d && e) fail("deterministic but not well-formed", toHex(b), "a fault", "None");
    if (!e) {
      string why;
      if (!laws(ix, t.n, why)) fail("laws", toHex(b), "laws", why);
    }
    if (!e && !d) {
      string why;
      if (!laws(ix2, t.n, why)) fail("laws (deterministic)", toHex(b), "laws", why);
    }
  }
  // A document nested a million deep takes no stack.
  {
    string deep(1000000, char(0x81));
    deep.push_back(char(0x00));
    cases++;
    cf::Index ix;
    cf::Scan e = scanOf(deep, false, ix);
    if (e || ix.size() != 1000001) fail("deep", "1,000,000 arrays", "1000001 rows", e ? faultName(e.fault) : std::to_string(ix.size()));
    string deepj = string(20000, '[') + string(20000, ']');
    Exact tj(deepj);
    cf::Index jx;
    if (cf::scan(tj.chars(), jx)) fail("deep json", "20000 arrays", "scan", "fault");
    else {
      string out;
      if (cf::Scan r = cf::encodeJson(tj.buf.get(), jx, out)) fail("deep encode", "20000 arrays", "bytes", faultName(r.fault));
    }
  }
  std::printf("%lld cases, %lld failures\n", cases, failures);
  return failures ? 1 : 0;
}
