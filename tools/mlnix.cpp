//===- mlnix.cpp - Nix-compatible command line driver ---------------------===//
//
//   mlnix instantiate|build|eval|parse|emit-mlir|run-mlir|store|hash|derivation
//
// When invoked through a symlink named nix-instantiate, nix-build, nix-store
// or nix-hash, behaves like that command; named nix, it evaluates lib/Corepkgs/cli.nix on its arguments.
//
//===----------------------------------------------------------------------===//

#include "Composite/Mutable.h"
#include "Nix/Prefetch.h"
#include "Nix/Eval.h"
#include "Nix/MLIRGen.h"
#include "Nix/Numbers.h"

#include "mlir/IR/AsmState.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/Support/raw_ostream.h"

#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

using namespace nixev;
namespace nd = mlir::nix;

namespace nixev {
extern bool tomlTimestamps;
}


namespace {

/// A line to standard error.
void lineToStderr(std::string_view line) { nixsys::lineToStderr(line.data(), line.size()); }
/// A line to standard output.
void lineToStdout(std::string_view line) { nixsys::lineToStdout(line.data(), line.size()); }

/// What the standard library's stoul was: the facet's reading of the digits, and the two exceptions it threw (nothing read; out of range).
unsigned long toUnsigned(std::string_view v) { return nixsys::stoValue("stoul", nixsys::readUnsigned(v)); }

[[noreturn]] void usage(std::string_view msg) {
  composite::Text t;
  t.put("error: ").put(msg).put("\nTry 'mlnix --help' for more information.\n");
  nixsys::toStderr(t.data(), t.size());
  exit(1);
}

composite::Text defaultSystem() {
#if defined(__APPLE__)
#if defined(__aarch64__)
  return "aarch64-darwin";
#else
  return "x86_64-darwin";
#endif
#else
#if defined(__aarch64__)
  return "aarch64-linux";
#else
  return "x86_64-linux";
#endif
#endif
}

composite::Text absPath(std::string_view p) {
  if (!p.empty() && p[0] == '/') return nixfe::canonPath(p);
  char buf[PATH_MAX];
  return nixfe::canonPath(composite::cat(getcwd(buf, sizeof buf) ? buf : "/", '/', p));
}

/// The text algebra is lowered/tools/ToolOpts.mlir.  A text entry returns -need-2 when the room is short: size, then drain.
template <class F> composite::Text drained(F f) {
  composite::Text t;
  int64_t r = f(nullptr, 0);
  if (r < -1) { t.resize(size_t(-r - 2)); r = f(t.begin(), int64_t(t.size())); }
  t.truncate(size_t(r));
  return t;
}

// The names the driver knows: flags of each command, the --option names and values, the experimental words, the
// argv[0] and command names.  lowered/tools/ToolFlags.mlir holds the table (scripts/gen_tool_flags.py writes both).  Each name's
// code is one of these; a name the table does not have is OPT_NONE.  Two spellings of one thing share a code.
enum Opt : int64_t {
  OPT_NONE = -1,
  OPT_INCLUDE = 1, OPT_ARG = 2, OPT_ARGSTR = 3, OPT_ATTR = 4, OPT_EXPR = 5, OPT_SHOW_TRACE = 6, OPT_TRACE_VERBOSE = 7,
  OPT_ABORT_ON_WARN = 8, OPT_PURE_EVAL = 9, OPT_IMPURE = 10, OPT_RESTRICT_EVAL = 11, OPT_EXPFEAT = 12, OPT_OPTION = 13,
  OPT_LINT_ABS = 14, OPT_LINT_SHORT = 15, OPT_LINT_URL = 16, OPT_SYSTEM = 17, OPT_STORE_DIR = 18, OPT_STORE = 19,
  OPT_READONLY = 20, OPT_READWRITE = 21, OPT_KEEP_FAILED = 22, OPT_JOBS = 23, OPT_CORES = 24, OPT_NO_OPT = 25,
  OPT_NOOP = 26, OPT_EVAL = 27, OPT_PARSE = 28, OPT_EMIT_MLIR = 29, OPT_STRICT = 30, OPT_JSON = 31, OPT_XML = 32,
  OPT_RAW = 33, OPT_NO_LOCATION = 34, OPT_FIND_FILE = 35, OPT_DRY_RUN = 36, OPT_ADD_ROOT = 37, OPT_INDIRECT = 38,
  OPT_OUT_LINK = 39, OPT_NO_OUT_LINK = 40, OPT_STDIN = 41, OPT_OP_ADD = 42, OPT_OP_ADD_FIXED = 43, OPT_OP_REALISE = 44,
  OPT_OP_QUERY = 45, OPT_OP_DUMP = 46, OPT_OP_GC = 47, OPT_OP_DELETE = 48, OPT_OP_VERIFY = 49, OPT_OP_PRINT_ENV = 50,
  OPT_OP_RESTORE = 51, OPT_OP_OTHER = 52, OPT_Q_REFS = 53, OPT_Q_REQS = 54, OPT_Q_REFERRERS = 55, OPT_Q_DERIVER = 56,
  OPT_Q_OUTPUTS = 57, OPT_Q_HASH = 58, OPT_Q_SIZE = 59, OPT_INCLUDE_OUTPUTS = 60, OPT_PRINT_INVALID = 61,
  OPT_RECURSIVE = 62, OPT_TYPE = 63, OPT_FLAT = 64, OPT_BASE32 = 65, OPT_BASE16 = 66, OPT_BASE64 = 67, OPT_SRI = 68,
  OPT_TRUNCATE = 69, OPT_TO_BASE32 = 70, OPT_TO_NIX32 = 71, OPT_TO_BASE16 = 72, OPT_TO_BASE64 = 73, OPT_TO_SRI = 74,
  OPT_MODE_PATH = 75, OPT_MODE_FILE = 76, OPT_HELP = 77, OPT_VERSION = 78, OPT_INSTANTIATE = 79, OPT_BUILD = 80,
  OPT_EVAL_CMD = 81, OPT_PARSE_CMD = 82, OPT_EMIT_CMD = 83, OPT_RUN_CMD = 84, OPT_PRIMOPS = 85, OPT_STORE_CMD = 86,
  OPT_HASH_CMD = 87, OPT_DERIVATION = 88, OPT_SHOW = 89, OPT_PROG_NIX = 90, OPT_PROG_INSTANTIATE = 91,
  OPT_PROG_BUILD = 92, OPT_PROG_STORE = 93, OPT_PROG_HASH = 94, OPT_VAL_MAX_CALL_DEPTH = 95, OPT_VAL_EXPFEAT = 96,
  OPT_VAL_SYSTEM = 97, OPT_VAL_PURE_EVAL = 98, OPT_TRUE = 99, OPT_WARN = 100, OPT_FATAL = 101, OPT_IGNORE = 102,
  OPT_WORD_PIPE = 103, OPT_WORD_TOML = 104, OPT_DUMMY = 105, OPT_AUTO = 106, OPT_LOCAL = 107, OPT_DAEMON = 108,
};
extern "C" int64_t mlnix_tf_lookup(const char *p, int64_t n);
extern "C" int64_t mlnix_tf_lines(const int64_t *recs, int64_t n, int64_t mode, char *into, int64_t cap);
extern "C" int64_t mlnix_tf_primops(const int64_t *recs, int64_t n, char *into, int64_t cap);
extern "C" int64_t mlnix_tf_count(int64_t n, char *into, int64_t cap);
/// The code of a name, or OPT_NONE (the bisect over the table is lowered/tools/ToolFlags.mlir).
Opt optCode(const char *p, size_t n) { return Opt(mlnix_tf_lookup(p, int64_t(n))); }
Opt optCode(std::string_view s) { return optCode(s.data(), s.size()); }

extern "C" int64_t mlnix_ts_nixpath(const char *p, int64_t n, int64_t *recs, int64_t cap);
/// NIX_PATH's elements as records (prefix off/len, path off/len) into s.
composite::MutableSeries<SearchPathElem> parseNixPath(std::string_view s) {
  int64_t need = mlnix_ts_nixpath(s.data(), s.size(), nullptr, 0); // -count-2, or 0 when there is none
  composite::MutableSeries<int64_t> r(size_t(need < 0 ? -need - 2 : 0) * 4);
  composite::MutableSeries<SearchPathElem> res;
  for (int64_t k = 0, n = mlnix_ts_nixpath(s.data(), s.size(), r.data(), r.size() / 4); k < n; k++)
    res.append({composite::Text(s.substr(r[4 * k], r[4 * k + 1])), composite::Text(s.substr(r[4 * k + 2], r[4 * k + 3]))});
  return res;
}

struct Options {
  composite::MutableSeries<composite::Text> files;
  composite::MutableSeries<composite::Text> attrPaths;
  composite::MutableSeries<composite::Join<composite::Text, composite::Text>> argExprs, argStrs;
  composite::MutableSeries<composite::Text> includes;
  bool fromArgs = false, readStdin = false, evalOnly = false, parseOnly = false, strict = false;
  bool json = false, xml = false, raw = false, location = true, findFile = false;
  bool readWrite = false, readOnly = false, dryRun = false, noOutLink = false, showTrace = false;
  bool emitMLIR = false, noOpt = false;
  composite::Text outLink = "result", addRoot;
  EvalSettings eval;
  nixstore::StoreSettings store;
  bool storeDirSet = false, storeRootSet = false;
};

/// Parse options shared by all evaluating commands. Returns false if `arg`
/// was not recognised.
bool parseCommon(Options &o, std::string_view arg, int &i, int argc, char **argv) {
  auto next = [&]() -> std::string_view {
    if (i + 1 >= argc) usage(composite::cat("flag '", arg, "' requires an argument"));
    return argv[++i];
  };
  switch (Opt c = optCode(arg)) {
  case OPT_INCLUDE: o.includes.append(composite::Text(next())); break;
  case OPT_ARG: { composite::Text n(next()), v(next()); o.argExprs.append({composite::mv(n), composite::mv(v)}); break; }
  case OPT_ARGSTR: { composite::Text n(next()), v(next()); o.argStrs.append({composite::mv(n), composite::mv(v)}); break; }
  case OPT_ATTR: o.attrPaths.append(composite::Text(next())); break;
  case OPT_EXPR: o.fromArgs = true; break;
  case OPT_SHOW_TRACE: o.eval.showTrace = true; break;
  case OPT_TRACE_VERBOSE: o.eval.traceVerbose = true; break;
  case OPT_ABORT_ON_WARN: o.eval.abortOnWarn = true; break;
  case OPT_PURE_EVAL: o.eval.pureEval = true; break;
  case OPT_IMPURE: o.eval.pureEval = false; break;
  case OPT_RESTRICT_EVAL: o.eval.restrictEval = true; break;
  case OPT_EXPFEAT: {
    std::string_view f = next();
    composite::eachWord(f.data(), uint32_t(f.size()), [&](const char *p, uint32_t n) {
      Opt w = optCode(p, n);
      if (w == OPT_WORD_PIPE) o.eval.pipeOperators = true;
      if (w == OPT_WORD_TOML) nixev::tomlTimestamps = true;
    });
    break;
  }
  case OPT_OPTION: {
    std::string_view n = next(), v = next();
    Opt nc = optCode(n);
    if (nc == OPT_VAL_MAX_CALL_DEPTH) o.eval.maxCallDepth = toUnsigned(v);
    else if (nc == OPT_VAL_EXPFEAT && v.find("pipe-operators") != std::string_view::npos) o.eval.pipeOperators = true;
    else if (nc == OPT_VAL_SYSTEM) o.eval.currentSystem = composite::Text(v);
    else if (nc == OPT_VAL_PURE_EVAL) o.eval.pureEval = optCode(v) == OPT_TRUE;
    break;
  }
  case OPT_LINT_ABS: case OPT_LINT_SHORT: case OPT_LINT_URL: {
    std::string_view v = next();
    Opt lv = optCode(v);
    nixfe::Lint l = lv == OPT_WARN ? nixfe::Lint::Warn : lv == OPT_FATAL ? nixfe::Lint::Fatal : nixfe::Lint::Ignore;
    if (lv != OPT_WARN && lv != OPT_FATAL && lv != OPT_IGNORE)
      usage(composite::cat("option '", arg.substr(2), "' has invalid value '", v, "' (expected 'ignore', 'warn', or 'fatal')"));
    if (c == OPT_LINT_ABS) o.eval.lintAbsolutePaths = l;
    else if (c == OPT_LINT_SHORT) o.eval.lintShortPaths = l;
    else o.eval.lintUrls = l;
    break;
  }
  case OPT_SYSTEM: o.eval.currentSystem = composite::Text(next()); break;
  case OPT_STORE_DIR: o.store.storeDir = absPath(next()); o.storeDirSet = true; break;
  case OPT_STORE: {
    std::string_view s = next();
    Opt sc = optCode(s);
    if (sc == OPT_DUMMY) o.readOnly = o.store.dummy = true;
    else if (s.rfind("local?root=", 0) == 0) { o.store.realRoot = absPath(s.substr(11)); o.storeRootSet = true; }
    else if (sc != OPT_AUTO && sc != OPT_LOCAL && sc != OPT_DAEMON) { o.store.realRoot = absPath(s); o.storeRootSet = true; }
    break;
  }
  case OPT_READONLY: o.readOnly = true; break;
  case OPT_READWRITE: o.readWrite = true; break;
  case OPT_KEEP_FAILED: o.store.keepFailed = true; break;
  case OPT_JOBS: next(); break;
  case OPT_CORES: o.store.cores = toUnsigned(next()); break;
  case OPT_NO_OPT: o.noOpt = true; break;
  case OPT_NOOP: break;
  default:
    if (arg.rfind("-I", 0) == 0 && arg.size() > 2) { o.includes.append(composite::Text(arg.substr(2))); break; }
    return false;
  }
  return true;
}

void finishOptions(Options &o) {
  if (o.eval.currentSystem.empty()) {
    const char *sys = getenv("NIX_SYSTEM");
    o.eval.currentSystem = sys ? composite::Text(sys) : defaultSystem();
  }
  // NIX_PATH and -I.
  for (const composite::Text &inc : o.includes) {
    auto v = parseNixPath(inc);
    for (auto &e : v) o.eval.nixPath.append(composite::mv(e));
  }
  if (const char *np = getenv("NIX_PATH")) {
    auto v = parseNixPath(np);
    for (auto &e : v) o.eval.nixPath.append(composite::mv(e));
  }
  for (auto &e : o.eval.nixPath)
    if (e.path.find("://") == composite::npos) e.path = absPath(e.path);
  if (o.noOpt) o.eval.optimize = false;
  // Store configuration.
  if (!o.storeDirSet) {
    if (const char *sd = getenv("NIX_STORE_DIR")) o.store.storeDir = sd;
    else if (const char *sd2 = getenv("NIX_STORE")) o.store.storeDir = sd2;
  }
  if (const char *r = getenv("NIX_REMOTE"); r && optCode(std::string_view(r)) == OPT_DUMMY) o.readOnly = o.store.dummy = true;
  if (!o.storeRootSet) {
    if (const char *r = getenv("MLNIX_STORE_ROOT")) o.store.realRoot = r;
    else {
      // Use the store directory directly if we can write to it; otherwise
      // fall back to a chroot-style store under the user's data directory.
      const composite::Text &sd = o.store.storeDir;
      bool usable = access(sd.c_str(), W_OK) == 0 ||
                    (access(sd.c_str(), F_OK) != 0 && access(nixstore::dirOf(sd).c_str(), W_OK) == 0);
      if (!usable) {
        const char *home = getenv("HOME");
        o.store.realRoot = composite::cat(home ? home : "/tmp", "/.local/share/mlnix/root");
      }
    }
  }
  if (const char *sd = getenv("MLNIX_STATE_DIR")) o.store.stateDir = sd;
  o.store.readOnly = o.readOnly;
  o.store.system = o.eval.currentSystem.clone();
}

AutoArgs buildAutoArgs(EvalState &st, const Options &o) {
  AutoArgs res; // a name given twice stands for its last value
  char buf[PATH_MAX];
  composite::Text cwd(getcwd(buf, sizeof buf) ? buf : "/");
  auto set = [&](std::string_view n, Value *v) { res.set(n.data(), uint32_t(n.size()), v, [&] { return st.copyString(n); }); };
  for (auto &[n, e] : o.argExprs) set(n, st.evalString(e, cwd, "«string»"));
  for (auto &[n, s] : o.argStrs) {
    Value *v = st.allocValue();
    st.mkString(*v, s);
    set(n, v);
  }
  return res;
}

/// findAlongAttrPath
Value *findAlongAttrPath(EvalState &st, std::string_view path, const AutoArgs &autoArgs,
                         Value &root) {
  composite::MutableSeries<composite::Text> comps;
  {
    composite::Text cur;
    bool quoted = false;
    for (char c : path) {
      if (c == '"') { quoted = !quoted; continue; }
      if (c == '.' && !quoted) { comps.append(composite::mv(cur)); cur.clear(); continue; }
      cur += c;
    }
    if (quoted) throw EvalError(composite::cat("missing closing quote in selection path '", path, "'"));
    if (!path.empty()) comps.append(composite::mv(cur));
  }
  Value *v = &root;
  for (auto &c : comps) {
    if (c.empty()) throw EvalError(composite::cat("empty attribute name in selection path '", path, "'"));
    Value *vNew = st.allocValue();
    st.autoCallFunction(autoArgs, *v, *vNew);
    v = vNew;
    st.forceValue(*v);
    composite::text::Reading index = nixsys::readUnsigned(c); // a list index is digits all through: no space, no sign
    bool isIndex = !c.empty() && composite::isAsciiDigit(c[0]) && index.consumed == c.size();
    if (!isIndex) {
      if (v->type != VType::Attrs)
        throw TypeError(composite::cat("the expression selected by the selection path '", path, "' should be a set but is ",
                                       EvalState::showType(*v)));
      const Attr *a = v->attrs->get(st.symbols.create(c));
      if (!a) throw EvalError(composite::cat("attribute '", c, "' in selection path '", path, "' not found"));
      v = a->value;
    } else {
      if (v->type != VType::List)
        throw TypeError(composite::cat("the expression selected by the selection path '", path, "' should be a list but is ",
                                       EvalState::showType(*v)));
      size_t idx = nixsys::stoValue("stoul", index);
      if (idx >= v->listSize()) throw EvalError(composite::cat("list index ", c, " in selection path '", path, "' is out of range"));
      v = v->list.elems[idx];
    }
  }
  return v;
}

struct DrvInfo {
  composite::Text drvPath, outputName, attrPath;
  nixstore::SortedMap<composite::Text> outputs;
};

bool getDerivation(EvalState &st, Value &v, std::string_view attrPath, composite::MutableSeries<DrvInfo> &drvs,
                   composite::WordTable<bool> &done) {
  st.forceValue(v);
  if (!st.isDerivation(v)) return true;
  if (!done.insert(uint64_t(uintptr_t(v.attrs)), true)) return false;
  DrvInfo d;
  d.attrPath = composite::Text(attrPath);
  const Attr *dp = v.attrs->get(st.s.drvPath);
  if (!dp) throw EvalError("derivation does not contain a 'drvPath' attribute");
  NixStringContext ctx;
  d.drvPath = st.coerceToString(*dp->value, ctx, false, false);
  d.outputName = "out";
  if (const Attr *on = v.attrs->get(st.s.outputName)) d.outputName = composite::Text(st.forceStringNoCtx(*on->value));
  drvs.append(composite::mv(d));
  return false;
}

void getDerivations(EvalState &st, Value &vIn, std::string_view prefix, const AutoArgs &autoArgs,
                    composite::MutableSeries<DrvInfo> &drvs, composite::WordTable<bool> &done) {
  Value v;
  st.autoCallFunction(autoArgs, vIn, v);
  if (!getDerivation(st, v, prefix, drvs, done)) return;
  if (v.type == VType::Attrs) {
    if (!done.insert(uint64_t(uintptr_t(v.attrs)), true)) return;
    for (const Attr *a : v.attrs->lexicographicOrder(st.symbols)) {
      composite::Text p2 = prefix.empty() ? composite::Text(st.symbols[a->name]) : composite::cat(prefix, '.', st.symbols[a->name]);
      if (getDerivation(st, *a->value, p2, drvs, done)) {
        if (a->value->type == VType::Attrs) {
          const Attr *r = a->value->attrs->get(st.symbols.create("recurseForDerivations"));
          if (r && st.forceBool(*r->value, nullptr)) getDerivations(st, *a->value, p2, autoArgs, drvs, done);
        }
      }
    }
  } else if (v.type == VType::List) {
    for (size_t i = 0; i < v.listSize(); i++) {
      composite::Text p2 = prefix.empty() ? composite::str(i) : composite::cat(prefix, '.', i);
      if (getDerivation(st, *v.list.elems[i], p2, drvs, done))
        getDerivations(st, *v.list.elems[i], p2, autoArgs, drvs, done);
    }
  } else {
    throw TypeError("expression does not evaluate to a derivation (or a set or list of those)");
  }
}

composite::Text readStdin() {
  composite::Text text;
  nixsys::readInto(STDIN_FILENO, text);
  return text;
}

composite::Text cwdPath() {
  char buf[PATH_MAX];
  return composite::Text(getcwd(buf, sizeof buf) ? buf : "/");
}

/// Locate the file argument (handles <lookup> and directories).
composite::Text lookupFileArg(EvalState &st, std::string_view s) {
  if (s.size() > 2 && s.front() == '<' && s.back() == '>') {
    Value *np = st.baseEnvValue("__nixPath");
    return st.findFile(*np, s.substr(1, s.size() - 2), nullptr);
  }
  return absPath(s);
}

int runEvalCommandIn(Options &o, bool build, EvalState &st, nixstore::Store *store);

int runEvalCommand(Options &o, bool build) {
  finishOptions(o);
  if (o.evalOnly && !o.readWrite) o.store.readOnly = true;
  // An evaluation never destroys its state: the process exits right after, and taking a module of a
  // million ops, the attribute uniquer and the arenas apart one object at a time cost 6.6% of a NixOS
  // evaluation (77de09c:docs/PERFORMANCE.md).  The one thing the destructor did, printing the statistics, is
  // done here.  `build` keeps the ordinary teardown.  The store lives as long as the state.
  nixstore::Store *store = new nixstore::Store(o.store);
  EvalState *stp = new EvalState(std::move(o.eval), store); // the settings are the state's from here on
  struct Teardown {
    EvalState *st;
    nixstore::Store *store;
    bool leak;
    ~Teardown() {
      if (!leak) {
        delete st;
        delete store;
      } else if (st->statsEnabled) st->printStats();
    }
  } teardown{stp, store, !build};
  EvalState &st = *stp;
  try {
    return runEvalCommandIn(o, build, st, store);
  } catch (nixfe::ParseError &e) {
    lineToStderr(formatParseError(e));
    return 1;
  } catch (EvalError &e) {
    lineToStderr(formatError(&st, e));
    return 1;
  } catch (nixstore::Error &e) {
    lineToStderr(composite::cat("error: ", e.what()));
    return 1;
  }
}

int runEvalCommandIn(Options &o, bool build, EvalState &st, nixstore::Store *store) {
  auto autoArgs = buildAutoArgs(st, o);
  if (o.attrPaths.empty()) o.attrPaths.append("");


  auto handleParsed = [&](composite::Text text, std::string_view baseDir, std::string_view name,
                          std::string_view path) -> Value * {
    nixfe::Origin *origin = nixfe::newOrigin();
    origin->name = composite::Text(name);
    origin->path = composite::Text(path);
    origin->baseDir = composite::Text(baseDir);
    origin->text = nixfe::Source::fromString(composite::mv(text));
    st.origins.append(origin);
    if (o.parseOnly) {
      st.lowerToMLIR(origin); // static checks (undefined variables), like bindVars
      nixfe::ParseOptions po = st.parseOptions();
      po.lintAbsolutePaths = po.lintShortPaths = po.lintUrls = nixfe::Lint::Ignore; // warned once, above
      composite::Text shown;
      nixfe::showSource(shown, origin, po);
      shown.put('\n');
      nixsys::toStdout(shown.data(), shown.size());
      return nullptr;
    }
    // The IR is printed whole: a deferred body would print as an empty shell, which is not the program.
    if (o.emitMLIR) st.settings.deferBodies = false;
    auto op = st.lowerToMLIR(origin);
    if (o.emitMLIR) {
      mlir::OpPrintingFlags flags;
      flags.enableDebugInfo(false);
      op->print(llvm::outs(), flags);
      llvm::outs() << "\n";
      llvm::outs().flush();
      return nullptr;
    }
    return st.evalExprOp(op);
  };

  // The roots, read and evaluated in turn: stdin, or each --expr text, or each file.
  if (!o.readStdin && !o.fromArgs && o.files.empty()) o.files.append("./default.nix");
  auto rootOf = [&](uint32_t i) -> Value * {
    if (o.readStdin) return handleParsed(readStdin(), cwdPath(), "«stdin»", "");
    std::string_view f = o.files[i];
    if (o.fromArgs) return handleParsed(composite::Text(f), cwdPath(), "«string»", "");
    composite::Text p = lookupFileArg(st, f);
    if (o.findFile) {
      lineToStdout(p);
      return nullptr;
    }
    composite::Text resolved = st.resolveExprPath(st.realisePath(p, nullptr));
    if (resolved.size() > 5 && resolved.substr(resolved.size() - 5) == ".mlir") return st.evalMLIRFile(resolved, "");
    composite::Text text = nixstore::readFile(resolved);
    return handleParsed(composite::mv(text), nixstore::dirOf(resolved), resolved, resolved);
  };

  int rootNr = 0;
  composite::MutableSeries<composite::Text> buildOutputs;
  for (uint32_t i = 0, nRoots = o.readStdin ? 1 : o.files.size(); i < nRoots; i++) {
    Value *root = rootOf(i);
    if (!root) continue;
    for (auto &ap : o.attrPaths) {
      Value &v = *findAlongAttrPath(st, ap, autoArgs, *root);
      st.forceValue(v);
      NixStringContext ctx;
      if (o.evalOnly) {
        Value vRes;
        if (autoArgs.empty()) vRes = v;
        else st.autoCallFunction(autoArgs, v, vRes);
        if (o.raw) {
          composite::Text raw = st.coerceToString(vRes, ctx, false, true);
          nixsys::toStdout(raw.data(), raw.size());
        } else if (o.xml) {
          composite::Text xml;
          try {
            st.printValueAsXML(xml, vRes, o.strict, o.location, ctx);
          } catch (...) {
            nixsys::toStdout(xml.data(), xml.size()); // the part a stream had taken before the error stays on standard output
            throw;
          }
          nixsys::toStdout(xml.data(), xml.size());
        } else if (o.json) {
          JsonOut js;
          st.printValueAsJSON(js, vRes, o.strict, ctx, true);
          nixsys::lineToStdout(js.view().data(), js.view().size());
          fflush(stdout);
        } else {
          if (o.strict) st.forceValueDeep(vRes);
          composite::WordTable<char> seen; // the sets and lists met, by address
          composite::Text shown;
          try {
            st.printValue(shown, vRes, &seen);
          } catch (...) {
            nixsys::toStdout(shown.data(), shown.size()); // as above
            throw;
          }
          nixsys::lineToStdout(shown.data(), shown.size());
          fflush(stdout);
        }
      } else {
        composite::MutableSeries<DrvInfo> drvs;
        composite::WordTable<bool> done; // the sets met, by address
        getDerivations(st, v, "", autoArgs, drvs, done);
        for (auto &d : drvs) {
          if (!build) {
            composite::Text out = d.drvPath.clone();
            if (!o.addRoot.empty()) {
              composite::Text rootName = absPath(o.addRoot);
              if (++rootNr > 1) rootName.put('-').putInt(rootNr);
              store->addPermRoot(d.drvPath, rootName);
              out = composite::mv(rootName);
            }
            if (d.outputName != "out") out.put('!').put(d.outputName);
            lineToStdout(out);
          } else {
            if (o.dryRun) {
              lineToStderr(composite::cat("these derivations will be built:\n  ", d.drvPath));
              continue;
            }
            auto outs = store->buildDerivation(d.drvPath);
            composite::Text outPath = outs.at(d.outputName).clone();
            if (!o.noOutLink) {
              composite::Text link = o.outLink.clone();
              if (++rootNr > 1) link.put('-').putInt(rootNr);
              if (d.outputName != "out") link.put('-').put(d.outputName);
              store->addPermRoot(outPath, absPath(link));
            }
            buildOutputs.append(composite::mv(outPath));
          }
        }
      }
    }
  }
  for (auto &p : buildOutputs) lineToStdout(p);
  return 0;
}

int cmdInstantiate(int argc, char **argv, int start, bool build) {
  Options o;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    switch (optCode(a)) {
    case OPT_EVAL: o.evalOnly = true; break;
    case OPT_PARSE: o.parseOnly = true; o.evalOnly = true; break;
    case OPT_EMIT_MLIR: o.emitMLIR = true; o.evalOnly = true; break;
    case OPT_STRICT: o.strict = true; break;
    case OPT_JSON: o.json = true; break;
    case OPT_XML: o.xml = true; break;
    case OPT_RAW: o.raw = true; break;
    case OPT_NO_LOCATION: o.location = false; break;
    case OPT_FIND_FILE: o.findFile = true; break;
    case OPT_DRY_RUN: o.dryRun = true; break;
    case OPT_ADD_ROOT: if (++i >= argc) usage("--add-root requires an argument"); o.addRoot = argv[i]; break;
    case OPT_INDIRECT: break;
    case OPT_OUT_LINK: if (++i >= argc) usage("--out-link requires an argument"); o.outLink = argv[i]; break;
    case OPT_NO_OUT_LINK: o.noOutLink = true; break;
    case OPT_STDIN: o.readStdin = true; break;
    default:
      if (a.size() > 1 && a[0] == '-' && !o.fromArgs) usage(composite::cat("unrecognised flag '", a, "'"));
      o.files.append(composite::Text(a));
    }
  }
  if (o.parseOnly && o.files.empty() && !o.fromArgs) o.readStdin = true;
  return runEvalCommand(o, build);
}

