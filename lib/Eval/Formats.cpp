//===- Formats.cpp - JSON, XML and TOML conversions -----------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Mutable.h"
#include "Nix/Eval.h"

#include "mlir/IR/BuiltinAttributes.h"

#include <math.h>
#include <unistd.h>
#include <limits.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

using A = Value **;

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

// builtins.fromJSON's reader is hollowed into lowered/nixeval/JsonRead.mlir (the confix dialect's confix.checked: the scan
// into the rows of an index, checked as the reader before checked, the open containers a stack in the record; then the
// strings decoded, the numbers read and a Value made for each row, an object's members in key order by trikeshed.sorted).
// Here: the arena (allocValue, mkString, the BindingsBuilder); the words.  The record and its arrays are nixstore::JsonRec (Store.h).
using nixstore::JsonRec;
extern "C" {
int32_t nixev_json_read(JsonRec *r, EvalState *st, Value *root);
uint64_t nixev_json_decode(const char *s, uint64_t from, uint64_t to, char *into, int64_t shown);
const char *nixev_json_what(int64_t fault, uint64_t *len);
Value *nixev_json_value(EvalState *st) { return st->allocValue(); }
void nixev_json_string(EvalState *st, Value *v, const char *p, uint64_t n) { st->mkString(*v, std::string_view(p, n)); }
void nixev_json_attrs(EvalState *st, Value *v, const composite::Chars *keys, Value **vals, uint64_t n) {
  EvalState::BindingsBuilder bb(*st);
  for (uint64_t k = 0; k < n; k++) bb.insert(llvm::StringRef(keys[k].data(), keys[k].size()), vals[k]);
  st->mkAttrs(*v, bb.finish());
}
}

void parseJSON(EvalState &state, std::string_view json, Value &v) {
  if (json.size() >= 0xFFFFFFFFull) throw EvalError("a JSON text of 4 GiB or more is not supported");
  JsonRec r;
  r.w[0] = uint64_t(json.data()), r.w[1] = json.size();
  r.size(json.size() / 8 + 16, 16);
  int32_t fault = nixev_json_read(&r, &state, &v);
  if (!fault) return;
  // The words of the reader that took JSON before the index did; the column is where the reading had got to, plus one.
  uint32_t at = uint32_t(r.w[14]), end = uint32_t(r.w[15]);
  if (fault == 14) throw EvalError(composite::cat("unsigned json number ", json.substr(at, end - at), " outside of Nix integer range"));
  if (fault == 15) {
    composite::Text shown; // a NUL shown as U+2400 SYMBOL FOR NULL
    shown.resize(end - at);
    shown.truncate(uint32_t(nixev_json_decode(json.data(), at, end - 1, shown.begin(), 1)));
    throw EvalError(composite::cat("input string '", shown, "' cannot be represented as Nix string because it contains null bytes"));
  }
  uint64_t len;
  const char *what = nixev_json_what(fault, &len);
  throw EvalError(composite::cat("[json.exception.parse_error.101] parse error at line 1, column ", size_t(at) + 1,
                                 ": syntax error while parsing value - ", std::string_view(what, len)));
}

//===----------------------------------------------------------------------===//
// XML output
//===----------------------------------------------------------------------===//

