//===- KursiveDialect.cpp - kursive combinators: re2mlir and kursive-to-program ----------------------------------===//
//
// re2mlir reads a POSIX extended regular expression with the grammar of Kursive.h's compiler (as libstdc++'s
// std::regex::extended reads it, Nix's builtins.match and builtins.split) into kursive combinators.  It counts the tree
// nodes and the sets that compiler made, so that it runs out of room (Space) exactly where the compiler did, and it
// rejects (Invalid) what the compiler rejected, the first error winning.  kursive-to-program generates from the
// combinators the Step program of that compiler, step for step and set for set, as constant globals that
// mlnix_kursive_walk (lowered/nixeval/KursiveOps.mlir) runs.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kursive.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/TypeSwitch.h"

#include "NixDialect/KursiveDialect.cpp.inc"
#define GET_TYPEDEF_CLASSES
#include "NixDialect/KursiveTypes.cpp.inc"
#define GET_OP_CLASSES
#include "NixDialect/Kursive.cpp.inc"

using namespace mlir;
using namespace mlir::kursive;

void KursiveDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "NixDialect/KursiveTypes.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "NixDialect/Kursive.cpp.inc"
      >();
}

namespace {
enum Err : int32_t { None, Invalid, Space };
constexpr uint32_t kUnbounded = ~0u;

// C-locale character classes: what regex_traits<char> answers for a byte under the C locale.  -1: no such class.
int classMember(StringRef name, unsigned c) {
  bool upper = c >= 'A' && c <= 'Z', lower = c >= 'a' && c <= 'z', digit = c >= '0' && c <= '9';
  bool alpha = upper || lower, alnum = alpha || digit, space = c == ' ' || (c >= '\t' && c <= '\r');
  bool print = c >= 0x20 && c < 0x7f, graph = c > 0x20 && c < 0x7f, cntrl = c < 0x20 || c == 0x7f;
  bool xdigit = digit || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
  return llvm::StringSwitch<int>(name)
      .Case("alnum", alnum).Case("alpha", alpha).Case("digit", digit).Case("d", digit).Case("space", space).Case("s", space).Case("upper", upper)
      .Case("lower", lower).Case("xdigit", xdigit).Case("blank", c == ' ' || c == '\t').Case("punct", graph && !alnum)
      .Case("print", print).Case("graph", graph).Case("cntrl", cntrl).Case("w", alnum || c == '_').Default(-1);
}

/// One atom as read: a combinator, or a byte not yet one (a run of bytes becomes one kursive.lit).
struct Atom {
  Value v;
  int byte = -1;
  bool assertion = false;
};

struct Reader {
  StringRef s;
  OpBuilder &b;
  Location loc;
  uint32_t capNodes, capSets;
  size_t p = 0;
  uint32_t nodes = 0, sets = 0, groups = 0;
  Err fail = None;

  Type T() { return b.getType<StepType>(); }
  bool ok() const { return fail == None; }
  void bad(Err e) { if (fail == None) fail = e; }
  void node() { if (nodes == capNodes) bad(Space); else nodes++; }
  void set() { if (sets == capSets) bad(Space); else sets++; }
  int at(size_t i) const { return i < s.size() ? (unsigned char)s[i] : -1; }
  bool is(char c) const { return at(p) == (unsigned char)c; }
  static bool special(int e) { return e > 0 && StringRef(".[\\()*+?{|^$").contains(char(e)); }
  Value setOf(const uint64_t w[4]) {
    return SetOp::create(b, loc, T(), ArrayRef<int64_t>{int64_t(w[0]), int64_t(w[1]), int64_t(w[2]), int64_t(w[3])});
  }
  Value byteOf(unsigned c) {
    uint64_t w[4] = {0, 0, 0, 0};
    w[c >> 6] |= uint64_t(1) << (c & 63);
    return setOf(w);
  }
  void flush(SmallString<16> &run, SmallVector<Value> &items) {
    if (run.size() == 1) items.push_back(byteOf((unsigned char)run[0]));
    else if (!run.empty()) items.push_back(LitOp::create(b, loc, T(), b.getStringAttr(run)));
    run.clear();
  }