extern "C" int64_t mlnix_ts_printenv(const int64_t *envs, int64_t nenv, const int64_t *args, int64_t nargs, char *into, int64_t cap);
int cmdStore(int argc, char **argv, int start) {
  Options o;
  Opt op = OPT_NONE;
  composite::MutableSeries<composite::Text> args;
  bool queryRefs = false, queryReqs = false, queryReferrers = false, queryDeriver = false, queryOutputs = false,
       queryHash = false, querySize = false, includeOutputs = false, printInvalid = false;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    switch (Opt c = optCode(a)) {
    case OPT_OP_ADD: case OPT_OP_ADD_FIXED: case OPT_OP_REALISE: case OPT_OP_QUERY: case OPT_OP_DUMP: case OPT_OP_GC:
    case OPT_OP_DELETE: case OPT_OP_VERIFY: case OPT_OP_PRINT_ENV: case OPT_OP_RESTORE: case OPT_OP_OTHER:
      op = c; // -r and -q are the operations --realise and --query: the same codes
      break;
    case OPT_Q_REFS: queryRefs = true; break;
    case OPT_Q_REQS: queryReqs = true; break;
    case OPT_Q_REFERRERS: queryReferrers = true; break;
    case OPT_Q_DERIVER: queryDeriver = true; break;
    case OPT_Q_OUTPUTS: queryOutputs = true; break;
    case OPT_Q_HASH: queryHash = true; break;
    case OPT_Q_SIZE: querySize = true; break;
    case OPT_INCLUDE_OUTPUTS: includeOutputs = true; break;
    case OPT_PRINT_INVALID: printInvalid = true; break;
    case OPT_RECURSIVE: break;
    default: args.append(composite::Text(a));
    }
  }
  finishOptions(o);
  nixstore::Store store(o.store);
  auto toStore = [&](std::string_view p) {
    composite::Text ap(p);
    if (!nixstore::isInStore(store.storeDir(), ap)) {
      ap = absPath(p);
      // Follow result symlinks into the (possibly chroot) store.
      char buf[PATH_MAX];
      ssize_t n = readlink(ap.c_str(), buf, sizeof buf - 1);
      if (n > 0) {
        ap = composite::Text(buf, size_t(n));
        if (!o.store.realRoot.empty() && ap.rfind(o.store.realRoot, 0) == 0) ap = composite::Text(ap.substr(o.store.realRoot.size()));
      }
    }
    return nixstore::toStorePath(store.storeDir(), ap);
  };
  try {
    if (op == OPT_OP_ADD) {
      for (auto &a : args) lineToStdout(store.addToStore(nixstore::baseNameOf(absPath(a)), absPath(a)));
    } else if (op == OPT_OP_ADD_FIXED) {
      if (args.empty()) usage("--add-fixed requires an algorithm");
      auto algo = nixstore::parseHashAlgo(args[0]);
      if (!algo) usage(composite::cat("unknown hash algorithm '", args[0], "'"));
      for (size_t i = 1; i < args.size(); i++)
        lineToStdout(store.addToStore(nixstore::baseNameOf(absPath(args[i])), absPath(args[i]), nixstore::FileIngestionMethod::Flat, *algo));
    } else if (op == OPT_OP_REALISE) {
      for (auto &a : args) {
        composite::Text p = toStore(a);
        if (p.size() > 4 && p.substr(p.size() - 4) == ".drv") {
          for (auto &[n, out] : store.buildDerivation(p)) lineToStdout(out);
        } else {
          store.ensurePath(p);
          lineToStdout(p);
        }
      }
    } else if (op == OPT_OP_QUERY) {
      nixstore::SortedSet out;
      composite::MutableSeries<composite::Text> ordered;
      for (auto &a : args) {
        composite::Text p = toStore(a);
        if (queryRefs) {
          auto info = store.queryPathInfo(p);
          if (!info) throw nixstore::Error(composite::cat("path '", p, "' is not valid"));
          for (auto &r : info->references) out.insert(r);
        } else if (queryReqs) {
          auto c = store.computeFSClosure(nixstore::SortedSet::of(p), includeOutputs);
          out.insert(c.begin(), c.end());
        } else if (queryReferrers) {
          auto r = store.queryReferrers(p);
          out.insert(r.begin(), r.end());
        } else if (queryDeriver) {
          auto info = store.queryPathInfo(p);
          ordered.append(info && !info->deriver.empty() ? info->deriver.clone() : composite::Text("unknown-deriver"));
        } else if (queryOutputs) {
          const auto &d = store.readDerivation(p);
          for (auto &[n, o2] : d.outputs) ordered.append(o2.path.clone());
        } else if (queryHash || querySize) {
          auto info = store.queryPathInfo(p);
          if (!info) throw nixstore::Error(composite::cat("path '", p, "' is not valid"));
          ordered.append(queryHash ? info->narHash.to_string(nixstore::HashFormat::Nix32, true)
                                      : composite::str(info->narSize));
        } else {
          ordered.append(composite::mv(p));
        }
      }
      // the set's rows, then the ordered list: one line each, written once (mlnix_tf_lines)
      composite::MutableSeries<int64_t> recs;
      for (auto &p : out) recs.append(int64_t(intptr_t(p.data()))), recs.append(int64_t(p.size()));
      for (auto &p : ordered) recs.append(int64_t(intptr_t(p.data()))), recs.append(int64_t(p.size()));
      nixsys::toStdout(drained([&](char *b, int64_t cap) { return mlnix_tf_lines(recs.data(), int64_t(recs.size() / 2), 0, b, cap); }));
    } else if (op == OPT_OP_DUMP) {
      for (auto &a : args)
        nixstore::dumpPath(absPath(a), [](std::string_view d) { nixsys::toStdout(d.data(), d.size()); });
    } else if (op == OPT_OP_RESTORE) {
      if (args.size() != 1) usage("--restore requires a path");
      nixstore::restorePath(absPath(args[0]), readStdin());
    } else if (op == OPT_OP_GC) {
      composite::MutableSeries<composite::Text> deleted;
      store.collectGarbage(printInvalid, deleted);
      composite::MutableSeries<int64_t> recs; // the deleted paths, a line each: "deleting 'P'", or P with --print-dead
      for (auto &d : deleted) recs.append(int64_t(intptr_t(d.data()))), recs.append(int64_t(d.size()));
      nixsys::toStdout(drained([&](char *p, int64_t cap) { return mlnix_tf_lines(recs.data(), int64_t(deleted.size()), printInvalid ? 0 : 1, p, cap); }));
      nixsys::lineToStderr(drained([&](char *p, int64_t cap) { return mlnix_tf_count(int64_t(deleted.size()), p, cap); }));
    } else if (op == OPT_OP_DELETE) {
      for (auto &a : args) {
        composite::Text p = toStore(a);
        if (!store.deletePath(p)) throw nixstore::Error(composite::cat("cannot delete path '", p, "' since it is still alive"));
      }
    } else if (op == OPT_OP_VERIFY) {
      int bad = 0;
      composite::MutableSeries<composite::Text> paths = args.empty() ? store.allValidPaths() : composite::MutableSeries<composite::Text>{};
      for (auto &a : args) paths.append(toStore(a));
      for (auto &p : paths) {
        auto info = store.queryPathInfo(p);
        if (!info) { lineToStderr(composite::cat("path '", p, "' is not valid")); bad++; continue; }
        auto [h, n] = nixstore::hashPath(store.toReal(p));
        if (!(h == info->narHash)) {
          lineToStderr(composite::cat("path '", p, "' was modified! expected hash '", info->narHash.to_string(nixstore::HashFormat::Nix32, true),
                   "', got '", h.to_string(nixstore::HashFormat::Nix32, true), "'"));
          bad++;
        }
      }
      return bad ? 1 : 0;
    } else if (op == OPT_OP_PRINT_ENV) {
      for (auto &a : args) {
        const auto &d = store.readDerivation(toStore(a));
        composite::MutableSeries<int64_t> envs, xs; // windows: (key, value) per variable, then the arguments
        for (auto &[k, v] : d.env) for (const composite::Text *t : {&k, &v}) envs.append(int64_t(intptr_t(t->data()))), envs.append(t->size());
        for (auto &x : d.args) xs.append(int64_t(intptr_t(x.data()))), xs.append(x.size());
        nixsys::toStdout(drained([&](char *p, int64_t cap) { return mlnix_ts_printenv(envs.data(), d.env.size(), xs.data(), d.args.size(), p, cap); }));
      }
    } else {
      usage("no operation specified");
    }
  } catch (nixstore::Error &e) {
    lineToStderr(composite::cat("error: ", e.what()));
    return 1;
  }
  return 0;
}

