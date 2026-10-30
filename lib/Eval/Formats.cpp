//===- Formats.cpp - JSON, XML and TOML conversions -----------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Mutable.h"
#include "Nix/Eval.h"

#include "mlir/IR/BuiltinAttributes.h"

#include <cmath>
#include <cstring>
#include <unistd.h>
#include <climits>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

using A = Value **;
static composite::Text str(std::string_view s) { return composite::Text(s); }

/// Whether `k` is one of `names` (a fixed set of words, asked by count() before).
template <size_t N> static bool oneOf(std::string_view k, const char *const (&names)[N]) {
  for (const char *n : names)
    if (k == n) return true;
  return false;
}

/// Drops one row of a SortedMap (the store's has no erase): the rows after it move down a place, as SortedSet::erase moves its rows.
template <class V> static void eraseRow(nixstore::SortedMap<V> &m, typename nixstore::SortedMap<V>::Row *at) {
  for (typename nixstore::SortedMap<V>::Row *r = at; r + 1 != m.end(); ++r) nixstore::SortedMap<V>::swapRows(r[0], r[1]);
  m.rows.pop();
}

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
      throw EvalError(composite::cat("JSON serialization error: [json.exception.type_error.316] invalid UTF-8 byte at index ", bad, ": 0x",
                                     hex[byte >> 4], hex[byte & 15]));
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

void JsonOut::putInt(int64_t x) {
  char buf[24], *e = buf + sizeof buf, *p = e;
  uint64_t u = x < 0 ? 0 - uint64_t(x) : uint64_t(x); // INT64_MIN too
  do *--p = char('0' + u % 10); while (u /= 10);
  if (x < 0) *--p = '-';
  put(std::string_view(p, size_t(e - p)));
}

void JsonOut::putString(std::string_view s) {
  static const char hex[] = "0123456789abcdef";
  put('"');
  size_t run = 0; // the bytes since the last escape go in as one piece
  for (size_t i = 0; i < s.size(); i++) {
    unsigned char c = (unsigned char)s[i];
    if (c >= 0x20 && c != '"' && c != '\\') continue;
    put(s.substr(run, i - run));
    switch (c) {
    case '"': put("\\\""); break;
    case '\\': put("\\\\"); break;
    case '\b': put("\\b"); break;
    case '\f': put("\\f"); break;
    case '\n': put("\\n"); break;
    case '\r': put("\\r"); break;
    case '\t': put("\\t"); break;
    default: {
      char u[6] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
      put(std::string_view(u, 6));
    }
    }
    run = i + 1;
  }
  put(s.substr(run));
  put('"');
}