  // One byte of a bracket expression: [. .] or [= =] name one byte (-1: malformed), else the byte itself.
  int element() {
    if (is('[') && (at(p + 1) == '.' || at(p + 1) == '=')) {
      int kind = at(p + 1);
      if (at(p + 3) != kind || at(p + 4) != ']') return -1;
      int c = at(p + 2);
      p += 5;
      return c;
    }
    return at(p++);
  }

  // A bracket expression, after its '[': a backslash in it is a byte like any other (POSIX), ']' first is a member,
  // '-' first or last too.
  Value bracket() {
    uint64_t w[4] = {0, 0, 0, 0};
    bool neg = is('^'), first = true;
    if (neg) p++;
    int prev = -1; // the last single byte added, a range's possible start
    while (p < s.size() && (first || !is(']'))) {
      if (is('[') && at(p + 1) == ':') {
        size_t q = p + 2, name = q;
        while (q + 1 < s.size() && !(s[q] == ':' && s[q + 1] == ']')) q++;
        if (q + 1 >= s.size() || classMember(s.slice(name, q), 0) < 0) return bad(Invalid), Value();
        for (unsigned c = 0; c < 256; c++)
          if (classMember(s.slice(name, q), c) > 0) w[c >> 6] |= uint64_t(1) << (c & 63);
        p = q + 2, prev = -1, first = false;
        continue;
      }
      int c = element();
      if (c < 0) return bad(Invalid), Value();
      if (c == '-' && !first && prev >= 0 && p < s.size() && !is(']')) { // a range from the byte before to the byte after
        if (is('[') && at(p + 1) == ':') return bad(Invalid), Value();
        int hi = element();
        if (hi < prev) return bad(Invalid), Value();
        for (int k = prev; k <= hi; k++) w[k >> 6] |= uint64_t(1) << (k & 63);
        prev = -1;
      } else w[c >> 6] |= uint64_t(1) << (c & 63), prev = c;
      first = false;
    }
    if (!is(']')) return bad(Invalid), Value();
    p++;
    if (neg) for (auto &x : w) x = ~x;
    set(), node();
    return ok() ? setOf(w) : Value();
  }

  bool number(uint32_t &v) {
    if (!(at(p) >= '0' && at(p) <= '9')) return false;
    v = 0;
    while (at(p) >= '0' && at(p) <= '9') {
      v = v * 10 + uint32_t(s[p++] - '0');
      if (v > 100000) return bad(Space), false;
    }
    return true;
  }

  Atom atom() {
    int c = at(p++);
    switch (c) {
    case '.': { // any byte but NUL, as libstdc++'s POSIX '.'
      uint64_t w[4] = {~uint64_t(1), ~uint64_t(0), ~uint64_t(0), ~uint64_t(0)};
      set(), node();
      return {ok() ? setOf(w) : Value()};
    }
    case '[': return {bracket()};
    case '^': node(); return {ok() ? BolOp::create(b, loc, T()).getResult() : Value(), -1, true};
    case '$': node(); return {ok() ? EolOp::create(b, loc, T()).getResult() : Value(), -1, true};
    case '(': {
      uint32_t g = ++groups;
      Value inner;
      if (is(')')) { node(); if (ok()) inner = EmptyOp::create(b, loc, T()); }
      else inner = alternation();
      if (!ok()) return {};
      if (!is(')')) return bad(Invalid), Atom();
      p++;
      node();
      return {ok() ? GroupOp::create(b, loc, T(), inner, g).getResult() : Value()};
    }
    case '\\': { // only a special character may be escaped: Nix's libstdc++ is built strict (__STRICT_ANSI__)
      int e = at(p);
      if (e < 0 || (p++, !special(e))) return bad(Invalid), Atom();
      set(), node();
      return {Value(), e};
    }
    case '*': case '+': case '?': case '{': case ')': case '|': return bad(Invalid), Atom(); // nothing to repeat
    default: set(), node(); return {Value(), c};
    }
  }