int cmdHash(int argc, char **argv, int start) {
  Opt mode = OPT_NONE;
  nixstore::HashAlgo algo = nixstore::HashAlgo::SHA256;
  nixstore::HashFormat fmt = nixstore::HashFormat::Base16;
  bool flat = false, sri = false;
  composite::MutableSeries<composite::Text> args;
  bool algoGiven = false;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
    switch (optCode(a)) {
    case OPT_TYPE: {
      if (++i >= argc) usage("--type requires an argument");
      auto t = nixstore::parseHashAlgo(argv[i]);
      if (!t) usage(composite::cat("unknown hash algorithm '", argv[i], "'"));
      algo = *t;
      algoGiven = true;
      break;
    }
    case OPT_FLAT: flat = true; break;
    case OPT_BASE32: fmt = nixstore::HashFormat::Nix32; break;
    case OPT_BASE16: fmt = nixstore::HashFormat::Base16; break;
    case OPT_BASE64: fmt = nixstore::HashFormat::Base64; break;
    case OPT_SRI: sri = true; break;
    case OPT_TRUNCATE: break;
    case OPT_TO_BASE32: case OPT_TO_NIX32: case OPT_TO_BASE16: case OPT_TO_BASE64: case OPT_TO_SRI: case OPT_MODE_PATH: case OPT_MODE_FILE:
      mode = optCode(a); break;
    default: args.append(composite::Text(a));
    }
  }
  const bool toMode = mode == OPT_TO_BASE32 || mode == OPT_TO_NIX32 || mode == OPT_TO_BASE16 || mode == OPT_TO_BASE64 || mode == OPT_TO_SRI;
  try {
    for (auto &a : args) {
      if (toMode) {
        if (!algoGiven && a.find(':') == composite::npos && a.find('-') == composite::npos)
          throw nixstore::Error(composite::cat("hash '", a, "' does not include a type, nor is the type otherwise known from context"));
        auto h = nixstore::parseHash(a, algo);
        nixstore::HashFormat f = mode == OPT_TO_BASE16 ? nixstore::HashFormat::Base16
                                 : mode == OPT_TO_BASE64 ? nixstore::HashFormat::Base64
                                 : mode == OPT_TO_SRI ? nixstore::HashFormat::SRI : nixstore::HashFormat::Nix32;
        lineToStdout(h.to_string(f, f == nixstore::HashFormat::SRI));
        continue;
      }
      nixstore::Hash h = (flat || mode == OPT_MODE_FILE) ? nixstore::hashFile(algo, absPath(a))
                                                          : nixstore::hashPath(absPath(a), nullptr, algo).a;
      lineToStdout(sri ? h.to_string(nixstore::HashFormat::SRI, true) : h.to_string(fmt, false));
    }
  } catch (nixstore::Error &e) {
    lineToStderr(composite::cat("error: ", e.what()));
    return 1;
  }
  return 0;
}

