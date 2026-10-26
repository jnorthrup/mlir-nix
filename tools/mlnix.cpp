//===- mlnix.cpp - Nix-compatible command line driver ---------------------===//
//
//   mlnix instantiate|build|eval|parse|emit-mlir|run-mlir|store|hash|derivation
//
// When invoked through a symlink named nix-instantiate, nix-build, nix-store
// or nix-hash, behaves like that command.
//
//===----------------------------------------------------------------------===//

#include "Nix/Eval.h"
#include "Nix/MLIRGen.h"

#include "mlir/IR/AsmState.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/Support/raw_ostream.h"

#include <cstring>
#include <iostream>
#include <map>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

using namespace nixev;
namespace nd = mlir::nix;

namespace nixev {
extern bool tomlTimestamps;
}

namespace {

[[noreturn]] void usage(const std::string &msg) {
  std::cerr << "error: " << msg << "\nTry 'mlnix --help' for more information.\n";
  exit(1);
}

std::string defaultSystem() {
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

std::string absPath(const std::string &p) {
  if (!p.empty() && p[0] == '/') return nixfe::canonPath(p);
  char buf[PATH_MAX];
  std::string cwd = getcwd(buf, sizeof buf) ? buf : "/";
  return nixfe::canonPath(cwd + "/" + p);
}

std::vector<SearchPathElem> parseNixPath(const std::string &s) {
  std::vector<SearchPathElem> res;
  size_t i = 0;
  while (i < s.size()) {
    size_t j = i;
    std::string elem;
    while (j < s.size()) {
      if (s[j] == ':') {
        if (s.compare(j, 3, "://") == 0) { elem += "://"; j += 3; continue; }
        break;
      }
      elem += s[j++];
    }
    if (!elem.empty()) {
      SearchPathElem e;
      auto eq = elem.find('=');
      if (eq != std::string::npos) { e.prefix = elem.substr(0, eq); e.path = elem.substr(eq + 1); }
      else e.path = elem;
      res.push_back(e);
    }
    i = j + 1;
  }
  return res;
}

struct Options {
  std::vector<std::string> files;
  std::vector<std::string> attrPaths;
  std::vector<std::pair<std::string, std::string>> argExprs, argStrs;
  std::vector<std::string> includes;
  bool fromArgs = false, readStdin = false, evalOnly = false, parseOnly = false, strict = false;
  bool json = false, xml = false, raw = false, location = true, findFile = false;
  bool readWrite = false, readOnly = false, dryRun = false, noOutLink = false, showTrace = false;
  bool emitMLIR = false, noOpt = false;
  std::string outLink = "result", addRoot;
  EvalSettings eval;
  nixstore::StoreSettings store;
  bool storeDirSet = false, storeRootSet = false;
};

/// Parse options shared by all evaluating commands. Returns false if `arg`
/// was not recognised.
bool parseCommon(Options &o, const std::string &arg, int &i, int argc, char **argv) {
  auto next = [&]() -> std::string {
    if (i + 1 >= argc) usage("flag '" + arg + "' requires an argument");
    return argv[++i];
  };
  if (arg == "-I" || arg == "--include") {
    std::string v = next();
    o.includes.push_back(v);
  } else if (arg.rfind("-I", 0) == 0 && arg.size() > 2) {
    o.includes.push_back(arg.substr(2));
  } else if (arg == "--arg") {
    std::string n = next(), v = next();
    o.argExprs.push_back({n, v});
  } else if (arg == "--argstr") {
    std::string n = next(), v = next();
    o.argStrs.push_back({n, v});
  } else if (arg == "-A" || arg == "--attr") {
    o.attrPaths.push_back(next());
  } else if (arg == "-E" || arg == "--expr") {
    o.fromArgs = true;
  } else if (arg == "--show-trace") {
    o.eval.showTrace = true;
  } else if (arg == "--trace-verbose") {
    o.eval.traceVerbose = true;
  } else if (arg == "--abort-on-warn") {
    o.eval.abortOnWarn = true;
  } else if (arg == "--pure-eval") {
    o.eval.pureEval = true;
  } else if (arg == "--impure") {
    o.eval.pureEval = false;
  } else if (arg == "--restrict-eval") {
    o.eval.restrictEval = true;
  } else if (arg == "--extra-experimental-features" || arg == "--experimental-features") {
    std::string f = next();
    std::istringstream ss(f);
    std::string w;
    while (ss >> w) {
      if (w == "pipe-operators") o.eval.pipeOperators = true;
      if (w == "parse-toml-timestamps") nixev::tomlTimestamps = true;
    }
  } else if (arg == "--option") {
    std::string n = next(), v = next();
    if (n == "max-call-depth") o.eval.maxCallDepth = std::stoul(v);
    else if ((n == "extra-experimental-features" || n == "experimental-features") && v.find("pipe-operators") != std::string::npos)
      o.eval.pipeOperators = true;
    else if (n == "system") o.eval.currentSystem = v;
    else if (n == "pure-eval") o.eval.pureEval = v == "true";
  } else if (arg == "--lint-absolute-path-literals" || arg == "--lint-short-path-literals" || arg == "--lint-url-literals") {
    std::string v = next();
    nixfe::Lint l = v == "warn" ? nixfe::Lint::Warn : v == "fatal" ? nixfe::Lint::Fatal : nixfe::Lint::Ignore;
    if (v != "warn" && v != "fatal" && v != "ignore")
      usage("option '" + arg.substr(2) + "' has invalid value '" + v + "' (expected 'ignore', 'warn', or 'fatal')");
    if (arg == "--lint-absolute-path-literals") o.eval.lintAbsolutePaths = l;
    else if (arg == "--lint-short-path-literals") o.eval.lintShortPaths = l;
    else o.eval.lintUrls = l;
  } else if (arg == "--system") {
    o.eval.currentSystem = next();
  } else if (arg == "--store-dir") {
    o.store.storeDir = absPath(next());
    o.storeDirSet = true;
  } else if (arg == "--store") {
    std::string s = next();
    if (s == "dummy://") o.readOnly = true;
    else if (s.rfind("local?root=", 0) == 0) { o.store.realRoot = absPath(s.substr(11)); o.storeRootSet = true; }
    else if (s != "auto" && s != "local" && s != "daemon") { o.store.realRoot = absPath(s); o.storeRootSet = true; }
  } else if (arg == "--readonly-mode") {
    o.readOnly = true;
  } else if (arg == "--read-write-mode") {
    o.readWrite = true;
  } else if (arg == "-K" || arg == "--keep-failed") {
    o.store.keepFailed = true;
  } else if (arg == "-j" || arg == "--max-jobs" || arg == "--cores") {
    std::string v = next();
    if (arg == "--cores") o.store.cores = std::stoul(v);
  } else if (arg == "--no-opt") {
    o.noOpt = true;
  } else if (arg == "-v" || arg == "--verbose" || arg == "-Q" || arg == "--no-build-output" || arg == "--quiet" ||
             arg == "--no-substitute" || arg == "--fallback" || arg == "-L" || arg == "--print-build-logs") {
  } else {
    return false;
  }
  return true;
}

void finishOptions(Options &o) {
  if (o.eval.currentSystem.empty()) {
    const char *sys = getenv("NIX_SYSTEM");
    o.eval.currentSystem = sys ? sys : defaultSystem();
  }
  // NIX_PATH and -I.
  for (auto it = o.includes.rbegin(); it != o.includes.rend(); ++it) {
    auto v = parseNixPath(*it);
    o.eval.nixPath.insert(o.eval.nixPath.begin(), v.begin(), v.end());
  }
  if (const char *np = getenv("NIX_PATH")) {
    auto v = parseNixPath(np);
    o.eval.nixPath.insert(o.eval.nixPath.end(), v.begin(), v.end());
  }
  for (auto &e : o.eval.nixPath)
    if (e.path.find("://") == std::string::npos) e.path = absPath(e.path);
  if (o.noOpt) o.eval.optimize = false;
  // Store configuration.
  if (!o.storeDirSet) {
    if (const char *sd = getenv("NIX_STORE_DIR")) o.store.storeDir = sd;
    else if (const char *sd2 = getenv("NIX_STORE")) o.store.storeDir = sd2;
  }
  if (const char *r = getenv("NIX_REMOTE"); r && std::string(r) == "dummy://") o.readOnly = true;
  if (!o.storeRootSet) {
    if (const char *r = getenv("MLNIX_STORE_ROOT")) o.store.realRoot = r;
    else {
      // Use the store directory directly if we can write to it; otherwise
      // fall back to a chroot-style store under the user's data directory.
      std::string sd = o.store.storeDir;
      bool usable = access(sd.c_str(), W_OK) == 0 ||
                    (access(sd.c_str(), F_OK) != 0 && access(nixstore::dirOf(sd).c_str(), W_OK) == 0);
      if (!usable) {
        const char *home = getenv("HOME");
        o.store.realRoot = std::string(home ? home : "/tmp") + "/.local/share/mlnix/root";
      }
    }
  }
  if (const char *sd = getenv("MLNIX_STATE_DIR")) o.store.stateDir = sd;
  o.store.readOnly = o.readOnly;
  o.store.system = o.eval.currentSystem;
}

std::map<std::string, Value *> buildAutoArgs(EvalState &st, const Options &o) {
  std::map<std::string, Value *> res;
  char buf[PATH_MAX];
  std::string cwd = getcwd(buf, sizeof buf) ? buf : "/";
  for (auto &[n, e] : o.argExprs) res[n] = st.evalString(e, cwd, "«string»");
  for (auto &[n, s] : o.argStrs) {
    Value *v = st.allocValue();
    st.mkString(*v, s);
    res[n] = v;
  }
  return res;
}

/// findAlongAttrPath
Value *findAlongAttrPath(EvalState &st, const std::string &path, const std::map<std::string, Value *> &autoArgs,
                         Value &root) {
  std::vector<std::string> comps;
  {
    std::string cur;
    bool quoted = false;
    for (char c : path) {
      if (c == '"') { quoted = !quoted; continue; }
      if (c == '.' && !quoted) { comps.push_back(cur); cur.clear(); continue; }
      cur += c;
    }
    if (quoted) throw EvalError("missing closing quote in selection path '" + path + "'");
    if (!path.empty()) comps.push_back(cur);
  }
  Value *v = &root;
  for (auto &c : comps) {
    if (c.empty()) throw EvalError("empty attribute name in selection path '" + path + "'");
    Value *vNew = st.allocValue();
    st.autoCallFunction(autoArgs, *v, *vNew);
    v = vNew;
    st.forceValue(*v);
    bool isIndex = !c.empty() && std::all_of(c.begin(), c.end(), [](char ch) { return isdigit((unsigned char)ch); });
    if (!isIndex) {
      if (v->type != VType::Attrs)
        throw TypeError("the expression selected by the selection path '" + path + "' should be a set but is " +
                        EvalState::showType(*v));
      const Attr *a = v->attrs->get(st.symbols.create(c));
      if (!a) throw EvalError("attribute '" + c + "' in selection path '" + path + "' not found");
      v = a->value;
    } else {
      if (v->type != VType::List)
        throw TypeError("the expression selected by the selection path '" + path + "' should be a list but is " +
                        EvalState::showType(*v));
      size_t idx = std::stoul(c);
      if (idx >= v->list.size) throw EvalError("list index " + c + " in selection path '" + path + "' is out of range");
      v = v->list.elems[idx];
    }
  }
  return v;
}

struct DrvInfo {
  std::string drvPath, outputName, attrPath;
  std::map<std::string, std::string> outputs;
};

bool getDerivation(EvalState &st, Value &v, const std::string &attrPath, std::vector<DrvInfo> &drvs,
                   std::set<const void *> &done) {
  st.forceValue(v);
  if (!st.isDerivation(v)) return true;
  if (!done.insert(v.attrs).second) return false;
  DrvInfo d;
  d.attrPath = attrPath;
  const Attr *dp = v.attrs->get(st.s.drvPath);
  if (!dp) throw EvalError("derivation does not contain a 'drvPath' attribute");
  NixStringContext ctx;
  d.drvPath = st.coerceToString(*dp->value, ctx, false, false);
  d.outputName = "out";
  if (const Attr *on = v.attrs->get(st.s.outputName)) d.outputName = std::string(st.forceStringNoCtx(*on->value));
  drvs.push_back(d);
  return false;
}

void getDerivations(EvalState &st, Value &vIn, const std::string &prefix, const std::map<std::string, Value *> &autoArgs,
                    std::vector<DrvInfo> &drvs, std::set<const void *> &done) {
  Value v;
  st.autoCallFunction(autoArgs, vIn, v);
  if (!getDerivation(st, v, prefix, drvs, done)) return;
  if (v.type == VType::Attrs) {
    if (!done.insert(v.attrs).second) return;
    for (const Attr *a : v.attrs->lexicographicOrder(st.symbols)) {
      std::string p2 = prefix.empty() ? st.symbols[a->name].str() : prefix + "." + st.symbols[a->name].str();
      if (getDerivation(st, *a->value, p2, drvs, done)) {
        if (a->value->type == VType::Attrs) {
          const Attr *r = a->value->attrs->get(st.symbols.create("recurseForDerivations"));
          if (r && st.forceBool(*r->value, nullptr)) getDerivations(st, *a->value, p2, autoArgs, drvs, done);
        }
      }
    }
  } else if (v.type == VType::List) {
    for (size_t i = 0; i < v.list.size; i++) {
      std::string p2 = prefix.empty() ? std::to_string(i) : prefix + "." + std::to_string(i);
      if (getDerivation(st, *v.list.elems[i], p2, drvs, done))
        getDerivations(st, *v.list.elems[i], p2, autoArgs, drvs, done);
    }
  } else {
    throw TypeError("expression does not evaluate to a derivation (or a set or list of those)");
  }
}

std::string readStdin() {
  std::stringstream ss;
  ss << std::cin.rdbuf();
  return ss.str();
}

std::string cwdPath() {
  char buf[PATH_MAX];
  return getcwd(buf, sizeof buf) ? buf : "/";
}

/// Locate the file argument (handles <lookup> and directories).
std::string lookupFileArg(EvalState &st, const std::string &s) {
  if (s.size() > 2 && s.front() == '<' && s.back() == '>') {
    Value *np = st.baseEnvValue("__nixPath");
    return st.findFile(*np, s.substr(1, s.size() - 2), nullptr);
  }
  return absPath(s);
}

int runEvalCommandIn(Options &o, bool build, EvalState &st, std::shared_ptr<nixstore::Store> store);

int runEvalCommand(Options &o, bool build) {
  finishOptions(o);
  if (o.evalOnly && !o.readWrite) o.store.readOnly = true;
  auto store = std::make_shared<nixstore::Store>(o.store);
  EvalState st(o.eval, store);
  try {
    return runEvalCommandIn(o, build, st, store);
  } catch (nixfe::ParseError &e) {
    std::cout.flush();
    std::cerr << formatParseError(e) << std::endl;
    return 1;
  } catch (EvalError &e) {
    std::cout.flush();
    std::cerr << formatError(&st, e) << std::endl;
    return 1;
  } catch (nixstore::Error &e) {
    std::cout.flush();
    std::cerr << "error: " << e.what() << std::endl;
    return 1;
  }
}

int runEvalCommandIn(Options &o, bool build, EvalState &st, std::shared_ptr<nixstore::Store> store) {
  auto autoArgs = buildAutoArgs(st, o);
  if (o.attrPaths.empty()) o.attrPaths.push_back("");

  std::vector<std::pair<std::string, std::function<Value *()>>> exprs;
  std::vector<std::pair<nixfe::Expr *, std::shared_ptr<nixfe::Origin>>> parsed;

  auto handleParsed = [&](const std::string &text, const std::string &baseDir, const std::string &name,
                          const std::string &path) -> Value * {
    auto *arena = new nixfe::ExprArena();
    st.arenas.push_back(arena);
    auto origin = std::make_shared<nixfe::Origin>();
    origin->name = name;
    origin->path = path;
    origin->baseDir = baseDir;
    origin->text = std::make_shared<std::string>(text);
    st.origins.push_back(origin);
    nixfe::ParseOptions po = st.parseOptions();
    nixfe::Expr *e = nixfe::parse(*arena, origin, po);
    if (o.parseOnly) {
      st.lowerToMLIR(e, origin); // static checks (undefined variables), like bindVars
      nixfe::showExpr(std::cout, e);
      std::cout << "\n";
      return nullptr;
    }
    auto op = st.lowerToMLIR(e, origin);
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

  std::vector<std::function<Value *()>> roots;
  if (o.readStdin) {
    roots.push_back([&]() { return handleParsed(readStdin(), cwdPath(), "«stdin»", ""); });
  } else if (o.fromArgs) {
    for (auto &f : o.files) roots.push_back([&, f]() { return handleParsed(f, cwdPath(), "«string»", ""); });
  } else {
    if (o.files.empty()) o.files.push_back("./default.nix");
    for (auto &f : o.files)
      roots.push_back([&, f]() -> Value * {
        std::string p = lookupFileArg(st, f);
        if (o.findFile) {
          std::cout << p << "\n";
          return nullptr;
        }
        std::string resolved = st.resolveExprPath(st.realisePath(p, nullptr));
        if (resolved.size() > 5 && resolved.substr(resolved.size() - 5) == ".mlir") return st.evalMLIRFile(resolved, "");
        std::string text = nixstore::readFile(resolved);
        return handleParsed(text, nixstore::dirOf(resolved), resolved, resolved);
      });
  }

  int rootNr = 0;
  std::vector<std::string> buildOutputs;
  for (auto &r : roots) {
    Value *root = r();
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
          std::cout << st.coerceToString(vRes, ctx, false, true);
        } else if (o.xml) {
          st.printValueAsXML(std::cout, vRes, o.strict, o.location, ctx);
        } else if (o.json) {
          st.printValueAsJSON(std::cout, vRes, o.strict, ctx, true);
          std::cout << std::endl;
        } else {
          if (o.strict) st.forceValueDeep(vRes);
          std::set<const void *> seen;
          st.printValue(std::cout, vRes, &seen);
          std::cout << std::endl;
        }
      } else {
        std::vector<DrvInfo> drvs;
        std::set<const void *> done;
        getDerivations(st, v, "", autoArgs, drvs, done);
        for (auto &d : drvs) {
          if (!build) {
            std::string out = d.drvPath;
            if (!o.addRoot.empty()) {
              std::string rootName = absPath(o.addRoot);
              if (++rootNr > 1) rootName += "-" + std::to_string(rootNr);
              store->addPermRoot(d.drvPath, rootName);
              out = rootName;
            }
            std::cout << out << (d.outputName != "out" ? "!" + d.outputName : "") << "\n";
          } else {
            if (o.dryRun) {
              std::cerr << "these derivations will be built:\n  " << d.drvPath << "\n";
              continue;
            }
            auto outs = store->buildDerivation(d.drvPath);
            std::string outPath = outs.at(d.outputName);
            if (!o.noOutLink) {
              std::string link = o.outLink;
              if (++rootNr > 1) link += "-" + std::to_string(rootNr);
              if (d.outputName != "out") link += "-" + d.outputName;
              store->addPermRoot(outPath, absPath(link));
            }
            buildOutputs.push_back(outPath);
          }
        }
      }
    }
  }
  for (auto &p : buildOutputs) std::cout << p << "\n";
  return 0;
}

