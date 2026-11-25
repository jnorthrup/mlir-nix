//===- Builtins.cpp - The Nix builtins (language-level) -------------------===//

#include "llvm/ADT/StringMap.h"
#include "Composite/CharSeries.h"
#include "Composite/Kursive.h"
#include "Composite/Mutable.h"
#include "Nix/Eval.h"
#include "Nix/Numbers.h"
#include "NixDialect/Kursive.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/TypeSwitch.h"

#include <stdio.h>
#include <time.h>
#include <dirent.h>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

void registerStoreBuiltins(EvalState &state);
void registerFormatBuiltins(EvalState &state);

// The list primops' algebra is hollowed into lowered/nixeval/ListOps.mlir (trikeshed.size / at / series / fold), version
// comparison into VersionOps.mlir (trikeshed.at / slice / compare / text) and __sort into SortOps.mlir (trikeshed.sorted),
// lowered by --trikeshed-lower-cursors and linked into NixEval.  The bridges below force the operands (Nix's error order
// and wording) and call these entries; the entries call back into the evaluator through the callbacks for the cells only
// the evaluator can make (a thunk `f i`, a fresh cell), the stoll reading whose throw stays here, and a sort comparison.
// The integer checked-arithmetic core is ArithOps.mlir and the type predicates / typeOf are TypeOps.mlir (llvm dialect,
// mlnix_lower_interface): the bridges keep the forcing, the dispatch and Nix's error wording.
extern "C" {
void nixev_ts_length(Value *list, Value *v);
void nixev_ts_elemAt(EvalState *st, Value *list, int64_t n, Value *v, PosPtr pos);
void nixev_ts_genList(EvalState *st, Value *f, int64_t n, Value *v);
void nixev_ts_fold(EvalState *st, Value *f, Value *list, Value *nul, Value *v, PosPtr pos);
int64_t nixev_ts_compare_versions(const char *a, int64_t an, const char *b, int64_t bn);
int64_t nixev_ts_next_component(const char *p, int64_t n, int64_t from, int64_t *start, int64_t *len);
void nixev_ts_sort(EvalState *st, Value *f, int64_t isLessThan, Value **from, int64_t n, Value **into, PosPtr pos);
int mlnix_arith_int(int op, int64_t x, int64_t y, int64_t *r); // 0 ok, 1 overflow, 2 division by zero
void mlnix_type_pred(Value *v, int tag, Value *out); // tag: a VType, or 16 for the function group
int mlnix_round(int up, double d, int64_t *out); // __ceil/__floor: 1 in range (result stored), 0 out of range
Value *nixev_gen_elem(EvalState *st, Value *f, int64_t i) { Value *iv = st->allocValue(); st->mkInt(*iv, i); return st->mkAppValue(f, iv); }
Value *nixev_cell(EvalState *st) { return st->allocValue(); }
// componentsLT's toInt: digits all through, their value as stoll made it; std::out_of_range past the range of long long
int64_t nixev_ver_int(const char *p, int64_t n, int64_t *out) {
  std::string_view s(p, size_t(n));
  composite::text::Reading r = nixsys::readSigned(s);
  if (s.empty() || !composite::isAsciiDigit(s[0]) || r.consumed != s.size()) return 0;
  *out = int64_t(nixsys::stoValue("stoll", r));
  return 1;
}
}
// The string primops' algebra and mkStringOf are hollowed into lowered/nixeval/StringOps.mlir (trikeshed.size / slice /
// compare / combineAll / drain).  The bridges force and coerce the operands (Nix's error order and wording, the string
// contexts); the entries call back for the arena room, the 4 GiB refusal, and the replacement strings only the evaluator
// can force with their contexts.  A composite::Chars is 16 bytes: u32 count @0, const char *data @8.
struct TsBounds { int64_t from, to; };
struct TsReplace {
  EvalState *st; Value **to; PosPtr pos; NixStringContext *ctx;
  composite::WordTable<composite::Chars> cache; // the replacement strings by index + 1, forced once each, in match order
};
// The set primops' algebra is hollowed into lowered/nixeval/SetOps.mlir (trikeshed.sorted / bisect / where / alpha /
// compare / series / drain), lowered the same way.  The bridges force the operands (Nix's error order and wording) and
// call these entries; attrNames / attrValues hand in the symbol table's prefix words and name windows (their data
// pointers) so the names sort by their bytes, and nixev_name_cell makes a name's string cell over the table's own bytes.
extern "C" {
void nixev_ts_stringLength(const char *s, int64_t n, Value *v);
TsBounds nixev_ts_substring(const char *s, int64_t n, int64_t start, int64_t len);
// The path primops' slash scans are hollowed into lowered/nixeval/PathBounds.mlir (trikeshed.at / slice over the byte
// series): the bounds of baseNameOf's component and dirOf's last slash.  The bridges coerce and share the window.
TsBounds nixev_ts_basename_bounds(const char *p, int64_t n);
int64_t nixev_ts_dirname_slash(const char *p, int64_t n);
int64_t nixev_ts_drvname_split(const char *s, int64_t n); // __parseDrvName's first qualifying dash, -1 when none
void nixev_ts_concat(EvalState *st, const composite::Chars *pieces, int64_t np, Value *v, const StringContext *ctx);
void nixev_ts_replace(EvalState *st, TsReplace *r, const char *s, int64_t sn, const composite::Chars *from, int64_t m, Value *v);
void nixev_ts_attrNames(EvalState *st, Bindings *set, Value *v, const uint64_t *prefixes, const llvm::StringRef *names);
void nixev_ts_attrValues(EvalState *st, Bindings *set, Value *v, const uint64_t *prefixes, const llvm::StringRef *names);
int nixev_ts_getAttr(EvalState *st, Bindings *set, int64_t sym, Value *v, PosPtr pos);
int nixev_ts_hasAttr(Bindings *set, int64_t sym);
void nixev_ts_intersectAttrs(EvalState *st, Value *v, Bindings *b0, Bindings *b1);
char *nixev_str_room(EvalState *st, int64_t n) {
  if (st->statsEnabled) st->nStringBytes += uint64_t(n) + 1;
  return static_cast<char *>(st->alloc.Allocate(size_t(n) + 1, 1));
}
void nixev_str_toobig() { throw EvalError("string of 4 GiB or more"); }
void nixev_replace_to(TsReplace *r, int64_t j, composite::Chars *out) {
  const composite::Chars *c = r->cache.find(uint64_t(j) + 1);
  if (!c) {
    NixStringContext c2;
    auto ts = r->st->forceString(*r->to[j], c2, r->pos, "while evaluating one of the replacement strings passed to builtins.replaceStrings");
    r->cache.insert(uint64_t(j) + 1, composite::chars(ts.data(), uint32_t(ts.size())));
    c = r->cache.find(uint64_t(j) + 1);
    r->ctx->insert(c2.begin(), c2.end());
  }
  *out = *c;
}
Value *nixev_name_cell(EvalState *st, const char *p, size_t n) { return st->newStringWindow(llvm::StringRef(p, n)); }
// one sort comparison: a < b by the Nix function (or the lessThan fast path), the return value forced
int64_t nixev_sort_lt(EvalState *st, Value *f, int64_t isLessThan, Value *a, Value *b, PosPtr pos) {
  if (isLessThan) return st->lessThan(*a, *b, pos) ? 1 : 0;
  Value *fargs[2] = {a, b};
  Value r;
  st->callFunction(*f, 2, fargs, r, pos);
  return st->forceBool(r, pos, "while evaluating the return value of the sorting function passed to builtins.sort") ? 1 : 0;
}
}