int cmdDerivationShow(int argc, char **argv, int start) {
  Options o;
  composite::MutableSeries<composite::Text> args;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    args.append(composite::Text(a));
  }
  finishOptions(o);
  nixstore::Store store(o.store);
  nixsys::toStdout("{"); // a derivation at a time, as it was: one that cannot be read leaves the ones before it on standard output
  bool first = true;
  for (auto &a : args) {
    composite::Text p = nixstore::isInStore(store.storeDir(), a) ? a.clone() : absPath(a);
    const auto &d = store.readDerivation(p);
    composite::Text j = nixstore::derivationToJSON(store.storeDir(), p, d);
    nixsys::toStdout(first ? "" : ",");
    nixsys::toStdout(j.data() + 1, uint32_t(j.size() - 2));
    first = false;
  }
  nixsys::toStdout("}\n");
  return 0;
}

extern "C" int64_t mlnix_ts_help(char *into, int64_t cap);
void printHelp() { nixsys::toStdout(drained(mlnix_ts_help)); }

extern "C" int64_t mlnix_ts_nixlist(const int64_t *wins, int64_t n, char *into, int64_t cap);
extern "C" int64_t mlnix_ts_args(char **argv, int64_t argc, int64_t cmd, char **out);
int realMain(int argc, char **argv) {
  composite::Text prog = nixstore::baseNameOf(argv[0]);
  Opt progCode = optCode(prog.data(), prog.size());
  if (progCode == OPT_PROG_NIX) { // the nix command is Nix (lib/Corepkgs/cli.nix); here only its argument vector is made a Nix list
    composite::MutableSeries<int64_t> wins;
    for (int i = 1; i < argc; i++) wins.append(int64_t(intptr_t(argv[i]))), wins.append(int64_t(strlen(argv[i])));
    composite::Text expr = drained([&](char *p, int64_t cap) { return mlnix_ts_nixlist(wins.data(), argc - 1, p, cap); });
    const char *nargs[] = {argv[0], "--eval", "--raw", "--read-write-mode", "-E", expr.c_str()};
    return cmdInstantiate(6, const_cast<char **>(nargs), 1, false);
  }
  if (progCode == OPT_PROG_INSTANTIATE) return cmdInstantiate(argc, argv, 1, false);
  if (progCode == OPT_PROG_BUILD) return cmdInstantiate(argc, argv, 1, true);
  if (progCode == OPT_PROG_STORE) return cmdStore(argc, argv, 1);
  if (progCode == OPT_PROG_HASH) return cmdHash(argc, argv, 1);
  if (argc < 2) {
    printHelp();
    return 1;
  }
  std::string_view cmd = argv[1];
  switch (Opt c = optCode(cmd)) {
  case OPT_HELP:
    printHelp();
    return 0;
  case OPT_VERSION: {
    static const char version[] = "mlnix (Nix-compatible) 2.35.4\n";
    nixsys::toStdout(version, sizeof version - 1);
    return 0;
  }
  case OPT_INSTANTIATE: return cmdInstantiate(argc, argv, 2, false);
  case OPT_BUILD: return cmdInstantiate(argc, argv, 2, true);
  case OPT_EVAL_CMD: case OPT_PARSE_CMD: case OPT_EMIT_CMD: case OPT_RUN_CMD: { // argv[0], the command's flags, the rest
    composite::MutableSeries<char *> nargs(size_t(argc) + 1);
    int64_t n = mlnix_ts_args(argv, argc, c == OPT_EVAL_CMD ? 0 : c == OPT_PARSE_CMD ? 1 : c == OPT_EMIT_CMD ? 2 : 3, nargs.data());
    return cmdInstantiate(int(n), nargs.data(), 1, false);
  }
  case OPT_PRIMOPS: {
    // Dump the live primop registry ("<base-env key> <arity>", sorted by name in mlnix_tf_primops); the continent
    // dialects (include/NixDialect/NixPrims.td) must stay in sync with it.
    Options o;
    o.readOnly = true;
    finishOptions(o);
    o.store.readOnly = true;
    nixstore::Store store(o.store);
    EvalState st(std::move(o.eval), &store);
    composite::MutableSeries<int64_t> recs; // (name ptr, name len, arity) per primop, in the registry's order
    for (auto &e : st.baseEnv)
      if (e.v->type == VType::PrimOp)
        recs.append(int64_t(intptr_t(e.p))), recs.append(int64_t(e.n)), recs.append(int64_t(e.v->primOp->arity));
    nixsys::toStdout(drained([&](char *p, int64_t cap) { return mlnix_tf_primops(recs.data(), int64_t(recs.size() / 3), p, cap); }));
    return 0;
  }
  case OPT_STORE_CMD: return cmdStore(argc, argv, 2);
  case OPT_HASH_CMD: return cmdHash(argc, argv, 2);
  case OPT_DERIVATION:
    if (argc < 3 || optCode(argv[2]) != OPT_SHOW) usage("expected 'mlnix derivation show DRV...'");
    return cmdDerivationShow(argc, argv, 3);
  default:
    break;
  }
  usage(composite::cat("unknown command '", cmd, "'"));
}

} // namespace