  Value postfix(Value a, bool assertion) {
    while (p < s.size() && ok()) {
      uint32_t lo, hi;
      if (is('*')) lo = 0, hi = kUnbounded;
      else if (is('+')) lo = 1, hi = kUnbounded;
      else if (is('?')) lo = 0, hi = 1;
      else if (is('{')) {
        if (assertion) return bad(Invalid), Value();
        p++;
        if (!number(lo)) return bad(Invalid), Value();
        hi = lo;
        if (is(',')) { p++; if (!number(hi)) hi = kUnbounded; }
        if (!ok()) return Value();
        if (!is('}') || (hi != kUnbounded && hi < lo)) return bad(Invalid), Value();
        p++, node();
        if (ok()) a = RepeatOp::create(b, loc, T(), a, lo, int32_t(hi));
        continue;
      } else break;
      if (assertion) return bad(Invalid), Value(); // libstdc++: an anchor takes no quantifier
      p++, node();
      if (ok()) a = RepeatOp::create(b, loc, T(), a, lo, int32_t(hi));
    }
    return a;
  }

  // Atoms with their repetitions; bytes in a row with no repetition after them become one kursive.lit.
  Value sequence() {
    SmallVector<Value> items;
    SmallString<16> run;
    bool any = false;
    while (p < s.size() && !is('|') && !is(')') && ok()) {
      int c = at(p);
      bool plain = !StringRef(".[^$(*+?{)|\\").contains(char(c)) || (c == '\\' && special(at(p + 1)));
      if (!plain) flush(run, items);
      Atom a = atom();
      if (!ok()) return Value();
      if (a.byte >= 0) {
        if (StringRef("*+?{").contains(char(at(p))) && p < s.size()) flush(run, items), a.v = byteOf(unsigned(a.byte));
        else run.push_back(char(a.byte));
      }
      Value v = postfix(a.v, a.assertion);
      if (!ok()) return Value();
      if (any) node(); // the compiler's Cat
      any = true;
      if (v) items.push_back(v);
    }
    if (!ok()) return Value();
    flush(run, items);
    if (!any) {
      node();
      return ok() ? EmptyOp::create(b, loc, T()).getResult() : Value();
    }
    return items.size() == 1 ? items[0] : ThenOp::create(b, loc, T(), items).getResult();
  }

  Value alternation() {
    SmallVector<Value> alts{sequence()};
    while (is('|') && ok()) {
      p++;
      alts.push_back(sequence());
      node();
    }
    if (!ok()) return Value();
    return alts.size() == 1 ? alts[0] : OrOp::create(b, loc, T(), alts, /*longest=*/true).getResult();
  }
};

struct Re2MlirPass : PassWrapper<Re2MlirPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Re2MlirPass)
  Re2MlirPass() = default;
  Re2MlirPass(const Re2MlirPass &o) : PassWrapper(o) {}
  StringRef getArgument() const override { return "re2mlir"; }
  StringRef getDescription() const override {
    return "Read each kursive.pattern (a POSIX extended regular expression) into kursive combinators, or reject it";
  }
  Option<unsigned> poolCap{*this, "pool-cap", llvm::cl::desc("tree nodes the compiler had room for"), llvm::cl::init(1 << 16)};
  Option<unsigned> setCap{*this, "set-cap", llvm::cl::desc("sets the compiler had room for"), llvm::cl::init(4096)};
  void runOnOperation() override {
    SmallVector<PatternOp> patterns(getOperation().getOps<PatternOp>());
    for (PatternOp pat : patterns) {
      OpBuilder b(pat);
      auto regex = RegexOp::create(b, pat.getLoc(), pat.getSymName(), 0u);
      Block *body = b.createBlock(&regex.getBody());
      Reader r{pat.getSource(), b, pat.getLoc(), poolCap, setCap};
      Value top = r.alternation();
      if (r.ok() && r.p != r.s.size()) r.bad(Invalid); // a ')' with no '(' before it
      if (r.ok()) {
        b.setInsertionPointToEnd(body);
        YieldOp::create(b, pat.getLoc(), top);
        regex.setGroups(r.groups);
      } else {
        b.setInsertionPoint(regex);
        RejectedOp::create(b, pat.getLoc(), pat.getSymName(), pat.getSource(), r.fail == Space ? "space" : "invalid");
        regex.erase();
      }
      pat.erase();
    }
  }
};

