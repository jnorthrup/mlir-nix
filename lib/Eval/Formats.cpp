//===- Formats.cpp - JSON, XML and TOML conversions -----------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Mutable.h"
#include "Nix/Eval.h"

#include "mlir/IR/BuiltinAttributes.h"

#include <cmath>
#include <cstring>
#include <map>
#include <set>
#include <unistd.h>
#include <climits>
#include <sstream>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

using A = Value **;
static std::string str(std::string_view s) { return std::string(s); }

//===----------------------------------------------------------------------===//
// JSON output
//===----------------------------------------------------------------------===//

static void checkUTF8(std::string_view s) {
  size_t i = 0;
  while (i < s.size()) {
    unsigned char c = s[i];
    size_t n = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
    bool ok = n != 0 && i + n <= s.size();
    for (size_t k = 1; ok && k < n; k++) ok = ((unsigned char)s[i + k] >> 6) == 2;
    if (!ok) {
      size_t bad = i;
      if (n > 1)
        for (size_t k = 1; k < n && i + k < s.size(); k++)
          if (((unsigned char)s[i + k] >> 6) != 2) { bad = i + k; break; }
      const char hex[] = "0123456789ABCDEF";
      unsigned char byte = (unsigned char)s[bad];
      throw EvalError("JSON serialization error: [json.exception.type_error.316] invalid UTF-8 byte at index " + std::to_string(bad) + ": 0x" +
                      hex[byte >> 4] + hex[byte & 15]);
    }
    i += n;
  }
}

namespace {
struct CallDepth {
  unsigned &d;
  CallDepth(EvalState &st, PosPtr pos) : d(st.callDepth) {
    if (++d > st.settings.maxCallDepth) {
      --d;
      throw StackOverflowError("stack overflow; max-call-depth exceeded", pos);
    }
  }
  ~CallDepth() { --d; }
};
} // namespace

void EvalState::printValueAsJSON(std::ostream &out, Value &v, bool strict, NixStringContext &ctx, bool copyToStore,
                                 PosPtr pos) {
  CallDepth guard(*this, pos);
  if (strict) forceValue(v, pos);
  switch (v.type) {
  case VType::Int: out << v.integer; break;
  case VType::Bool: out << (v.boolean ? "true" : "false"); break;
  case VType::String:
    copyContext(v, ctx);
    checkUTF8(v.sv());
    out << nixstore::jsonEscape(v.sv());
    break;
  case VType::Path:
    if (copyToStore) out << nixstore::jsonEscape(copyPathToStore(ctx, std::string(v.pathView())));
    else out << nixstore::jsonEscape(v.pathView());
    break;
  case VType::Null: out << "null"; break;
  case VType::Attrs: {
    if (auto s2 = tryAttrsToString(v, ctx, false, false)) {
      out << nixstore::jsonEscape(*s2);
      break;
    }
    if (const Attr *o = v.attrs->get(s.outPath)) {
      printValueAsJSON(out, *o->value, strict, ctx, copyToStore, positionOf(*o));
      break;
    }
    out << "{";
    bool first = true;
    for (const Attr *a : v.attrs->lexicographicOrder(symbols)) {
      if (!first) out << ",";
      first = false;
      out << nixstore::jsonEscape(symbols[a->name]) << ":";
      try {
        printValueAsJSON(out, *a->value, strict, ctx, copyToStore, positionOf(*a));
      } catch (EvalError &e) {
        e.addTrace(positionOf(*a), "while evaluating attribute '" + symbols[a->name].str() + "'");
        throw;
      }
    }
    out << "}";
    break;
  }
  case VType::List:
    out << "[";
    for (size_t i = 0; i < v.listSize(); i++) {
      if (i) out << ",";
      if (callDepth <= 2) beginEpoch(); // MLNIX_STATS: an element of the top-level list is an epoch
      try {
        printValueAsJSON(out, *v.list.elems[i], strict, ctx, copyToStore, pos);
      } catch (EvalError &e) {
        e.addTrace(pos, "while evaluating list element at index " + std::to_string(i));
        throw;
      }
    }
    out << "]";
    break;
  case VType::Float: out << nixstore::jsonFloat(v.fpoint); break;
  case VType::Thunk: case VType::App: case VType::Blackhole:
    out << "null";
    break;
  default:
    throw EvalError(std::string("cannot convert ") + showType(v) + " to JSON", pos);
  }
}

//===----------------------------------------------------------------------===//
// JSON input
//===----------------------------------------------------------------------===//