#if defined(__linux__) && defined(__GLIBC__)
/// Ask glibc malloc for transparent huge pages (glibc 2.35+; THP in madvise or always mode).  An
/// evaluation touches ~1.8 GiB, and the first touch of a 4 KiB page costs about 4 us under WSL2: with
/// these tunables a NixOS evaluation goes from 450k page faults to 70k and runs 23% faster, user time
/// included (fewer TLB misses).  Tunables are read by the dynamic loader, so the program re-executes
/// itself once with them set; the second image removes them again so that child processes (builders)
/// do not inherit them.  MLNIX_NO_HUGEPAGES=1 opts out, and a GLIBC_TUNABLES that is already set is
/// left alone.
static void useHugePages(char **argv) {
  if (getenv("MLNIX_HUGEPAGES")) { // this is the second image
    unsetenv("MLNIX_HUGEPAGES");
    unsetenv("GLIBC_TUNABLES");
    return;
  }
  if (getenv("MLNIX_NO_HUGEPAGES") || getenv("GLIBC_TUNABLES")) return;
  setenv("GLIBC_TUNABLES", "glibc.malloc.hugetlb=1:glibc.malloc.top_pad=268435456", 1);
  setenv("MLNIX_HUGEPAGES", "1", 1);
  execv("/proc/self/exe", argv); // returns only on failure: carry on as we are
  unsetenv("GLIBC_TUNABLES");
  unsetenv("MLNIX_HUGEPAGES");
}
#endif

int main(int argc, char **argv) {
#if defined(__linux__) && defined(__GLIBC__)
  useHugePages(argv);
#endif
  nixprefetch::init(argc, argv); // MLNIX_PREFETCH=record:FILE | replay:FILE | auto
  int rc = 1;
  try {
    rc = runWithLargeStack([&]() -> int {
      try {
        return realMain(argc, argv);
      } catch (nixfe::ParseError &e) {
        lineToStderr(formatParseError(e));
        return 1;
      } catch (EvalError &e) {
        lineToStderr(formatError(nullptr, e));
        return 1;
      } catch (nixstore::Error &e) {
        lineToStderr(composite::cat("error: ", e.what()));
        return 1;
      }
    });
  } catch (std::exception &e) {
    lineToStderr(composite::cat("error: ", e.what()));
    return 1;
  }
  return rc;
}