int cmdInstantiate(int argc, char **argv, int start, bool build) {
  Options o;
  for (int i = start; i < argc; i++) {
    std::string a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    if (a == "--eval" || a == "--eval-only") o.evalOnly = true;
    else if (a == "--parse" || a == "--parse-only") { o.parseOnly = true; o.evalOnly = true; }
    else if (a == "--emit-mlir") { o.emitMLIR = true; o.evalOnly = true; }
    else if (a == "--strict") o.strict = true;
    else if (a == "--json") o.json = true;
    else if (a == "--xml") o.xml = true;
    else if (a == "--raw") o.raw = true;
    else if (a == "--no-location") o.location = false;
    else if (a == "--find-file") o.findFile = true;
    else if (a == "--dry-run") o.dryRun = true;
    else if (a == "--add-root") { if (++i >= argc) usage("--add-root requires an argument"); o.addRoot = argv[i]; }
    else if (a == "--indirect") {}
    else if (a == "-o" || a == "--out-link") { if (++i >= argc) usage("--out-link requires an argument"); o.outLink = argv[i]; }
    else if (a == "--no-out-link") o.noOutLink = true;
    else if (a == "-") o.readStdin = true;
    else if (a.size() > 1 && a[0] == '-' && !o.fromArgs) usage("unrecognised flag '" + a + "'");
    else o.files.push_back(a);
  }
  if (o.parseOnly && o.files.empty() && !o.fromArgs) o.readStdin = true;
  return runEvalCommand(o, build);
}