namespace {
struct JSONParser {
  EvalState &st;
  std::string_view s;
  size_t p = 0;
  [[noreturn]] void fail(const std::string &what) {
    throw EvalError("[json.exception.parse_error.101] parse error at line 1, column " + std::to_string(p + 1) +
                    ": syntax error while parsing value - " + what);
  }
  void ws() {
    while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) p++;
  }
  static void utf8(std::string &out, uint32_t cp) {
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
  std::string string() {
    std::string r = stringRaw();
    if (r.find('\0') != std::string::npos) {
      std::string shown;
      for (char c : r) {
        if (c == '\0') shown += "\u2400";
        else shown += c;
      }
      // U+2400 SYMBOL FOR NULL, as UTF-8.
      std::string out2;
      for (size_t i = 0; i < shown.size(); i++) {
        if (shown.compare(i, 6, "\u2400") == 0) { out2 += "\xe2\x90\x80"; i += 5; }
        else out2 += shown[i];
      }
      throw EvalError("input string '" + out2 + "' cannot be represented as Nix string because it contains null bytes");
    }
    return r;
  }
  std::string stringRaw() {
    p++; // "
    std::string out;
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
  void value(Value &v) {
    ws();
    if (p >= s.size()) fail("unexpected end of input; expected '[', '{', or a literal");
    char c = s[p];
    if (c == '{') {
      p++;
      EvalState::BindingsBuilder bb(st);
      std::map<std::string, Value *> m;
      ws();
      if (p < s.size() && s[p] == '}') { p++; st.mkAttrs(v, bb.finish()); return; }
      while (true) {
        ws();
        if (p >= s.size() || s[p] != '"') fail("invalid literal; expected string literal");
        std::string k = string();
        ws();
        if (p >= s.size() || s[p] != ':') fail("syntax error; expected ':'");
        p++;
        Value *e = st.allocValue();
        value(*e);
        m[k] = e; // last wins
        ws();
        if (p < s.size() && s[p] == ',') { p++; continue; }
        if (p < s.size() && s[p] == '}') { p++; break; }
        fail("syntax error; expected '}'");
      }
      for (auto &[k, e] : m) bb.insert(k, e);
      st.mkAttrs(v, bb.finish());
      return;
    }
    if (c == '[') {
      p++;
      composite::MutableSeries<Value *> elems;
      ws();
      if (p < s.size() && s[p] == ']') { p++; st.mkList(v, 0); return; }
      while (true) {
        Value *e = st.allocValue();
        value(*e);
        elems.append(e);
        ws();
        if (p < s.size() && s[p] == ',') { p++; continue; }
        if (p < s.size() && s[p] == ']') { p++; break; }
        fail("syntax error; expected ']'");
      }
      st.mkList(v, elems);
      return;
    }
    if (c == '"') { st.mkString(v, string()); return; }
    if (s.substr(p, 4) == "true") { p += 4; st.mkBool(v, true); return; }
    if (s.substr(p, 5) == "false") { p += 5; st.mkBool(v, false); return; }
    if (s.substr(p, 4) == "null") { p += 4; st.mkNull(v); return; }
    if (c == '-' || (c >= '0' && c <= '9')) {
      size_t start = p;
      if (s[p] == '-') p++;
      bool isFloat = false;
      while (p < s.size() && composite::isAsciiDigit(s[p])) p++;
      if (p < s.size() && s[p] == '.') { isFloat = true; p++; while (p < s.size() && composite::isAsciiDigit(s[p])) p++; }
      if (p < s.size() && (s[p] == 'e' || s[p] == 'E')) {
        isFloat = true;
        p++;
        if (p < s.size() && (s[p] == '+' || s[p] == '-')) p++;
        while (p < s.size() && composite::isAsciiDigit(s[p])) p++;
      }
      std::string num(s.substr(start, p - start));
      if (!isFloat) {
        // The integer facets (composite::text::Integer), the reading strtoll and strtoull make: overflow is ERANGE.
        composite::CharSeries digits = composite::chars(num);
        if (num[0] == '-') {
          composite::text::Reading r = composite::facet<composite::text::Integer<10, true>>(digits);
          if (r.overflow) { st.mkFloat(v, strtod(num.c_str(), nullptr)); return; }
          st.mkInt(v, (int64_t)r.value);
        } else {
          composite::text::Reading r = composite::facet<composite::text::Integer<10, false>>(digits);
          if (r.overflow) { st.mkFloat(v, strtod(num.c_str(), nullptr)); return; }
          if (r.value > (uint64_t)INT64_MAX)
            throw EvalError("unsigned json number " + num + " outside of Nix integer range");
          st.mkInt(v, (int64_t)r.value);
        }
      } else {
        st.mkFloat(v, strtod(num.c_str(), nullptr));
      }
      return;
    }
    fail("invalid literal");
  }
};
} // namespace

void parseJSON(EvalState &state, std::string_view json, Value &v) {
  JSONParser P{state, json};
  P.value(v);
  P.ws();
  if (P.p != json.size()) P.fail("syntax error while parsing value - unexpected trailing content; expected end of input");
}

//===----------------------------------------------------------------------===//
// XML output
//===----------------------------------------------------------------------===//

namespace {
struct XMLWriter {
  std::ostream &out;
  composite::MutableSeries<std::string> stack{};
  using Attrs = std::map<std::string, std::string>;
  void attrs(const Attrs &as) {
    for (auto &[k, v] : as) {
      out << " " << k << "=\"";
      for (char c : v) {
        if (c == '"') out << "&quot;";
        else if (c == '<') out << "&lt;";
        else if (c == '>') out << "&gt;";
        else if (c == '&') out << "&amp;";
        else if (c == '\n') out << "&#xA;";
        else out << c;
      }
      out << "\"";
    }
  }
  void open(const std::string &n, const Attrs &as = {}) {
    out << std::string(stack.size() * 2, ' ') << "<" << n;
    attrs(as);
    out << ">\n";
    stack.append(n);
  }
  void close() {
    out << std::string((stack.size() - 1) * 2, ' ') << "</" << stack.back() << ">\n";
    stack.pop();
  }
  void empty(const std::string &n, const Attrs &as = {}) {
    out << std::string(stack.size() * 2, ' ') << "<" << n;
    attrs(as);
    out << " />\n";
  }
};

void posToXML(EvalState &st, XMLWriter::Attrs &as, PosPtr pos) {
  auto loc = nd::decodePos(pos);
  if (!loc) return;
  if (!loc->file.empty() && loc->file[0] == '/') as["path"] = loc->file;
  as["line"] = std::to_string(loc->line);
  as["column"] = std::to_string(loc->col);
}

void toXML(EvalState &st, XMLWriter &doc, Value &v, bool strict, bool location, NixStringContext &ctx,
           std::set<std::string> &drvsSeen, PosPtr pos);

void showAttrsXML(EvalState &st, XMLWriter &doc, Bindings *attrs, bool strict, bool location,
                  NixStringContext &ctx, std::set<std::string> &drvsSeen) {
  for (const Attr *a : attrs->lexicographicOrder(st.symbols)) {
    XMLWriter::Attrs as{{"name", st.symbols[a->name].str()}};
    if (location) posToXML(st, as, st.positionOf(*a));
    doc.open("attr", as);
    toXML(st, doc, *a->value, strict, location, ctx, drvsSeen, st.positionOf(*a));
    doc.close();
  }
}

std::string fmtFloatXML(double d) {
  std::ostringstream os;
  os << d;
  return os.str();
}

void toXML(EvalState &st, XMLWriter &doc, Value &v, bool strict, bool location, NixStringContext &ctx,
           std::set<std::string> &drvsSeen, PosPtr pos) {
  if (strict) st.forceValue(v, pos);
  switch (v.type) {
  case VType::Int: doc.empty("int", {{"value", std::to_string(v.integer)}}); break;
  case VType::Bool: doc.empty("bool", {{"value", v.boolean ? "true" : "false"}}); break;
  case VType::String:
    st.copyContext(v, ctx);
    doc.empty("string", {{"value", str(v.sv())}});
    break;
  case VType::Path: doc.empty("path", {{"value", str(v.pathView())}}); break;
  case VType::Null: doc.empty("null"); break;
  case VType::Attrs:
    if (st.isDerivation(v)) {
      XMLWriter::Attrs as;
      std::string drvPath;
      if (const Attr *a = v.attrs->get(st.s.drvPath)) {
        if (strict) st.forceValue(*a->value, st.positionOf(*a));
        if (a->value->type == VType::String) as["drvPath"] = drvPath = str(a->value->sv());
      }
      if (const Attr *a = v.attrs->get(st.s.outPath)) {
        if (strict) st.forceValue(*a->value, st.positionOf(*a));
        if (a->value->type == VType::String) as["outPath"] = str(a->value->sv());
      }
      doc.open("derivation", as);
      if (!drvPath.empty() && drvsSeen.insert(drvPath).second)
        showAttrsXML(st, doc, v.attrs, strict, location, ctx, drvsSeen);
      else
        doc.empty("repeated");
      doc.close();
    } else {
      doc.open("attrs");
      showAttrsXML(st, doc, v.attrs, strict, location, ctx, drvsSeen);
      doc.close();
    }
    break;
  case VType::List:
    doc.open("list");
    for (size_t i = 0; i < v.listSize(); i++) toXML(st, doc, *v.list.elems[i], strict, location, ctx, drvsSeen, pos);
    doc.close();
    break;
  case VType::Lambda: {
    auto lam = cast<nd::LambdaOp>(v.thunk.op);
    XMLWriter::Attrs as;
    if (location) posToXML(st, as, nd::posOfOp(lam));
    doc.open("function", as);
    if (lam.getFormals()) {
      XMLWriter::Attrs pa;
      if (auto n = lam.getArgName()) pa["name"] = n->str();
      if (lam.getEllipsis()) pa["ellipsis"] = "1";
      doc.open("attrspat", pa);
      composite::MutableSeries<llvm::StringRef> names; // the formals' bytes are the attributes' own: windows on them are sorted
      ArrayAttr formals = *lam.getFormals();
      for (Attribute f : formals) names.append(cast<StringAttr>(f).getValue());
      composite::sortRows(names.data(), names.size(), [](llvm::StringRef a, llvm::StringRef b) {
        return composite::lessChars(composite::series(a.data(), uint32_t(a.size())), composite::series(b.data(), uint32_t(b.size())));
      });
      for (llvm::StringRef n : names) doc.empty("attr", {{"name", n.str()}});
      doc.close();
    } else {
      doc.empty("varpat", {{"name", lam.getArgName() ? lam.getArgName()->str() : ""}});
    }
    doc.close();
    break;
  }
  case VType::PrimOp: case VType::PrimOpApp: doc.empty("unevaluated"); break;
  case VType::Float: doc.empty("float", {{"value", fmtFloatXML(v.fpoint)}}); break;
  default: doc.empty("unevaluated"); break;
  }
}
} // namespace

void EvalState::printValueAsXML(std::ostream &out, Value &v, bool strict, bool location, NixStringContext &ctx) {
  out << "<?xml version='1.0' encoding='utf-8'?>\n";
  XMLWriter doc{out};
  doc.open("expr");
  std::set<std::string> drvsSeen;
  toXML(*this, doc, v, strict, location, ctx, drvsSeen, nullptr);
  doc.close();
}

//===----------------------------------------------------------------------===//
// TOML input
//===----------------------------------------------------------------------===//

namespace {
struct TomlNode {
  enum Kind { Table, Array, Leaf } kind = Table;
  std::map<std::string, std::shared_ptr<TomlNode>> table;
  composite::MutableSeries<std::shared_ptr<TomlNode>> array;
  Value *leaf = nullptr;
  bool defined = false;       // explicitly defined via [header]
  bool inlineTable = false;   // immutable
  bool arrayOfTables = false;
};

struct TomlParser {
  EvalState &st;
  std::string_view s;
  bool timestamps;
  size_t p = 0;
  int line = 1;

