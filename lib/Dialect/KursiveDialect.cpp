//===- KursiveDialect.cpp - kursive combinators: re2mlir and kursive-to-program ----------------------------------===//
//
// re2mlir reads a POSIX extended regular expression (as libstdc++'s std::regex::extended reads it, Nix's
// builtins.match and builtins.split) into kursive combinators with a reader written in those combinators: the
// grammar lowered/kursive/Ere.mlir, compiled once by kursive-to-program and walked token by token by
// mlnix_kursive_walk (lowered/nixeval/KursiveOps.mlir).  The actions on the tokens count the tree nodes and the sets
// the old compiler made, so that the reader runs out of room (Space) exactly where it did, and rejects (Invalid) what
// it rejected, the first error winning.  kursive-to-program generates from the combinators the Step program of that
// compiler, step for step and set for set, as constant globals that the walk runs.
//
//===----------------------------------------------------------------------===//

#include "NixDialect/Kursive.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
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

template <class T> void global(OpBuilder &b, Location loc, StringRef name, Type elem, ArrayRef<T> xs) {
  auto type = MemRefType::get({int64_t(xs.size())}, elem);
  auto init = DenseElementsAttr::get(RankedTensorType::get({int64_t(xs.size())}, elem), xs);
  memref::GlobalOp::create(b, loc, name, b.getStringAttr("private"), type, init, /*constant=*/true, IntegerAttr());
}
// counts: nSteps, nSets, groups, loops, error
void counts(OpBuilder &b, Location loc, StringRef sym, ArrayRef<int32_t> c) {
  global(b, loc, (sym + "_counts").str(), b.getI32Type(), c);
}

/// kursive-to-program: each kursive.regex (and kursive.rejected) of m becomes the constant globals of its program.
LogicalResult toProgram(ModuleOp m, unsigned stepCap) {
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
    if (g.peg) return g.peg->emitError("kursive-to-program: an ordered choice (kursive.or without `longest`) has no Step form");
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
  return success();
}

/// The patterns' own context: the evaluator's may be in use.
MLIRContext &patternContext() {
  static MLIRContext ctx(MLIRContext::Threading::DISABLED);
  static bool loaded = (ctx.loadDialect<KursiveDialect, memref::MemRefDialect>(), true);
  (void)loaded;
  return ctx;
}

/// The ERE grammar (lowered/kursive/Ere.mlir), compiled once by kursive-to-program: @ere_main's and @ere_bracket's
/// Step programs, walked by mlnix_kursive_walk (lowered/nixeval/KursiveOps.mlir) from the reader's cursor.
struct Grammar {
  SmallVector<uint32_t> steps;
  SmallVector<uint64_t> sets;
  uint32_t counts[4] = {0, 0, 0, 0}; // steps, sets, groups, loops
  int err = Invalid;
};

Grammar readGrammar(ModuleOp m, StringRef sym) {
  Grammar p;
  for (auto g : m.getOps<memref::GlobalOp>()) {
    StringRef name = g.getSymName();
    if (!name.consume_front(sym)) continue;
    auto v = cast<DenseElementsAttr>(*g.getInitialValue());
    if (name == "_counts") {
      auto c = v.getValues<int32_t>();
      for (int i = 0; i < 4; i++) p.counts[i] = uint32_t(c[i]);
      p.err = c[4];
    } else if (name == "_steps") for (int32_t w : v.getValues<int32_t>()) p.steps.push_back(uint32_t(w));
    else if (name == "_sets") for (int64_t w : v.getValues<int64_t>()) p.sets.push_back(uint64_t(w));
  }
  return p;
}

extern "C" int32_t mlnix_kursive_walk(const void *steps, const void *sets, uint32_t groups, uint32_t loops,
    const char *text, uint32_t n, uint32_t start, int32_t exact, int32_t notNull,
    uint32_t *caps, uint32_t *best, void *loopsArr, void *stack, uint32_t cap, uint64_t *budget);

const Grammar *ereGrammars() {
  static const char *text =
#include "KursiveEre.inc"
      ;
  static Grammar g[2];
  static bool done = [] {
    OwningOpRef<ModuleOp> m = parseSourceString<ModuleOp>(text, &patternContext());
    if (!m || failed(toProgram(*m, 1 << 16))) llvm::report_fatal_error("kursive: the ERE grammar does not compile");
    g[0] = readGrammar(*m, "ere_main"), g[1] = readGrammar(*m, "ere_bracket");
    return true;
  }();
  (void)done;
  return g;
}

/// A pattern read token by token: each token is the longest match of the grammar at the cursor, and these are its
/// actions.  They count the tree nodes and the sets the old compiler made, so that the reader runs out of room (Space)
/// exactly where it did and rejects (Invalid) what it rejected, the first error winning.
struct Reader {
  enum Main { Dot = 1, Bracket = 2, Neg = 3, BolT = 4, EolT = 5, Open = 6, Close = 7, Bar = 8, Esc = 9, Escaped = 10,
              Quant = 11, Brace = 12, Lo = 13, Upper = 14, Hi = 15, Shut = 16, Byte = 17 };
  enum Br { Class = 1, Name = 2, BadClass = 3, Coll = 4, CollByte = 5, Equiv = 6, EquivByte = 7, BadColl = 8, Elem = 9 };
  StringRef s;
  OpBuilder &b;
  Location loc;
  uint32_t capNodes, capSets;
  size_t p = 0;
  uint32_t nodes = 0, sets = 0, groups = 0;
  Err fail = None;
  SmallVector<uint32_t> marks, best, loops, stack;
  uint32_t *m = nullptr; // the marks of the last token