int cmdStore(int argc, char **argv, int start) {
  Options o;
  std::string op;
  std::vector<std::string> args;
  bool queryRefs = false, queryReqs = false, queryReferrers = false, queryDeriver = false, queryOutputs = false,
       queryHash = false, querySize = false, includeOutputs = false, printInvalid = false;
  for (int i = start; i < argc; i++) {
    std::string a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    if (a == "--add" || a == "--add-fixed" || a == "--realise" || a == "-r" || a == "--query" || a == "-q" ||
        a == "--dump" || a == "--gc" || a == "--delete" || a == "--verify-path" || a == "--print-env" ||
        a == "--restore" || a == "--read-log" || a == "--dump-db" || a == "--verify")
      op = a == "-r" ? "--realise" : a == "-q" ? "--query" : a;
    else if (a == "--references") queryRefs = true;
    else if (a == "--requisites" || a == "-R") queryReqs = true;
    else if (a == "--referrers") queryReferrers = true;
    else if (a == "--deriver" || a == "-d") queryDeriver = true;
    else if (a == "--outputs") queryOutputs = true;
    else if (a == "--hash") queryHash = true;
    else if (a == "--size") querySize = true;
    else if (a == "--include-outputs") includeOutputs = true;
    else if (a == "--print-dead" || a == "--print-live") printInvalid = true;
    else if (a == "--recursive") {}
    else args.push_back(a);
  }
  finishOptions(o);
  nixstore::Store store(o.store);
  auto toStore = [&](const std::string &p) {
    std::string ap = p;
    if (!nixstore::isInStore(store.storeDir(), ap)) {
      ap = absPath(p);
      // Follow result symlinks into the (possibly chroot) store.
      char buf[PATH_MAX];
      ssize_t n = readlink(ap.c_str(), buf, sizeof buf - 1);
      if (n > 0) {
        ap = std::string(buf, n);
        if (!o.store.realRoot.empty() && ap.rfind(o.store.realRoot, 0) == 0) ap = ap.substr(o.store.realRoot.size());
      }
    }
    return nixstore::toStorePath(store.storeDir(), ap);
  };
  try {
    if (op == "--add") {
      for (auto &a : args) std::cout << store.addToStore(nixstore::baseNameOf(absPath(a)), absPath(a)) << "\n";
    } else if (op == "--add-fixed") {
      if (args.empty()) usage("--add-fixed requires an algorithm");
      auto algo = nixstore::parseHashAlgo(args[0]);
      if (!algo) usage("unknown hash algorithm '" + args[0] + "'");
      for (size_t i = 1; i < args.size(); i++)
        std::cout << store.addToStore(nixstore::baseNameOf(absPath(args[i])), absPath(args[i]),
                                      nixstore::FileIngestionMethod::Flat, *algo)
                  << "\n";
    } else if (op == "--realise") {
      for (auto &a : args) {
        std::string p = toStore(a);
        if (p.size() > 4 && p.substr(p.size() - 4) == ".drv") {
          for (auto &[n, out] : store.buildDerivation(p)) std::cout << out << "\n";
        } else {
          store.ensurePath(p);
          std::cout << p << "\n";
        }
      }
    } else if (op == "--query") {
      std::set<std::string> out;
      std::vector<std::string> ordered;
      for (auto &a : args) {
        std::string p = toStore(a);
        if (queryRefs) {
          auto info = store.queryPathInfo(p);
          if (!info) throw nixstore::Error("path '" + p + "' is not valid");
          for (auto &r : info->references) out.insert(r);
        } else if (queryReqs) {
          auto c = store.computeFSClosure({p}, includeOutputs);
          out.insert(c.begin(), c.end());
        } else if (queryReferrers) {
          auto r = store.queryReferrers(p);
          out.insert(r.begin(), r.end());
        } else if (queryDeriver) {
          auto info = store.queryPathInfo(p);
          ordered.push_back(info && !info->deriver.empty() ? info->deriver : "unknown-deriver");
        } else if (queryOutputs) {
          auto d = store.readDerivation(p);
          for (auto &[n, o2] : d.outputs) ordered.push_back(o2.path);
        } else if (queryHash || querySize) {
          auto info = store.queryPathInfo(p);
          if (!info) throw nixstore::Error("path '" + p + "' is not valid");
          ordered.push_back(queryHash ? info->narHash.to_string(nixstore::HashFormat::Nix32, true)
                                      : std::to_string(info->narSize));
        } else {
          ordered.push_back(p);
        }
      }
      for (auto &p : out) std::cout << p << "\n";
      for (auto &p : ordered) std::cout << p << "\n";
    } else if (op == "--dump") {
      for (auto &a : args)
        nixstore::dumpPath(absPath(a), [](std::string_view d) { std::cout.write(d.data(), d.size()); });
    } else if (op == "--restore") {
      if (args.size() != 1) usage("--restore requires a path");
      nixstore::restorePath(absPath(args[0]), readStdin());
    } else if (op == "--gc") {
      std::vector<std::string> deleted;
      store.collectGarbage(printInvalid, deleted);
      for (auto &d : deleted) std::cout << (printInvalid ? "" : "deleting '") << d << (printInvalid ? "" : "'") << "\n";
      std::cerr << deleted.size() << " store paths deleted\n";
    } else if (op == "--delete") {
      for (auto &a : args) {
        std::string p = toStore(a);
        if (!store.deletePath(p)) throw nixstore::Error("cannot delete path '" + p + "' since it is still alive");
      }
    } else if (op == "--verify-path" || op == "--verify") {
      int bad = 0;
      std::vector<std::string> paths = args.empty() ? store.allValidPaths() : std::vector<std::string>{};
      for (auto &a : args) paths.push_back(toStore(a));
      for (auto &p : paths) {
        auto info = store.queryPathInfo(p);
        if (!info) { std::cerr << "path '" << p << "' is not valid\n"; bad++; continue; }
        auto [h, n] = nixstore::hashPath(store.toReal(p));
        if (!(h == info->narHash)) {
          std::cerr << "path '" << p << "' was modified! expected hash '"
                    << info->narHash.to_string(nixstore::HashFormat::Nix32, true) << "', got '"
                    << h.to_string(nixstore::HashFormat::Nix32, true) << "'\n";
          bad++;
        }
      }
      return bad ? 1 : 0;
    } else if (op == "--print-env") {
      for (auto &a : args) {
        auto d = store.readDerivation(toStore(a));
        for (auto &[k, v] : d.env) std::cout << "export " << k << "; " << k << "='" << v << "'\n";
        std::cout << "export _args; _args='";
        for (auto &x : d.args) std::cout << x << " ";
        std::cout << "'\n";
      }
    } else {
      usage("no operation specified");
    }
  } catch (nixstore::Error &e) {
    std::cerr << "error: " << e.what() << "\n";
    return 1;
  }
  return 0;
}

