//===- Builtins.cpp - The Nix builtins (language-level) -------------------===//

#include "Nix/Eval.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/TypeSwitch.h"

#include <algorithm>
#include <cmath>
#include <ctime>
#include <dirent.h>
#include <iostream>
#include <regex>
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

//===----------------------------------------------------------------------===//
// Regex cache
//===----------------------------------------------------------------------===//

static std::regex &getRegex(EvalState &st, const std::string &re, PosPtr pos) {
  static std::map<std::string, std::regex> cache;
  auto it = cache.find(re);
  if (it != cache.end()) return it->second;
  try {
    return cache.emplace(re, std::regex(re, std::regex::extended)).first->second;
  } catch (std::regex_error &e) {
    if (e.code() == std::regex_constants::error_space)
      throw EvalError("memory limit exceeded by regular expression '" + re + "'", pos);
    throw EvalError("invalid regular expression '" + re + "'", pos);
  }
}

/// A group of a regex match as Nix gives it: its text, or null where the group took no part.
static Value *groupValue(EvalState &st, const std::ssub_match &g) {
  if (!g.matched) { Value *e = st.allocValue(); st.mkNull(*e); return e; }
  return st.newString(g.str());
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
  auto typePred = [&](const char *name, auto pred) {
    S.addPrimOpClosure(name, 1, [pred](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      st.mkBool(v, pred(*args[0]));
    });
  };
  typePred("isNull", [](Value &x) { return x.type == VType::Null; });
  typePred("__isFunction", [](Value &x) { return x.isFunction(); });
  typePred("__isInt", [](Value &x) { return x.type == VType::Int; });
  typePred("__isFloat", [](Value &x) { return x.type == VType::Float; });
  typePred("__isString", [](Value &x) { return x.type == VType::String; });
  typePred("__isBool", [](Value &x) { return x.type == VType::Bool; });
  typePred("__isPath", [](Value &x) { return x.type == VType::Path; });
  typePred("__isAttrs", [](Value &x) { return x.type == VType::Attrs; });
  typePred("__isList", [](Value &x) { return x.type == VType::List; });
  S.addPrimOp("__typeOf", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    st.mkString(v, EvalState::typeOf(*args[0]));
  });

  // -- Arithmetic ------------------------------------------------------------
  auto arith = [&](const char *name, char op) {
    S.addPrimOpClosure(name, 2, [op](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      st.forceValue(*args[1], pos);
      Value &a = *args[0], &b = *args[1];
      const char *opname = op == '+' ? "addition" : op == '-' ? "subtraction" : op == '*' ? "multiplication" : "division";
      if (a.type == VType::Float || b.type == VType::Float) {
        double x = st.forceFloat(a, pos, std::string("while evaluating the first argument of the ") + opname);
        double y = st.forceFloat(b, pos, std::string("while evaluating the second argument of the ") + opname);
        if (op == '/' && y == 0) throw EvalError("division by zero", pos);
        st.mkFloat(v, op == '+' ? x + y : op == '-' ? x - y : op == '*' ? x * y : x / y);
        return;
      }
      int64_t x = st.forceInt(a, pos, std::string("while evaluating the first argument of the ") + opname);
      int64_t y = st.forceInt(b, pos, std::string("while evaluating the second argument of the ") + opname);
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
  arith("__add", '+');
  arith("__sub", '-');
  arith("__mul", '*');
  arith("__div", '/');
  auto bitop = [&](const char *name, char op) {
    S.addPrimOpClosure(name, 2, [op](EvalState &st, A args, Value &v, PosPtr pos) {
      int64_t a = st.forceInt(*args[0], pos), b = st.forceInt(*args[1], pos);
      st.mkInt(v, op == '&' ? (a & b) : op == '|' ? (a | b) : (a ^ b));
    });
  };
  bitop("__bitAnd", '&');
  bitop("__bitOr", '|');
  bitop("__bitXor", '^');
  S.addPrimOp("__lessThan", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.mkBool(v, st.lessThan(*args[0], *args[1], pos));
  });
  auto rounding = [&](const char *name, bool up) {
    S.addPrimOpClosure(name, 1, [up](EvalState &st, A args, Value &v, PosPtr pos) {
      st.forceValue(*args[0], pos);
      if (args[0]->type == VType::Int) { v = *args[0]; return; }
      double d = st.forceFloat(*args[0], pos);
      double r = up ? std::ceil(d) : std::floor(d);
      if (!(r >= -9223372036854775808.0 && r < 9223372036854775808.0))
        throw EvalError("NixFloat argument " + std::to_string(d) + " is not in the range of NixInt", pos);
      st.mkInt(v, (int64_t)r);
    });
  };
  rounding("__ceil", true);
  rounding("__floor", false);

  // -- Strings ---------------------------------------------------------------
  S.addPrimOp("toString", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, true, false, pos, "while evaluating the first argument passed to builtins.toString");
    st.mkString(v, s, ctx);
  });
  S.addPrimOp("__stringLength", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos, "while evaluating the argument passed to builtins.stringLength");
    st.mkInt(v, (int64_t)s.size());
  });
  S.addPrimOp("__substring", 3, [](EvalState &st, A args, Value &v, PosPtr pos) {
    int64_t start = st.forceInt(*args[0], pos, "while evaluating the first argument (the start offset) passed to builtins.substring");
    if (start < 0) throw EvalError("negative start position in substring", pos);
    int64_t len = st.forceInt(*args[1], pos, "while evaluating the second argument (the substring length) passed to builtins.substring");
    if (len == 0) {
      st.forceValue(*args[2], pos);
      if (args[2]->type == VType::String) {
        NixStringContext c;
        st.copyContext(*args[2], c);
        st.mkString(v, "", c);
        return;
      }
    }
    NixStringContext ctx;
    auto s = st.coerceToString(*args[2], ctx, false, true, pos, "while evaluating the third argument (the string) passed to builtins.substring");
    size_t l = len < 0 ? std::string::npos : (size_t)len;
    st.mkString(v, (uint64_t)start >= s.size() ? "" : s.substr(start, l), ctx);
  });
  S.addPrimOp("__concatStringsSep", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto sep = st.forceString(*args[0], ctx, pos, "while evaluating the first argument (the separator string) passed to builtins.concatStringsSep");
    st.forceList(*args[1], pos, "while evaluating the second argument (the list of strings to concat) passed to builtins.concatStringsSep");
    std::string res;
    for (size_t i = 0; i < args[1]->listSize(); i++) {
      if (i) res += sep;
      res += st.coerceToString(*args[1]->list.elems[i], ctx, false, true, pos,
                               "while evaluating one element of the list of strings to concat passed to builtins.concatStringsSep");
    }
    st.mkString(v, res, ctx);
  });
  S.addPrimOp("__replaceStrings", 3, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[0], pos, "while evaluating the first argument passed to builtins.replaceStrings");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.replaceStrings");
    if (args[0]->listSize() != args[1]->listSize())
      throw EvalError("'from' and 'to' arguments passed to builtins.replaceStrings have different lengths", pos);
    std::vector<std::string> from;
    for (size_t i = 0; i < args[0]->listSize(); i++)
      from.push_back(str(st.forceString(*args[0]->list.elems[i], pos, "while evaluating one of the strings to replace passed to builtins.replaceStrings")));
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
    auto re = str(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.match"));
    std::regex &regex = getRegex(st, re, pos);
    NixStringContext ctx;
    auto s = st.coerceToString(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.match");
    std::smatch m;
    if (!std::regex_match(s, m, regex)) { st.mkNull(v); return; }
    st.mkList(v, uint32_t(m.size() - 1) |cp::j| [&](uint32_t i) { return groupValue(st, m[i + 1]); });
  });
  S.addPrimOp("__split", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto re = str(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.split"));
    std::regex &regex = getRegex(st, re, pos);
    NixStringContext ctx;
    auto s = st.coerceToString(*args[1], ctx, false, true, pos, "while evaluating the second argument passed to builtins.split");
    auto begin = std::sregex_iterator(s.begin(), s.end(), regex);
    auto end = std::sregex_iterator();
    std::vector<Value *> out;
    size_t lastEnd = 0;
    std::smatch last;
    bool any = false;
    for (auto i = begin; i != end; ++i) {
      any = true;
      const std::smatch &m = *i;
      Value *pre = st.newString(str(std::string_view(s).substr(lastEnd, m.position(0) - lastEnd)));
      out.push_back(pre);
      Value *groups = st.allocValue();
      st.mkList(*groups, uint32_t(m.size() - 1) |cp::j| [&](uint32_t g) { return groupValue(st, m[g + 1]); });
      out.push_back(groups);
      lastEnd = m.position(0) + m.length(0);
    }
    Value *rest = st.newString(any ? s.substr(lastEnd) : s);
    out.push_back(rest);
    MLNIX_FILL(st, EvalState::FillSplit, out.size());
    st.mkList(v, out);
  });
  S.addPrimOp("__compareVersions", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto a = st.forceStringNoCtx(*args[0], pos), b = st.forceStringNoCtx(*args[1], pos);
    st.mkInt(v, compareVersions(a, b));
  });
  S.addPrimOp("__splitVersion", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto ver = st.forceStringNoCtx(*args[0], pos);
    auto p = ver.begin();
    std::vector<std::string> comps;
    while (p != ver.end()) {
      auto c = nextComponent(p, ver.end());
      if (c.empty()) break;
      comps.push_back(str(c));
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
    auto s = st.coerceToString(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to builtins.baseNameOf");
    std::string_view p = s;
    std::string res;
    if (!p.empty()) {
      size_t last = p.size() - 1;
      if (p[last] == '/' && last > 0) last--;
      size_t slash = p.rfind('/', last);
      res = slash == std::string_view::npos ? str(p.substr(0, last + 1)) : str(p.substr(slash + 1, last - slash));
    }
    st.mkString(v, res, ctx);
  });
  S.addPrimOp("dirOf", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::Path) {
      std::string p(args[0]->pathView());
      st.mkPath(v, nixstore::dirOf(p));
      return;
    }
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, false, pos, "while evaluating the first argument passed to 'builtins.dirOf'");
    auto slash = s.rfind('/');
    std::string d = slash == std::string::npos ? "." : slash == 0 ? "/" : s.substr(0, slash);
    st.mkString(v, d, ctx);
  });

  // -- Context ---------------------------------------------------------------
  S.addPrimOp("__unsafeDiscardStringContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos);
    st.mkString(v, s);
  });
  S.addPrimOp("__hasContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceString(*args[0], pos, "while evaluating the argument passed to builtins.hasContext");
    st.mkBool(v, args[0]->str.ctx != nullptr);
  });
  S.addPrimOp("__unsafeDiscardOutputDependency", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx, out;
    auto s = st.coerceToString(*args[0], ctx, false, true, pos);
    for (auto &c : ctx) out.insert(c[0] == '=' ? c.substr(1) : c);
    st.mkString(v, s, out);
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
    st.mkString(v, s, NixStringContext{c});
  });
  S.addPrimOp("__getContext", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    st.forceString(*args[0], ctx, pos, "while evaluating the argument passed to builtins.getContext");
    struct Info { bool path = false, all = false; std::vector<std::string> outputs; };
    std::map<std::string, Info> m;
    for (auto &c : ctx) {
      if (c[0] == '=') m[c.substr(1)].all = true;
      else if (c[0] == '!') {
        auto p = c.find('!', 1);
        m[c.substr(p + 1)].outputs.push_back(c.substr(1, p - 1));
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
        if (st.forceBool(*p->value, pos)) ctx.insert(path);
      if (const Attr *p = a.value->attrs->get(st.symbols.create("allOutputs")))
        if (st.forceBool(*p->value, pos)) {
          if (path.size() < 4 || path.substr(path.size() - 4) != ".drv")
            throw EvalError("tried to add all-outputs context of " + path + ", which is not a derivation, to a string", pos);
          ctx.insert("=" + path);
        }
      if (const Attr *p = a.value->attrs->get(st.s.outputs)) {
        st.forceList(*p->value, pos);
        if (p->value->listSize() && (path.size() < 4 || path.substr(path.size() - 4) != ".drv"))
          throw EvalError("tried to add derivation output context of " + path + ", which is not a derivation, to a string", pos);
        for (size_t i = 0; i < p->value->listSize(); i++)
          ctx.insert("!" + str(st.forceStringNoCtx(*p->value->list.elems[i], pos)) + "!" + path);
      }
    }
    st.mkString(v, s, ctx);
  });

  // -- Attribute sets ----------------------------------------------------------
  S.addPrimOp("__attrNames", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrNames");
    auto sorted = args[0]->attrs->lexicographicOrder(st.symbols);
    st.mkList(v, sorted |cp::α| [&](const Attr *a) { return st.newString(st.symbols[a->name]); });
  });
  S.addPrimOp("__attrValues", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.attrValues");
    auto sorted = args[0]->attrs->lexicographicOrder(st.symbols);
    st.mkList(v, sorted |cp::α| [](const Attr *a) { return a->value; });
  });
  S.addPrimOp("__getAttr", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getAttr");
    st.forceAttrs(*args[1], pos, "while evaluating the second argument passed to builtins.getAttr");
    const Attr *a = args[1]->attrs->get(st.symbols.create(name));
    if (!a) throw EvalError("attribute '" + str(name) + "' missing", pos);
    st.forceValue(*a->value, pos);
    v = *a->value;
  });
  S.addPrimOp("__unsafeGetAttrPos", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = st.forceStringNoCtx(*args[0], pos);
    st.forceAttrs(*args[1], pos);
    const Attr *a = args[1]->attrs->get(st.symbols.create(name));
    if (!a || !a->pos) { st.mkNull(v); return; }
    auto f = nd::decodePos(a->pos);
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
    st.mkBool(v, args[1]->attrs->get(st.symbols.create(name)) != nullptr);
  });
  S.addPrimOp("removeAttrs", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.removeAttrs");
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.removeAttrs");
    std::set<Symbol> rm;
    for (size_t i = 0; i < args[1]->listSize(); i++)
      rm.insert(st.symbols.create(st.forceStringNoCtx(*args[1]->list.elems[i], pos, "while evaluating the values of the second argument passed to builtins.removeAttrs")));
    Bindings *b = st.allocBindings(args[0]->attrs->size());
    size_t n = 0;
    for (auto &a : *args[0]->attrs)
      if (!rm.count(a.name)) b->attrs[n++] = a;
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
      bb.insert(st.symbols.create(name), val->value, val->pos);
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
    Symbol name = st.symbols.create(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.catAttrs"));
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.catAttrs");
    std::vector<Value *> res;
    for (Value &e : args[1]->values()) {
      st.forceAttrs(e, pos, "while evaluating an element in the list passed as second argument to builtins.catAttrs");
      if (const Attr *a = e.attrs->get(name)) res.push_back(a->value);
    }
    MLNIX_FILL(st, EvalState::FillCatAttrs, res.size());
    st.mkList(v, res);
  });
  S.addPrimOp("__functionArgs", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    if (args[0]->type == VType::PrimOp || args[0]->type == VType::PrimOpApp) { st.mkAttrs(v, st.allocBindings(0)); return; }
    if (args[0]->type != VType::Lambda) throw EvalError("'functionArgs' requires a function", pos);
    auto lam = cast<nd::LambdaOp>(args[0]->thunk.op);
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
      Value *name = st.newString(st.symbols[a.name]);
      Value *f1 = st.mkAppValue(args[0], name);
      b->attrs[n++] = {a.name, st.mkAppValue(f1, a.value), a.pos};
    }
    b->size_ = n;
    st.mkAttrs(v, b);
  });
  S.addPrimOp("__zipAttrsWith", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.zipAttrsWith");
    std::map<Symbol, std::vector<Value *>> m;
    for (Value &e : args[1]->values()) {
      st.forceAttrs(e, pos, "while evaluating a value of the list passed as second argument to builtins.zipAttrsWith");
      for (auto &a : *e.attrs) m[a.name].push_back(a.value);
    }
    EvalState::BindingsBuilder bb(st);
    for (auto &[sym, vals] : m) {
      Value *name = st.newString(st.symbols[sym]);
      Value *list = st.allocValue();
      st.mkList(*list, vals);
      bb.insert(sym, st.mkAppValue(st.mkAppValue(args[0], name), list));
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
    MLNIX_FILL(st, EvalState::FillConcatLists, all.size());
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
    MLNIX_FILL(st, EvalState::FillConcatMap, all.size());
    st.mkList(v, all);
  });
  S.addPrimOp("__filter", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.filter");
    std::vector<Value *> res;
    bool same = true;
    for (size_t i = 0; i < args[1]->listSize(); i++) {
      Value r;
      st.callFunction(*args[0], *args[1]->list.elems[i], r, pos);
      if (st.forceBool(r, pos, "while evaluating the return value of the filtering function passed to builtins.filter"))
        res.push_back(args[1]->list.elems[i]);
      else same = false;
    }
    if (same) { v = *args[1]; return; }
    MLNIX_FILL(st, EvalState::FillFilter, res.size());
    st.mkList(v, res);
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
    std::vector<Value *> elems(args[1]->list.elems, args[1]->list.elems + n);
    for (auto *e : elems) st.forceValue(*e, pos);
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
    std::stable_sort(elems.begin(), elems.end(), cmp);
    MLNIX_FILL(st, EvalState::FillSort, n);
    st.mkList(v, elems);
  });
  S.addPrimOp("__partition", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.partition");
    std::vector<Value *> right, wrong;
    for (Value *e : args[1]->items()) {
      st.forceValue(*e, pos);
      Value r;
      st.callFunction(*args[0], *e, r, pos);
      if (st.forceBool(r, pos, "while evaluating the return value of the partition function passed to builtins.partition")) right.push_back(e);
      else wrong.push_back(e);
    }
    EvalState::BindingsBuilder bb(st);
    Value &rv = bb.alloc(st.s.right);
    st.mkList(rv, right);
    Value &wv = bb.alloc(st.s.wrong);
    st.mkList(wv, wrong);
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__groupBy", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceList(*args[1], pos, "while evaluating the second argument passed to builtins.groupBy");
    std::map<Symbol, std::vector<Value *>> m;
    std::vector<Symbol> order;
    for (Value *e : args[1]->items()) {
      Value r;
      st.callFunction(*args[0], *e, r, pos);
      Symbol key = st.symbols.create(st.forceStringNoCtx(r, pos, "while evaluating the return value of the grouping function passed to builtins.groupBy"));
      m[key].push_back(e);
    }
    EvalState::BindingsBuilder bb(st);
    for (auto &[k, vals] : m) {
      Value &l = bb.alloc(k);
      st.mkList(l, vals);
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
    std::vector<Value *> work(ss->value->list.elems, ss->value->list.elems + ss->value->listSize());
    std::reverse(work.begin(), work.end());
    std::vector<Value *> res;
    auto cmp = [&](Value *a, Value *b) { return st.lessThan(*a, *b, pos); };
    std::set<Value *, decltype(cmp)> done(cmp);
    std::vector<Value *> queue(ss->value->list.elems, ss->value->list.elems + ss->value->listSize());
    size_t qi = 0;
    while (qi < queue.size()) {
      Value *e = queue[qi++];
      st.forceAttrs(*e, pos, "while evaluating one of the elements generated by (or initially passed to) builtins.genericClosure");
      const Attr *key = e->attrs->get(st.s.key);
      if (!key) throw EvalError("attribute 'key' missing", pos);
      st.forceValue(*key->value, pos);
      if (done.count(key->value)) continue;
      done.insert(key->value);
      res.push_back(e);
      Value r;
      st.callFunction(*op->value, *e, r, pos);
      st.forceList(r, pos, "while evaluating the return value of the `operator` passed to builtins.genericClosure");
      for (size_t i = 0; i < r.listSize(); i++) queue.push_back(r.list.elems[i]);
    }
    MLNIX_FILL(st, EvalState::FillGenericClosure, res.size());
    st.mkList(v, res);
  });

  // -- Environment -----------------------------------------------------------
  S.addPrimOp("__getEnv", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = str(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.getEnv"));
    const char *e = st.settings.pureEval ? nullptr : getenv(name.c_str());
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
    std::vector<std::string> names;
    for (auto &a : *args[0]->attrs) names.push_back(str(st.symbols[a.name]));
    std::sort(names.begin(), names.end());
    std::string real = st.resolveExprPath(st.realisePath(path, pos));
    std::string key = real;
    for (auto &n : names) key += "\n" + n;
    Value *fn;
    auto it = st.scopedImportCache.find(key);
    if (it != st.scopedImportCache.end()) fn = it->second;
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
      st.origins.push_back(origin);
      fn = st.evalExprOp(st.lowerToMLIR(origin, &names));
      st.scopedImportCache[key] = fn;
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
