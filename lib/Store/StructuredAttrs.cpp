//===- StructuredAttrs.cpp - __structuredAttrs support for builders -------===//
//
// A tiny JSON DOM (enough for structured attributes), plus the generation of
// .attrs.json / .attrs.sh exactly as upstream's ParsedDerivation does.
//
//===----------------------------------------------------------------------===//

#include "Nix/Store.h"

#include <cmath>
#include <cstring>
#include <map>
#include <regex>
#include <vector>

namespace nixstore {

namespace {
struct JV {
  enum T { Null, Bool, Num, Str, Arr, Obj } t = Null;
  bool b = false;
  std::string raw; // number text or string value
  std::vector<JV> arr;
  std::map<std::string, JV> obj;
};

struct P {
  std::string_view s;
  size_t p = 0;
  void ws() {
    while (p < s.size() && isspace((unsigned char)s[p])) p++;
  }
  [[noreturn]] void fail() { throw Error("invalid structured attributes JSON"); }
  std::string str() {
    p++;
    std::string o;
    while (p < s.size() && s[p] != '"') {
      if (s[p] == '\\') {
        p++;
        char e = s[p++];
        switch (e) {
        case 'n': o += '\n'; break;
        case 't': o += '\t'; break;
        case 'r': o += '\r'; break;
        case 'b': o += '\b'; break;
        case 'f': o += '\f'; break;
        case 'u': {
          unsigned cp = std::stoul(std::string(s.substr(p, 4)), nullptr, 16);
          p += 4;
          if (cp >= 0xD800 && cp <= 0xDBFF && s.substr(p, 2) == "\\u") {
            unsigned lo = std::stoul(std::string(s.substr(p + 2, 4)), nullptr, 16);
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
      if (s[p] == '}') { p++; return v; }
      while (true) {
        ws();
        std::string k = str();
        ws();
        p++; // :
        v.obj[k] = val();
        ws();
        if (s[p] == ',') { p++; continue; }
        p++;
        return v;
      }
    }
    if (c == '[') {
      p++;
      v.t = JV::Arr;
      ws();
      if (s[p] == ']') { p++; return v; }
      while (true) {
        v.arr.push_back(val());
        ws();
        if (s[p] == ',') { p++; continue; }
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
    v.raw = std::string(s.substr(st, p - st));
    return v;
  }
};

std::string dump(const JV &v) {
  switch (v.t) {
  case JV::Null: return "null";
  case JV::Bool: return v.b ? "true" : "false";
  case JV::Num: return v.raw;
  case JV::Str: return jsonEscape(v.raw);
  case JV::Arr: {
    std::string o = "[";
    for (size_t i = 0; i < v.arr.size(); i++) o += (i ? "," : "") + dump(v.arr[i]);
    return o + "]";
  }
  case JV::Obj: {
    std::string o = "{";
    bool first = true;
    for (auto &[k, x] : v.obj) {
      o += (first ? "" : ",") + jsonEscape(k) + ":" + dump(x);
      first = false;
    }
    return o + "}";
  }
  }
  return "null";
}

std::string shellEscape(std::string_view s) {
  std::string r = "'";
  for (char c : s) {
    if (c == '\'') r += "'\\''";
    else r += c;
  }
  return r + "'";
}

std::optional<std::string> simple(const JV &v) {
  switch (v.t) {
  case JV::Str: return shellEscape(v.raw);
  case JV::Num: {
    double f = strtod(v.raw.c_str(), nullptr);
    if (std::ceil((float)f) == (float)f) return std::to_string((int)f);
    return std::nullopt;
  }
  case JV::Null: return std::string("''");
  case JV::Bool: return v.b ? std::string("1") : std::string("");
  default: return std::nullopt;
  }
}

void rewrite(JV &v, const std::map<std::string, std::string> &rw) {
  auto fix = [&](std::string &s) {
    for (auto &[from, to] : rw) {
      size_t pos = 0;
      while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
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
std::pair<std::string, std::string> structuredAttrsFiles(const std::string &json,
                                                         const std::map<std::string, std::string> &outputs,
                                                         const std::map<std::string, std::string> &rewrites) {
  P parser{json};
  JV root = parser.val();
  if (root.t != JV::Obj) throw Error("structured attributes must be a JSON object");
  rewrite(root, rewrites);
  JV outs;
  outs.t = JV::Obj;
  for (auto &[n, p] : outputs) {
    JV s;
    s.t = JV::Str;
    s.raw = p;
    outs.obj[n] = s;
  }
  root.obj["outputs"] = outs;
  static const std::regex shVarName("[A-Za-z_][A-Za-z0-9_]*");
  std::string sh;
  for (auto &[key, value] : root.obj) {
    if (!std::regex_match(key, shVarName)) continue;
    if (auto s = simple(value)) {
      sh += "declare " + key + "=" + *s + "\n";
    } else if (value.t == JV::Arr) {
      std::string s2;
      bool good = true;
      for (auto &x : value.arr) {
        auto s3 = simple(x);
        if (!s3) { good = false; break; }
        s2 += *s3 + " ";
      }
      if (good) sh += "declare -a " + key + "=(" + s2 + ")\n";
    } else if (value.t == JV::Obj) {
      std::string s2;
      bool good = true;
      for (auto &[k2, x] : value.obj) {
        auto s3 = simple(x);
        if (!s3) { good = false; break; }
        s2 += "[" + shellEscape(k2) + "]=" + *s3 + " ";
      }
      if (good) sh += "declare -A " + key + "=(" + s2 + ")\n";
    }
  }
  return {dump(root), sh};
}

} // namespace nixstore
