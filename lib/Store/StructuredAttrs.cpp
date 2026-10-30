//===- StructuredAttrs.cpp - __structuredAttrs support for builders -------===//
//
// A tiny JSON DOM (enough for structured attributes), plus the generation of
// .attrs.json / .attrs.sh exactly as upstream's ParsedDerivation does.
//
//===----------------------------------------------------------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Mutable.h"
#include "Nix/Store.h"

#include <cmath>
#include <cstring>

namespace nixstore {

namespace {
struct Member;
struct JV {
  enum T { Null, Bool, Num, Str, Arr, Obj } t = Null;
  bool b = false;
  composite::Text raw; // number text or string value
  composite::MutableSeries<JV> arr;
  composite::MutableSeries<Member> obj; // the members in key order, as a JSON object is written: rows, no tree
  JV() = default;
  JV(JV &&) = default;
  JV &operator=(JV &&) = default;
  /// A JSON value is copied into its parent; its arrays and members are copied cell by cell, spelled out.
  JV(const JV &o);
  /// The member named k, made null first when there is none, where its key sorts.
  JV &member(std::string_view k);
  JV &operator=(const JV &o) {
    if (this != &o) { JV c(o); *this = static_cast<JV &&>(c); }
    return *this;
  }
};
struct Member {
  composite::Text key;
  JV value;
};
JV::JV(const JV &o) : t(o.t), b(o.b), raw(o.raw.clone()) {
  for (const JV &x : o.arr) arr.append(x);
  for (const Member &m : o.obj) obj.append(Member{m.key.clone(), m.value});
}
JV &JV::member(std::string_view k) {
  uint32_t lo = 0, hi = obj.size();
  while (lo < hi) {
    uint32_t mid = (lo + hi) / 2;
    if (obj[mid].key < k) lo = mid + 1;
    else hi = mid;
  }
  if (lo < obj.size() && obj[lo].key == k) return obj[lo].value;
  obj.append(Member{composite::Text(k), JV()});
  for (uint32_t j = obj.size() - 1; j > lo; j--) { // the new row moves down to its place
    Member t = composite::mv(obj[j]);
    obj[j] = composite::mv(obj[j - 1]);
    obj[j - 1] = composite::mv(t);
  }
  return obj[lo].value;
}

struct P {
  std::string_view s;
  size_t p = 0;
  void ws() {
    while (p < s.size() && isspace((unsigned char)s[p])) p++;
  }
  [[noreturn]] void fail() { throw Error("invalid structured attributes JSON"); }
  /// The byte at p, NUL at or past the end: a \u escape cut short by the end of the input leaves p beyond it.
  char peek() const { return p < s.size() ? s[p] : '\0'; }
  /// The (up to) four hex digits of a \u escape at `at`, as strtoul reads them; a window with none is not JSON.
  unsigned hex4(size_t at) {
    uint32_t n = at < s.size() ? uint32_t(composite::min<size_t>(4, s.size() - at)) : 0;
    composite::text::Reading r = composite::facet<composite::text::Integer<16, false>>(composite::chars(s.data() + at, n));
    if (r.consumed == 0) fail();
    return unsigned(r.value);
  }
  composite::Text str() {
    p++;
    composite::Text o;
    while (p < s.size() && s[p] != '"') {
      if (s[p] == '\\') {
        p++;
        char e = peek();
        p++;
        switch (e) {
        case 'n': o += '\n'; break;
        case 't': o += '\t'; break;
        case 'r': o += '\r'; break;
        case 'b': o += '\b'; break;
        case 'f': o += '\f'; break;
        case 'u': {
          unsigned cp = hex4(p);
          p += 4;
          if (cp >= 0xD800 && cp <= 0xDBFF && s.substr(p, 2) == "\\u") {
            unsigned lo = hex4(p + 2);
            p += 6;
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          }
          if (cp < 0x80) o += char(cp);
          else if (cp < 0x800) { o += char(0xC0 | (cp >> 6)); o += char(0x80 | (cp & 0x3F)); }
          else if (cp < 0x10000) { o += char(0xE0 | (cp >> 12)); o += char(0x80 | ((cp >> 6) & 0x3F)); o += char(0x80 | (cp & 0x3F)); }
          else { o += char(0xF0 | (cp >> 18)); o += char(0x80 | ((cp >> 12) & 0x3F)); o += char(0x80 | ((cp >> 6) & 0x3F)); o += char(0x80 | (cp & 0x3F)); }
          break;
        }
        default: o += e;
        }
      } else {
        o += s[p++];
      }
    }
    p++;
    return o;
  }
  JV val() {
    ws();
    JV v;
    if (p >= s.size()) fail();
    char c = s[p];
    if (c == '{') {
      p++;
      v.t = JV::Obj;
      ws();
      if (peek() == '}') { p++; return v; }
      while (true) {
        ws();
        composite::Text k = str();
        ws();
        p++; // :
        v.member(k) = val();
        ws();
        if (peek() == ',') { p++; continue; }
        p++;
        return v;
      }
    }
    if (c == '[') {
      p++;
      v.t = JV::Arr;
      ws();
      if (peek() == ']') { p++; return v; }
      while (true) {
        v.arr.append(val());
        ws();
        if (peek() == ',') { p++; continue; }
        p++;
        return v;
      }
    }
    if (c == '"') { v.t = JV::Str; v.raw = str(); return v; }
    if (s.substr(p, 4) == "true") { p += 4; v.t = JV::Bool; v.b = true; return v; }
    if (s.substr(p, 5) == "false") { p += 5; v.t = JV::Bool; return v; }
    if (s.substr(p, 4) == "null") { p += 4; return v; }
    size_t st = p;
    while (p < s.size() && (isdigit((unsigned char)s[p]) || strchr("+-.eE", s[p]))) p++;
    v.t = JV::Num;
    v.raw = composite::Text(s.substr(st, p - st));
    return v;
  }
};

composite::Text dump(const JV &v) {
  switch (v.t) {
  case JV::Null: return "null";
  case JV::Bool: return v.b ? "true" : "false";
  case JV::Num: return v.raw.clone();
  case JV::Str: return jsonEscape(v.raw);
  case JV::Arr: {
    composite::Text o = "[";
    for (size_t i = 0; i < v.arr.size(); i++) o.put(i ? "," : "").put(dump(v.arr[i]));
    o += ']';
    return o;
  }
  case JV::Obj: {
    composite::Text o = "{";
    bool first = true;
    for (auto &[k, x] : v.obj) {
      o.put(first ? "" : ",").put(jsonEscape(k)).put(':').put(dump(x));
      first = false;
    }
    o += '}';
    return o;
  }
  }
  return "null";
}

composite::Text shellEscape(std::string_view s) {
  composite::Text r = "'";
  for (char c : s) {
    if (c == '\'') r += "'\\''";
    else r += c;
  }
  r += '\'';
  return r;
}

/// Whether `s` is a name the shell can declare: [A-Za-z_][A-Za-z0-9_]*
bool isShellName(composite::Chars s) {
  auto word = [](char c) { return composite::isAsciiAlnum(c) || c == '_'; };
  return s.size() && !composite::isAsciiDigit(s[0]) && composite::firstWhere(s, [&](char c) { return !word(c); }) == s.size();
}

composite::Maybe<composite::Text> simple(const JV &v) {
  switch (v.t) {
  case JV::Str: return shellEscape(v.raw);
  case JV::Num: {
    double f = strtod(v.raw.c_str(), nullptr);
    if (std::ceil((float)f) == (float)f) return composite::str((int)f);
    return nullptr;
  }
  case JV::Null: return composite::Text("''");
  case JV::Bool: return v.b ? composite::Text("1") : composite::Text("");
  default: return nullptr;
  }
}

void rewrite(JV &v, const SortedMap<composite::Text> &rw) {
  auto fix = [&](composite::Text &s) {
    for (auto &[from, to] : rw) {
      size_t pos = 0;
      while ((pos = s.find(from, pos)) != composite::npos) {
        s.erase(pos, from.size());
        s.insert(pos, to);
        pos += to.size();
      }
    }
  };
  if (v.t == JV::Str) fix(v.raw);
  for (auto &x : v.arr) rewrite(x, rw);
  for (auto &[k, x] : v.obj) rewrite(x, rw);
}
} // namespace

/// Produce (.attrs.json, .attrs.sh) for a structured-attrs derivation.
composite::Join<composite::Text, composite::Text> structuredAttrsFiles(std::string_view json,
                                                         const SortedMap<composite::Text> &outputs,
                                                         const SortedMap<composite::Text> &rewrites) {
  P parser{json};
  JV root = parser.val();
  if (root.t != JV::Obj) throw Error("structured attributes must be a JSON object");
  rewrite(root, rewrites);
  JV outs;
  outs.t = JV::Obj;
  for (auto &[n, p] : outputs) {
    JV s;
    s.t = JV::Str;
    s.raw = p.clone();
    outs.member(n) = s;
  }
  root.member("outputs") = outs;
  composite::Text sh;
  for (auto &[key, value] : root.obj) {
    if (!isShellName(composite::chars(key.data(), uint32_t(key.size())))) continue;
    if (auto s = simple(value)) {
      sh.put("declare ").put(key).put('=').put(*s).put('\n');
    } else if (value.t == JV::Arr) {
      composite::Text s2;
      bool good = true;
      for (auto &x : value.arr) {
        auto s3 = simple(x);
        if (!s3) { good = false; break; }
        s2.put(*s3).put(' ');
      }
      if (good) sh.put("declare -a ").put(key).put("=(").put(s2).put(")\n");
    } else if (value.t == JV::Obj) {
      composite::Text s2;
      bool good = true;
      for (auto &[k2, x] : value.obj) {
        auto s3 = simple(x);
        if (!s3) { good = false; break; }
        s2.put('[').put(shellEscape(k2)).put("]=").put(*s3).put(' ');
      }
      if (good) sh.put("declare -A ").put(key).put("=(").put(s2).put(")\n");
    }
  }
  return {dump(root), composite::mv(sh)};
}

} // namespace nixstore