  [[noreturn]] void fail(const std::string &m) {
    throw EvalError("while parsing TOML: " + m + " (line " + std::to_string(line) + ")");
  }
  bool eof() { return p >= s.size(); }
  char peek(size_t o = 0) { return p + o < s.size() ? s[p + o] : '\0'; }
  void wsInline() {
    while (!eof() && (s[p] == ' ' || s[p] == '\t')) p++;
  }
  void comment() {
    if (peek() == '#') {
      while (!eof() && s[p] != '\n') {
        if ((unsigned char)s[p] < 0x20 && s[p] != '\t' && s[p] != '\r') fail("control character in comment");
        p++;
      }
    }
  }
  void newline() {
    if (peek() == '\r' && peek(1) == '\n') p += 2, line++;
    else if (peek() == '\n') p++, line++;
  }
  void wsAll() { // whitespace, newlines and comments (inside arrays)
    while (!eof()) {
      wsInline();
      comment();
      if (peek() == '\n' || (peek() == '\r' && peek(1) == '\n')) newline();
      else break;
    }
  }
  static bool isBare(char c) { return composite::isAsciiAlnum(c) || c == '_' || c == '-'; }

  static void utf8(std::string &out, uint32_t cp) {
    if (cp < 0x80) out += char(cp);
    else if (cp < 0x800) { out += char(0xC0 | (cp >> 6)); out += char(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += char(0xE0 | (cp >> 12)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
    else { out += char(0xF0 | (cp >> 18)); out += char(0x80 | ((cp >> 12) & 0x3F)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
  }

  std::string escape() {
    // at backslash
    p++;
    char e = peek();
    p++;
    std::string out;
    switch (e) {
    case 'b': return "\b";
    case 't': return "\t";
    case 'n': return "\n";
    case 'f': return "\f";
    case 'r': return "\r";
    case 'e': return "\x1b";
    case '"': return "\"";
    case '\\': return "\\";
    case 'u': case 'U': {
      int n = e == 'u' ? 4 : 8;
      uint32_t cp = 0;
      for (int i = 0; i < n; i++) {
        char c = peek();
        p++;
        cp <<= 4;
        if (c >= '0' && c <= '9') cp |= c - '0';
        else if (c >= 'a' && c <= 'f') cp |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') cp |= c - 'A' + 10;
        else fail("invalid unicode escape");
      }
      utf8(out, cp);
      return out;
    }
    default: fail(std::string("invalid escape sequence '\\") + e + "'");
    }
  }

  std::string basicString() {
    if (s.substr(p, 3) == "\"\"\"") {
      p += 3;
      if (peek() == '\n') { p++; line++; }
      else if (peek() == '\r' && peek(1) == '\n') { p += 2; line++; }
      std::string out;
      while (true) {
        if (eof()) fail("unterminated multi-line string");
        if (s.substr(p, 3) == "\"\"\"") {
          p += 3;
          // Up to two additional quotes belong to the content.
          int extra = 0;
          while (peek() == '"' && extra < 2) { out += '"'; p++; extra++; }
          return out;
        }
        char c = s[p];
        if (c == '\\') {
          // line ending backslash
          size_t q = p + 1;
          while (q < s.size() && (s[q] == ' ' || s[q] == '\t')) q++;
          if (q < s.size() && (s[q] == '\n' || s[q] == '\r')) {
            p = q;
            while (!eof() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) {
              if (s[p] == '\n') line++;
              p++;
            }
            continue;
          }
          out += escape();
          continue;
        }
        if (c == '\n') line++;
        out += c;
        p++;
      }
    }
    p++;
    std::string out;
    while (true) {
      if (eof() || peek() == '\n') fail("unterminated string");
      char c = s[p];
      if (c == '"') { p++; return out; }
      if (c == '\\') { out += escape(); continue; }
      out += c;
      p++;
    }
  }
  std::string literalString() {
    if (s.substr(p, 3) == "'''") {
      p += 3;
      if (peek() == '\n') { p++; line++; }
      else if (peek() == '\r' && peek(1) == '\n') { p += 2; line++; }
      std::string out;
      while (true) {
        if (eof()) fail("unterminated multi-line literal string");
        if (s.substr(p, 3) == "'''") {
          p += 3;
          int extra = 0;
          while (peek() == '\'' && extra < 2) { out += '\''; p++; extra++; }
          return out;
        }
        if (s[p] == '\n') line++;
        out += s[p++];
      }
    }
    p++;
    std::string out;
    while (true) {
      if (eof() || peek() == '\n') fail("unterminated literal string");
      if (peek() == '\'') { p++; return out; }
      out += s[p++];
    }
  }

  composite::MutableSeries<std::string> key() {
    composite::MutableSeries<std::string> parts;
    while (true) {
      wsInline();
      std::string k;
      if (peek() == '"') k = basicString();
      else if (peek() == '\'') k = literalString();
      else {
        size_t start = p;
        while (!eof() && isBare(s[p])) p++;
        if (p == start) fail("expected a key");
        k = std::string(s.substr(start, p - start));
      }
      if (k.find('\0') != std::string::npos) fail("key contains a NUL byte");
      parts.append(k);
      wsInline();
      if (peek() == '.') { p++; continue; }
      return parts;
    }
  }

  bool isDateAhead() {
    // YYYY-MM-DD or HH:MM:SS
    auto d = [&](size_t o) { return composite::isAsciiDigit(peek(o)); };
    if (d(0) && d(1) && d(2) && d(3) && peek(4) == '-' && d(5) && d(6) && peek(7) == '-') return true;
    if (d(0) && d(1) && peek(2) == ':' && d(3) && d(4) && peek(5) == ':') return true;
    return false;
  }

  std::string dateTime() {
    size_t start = p;
    auto take = [&](auto pred) { while (!eof() && pred(s[p])) p++; };
    take([](char c) { return composite::isAsciiDigit(c) || c == '-' || c == ':'; });
    std::string res(s.substr(start, p - start));
    // date-time separator
    if ((peek() == 'T' || peek() == 't' || (peek() == ' ' && composite::isAsciiDigit(peek(1)))) && res.find('-') != std::string::npos) {
      p++;
      res += 'T';
      size_t ts = p;
      take([](char c) { return composite::isAsciiDigit(c) || c == ':'; });
      res += std::string(s.substr(ts, p - ts));
    }
    if (peek() == '.') {
      p++;
      size_t fs = p;
      take([](char c) { return composite::isAsciiDigit(c); });
      std::string frac(s.substr(fs, p - fs));
      size_t padTo = frac.size() <= 3 ? 3 : frac.size() <= 6 ? 6 : 9;
      if (frac.size() > 9) frac = frac.substr(0, 9);
      while (frac.size() < padTo) frac += '0';
      res += "." + frac;
    }
    if (peek() == 'Z' || peek() == 'z') { p++; res += "Z"; }
    else if ((peek() == '+' || peek() == '-') && composite::isAsciiDigit(peek(1))) {
      size_t os = p;
      p++;
      take([](char c) { return composite::isAsciiDigit(c) || c == ':'; });
      res += std::string(s.substr(os, p - os));
    }
    return res;
  }

  Value *number() {
    size_t start = p;
    std::string tok;
    while (!eof() && (composite::isAsciiAlnum(s[p]) || s[p] == '_' || s[p] == '+' || s[p] == '-' || s[p] == '.'))
      tok += s[p++];
    if (tok.empty()) fail("expected a value");
    Value *v = st.allocValue();
    std::string t = tok;
    bool neg = false;
    std::string body = t;
    if (body[0] == '+' || body[0] == '-') { neg = body[0] == '-'; body = body.substr(1); }
    if (body == "inf") { st.mkFloat(*v, neg ? -INFINITY : INFINITY); return v; }
    if (body == "nan") { st.mkFloat(*v, NAN); return v; }
    auto strip = [&](std::string x) {
      std::string r;
      for (size_t i = 0; i < x.size(); i++) {
        if (x[i] == '_') {
          if (i == 0 || i + 1 >= x.size() || !composite::isAsciiAlnum(x[i - 1]) || !composite::isAsciiAlnum(x[i + 1]))
            fail("invalid underscore in number");
          continue;
        }
        r += x[i];
      }
      return r;
    };
    if (body.size() > 2 && body[0] == '0' && (body[1] == 'x' || body[1] == 'o' || body[1] == 'b')) {
      if (t[0] == '+' || t[0] == '-') fail("sign not allowed on non-decimal integer");
      int base = body[1] == 'x' ? 16 : body[1] == 'o' ? 8 : 2;
      std::string digits = strip(body.substr(2));
      composite::CharSeries cs = composite::chars(digits);
      composite::text::Reading r = base == 16 ? composite::facet<composite::text::Integer<16, false>>(cs)
                                 : base == 8  ? composite::facet<composite::text::Integer<8, false>>(cs)
                                              : composite::facet<composite::text::Integer<2, false>>(cs);
      if (r.consumed != digits.size()) fail("invalid integer");
      if (r.overflow || r.value > (uint64_t)INT64_MAX) fail("too large integer");
      st.mkInt(*v, (int64_t)r.value);
      return v;
    }
    std::string clean = strip(t);
    bool isFloat = clean.find_first_of(".eE") != std::string::npos;
    if (isFloat) {
      char *end;
      double d = strtod(clean.c_str(), &end);
      if (*end) fail("invalid float '" + tok + "'");
      st.mkFloat(*v, d);
      return v;
    }
    std::string digits = clean[0] == '+' || clean[0] == '-' ? clean.substr(1) : clean;
    if (digits.size() > 1 && digits[0] == '0') fail("leading zeros are not allowed");
    composite::text::Reading r = composite::facet<composite::text::Integer<10, true>>(composite::chars(clean));
    long long n = (long long)r.value;
    if (r.consumed != clean.size()) fail("invalid value '" + tok + "'");
    if (r.overflow) {
      if (clean[0] == '-')
        throw EvalError("while parsing TOML: [error] toml::parse_dec_integer: too small integer: current min digits = -2^63");
      throw EvalError("while parsing TOML: [error] toml::parse_dec_integer: too large integer: current max digits = 2^63");
    }
    (void)start;
    st.mkInt(*v, n);
    return v;
  }

  Value *value() {
    char c = peek();
    if (c == '"') {
      std::string sv = basicString();
      if (sv.find('\0') != std::string::npos) fail("string contains a NUL byte");
      Value *v = st.newString(sv);
      return v;
    }
    if (c == '\'') {
      Value *v = st.newString(literalString());
      return v;
    }
    if (s.substr(p, 4) == "true" && !isBare(peek(4))) { p += 4; return &st.vTrue; }
    if (s.substr(p, 5) == "false" && !isBare(peek(5))) { p += 5; return &st.vFalse; }
    if (c == '[') {
      p++;
      composite::MutableSeries<Value *> elems;
      while (true) {
        wsAll();
        if (peek() == ']') { p++; break; }
        elems.append(value());
        wsAll();
        if (peek() == ',') { p++; continue; }
        if (peek() == ']') { p++; break; }
        fail("expected ',' or ']' in array");
      }
      Value *v = st.allocValue();
      st.mkList(*v, elems);
      return v;
    }
    if (c == '{') {
      p++;
      auto node = std::make_shared<TomlNode>();
      wsInline();
      if (peek() == '}') { p++; return toValue(*node); }
      while (true) {
        auto k = key();
        wsInline();
        if (peek() != '=') fail("expected '=' in inline table");
        p++;
        wsInline();
        Value *v = value();
        setKey(*node, k, v);
        wsInline();
        if (peek() == ',') { p++; continue; }
        if (peek() == '}') { p++; break; }
        fail("expected ',' or '}' in inline table");
      }
      return toValue(*node);
    }
    if (isDateAhead()) {
      std::string dt = dateTime();
      if (!timestamps) throw EvalError("while parsing TOML: Dates and times are not supported");
      Value *v = st.allocValue();
      EvalState::BindingsBuilder bb(st);
      st.mkString(bb.alloc("_type"), "timestamp");
      st.mkString(bb.alloc("value"), dt);
      st.mkAttrs(*v, bb.finish());
      return v;
    }
    return number();
  }

  void setKey(TomlNode &tbl, const composite::MutableSeries<std::string> &k, Value *v) {
    TomlNode *cur = &tbl;
    for (size_t i = 0; i + 1 < k.size(); i++) {
      auto &n = cur->table[k[i]];
      if (!n) n = std::make_shared<TomlNode>();
      else if (n->kind != TomlNode::Table || n->inlineTable) fail("cannot redefine key '" + k[i] + "'");
      cur = n.get();
    }
    auto &leaf = cur->table[k.back()];
    if (leaf) fail("duplicate key '" + k.back() + "'");
    leaf = std::make_shared<TomlNode>();
    leaf->kind = TomlNode::Leaf;
    leaf->leaf = v;
  }

  Value *toValue(TomlNode &n) {
    if (n.kind == TomlNode::Leaf) return n.leaf;
    Value *v = st.allocValue();
    if (n.kind == TomlNode::Array) {
      st.mkList(*v, n.array |cp::α| [&](const auto &x) { return toValue(*x); });
      return v;
    }
    EvalState::BindingsBuilder bb(st);
    for (auto &[k, c] : n.table) bb.insert(k, toValue(*c));
    st.mkAttrs(*v, bb.finish());
    return v;
  }

  void parse(Value &out) {
    TomlNode root;
    TomlNode *cur = &root;
    while (true) {
      wsAll();
      if (eof()) break;
      if (peek() == '[') {
        bool aot = peek(1) == '[';
        p += aot ? 2 : 1;
        auto k = key();
        wsInline();
        if (aot) {
          if (peek() != ']' || peek(1) != ']') fail("expected ']]'");
          p += 2;
        } else {
          if (peek() != ']') fail("expected ']'");
          p++;
        }
        TomlNode *t = &root;
        for (size_t i = 0; i + 1 < k.size(); i++) {
          auto &n = t->table[k[i]];
          if (!n) n = std::make_shared<TomlNode>();
          if (n->kind == TomlNode::Array) t = n->array.back().get();
          else if (n->kind == TomlNode::Table && !n->inlineTable) t = n.get();
          else fail("cannot redefine key '" + k[i] + "'");
        }
        auto &last = t->table[k.back()];
        if (aot) {
          if (!last) { last = std::make_shared<TomlNode>(); last->kind = TomlNode::Array; last->arrayOfTables = true; }
          if (last->kind != TomlNode::Array || !last->arrayOfTables) fail("cannot redefine key '" + k.back() + "'");
          auto nt = std::make_shared<TomlNode>();
          last->array.append(nt);
          cur = nt.get();
        } else {
          if (!last) last = std::make_shared<TomlNode>();
          else if (last->kind != TomlNode::Table || last->defined) fail("table '" + k.back() + "' already defined");
          last->defined = true;
          cur = last.get();
        }
        wsInline();
        comment();
        if (!eof() && peek() != '\n' && peek() != '\r') fail("expected newline after table header");
        continue;
      }
      auto k = key();
      wsInline();
      if (peek() != '=') fail("expected '=' after key");
      p++;
      wsInline();
      Value *v = value();
      setKey(*cur, k, v);
      wsInline();
      comment();
      if (!eof() && peek() != '\n' && peek() != '\r') fail("expected newline after value");
    }
    out = *toValue(root);
  }
};
} // namespace

void parseTOML(EvalState &state, std::string_view toml, Value &v) {
  TomlParser P{state, toml, false};
  P.parse(v);
}

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

bool tomlTimestamps = false;

//===----------------------------------------------------------------------===//
// Flake references (parseFlakeRef / flakeRefToString)
//===----------------------------------------------------------------------===//

static std::string percentDecode(std::string_view s) {
  std::string r;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '%' && i + 2 < s.size() && composite::isDigitIn(s[i + 1], 16) && composite::isDigitIn(s[i + 2], 16)) {
      r += char(std::stoi(std::string(s.substr(i + 1, 2)), nullptr, 16));
      i += 2;
    } else r += s[i];
  }
  return r;
}

static std::string percentEncode(std::string_view s, const char *keep = "-._~/:@!$'()*+,;=") {
  std::string r;
  for (unsigned char c : s) {
    if (composite::isAsciiAlnum(char(c)) || c == 0 || std::string_view(keep).find(char(c)) != std::string_view::npos) r += char(c);
    else {
      const char buf[4] = {'%', "0123456789ABCDEF"[c >> 4], "0123456789ABCDEF"[c & 15], 0};
      r += buf;
    }
  }
  return r;
}

static std::map<std::string, std::string> parseQuery(std::string_view q) {
  std::map<std::string, std::string> m;
  size_t i = 0;
  while (i < q.size()) {
    size_t amp = q.find('&', i);
    if (amp == std::string_view::npos) amp = q.size();
    auto kv = q.substr(i, amp - i);
    auto eq = kv.find('=');
    if (eq != std::string_view::npos) m[percentDecode(kv.substr(0, eq))] = percentDecode(kv.substr(eq + 1));
    else if (!kv.empty()) m[percentDecode(kv)] = "";
    i = amp + 1;
  }
  return m;
}

static bool isHexRev(std::string_view s) {
  if (s.size() != 40) return false;
  for (char c : s)
    if (!composite::isDigitIn(c, 16)) return false;
  return true;
}

static void putFlakeAttr(EvalState &st, EvalState::BindingsBuilder &bb, const std::string &k, const std::string &v) {
  static const std::set<std::string> ints = {"revCount", "lastModified"};
  static const std::set<std::string> bools = {"submodules", "shallow", "allRefs", "exportIgnore", "lfs", "verifyCommit"};
  Value &x = bb.alloc(k);
  if (ints.count(k)) st.mkInt(x, (int64_t)composite::facet<composite::text::Integer<10, true>>(composite::chars(v)).value);
  else if (bools.count(k)) st.mkBool(x, v == "1" || v == "true");
  else st.mkString(x, v);
}

static void parseFlakeRef(EvalState &st, std::string_view ref, Value &v, PosPtr pos) {
  std::string s(ref);
  std::string query;
  if (auto q = s.find('?'); q != std::string::npos) {
    query = s.substr(q + 1);
    s = s.substr(0, q);
  }
  if (auto h = s.find('#'); h != std::string::npos) s = s.substr(0, h);
  auto params = parseQuery(query);
  EvalState::BindingsBuilder bb(st);
  auto colon = s.find(':');
  std::string scheme = colon == std::string::npos ? "" : s.substr(0, colon);
  if (scheme == "github" || scheme == "gitlab" || scheme == "sourcehut") {
    std::string rest = s.substr(colon + 1);
    composite::MutableSeries<std::string> parts;
    size_t i = 0;
    while (true) {
      size_t sl = rest.find('/', i);
      parts.append(percentDecode(rest.substr(i, sl == std::string::npos ? std::string::npos : sl - i)));
      if (sl == std::string::npos) break;
      i = sl + 1;
    }
    if (parts.size() < 2 || parts.size() > 3)
      throw EvalError("'" + std::string(ref) + "' is not a valid URL", pos);
    st.mkString(bb.alloc("type"), scheme);
    st.mkString(bb.alloc("owner"), parts[0]);
    st.mkString(bb.alloc("repo"), parts[1]);
    if (parts.size() == 3) {
      if (isHexRev(parts[2])) params["rev"] = parts[2];
      else params["ref"] = parts[2];
    }
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  } else if (scheme == "path" || (scheme.empty() && (s[0] == '/' || s[0] == '.'))) {
    st.mkString(bb.alloc("type"), "path");
    std::string p = scheme.empty() ? s : s.substr(colon + 1);
    if (!p.empty() && p[0] != '/') {
      char buf[PATH_MAX];
      p = nixfe::canonPath(std::string(getcwd(buf, sizeof buf) ? buf : "/") + "/" + p);
    }
    st.mkString(bb.alloc("path"), percentDecode(p));
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  } else if (scheme.rfind("git+", 0) == 0 || scheme.rfind("hg+", 0) == 0 || scheme.rfind("tarball+", 0) == 0 ||
             scheme.rfind("file+", 0) == 0) {
    auto plus = scheme.find('+');
    std::string type = scheme.substr(0, plus);
    st.mkString(bb.alloc("type"), type == "hg" ? "mercurial" : type);
    std::string url = s.substr(plus + 1);
    std::map<std::string, std::string> keep;
    for (auto &[k, val] : params) {
      static const std::set<std::string> attrs = {"ref", "rev", "dir", "narHash", "revCount", "lastModified",
                                                  "submodules", "shallow", "allRefs", "exportIgnore", "lfs"};
      if (attrs.count(k)) putFlakeAttr(st, bb, k, val);
      else keep[k] = val;
    }
    if (!keep.empty()) {
      url += "?";
      bool first = true;
      for (auto &[k, val] : keep) { url += (first ? "" : "&") + k + "=" + val; first = false; }
    }
    st.mkString(bb.alloc("url"), url);
  } else if (scheme == "http" || scheme == "https" || scheme == "file") {
    static const char *exts[] = {".zip", ".tar", ".tgz", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst"};
    bool tarball = false;
    for (auto *e : exts)
      if (s.size() >= strlen(e) && s.substr(s.size() - strlen(e)) == e) tarball = true;
    st.mkString(bb.alloc("type"), tarball ? "tarball" : "file");
    std::string url = s;
    if (!query.empty()) url += "?" + query;
    st.mkString(bb.alloc("url"), url);
  } else {
    // Indirect: [flake:]id[/ref-or-rev]
    std::string rest = scheme == "flake" ? s.substr(colon + 1) : s;
    auto sl = rest.find('/');
    st.mkString(bb.alloc("type"), "indirect");
    st.mkString(bb.alloc("id"), rest.substr(0, sl));
    if (sl != std::string::npos) {
      std::string r = rest.substr(sl + 1);
      if (isHexRev(r)) params["rev"] = r;
      else params["ref"] = r;
    }
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  }
  st.mkAttrs(v, bb.finish());
}

static void flakeRefToString(EvalState &st, Value &arg, Value &v, PosPtr pos) {
  st.forceAttrs(arg, pos, "while evaluating the argument passed to builtins.flakeRefToString");
  std::map<std::string, std::string> m;
  for (auto &a : *arg.attrs) {
    st.forceValue(*a.value, pos);
    std::string k = st.symbols[a.name].str();
    switch (a.value->type) {
    case VType::String: m[k] = std::string(a.value->sv()); break;
    case VType::Int:
      if (a.value->integer < 0)
        throw EvalError("negative value given for flake ref attr " + k + ": " + std::to_string(a.value->integer), pos);
      m[k] = std::to_string(a.value->integer);
      break;
    case VType::Bool: m[k] = a.value->boolean ? "1" : "0"; break;
    default:
      throw EvalError("flake reference attribute sets may only contain integers, Booleans, and strings, but attribute '" +
                          k + "' is " + EvalState::showType(*a.value),
                      pos);
    }
  }
  auto take = [&](const std::string &k) {
    auto it = m.find(k);
    if (it == m.end()) return std::string();
    std::string r = it->second;
    m.erase(it);
    return r;
  };
  std::string type = take("type");
  if (type.empty()) throw EvalError("attribute 'type' is missing in call to 'fetchTree'", pos);
  std::string res;
  if (type == "github" || type == "gitlab" || type == "sourcehut") {
    std::string owner = take("owner"), repo = take("repo"), rev = take("rev"), ref = take("ref");
    res = type + ":" + percentEncode(owner) + "/" + percentEncode(repo);
    if (!rev.empty()) res += "/" + rev;
    else if (!ref.empty()) res += "/" + percentEncode(ref);
  } else if (type == "path") {
    res = "path:" + percentEncode(take("path"));
  } else if (type == "git" || type == "mercurial" || type == "tarball" || type == "file") {
    std::string url = take("url");
    std::string prefix = type == "mercurial" ? "hg" : type;
    res = prefix + "+" + url;
  } else if (type == "indirect") {
    res = "flake:" + take("id");
    std::string rev = take("rev"), ref = take("ref");
    if (!ref.empty()) res += "/" + ref;
    if (!rev.empty()) res += "/" + rev;
  } else {
    throw EvalError("unsupported flake reference type '" + type + "'", pos);
  }
  if (!m.empty()) {
    res += "?";
    bool first = true;
    for (auto &[k, val] : m) {
      res += (first ? "" : "&") + percentEncode(k, "-._~") + "=" + percentEncode(val, "-._~/:");
      first = false;
    }
  }
  st.mkString(v, res);
}

void registerFormatBuiltins(EvalState &state) {
  auto &S = state;
  S.addPrimOp("__parseFlakeRef", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto s = st.forceStringNoCtx(*args[0], pos, "while evaluating the argument passed to builtins.parseFlakeRef");
    parseFlakeRef(st, s, v, pos);
  });
  S.addPrimOp("__flakeRefToString", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    flakeRefToString(st, *args[0], v, pos);
  });
  S.addPrimOp("__toJSON", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    std::ostringstream os;
    NixStringContext ctx;
    st.printValueAsJSON(os, *args[0], true, ctx, true, pos);
    st.mkString(v, os.str(), ctx);
  });
  S.addPrimOp("__fromJSON", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto s = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.fromJSON");
    try {
      parseJSON(st, s, v);
    } catch (EvalError &e) {
      if (!e.pos) e.pos = pos;
      throw;
    }
  });
  S.addPrimOp("__toXML", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    std::ostringstream os;
    NixStringContext ctx;
    st.printValueAsXML(os, *args[0], true, false, ctx);
    st.mkString(v, os.str(), ctx);
  });
  S.addPrimOp("fromTOML", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto s = st.forceString(*args[0], pos, "while evaluating the argument passed to builtins.fromTOML");
    TomlParser P{st, s, tomlTimestamps};
    try {
      P.parse(v);
    } catch (EvalError &e) {
      if (!e.pos) e.pos = pos;
      throw;
    }
  });
}

} // namespace nixev