  Type T() { return b.getType<StepType>(); }
  bool ok() const { return fail == None; }
  void bad(Err e) { if (fail == None) fail = e; }
  void node() { if (nodes == capNodes) bad(Space); else nodes++; }
  void set() { if (sets == capSets) bad(Space); else sets++; }
  bool has(unsigned g) const { return m[2 * g] != ~0u; }
  StringRef span(unsigned g) const { return s.slice(m[2 * g], m[2 * g + 1]); }
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

  /// The token at the cursor by grammar g (0 main, 1 bracket): the alternative that matched (0: none), its marks in m.
  /// A walk that runs out of checkpoints runs again with twice as many.
  unsigned token(unsigned which) {
    const Grammar &g = ereGrammars()[which];
    uint32_t slots = 2 * (g.counts[2] + 1);
    marks.resize(slots), best.resize(slots), loops.resize(2 * g.counts[3] + 2);
    if (stack.empty()) stack.resize(3 * 256);
    for (;;) {
      uint64_t budget = ~uint64_t(0);
      int32_t r = mlnix_kursive_walk(g.steps.data(), g.sets.data(), g.counts[2], g.counts[3], s.data(), uint32_t(s.size()),
          uint32_t(p), 0, 1, marks.data(), best.data(), loops.data(), stack.data(), uint32_t(stack.size() / 3), &budget);
      if (r == 2) { stack.resize(2 * stack.size()); continue; }
      m = best.data();
      if (r == 0) return 0;
      for (unsigned k = 1; k <= g.counts[2]; k++)
        if (has(k)) return k;
      return 0;
    }
  }

  bool number(StringRef digits, uint32_t &v) {
    if (digits.empty()) return false;
    v = 0;
    for (char d : digits)
      if ((v = v * 10 + uint32_t(d - '0')) > 100000) return bad(Space), false;
    return true;
  }

  /// A bracket expression, after its '[' (and '^'): a ']' first is a member, a '-' first or last too; a '-' after a
  /// byte and before an element is a range.
  Value bracket(bool neg) {
    uint64_t w[4] = {0, 0, 0, 0};
    bool first = true;
    int prev = -1; // the last single byte added, a range's possible start
    auto elem = [&](unsigned k) { return k == Elem ? int((unsigned char)s[m[0]]) : k == Coll ? int((unsigned char)s[m[2 * CollByte]])
                                       : k == Equiv ? int((unsigned char)s[m[2 * EquivByte]]) : -1; };
    for (;;) {
      if (p == s.size()) return bad(Invalid), Value();
      unsigned k = token(1);
      if (k == Elem && s[p] == ']' && !first) break;
      if (k == Class || k == BadClass) {
        if (k == BadClass || classMember(span(Name), 0) < 0) return bad(Invalid), Value();
        for (unsigned c = 0; c < 256; c++)
          if (classMember(span(Name), c) > 0) w[c >> 6] |= uint64_t(1) << (c & 63);
        p = m[1], prev = -1, first = false;
        continue;
      }
      int c = elem(k);
      if (c < 0) return bad(Invalid), Value();
      p = m[1];
      if (c == '-' && !first && prev >= 0 && p < s.size() && s[p] != ']') { // a range from the byte before to the byte after
        k = token(1);
        int hi = elem(k);
        if (k == Class || k == BadClass || hi < prev) return bad(Invalid), Value();
        p = m[1];
        for (int x = prev; x <= hi; x++) w[x >> 6] |= uint64_t(1) << (x & 63);
        prev = -1;
      } else w[c >> 6] |= uint64_t(1) << (c & 63), prev = c;
      first = false;
    }
    p++;
    if (neg) for (auto &x : w) x = ~x;
    set(), node();
    return ok() ? setOf(w) : Value();
  }

  /// An alternation being read: the top's, or a group's.
  struct Frame {
    SmallVector<Value> alts, items;
    SmallString<16> run;
    bool any = false;
    uint32_t group = 0;
  };
  Value pend; // the atom whose repetitions may follow
  bool pending = false, assertion = false;

