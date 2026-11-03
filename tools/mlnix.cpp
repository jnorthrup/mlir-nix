//===- mlnix.cpp - Nix-compatible command line driver ---------------------===//
//
//   mlnix instantiate|build|eval|parse|emit-mlir|run-mlir|store|hash|derivation
//
// When invoked through a symlink named nix-instantiate, nix-build, nix-store
// or nix-hash, behaves like that command.
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

#include <cstring>
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

composite::MutableSeries<SearchPathElem> parseNixPath(std::string_view s) {
  composite::MutableSeries<SearchPathElem> res;
  size_t i = 0;
  while (i < s.size()) {
    size_t j = i;
    composite::Text elem;
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
      if (eq != composite::npos) { e.prefix = composite::Text(elem.substr(0, eq)); e.path = composite::Text(elem.substr(eq + 1)); }
      else e.path = composite::mv(elem);
      res.append(composite::mv(e));
    }
    i = j + 1;
  }
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
  if (arg == "-I" || arg == "--include") {
    std::string_view v = next();
    o.includes.append(composite::Text(v));
  } else if (arg.rfind("-I", 0) == 0 && arg.size() > 2) {
    o.includes.append(composite::Text(arg.substr(2)));
  } else if (arg == "--arg") {
    composite::Text n(next()), v(next());
    o.argExprs.append({composite::mv(n), composite::mv(v)});
  } else if (arg == "--argstr") {
    composite::Text n(next()), v(next());
    o.argStrs.append({composite::mv(n), composite::mv(v)});
  } else if (arg == "-A" || arg == "--attr") {
    o.attrPaths.append(composite::Text(next()));
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
    std::string_view f = next();
    composite::eachWord(f.data(), uint32_t(f.size()), [&](const char *p, uint32_t n) {
      std::string_view w(p, n);
      if (w == "pipe-operators") o.eval.pipeOperators = true;
      if (w == "parse-toml-timestamps") nixev::tomlTimestamps = true;
    });
  } else if (arg == "--option") {
    std::string_view n = next(), v = next();
    if (n == "max-call-depth") o.eval.maxCallDepth = toUnsigned(v);
    else if ((n == "extra-experimental-features" || n == "experimental-features") && v.find("pipe-operators") != std::string_view::npos)
      o.eval.pipeOperators = true;
    else if (n == "system") o.eval.currentSystem = composite::Text(v);
    else if (n == "pure-eval") o.eval.pureEval = v == "true";
  } else if (arg == "--lint-absolute-path-literals" || arg == "--lint-short-path-literals" || arg == "--lint-url-literals") {
    std::string_view v = next();
    nixfe::Lint l = v == "warn" ? nixfe::Lint::Warn : v == "fatal" ? nixfe::Lint::Fatal : nixfe::Lint::Ignore;
    if (v != "warn" && v != "fatal" && v != "ignore")
      usage(composite::cat("option '", arg.substr(2), "' has invalid value '", v, "' (expected 'ignore', 'warn', or 'fatal')"));
    if (arg == "--lint-absolute-path-literals") o.eval.lintAbsolutePaths = l;
    else if (arg == "--lint-short-path-literals") o.eval.lintShortPaths = l;
    else o.eval.lintUrls = l;
  } else if (arg == "--system") {
    o.eval.currentSystem = composite::Text(next());
  } else if (arg == "--store-dir") {
    o.store.storeDir = absPath(next());
    o.storeDirSet = true;
  } else if (arg == "--store") {
    std::string_view s = next();
    if (s == "dummy://") o.readOnly = o.store.dummy = true;
    else if (s.rfind("local?root=", 0) == 0) { o.store.realRoot = absPath(s.substr(11)); o.storeRootSet = true; }
    else if (s != "auto" && s != "local" && s != "daemon") { o.store.realRoot = absPath(s); o.storeRootSet = true; }
  } else if (arg == "--readonly-mode") {
    o.readOnly = true;
  } else if (arg == "--read-write-mode") {
    o.readWrite = true;
  } else if (arg == "-K" || arg == "--keep-failed") {
    o.store.keepFailed = true;
  } else if (arg == "-j" || arg == "--max-jobs" || arg == "--cores") {
    std::string_view v = next();
    if (arg == "--cores") o.store.cores = toUnsigned(v);
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
  if (const char *r = getenv("NIX_REMOTE"); r && std::string_view(r) == "dummy://") o.readOnly = o.store.dummy = true;
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
                   std::set<const void *> &done) {
  st.forceValue(v);
  if (!st.isDerivation(v)) return true;
  if (!done.insert(v.attrs).second) return false;
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
                    composite::MutableSeries<DrvInfo> &drvs, std::set<const void *> &done) {
  Value v;
  st.autoCallFunction(autoArgs, vIn, v);
  if (!getDerivation(st, v, prefix, drvs, done)) return;
  if (v.type == VType::Attrs) {
    if (!done.insert(v.attrs).second) return;
    for (const Attr *a : v.attrs->lexicographicOrder(st.symbols)) {
      composite::Text p2 = prefix.empty() ? composite::Text(st.symbols[a->name]) : composite::cat(prefix, '.', st.symbols[a->name]);
      st.beginEpoch();
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
  // evaluation (docs/PERFORMANCE.md).  The one thing the destructor did, printing the statistics, is
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

  composite::MutableSeries<std::function<Value *()>> roots;
  if (o.readStdin) {
    roots.append([&]() { return handleParsed(readStdin(), cwdPath(), "«stdin»", ""); });
  } else if (o.fromArgs) {
    for (auto &f : o.files) roots.append([&, f = std::string_view(f)]() { return handleParsed(composite::Text(f), cwdPath(), "«string»", ""); });
  } else {
    if (o.files.empty()) o.files.append("./default.nix");
    for (auto &f : o.files)
      roots.append([&, f = std::string_view(f)]() -> Value * {
        composite::Text p = lookupFileArg(st, f);
        if (o.findFile) {
          lineToStdout(p);
          return nullptr;
        }
        composite::Text resolved = st.resolveExprPath(st.realisePath(p, nullptr));
        if (resolved.size() > 5 && resolved.substr(resolved.size() - 5) == ".mlir") return st.evalMLIRFile(resolved, "");
        composite::Text text = nixstore::readFile(resolved);
        return handleParsed(composite::mv(text), nixstore::dirOf(resolved), resolved, resolved);
      });
  }

  int rootNr = 0;
  composite::MutableSeries<composite::Text> buildOutputs;
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
        std::set<const void *> done;
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
    else if (a.size() > 1 && a[0] == '-' && !o.fromArgs) usage(composite::cat("unrecognised flag '", a, "'"));
    else o.files.append(composite::Text(a));
  }
  if (o.parseOnly && o.files.empty() && !o.fromArgs) o.readStdin = true;
  return runEvalCommand(o, build);
}

int cmdStore(int argc, char **argv, int start) {
  Options o;
  std::string_view op;
  composite::MutableSeries<composite::Text> args;
  bool queryRefs = false, queryReqs = false, queryReferrers = false, queryDeriver = false, queryOutputs = false,
       queryHash = false, querySize = false, includeOutputs = false, printInvalid = false;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
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
    else args.append(composite::Text(a));
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
    if (op == "--add") {
      for (auto &a : args) lineToStdout(store.addToStore(nixstore::baseNameOf(absPath(a)), absPath(a)));
    } else if (op == "--add-fixed") {
      if (args.empty()) usage("--add-fixed requires an algorithm");
      auto algo = nixstore::parseHashAlgo(args[0]);
      if (!algo) usage(composite::cat("unknown hash algorithm '", args[0], "'"));
      for (size_t i = 1; i < args.size(); i++)
        lineToStdout(store.addToStore(nixstore::baseNameOf(absPath(args[i])), absPath(args[i]), nixstore::FileIngestionMethod::Flat, *algo));
    } else if (op == "--realise") {
      for (auto &a : args) {
        composite::Text p = toStore(a);
        if (p.size() > 4 && p.substr(p.size() - 4) == ".drv") {
          for (auto &[n, out] : store.buildDerivation(p)) lineToStdout(out);
        } else {
          store.ensurePath(p);
          lineToStdout(p);
        }
      }
    } else if (op == "--query") {
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
      for (auto &p : out) lineToStdout(p);
      for (auto &p : ordered) lineToStdout(p);
    } else if (op == "--dump") {
      for (auto &a : args)
        nixstore::dumpPath(absPath(a), [](std::string_view d) { nixsys::toStdout(d.data(), d.size()); });
    } else if (op == "--restore") {
      if (args.size() != 1) usage("--restore requires a path");
      nixstore::restorePath(absPath(args[0]), readStdin());
    } else if (op == "--gc") {
      composite::MutableSeries<composite::Text> deleted;
      store.collectGarbage(printInvalid, deleted);
      for (auto &d : deleted) {
        if (printInvalid) lineToStdout(d);
        else lineToStdout(composite::cat("deleting '", d, "'"));
      }
      composite::Text count;
      count.putUnsigned(deleted.size()).put(" store paths deleted");
      nixsys::lineToStderr(count.data(), count.size());
    } else if (op == "--delete") {
      for (auto &a : args) {
        composite::Text p = toStore(a);
        if (!store.deletePath(p)) throw nixstore::Error(composite::cat("cannot delete path '", p, "' since it is still alive"));
      }
    } else if (op == "--verify-path" || op == "--verify") {
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
    } else if (op == "--print-env") {
      for (auto &a : args) {
        const auto &d = store.readDerivation(toStore(a));
        for (auto &[k, v] : d.env) lineToStdout(composite::cat("export ", k, "; ", k, "='", v, "'"));
        composite::Text args("export _args; _args='");
        for (auto &x : d.args) args.put(x).put(' ');
        lineToStdout(args + "'");
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
  std::string_view mode;
  nixstore::HashAlgo algo = nixstore::HashAlgo::SHA256;
  nixstore::HashFormat fmt = nixstore::HashFormat::Base16;
  bool flat = false, sri = false;
  composite::MutableSeries<composite::Text> args;
  bool algoGiven = false;
  for (int i = start; i < argc; i++) {
    std::string_view a = argv[i];
    if (a == "--type") {
      if (++i >= argc) usage("--type requires an argument");
      auto t = nixstore::parseHashAlgo(argv[i]);
      if (!t) usage(composite::cat("unknown hash algorithm '", argv[i], "'"));
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
    else args.append(composite::Text(a));
  }
  try {
    for (auto &a : args) {
      if (mode.rfind("--to-", 0) == 0) {
        if (!algoGiven && a.find(':') == composite::npos && a.find('-') == composite::npos)
          throw nixstore::Error(composite::cat("hash '", a, "' does not include a type, nor is the type otherwise known from context"));
        auto h = nixstore::parseHash(a, algo);
        nixstore::HashFormat f = mode == "--to-base16" ? nixstore::HashFormat::Base16
                                 : mode == "--to-base64" ? nixstore::HashFormat::Base64
                                 : mode == "--to-sri" ? nixstore::HashFormat::SRI : nixstore::HashFormat::Nix32;
        lineToStdout(h.to_string(f, f == nixstore::HashFormat::SRI));
        continue;
      }
      nixstore::Hash h = (flat || mode == "file") ? nixstore::hashFile(algo, absPath(a))
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

void printHelp() {
  static const char help[] = R"(mlnix - a Nix implementation built on an MLIR dialect

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
  nixsys::toStdout(help, sizeof help - 1);
}

int realMain(int argc, char **argv) {
  composite::Text prog = nixstore::baseNameOf(argv[0]);
  if (prog == "nix-instantiate") return cmdInstantiate(argc, argv, 1, false);
  if (prog == "nix-build") return cmdInstantiate(argc, argv, 1, true);
  if (prog == "nix-store") return cmdStore(argc, argv, 1);
  if (prog == "nix-hash") return cmdHash(argc, argv, 1);
  if (argc < 2) {
    printHelp();
    return 1;
  }
  std::string_view cmd = argv[1];
  if (cmd == "--help" || cmd == "-h" || cmd == "help") {
    printHelp();
    return 0;
  }
  if (cmd == "--version") {
    static const char version[] = "mlnix (Nix-compatible) 2.35.4\n";
    nixsys::toStdout(version, sizeof version - 1);
    return 0;
  }
  if (cmd == "instantiate") return cmdInstantiate(argc, argv, 2, false);
  if (cmd == "build") return cmdInstantiate(argc, argv, 2, true);
  if (cmd == "eval" || cmd == "parse" || cmd == "emit-mlir" || cmd == "run-mlir") {
    composite::MutableSeries<char *> args;
    for (int ai = 0; ai < argc; ai++) args.append(argv[ai]);
    composite::MutableSeries<composite::Text> extra;
    if (cmd == "eval") extra = {"--eval", "--strict"};
    if (cmd == "parse") extra = {"--parse"};
    if (cmd == "emit-mlir") extra = {"--emit-mlir"};
    if (cmd == "run-mlir") extra = {"--eval", "--strict"};
    composite::MutableSeries<char *> nargs;
    nargs.append(argv[0]);
    for (auto &e : extra) nargs.append(const_cast<char *>(e.c_str()));
    for (int i = 2; i < argc; i++) nargs.append(argv[i]);
    return cmdInstantiate(nargs.size(), nargs.data(), 1, false);
  }
  if (cmd == "primops") {
    // Dump the live primop registry ("<base-env key> <arity>"); the continent
    // dialects (include/NixDialect/NixPrims.td) must stay in sync with it.
    Options o;
    o.readOnly = true;
    finishOptions(o);
    o.store.readOnly = true;
    nixstore::Store store(o.store);
    EvalState st(std::move(o.eval), &store);
    using Entry = composite::TextTable<Value *>::Row;
    composite::MutableSeries<const Entry *> v; // the entries where they lie, ordered by name
    for (auto &e : st.baseEnv)
      if (e.v->type == VType::PrimOp) v.append(&e);
    composite::sortRows(v.data(), v.size(), [](const Entry *a, const Entry *b) {
      return composite::lessChars(composite::series(a->p, a->n), composite::series(b->p, b->n));
    });
    composite::Text rows;
    for (const Entry *e : v) rows.put(e->p, e->n).put(' ').putInt(e->v->primOp->arity).put('\n');
    nixsys::toStdout(rows.data(), rows.size());
    return 0;
  }
  if (cmd == "store") return cmdStore(argc, argv, 2);
  if (cmd == "hash") return cmdHash(argc, argv, 2);
  if (cmd == "derivation") {
    if (argc < 3 || std::string_view(argv[2]) != "show") usage("expected 'mlnix derivation show DRV...'");
    return cmdDerivationShow(argc, argv, 3);
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
