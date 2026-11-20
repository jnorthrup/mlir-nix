//===- Formats.cpp - JSON, XML and TOML conversions -----------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Confix.h"
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

//===----------------------------------------------------------------------===//
// JSON output
//===----------------------------------------------------------------------===//

// The scan is lowered/nixeval/FlakeRefOps.mlir's nixev_ts_utf8_bad (the bad byte's index, or -1); the wording stays here.
extern "C" int64_t nixev_ts_utf8_bad(const char *p, int64_t n);
static void checkUTF8(std::string_view s) {
  int64_t at = nixev_ts_utf8_bad(s.data(), int64_t(s.size()));
  if (at < 0) return;
  size_t bad = size_t(at);
  const char hex[] = "0123456789ABCDEF";
  unsigned char byte = (unsigned char)s[bad];
  throw EvalError(composite::cat("JSON serialization error: [json.exception.type_error.316] invalid UTF-8 byte at index ", bad, ": 0x",
                                 hex[byte >> 4], hex[byte & 15]));
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

// The byte emission of JSON (an integer's digits, a string's escaping) is hollowed into lowered/nixeval/PrintOps.mlir
// (trikeshed.fold / series / combine / combineAll / slice / drain), lowered by --trikeshed-lower-cursors and linked into
// NixEval.  Each entry drains into room reserved here and returns how many bytes it wrote; the count is adopted as
// appendAll adopts a copied run (the cells are plain chars, already written).
extern "C" {
size_t nixev_ts_int(int64_t x, char *into, size_t cap);
size_t nixev_ts_escape(const char *p, size_t n, char *into, size_t cap);
}

void JsonOut::putInt(int64_t x) {
  uint32_t off = bytes.size();
  bytes.reserve(size_t(off) + 21); // a sign and at most 19 digits
  bytes.n += uint32_t(nixev_ts_int(x, bytes.data() + off, 21));
}

void JsonOut::putString(std::string_view s) {
  uint32_t off = bytes.size();
  size_t room = 2 + 6 * s.size(); // two quotes and at most six bytes a byte (\u00xx)
  bytes.reserve(size_t(off) + room);
  bytes.n += uint32_t(nixev_ts_escape(s.data(), s.size(), bytes.data() + off, room));
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
/// The error of a scan that stopped (Composite/Confix.h), in the words of the reader that took JSON before the index did.
[[noreturn]] void jsonFault(const composite::confix::Scan &e, std::string_view json) {
  using composite::confix::Fault;
  if (e.fault == Fault::Unsigned)
    throw EvalError(composite::cat("unsigned json number ", json.substr(e.at, e.end - e.at), " outside of Nix integer range"));
  if (e.fault == Fault::Nul) {
    composite::Text decoded, shown;
    composite::confix::decode(json.data(), e.at, e.end - 1, decoded);
    for (char c : decoded) {
      if (c == '\0') shown += "\xe2\x90\x80"; // U+2400 SYMBOL FOR NULL, as UTF-8
      else shown += c;
    }
    throw EvalError(composite::cat("input string '", shown, "' cannot be represented as Nix string because it contains null bytes"));
  }
  throw EvalError(composite::cat("[json.exception.parse_error.101] parse error at line 1, column ", size_t(e.at) + 1,
                                 ": syntax error while parsing value - ", composite::confix::what(e.fault)));
}

/// The text of the String row from..to (its quotes): a window of the source when nothing in it is escaped, else decoded into `scratch`.
std::string_view stringOf(std::string_view json, uint32_t from, uint32_t to, composite::Text &scratch) {
  const char *body = json.data() + from + 1;
  if (!memchr(body, '\\', to - from - 1)) return std::string_view(body, to - from - 1);
  scratch.clear();
  composite::confix::decode(json.data(), from, to, scratch);
  return std::string_view(scratch.data(), scratch.size());
}

/// The values of an index, made now: a Value for each row, a container's filled from the Values of its children, which are made before it is
/// visited because the row of a child comes after the row of its parent.
void reifyJSON(EvalState &st, const composite::confix::Index &ix, std::string_view json, Value &root) {
  using composite::confix::Tag;
  const char *s = json.data();
  composite::MutableSeries<Value *> vals(ix.size());
  vals[0] = &root;
  composite::Text scratch;
  composite::MutableSeries<Value *> elems, members;
  composite::MutableSeries<composite::Text> keys;
  composite::MutableSeries<uint32_t> order;
  for (uint32_t i = 0; i < ix.size(); i++) {
    if (!vals[i]) continue; // a key: it is read when its object is made
    Value &v = *vals[i];
    uint32_t from = ix.open(i), to = ix.close(i);
    switch (ix.tag(i)) {
    case Tag::Nothing: st.mkNull(v); break;
    case Tag::Boolean: st.mkBool(v, s[from] == 't'); break;
    case Tag::Long: st.mkInt(v, composite::confix::readLong(s, from, to)); break;
    case Tag::Double: {
      composite::Text num(json.substr(from, to - from + 1)); // strtod wants the NUL after it
      st.mkFloat(v, strtod(num.c_str(), nullptr));
      break;
    }
    case Tag::String: st.mkString(v, stringOf(json, from, to, scratch)); break;
    case Tag::Array: {
      auto kids = ix.kidsOf(i);
      if (kids.size() == 0) { st.mkList(v, 0); break; }
      elems.clear();
      for (uint32_t k = 0; k < kids.size(); k++) {
        vals[kids[k]] = st.allocValue();
        elems.append(vals[kids[k]]);
      }
      st.mkList(v, elems);
      break;
    }
    case Tag::Object: {
      auto kids = ix.kidsOf(i);
      EvalState::BindingsBuilder bb(st);
      // The members in the order they came, sorted once below: an object of n members costs n log n whatever the order of its keys.
      keys.clear();
      members.clear();
      order.clear();
      for (uint32_t k = 0; k + 1 < kids.size(); k += 2) {
        keys.append(composite::Text(stringOf(json, ix.open(kids[k]), ix.close(kids[k]), scratch)));
        members.append(vals[kids[k + 1]] = st.allocValue());
        order.append(k / 2);
      }
      // In key order, as the sorted map they were in gave them; sortRows is stable, so of equal keys the last in the text is the last here: it wins.
      composite::sortRows(order.begin(), order.size(), [&](uint32_t a, uint32_t b) { return keys[a] < keys[b]; });
      for (uint32_t k = 0; k < order.size(); k++) {
        if (k + 1 < order.size() && keys[order[k]] == keys[order[k + 1]]) continue;
        bb.insert(keys[order[k]], members[order[k]]);
      }
      st.mkAttrs(v, bb.finish());
      break;
    }
    }
  }
}
} // namespace

void parseJSON(EvalState &state, std::string_view json, Value &v) {
  if (json.size() >= 0xFFFFFFFFull) throw EvalError("a JSON text of 4 GiB or more is not supported");
  composite::confix::Index ix;
  composite::confix::Scan e = composite::confix::scan(composite::chars(json.data(), uint32_t(json.size())), ix);
  if (e) jsonFault(e, json);
  reifyJSON(state, ix, json, v);
}

//===----------------------------------------------------------------------===//
// XML output
//===----------------------------------------------------------------------===//

namespace {
// The XML byte emission is hollowed into lowered/nixeval/XmlOps.mlir (trikeshed.series / slice / text / combine /
// combineAll / at / drain over a constant escape table), lowered by --trikeshed-lower-cursors and linked into NixEval.
// One entry writes a whole tag line into room reserved here and returns how many bytes it wrote; the attribute rows
// and the element stack stay here, as does the recursion/forcing of toXML below.
extern "C" size_t nixev_ts_xml_tag(int64_t kind, int64_t depth, const char *name, int64_t nn,
                                   const composite::Chars *keys, const composite::Chars *vals, int64_t nrows,
                                   char *into, size_t cap);

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
  /// One tag line: the rows sorted by name (as Nix's std::map wrote them), their keys and values as windows, the room
  /// the emission needs (2 a depth, 2 the prefix, the name, 4 the suffix, and 4 + key + 6 a value byte), drained into
  /// the Text's own buffer and adopted (resize before, truncate after, the PathOps way).  kind 0 open, 1 close, 2 empty.
  void tag(int64_t kind, size_t depth, std::string_view n, const Attrs &as) {
    composite::MutableSeries<const Attrs::Row *> sorted;
    for (const Attrs::Row &r : as.rows) sorted.append(&r);
    composite::sortRows(sorted.data(), sorted.size(), [](const Attrs::Row *a, const Attrs::Row *b) { return strcmp(a->k, b->k) < 0; });
    composite::MutableSeries<composite::Chars> keys, vals;
    size_t room = 2 * depth + 2 + n.size() + 4;
    for (const Attrs::Row *r : sorted) {
      size_t kn = strlen(r->k);
      keys.append(composite::chars(r->k, uint32_t(kn)));
      vals.append(r->v.chars());
      room += 4 + kn + 6 * size_t(r->v.size());
    }
    size_t at = out.size();
    out.resize(at + room);
    out.truncate(at + nixev_ts_xml_tag(kind, int64_t(depth), n.data(), int64_t(n.size()), keys.data(), vals.data(),
                                       int64_t(keys.size()), out.begin() + at, room));
  }
  void open(std::string_view n, const Attrs &as = {}) { tag(0, stack.size(), n, as); stack.append(composite::Text(n)); }
  void close() { tag(1, stack.size() - 1, stack.back(), {}); stack.pop(); }
  void empty(std::string_view n, const Attrs &as = {}) { tag(2, stack.size(), n, as); }
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

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

bool tomlTimestamps = false;

//===----------------------------------------------------------------------===//
// Flake references (parseFlakeRef / flakeRefToString)
//===----------------------------------------------------------------------===//

// The text algebra of both (percent-decoding and -encoding with their keep sets, the query's split and SortedMap order,
// isHexRev, putFlakeAttr's typing, the reference-type classification and the unparsed text) is
// lowered/nixeval/FlakeRefOps.mlir.  These bridges keep the forcing, the throws' wording, the values (BindingsBuilder,
// mkString/mkInt/mkBool) and canonPath against the working directory (a callback); the entries write into room sized here.
extern "C" {
int64_t nixev_ts_flake_parse(void *ctx, const char *p, int64_t n, char *out, int64_t cap, int64_t *recs);
int64_t nixev_ts_flake_unparse(const int64_t *ents, int64_t n, char *into, int64_t cap);
const char *nixev_flake_canon(composite::Text *t, const char *p, int64_t n, int64_t *len) {
  char buf[PATH_MAX];
  *t = nixfe::canonPath(composite::cat(getcwd(buf, sizeof buf) ? buf : "/", '/', std::string_view(p, size_t(n))));
  *len = int64_t(t->size());
  return t->begin();
}
}

// Records of 6 i64 (name offset, length, value offset, length, kind 0 string / 1 int / 2 bool, the int or bool) over
// the bytes in `out`; the entry asks for more room with -(need) - 2 and reports a bad github-like reference with -1.
static void parseFlakeRef(EvalState &st, std::string_view ref, Value &v, PosPtr pos) {
  composite::Text out, canon;
  composite::MutableSeries<int64_t> recs;
  recs.resize((ref.size() + 8) * 6);
  int64_t r, cap = 4 * int64_t(ref.size()) + 128;
  do {
    out.resize(size_t(cap));
    r = nixev_ts_flake_parse(&canon, ref.data(), int64_t(ref.size()), out.begin(), cap, recs.data());
    cap = -r - 2;
  } while (r < -1);
  if (r < 0) throw EvalError(composite::cat("'", ref, "' is not a valid URL"), pos);
  EvalState::BindingsBuilder bb(st);
  for (const int64_t *x = recs.data(), *end = x + 6 * r; x != end; x += 6) {
    Value &a = bb.alloc(std::string_view(out.begin() + x[0], size_t(x[1])));
    if (x[4] == 1) st.mkInt(a, x[5]);
    else if (x[4] == 2) st.mkBool(a, x[5] != 0);
    else st.mkString(a, std::string_view(out.begin() + x[2], size_t(x[3])));
  }
  st.mkAttrs(v, bb.finish());
}

// Entries of 5 i64 (key address, length, value address, length or the int/bool, kind 0 string / 1 int / 2 bool) in
// the set's order; `into`'s last 21 bytes per entry hold the ints' digits.
static void flakeRefToString(EvalState &st, Value &arg, Value &v, PosPtr pos) {
  st.forceAttrs(arg, pos, "while evaluating the argument passed to builtins.flakeRefToString");
  composite::MutableSeries<int64_t> ents;
  int64_t cap = 64;
  for (auto &a : *arg.attrs) {
    st.forceValue(*a.value, pos);
    std::string_view k = st.symbols[a.name]; // the symbol table's bytes: they never move
    Value &x = *a.value;
    if (x.type == VType::Int && x.integer < 0)
      throw EvalError(composite::cat("negative value given for flake ref attr ", k, ": ", x.integer), pos);
    if (x.type != VType::String && x.type != VType::Int && x.type != VType::Bool)
      throw EvalError(composite::cat("flake reference attribute sets may only contain integers, Booleans, and strings, but attribute '",
                                     k, "' is ", EvalState::showType(x)),
                      pos);
    std::string_view s = x.type == VType::String ? x.sv() : std::string_view();
    int64_t kind = x.type == VType::String ? 0 : x.type == VType::Int ? 1 : 2;
    int64_t row[5] = {(int64_t)k.data(), int64_t(k.size()), (int64_t)s.data(), kind == 0 ? int64_t(s.size()) : kind == 1 ? x.integer : int64_t(x.boolean), kind};
    for (int64_t w : row) ents.append(w);
    cap += 3 * int64_t(k.size() + s.size()) + 45;
  }
  composite::Text res;
  res.resize(size_t(cap));
  int64_t r = nixev_ts_flake_unparse(ents.data(), int64_t(ents.size() / 5), res.begin(), cap);
  if (r == -1) throw EvalError("attribute 'type' is missing in call to 'fetchTree'", pos);
  if (r < 0) throw EvalError(composite::cat("unsupported flake reference type '", res.substr(0, size_t(-r - 2)), "'"), pos);
  res.truncate(size_t(r));
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
