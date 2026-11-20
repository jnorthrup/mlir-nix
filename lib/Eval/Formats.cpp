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

// The scan of the document (whitespace, comments, keys, headers, strings and escapes, numbers, dates, the array and
// inline-table nesting, the syntax errors) is lowered/nixeval/TomlScan.mlir, and so is every message's text.  It hands
// its events here in order, and the tables (dotted keys, headers, array-of-tables, duplicates, redefinitions) are built
// and checked here, so an error found here still comes before a lexical error later in the text.
extern "C" int32_t nixev_ts_toml_scan(int64_t *rec);
extern "C" int64_t nixev_ts_toml_msg(int64_t code, int64_t line, const char *w, int64_t wn, char *into, int64_t cap);
namespace {
[[noreturn]] void tomlFail(int64_t code, int64_t line, std::string_view w) {
  composite::Text m;
  m.resize(200 + w.size());
  m.truncate(size_t(nixev_ts_toml_msg(code, line, w.data(), int64_t(w.size()), m.begin(), int64_t(m.size()))));
  throw EvalError(composite::mv(m));
}

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
  bool timestamps;
  composite::MutableSeries<composite::Own<TomlNode>> nodes; // every node of the parse, owned here
  composite::Bump keyBytes;                                  // every key of every table
  TomlNode root;
  int64_t line = 1;                                          // the line of the scan's latest event
  struct Frame { TomlNode *node; uint32_t elems, keys; };    // an open array (node null) or table; frames[0] the current [table]
  composite::MutableSeries<Frame> frames;
  composite::MutableSeries<Value *> elems;                   // the open arrays' elements
  composite::MutableSeries<std::string_view> keys;           // the open keys' parts (windows on the input or the scan's bytes)
  TomlNode *make() { return nodes[nodes.append(composite::own<TomlNode>())].get(); }
  /// The child of `t` named `k`, null when there is none yet: a reference to fill.  It holds until t's next new key.
  TomlNode *&child(TomlNode &t, std::string_view k) {
    return t.table.at(k.data(), uint32_t(k.size()), [&] { return keyBytes.copy(k.data(), uint32_t(k.size())); });
  }
  [[noreturn]] void fail(int64_t code, std::string_view k) { tomlFail(code, line, k); }

  void setKey(TomlNode &tbl, uint32_t from, Value *v) {
    TomlNode *cur = &tbl;
    for (uint32_t i = from; i + 1 < keys.size(); i++) {
      TomlNode *&n = child(*cur, keys[i]);
      if (!n) n = make();
      else if (n->kind != TomlNode::Table || n->inlineTable) fail(29, keys[i]);
      cur = n;
    }
    TomlNode *&leaf = child(*cur, keys.back());
    if (leaf) fail(30, keys.back());
    leaf = make();
    leaf->kind = TomlNode::Leaf;
    leaf->leaf = v;
  }

  void header(bool aot) {
    TomlNode *t = &root;
    for (uint32_t i = 0; i + 1 < keys.size(); i++) {
      TomlNode *&n = child(*t, keys[i]);
      if (!n) n = make();
      if (n->kind == TomlNode::Array) t = n->array.back();
      else if (n->kind == TomlNode::Table && !n->inlineTable) t = n;
      else fail(29, keys[i]);
    }
    TomlNode *&last = child(*t, keys.back());
    if (aot) {
      if (!last) { last = make(); last->kind = TomlNode::Array; last->arrayOfTables = true; }
      if (last->kind != TomlNode::Array || !last->arrayOfTables) fail(29, keys.back());
      TomlNode *nt = make();
      last->array.append(nt);
      frames[0].node = nt;
    } else {
      if (!last) last = make();
      else if (last->kind != TomlNode::Table || last->defined) fail(31, keys.back());
      last->defined = true;
      frames[0].node = last;
    }
    keys.clear();
  }

  /// A complete value: an element of the open array, or the value of the open table's key.
  void deliver(Value *v) {
    Frame &f = frames.back();
    if (!f.node) { elems.append(v); return; }
    setKey(*f.node, f.keys, v);
    while (keys.size() > f.keys) keys.pop();
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

  void parse(std::string_view s, Value &out) {
    frames.append({&root, 0, 0});
    composite::MutableSeries<uint8_t> stack(s.size() + 1);
    composite::MutableSeries<char> dec(2 * s.size() + 16);
    int64_t rec[16] = {int64_t(s.data()), int64_t(s.size()), int64_t(this), int64_t(stack.data()), int64_t(dec.data()), 0, 1};
    if (int32_t code = nixev_ts_toml_scan(rec)) tomlFail(code, rec[6], std::string_view((const char *)rec[9], size_t(rec[10])));
    out = *toValue(root);
  }
};
} // namespace

/// The scan's events (TomlScan.mlir's header lists them): the values made here, in order.
extern "C" void nixev_toml_ev(void *c, int64_t kind, const char *p, int64_t a, int64_t line) {
  TomlParser &P = *static_cast<TomlParser *>(c);
  EvalState &st = P.st;
  P.line = line;
  Value *v;
  switch (kind) {
  case 0: P.keys.append(std::string_view(p, size_t(a))); return;
  case 1: v = st.newString(std::string_view(p, size_t(a))); break;
  case 2: st.mkInt(*(v = st.allocValue()), a); break;
  case 3: st.mkFloat(*(v = st.allocValue()), __builtin_bit_cast(double, a)); break;
  case 4: v = a ? &st.vTrue : &st.vFalse; break;
  case 5: {
    if (!P.timestamps) tomlFail(32, 0, {});
    v = st.allocValue();
    EvalState::BindingsBuilder bb(st);
    st.mkString(bb.alloc("_type"), "timestamp");
    st.mkString(bb.alloc("value"), std::string_view(p, size_t(a)));
    st.mkAttrs(*v, bb.finish());
    break;
  }
  case 6: P.frames.append({nullptr, P.elems.size(), P.keys.size()}); return;
  case 7: {
    uint32_t from = P.frames.back().elems, n = P.elems.size() - from;
    st.mkList(*(v = st.allocValue()), size_t(n));
    for (uint32_t i = 0; i < n; i++) v->list.elems[i] = P.elems[from + i];
    while (P.elems.size() > from) P.elems.pop();
    P.frames.pop();
    break;
  }
  case 8: P.frames.append({P.make(), P.elems.size(), P.keys.size()}); return;
  case 9: v = P.toValue(*P.frames.back().node); P.frames.pop(); break;
  default: return P.header(a != 0);
  }
  P.deliver(v);
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
    TomlParser P{st, tomlTimestamps};
    try {
      P.parse(s, v);
    } catch (EvalError &e) {
      if (!e.pos) e.pos = pos;
      throw;
    }
  });
}

} // namespace nixev
