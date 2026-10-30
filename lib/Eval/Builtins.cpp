//===- Builtins.cpp - The Nix builtins (language-level) -------------------===//

#include "Composite/CharSeries.h"
#include "Composite/Kursive.h"
#include "Composite/Mutable.h"
#include "Nix/Eval.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cmath>
#include <ctime>
#include <dirent.h>
#include <iostream>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

using namespace mlir;
namespace nd = mlir::nix;

namespace nixev {

void registerStoreBuiltins(EvalState &state);
void registerFormatBuiltins(EvalState &state);

static std::string str(std::string_view s) { return std::string(s); }

//===----------------------------------------------------------------------===//
// Version comparison (upstream names.cc)
//===----------------------------------------------------------------------===//

static std::string_view nextComponent(std::string_view::const_iterator &p, const std::string_view::const_iterator end) {
  while (p != end && (*p == '.' || *p == '-')) ++p;
  if (p == end) return "";
  auto s = p;
  if (isdigit((unsigned char)*p))
    while (p != end && isdigit((unsigned char)*p)) p++;
  else
    while (p != end && (!isdigit((unsigned char)*p) && *p != '.' && *p != '-')) p++;
  return std::string_view(&*s, p - s);
}

static bool componentsLT(std::string_view c1, std::string_view c2) {
  auto toInt = [](std::string_view s, long long &n) {
    if (s.empty()) return false;
    for (char c : s)
      if (!isdigit((unsigned char)c)) return false;
    n = std::stoll(std::string(s));
    return true;
  };
  long long n1, n2;
  bool i1 = toInt(c1, n1), i2 = toInt(c2, n2);
  if (i1 && i2) return n1 < n2;
  if (c1.empty() && i2) return true;
  if (c1 == "pre" && c2 != "pre") return true;
  if (c2 == "pre") return false;
  if (i1) return false;
  if (i2) return true;
  return c1 < c2;
}

static int compareVersions(std::string_view v1, std::string_view v2) {
  auto p1 = v1.begin(), p2 = v2.begin();
  while (p1 != v1.end() || p2 != v2.end()) {
    auto c1 = nextComponent(p1, v1.end());
    auto c2 = nextComponent(p2, v2.end());
    if (componentsLT(c1, c2)) return -1;
    if (componentsLT(c2, c1)) return 1;
  }
  return 0;
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
  static ku::detail::Node pool[1 << 16];
  ku::Program scratch{steps, 0, 1 << 16, sets, 0, 4096};
  ku::compile(re.data(), uint32_t(re.size()), scratch, pool, 1 << 16);
  if (scratch.error == ku::Error::Space) throw EvalError("memory limit exceeded by regular expression '" + str(re) + "'", pos);
  if (scratch.error != ku::Error::None) throw EvalError("invalid regular expression '" + str(re) + "'", pos);
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
    if (s.budget == 0 || k.stack.size() >= (1u << 26)) throw EvalError("memory limit exceeded by regular expression '" + str(re) + "'", pos);
    k.stack.resize(k.stack.size() * 2);
  }
}

/// A piece of the input of a match or a split: a window on its bytes when they are an arena string's, which stay; a copy when they are the
/// text a coercion made in `scratch`.
static Value *pieceOf(EvalState &st, std::string_view s, size_t b, size_t n, const std::string &scratch) {
  std::string_view piece = s.substr(b, n);
  return s.data() == scratch.data() ? st.newString(piece) : st.newStringWindow(piece);
}