/// Kursive.h's Step ops and the code generator over the combinators.
enum StepOp : uint32_t { Char, Alt, Rep, Jmp, Save, Bol, Eol, Match };

struct Gen {
  uint32_t cap = 0;
  DenseMap<Operation *, uint32_t> setOf; // a kursive.set's slot, a kursive.lit's first slot
  SmallVector<uint32_t> steps;           // 4 words a step: op, x, y, z
  uint32_t loops = 0;
  Err fail = None;
  Operation *peg = nullptr;

  uint32_t n() const { return uint32_t(steps.size() / 4); }
  uint32_t emit(uint32_t op, uint32_t x = 0) {
    if (n() == cap) { fail = Space; return 0; }
    steps.append({op, x, 0, 0});
    return n() - 1;
  }
  // One repeat state: its body, then the way out; a loop's body jumps back to it.
  void repeat(Value body, bool loop) {
    uint32_t r = emit(Rep);
    if (fail) return;
    steps[4 * r + 3] = loops++, steps[4 * r + 1] = n();
    gen(body);
    if (loop) emit(Jmp, r);
    if (!fail) steps[4 * r + 2] = n();
  }
  // alt L1 L2; L1: the first k - 1 alternatives; jmp end; L2: the k-th; end:  (a|b|c is (a|b)|c)
  void alternatives(OperandRange xs, size_t k) {
    if (k == 1) return gen(xs[0]);
    uint32_t alt = emit(Alt);
    if (fail) return;
    steps[4 * alt + 1] = n();
    alternatives(xs, k - 1);
    uint32_t jmp = emit(Jmp);
    if (fail) return;
    steps[4 * alt + 2] = n();
    gen(xs[k - 1]);
    steps[4 * jmp + 1] = n();
  }
  void gen(Value v) {
    if (fail) return;
    Operation *op = v.getDefiningOp();
    llvm::TypeSwitch<Operation *>(op)
        .Case([&](SetOp o) { emit(Char, setOf[op]); })
        .Case([&](LitOp o) { for (uint32_t k = 0; k < o.getBytes().size() && !fail; k++) emit(Char, setOf[op] + k); })
        .Case([&](ThenOp o) { for (Value x : o.getSteps()) gen(x); })
        .Case([&](OrOp o) {
          if (!o.getLongest()) peg = op;
          else alternatives(o.getSteps(), o.getSteps().size());
        })
        .Case([&](RepeatOp o) {
          uint32_t lo = uint32_t(o.getMin()), hi = uint32_t(o.getMax());
          for (uint32_t k = 0; k < lo && !fail; k++) gen(o.getBody());
          if (hi == kUnbounded) repeat(o.getBody(), true);
          else for (uint32_t k = lo; k < hi && !fail; k++) repeat(o.getBody(), false); // each optional copy its own state
        })
        .Case([&](GroupOp o) {
          emit(Save, 2 * uint32_t(o.getIndex()));
          gen(o.getBody());
          emit(Save, 2 * uint32_t(o.getIndex()) + 1);
        })
        .Case([&](BolOp) { emit(Bol); })
        .Case([&](EolOp) { emit(Eol); })
        .Default([](Operation *) {}); // kursive.empty
  }
};