// The higher-order list primops' algebra is hollowed into lowered/nixeval/ListOps2.mlir (trikeshed.size / at / where /
// combineAll / drain), lowered the same way.  The bridges force the operands (Nix's error order and wording) and call
// these entries; the entries call back for each Nix function application (callFunction + forceBool, or eqValues) and,
// for concatLists/concatMap, each inner list's cells.  concatMap's callback caches each call's result (the function runs
// once per element though a combineAll's region runs for its size and again for its drain).  any/all/elem short-circuit
// in the entry's scf.while, so a later element is never forced.
struct TsConcatMap { EvalState *st; Value *f; PosPtr pos; composite::MutableSeries<Value *> rs; };
extern "C" {
void nixev_ts_concatLists(EvalState *st, Value *list, Value *v, PosPtr pos);
void nixev_ts_concatMap(EvalState *st, Value *list, Value *v, TsConcatMap *cm);
int64_t nixev_ts_filter(EvalState *st, Value *f, Value *list, Value **keep, PosPtr pos);
void nixev_ts_any(EvalState *st, Value *f, Value *list, Value *v, PosPtr pos);
void nixev_ts_all(EvalState *st, Value *f, Value *list, Value *v, PosPtr pos);
void nixev_ts_elem(EvalState *st, Value *a, Value *list, Value *v, PosPtr pos);
void nixev_concat_part(EvalState *st, Value *l, PosPtr pos, void **elems, int64_t *n) {
  st->forceList(*l, pos, "while evaluating a value of the list passed to builtins.concatLists"); *elems = l->list.elems; *n = int64_t(l->listSize());
}
void nixev_concatmap_part(TsConcatMap *cm, int64_t k, Value *x, void **elems, int64_t *n) {
  Value *r = size_t(k) < cm->rs.size() ? cm->rs[uint32_t(k)] : nullptr;
  if (!r) {
    r = cm->st->allocValue(); cm->st->callFunction(*cm->f, *x, *r, cm->pos);
    cm->st->forceList(*r, cm->pos, "while evaluating the return value of the function passed to builtins.concatMap"); cm->rs.append(r);
  }
  *elems = r->list.elems; *n = int64_t(r->listSize());
}
int64_t nixev_pred(EvalState *st, Value *f, Value *x, PosPtr pos, int64_t which) {
  Value r; st->callFunction(*f, *x, r, pos);
  const char *ctx = which == 0 ? "while evaluating the return value of the filtering function passed to builtins.filter" : which == 1 ? "while evaluating the return value of the function passed to builtins.any" : "while evaluating the return value of the function passed to builtins.all";
  return st->forceBool(r, pos, ctx) ? 1 : 0;
}
int64_t nixev_elem_eq(EvalState *st, Value *a, Value *e, PosPtr pos) { return (a == e || st->eqValues(*a, *e, pos)) ? 1 : 0; }
}

/// A string result that is `w`, a window on the bytes of `arg` when the argument was a string: those bytes and its context are shared,
/// nothing is copied.  Any other argument was coerced into text of its own, so the result is made from it with `ctx`.
/// A constant as a type, so that a registering loop can make one plain function per constant: a template lambda's body sees V as a
/// constant, not a capture, and converts to a primop's function pointer.
template <auto V> struct K {};

static void mkSharedString(EvalState &st, Value &v, const Value &arg, composite::Chars w, const NixStringContext &ctx) {
  if (arg.type != VType::String) return st.mkString(v, composite::view(w), ctx);
  v.type = VType::String;
  v.str.s = w.data();
  v.aux = w.size();
  v.str.ctx = arg.str.ctx;
}

//===----------------------------------------------------------------------===//
// Regular expressions: Kursive (Composite/Kursive.h), TrikeShed's parsers over a cursor, as libstdc++'s std::regex::extended answers
//===----------------------------------------------------------------------===//

namespace ku = composite::kursive;

/// A pattern's program, compiled at its first sight into arena memory of exactly its size and kept for the run.  A pattern libstdc++ would
/// reject throws the error Nix gives for it, every time it is met, before the input is evaluated.
static const ku::Program &kursiveOf(EvalState &st, std::string_view re, PosPtr pos) {
  static llvm::StringMap<const ku::Program *> cache;
  auto it = cache.find(llvm::StringRef(re.data(), re.size()));
  if (it != cache.end()) return *it->second;
  static ku::Step steps[1 << 16];
  static ku::Set sets[4096];
  ku::Program scratch{steps, 0, 1 << 16, sets, 0, 4096};
  static uint32_t words[4 << 16], n[4]; // the combinators: re2mlir, kursive-to-program (lib/Dialect/KursiveDialect.cpp)
  scratch.error = ku::Error(mlir::kursive::compileProgram(llvm::StringRef(re.data(), re.size()), 1 << 16, 1 << 16, 4096, words, &sets[0].w[0], n));
  scratch.nSteps = n[0], scratch.nSets = n[1], scratch.groups = n[2], scratch.loops = n[3];
  for (uint32_t i = 0; i < scratch.nSteps; i++) steps[i] = {ku::Op(words[4 * i]), words[4 * i + 1], words[4 * i + 2], words[4 * i + 3]};
  if (scratch.error == ku::Error::Space) throw EvalError(composite::cat("memory limit exceeded by regular expression '", re, "'"), pos);
  if (scratch.error != ku::Error::None) throw EvalError(composite::cat("invalid regular expression '", re, "'"), pos);
  auto *prog = static_cast<ku::Program *>(st.alloc.Allocate(sizeof(ku::Program), alignof(ku::Program)));
  auto *t = static_cast<ku::Step *>(st.alloc.Allocate(scratch.nSteps * sizeof(ku::Step), alignof(ku::Step)));
  auto *u = static_cast<ku::Set *>(st.alloc.Allocate(scratch.nSets * sizeof(ku::Set), alignof(ku::Set)));
  for (uint32_t i = 0; i < scratch.nSteps; i++) t[i] = steps[i];
  for (uint32_t i = 0; i < scratch.nSets; i++) u[i] = sets[i];
  *prog = ku::Program{t, scratch.nSteps, scratch.nSteps, u, scratch.nSets, scratch.nSets, scratch.groups, scratch.loops, ku::Error::None};
  cache.try_emplace(llvm::StringRef(re.data(), re.size()), prog);
  return *prog;
}

/// The memory walks work in, kept for the run: the groups' marks, the loops' states, the checkpoints (doubled when a walk runs out).
struct KursiveScratch {
  cp::MutableSeries<uint32_t> caps, best;
  cp::MutableSeries<ku::LoopState> loops;
  cp::MutableSeries<ku::Entry> stack;
};
static KursiveScratch &kursiveScratch() {
  static KursiveScratch s;
  return s;
}