/// The groups of a walk's answer as Nix gives them: each group's text, or null where it took no part.
static void kursiveGroups(EvalState &st, Value &v, const ku::Program &p, std::string_view s, const std::string &scratch) {
  const uint32_t *best = kursiveScratch().best.data();
  st.mkList(v, p.groups |cp::j| [&](uint32_t i) -> Value * {
    uint32_t b = best[2 * (i + 1)], e = best[2 * (i + 1) + 1];
    if (b == ~0u || e == ~0u) { Value *n = st.allocValue(); st.mkNull(*n); return n; }
    return pieceOf(st, s, b, e - b, scratch);
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
  BindingsBuilder bb(*this);
  for (auto &e : baseEnv) {
    llvm::StringRef name = e.getKey();
    if (name.starts_with("__")) name = name.drop_front(2);
    bb.insert(name, e.getValue());
  }
  builtinsAttrs = bb.finish();
  mkAttrs(*builtinsV, builtinsAttrs);
}

void registerBuiltins(EvalState &state) {
  using A = Value **;
  auto &S = state;

  // -- Control -----------------------------------------------------------
  S.addPrimOp("abort", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos, "while evaluating the error message passed to builtins.abort");
    throw Abort("evaluation aborted with the following error message: '" + s + "'", pos);
  });
  S.addPrimOp("throw", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos, "while evaluating the error message passed to builtin.throw");
    throw ThrownError(s, pos);
  });
  S.addPrimOp("__addErrorContext", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    try {
      st.forceValue(*args[1], pos);
      v = *args[1];
    } catch (EvalError &e) {
      NixStringContext ctx;
      auto msg = st.coerceToString(*args[0], ctx, false, false, pos);
      e.addTrace(nullptr, msg);
      throw;
    }
  });
  S.addPrimOp("__tryEval", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
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
  S.addPrimOp("__seq", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__deepSeq", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValueDeep(*args[0]);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__trace", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::String) st.printTrace("trace: " + str(args[0]->sv()));
    else st.printTrace("trace: " + st.printValueForTrace(*args[0]));
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__traceVerbose", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    if (st.settings.traceVerbose) {
      st.forceValue(*args[0], pos);
      if (args[0]->type == VType::String) st.printTrace("trace: " + str(args[0]->sv()));
      else st.printTrace("trace: " + st.printValueForTrace(*args[0]));
    }
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("__warn", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto msg = st.forceString(*args[0], pos, "while evaluating the first argument; the message passed to builtins.warn");
    std::cerr << "evaluation warning: " << msg << std::endl;
    if (st.settings.abortOnWarn) throw EvalError(str(msg), pos);
    st.forceValue(*args[1], pos);
    v = *args[1];
  });
  S.addPrimOp("break", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    v = *args[0];
  });

  // -- Types ---------------------------------------------------------------
  auto typePred = [&]<VType T>(const char *name, K<T>) {
    S.addPrimOp(name, 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      st.mkBool(v, args[0]->type == T);
    });
  };
  typePred("isNull", K<VType::Null>{});
  S.addPrimOp("__isFunction", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.mkBool(v, args[0]->isFunction());
  });
  typePred("__isInt", K<VType::Int>{});
  typePred("__isFloat", K<VType::Float>{});
  typePred("__isString", K<VType::String>{});
  typePred("__isBool", K<VType::Bool>{});
  typePred("__isPath", K<VType::Path>{});
  typePred("__isAttrs", K<VType::Attrs>{});
  typePred("__isList", K<VType::List>{});
  S.addPrimOp("__typeOf", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.mkString(v, EvalState::typeOf(*args[0]));
  });

  // -- Arithmetic ------------------------------------------------------------
  auto arith = [&]<char op>(const char *name, K<op>) {
    S.addPrimOp(name, 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
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
      int64_t r;
      bool of = false;
      const char *verb = "";
      switch (op) {
      case '+': of = __builtin_add_overflow(x, y, &r); verb = "adding"; break;
      case '-': of = __builtin_sub_overflow(x, y, &r); verb = "subtracting"; break;
      case '*': of = __builtin_mul_overflow(x, y, &r); verb = "multiplying"; break;
      default:
        if (y == 0) throw EvalError("division by zero", pos);
        if (x == INT64_MIN && y == -1) { of = true; verb = "dividing"; r = 0; }
        else r = x / y;
      }
      if (of) {
        const char *sym = op == '+' ? " + " : op == '-' ? " - " : op == '*' ? " * " : " / ";
        throw EvalError(std::string("integer overflow in ") + verb + " " + std::to_string(x) + sym + std::to_string(y), pos);
      }
      st.mkInt(v, r);
    });
  };
  arith("__add", K<'+'>{});
  arith("__sub", K<'-'>{});
  arith("__mul", K<'*'>{});
  arith("__div", K<'/'>{});
  auto bitop = [&]<char op>(const char *name, K<op>) {
    S.addPrimOp(name, 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
      int64_t a = st.forceInt(*args[0], pos), b = st.forceInt(*args[1], pos);
      st.mkInt(v, op == '&' ? (a & b) : op == '|' ? (a | b) : (a ^ b));
    });
  };
  bitop("__bitAnd", K<'&'>{});
  bitop("__bitOr", K<'|'>{});
  bitop("__bitXor", K<'^'>{});
  S.addPrimOp("__lessThan", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.mkBool(v, st.lessThan(*args[0], *args[1], pos));
  });
  auto rounding = [&]<bool up>(const char *name, K<up>) {
    S.addPrimOp(name, 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      if (args[0]->type == VType::Int) { v = *args[0]; return; }
      double d = st.forceFloat(*args[0], pos);
      double r = up ? std::ceil(d) : std::floor(d);
      if (!(r >= -9223372036854775808.0 && r < 9223372036854775808.0))
        throw EvalError("NixFloat argument " + std::to_string(d) + " is not in the range of NixInt", pos);
      st.mkInt(v, (int64_t)r);
    });
  };
  rounding("__ceil", K<true>{});
  rounding("__floor", K<false>{});

  // -- Strings ---------------------------------------------------------------
  S.addPrimOp("toString", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, true, false, pos, "while evaluating the first argument passed to builtins.toString", scratch);
    mkSharedString(st, v, *args[0], w, ctx);
  });
  S.addPrimOp("__stringLength", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "while evaluating the argument passed to builtins.stringLength", scratch);
    st.mkInt(v, (int64_t)w.size());
  });
  S.addPrimOp("__substring", 3, [](EvalState &st, A args, Value &v, PosPtr pos) {
    int64_t start = st.forceInt(*args[0], pos, "while evaluating the first argument (the start offset) passed to builtins.substring");
    if (start < 0) throw EvalError("negative start position in substring", pos);
    int64_t len = st.forceInt(*args[1], pos, "while evaluating the second argument (the substring length) passed to builtins.substring");
    st.forceValue(*args[2], pos);
    if (args[2]->type == VType::String) {
      // A window over the string's own bytes, sharing its context: nothing is copied.
      composite::Chars chars = args[2]->window();
      uint32_t from = (uint64_t)start >= chars.size() ? chars.size() : uint32_t(start);
      uint32_t to = len < 0 || (uint64_t)len >= chars.size() - from ? chars.size() : from + uint32_t(len);
      composite::Chars w = composite::slice(chars, from, to);
      v.type = VType::String;
      v.str.s = w.data();
      v.aux = w.size();
      v.str.ctx = args[2]->str.ctx;
      return;
    }
    NixStringContext ctx;
    std::string scratch;  // only a coerced argument (a path, a set) gets here: a string was shared above
    std::string_view s = composite::view(st.coerceToWindow(*args[2], ctx, false, true, pos, "while evaluating the third argument (the string) passed to builtins.substring", scratch));
    size_t l = len < 0 ? std::string::npos : (size_t)len;
    st.mkString(v, (uint64_t)start >= s.size() ? "" : s.substr(start, l), ctx);
  });
  S.addPrimOp("__concatStringsSep", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto sep = st.forceString(*args[0], ctx, pos, "while evaluating the first argument (the separator string) passed to builtins.concatStringsSep");
    st.forceList(*args[1], pos, "while evaluating the second argument (the list of strings to concat) passed to builtins.concatStringsSep");
    // The result is the series of its pieces: strings are windows over their own bytes, the separator one window, coerced elements
    // (paths, sets with outPath) the only text made; one arena buffer, written once.
    size_t ne = args[1]->listSize(), np = ne ? 2 * ne - 1 : 0, nv = 0;
    composite::Chars stackPieces[32];
    composite::Chars *pieces = np <= 32 ? stackPieces : static_cast<composite::Chars *>(st.alloc.Allocate(np * sizeof(composite::Chars), alignof(composite::Chars)));
    std::string scratch;
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
    st.mkStringOf(v, llvm::ArrayRef<composite::Chars>(pieces, nv), own.result(st, ctx));
  });
  S.addPrimOp("__replaceStrings", 3, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.replaceStrings");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.replaceStrings");
    if (args[0]->listSize() != args[1]->listSize())
      throw EvalError("'from' and 'to' arguments passed to builtins.replaceStrings have different lengths", pos);
    auto from = llvm::to_vector(args[0]->values() |cp::α| [&](Value &e) {
      return str(st.forceString(e, pos, "while evaluating one of the strings to replace passed to builtins.replaceStrings")); });
    std::map<size_t, std::string> cache;
    NixStringContext ctx;
    std::string s = str(st.forceString(*args[2], ctx, pos, "while evaluating the third argument passed to builtins.replaceStrings"));
    std::string res;
    for (size_t p = 0; p <= s.size();) {
      bool found = false;
      for (size_t j = 0; j < from.size(); j++) {
        if (s.compare(p, from[j].size(), from[j]) == 0) {
          found = true;
          auto c = cache.find(j);
          if (c == cache.end()) {
            NixStringContext c2;
            auto ts = st.forceString(*args[1]->list.elems[j], c2, pos, "while evaluating one of the replacement strings passed to builtins.replaceStrings");
            c = cache.emplace(j, str(ts)).first;
            ctx.insert(c2.begin(), c2.end());
          }
          res += c->second;
          if (from[j].empty()) {
            if (p < s.size()) res += s[p];
            p++;
          } else {
            p += from[j].size();
          }
          break;
        }
      }
      if (!found) {
        if (p < s.size()) res += s[p];
        p++;
      }
    }
    st.mkString(v, res, ctx);
  });
  S.addPrimOp("__match", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto re = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.match");
    const ku::Program &prog = kursiveOf(st, re, pos); // an invalid pattern throws before the input is evaluated
    NixStringContext ctx;
    std::string scratch;
    auto s = composite::view(st.coerceToWindow(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.match", scratch));
    if (st.statsEnabled) [[unlikely]] { ++st.nMatchCalls; ++st.matchPairs[str(re) + '\0' + str(s)]; }
    // The answer is a function of the pattern's bytes and the input's, and it is a value nothing writes (null, or a list of strings with no
    // context): a pair met before is answered from the memo, keyed by its content, built in a buffer that is reused (more than half of the
    // calls of a NixOS evaluation repeat a pair).
    std::string &key = st.matchKey; // the pattern's length, the pattern, the input: no two pairs share a key
    uint32_t rlen = uint32_t(re.size());
    key.assign(reinterpret_cast<const char *>(&rlen), sizeof rlen);
    key.append(re.data(), re.size());
    key.append(s.data(), s.size());
    auto memo = st.matchMemo.find(key);
    if (memo != st.matchMemo.end()) { v = memo->second; return; }
    // Kursive walks the pattern's program over the input's bytes where they lie: the groups are marks, and nothing is allocated.
    ku::Result r = kursiveRun(prog, re, pos, [&](ku::Scratch &k) { return ku::matchAll(prog, s.data(), uint32_t(s.size()), k); });
    if (r == ku::Result::NoMatch) st.mkNull(v);
    else kursiveGroups(st, v, prog, s, scratch);
    st.matchMemo.try_emplace(key, v);
  });
  S.addPrimOp("__split", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto re = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.split");
    const ku::Program &prog = kursiveOf(st, re, pos);
    NixStringContext ctx;
    std::string scratch;
    auto s = composite::view(st.coerceToWindow(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.split", scratch));
    // std::cregex_iterator's walk: each match at the leftmost start that has one, the longest there; after an empty match, a non-empty one
    // at the same place, else the search goes on one byte later.  Between matches the text in between, and each match's groups.
    uint32_t n = uint32_t(s.size()), lastEnd = 0, from = 0;
    bool afterEmpty = false;
    composite::MutableSeries<Value *> out;
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
      out.append(pieceOf(st, s, lastEnd, ms - lastEnd, scratch));
      Value *groups = st.allocValue();
      kursiveGroups(st, *groups, prog, s, scratch);
      out.append(groups);
      lastEnd = me;
      from = me;
      afterEmpty = ms == me;
      if (afterEmpty && me == n) break;
    }
    out.append(pieceOf(st, s, lastEnd, n - lastEnd, scratch));
    st.mkList(v, out);
  });
  S.addPrimOp("__compareVersions", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto a = st.forceStringNoCtx(*args[0], pos), b = st.forceStringNoCtx(*args[1], pos);
    st.mkInt(v, compareVersions(a, b));
  });
  S.addPrimOp("__splitVersion", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto ver = st.forceStringNoCtx(*args[0], pos);
    auto p = ver.begin();
    composite::MutableSeries<std::string> comps;
    while (p != ver.end()) {
      auto c = nextComponent(p, ver.end());
      if (c.empty()) break;
      comps.append(str(c));
    }
    st.mkList(v, comps |cp::α| [&](const auto &c) { return st.newString(c); });
  });
  S.addPrimOp("__parseDrvName", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = str(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.parseDrvName"));
    std::string n = name, ver;
    for (size_t i = 0; i < name.size(); i++) {
      if (name[i] == '-' && i + 1 < name.size() && !isalpha((unsigned char)name[i + 1])) {
        n = name.substr(0, i);
        ver = name.substr(i + 1);
        break;
      }
    }
    EvalState::BindingsBuilder bb(st);
    st.mkString(bb.alloc(st.s.name), n);
    st.mkString(bb.alloc("version"), ver);
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("baseNameOf", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to builtins.baseNameOf", scratch);
    std::string_view p = composite::view(w);
    uint32_t from = 0, to = 0;
    if (!p.empty()) {
      size_t last = p.size() - 1;
      if (p[last] == '/' && last > 0) last--;
      size_t slash = p.rfind('/', last);
      from = slash == std::string_view::npos ? 0 : uint32_t(slash + 1);
      to = uint32_t(last + 1);
    }
    mkSharedString(st, v, *args[0], composite::slice(w, from, to), ctx);
  });
  S.addPrimOp("dirOf", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::Path) {
      std::string p(args[0]->pathView());
      st.mkPath(v, nixstore::dirOf(p));
      return;
    }
    NixStringContext ctx;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to 'builtins.dirOf'", scratch);
    auto slash = composite::view(w).rfind('/');
    if (slash == std::string_view::npos) return st.mkString(v, ".", ctx);
    mkSharedString(st, v, *args[0], composite::slice(w, 0, slash == 0 ? 1 : uint32_t(slash)), ctx);
  });

  // -- Context ---------------------------------------------------------------
  S.addPrimOp("__unsafeDiscardStringContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "", scratch);
    mkSharedString(st, v, *args[0], w, {});
    if (args[0]->type == VType::String) v.str.ctx = nullptr;  // the bytes are shared, the context is not
  });
  S.addPrimOp("__hasContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceString(*args[0], pos, "while evaluating the argument passed to builtins.hasContext");
    st.mkBool(v, args[0]->str.ctx != nullptr);
  });
  S.addPrimOp("__unsafeDiscardOutputDependency", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx, out;
    std::string scratch;
    auto w = st.coerceToWindow(*args[0], ctx, false, true, pos, "", scratch);
    for (const char *c : ctx) out.insert(c[0] == '=' ? c + 1 : c); // the path after '=' is a suffix of the element: nothing copied
    st.mkString(v, composite::view(w), out);
  });
  S.addPrimOp("__addDrvOutputDependencies", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.forceString(*args[0], ctx, pos, "while evaluating the argument passed to builtins.addDrvOutputDependencies");
    if (ctx.size() != 1)
      throw EvalError("context of string '" + str(s) + "' must have exactly one element, but has " + std::to_string(ctx.size()), pos);
    std::string c = *ctx.begin();
    if (c[0] == '!') throw EvalError("`addDrvOutputDependencies` can only act on derivations, not on a derivation output such as '" + c.substr(c.find('!', 1) + 1) + "'", pos);
    if (c[0] != '=') {
      if (c.size() < 4 || c.substr(c.size() - 4) != ".drv")
        throw EvalError("path '" + c + "' is not a derivation", pos);
      c = "=" + c;
    }
    st.mkString(v, s, NixStringContext{st.copyString(c)});
  });
  S.addPrimOp("__getContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    st.forceString(*args[0], ctx, pos, "while evaluating the argument passed to builtins.getContext");
    struct Info { bool path = false, all = false; composite::MutableSeries<std::string> outputs; };
    std::map<std::string, Info> m;
    for (const char *e : ctx) {
      std::string c = e;
      if (c[0] == '=') m[c.substr(1)].all = true;
      else if (c[0] == '!') {
        auto p = c.find('!', 1);
        m[c.substr(p + 1)].outputs.append(c.substr(1, p - 1));
      } else m[c].path = true;
    }
    EvalState::BindingsBuilder bb(st);
    for (auto &[path, info] : m) {
      EvalState::BindingsBuilder ib(st);
      if (info.path) ib.insert("path", &st.vTrue);
      if (info.all) ib.insert("allOutputs", &st.vTrue);
      if (!info.outputs.empty()) {
        Value &ol = ib.alloc("outputs");
        st.mkList(ol, info.outputs |cp::α| [&](const auto &o) { return st.newString(o); });
      }
      Value &iv = bb.alloc(path);
      st.mkAttrs(iv, ib.finish());
    }
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__appendContext", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = str(st.forceString(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.appendContext"));
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.appendContext");
    for (auto &a : *args[1]->attrs) {
      std::string path = str(st.symbols[a.name]);
      if (!nixstore::isStorePath(st.store->storeDir(), path))
        throw EvalError("context key '" + path + "' is not a store path", pos);
      st.forceAttrs(*a.value, pos);
      if (const Attr *p = a.value->attrs->get(st.symbols.create("path")))
        if (st.forceBool(*p->value, pos)) ctx.insert(st.copyString(path));
      if (const Attr *p = a.value->attrs->get(st.symbols.create("allOutputs")))
        if (st.forceBool(*p->value, pos)) {
          if (path.size() < 4 || path.substr(path.size() - 4) != ".drv")
            throw EvalError("tried to add all-outputs context of " + path + ", which is not a derivation, to a string", pos);
          ctx.insert(st.copyString("=" + path));
        }
      if (const Attr *p = a.value->attrs->get(st.s.outputs)) {
        st.forceList(*p->value, pos);
        if (p->value->listSize() && (path.size() < 4 || path.substr(path.size() - 4) != ".drv"))
          throw EvalError("tried to add derivation output context of " + path + ", which is not a derivation, to a string", pos);
        for (size_t i = 0; i < p->value->listSize(); i++)
          ctx.insert(st.copyString("!" + str(st.forceStringNoCtx(*p->value->list.elems[i], pos)) + "!" + path));
      }
    }
    st.mkString(v, s, ctx);
  });

  // -- Attribute sets ----------------------------------------------------------
  S.addPrimOp("__attrNames", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrNames");
    auto sorted = args[0]->attrs->lexicographicOrder(st.symbols);
    st.mkList(v, sorted |cp::α| [&](const Attr *a) { return st.newStringWindow(st.symbols[a->name]); }); // the names' own bytes
  });
  S.addPrimOp("__attrValues", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrValues");
    auto sorted = args[0]->attrs->lexicographicOrder(st.symbols);
    st.mkList(v, sorted |cp::α| [](const Attr *a) { return a->value; });
  });
  S.addPrimOp("__getAttr", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getAttr");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.getAttr");
    const Attr *a = args[1]->attrs->get(st.symbolOfString(name));
    if (!a) throw EvalError("attribute '" + str(name) + "' missing", pos);
    st.forceValue(*a->value, pos);
    v = *a->value;
  });
  S.addPrimOp("__unsafeGetAttrPos", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
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
  S.addPrimOp("__hasAttr", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.hasAttr");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.hasAttr");
    st.mkBool(v, args[1]->attrs->get(st.symbolOfString(name)) != nullptr);
  });
  S.addPrimOp("removeAttrs", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.removeAttrs");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.removeAttrs");
    // The names to drop, sorted once; the set's rows are sorted by name too, so dropping them is one merge walk, no tree.
    size_t nr = args[1]->listSize();
    Symbol stackRm[16];
    Symbol *rm = nr <= 16 ? stackRm : static_cast<Symbol *>(st.alloc.Allocate(nr * sizeof(Symbol), alignof(Symbol)));
    for (size_t i = 0; i < nr; i++)
      rm[i] = st.symbolOfString(st.forceStringNoCtx(*args[1]->list.elems[i], pos, "while evaluating the values of the second argument passed to builtins.removeAttrs"));
    cp::sortRows(rm, nr, [](Symbol x, Symbol y) { return x < y; });
    Bindings *b = st.allocBindings(args[0]->attrs->size());
    size_t n = 0, k = 0;
    for (auto &a : *args[0]->attrs) {
      while (k < nr && rm[k] < a.name) k++;
      if (k < nr && rm[k] == a.name) continue;
      b->attrs[n++] = a;
    }
    b->size_ = n;
    st.mkAttrs(v, b);
  });
  S.addPrimOp("__listToAttrs", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the argument passed to builtins.listToAttrs");
    EvalState::BindingsBuilder bb(st);
    for (Value &e : args[0]->values()) {
      st.forceAttrs(e, pos, "while evaluating an element of the list passed to builtins.listToAttrs");
      const Attr *n = e.attrs->get(st.s.name);
      if (!n) throw EvalError("attribute 'name' missing", pos)
                  .addTrace(pos, "in a {name=...; value=...;} pair");
      auto name = st.forceStringNoCtx(*n->value, pos, "while evaluating the `name` attribute of an element of the list passed to builtins.listToAttrs");
      const Attr *val = e.attrs->get(st.s.value);
      if (!val) throw EvalError("attribute 'value' missing", pos)
                    .addTrace(pos, "in a {name=...; value=...;} pair");
      bb.insertIndexed(st.symbolOfString(name), val->value, val->pos);
    }
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__intersectAttrs", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.intersectAttrs");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.intersectAttrs");
    Bindings *b = st.allocBindings(std::min(args[0]->attrs->size(), args[1]->attrs->size()));
    size_t n = 0;
    // Walk the smaller set and probe the larger one.  callPackage intersects a
    // function's ~10 formals with all of nixpkgs (~40k attributes): walking the
    // large side did 40k failing probes and a 1 MB scan per call (90-96% of all
    // attrset lookups in the NixOS and nixpkgs workloads).  Either way the result
    // is sorted, with the entries of the second set.
    if (args[0]->attrs->size() < args[1]->attrs->size()) {
      for (auto &a : *args[0]->attrs)
        if (const Attr *j = args[1]->attrs->get(a.name)) b->attrs[n++] = *j;
    } else {
      for (auto &a : *args[1]->attrs)
        if (args[0]->attrs->get(a.name)) b->attrs[n++] = a;
    }
    b->size_ = n;
    st.mkAttrs(v, b);
  });
  S.addPrimOp("__catAttrs", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    Symbol name = st.symbolOfString(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.catAttrs"));
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.catAttrs");
    composite::MutableSeries<Value *> res;
    for (Value &e : args[1]->values()) {
      st.forceAttrs(e, pos, "while evaluating an element in the list passed as second argument to builtins.catAttrs");
      if (const Attr *a = e.attrs->get(name)) res.append(a->value);
    }
    st.mkList(v, res);
  });
  S.addPrimOp("__functionArgs", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::PrimOp || args[0]->type == VType::PrimOpApp) { st.mkAttrs(v, st.allocBindings(0)); return; }
    if (args[0]->type != VType::Lambda) throw EvalError("'functionArgs' requires a function", pos);
    auto lam = cast<nd::LambdaOp>(args[0]->thunk.node->def);
    if (!lam.getFormals()) { st.mkAttrs(v, st.allocBindings(0)); return; }
    EvalState::BindingsBuilder bb(st);
    auto defs = *lam.getFormalDefaults();
    // Positions of the formals come from the nix.formal ops in the body.
    auto locs = lam.getFormalLocs();
    for (size_t i = 0; i < lam.getFormals()->size(); i++) {
      std::string n = cast<StringAttr>((*lam.getFormals())[i]).getValue().str();
      PosPtr p = locs && i < locs->size() ? nd::posOfWord(uint64_t((*locs)[i])) : nullptr;
      bb.insert(n, defs[i] ? &st.vTrue : &st.vFalse, p);
    }
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__mapAttrs", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.mapAttrs");
    Bindings *b = st.allocBindings(args[1]->attrs->size());
    size_t n = 0;
    for (auto &a : *args[1]->attrs) {
      Value *name = st.newStringWindow(st.symbols[a.name]); // the name's own bytes, in the symbol table
      Value *f1 = st.mkAppValue(args[0], name);
      b->attrs[n++] = {a.name, a.pos, st.mkAppValue(f1, a.value)};
    }
    b->size_ = n;
    st.mkAttrs(v, b);
  });
  S.addPrimOp("__zipAttrsWith", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.zipAttrsWith");
    // Every (name, value) of every set, in list order, in one buffer; a stable sort by name groups each name's values and keeps them in
    // list order: no tree, no series per name.
    struct NV { Symbol name; Value *value; };
    size_t total = 0;
    for (Value &e : args[1]->values()) {
      st.forceAttrs(e, pos, "while evaluating a value of the list passed as second argument to builtins.zipAttrsWith");
      total += e.attrs->size();
    }
    composite::MutableSeries<NV> all;
    all.reserve(total);
    for (Value &e : args[1]->values())
      for (auto &a : *e.attrs) all.append({a.name, a.value});
    cp::sortRows(all.data(), all.size(), [](const NV &x, const NV &y) { return x.name < y.name; });
    EvalState::BindingsBuilder bb(st);
    for (uint32_t i = 0, n = all.size(); i < n;) {
      uint32_t j = i;
      while (j < n && all[j].name == all[i].name) j++;
      Value *name = st.newStringWindow(st.symbols[all[i].name]);
      Value *list = st.allocValue();
      st.mkList(*list, cp::series(all.data() + i, j - i) |cp::α| [](const NV &x) { return x.value; });
      bb.insert(all[i].name, st.mkAppValue(st.mkAppValue(args[0], name), list));
      i = j;
    }
    st.mkAttrs(v, bb.finish());
  });

  // -- Lists -----------------------------------------------------------------
  S.addPrimOp("map", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.map");
    size_t n = args[1]->listSize();
    if (!n) { v = *args[1]; return; }
    Value **src = args[1]->list.elems;
    Value *f = args[0];
    st.mkList(v, cp::series(src, n) |cp::α| [&](Value *x) { return st.mkAppValue(f, x); });
  });
  S.addPrimOp("__length", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.length");
    st.mkInt(v, (int64_t)args[0]->listSize());
  });
  S.addPrimOp("__head", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.head");
    if (!args[0]->listSize()) throw EvalError("'builtins.head' called on an empty list", pos);
    Value *e = args[0]->list.elems[0];
    st.forceValue(*e, pos);
    v = *e;
  });
  S.addPrimOp("__tail", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.tail");
    if (!args[0]->listSize()) throw EvalError("'builtins.tail' called on an empty list", pos);
    size_t n = args[0]->listSize() - 1;
    Value **src = args[0]->list.elems;
    st.mkList(v, cp::series(src + 1, n));
  });
  S.addPrimOp("__elemAt", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.elemAt");
    int64_t n = st.forceInt(*args[1], pos, "while evaluating the second argument passed to builtins.elemAt");
    if (n < 0 || (uint64_t)n >= args[0]->listSize())
      throw EvalError("list index " + std::to_string(n) + " is out of bounds", pos);
    Value *e = args[0]->list.elems[n];
    st.forceValue(*e, pos);
    v = *e;
  });
  S.addPrimOp("__elem", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.elem");
    bool res = false;
    for (Value *e : args[1]->items()) {
      if (e == args[0] || st.eqValues(*args[0], *e, pos)) { res = true; break; }
    }
    st.mkBool(v, res);
  });
  S.addPrimOp("__concatLists", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.concatLists");
    cp::Combine all(args[0]->items() |cp::α| [&](Value *l) {
      st.forceList(*l, pos, "while evaluating a value of the list passed to builtins.concatLists");
      return l->items();
    });
    st.mkList(v, all);
  });
  S.addPrimOp("__concatMap", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.concatMap");
    llvm::SmallVector<Value *, 16> rs; // one per call: the elements are not copied before the list is
    for (Value *x : args[1]->items()) {
      Value *r = st.allocValue();
      st.callFunction(*args[0], *x, *r, pos);
      st.forceList(*r, pos, "while evaluating the return value of the function passed to builtins.concatMap");
      rs.push_back(r);
    }
    cp::Combine all(rs |cp::α| [](Value *r) { return r->items(); });
    st.mkList(v, all);
  });
  S.addPrimOp("__filter", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.filter");
    // The kept cells go into stack scratch when the list is short, and straight into the arena list they will be when it is long (its
    // tail past the kept ones is left, never copied): no growing heap series.
    size_t n = args[1]->listSize();
    Value **elems = args[1]->list.elems;
    Value *stackKeep[32];
    Value **keep = n <= 32 ? stackKeep : st.allocList(n);
    size_t k = 0;
    for (size_t i = 0; i < n; i++) {
      Value r;
      st.callFunction(*args[0], *elems[i], r, pos);
      if (st.forceBool(r, pos, "while evaluating the return value of the filtering function passed to builtins.filter")) keep[k++] = elems[i];
    }
    if (k == n) { v = *args[1]; return; }
    if (n <= 32) return st.mkList(v, cp::series(keep, uint32_t(k)));
    st.mkList(v, 0);
    v.aux = uint32_t(k);
    v.list.elems = keep;
  });
  S.addPrimOp("__any", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.any");
    st.mkBool(v, std::ranges::any_of(args[1]->items(), [&](Value *e) {
      Value r;
      st.callFunction(*args[0], *e, r, pos);
      return st.forceBool(r, pos, "while evaluating the return value of the function passed to builtins.any");
    }));
  });
  S.addPrimOp("__all", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.all");
    st.mkBool(v, std::ranges::all_of(args[1]->items(), [&](Value *e) {
      Value r;
      st.callFunction(*args[0], *e, r, pos);
      return st.forceBool(r, pos, "while evaluating the return value of the function passed to builtins.all");
    }));
  });
  S.addPrimOp("__foldl'", 3, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceFunction(*args[0], pos, "while evaluating the first argument passed to builtins.foldlStrict");
    st.forceList(*args[2], pos, "while evaluating the third argument passed to builtins.foldlStrict");
    size_t n = args[2]->listSize();
    if (n) {
      Value *cur = args[1];
      Value **elems = args[2]->list.elems;
      for (size_t i = 0; i < n; i++) {
        Value *fargs[2] = {cur, elems[i]};
        Value *next = i == n - 1 ? &v : st.allocValue();
        st.callFunction(*args[0], 2, fargs, *next, pos);
        cur = next;
      }
      st.forceValue(v, pos);
    } else {
      st.forceValue(*args[1], pos);
      v = *args[1];
    }
  });
  S.addPrimOp("__genList", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    int64_t n = st.forceInt(*args[1], pos, "while evaluating the second argument passed to builtins.genList");
    if (n < 0) throw EvalError("cannot create list of size " + std::to_string(n), pos);
    st.forceFunction(*args[0], pos, "while evaluating the first argument passed to builtins.genList");
    st.mkList(v, n);
    for (int64_t i = 0; i < n; i++) {
      Value *iv = st.allocValue();
      st.mkInt(*iv, i);
      v.list.elems[i] = st.mkAppValue(args[0], iv);
    }
  });
  S.addPrimOp("__sort", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.sort");
    size_t n = args[1]->listSize();
    for (size_t k = 0; k < n; k++) st.forceValue(*args[1]->list.elems[k], pos);
    if (n == 0) { v = *args[1]; return; }
    st.forceFunction(*args[0], pos, "while evaluating the sorting function passed to builtins.sort");
    // Fast path for __lessThan.
    bool isLessThan = args[0]->type == VType::PrimOp && args[0]->primOp->name == "lessThan";
    auto cmp = [&](Value *a, Value *b) {
      if (isLessThan) return st.lessThan(*a, *b, pos);
      Value *fargs[2] = {a, b};
      Value r;
      st.callFunction(*args[0], 2, fargs, r, pos);
      return st.forceBool(r, pos, "while evaluating the return value of the sorting function passed to builtins.sort");
    };
    // The argument's cells are const and read where they lie: the sort's first pass is the drain into the result list.
    Value *const *from = args[1]->list.elems;
    st.mkList(v, n);
    composite::sortRows(from, v.list.elems, n, cmp);
  });
  S.addPrimOp("__partition", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.partition");
    // Each element's side, in stack bytes (the arena past 64), then two lists of exactly their sizes filled in list order: no heap series.
    size_t n = args[1]->listSize(), nr = 0;
    Value **elems = args[1]->list.elems;
    bool stackSide[64];
    bool *side = n <= 64 ? stackSide : static_cast<bool *>(st.alloc.Allocate(n, 1));
    for (size_t i = 0; i < n; i++) {
      st.forceValue(*elems[i], pos);
      Value r;
      st.callFunction(*args[0], *elems[i], r, pos);
      side[i] = st.forceBool(r, pos, "while evaluating the return value of the partition function passed to builtins.partition");
      nr += side[i];
    }
    EvalState::BindingsBuilder bb(st);
    Value &rv = bb.alloc(st.s.right);
    st.mkList(rv, nr);
    Value &wv = bb.alloc(st.s.wrong);
    st.mkList(wv, n - nr);
    for (size_t i = 0, a = 0, b = 0; i < n; i++) (side[i] ? rv.list.elems[a++] : wv.list.elems[b++]) = elems[i];
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__groupBy", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.groupBy");
    // (group, element) pairs in list order, in one buffer; a stable sort by group keeps each group's elements in list order: no tree.
    struct KV { Symbol key; Value *value; };
    composite::MutableSeries<KV> kv;
    kv.reserve(args[1]->listSize());
    for (Value *e : args[1]->items()) {
      Value r;
      st.callFunction(*args[0], *e, r, pos);
      kv.append({st.symbolOfString(st.forceStringNoCtx(r, pos, "while evaluating the return value of the grouping function passed to builtins.groupBy")), e});
    }
    cp::sortRows(kv.data(), kv.size(), [](const KV &x, const KV &y) { return x.key < y.key; });
    EvalState::BindingsBuilder bb(st);
    for (uint32_t i = 0, n = kv.size(); i < n;) {
      uint32_t j = i;
      while (j < n && kv[j].key == kv[i].key) j++;
      st.mkList(bb.alloc(kv[i].key), cp::series(kv.data() + i, j - i) |cp::α| [](const KV &x) { return x.value; });
      i = j;
    }
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__genericClosure", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.genericClosure");
    const Attr *ss = args[0]->attrs->get(st.s.startSet);
    if (!ss) throw EvalError("attribute 'startSet' missing", pos);
    st.forceList(*ss->value, pos, "while evaluating the 'startSet' attribute passed as argument to builtins.genericClosure");
    const Attr *op = args[0]->attrs->get(st.s.operator_);
    if (!op) throw EvalError("attribute 'operator' missing", pos);
    composite::MutableSeries<Value *> res;
    auto cmp = [&](Value *a, Value *b) { return st.lessThan(*a, *b, pos); };
    std::set<Value *, decltype(cmp)> done(cmp);
    composite::MutableSeries<Value *> queue;
    for (size_t k = 0, nk = ss->value->listSize(); k < nk; k++) queue.append(ss->value->list.elems[k]);
    size_t qi = 0;
    while (qi < queue.size()) {
      Value *e = queue[qi++];
      st.forceAttrs(*e, pos, "while evaluating one of the elements generated by (or initially passed to) builtins.genericClosure");
      const Attr *key = e->attrs->get(st.s.key);
      if (!key) throw EvalError("attribute 'key' missing", pos);
      st.forceValue(*key->value, pos);
      if (done.count(key->value)) continue;
      done.insert(key->value);
      res.append(e);
      Value r;
      st.callFunction(*op->value, *e, r, pos);
      st.forceList(r, pos, "while evaluating the return value of the `operator` passed to builtins.genericClosure");
      for (size_t i = 0; i < r.listSize(); i++) queue.append(r.list.elems[i]);
    }
    st.mkList(v, res);
  });

  // -- Environment -----------------------------------------------------------
  S.addPrimOp("__getEnv", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    composite::CharSeries name = composite::chars(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getEnv"));
    // A whole arena string is its own C string (copyString terminates it); only a window that is not followed by its NUL is copied.
    std::string copy;
    const char *cname = composite::facet<composite::text::Terminated>(name) ? name.data() : (copy = std::string(composite::view(name.window()))).c_str();
    const char *e = st.settings.pureEval ? nullptr : getenv(cname);
    st.mkString(v, e ? e : "");
  });

  // -- Import ----------------------------------------------------------------
  S.addPrimOp("import", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string path = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.import");
    st.realiseContext(ctx, pos);
    Value *r = st.evalFile(path);
    st.forceValue(*r, pos);
    v = *r;
  });
  S.addPrimOp("scopedImport", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos);
    NixStringContext ctx;
    std::string path = st.coerceToPath(*args[1], ctx, pos, "while evaluating the second argument passed to builtins.scopedImport");
    st.realiseContext(ctx, pos);
    composite::MutableSeries<std::string> names; // the scope's names in order: the cache key, and the names the file is lowered against
    for (const Attr *a : args[0]->attrs->lexicographicOrder(st.symbols)) names.append(str(st.symbols[a->name]));
    std::string real = st.resolveExprPath(st.realisePath(path, pos));
    std::string key = real;
    for (auto &n : names) key += "\n" + n;
    Value *fn;
    if (Value **hit = st.scopedImportCache.find(key.data(), uint32_t(key.size()))) fn = *hit;
    else {
      std::string text;
      try {
        text = nixstore::readFile(real);
      } catch (nixstore::Error &e) {
        throw EvalError(e.what(), pos);
      }
      auto origin = std::make_shared<nixfe::Origin>();
      origin->name = real;
      origin->path = real;
      origin->baseDir = nixstore::dirOf(real);
      origin->text = nixfe::Source::fromString(text);
      st.origins.append(origin);
      fn = st.evalExprOp(st.lowerToMLIR(origin, &names));
      st.scopedImportCache.set(key.data(), uint32_t(key.size()), fn, [&] { return st.copyString(key); });
    }
    st.callFunction(*fn, *args[0], v, pos);
  });
  S.addPrimOp("__findFile", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[1], pos, "while evaluating the second argument passed to builtins.findFile");
    std::string p = st.findFile(*args[0], name, pos);
    st.mkPath(v, p);
  });
}

} // namespace nixev