void EvalState::printValueAsJSON(JsonOut &out, Value &v, bool strict, NixStringContext &ctx, bool copyToStore,
                                 PosPtr pos) {
  CallDepth guard(*this, pos);
  if (strict) forceValue(v, pos);
  switch (v.type) {
  case VType::Int: out.putInt(v.integer); break;
  case VType::Bool: out.put(v.boolean ? "true" : "false"); break;
  case VType::String:
    copyContext(v, ctx);
    checkUTF8(v.sv());
    out.putString(v.sv());
    break;
  case VType::Path:
    if (copyToStore) out.putString(copyPathToStore(ctx, v.pathView()));
    else out.putString(v.pathView());
    break;
  case VType::Null: out.put("null"); break;
  case VType::Attrs: {
    if (auto s2 = tryAttrsToString(v, ctx, false, false)) {
      out.putString(*s2);
      break;
    }
    if (const Attr *o = v.attrs->get(s.outPath)) {
      printValueAsJSON(out, *o->value, strict, ctx, copyToStore, positionOf(*o));
      break;
    }
    out.put('{');
    bool first = true;
    for (const Attr *a : v.attrs->lexicographicOrder(symbols)) {
      if (!first) out.put(',');
      first = false;
      out.putString(symbols[a->name]);
      out.put(':');
      try {
        printValueAsJSON(out, *a->value, strict, ctx, copyToStore, positionOf(*a));
      } catch (EvalError &e) {
        e.addTrace(positionOf(*a), composite::cat("while evaluating attribute '", symbols[a->name], "'"));
        throw;
      }
    }
    out.put('}');
    break;
  }
  case VType::List:
    out.put('[');
    for (size_t i = 0; i < v.listSize(); i++) {
      if (i) out.put(',');
      if (callDepth <= 2) beginEpoch(); // MLNIX_STATS: an element of the top-level list is an epoch
      try {
        printValueAsJSON(out, *v.list.elems[i], strict, ctx, copyToStore, pos);
      } catch (EvalError &e) {
        e.addTrace(pos, composite::cat("while evaluating list element at index ", i));
        throw;
      }
    }
    out.put(']');
    break;
  case VType::Float: out.put(nixstore::jsonFloat(v.fpoint)); break;
  case VType::Thunk: case VType::App: case VType::AttrApp: case VType::Failed: case VType::Blackhole:
    out.put("null");
    break;
  default:
    throw EvalError(composite::cat("cannot convert ", showType(v), " to JSON"), pos);
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
  [[noreturn]] void fail(std::string_view what) {
    throw EvalError(composite::cat("[json.exception.parse_error.101] parse error at line 1, column ", p + 1,
                                   ": syntax error while parsing value - ", what));
  }
  void ws() {
    while (p < s.size() && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) p++;
  }
  static void utf8(composite::Text &out, uint32_t cp) {
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
  composite::Text string() {
    composite::Text r = stringRaw();
    if (r.find('\0') != composite::npos) {
      composite::Text shown;
      for (char c : r) {
        if (c == '\0') shown += "\u2400";
        else shown += c;
      }
      // U+2400 SYMBOL FOR NULL, as UTF-8.
      composite::Text out2;
      for (size_t i = 0; i < shown.size(); i++) {
        if (shown.substr(i, 6) == "\u2400") { out2 += "\xe2\x90\x80"; i += 5; }
        else out2 += shown[i];
      }
      throw EvalError(composite::cat("input string '", out2, "' cannot be represented as Nix string because it contains null bytes"));
    }
    return r;
  }
  composite::Text stringRaw() {
    p++; // "
    composite::Text out;
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
      // The members in the order they came, sorted once below: an object of n members costs n log n whatever the order of its keys.
      composite::MutableSeries<composite::Text> keys;
      composite::MutableSeries<Value *> vals;
      ws();
      if (p < s.size() && s[p] == '}') { p++; st.mkAttrs(v, bb.finish()); return; }
      while (true) {
        ws();
        if (p >= s.size() || s[p] != '"') fail("invalid literal; expected string literal");
        composite::Text k = string();
        ws();
        if (p >= s.size() || s[p] != ':') fail("syntax error; expected ':'");
        p++;
        Value *e = st.allocValue();
        value(*e);
        keys.append(composite::mv(k));
        vals.append(e);
        ws();
        if (p < s.size() && s[p] == ',') { p++; continue; }
        if (p < s.size() && s[p] == '}') { p++; break; }
        fail("syntax error; expected '}'");
      }
      // In key order, as the sorted map they were in gave them; sortRows is stable, so of equal keys the last in the text is the last here: it wins.
      composite::MutableSeries<uint32_t> order;
      for (uint32_t i = 0; i < keys.size(); i++) order.append(i);
      composite::sortRows(order.begin(), order.size(), [&](uint32_t a, uint32_t b) { return keys[a] < keys[b]; });
      for (uint32_t i = 0; i < order.size(); i++) {
        if (i + 1 < order.size() && keys[order[i]] == keys[order[i + 1]]) continue;
        bb.insert(keys[order[i]], vals[order[i]]);
      }
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
      composite::Text num(s.substr(start, p - start));
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
            throw EvalError(composite::cat("unsigned json number ", num, " outside of Nix integer range"));
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
  composite::Text &out;
  composite::MutableSeries<composite::Text> stack{};
  /// An element's attributes: a few rows, written in name order (as Nix's std::map wrote them); a name set again is replaced.
  struct Attrs {
    struct Row {
      const char *k;
      composite::Text v;
    };
    composite::MutableSeries<Row, composite::Spill<Row, 4>> rows;
    Attrs() = default;
    Attrs(const char *k, composite::Text v) { set(k, composite::mv(v)); }
    void set(const char *k, composite::Text v) {
      for (Row &r : rows)
        if (strcmp(r.k, k) == 0) {
          r.v = composite::mv(v);
          return;
        }
      rows.append(Row{k, composite::mv(v)});
    }
  };
  void indent(size_t depth) {
    for (size_t i = 0; i < depth * 2; i++) out.put(' ');
  }
  void put(std::string_view s) { out.put(s.data(), uint32_t(s.size())); }
  void attrs(const Attrs &as) {
    composite::MutableSeries<const Attrs::Row *> sorted;
    for (const Attrs::Row &r : as.rows) sorted.append(&r);
    composite::sortRows(sorted.data(), sorted.size(), [](const Attrs::Row *a, const Attrs::Row *b) { return strcmp(a->k, b->k) < 0; });
    for (const Attrs::Row *r : sorted) {
      out.put(' ').put(r->k).put("=\"");
      for (char c : r->v) {
        if (c == '"') out.put("&quot;");
        else if (c == '<') out.put("&lt;");
        else if (c == '>') out.put("&gt;");
        else if (c == '&') out.put("&amp;");
        else if (c == '\n') out.put("&#xA;");
        else out.put(c);
      }
      out.put('"');
    }
  }
  void open(std::string_view n, const Attrs &as = {}) {
    indent(stack.size());
    out.put('<');
    put(n);
    attrs(as);
    out.put(">\n");
    stack.append(composite::Text(n));
  }
  void close() {
    indent(stack.size() - 1);
    out.put("</");
    put(stack.back());
    out.put(">\n");
    stack.pop();
  }
  void empty(std::string_view n, const Attrs &as = {}) {
    indent(stack.size());
    out.put('<');
    put(n);
    attrs(as);
    out.put(" />\n");
  }
};

void posToXML(EvalState &st, XMLWriter::Attrs &as, PosPtr pos) {
  auto loc = nd::decodePos(pos);
  if (!loc) return;
  if (!loc->file.empty() && loc->file[0] == '/') as.set("path", composite::Text(loc->file));
  as.set("line", composite::str(loc->line));
  as.set("column", composite::str(loc->col));
}

void toXML(EvalState &st, XMLWriter &doc, Value &v, bool strict, bool location, NixStringContext &ctx, composite::TextSet &drvsSeen,
           PosPtr pos);

void showAttrsXML(EvalState &st, XMLWriter &doc, Bindings *attrs, bool strict, bool location, NixStringContext &ctx,
                  composite::TextSet &drvsSeen) {
  for (const Attr *a : attrs->lexicographicOrder(st.symbols)) {
    XMLWriter::Attrs as("name", composite::Text(st.symbols[a->name]));
    if (location) posToXML(st, as, st.positionOf(*a));
    doc.open("attr", as);
    toXML(st, doc, *a->value, strict, location, ctx, drvsSeen, st.positionOf(*a));
    doc.close();
  }
}

composite::Text fmtFloatXML(double d) {
  composite::Text t;
  nixfe::printFloat(t, d);
  return t;
}

void toXML(EvalState &st, XMLWriter &doc, Value &v, bool strict, bool location, NixStringContext &ctx, composite::TextSet &drvsSeen,
           PosPtr pos) {
  if (strict) st.forceValue(v, pos);
  switch (v.type) {
  case VType::Int: doc.empty("int", XMLWriter::Attrs("value", composite::str(v.integer))); break;
  case VType::Bool: doc.empty("bool", XMLWriter::Attrs("value", v.boolean ? "true" : "false")); break;
  case VType::String:
    st.copyContext(v, ctx);
    doc.empty("string", XMLWriter::Attrs("value", str(v.sv())));
    break;
  case VType::Path: doc.empty("path", XMLWriter::Attrs("value", str(v.pathView()))); break;
  case VType::Null: doc.empty("null"); break;
  case VType::Attrs:
    if (st.isDerivation(v)) {
      XMLWriter::Attrs as;
      composite::Text drvPath;
      if (const Attr *a = v.attrs->get(st.s.drvPath)) {
        if (strict) st.forceValue(*a->value, st.positionOf(*a));
        if (a->value->type == VType::String) {
          drvPath = str(a->value->sv());
          as.set("drvPath", drvPath.clone());
        }
      }
      if (const Attr *a = v.attrs->get(st.s.outPath)) {
        if (strict) st.forceValue(*a->value, st.positionOf(*a));
        if (a->value->type == VType::String) as.set("outPath", str(a->value->sv()));
      }
      doc.open("derivation", as);
      if (!drvPath.empty() && drvsSeen.insert(drvPath.data(), uint32_t(drvPath.size())))
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
    auto lam = cast<nd::LambdaOp>(v.thunk.node->def);
    XMLWriter::Attrs as;
    if (location) posToXML(st, as, nd::posOfOp(lam));
    doc.open("function", as);
    if (lam.getFormals()) {
      XMLWriter::Attrs pa;
      if (auto n = lam.getArgName()) pa.set("name", composite::Text(*n));
      if (lam.getEllipsis()) pa.set("ellipsis", "1");
      doc.open("attrspat", pa);
      composite::MutableSeries<llvm::StringRef> names; // the formals' bytes are the attributes' own: windows on them are sorted
      ArrayAttr formals = *lam.getFormals();
      for (Attribute f : formals) names.append(cast<StringAttr>(f).getValue());
      composite::sortRows(names.data(), names.size(), [](llvm::StringRef a, llvm::StringRef b) {
        return composite::lessChars(composite::series(a.data(), uint32_t(a.size())), composite::series(b.data(), uint32_t(b.size())));
      });
      for (llvm::StringRef n : names) doc.empty("attr", XMLWriter::Attrs("name", composite::Text(n)));
      doc.close();
    } else {
      doc.empty("varpat", XMLWriter::Attrs("name", composite::Text(lam.getArgName() ? *lam.getArgName() : llvm::StringRef(""))));
    }
    doc.close();
    break;
  }
  case VType::PrimOp: case VType::PrimOpApp: doc.empty("unevaluated"); break;
  case VType::Float: doc.empty("float", XMLWriter::Attrs("value", fmtFloatXML(v.fpoint))); break;
  default: doc.empty("unevaluated"); break;
  }
}
} // namespace

void EvalState::printValueAsXML(composite::Text &out, Value &v, bool strict, bool location, NixStringContext &ctx) {
  out.put("<?xml version='1.0' encoding='utf-8'?>\n");
  XMLWriter doc{out};
  doc.open("expr");
  composite::TextSet drvsSeen;
  toXML(*this, doc, v, strict, location, ctx, drvsSeen, nullptr);
  doc.close();
}

//===----------------------------------------------------------------------===//
// TOML input
//===----------------------------------------------------------------------===//

namespace {
struct TomlNode {
  enum Kind { Table, Array, Leaf } kind = Table;
  composite::TextTable<TomlNode *> table;     // by key, the keys' bytes in the parser's Bump; no order (the set is sorted when built)
  composite::MutableSeries<TomlNode *> array; // the nodes are the parser's
  Value *leaf = nullptr;
  bool defined = false;       // explicitly defined via [header]
  bool inlineTable = false;   // immutable
  bool arrayOfTables = false;
};

struct TomlParser {
  EvalState &st;
  std::string_view s;
  bool timestamps;
  composite::MutableSeries<composite::Own<TomlNode>> nodes; // every node of the parse, owned here
  composite::Bump keyBytes;                                  // every key of every table
  TomlNode *make() { return nodes[nodes.append(composite::own<TomlNode>())].get(); }
  /// The child of `t` named `k`, null when there is none yet: a reference to fill.  It holds until t's next new key.
  TomlNode *&child(TomlNode &t, std::string_view k) {
    return t.table.at(k.data(), uint32_t(k.size()), [&] { return keyBytes.copy(k.data(), uint32_t(k.size())); });
  }
  size_t p = 0;
  int line = 1;

  [[noreturn]] void fail(std::string_view m) {
    throw EvalError(composite::cat("while parsing TOML: ", m, " (line ", line, ")"));
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

  static void utf8(composite::Text &out, uint32_t cp) {
    if (cp < 0x80) out += char(cp);
    else if (cp < 0x800) { out += char(0xC0 | (cp >> 6)); out += char(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += char(0xE0 | (cp >> 12)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
    else { out += char(0xF0 | (cp >> 18)); out += char(0x80 | ((cp >> 12) & 0x3F)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
  }

  composite::Text escape() {
    // at backslash
    p++;
    char e = peek();
    p++;
    composite::Text out;
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
    default: fail(composite::cat("invalid escape sequence '\\", e, "'"));
    }
  }

  composite::Text basicString() {
    if (s.substr(p, 3) == "\"\"\"") {
      p += 3;
      if (peek() == '\n') { p++; line++; }
      else if (peek() == '\r' && peek(1) == '\n') { p += 2; line++; }
      composite::Text out;
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
    composite::Text out;
    while (true) {
      if (eof() || peek() == '\n') fail("unterminated string");
      char c = s[p];
      if (c == '"') { p++; return out; }
      if (c == '\\') { out += escape(); continue; }
      out += c;
      p++;
    }
  }
  composite::Text literalString() {
    if (s.substr(p, 3) == "'''") {
      p += 3;
      if (peek() == '\n') { p++; line++; }
      else if (peek() == '\r' && peek(1) == '\n') { p += 2; line++; }
      composite::Text out;
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
    composite::Text out;
    while (true) {
      if (eof() || peek() == '\n') fail("unterminated literal string");
      if (peek() == '\'') { p++; return out; }
      out += s[p++];
    }
  }

  composite::MutableSeries<composite::Text> key() {
    composite::MutableSeries<composite::Text> parts;
    while (true) {
      wsInline();
      composite::Text k;
      if (peek() == '"') k = basicString();
      else if (peek() == '\'') k = literalString();
      else {
        size_t start = p;
        while (!eof() && isBare(s[p])) p++;
        if (p == start) fail("expected a key");
        k = composite::Text(s.substr(start, p - start));
      }
      if (k.find('\0') != composite::npos) fail("key contains a NUL byte");
      parts.append(composite::mv(k));
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

  composite::Text dateTime() {
    size_t start = p;
    auto take = [&](auto pred) { while (!eof() && pred(s[p])) p++; };
    take([](char c) { return composite::isAsciiDigit(c) || c == '-' || c == ':'; });
    composite::Text res(s.substr(start, p - start));
    // date-time separator
    if ((peek() == 'T' || peek() == 't' || (peek() == ' ' && composite::isAsciiDigit(peek(1)))) && res.find('-') != composite::npos) {
      p++;
      res += 'T';
      size_t ts = p;
      take([](char c) { return composite::isAsciiDigit(c) || c == ':'; });
      res += s.substr(ts, p - ts);
    }
    if (peek() == '.') {
      p++;
      size_t fs = p;
      take([](char c) { return composite::isAsciiDigit(c); });
      composite::Text frac(s.substr(fs, p - fs));
      size_t padTo = frac.size() <= 3 ? 3 : frac.size() <= 6 ? 6 : 9;
      if (frac.size() > 9) frac.truncate(9);
      while (frac.size() < padTo) frac += '0';
      res += '.';
      res += frac;
    }
    if (peek() == 'Z' || peek() == 'z') { p++; res += "Z"; }
    else if ((peek() == '+' || peek() == '-') && composite::isAsciiDigit(peek(1))) {
      size_t os = p;
      p++;
      take([](char c) { return composite::isAsciiDigit(c) || c == ':'; });
      res += s.substr(os, p - os);
    }
    return res;
  }

  Value *number() {
    size_t start = p;
    composite::Text tok;
    while (!eof() && (composite::isAsciiAlnum(s[p]) || s[p] == '_' || s[p] == '+' || s[p] == '-' || s[p] == '.'))
      tok += s[p++];
    if (tok.empty()) fail("expected a value");
    Value *v = st.allocValue();
    std::string_view t = tok; // windows on tok, which is not written to again
    bool neg = false;
    std::string_view body = t;
    if (body[0] == '+' || body[0] == '-') { neg = body[0] == '-'; body = body.substr(1); }
    if (body == "inf") { st.mkFloat(*v, neg ? -INFINITY : INFINITY); return v; }
    if (body == "nan") { st.mkFloat(*v, NAN); return v; }
    auto strip = [&](std::string_view x) {
      composite::Text r;
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
      composite::Text digits = strip(body.substr(2));
      composite::CharSeries cs = composite::chars(digits);
      composite::text::Reading r = base == 16 ? composite::facet<composite::text::Integer<16, false>>(cs)
                                 : base == 8  ? composite::facet<composite::text::Integer<8, false>>(cs)
                                              : composite::facet<composite::text::Integer<2, false>>(cs);
      if (r.consumed != digits.size()) fail("invalid integer");
      if (r.overflow || r.value > (uint64_t)INT64_MAX) fail("too large integer");
      st.mkInt(*v, (int64_t)r.value);
      return v;
    }
    composite::Text clean = strip(t);
    bool isFloat = clean.find_first_of(".eE") != composite::npos;
    if (isFloat) {
      char *end;
      double d = strtod(clean.c_str(), &end);
      if (*end) fail(composite::cat("invalid float '", tok, "'"));
      st.mkFloat(*v, d);
      return v;
    }
    std::string_view digits = clean[0] == '+' || clean[0] == '-' ? std::string_view(clean).substr(1) : std::string_view(clean);
    if (digits.size() > 1 && digits[0] == '0') fail("leading zeros are not allowed");
    composite::text::Reading r = composite::facet<composite::text::Integer<10, true>>(composite::chars(clean));
    long long n = (long long)r.value;
    if (r.consumed != clean.size()) fail(composite::cat("invalid value '", tok, "'"));
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
      composite::Text sv = basicString();
      if (sv.find('\0') != composite::npos) fail("string contains a NUL byte");
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
      TomlNode *node = make();
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
      composite::Text dt = dateTime();
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

  void setKey(TomlNode &tbl, const composite::MutableSeries<composite::Text> &k, Value *v) {
    TomlNode *cur = &tbl;
    for (size_t i = 0; i + 1 < k.size(); i++) {
      TomlNode *&n = child(*cur, k[i]);
      if (!n) n = make();
      else if (n->kind != TomlNode::Table || n->inlineTable) fail(composite::cat("cannot redefine key '", k[i], "'"));
      cur = n;
    }
    TomlNode *&leaf = child(*cur, k.back());
    if (leaf) fail(composite::cat("duplicate key '", k.back(), "'"));
    leaf = make();
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
    for (auto &r : n.table) bb.insert(llvm::StringRef(r.p, r.n), toValue(*r.v));
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
          TomlNode *&n = child(*t, k[i]);
          if (!n) n = make();
          if (n->kind == TomlNode::Array) t = n->array.back();
          else if (n->kind == TomlNode::Table && !n->inlineTable) t = n;
          else fail(composite::cat("cannot redefine key '", k[i], "'"));
        }
        TomlNode *&last = child(*t, k.back());
        if (aot) {
          if (!last) { last = make(); last->kind = TomlNode::Array; last->arrayOfTables = true; }
          if (last->kind != TomlNode::Array || !last->arrayOfTables) fail(composite::cat("cannot redefine key '", k.back(), "'"));
          TomlNode *nt = make();
          last->array.append(nt);
          cur = nt;
        } else {
          if (!last) last = make();
          else if (last->kind != TomlNode::Table || last->defined) fail(composite::cat("table '", k.back(), "' already defined"));
          last->defined = true;
          cur = last;
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

static composite::Text percentDecode(std::string_view s) {
  composite::Text r;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '%' && i + 2 < s.size() && composite::isDigitIn(s[i + 1], 16) && composite::isDigitIn(s[i + 2], 16)) {
      r += char(composite::facet<composite::text::Integer<16, false>>(composite::chars(s.data() + i + 1, 2)).value);
      i += 2;
    } else r += s[i];
  }
  return r;
}

static composite::Text percentEncode(std::string_view s, const char *keep = "-._~/:@!$'()*+,;=") {
  composite::Text r;
  for (unsigned char c : s) {
    if (composite::isAsciiAlnum(char(c)) || c == 0 || std::string_view(keep).find(char(c)) != std::string_view::npos) r += char(c);
    else {
      const char buf[4] = {'%', "0123456789ABCDEF"[c >> 4], "0123456789ABCDEF"[c & 15], 0};
      r += buf;
    }
  }
  return r;
}

static nixstore::SortedMap<composite::Text> parseQuery(std::string_view q) {
  nixstore::SortedMap<composite::Text> m;
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

static void putFlakeAttr(EvalState &st, EvalState::BindingsBuilder &bb, std::string_view k, std::string_view v) {
  static const char *const ints[] = {"revCount", "lastModified"};
  static const char *const bools[] = {"submodules", "shallow", "allRefs", "exportIgnore", "lfs", "verifyCommit"};
  Value &x = bb.alloc(k);
  if (oneOf(k, ints)) st.mkInt(x, (int64_t)composite::facet<composite::text::Integer<10, true>>(composite::chars(v)).value);
  else if (oneOf(k, bools)) st.mkBool(x, v == "1" || v == "true");
  else st.mkString(x, v);
}

static void parseFlakeRef(EvalState &st, std::string_view ref, Value &v, PosPtr pos) {
  composite::Text s(ref);
  composite::Text query;
  if (auto q = s.find('?'); q != composite::npos) {
    query.put(s.substr(q + 1));
    s.truncate(q);
  }
  if (auto h = s.find('#'); h != composite::npos) s.truncate(h);
  auto params = parseQuery(query);
  EvalState::BindingsBuilder bb(st);
  auto colon = s.find(':');
  composite::Text scheme;
  if (colon != composite::npos) scheme.put(s.substr(0, colon));
  if (scheme == "github" || scheme == "gitlab" || scheme == "sourcehut") {
    composite::Text rest(s.substr(colon + 1));
    composite::MutableSeries<composite::Text> parts;
    size_t i = 0;
    while (true) {
      size_t sl = rest.find('/', i);
      parts.append(percentDecode(rest.substr(i, sl == composite::npos ? composite::npos : sl - i)));
      if (sl == composite::npos) break;
      i = sl + 1;
    }
    if (parts.size() < 2 || parts.size() > 3)
      throw EvalError(composite::cat("'", ref, "' is not a valid URL"), pos);
    st.mkString(bb.alloc("type"), scheme);
    st.mkString(bb.alloc("owner"), parts[0]);
    st.mkString(bb.alloc("repo"), parts[1]);
    if (parts.size() == 3) {
      if (isHexRev(parts[2])) params["rev"] = parts[2].clone();
      else params["ref"] = parts[2].clone();
    }
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  } else if (scheme == "path" || (scheme.empty() && !s.empty() && (s[0] == '/' || s[0] == '.'))) {
    st.mkString(bb.alloc("type"), "path");
    composite::Text p(scheme.empty() ? s.chars() : s.substr(colon + 1));
    if (!p.empty() && p[0] != '/') {
      char buf[PATH_MAX];
      p = nixfe::canonPath(composite::cat(getcwd(buf, sizeof buf) ? buf : "/", '/', p));
    }
    st.mkString(bb.alloc("path"), percentDecode(p));
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  } else if (scheme.rfind("git+", 0) == 0 || scheme.rfind("hg+", 0) == 0 || scheme.rfind("tarball+", 0) == 0 ||
             scheme.rfind("file+", 0) == 0) {
    auto plus = scheme.find('+');
    composite::Text type(scheme.substr(0, plus));
    st.mkString(bb.alloc("type"), type == "hg" ? std::string_view("mercurial") : std::string_view(type));
    composite::Text url(s.substr(plus + 1));
    nixstore::SortedMap<composite::Text> keep;
    for (auto &[k, val] : params) {
      static const char *const attrs[] = {"ref", "rev", "dir", "narHash", "revCount", "lastModified",
                                          "submodules", "shallow", "allRefs", "exportIgnore", "lfs"};
      if (oneOf(k, attrs)) putFlakeAttr(st, bb, k, val);
      else keep[k] = val.clone();
    }
    if (!keep.empty()) {
      url += "?";
      bool first = true;
      for (auto &[k, val] : keep) { url.put(first ? "" : "&").put(k).put('=').put(val); first = false; }
    }
    st.mkString(bb.alloc("url"), url);
  } else if (scheme == "http" || scheme == "https" || scheme == "file") {
    static const char *exts[] = {".zip", ".tar", ".tgz", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst"};
    bool tarball = false;
    for (auto *e : exts)
      if (s.size() >= strlen(e) && s.substr(s.size() - strlen(e)) == e) tarball = true;
    st.mkString(bb.alloc("type"), tarball ? "tarball" : "file");
    composite::Text url = s.clone();
    if (!query.empty()) url.put('?').put(query);
    st.mkString(bb.alloc("url"), url);
  } else {
    // Indirect: [flake:]id[/ref-or-rev]
    composite::Text rest(scheme == "flake" ? s.substr(colon + 1) : s.chars());
    auto sl = rest.find('/');
    st.mkString(bb.alloc("type"), "indirect");
    st.mkString(bb.alloc("id"), rest.substr(0, sl));
    if (sl != composite::npos) {
      composite::Text r(rest.substr(sl + 1));
      if (isHexRev(r)) params["rev"] = composite::mv(r);
      else params["ref"] = composite::mv(r);
    }
    for (auto &[k, val] : params) putFlakeAttr(st, bb, k, val);
  }
  st.mkAttrs(v, bb.finish());
}

static void flakeRefToString(EvalState &st, Value &arg, Value &v, PosPtr pos) {
  st.forceAttrs(arg, pos, "while evaluating the argument passed to builtins.flakeRefToString");
  nixstore::SortedMap<composite::Text> m;
  for (auto &a : *arg.attrs) {
    st.forceValue(*a.value, pos);
    std::string_view k = st.symbols[a.name]; // the symbol table's bytes: they never move
    switch (a.value->type) {
    case VType::String: m[k] = composite::Text(a.value->sv()); break;
    case VType::Int:
      if (a.value->integer < 0)
        throw EvalError(composite::cat("negative value given for flake ref attr ", k, ": ", a.value->integer), pos);
      m[k] = composite::str(a.value->integer);
      break;
    case VType::Bool: m[k] = composite::Text(a.value->boolean ? "1" : "0"); break;
    default:
      throw EvalError(composite::cat("flake reference attribute sets may only contain integers, Booleans, and strings, but attribute '",
                                     k, "' is ", EvalState::showType(*a.value)),
                      pos);
    }
  }
  auto take = [&](std::string_view k) {
    auto it = m.find(k);
    if (it == m.end()) return composite::Text();
    composite::Text r = composite::mv(it->second);
    eraseRow(m, it);
    return r;
  };
  composite::Text type = take("type");
  if (type.empty()) throw EvalError("attribute 'type' is missing in call to 'fetchTree'", pos);
  composite::Text res;
  if (type == "github" || type == "gitlab" || type == "sourcehut") {
    composite::Text owner = take("owner"), repo = take("repo"), rev = take("rev"), ref = take("ref");
    res = composite::cat(type, ':', percentEncode(owner), '/', percentEncode(repo));
    if (!rev.empty()) res.put('/').put(rev);
    else if (!ref.empty()) res.put('/').put(percentEncode(ref));
  } else if (type == "path") {
    res = composite::cat("path:", percentEncode(take("path")));
  } else if (type == "git" || type == "mercurial" || type == "tarball" || type == "file") {
    composite::Text url = take("url");
    std::string_view prefix = type == "mercurial" ? std::string_view("hg") : std::string_view(type);
    res = composite::cat(prefix, '+', url);
  } else if (type == "indirect") {
    res = composite::cat("flake:", take("id"));
    composite::Text rev = take("rev"), ref = take("ref");
    if (!ref.empty()) res.put('/').put(ref);
    if (!rev.empty()) res.put('/').put(rev);
  } else {
    throw EvalError(composite::cat("unsupported flake reference type '", type, "'"), pos);
  }
  if (!m.empty()) {
    res += "?";
    bool first = true;
    for (auto &[k, val] : m) {
      res.put(first ? "" : "&").put(percentEncode(k, "-._~")).put('=').put(percentEncode(val, "-._~/:"));
      first = false;
    }
  }
  st.mkString(v, res);
}

void registerFormatBuiltins(EvalState &state) {
  auto &S = state;
  S.addPrimOp("__parseFlakeRef", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto s = st.forceStringNoCtx(*args[0], pos, "while evaluating the argument passed to builtins.parseFlakeRef");
    parseFlakeRef(st, s, v, pos);
  });
  S.addPrimOp("__flakeRefToString", [](EvalState &st, A args, Value &v, PosPtr pos) {
    flakeRefToString(st, *args[0], v, pos);
  });
  S.addPrimOp("__toJSON", [](EvalState &st, A args, Value &v, PosPtr pos) {
    JsonOut os;
    NixStringContext ctx;
    st.printValueAsJSON(os, *args[0], true, ctx, true, pos);
    st.mkString(v, os.view(), ctx);
  });
  S.addPrimOp("__fromJSON", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto s = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.fromJSON");
    try {
      parseJSON(st, s, v);
    } catch (EvalError &e) {
      if (!e.pos) e.pos = pos;
      throw;
    }
  });
  S.addPrimOp("__toXML", [](EvalState &st, A args, Value &v, PosPtr pos) {
    composite::Text xml;
    NixStringContext ctx;
    st.printValueAsXML(xml, *args[0], true, false, ctx);
    st.mkString(v, std::string_view(xml.data(), xml.size()), ctx);
  });
  S.addPrimOp("fromTOML", [](EvalState &st, A args, Value &v, PosPtr pos) {
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