/// A walk (a match or a search) run with checkpoints enough: one that runs out of them runs again with twice as many.  The marks of its
/// answer are kursiveScratch().best.
template <class Walk> static ku::Result kursiveRun(const ku::Program &p, std::string_view re, PosPtr pos, Walk walk) {
  KursiveScratch &k = kursiveScratch();
  uint32_t slots = 2 * (p.groups + 1);
  if (k.caps.size() < slots) { k.caps.resize(slots); k.best.resize(slots); }
  if (k.loops.size() < p.loops) k.loops.resize(p.loops);
  if (k.stack.size() == 0) k.stack.resize(1 << 12);
  for (;;) {
    ku::Scratch s{k.caps.data(), k.best.data(), k.loops.data(), k.stack.data(), k.stack.size(), uint64_t(1) << 34};
    ku::Result r = walk(s);
    if (r != ku::Result::GaveUp) return r;
    if (s.budget == 0 || k.stack.size() >= (1u << 26)) throw EvalError(composite::cat("memory limit exceeded by regular expression '", re, "'"), pos);
    k.stack.resize(k.stack.size() * 2);
  }
}

/// A piece of the input of a match or a split: a window on its bytes when they are an arena string's, which stay; a copy when they are the
/// text a coercion made in `scratch`.
/// The pieces of one split or match: equal pieces are one cell (a string has no identity Nix can see; kif.nix's tokens of
/// sumo.full are 1.43 M pieces of 143 k texts).  The table lives for the one call.
using PieceMemo = llvm::StringMap<Value *>;
static Value *pieceOf(EvalState &st, std::string_view s, size_t b, size_t n, const composite::Text &scratch, PieceMemo *memo = nullptr) {
  std::string_view piece = s.substr(b, n);
  if (Value *v = st.sharedShortString(piece)) return v;
  if (memo) {
    auto [it, fresh] = memo->try_emplace(llvm::StringRef(piece.data(), piece.size()), nullptr);
    if (!fresh) return it->second;
    return it->second = s.data() == scratch.data() ? st.newString(piece) : st.newStringWindow(piece);
  }
  return s.data() == scratch.data() ? st.newString(piece) : st.newStringWindow(piece);
}

/// The groups of a walk's answer as Nix gives them: each group's text, or null where it took no part.
static void kursiveGroups(EvalState &st, Value &v, const ku::Program &p, std::string_view s, const composite::Text &scratch,
                          PieceMemo *memo = nullptr) {
  const uint32_t *best = kursiveScratch().best.data();
  st.mkList(v, p.groups |cp::j| [&](uint32_t i) -> Value * {
    uint32_t b = best[2 * (i + 1)], e = best[2 * (i + 1) + 1];
    if (b == ~0u || e == ~0u) return st.sharedNull();
    return pieceOf(st, s, b, e - b, scratch, memo);
  });
}

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

void EvalState::createBaseEnv() {
  registerBuiltins(*this);
  registerStoreBuiltins(*this);
  registerFormatBuiltins(*this);

  // Constants.
  addConstant("true", &vTrue);
  addConstant("false", &vFalse);
  addConstant("null", &vNull);
  {
    Value *v = allocValue();
    mkInt(*v, 6);
    addConstant("__langVersion", v);
  }
  {
    Value *v = newString("2.35.4");
    addConstant("__nixVersion", v);
  }
  {
    Value *v = newString(store->storeDir());
    addConstant("__storeDir", v);
  }
  if (!settings.pureEval) {
    Value *v = newString(settings.currentSystem);
    addConstant("__currentSystem", v);
    Value *t = allocValue();
    mkInt(*t, (int64_t)time(nullptr));
    addConstant("__currentTime", t);
  }
  {
    Value *v = allocValue();
    mkList(*v, settings.nixPath |cp::α| [&](const auto &p) {
      BindingsBuilder bb(*this);
      mkString(bb.alloc(s.path), p.path);
      mkString(bb.alloc(s.prefix), p.prefix);
      Value *e = allocValue();
      mkAttrs(*e, bb.finish());
      return e;
    });
    addConstant("__nixPath", v);
  }

  // `derivation` is implemented in Nix, exactly as upstream.
  static const char *derivationNix = R"NIX(
drvAttrs@{
  outputs ? [ "out" ],
  ...
}:

let

  strict = derivationStrict drvAttrs;

  commonAttrs =
    drvAttrs
    // (builtins.listToAttrs outputsList)
    // {
      all = map (x: x.value) outputsList;
      inherit drvAttrs;
    };

  outputToAttrListElement = outputName: {
    name = outputName;
    value = commonAttrs // {
      outPath = strict.${outputName};
      drvPath = strict.drvPath;
      type = "derivation";
      inherit outputName;
    };
  };

  outputsList = map outputToAttrListElement outputs;

in
(builtins.head outputsList).value
)NIX";
  // `builtins` must exist before parsing derivation.nix (it references it).
  Value *builtinsV = allocValue();
  addConstant("builtins", builtinsV);
  Value *drvFun = evalString(derivationNix, "/", "«nix-internal»/derivation-internal.nix");
  addConstant("derivation", drvFun);

  // Build the `builtins` attribute set.
  BindingsBuilder bb(*this, baseEnv.size()); // a row a name at most
  for (auto &e : baseEnv) {
    llvm::StringRef name(e.p, e.n);
    if (name.starts_with("__")) name = name.drop_front(2);
    bb.insert(name, e.v);
  }
  builtinsAttrs = bb.finish();
  mkAttrs(*builtinsV, builtinsAttrs);
}