struct KursiveToProgramPass : PassWrapper<KursiveToProgramPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(KursiveToProgramPass)
  KursiveToProgramPass() = default;
  KursiveToProgramPass(const KursiveToProgramPass &o) : PassWrapper(o) {}
  StringRef getArgument() const override { return "kursive-to-program"; }
  StringRef getDescription() const override {
    return "Lower each kursive.regex to the constant globals of its Step program (@X_steps, @X_sets, @X_counts)";
  }
  void getDependentDialects(DialectRegistry &registry) const override { registry.insert<memref::MemRefDialect>(); }
  Option<unsigned> stepCap{*this, "step-cap", llvm::cl::desc("steps the program has room for"), llvm::cl::init(1 << 16)};

  template <class T> static void global(OpBuilder &b, Location loc, StringRef name, Type elem, ArrayRef<T> xs) {
    auto type = MemRefType::get({int64_t(xs.size())}, elem);
    auto init = DenseElementsAttr::get(RankedTensorType::get({int64_t(xs.size())}, elem), xs);
    memref::GlobalOp::create(b, loc, name, b.getStringAttr("private"), type, init, /*constant=*/true, IntegerAttr());
  }
  // counts: nSteps, nSets, groups, loops, error
  static void counts(OpBuilder &b, Location loc, StringRef sym, ArrayRef<int32_t> c) {
    global(b, loc, (sym + "_counts").str(), b.getI32Type(), c);
  }

  void runOnOperation() override {
    ModuleOp m = getOperation();
    for (RejectedOp r : llvm::make_early_inc_range(m.getOps<RejectedOp>())) {
      OpBuilder b(r);
      counts(b, r.getLoc(), r.getSymName(), {0, 0, 0, 0, r.getError() == "space" ? Space : Invalid});
      r.erase();
    }
    for (RegexOp x : llvm::make_early_inc_range(m.getOps<RegexOp>())) {
      Gen g;
      g.cap = stepCap;
      SmallVector<int64_t> sets; // the set table, in the order the slots stand
      auto add = [&](unsigned c) { sets.append({0, 0, 0, 0}); sets[sets.size() - 4 + (c >> 6)] |= int64_t(uint64_t(1) << (c & 63)); };
      for (Operation &op : x.getBody().front()) {
        if (auto s = dyn_cast<SetOp>(op)) g.setOf[&op] = uint32_t(sets.size() / 4), sets.append(s.getWords().begin(), s.getWords().end());
        else if (auto l = dyn_cast<LitOp>(op)) {
          g.setOf[&op] = uint32_t(sets.size() / 4);
          for (char c : l.getBytes()) add((unsigned char)c);
        }
      }
      auto yield = cast<YieldOp>(x.getBody().front().getTerminator());
      g.emit(Save, 0);
      g.gen(yield.getStep());
      g.emit(Save, 1);
      g.emit(Match);
      if (g.peg) {
        g.peg->emitError("kursive-to-program: an ordered choice (kursive.or without `longest`) has no Step form");
        return signalPassFailure();
      }
      OpBuilder b(x);
      StringRef sym = x.getSymName();
      if (g.fail) counts(b, x.getLoc(), sym, {0, 0, 0, 0, Space});
      else {
        SmallVector<int32_t> words(g.steps.begin(), g.steps.end());
        global(b, x.getLoc(), (sym + "_steps").str(), b.getI32Type(), ArrayRef<int32_t>(words));
        if (!sets.empty()) global(b, x.getLoc(), (sym + "_sets").str(), b.getI64Type(), ArrayRef<int64_t>(sets));
        counts(b, x.getLoc(), sym, {int32_t(g.n()), int32_t(sets.size() / 4), int32_t(x.getGroups()), int32_t(g.loops), None});
      }
      x.erase();
    }
  }
};
} // namespace

void mlir::kursive::registerKursivePasses() {
  PassRegistration<Re2MlirPass>();
  PassRegistration<KursiveToProgramPass>();
}