int cmdHash(int argc, char **argv, int start) {
  std::string mode;
  nixstore::HashAlgo algo = nixstore::HashAlgo::SHA256;
  nixstore::HashFormat fmt = nixstore::HashFormat::Base16;
  bool flat = false, sri = false;
  std::vector<std::string> args;
  bool algoGiven = false;
  for (int i = start; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--type") {
      if (++i >= argc) usage("--type requires an argument");
      auto t = nixstore::parseHashAlgo(argv[i]);
      if (!t) usage(std::string("unknown hash algorithm '") + argv[i] + "'");
      algo = *t;
      algoGiven = true;
    } else if (a == "--flat") flat = true;
    else if (a == "--base32" || a == "--nix32") fmt = nixstore::HashFormat::Nix32;
    else if (a == "--base16") fmt = nixstore::HashFormat::Base16;
    else if (a == "--base64") fmt = nixstore::HashFormat::Base64;
    else if (a == "--sri") sri = true;
    else if (a == "--truncate") {}
    else if (a == "--to-base32" || a == "--to-nix32" || a == "--to-base16" || a == "--to-base64" || a == "--to-sri")
      mode = a;
    else if (a == "path" || a == "file") mode = a;
    else args.push_back(a);
  }
  try {
    for (auto &a : args) {
      if (mode.rfind("--to-", 0) == 0) {
        if (!algoGiven && a.find(':') == std::string::npos && a.find('-') == std::string::npos)
          throw nixstore::Error("hash '" + a + "' does not include a type, nor is the type otherwise known from context");
        auto h = nixstore::parseHash(a, algo);
        nixstore::HashFormat f = mode == "--to-base16" ? nixstore::HashFormat::Base16
                                 : mode == "--to-base64" ? nixstore::HashFormat::Base64
                                 : mode == "--to-sri" ? nixstore::HashFormat::SRI : nixstore::HashFormat::Nix32;
        std::cout << h.to_string(f, f == nixstore::HashFormat::SRI) << "\n";
        continue;
      }
      nixstore::Hash h = (flat || mode == "file") ? nixstore::hashFile(algo, absPath(a))
                                                  : nixstore::hashPath(absPath(a), nullptr, algo).first;
      if (sri) std::cout << h.to_string(nixstore::HashFormat::SRI, true) << "\n";
      else std::cout << h.to_string(fmt, false) << "\n";
    }
  } catch (nixstore::Error &e) {
    std::cerr << "error: " << e.what() << "\n";
    return 1;
  }
  return 0;
}