// The attribute-set / list algebra of __groupBy, __zipAttrsWith, __partition, __catAttrs, removeAttrs, __listToAttrs and
// __mapAttrs is lowered/nixeval/GroupOps.mlir (trikeshed.sorted / where / alpha / slice / combineAll / drain), __getContext's
// ContextOps.mlir.  The callbacks are the evaluator's part, called where the C++ loops made them.  __genericClosure stays
// here: its comparisons (each a throwing, forcing lessThan) are made in the order libc++'s std::set made them.
extern "C" {
void nixev_ts_group(EvalState *st, Value *f, Value *list, Value *v, PosPtr pos, int64_t zip);
void nixev_ts_partition(EvalState *st, Value *f, Value *list, Value *v, PosPtr pos);
void nixev_ts_catAttrs(EvalState *st, int64_t sym, Value *list, Value *v, PosPtr pos);
void nixev_ts_removeAttrs(EvalState *st, Bindings *in, Value *list, Value *v, PosPtr pos);
void nixev_ts_mapAttrs(EvalState *st, Value *f, Bindings *in, Value *v);
void nixev_ts_listToAttrs(EvalState *st, Value *list, Value *v, PosPtr pos);
void nixev_ts_getContext(EvalState *st, EvalState::BindingsBuilder *bb, const char *const *elems, int64_t n, int64_t *outs);
int64_t nixev_gr_sym(EvalState *st, Value *f, Value *x, PosPtr pos, int64_t groupBy) {
  Value r;
  if (f) st->callFunction(*f, *x, r, pos);
  return st->symbolOfString(st->forceStringNoCtx(f ? r : *x, pos, groupBy ? "while evaluating the return value of the grouping function passed to builtins.groupBy" : "while evaluating the values of the second argument passed to builtins.removeAttrs"));
}
int64_t nixev_gr_side(EvalState *st, Value *f, Value *x, PosPtr pos) {
  st->forceValue(*x, pos);
  Value r;
  st->callFunction(*f, *x, r, pos);
  return st->forceBool(r, pos, "while evaluating the return value of the partition function passed to builtins.partition");
}
Bindings *nixev_gr_force(EvalState *st, Value *x, PosPtr pos, int64_t catAttrs) {
  st->forceAttrs(*x, pos, catAttrs ? "while evaluating an element in the list passed as second argument to builtins.catAttrs" : "while evaluating a value of the list passed as second argument to builtins.zipAttrsWith");
  return x->attrs;
}
int64_t nixev_gr_pair(EvalState *st, Value *e, PosPtr pos, Value **val) { // listToAttrs' {name, value}: the row's first word, the value in *val
  st->forceAttrs(*e, pos, "while evaluating an element of the list passed to builtins.listToAttrs");
  const Attr *n = e->attrs->get(st->s.name);
  if (!n) throw EvalError("attribute 'name' missing", pos).addTrace(pos, "in a {name=...; value=...;} pair");
  auto name = st->forceStringNoCtx(*n->value, pos, "while evaluating the `name` attribute of an element of the list passed to builtins.listToAttrs");
  const Attr *a = e->attrs->get(st->s.value);
  if (!a) throw EvalError("attribute 'value' missing", pos).addTrace(pos, "in a {name=...; value=...;} pair");
  *val = a->value;
  return int64_t(st->symbolOfString(name)) | int64_t(a->pos) << 32;
}
Value *nixev_gr_run(EvalState *st, Value *f, int64_t zip, int64_t name, int64_t n, Value ***elems) {
  Value *list = st->allocValue();
  st->mkList(*list, size_t(n));
  *elems = list->list.elems;
  return zip ? st->mkAttrAppValue(f, Symbol(name), list) : list; // zipAttrsWith's `f name values`, one cell
}
Value *nixev_gr_app(EvalState *st, Value *f, int64_t name, Value *x) { return st->mkAttrAppValue(f, Symbol(name), x); }
Bindings *nixev_gr_set(EvalState *st, Value *v, int64_t m, int64_t room, Bindings *pre) { // BindingsBuilder::finish's set of m rows
  if (!m && st->statsEnabled) ++st->nEmptyShared;
  Bindings *b = !m ? st->vEmptyAttrs.attrs : pre ? pre : st->allocBindings(size_t(room));
  if (m) b->size_ = uint32_t(m);
  st->mkAttrs(*v, b);
  return b;
}
void nixev_gr_partition(EvalState *st, Value *v, int64_t nr, int64_t nw, Value ***re, Value ***we) {
  EvalState::BindingsBuilder bb(*st);
  Value &rv = bb.alloc(st->s.right);
  st->mkList(rv, size_t(nr));
  Value &wv = bb.alloc(st->s.wrong);
  st->mkList(wv, size_t(nw));
  *re = rv.list.elems, *we = wv.list.elems;
  st->mkAttrs(*v, bb.finish());
}
void nixev_cx_group(EvalState *st, EvalState::BindingsBuilder *bb, const char *path, int64_t pn, int64_t flags, const composite::Chars *outs, int64_t no) {
  EvalState::BindingsBuilder ib(*st);
  if (flags & 1) ib.insert("path", &st->vTrue);
  if (flags & 2) ib.insert("allOutputs", &st->vTrue);
  if (no) st->mkList(ib.alloc("outputs"), cp::series(outs, uint32_t(no)) |cp::α| [&](composite::Chars o) { return st->newString(composite::view(o)); });
  Value &iv = bb->alloc(llvm::StringRef(path, size_t(pn)));
  st->mkAttrs(iv, ib.finish());
}
}