// builtins.toXML is a fill-drain: lowered/nixeval/XmlWalk.mlir walks the value (forcing order, the element nesting, the
// attributes' and formals' sorted order, a derivation's drvPath/outPath and «repeated») and fills rows of 20 i64, one a
// tag line; lowered/nixeval/XmlOps.mlir drains them into the text once.  Here: the evaluator, as the walk's callbacks.
namespace {
struct XmlWalk {
  EvalState &st;
  NixStringContext &ctx;
  composite::TextSet seen;                                       // the derivations met, by drvPath
  composite::MutableSeries<int64_t> rows;                        // the fill
  composite::MutableSeries<composite::MutableSeries<int64_t>> cells; // each set's sorted order, through its children's walk
  composite::MutableSeries<llvm::StringRef> names;               // the latest lambda's formals
  composite::Bump bytes;                                         // the floats' text
};
} // namespace
extern "C" {
void nixev_ts_xml_walk(XmlWalk *x, Value *v, int32_t strict, int32_t location);
int64_t nixev_ts_xml_text(const int64_t *rows, int64_t n, char *into, int64_t cap);
int64_t *nixev_xw_row(XmlWalk *x) { x->rows.resize(x->rows.size() + 20); return x->rows.end() - 20; }
int64_t *nixev_xw_cells(XmlWalk *x, int64_t n) { return x->cells[x->cells.append(composite::MutableSeries<int64_t>(size_t(n)))].data(); }
void nixev_xw_force(XmlWalk *x, Value *v, PosPtr pos) { x->st.forceValue(*v, pos); }
void nixev_xw_ctx(XmlWalk *x, Value *v) { x->st.copyContext(*v, x->ctx); }
int32_t nixev_xw_isdrv(XmlWalk *x, Value *v) { return x->st.isDerivation(*v); }
Value *nixev_xw_drvattr(XmlWalk *x, Value *v, int64_t out, int32_t strict) {
  const Attr *a = v->attrs->get(out ? x->st.s.outPath : x->st.s.drvPath);
  if (a && strict) x->st.forceValue(*a->value, x->st.positionOf(*a));
  return a ? a->value : nullptr;
}
int32_t nixev_xw_seen(XmlWalk *x, const char *p, int64_t n) { return x->seen.insert(p, uint32_t(n)); }
const char *nixev_xw_sym(XmlWalk *x, uint32_t s, int64_t *n) { llvm::StringRef r = x->st.symbols[s]; *n = int64_t(r.size()); return r.data(); }
PosPtr nixev_xw_apos(XmlWalk *x, const Attr *a) { return x->st.positionOf(*a); }
int32_t nixev_xw_pos(XmlWalk *x, PosPtr pos, int64_t *out) {
  auto loc = nd::decodePos(pos);
  if (loc) out[0] = int64_t(loc->file.data()), out[1] = int64_t(loc->file.size()), out[2] = loc->line, out[3] = loc->col;
  return loc.has_value();
}
const char *nixev_xw_float(XmlWalk *x, Value *v, int64_t *n) {
  composite::Text t;
  nixfe::printFloat(t, v->fpoint);
  *n = int64_t(t.size());
  return x->bytes.copy(t.data(), uint32_t(t.size()));
}
void nixev_xw_lambda(XmlWalk *x, Value *v, int64_t *rec) {
  auto lam = cast<nd::LambdaOp>(v->thunk.node->def);
  auto arg = lam.getArgName();
  x->names.clear();
  if (auto fs = lam.getFormals()) for (Attribute f : ArrayAttr(*fs)) x->names.append(cast<StringAttr>(f).getValue());
  int64_t r[7] = {int64_t(nd::posOfOp(lam)), lam.getFormals() ? 1 : 0, arg ? int64_t(arg->data()) : 0, arg ? int64_t(arg->size()) : -1,
                  lam.getEllipsis() ? 1 : 0, int64_t(x->names.size()), int64_t(x->names.data())};
  for (int64_t k = 0; k < 7; k++) rec[k] = r[k];
}
}
static_assert(sizeof(llvm::StringRef) == 16 && sizeof(Attr) == 16 && offsetof(Bindings, attrs) == 16); // as XmlWalk.mlir reads them

// The rows filled before an error are drained too: mlnix eval --xml shows the part written before it.
void EvalState::printValueAsXML(composite::Text &out, Value &v, bool strict, bool location, NixStringContext &ctx) {
  out.put("<?xml version='1.0' encoding='utf-8'?>\n");
  XmlWalk x{*this, ctx, {}, {}, {}, {}, {}};
  auto drain = [&] {
    size_t at = out.size(), total = size_t(nixev_ts_xml_text(x.rows.data(), x.rows.size() / 20, nullptr, 0));
    out.resize(at + total);
    nixev_ts_xml_text(x.rows.data(), x.rows.size() / 20, out.begin() + at, int64_t(total));
  };
  try {
    nixev_ts_xml_walk(&x, &v, strict, location);
  } catch (...) {
    drain();
    throw;
  }
  drain();
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
// An open array's close: its elements (a window of the elems stack) drained into the list's cells, FmtCompOps.mlir.
extern "C" void nixev_ts_toml_cells(const void *elems, int64_t n, void *into);
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
    nixev_ts_toml_cells(P.elems.data() + from, int64_t(n), v->list.elems);
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