int cmdDerivationShow(int argc, char **argv, int start) {
  Options o;
  std::vector<std::string> args;
  for (int i = start; i < argc; i++) {
    std::string a = argv[i];
    if (parseCommon(o, a, i, argc, argv)) continue;
    args.push_back(a);
  }
  finishOptions(o);
  nixstore::Store store(o.store);
  std::cout << "{";
  bool first = true;
  for (auto &a : args) {
    std::string p = nixstore::isInStore(store.storeDir(), a) ? a : absPath(a);
    auto d = store.readDerivation(p);
    std::string j = nixstore::derivationToJSON(store.storeDir(), p, d);
    std::cout << (first ? "" : ",") << j.substr(1, j.size() - 2);
    first = false;
  }
  std::cout << "}\n";
  return 0;
}

void printHelp() {
  std::cout << R"(mlnix - a Nix implementation built on an MLIR dialect

Usage:
  mlnix instantiate [options] [FILE | -E EXPR]...   (like nix-instantiate)
  mlnix build       [options] [FILE | -E EXPR]...   (like nix-build)
  mlnix eval        [options] [FILE | -E EXPR]      (= instantiate --eval --strict)
  mlnix parse       [FILE | -E EXPR]                (= instantiate --parse)
  mlnix emit-mlir   [--no-opt] [FILE | -E EXPR]     print the nix dialect IR
  mlnix run-mlir    FILE.mlir [-A ATTR]             evaluate nix dialect IR
  mlnix store       --add|--add-fixed|--realise|--query|--dump|--restore|--gc|--delete|--verify ...
  mlnix hash        path|file|--to-base32|--to-base16|--to-sri [--type ALGO] [--sri|--base32] ...
  mlnix derivation  show DRV...

Common options:
  -A ATTR  --arg NAME EXPR  --argstr NAME STR  -I PATH  --show-trace
  --store-dir DIR   logical store directory (default /nix/store, or $NIX_STORE_DIR)
  --store ROOT      physical root of a chroot store (local?root=ROOT), or dummy://
  --readonly-mode   compute store paths without writing
  --extra-experimental-features pipe-operators|parse-toml-timestamps

When invoked as nix-instantiate, nix-build, nix-store or nix-hash, mlnix
behaves like the corresponding Nix command.
)";
}