void registerBuiltins(EvalState &state) {
  using A = Value **;
  auto &S = state;

  // -- Control -----------------------------------------------------------
  S.addPrimOp("abort", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos, "while evaluating the error message passed to builtins.abort");
    throw Abort("evaluation aborted with the following error message: '" + s + "'", pos);
  });
  S.addPrimOp("throw", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos, "while evaluating the error message passed to builtin.throw");
    throw ThrownError(composite::mv(s), pos);
  });
  S.addPrimOp("__addErrorContext", [](EvalState &st, A args, Value &v, PosPtr pos) {
    try {
      st.forceValue(*args[1], pos);
      v = *args[1];
    } catch (EvalError &e) {
      NixStringContext ctx;
      auto msg = st.coerceToString(*args[0], ctx, false, false, pos);
      e.addTrace(nullptr, composite::mv(msg));
      throw;
    }
  });
  S.addPrimOp("__tryEval", [](EvalState &st, A args, Value &v, PosPtr pos) {
    EvalState::BindingsBuilder bb(st);
    st.tryLevel++;
    try {
      st.forceValue(*args[0], pos);
      bb.insert(st.s.value, args[0]);
      bb.insert(st.s.success, &st.vTrue);
    } catch (AssertionError &) {
      bb.insert(st.s.value, &st.vFalse);
      bb.insert(st.s.success, &st.vFalse);
    }
    st.tryLevel--;
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__seq", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__deepSeq", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValueDeep(*args[0]);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__trace", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::String) st.printTrace(composite::cat("trace: ", args[0]->sv()));
    else st.printTrace("trace: " + st.printValueForTrace(*args[0]));
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__traceVerbose", [](EvalState &st, A args, Value &v, PosPtr pos) {
    if (st.settings.traceVerbose) {
      st.forceValue(*args[0], pos);
      if (args[0]->type == VType::String) st.printTrace(composite::cat("trace: ", args[0]->sv()));
      else st.printTrace("trace: " + st.printValueForTrace(*args[0]));
    }
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__warn", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto msg = st.forceString(*args[0], pos, "while evaluating the first argument; the message passed to builtins.warn");
    composite::Text line = composite::cat("evaluation warning: ", msg);
    nixsys::lineToStderr(line.data(), line.size());
    if (st.settings.abortOnWarn) throw EvalError(msg, pos);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("break", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    v = *args[0];
  });

  // -- Types ---------------------------------------------------------------
  // The tag test and the Bool write are TypeOps.mlir (mlnix_type_pred); tag 16 is the function group (isFunction).
  auto typePred = [&]<int T>(const char *name, K<T>) {
    S.addPrimOp(name, [](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      mlnix_type_pred(args[0], T, &v);
    });
  };
  typePred("isNull", K<int(VType::Null)>{});
  typePred("__isFunction", K<16>{});
  typePred("__isInt", K<int(VType::Int)>{});
  typePred("__isFloat", K<int(VType::Float)>{});
  typePred("__isString", K<int(VType::String)>{});
  typePred("__isBool", K<int(VType::Bool)>{});
  typePred("__isPath", K<int(VType::Path)>{});
  typePred("__isAttrs", K<int(VType::Attrs)>{});
  typePred("__isList", K<int(VType::List)>{});
  S.addPrimOp("__typeOf", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.mkString(v, EvalState::typeOf(*args[0]));
  });

  // -- Arithmetic ------------------------------------------------------------
  auto arith = [&]<char op>(const char *name, K<op>) {
    S.addPrimOp(name, [](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      st.forceValue(*args[1], pos);
      Value &a = *args[0], &b = *args[1];
      // The error contexts are literals: a message nobody prints is not built (it was two heap strings a call, a ninth of the evaluator's).
      std::string_view first = op == '+' ? "while evaluating the first argument of the addition"
                             : op == '-' ? "while evaluating the first argument of the subtraction"
                             : op == '*' ? "while evaluating the first argument of the multiplication"
                                         : "while evaluating the first argument of the division";
      std::string_view second = op == '+' ? "while evaluating the second argument of the addition"
                              : op == '-' ? "while evaluating the second argument of the subtraction"
                              : op == '*' ? "while evaluating the second argument of the multiplication"
                                          : "while evaluating the second argument of the division";
      if (a.type == VType::Float || b.type == VType::Float) {
        double x = st.forceFloat(a, pos, first);
        double y = st.forceFloat(b, pos, second);
        if (op == '/' && y == 0) throw EvalError("division by zero", pos);
        st.mkFloat(v, op == '+' ? x + y : op == '-' ? x - y : op == '*' ? x * y : x / y);
        return;
      }
      int64_t x = st.forceInt(a, pos, first);
      int64_t y = st.forceInt(b, pos, second);
      // The checked core (overflow detection + result, __builtin_*_overflow's exact tests) is ArithOps.mlir.
      int64_t r;
      int flag = mlnix_arith_int(op, x, y, &r);
      if (flag == 2) throw EvalError("division by zero", pos);
      if (flag == 1) {
        const char *verb = op == '+' ? "adding" : op == '-' ? "subtracting" : op == '*' ? "multiplying" : "dividing";
        const char *sym = op == '+' ? " + " : op == '-' ? " - " : op == '*' ? " * " : " / ";
        throw EvalError(composite::cat("integer overflow in ", verb, " ", x, sym, y), pos);
      }
      st.mkInt(v, r);
    });
  };
  arith("__add", K<'+'>{});
  arith("__sub", K<'-'>{});
  arith("__mul", K<'*'>{});
  arith("__div", K<'/'>{});
  auto bitop = [&]<char op>(const char *name, K<op>) {
    S.addPrimOp(name, [](EvalState &st, A args, Value &v, PosPtr pos) {
      int64_t a = st.forceInt(*args[0], pos), b = st.forceInt(*args[1], pos);
      st.mkInt(v, op == '&' ? (a & b) : op == '|' ? (a | b) : (a ^ b));
    });
  };
  bitop("__bitAnd", K<'&'>{});
  bitop("__bitOr", K<'|'>{});
  bitop("__bitXor", K<'^'>{});
  S.addPrimOp("__lessThan", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.mkBool(v, st.lessThan(*args[0], *args[1], pos));
  });
  auto rounding = [&]<bool up>(const char *name, K<up>) {
    S.addPrimOp(name, [](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      if (args[0]->type == VType::Int) { v = *args[0]; return; }
      double d = st.forceFloat(*args[0], pos);
      // The ceil/floor core, the range test and the cast are Rounding.mlir; the wording quotes the original float.
      int64_t r;
      if (!mlnix_round(up, d, &r))
        throw EvalError(composite::cat("NixFloat argument ", nixfe::fixedFloat(d), " is not in the range of NixInt"), pos);
      st.mkInt(v, r);
    });
  };
  rounding("__ceil", K<true>{});
  rounding("__floor", K<false>{});

  // -- Strings ---------------------------------------------------------------
  S.addPrimOp("toString", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, true, false, pos, "while evaluating the first argument passed to builtins.toString", scratch);
    mkSharedString(st, v, *args[0], w, ctx);
  });
  S.addPrimOp("__stringLength", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "while evaluating the argument passed to builtins.stringLength", scratch);
    nixev_ts_stringLength(w.data(), w.size(), &v);
  });
  S.addPrimOp("__substring", [](EvalState &st, A args, Value &v, PosPtr pos) {
    int64_t start = st.forceInt(*args[0], pos, "while evaluating the first argument (the start offset) passed to builtins.substring");
    if (start < 0) throw EvalError("negative start position in substring", pos);
    int64_t len = st.forceInt(*args[1], pos, "while evaluating the second argument (the substring length) passed to builtins.substring");
    st.forceValue(*args[2], pos);
    if (args[2]->type == VType::String) {
      // A window over the string's own bytes, sharing its context: nothing is copied.
      composite::Chars chars = args[2]->window();
      auto b = nixev_ts_substring(chars.data(), chars.size(), start, len);
      v.type = VType::String;
      v.str.s = chars.data() + b.from;
      v.aux = uint32_t(b.to - b.from);
      v.str.ctx = args[2]->str.ctx;
      return;
    }
    NixStringContext ctx;
    composite::Text scratch;  // only a coerced argument (a path, a set) gets here: a string was shared above
    auto w = st.coerceToWindow(*args[2], ctx, false, true, pos, "while evaluating the third argument (the string) passed to builtins.substring", scratch);
    auto b = nixev_ts_substring(w.data(), w.size(), start, len);
    st.mkString(v, std::string_view(w.data() + b.from, size_t(b.to - b.from)), ctx);
  });
  S.addPrimOp("__concatStringsSep", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto sep = st.forceString(*args[0], ctx, pos, "while evaluating the first argument (the separator string) passed to builtins.concatStringsSep");
    st.forceList(*args[1], pos, "while evaluating the second argument (the list of strings to concat) passed to builtins.concatStringsSep");
    // The result is the series of its pieces: strings are windows over their own bytes, the separator one window, coerced elements
    // (paths, sets with outPath) the only text made; one arena buffer, written once.
    size_t ne = args[1]->listSize(), np = ne ? 2 * ne - 1 : 0, nv = 0;
    composite::Chars stackPieces[32];
    composite::Chars *pieces = np <= 32 ? stackPieces : static_cast<composite::Chars *>(st.alloc.Allocate(np * sizeof(composite::Chars), alignof(composite::Chars)));
    composite::Text scratch;
    PieceContexts own; // the elements' own contexts: shared as the result's when there is one, merged only when there are several
    for (size_t i = 0; i < ne; i++) {
      if (i) pieces[nv++] = composite::chars(sep);  // a window on the separator's own arena bytes
      Value &e = *args[1]->list.elems[i];
      st.forceValue(e, pos);
      const StringContext *pc = nullptr;
      composite::Chars w = st.coerceToWindow(e, ctx, false, true, pos,
          "while evaluating one element of the list of strings to concat passed to builtins.concatStringsSep", scratch, true, &pc);
      own.add(pc, ctx);
      if (w.size() && w.data() == scratch.data()) w = composite::chars(st.copyString(scratch), w.size()); // coerced text lives in the arena
      pieces[nv++] = w;
    }
    nixev_ts_concat(&st, pieces, int64_t(nv), &v, own.result(st, ctx));
  });
  S.addPrimOp("__replaceStrings", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.replaceStrings");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.replaceStrings");
    if (args[0]->listSize() != args[1]->listSize())
      throw EvalError("'from' and 'to' arguments passed to builtins.replaceStrings have different lengths", pos);
    auto from = llvm::to_vector(args[0]->values() |cp::α| [&](Value &e) {
      auto s = st.forceString(e, pos, "while evaluating one of the strings to replace passed to builtins.replaceStrings");
      return composite::chars(s.data(), uint32_t(s.size())); });
    NixStringContext ctx;
    std::string_view s = st.forceString(*args[2], ctx, pos, "while evaluating the third argument passed to builtins.replaceStrings");
    TsReplace r{&st, args[1]->list.elems, pos, &ctx, {}};
    nixev_ts_replace(&st, &r, s.data(), int64_t(s.size()), from.data(), int64_t(from.size()), &v);
    v.str.ctx = st.makeContext(ctx);
  });
  S.addPrimOp("__match", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto re = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.match");
    const ku::Program &prog = kursiveOf(st, re, pos); // an invalid pattern throws before the input is evaluated
    NixStringContext ctx;
    composite::Text scratch;
    auto s = composite::view(st.coerceToWindow(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.match", scratch));
    composite::Text &key = st.matchKey; // built in a buffer that is reused
    // The answer is a function of the pattern's bytes and the input's, and it is a value nothing writes (null, or a list of strings with no
    // context): a pair met before is answered from the memo, keyed by its content (more than half of the calls of a NixOS evaluation repeat
    // a pair).  The key is the pattern's length, the pattern and the input: no two pairs share one.
    uint32_t rlen = uint32_t(re.size());
    key.clear();
    key.put(reinterpret_cast<const char *>(&rlen), sizeof rlen).put(re.data(), rlen).put(s.data(), uint32_t(s.size()));
    if (Value *memo = st.matchMemo.find(key.data(), key.size())) { v = *memo; return; }
    // Kursive walks the pattern's program over the input's bytes where they lie: the groups are marks, and nothing is allocated.
    ku::Result r = kursiveRun(prog, re, pos, [&](ku::Scratch &k) { return ku::matchAll(prog, s.data(), uint32_t(s.size()), k); });
    if (r == ku::Result::NoMatch) st.mkNull(v);
    else kursiveGroups(st, v, prog, s, scratch);
    st.matchMemo.set(key.data(), key.size(), v, [&] { return st.keyText.copy(key.data(), key.size()); });
  });
  S.addPrimOp("__split", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto re = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.split");
    const ku::Program &prog = kursiveOf(st, re, pos);
    NixStringContext ctx;
    composite::Text scratch;
    auto s = composite::view(st.coerceToWindow(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.split", scratch));
    // std::cregex_iterator's walk: each match at the leftmost start that has one, the longest there; after an empty match, a non-empty one
    // at the same place, else the search goes on one byte later.  Between matches the text in between, and each match's groups.
    uint32_t n = uint32_t(s.size()), lastEnd = 0, from = 0;
    bool afterEmpty = false;
    composite::MutableSeries<Value *> out;
    PieceMemo memo;
    for (;;) {
      ku::Result r = kursiveRun(prog, re, pos, [&](ku::Scratch &k) { return ku::search(prog, s.data(), n, from, afterEmpty, afterEmpty, k); });
      if (r == ku::Result::NoMatch) {
        if (!afterEmpty) break;
        afterEmpty = false;
        from++; // the empty match was not followed by a non-empty one at its place: one byte on
        continue;
      }
      const uint32_t *best = kursiveScratch().best.data();
      uint32_t ms = best[0], me = best[1];
      out.append(pieceOf(st, s, lastEnd, ms - lastEnd, scratch, &memo));
      Value *groups = st.allocValue();
      kursiveGroups(st, *groups, prog, s, scratch, &memo);
      out.append(groups);
      lastEnd = me;
      from = me;
      afterEmpty = ms == me;
      if (afterEmpty && me == n) break;
    }
    out.append(pieceOf(st, s, lastEnd, n - lastEnd, scratch, &memo));
    st.mkList(v, out);
  });
  S.addPrimOp("__compareVersions", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto a = st.forceStringNoCtx(*args[0], pos), b = st.forceStringNoCtx(*args[1], pos);
    st.mkInt(v, nixev_ts_compare_versions(a.data(), int64_t(a.size()), b.data(), int64_t(b.size())));
  });
  S.addPrimOp("__splitVersion", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto ver = st.forceStringNoCtx(*args[0], pos);
    composite::MutableSeries<std::string_view> comps;
    int64_t n = int64_t(ver.size()), p = 0, s = 0, l = 0;
    while (p < n) {
      p = nixev_ts_next_component(ver.data(), n, p, &s, &l);
      if (l == 0) break;
      comps.append(std::string_view(ver.data() + s, size_t(l)));
    }
    st.mkList(v, comps |cp::α| [&](const auto &c) { return st.newString(c); });
  });
  S.addPrimOp("__parseDrvName", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.parseDrvName");
    // The dash scan is DrvNameOps.mlir: the first '-' followed by a non-letter, -1 when there is none.
    int64_t cut = nixev_ts_drvname_split(name.data(), int64_t(name.size()));
    std::string_view n = cut < 0 ? name : name.substr(0, size_t(cut));
    std::string_view ver = cut < 0 ? std::string_view() : name.substr(size_t(cut) + 1);
    EvalState::BindingsBuilder bb(st);
    st.mkString(bb.alloc(st.s.name), n);
    st.mkString(bb.alloc("version"), ver);
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("baseNameOf", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to builtins.baseNameOf", scratch);
    std::string_view p = composite::view(w);
    auto b = nixev_ts_basename_bounds(p.data(), int64_t(p.size()));
    mkSharedString(st, v, *args[0], composite::slice(w, uint32_t(b.from), uint32_t(b.to)), ctx);
  });
  S.addPrimOp("dirOf", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::Path) {
      std::string_view p(args[0]->pathView());
      st.mkPath(v, nixstore::dirOf(p));
      return;
    }
    NixStringContext ctx;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to 'builtins.dirOf'", scratch);
    std::string_view p = composite::view(w);
    auto slash = nixev_ts_dirname_slash(p.data(), int64_t(p.size()));
    if (slash < 0) return st.mkString(v, ".", ctx);
    mkSharedString(st, v, *args[0], composite::slice(w, 0, slash == 0 ? 1 : uint32_t(slash)), ctx);
  });

  // -- Context ---------------------------------------------------------------
  S.addPrimOp("__unsafeDiscardStringContext", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "", scratch);
    mkSharedString(st, v, *args[0], w, {});
    if (args[0]->type == VType::String) v.str.ctx = nullptr;  // the bytes are shared, the context is not
  });
  S.addPrimOp("__hasContext", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceString(*args[0], pos, "while evaluating the argument passed to builtins.hasContext");
    st.mkBool(v, args[0]->str.ctx != nullptr);
  });
  S.addPrimOp("__unsafeDiscardOutputDependency", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx, out;
    composite::Text scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "", scratch);
    for (const char *c : ctx) out.insert(c[0] == '=' ? c + 1 : c); // the path after '=' is a suffix of the element: nothing copied
    st.mkString(v, composite::view(w), out);
  });
  S.addPrimOp("__addDrvOutputDependencies", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.forceString(*args[0], ctx, pos, "while evaluating the argument passed to builtins.addDrvOutputDependencies");
    if (ctx.size() != 1)
      throw EvalError(composite::cat("context of string '", s, "' must have exactly one element, but has ", ctx.size()), pos);
    composite::Text c(*ctx.begin());
    if (c[0] == '!') throw EvalError(composite::cat("`addDrvOutputDependencies` can only act on derivations, not on a derivation output such as '", c.substr(c.find('!', 1) + 1), "'"), pos);
    if (c[0] != '=') {
      if (c.size() < 4 || c.substr(c.size() - 4) != ".drv")
        throw EvalError(composite::cat("path '", c, "' is not a derivation"), pos);
      c = composite::cat("=", c);
    }
    st.mkString(v, s, NixStringContext{st.copyString(c)});
  });
  S.addPrimOp("__getContext", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    st.forceString(*args[0], ctx, pos, "while evaluating the argument passed to builtins.getContext");
    EvalState::BindingsBuilder bb(st);
    composite::MutableSeries<int64_t> outs(2 * size_t(ctx.size())); // a path's outputs' windows, as ContextOps.mlir drains them
    nixev_ts_getContext(&st, &bb, ctx.begin(), ctx.size(), outs.data());
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__appendContext", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.forceString(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.appendContext");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.appendContext");
    for (auto &a : *args[1]->attrs) {
      std::string_view path = st.symbols[a.name];
      if (!nixstore::isStorePath(st.store->storeDir(), path))
        throw EvalError(composite::cat("context key '", path, "' is not a store path"), pos);
      st.forceAttrs(*a.value, pos);
      if (const Attr *p = a.value->attrs->get(st.symbols.create("path")))
        if (st.forceBool(*p->value, pos)) ctx.insert(st.copyString(path));
      if (const Attr *p = a.value->attrs->get(st.symbols.create("allOutputs")))
        if (st.forceBool(*p->value, pos)) {
          if (path.size() < 4 || path.substr(path.size() - 4) != ".drv")
            throw EvalError(composite::cat("tried to add all-outputs context of ", path, ", which is not a derivation, to a string"), pos);
          ctx.insert(st.copyString(composite::cat("=", path)));
        }
      if (const Attr *p = a.value->attrs->get(st.s.outputs)) {
        st.forceList(*p->value, pos);
        if (p->value->listSize() && (path.size() < 4 || path.substr(path.size() - 4) != ".drv"))
          throw EvalError(composite::cat("tried to add derivation output context of ", path, ", which is not a derivation, to a string"), pos);
        for (size_t i = 0; i < p->value->listSize(); i++)
          ctx.insert(st.copyString(composite::cat("!", st.forceStringNoCtx(*p->value->list.elems[i], pos), "!", path)));
      }
    }
    st.mkString(v, s, ctx);
  });

  // -- Attribute sets ----------------------------------------------------------
  S.addPrimOp("__attrNames", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrNames");
    nixev_ts_attrNames(&st, args[0]->attrs, &v, st.symbols.prefix.data(), st.symbols.names.data());
  });
  S.addPrimOp("__attrValues", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrValues");
    nixev_ts_attrValues(&st, args[0]->attrs, &v, st.symbols.prefix.data(), st.symbols.names.data());
  });
  S.addPrimOp("__getAttr", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getAttr");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.getAttr");
    if (!nixev_ts_getAttr(&st, args[1]->attrs, st.symbolOfString(name), &v, pos))
      throw EvalError(composite::cat("attribute '", name, "' missing"), pos);
  });
  S.addPrimOp("__unsafeGetAttrPos", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos);
    st.forceAttrs(*args[1], pos);
    const Attr *a = args[1]->attrs->get(st.symbolOfString(name));
    if (!a || !a->pos) { st.mkNull(v); return; }
    auto f = nd::decodePos(st.positionOf(*a));
    if (!f) { st.mkNull(v); return; }
    EvalState::BindingsBuilder bb(st);
    st.mkString(bb.alloc(st.s.file), f->file);
    st.mkInt(bb.alloc(st.s.line), f->line);
    st.mkInt(bb.alloc(st.s.column), f->col);
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__hasAttr", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.hasAttr");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.hasAttr");
    st.mkBool(v, nixev_ts_hasAttr(args[1]->attrs, st.symbolOfString(name)) != 0);
  });
  S.addPrimOp("removeAttrs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.removeAttrs");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.removeAttrs");
    nixev_ts_removeAttrs(&st, args[0]->attrs, args[1], &v, pos);
  });
  S.addPrimOp("__listToAttrs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the argument passed to builtins.listToAttrs");
    nixev_ts_listToAttrs(&st, args[0], &v, pos);
  });
  S.addPrimOp("__intersectAttrs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.intersectAttrs");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.intersectAttrs");
    // Walk the smaller set and probe the larger (callPackage intersects ~10 formals with all of nixpkgs); the result is
    // sorted, with the entries of the second set.  The walk and the probes are trikeshed.where / bisect in SetOps.mlir.
    nixev_ts_intersectAttrs(&st, &v, args[0]->attrs, args[1]->attrs);
  });
  S.addPrimOp("__catAttrs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    Symbol name = st.symbolOfString(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.catAttrs"));
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.catAttrs");
    nixev_ts_catAttrs(&st, name, args[1], &v, pos);
  });
  S.addPrimOp("__functionArgs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::PrimOp || args[0]->type == VType::PrimOpApp) { st.mkAttrs(v, st.allocBindings(0)); return; }
    if (args[0]->type != VType::Lambda) throw EvalError("'functionArgs' requires a function", pos);
    auto lam = cast<nd::LambdaOp>(args[0]->thunk.node->def);
    if (!lam.getFormals()) { st.mkAttrs(v, st.allocBindings(0)); return; }
    EvalState::BindingsBuilder bb(st, lam.getFormals()->size()); // a row a formal
    auto defs = *lam.getFormalDefaults();
    // Positions of the formals come from the nix.formal ops in the body.
    auto locs = lam.getFormalLocs();
    for (size_t i = 0; i < lam.getFormals()->size(); i++) {
      PosPtr p = locs && i < locs->size() ? nd::posOfWord(uint64_t((*locs)[i])) : nullptr;
      bb.insert(st.symbolOf(cast<StringAttr>((*lam.getFormals())[i])), defs[i] ? &st.vTrue : &st.vFalse, p); // by the name's address
    }
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__mapAttrs", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.mapAttrs");
    nixev_ts_mapAttrs(&st, args[0], args[1]->attrs, &v); // `f name value`, one cell a row
  });
  S.addPrimOp("__zipAttrsWith", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.zipAttrsWith");
    nixev_ts_group(&st, args[0], args[1], &v, pos, 1);
  });

  // -- Lists -----------------------------------------------------------------
  S.addPrimOp("map", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.map");
    size_t n = args[1]->listSize();
    if (!n) { v = *args[1]; return; }
    Value **src = args[1]->list.elems;
    Value *f = args[0];
    st.mkList(v, cp::series(src, n) |cp::α| [&](Value *x) { return st.mkAppValue(f, x); });
  });
  S.addPrimOp("__length", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.length");
    nixev_ts_length(args[0], &v);
  });
  S.addPrimOp("__head", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.head");
    if (!args[0]->listSize()) throw EvalError("'builtins.head' called on an empty list", pos);
    Value *e = args[0]->list.elems[0];
    st.forceValue(*e, pos);
    v = *e;
  });
  S.addPrimOp("__tail", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.tail");
    if (!args[0]->listSize()) throw EvalError("'builtins.tail' called on an empty list", pos);
    size_t n = args[0]->listSize() - 1;
    Value **src = args[0]->list.elems;
    st.mkList(v, cp::series(src + 1, n));
  });
  S.addPrimOp("__elemAt", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.elemAt");
    int64_t n = st.forceInt(*args[1], pos, "while evaluating the second argument passed to builtins.elemAt");
    if (n < 0 || (uint64_t)n >= args[0]->listSize())
      throw EvalError(composite::cat("list index ", n, " is out of bounds"), pos);
    nixev_ts_elemAt(&st, args[0], n, &v, pos);
  });
  S.addPrimOp("__elem", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.elem");
    nixev_ts_elem(&st, args[0], args[1], &v, pos);
  });
  S.addPrimOp("__concatLists", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.concatLists");
    nixev_ts_concatLists(&st, args[0], &v, pos);
  });
  S.addPrimOp("__concatMap", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.concatMap");
    TsConcatMap cm{&st, args[0], pos, {}};
    nixev_ts_concatMap(&st, args[1], &v, &cm);
  });
  S.addPrimOp("__filter", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.filter");
    // The kept cells go into stack scratch when the list is short, and straight into the arena list they will be when it is long (its
    // tail past the kept ones is left, never copied): the where of ListOps2.mlir drains them, the count comes back.
    size_t n = args[1]->listSize();
    Value *stackKeep[32];
    Value **keep = n <= 32 ? stackKeep : st.allocList(n);
    int64_t k = nixev_ts_filter(&st, args[0], args[1], keep, pos);
    if (size_t(k) == n) { v = *args[1]; return; }
    if (n <= 32) return st.mkList(v, cp::series(keep, uint32_t(k)));
    st.mkList(v, 0);
    v.aux = uint32_t(k);
    v.list.elems = keep;
  });
  S.addPrimOp("__any", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.any");
    nixev_ts_any(&st, args[0], args[1], &v, pos);
  });
  S.addPrimOp("__all", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.all");
    nixev_ts_all(&st, args[0], args[1], &v, pos);
  });
  S.addPrimOp("__foldl'", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceFunction(*args[0], pos, "while evaluating the first argument passed to builtins.foldlStrict");
    st.forceList(*args[2], pos, "while evaluating the third argument passed to builtins.foldlStrict");
    nixev_ts_fold(&st, args[0], args[2], args[1], &v, pos);
  });
  S.addPrimOp("__genList", [](EvalState &st, A args, Value &v, PosPtr pos) {
    int64_t n = st.forceInt(*args[1], pos, "while evaluating the second argument passed to builtins.genList");
    if (n < 0) throw EvalError(composite::cat("cannot create list of size ", n), pos);
    st.forceFunction(*args[0], pos, "while evaluating the first argument passed to builtins.genList");
    nixev_ts_genList(&st, args[0], n, &v);
  });
  S.addPrimOp("__sort", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.sort");
    size_t n = args[1]->listSize();
    for (size_t k = 0; k < n; k++) st.forceValue(*args[1]->list.elems[k], pos);
    if (n == 0) { v = *args[1]; return; }
    st.forceFunction(*args[0], pos, "while evaluating the sorting function passed to builtins.sort");
    // Fast path for __lessThan.
    bool isLessThan = args[0]->type == VType::PrimOp && args[0]->primOp->name == "lessThan";
    // The argument's cells are const and read where they lie: trikeshed.sorted drains them into the result list.
    st.mkList(v, n);
    nixev_ts_sort(&st, args[0], isLessThan ? 1 : 0, args[1]->list.elems, int64_t(n), v.list.elems, pos);
  });
  S.addPrimOp("__partition", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.partition");
    nixev_ts_partition(&st, args[0], args[1], &v, pos);
  });
  S.addPrimOp("__groupBy", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.groupBy");
    nixev_ts_group(&st, args[0], args[1], &v, pos, 0);
  });
  S.addPrimOp("__genericClosure", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.genericClosure");
    const Attr *ss = args[0]->attrs->get(st.s.startSet);
    if (!ss) throw EvalError("attribute 'startSet' missing", pos);
    st.forceList(*ss->value, pos, "while evaluating the 'startSet' attribute passed as argument to builtins.genericClosure");
    const Attr *op = args[0]->attrs->get(st.s.operator_);
    if (!op) throw EvalError("attribute 'operator' missing", pos);
    composite::MutableSeries<Value *> res;
    composite::MutableSeries<Value *> done; // the keys met, sorted by lessThan
    composite::MutableSeries<Value *> queue;
    for (size_t k = 0, nk = ss->value->listSize(); k < nk; k++) queue.append(ss->value->list.elems[k]);
    size_t qi = 0;
    while (qi < queue.size()) {
      Value *e = queue[qi++];
      st.forceAttrs(*e, pos, "while evaluating one of the elements generated by (or initially passed to) builtins.genericClosure");
      const Attr *key = e->attrs->get(st.s.key);
      if (!key) throw EvalError("attribute 'key' missing", pos);
      st.forceValue(*key->value, pos);
      // A binary search comparing as a std::set's lookup did: the key with an element first, then the element with the key.
      uint32_t lo = 0, hi = done.size();
      bool met = false;
      while (lo < hi && !met) {
        uint32_t mid = lo + (hi - lo) / 2;
        if (st.lessThan(*key->value, *done[mid], pos)) hi = mid;
        else if (st.lessThan(*done[mid], *key->value, pos)) lo = mid + 1;
        else met = true;
      }
      if (met) continue;
      done.append(nullptr);
      for (uint32_t i = done.size() - 1; i > lo; i--) done[i] = done[i - 1];
      done[lo] = key->value;
      res.append(e);
      Value r;
      st.callFunction(*op->value, *e, r, pos);
      st.forceList(r, pos, "while evaluating the return value of the `operator` passed to builtins.genericClosure");
      for (size_t i = 0; i < r.listSize(); i++) queue.append(r.list.elems[i]);
    }
    st.mkList(v, res);
  });

  // -- Environment -----------------------------------------------------------
  S.addPrimOp("__getEnv", [](EvalState &st, A args, Value &v, PosPtr pos) {
    composite::CharSeries name = composite::chars(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getEnv"));
    // A whole arena string is its own C string (copyString terminates it); only a window that is not followed by its NUL is copied.
    composite::Text copy;
    const char *cname = composite::facet<composite::text::Terminated>(name) ? name.data() : copy.assign(composite::view(name.window())).c_str();
    const char *e = st.settings.pureEval ? nullptr : getenv(cname);
    st.mkString(v, e ? e : "");
  });

  // -- Import ----------------------------------------------------------------
  S.addPrimOp("import", [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    composite::Text path = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.import");
    st.realiseContext(ctx, pos);
    Value *r = st.evalFile(path);
    st.forceValue(*r, pos);
    v = *r;
  });
  S.addPrimOp("scopedImport", [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos);
    NixStringContext ctx;
    composite::Text path = st.coerceToPath(*args[1], ctx, pos, "while evaluating the second argument passed to builtins.scopedImport");
    st.realiseContext(ctx, pos);
    composite::MutableSeries<composite::Text> names; // the scope's names in order: the cache key, and the names the file is lowered against
    for (const Attr *a : args[0]->attrs->lexicographicOrder(st.symbols)) names.append(composite::Text(st.symbols[a->name]));
    composite::Text real = st.resolveExprPath(st.realisePath(path, pos));
    composite::Text key = real.clone();
    for (auto &n : names) key.put('\n').put(n);
    Value *fn;
    if (Value **hit = st.scopedImportCache.find(key.data(), uint32_t(key.size()))) fn = *hit;
    else {
      composite::Text text;
      try {
        text = nixstore::readFile(real);
      } catch (nixstore::Error &e) {
        throw EvalError(e.what(), pos);
      }
      nixfe::Origin *origin = nixfe::newOrigin();
      origin->name = real.clone();
      origin->path = real.clone();
      origin->baseDir = nixstore::dirOf(real);
      origin->text = nixfe::Source::fromString(composite::mv(text));
      st.origins.append(origin);
      fn = st.evalExprOp(st.lowerToMLIR(origin, &names));
      st.scopedImportCache.set(key.data(), uint32_t(key.size()), fn, [&] { return st.copyString(key); });
    }
    st.callFunction(*fn, *args[0], v, pos);
  });
  S.addPrimOp("__findFile", [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[1], pos, "while evaluating the second argument passed to builtins.findFile");
    composite::Text p = st.findFile(*args[0], name, pos);
    st.mkPath(v, p);
  });
}

} // namespace nixev