  void atom(Value v, bool anchor = false) { pend = v, pending = true, assertion = anchor; }
  // The atom with its repetitions joins the sequence (the compiler's Cat after the first).
  void endAtom(Frame &f) {
    if (!pending) return;
    pending = false;
    if (f.any) node();
    f.any = true;
    if (pend) f.items.push_back(pend);
  }
  // Bytes in a row with no repetition after them are one kursive.lit; a sequence of nothing is kursive.empty.
  void endSequence(Frame &f) {
    endAtom(f);
    flush(f.run, f.items);
    Value v;
    if (!f.any) { node(); if (ok()) v = EmptyOp::create(b, loc, T()); }
    else v = f.items.size() == 1 ? f.items[0] : ThenOp::create(b, loc, T(), f.items).getResult();
    f.alts.push_back(v), f.items.clear(), f.any = false;
    if (f.alts.size() > 1) node(); // the compiler's alternation node
  }
  Value endAlternation(Frame &f) {
    endSequence(f);
    if (!ok()) return Value();
    return f.alts.size() == 1 ? f.alts[0] : OrOp::create(b, loc, T(), f.alts, /*longest=*/true).getResult();
  }

  Value read() {
    SmallVector<Frame, 4> st(1);
    while (ok()) {
      Frame &f = st.back();
      if (p == s.size()) {
        Value v = endAlternation(f);
        if (st.size() > 1) bad(Invalid); // a '(' with no ')'
        return ok() ? v : Value();
      }
      unsigned k = token(0);
      size_t end = m[1];
      if (k == Quant || k == Brace) { // a repetition of the atom before it
        if (!pending || assertion) return bad(Invalid), Value(); // nothing to repeat; an anchor takes no quantifier
        uint32_t lo = s[p] == '+', hi = s[p] == '?' ? 1 : kUnbounded;
        if (k == Brace) {
          if (!number(span(Lo), lo)) return bad(Invalid), Value();
          hi = lo;
          if (has(Upper) && !number(span(Hi), hi)) hi = kUnbounded;
          if (!ok()) return Value();
          if (!has(Shut) || (hi != kUnbounded && hi < lo)) return bad(Invalid), Value();
        }
        p = end, node();
        if (ok()) pend = RepeatOp::create(b, loc, T(), pend, lo, int32_t(hi));
        continue;
      }
      if (k == Bar) { p = end; endSequence(f); continue; }
      if (k == Close) {
        Value inner = endAlternation(f);
        if (st.size() == 1) return bad(Invalid), Value(); // a ')' with no '('
        if (!ok()) return Value();
        uint32_t g = f.group;
        st.pop_back();
        p = end, node();
        if (ok()) atom(GroupOp::create(b, loc, T(), inner, g));
        continue;
      }
      if (!k) return bad(Invalid), Value(); // a '\' before an ordinary character, or at the end (Nix's strict libstdc++)
      endAtom(f);
      if (k == Byte || k == Esc) { // a byte: in the run, or a set of its own if a repetition follows
        unsigned c = (unsigned char)s[k == Esc ? m[2 * Escaped] : p];
        p = end, set(), node();
        if (!ok()) return Value();
        if (p < s.size() && StringRef("*+?{").contains(s[p])) flush(f.run, f.items), atom(byteOf(c));
        else f.run.push_back(char(c)), atom(Value());
        continue;
      }
      flush(f.run, f.items);
      p = end;
      switch (k) {
      case Dot: { // any byte but NUL, as libstdc++'s POSIX '.'
        uint64_t w[4] = {~uint64_t(1), ~uint64_t(0), ~uint64_t(0), ~uint64_t(0)};
        set(), node();
        if (ok()) atom(setOf(w));
        break;
      }
      case Bracket: { Value v = bracket(has(Neg)); if (ok()) atom(v); break; }
      case BolT: node(); if (ok()) atom(BolOp::create(b, loc, T()), true); break;
      case EolT: node(); if (ok()) atom(EolOp::create(b, loc, T()), true); break;
      case Open: st.emplace_back().group = ++groups; break;
      }
    }
    return Value();
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
      Value top = r.read();
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
  void runOnOperation() override {
    if (failed(toProgram(getOperation(), stepCap))) signalPassFailure();
  }
};
} // namespace

int mlir::kursive::compileProgram(StringRef re, unsigned poolCap, unsigned capSteps, unsigned capSets, uint32_t *steps,
                                  uint64_t *sets, uint32_t counts[4]) {
  MLIRContext &ctx = patternContext();
  OpBuilder b(&ctx);
  OwningOpRef<ModuleOp> m = ModuleOp::create(b.getUnknownLoc());
  b.setInsertionPointToEnd(m->getBody());
  PatternOp::create(b, b.getUnknownLoc(), "x", re);
  PassManager pm(&ctx);
  auto r = std::make_unique<Re2MlirPass>();
  r->poolCap = poolCap, r->setCap = capSets;
  auto k = std::make_unique<KursiveToProgramPass>();
  k->stepCap = capSteps;
  pm.addPass(std::move(r)), pm.addPass(std::move(k));
  if (failed(pm.run(*m))) llvm::report_fatal_error("kursive: the passes failed on a pattern re2mlir read");
  Grammar g = readGrammar(*m, "x");
  for (int i = 0; i < 4; i++) counts[i] = g.counts[i];
  for (size_t i = 0; i < g.steps.size(); i++) steps[i] = g.steps[i];
  for (size_t i = 0; i < g.sets.size(); i++) sets[i] = g.sets[i];
  return g.err;
}

void mlir::kursive::registerKursivePasses() {
  PassRegistration<Re2MlirPass>();
  PassRegistration<KursiveToProgramPass>();
}