int realMain(int argc, char **argv) {
  std::string prog = nixstore::baseNameOf(argv[0]);
  if (prog == "nix-instantiate") return cmdInstantiate(argc, argv, 1, false);
  if (prog == "nix-build") return cmdInstantiate(argc, argv, 1, true);
  if (prog == "nix-store") return cmdStore(argc, argv, 1);
  if (prog == "nix-hash") return cmdHash(argc, argv, 1);
  if (argc < 2) {
    printHelp();
    return 1;
  }
  std::string cmd = argv[1];
  if (cmd == "--help" || cmd == "-h" || cmd == "help") {
    printHelp();
    return 0;
  }
  if (cmd == "--version") {
    std::cout << "mlnix (Nix-compatible) 2.35.4\n";
    return 0;
  }
  if (cmd == "instantiate") return cmdInstantiate(argc, argv, 2, false);
  if (cmd == "build") return cmdInstantiate(argc, argv, 2, true);
  if (cmd == "eval" || cmd == "parse" || cmd == "emit-mlir" || cmd == "run-mlir") {
    std::vector<char *> args(argv, argv + argc);
    std::vector<std::string> extra;
    if (cmd == "eval") extra = {"--eval", "--strict"};
    if (cmd == "parse") extra = {"--parse"};
    if (cmd == "emit-mlir") extra = {"--emit-mlir"};
    if (cmd == "run-mlir") extra = {"--eval", "--strict"};
    std::vector<char *> nargs;
    nargs.push_back(argv[0]);
    for (auto &e : extra) nargs.push_back(const_cast<char *>(e.c_str()));
    for (int i = 2; i < argc; i++) nargs.push_back(argv[i]);
    return cmdInstantiate(nargs.size(), nargs.data(), 1, false);
  }
  if (cmd == "store") return cmdStore(argc, argv, 2);
  if (cmd == "hash") return cmdHash(argc, argv, 2);
  if (cmd == "derivation") {
    if (argc < 3 || std::string(argv[2]) != "show") usage("expected 'mlnix derivation show DRV...'");
    return cmdDerivationShow(argc, argv, 3);
  }
  usage("unknown command '" + cmd + "'");
}

} // namespace

int main(int argc, char **argv) {
  std::ios::sync_with_stdio(true);
  int rc = 1;
  try {
    rc = runWithLargeStack([&]() -> int {
      try {
        return realMain(argc, argv);
      } catch (nixfe::ParseError &e) {
        std::cout.flush();
        std::cerr << formatParseError(e) << std::endl;
        return 1;
      } catch (EvalError &e) {
        std::cout.flush();
        std::cerr << formatError(nullptr, e) << std::endl;
        return 1;
      } catch (nixstore::Error &e) {
        std::cout.flush();
        std::cerr << "error: " << e.what() << std::endl;
        return 1;
      }
    });
  } catch (std::exception &e) {
    std::cerr << "error: " << e.what() << std::endl;
    return 1;
  }
  return rc;
}
