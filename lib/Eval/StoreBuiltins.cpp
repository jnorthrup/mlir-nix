//===- StoreBuiltins.cpp - Builtins that touch the store / file system ----===//

#include "Composite/Mutable.h"
#include "Nix/Prefetch.h"
#include "Nix/Eval.h"

#include <algorithm>
#include <cstring>
#include <dirent.h>
#include <iostream>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

namespace nixev {

using A = Value **;
static std::string str(std::string_view s) { return std::string(s); }

static bool isDrvPath(const std::string &p) { return p.size() > 4 && p.substr(p.size() - 4) == ".drv"; }

static void addOutputsToResult(EvalState &st, EvalState::BindingsBuilder &bb, const std::string &drvPath,
                               const nixstore::Derivation &drv) {
  for (auto &[name, o] : drv.outputs) {
    std::string p = o.kind == nixstore::DerivationOutput::CAFixed && o.path.empty()
                        ? o.fixedPath(st.store->storeDir(), drv.name, name) : o.path;
    st.mkString(bb.alloc(name), p, NixStringContext{st.copyString("!" + name + "!" + drvPath)});
  }
}

static void derivationStrict(EvalState &st, A args, Value &v, PosPtr pos) {
  st.forceAttrs(*args[0], pos, "while evaluating the argument passed to builtins.derivationStrict");
  Bindings *attrs = args[0]->attrs;
  const Attr *nameAttr = attrs->get(st.s.name);
  if (!nameAttr)
    throw EvalError("attribute 'name' missing", pos)
        .addTrace(pos, "in the attrset passed as argument to builtins.derivationStrict");
  std::string drvName;
  try {
    drvName = str(st.forceStringNoCtx(*nameAttr->value, pos, "while evaluating the `name` attribute passed to builtins.derivationStrict"));
  } catch (EvalError &e) {
    e.addTrace(st.positionOf(*nameAttr), "while evaluating the derivation attribute 'name'");
    throw;
  }
  try {
    try {
      nixstore::checkName(drvName);
    } catch (nixstore::Error &e) {
      throw EvalError("invalid derivation name: " + std::string(e.what()) + ". Please pass a different 'name'.", pos);
    }

    bool structured = false;
    if (const Attr *a = attrs->get(st.s.structuredAttrs))
      structured = st.forceBool(*a->value, pos, "while evaluating the `__structuredAttrs` attribute passed to builtins.derivationStrict");
    bool ignoreNulls = false;
    if (const Attr *a = attrs->get(st.s.ignoreNulls))
      ignoreNulls = st.forceBool(*a->value, pos, "while evaluating the `__ignoreNulls` attribute passed to builtins.derivationStrict");

    nixstore::Derivation drv;
    drv.name = drvName;
    nixstore::DrvInputs moduloInputs; // the input derivations as the output paths' hash saw them, for the derivation's modulo hash
    NixStringContext context;                         // what coercions make: paths copied to the store, and the rarer attributes
    composite::MutableSeries<const StringContext *> owns; // each string attribute's own context, interned: its elements are not copied
    std::string coerced;
    bool contentAddressed = false, isImpure = false;
    std::optional<std::string> outputHash;
    std::optional<nixstore::HashAlgo> outputHashAlgo;
    std::optional<nixstore::FileIngestionMethod> ingestionMethod;
    nixstore::SortedSet outputs; // the output names: rows kept sorted, in the order the derivation lists them
    outputs.insert("out");
    std::string jsonObj = "{";
    bool jsonFirst = true;

    auto handleHashMode = [&](std::string_view s) {
      if (s == "recursive" || s == "nar") ingestionMethod = nixstore::FileIngestionMethod::NixArchive;
      else if (s == "flat") ingestionMethod = nixstore::FileIngestionMethod::Flat;
      else if (s == "text")
        throw EvalError("experimental Nix feature 'dynamic-derivations' is disabled; add '--extra-experimental-features dynamic-derivations' to enable it", pos);
      else if (s == "git")
        throw EvalError("experimental Nix feature 'git-hashing' is disabled; add '--extra-experimental-features git-hashing' to enable it", pos);
      else throw EvalError("invalid value '" + str(s) + "' for 'outputHashMode' attribute", pos);
    };
    auto handleOutputs = [&](const auto &ss) {
      outputs = nixstore::SortedSet();
      for (auto &j : ss) {
        if (outputs.count(j)) throw EvalError("duplicate derivation output '" + j + "'", pos);
        if (j == "drvPath") throw EvalError("invalid derivation output name 'drvPath'", pos);
        outputs.insert(j);
      }
      if (outputs.empty()) throw EvalError("derivation cannot have an empty set of outputs", pos);
    };
    auto parseAlgo = [&](std::string_view s) -> std::optional<nixstore::HashAlgo> {
      if (s.empty()) return std::nullopt;
      auto a = nixstore::parseHashAlgo(s);
      if (!a) throw EvalError("unknown hash algorithm '" + str(s) + "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'", pos);
      return a;
    };

    for (const Attr *i : attrs->lexicographicOrder(st.symbols)) {
      if (i->name == st.s.ignoreNulls) continue;
      std::string key = str(st.symbols[i->name]);
      try {
        if (ignoreNulls) {
          st.forceValue(*i->value, pos);
          if (i->value->type == VType::Null) continue;
        }
        if (i->name == st.s.contentAddressed) {
          if (st.forceBool(*i->value, pos, "")) {
            contentAddressed = true;
            throw EvalError("experimental Nix feature 'ca-derivations' is disabled; add '--extra-experimental-features ca-derivations' to enable it", pos);
          }
        } else if (i->name == st.s.impure) {
          if (st.forceBool(*i->value, pos, "")) {
            isImpure = true;
            throw EvalError("experimental Nix feature 'impure-derivations' is disabled; add '--extra-experimental-features impure-derivations' to enable it", pos);
          }
        } else if (i->name == st.s.args) {
          st.forceList(*i->value, pos, "");
          for (size_t k = 0; k < i->value->listSize(); k++)
            drv.args.append(st.coerceToString(*i->value->list.elems[k], context, true, true, pos,
                                                 "while evaluating an element of the argument list"));
        } else if (structured) {
          if (i->name == st.s.structuredAttrs) continue;
          JsonOut js;
          js.put(jsonFirst ? "" : ",");
          js.putString(key);
          js.put(':');
          st.printValueAsJSON(js, *i->value, true, context, true, pos);
          jsonObj += js.view();
          jsonFirst = false;
          if (i->name == st.s.builder) drv.builder = str(st.forceString(*i->value, context, pos));
          else if (i->name == st.s.system) drv.platform = str(st.forceStringNoCtx(*i->value, pos));
          else if (i->name == st.s.outputHash) outputHash = str(st.forceStringNoCtx(*i->value, pos));
          else if (i->name == st.s.outputHashAlgo) outputHashAlgo = parseAlgo(st.forceStringNoCtx(*i->value, pos));
          else if (i->name == st.s.outputHashMode) handleHashMode(st.forceStringNoCtx(*i->value, pos));
          else if (i->name == st.s.outputs) {
            st.forceList(*i->value, pos, "");
            auto strs = i->value->values() |cp::α| [&](Value &e) { return str(st.forceStringNoCtx(e, pos)); };
            composite::MutableSeries<std::string> ss;
            for (uint32_t k = 0, n = strs.size(); k < n; k++) ss.append(strs[k]);
            handleOutputs(ss);
          }
          static const char *legacy[] = {"allowedReferences", "allowedRequisites", "disallowedReferences",
                                         "disallowedRequisites", "maxSize", "maxClosureSize"};
          for (auto *l : legacy)
            if (key == l)
              st.warn("In a derivation named '" + drvName + "', 'structuredAttrs' disables the effect of the derivation attribute '" +
                      key + "'; use 'outputChecks.<output>." + key + "' instead");
        } else {
          const StringContext *own = nullptr;
          std::string s(composite::view(st.coerceToWindow(*i->value, context, true, true, pos, "", coerced, true, &own)));
          if (own) owns.append(own);
          if (i->name == st.s.json) {
            st.warn("In derivation '" + drvName + "': setting structured attributes via '__json' is deprecated, and may be disallowed in future versions of Nix. Set '__structuredAttrs = true' instead.");
            drv.structuredAttrs = s;
          } else {
            if (i->name == st.s.builder) drv.builder = s;
            else if (i->name == st.s.system) drv.platform = s;
            else if (i->name == st.s.outputHash) outputHash = s;
            else if (i->name == st.s.outputHashAlgo) outputHashAlgo = parseAlgo(s);
            else if (i->name == st.s.outputHashMode) handleHashMode(s);
            else if (i->name == st.s.outputs) {
              composite::MutableSeries<std::string> ss;
              // The names are the words of the string, split at whitespace as a stream's >> splits them.
              auto space = [](char c) { return c == ' ' || (c >= '\t' && c <= '\r'); };
              for (size_t k = 0, n = s.size(); k < n;) {
                while (k < n && space(s[k])) k++;
                size_t b = k;
                while (k < n && !space(s[k])) k++;
                if (k > b) ss.append(s.substr(b, k - b));
              }
              handleOutputs(ss);
            }
            // Last, once nothing above can throw: the attributes come in name order, the map's own, so the key and the value move in at the
            // end with no search and no copy (a build script was copied twice here).
            drv.env.emplace_hint(drv.env.end(), std::move(key), std::move(s));
          }
        }
      } catch (EvalError &e) {
        e.addTrace(st.positionOf(*i), "while evaluating attribute '" + key + "' of derivation '" + drvName + "'");
        throw;
      }
    }
    if (structured) drv.structuredAttrs = jsonObj + "}";

    // The derivation's context: the string attributes' own (arena C strings, read where they lie) and what coercions made, sorted and made
    // unique once, in the order the set gave them.
    composite::MutableSeries<std::string_view> elems;
    for (const StringContext *c : owns)
      for (size_t k = 0; k < c->n; k++) elems.append(c->elems[k]);
    for (auto &c : context) elems.append(c);
    cp::sortRows(elems.data(), elems.size(), [](std::string_view a, std::string_view b) { return a < b; });
    size_t nElems = cp::uniqueFirst(elems.data(), elems.size(), [](std::string_view e) { return e; });
    for (size_t ei = 0; ei < nElems; ei++) {
      std::string_view c = elems[uint32_t(ei)];
      if (c[0] == '=') {
        std::string d(c.substr(1));
        auto refs = st.store->computeFSClosure({d});
        for (auto &j : refs) {
          drv.inputSrcs.insert(j);
          if (isDrvPath(j)) {
            const auto &dd = st.store->readDerivation(j);
            for (auto &[n, o] : dd.outputs) drv.inputDrvs[j].insert(n);
          }
        }
      } else if (c[0] == '!') {
        auto p = c.find('!', 1);
        drv.inputDrvs[c.substr(p + 1)].insert(c.substr(1, p - 1));
      } else {
        drv.inputSrcs.insert(c);
      }
    }

    if (drv.builder.empty()) throw EvalError("required attribute 'builder' missing", pos);
    if (drv.platform.empty()) throw EvalError("required attribute 'system' missing", pos);
    if (isDrvPath(drvName))
      throw EvalError("derivation names are allowed to end in '.drv' only if they produce a single derivation file", pos);

    if (outputHash) {
      if (outputs.size() != 1 || *outputs.begin() != "out")
        throw EvalError("multiple outputs are not supported in fixed-output derivations", pos);
      std::string warning;
      nixstore::Hash h;
      try {
        h = nixstore::parseHashAllowEmpty(*outputHash, outputHashAlgo, &warning);
      } catch (nixstore::Error &e) {
        throw EvalError(e.what(), pos);
      }
      if (!warning.empty()) st.warn(warning);
      nixstore::DerivationOutput o;
      o.kind = nixstore::DerivationOutput::CAFixed;
      o.method = ingestionMethod.value_or(nixstore::FileIngestionMethod::Flat);
      o.hash = h;
      o.hashAlgo = h.algo;
      try {
        o.path = o.fixedPath(st.store->storeDir(), drvName, "out");
      } catch (nixstore::Error &e) {
        throw EvalError(e.what(), pos);
      }
      drv.env["out"] = o.path;
      drv.outputs["out"] = o;
    } else {
      (void)contentAddressed;
      (void)isImpure;
      for (auto &o : outputs) {
        drv.env[o] = "";
        drv.outputs[o] = nixstore::DerivationOutput{};
      }
    }

    // A derivation made before with this content has its paths already, and neither hash below is made again: 37% of a NixOS
    // evaluation's derivations and 44% of nixpkgs-73's are made again by another call with equal attributes.
    std::string drvPath;
    uint64_t fingerprint;
    if (const std::string *same = st.store->sameDerivation(drv, fingerprint)) {
      drvPath = *same;
    } else {
      try {
        if (!outputHash) st.store->fillInOutputPaths(drv, &moduloInputs);
        drvPath = st.store->writeDerivation(std::move(drv));
        st.store->rememberDerivation(fingerprint, drvPath);
        if (!outputHash) st.store->hashLater(drvPath, std::move(moduloInputs)); // its modulo hash, for its dependents, made off this thread
      } catch (nixstore::Error &e) {
        throw EvalError(e.what(), pos);
      }
    }
    EvalState::BindingsBuilder bb(st);
    st.mkString(bb.alloc(st.s.drvPath), drvPath, NixStringContext{st.copyString("=" + drvPath)});
    addOutputsToResult(st, bb, drvPath, st.store->readDerivation(drvPath)); // the derivation as the store keeps it, not a copy
    st.mkAttrs(v, bb.finish());
  } catch (EvalError &e) {
    e.addTrace(nullptr, "while evaluating derivation '" + drvName + "'\n  whose name attribute is located at " +
                            st.showPos(st.positionOf(*nameAttr)));
    throw;
  }
}

static std::string fileTypeOf(const std::string &path) {
  struct stat st;
  if (lstat(path.c_str(), &st) != 0) return "";
  if (S_ISREG(st.st_mode)) return "regular";
  if (S_ISDIR(st.st_mode)) return "directory";
  if (S_ISLNK(st.st_mode)) return "symlink";
  return "unknown";
}

/// The type of a directory entry: the file system already told `readdir` (d_type), so no stat;
/// DT_UNKNOWN (some file systems) falls back to lstat, as upstream does.
static std::string dirEntryType(const std::string &dir, const dirent &e) {
  switch (e.d_type) {
  case DT_REG: return "regular";
  case DT_DIR: return "directory";
  case DT_LNK: return "symlink";
  case DT_UNKNOWN: return fileTypeOf(dir + "/" + e.d_name);
  default: return "unknown";
  }
}

/// Shared implementation of builtins.path and builtins.filterSource.
static void addPath(EvalState &st, PosPtr pos, std::string name, const std::string &path, Value *filterFun,
                    nixstore::FileIngestionMethod method, std::optional<nixstore::Hash> expected, Value &v,
                    const NixStringContext &ctx) {
  st.realiseContext(ctx, pos);
  std::string real = st.realisePath(path, pos);
  if (!nixstore::pathExists(real)) throw EvalError("path '" + path + "' does not exist", pos);
  nixstore::PathFilter filter;
  if (filterFun) {
    filter = [&](const std::string &p, std::string_view type) {
      // Map physical path back to the logical one.
      std::string logical = path + p.substr(real.size());
      Value *arg1 = st.newString(logical);
      Value *arg2 = st.newString(type.empty() ? fileTypeOf(p) : std::string(type)); // a prehashed tree's walk knows the type
      Value *fargs[2] = {arg1, arg2};
      Value r;
      st.callFunction(*filterFun, 2, fargs, r, pos);
      return st.forceBool(r, pos, "while evaluating the return value of the path filter function");
    };
  }
  try {
    nixstore::checkName(name);
  } catch (nixstore::Error &e) {
    throw EvalError(std::string("invalid store path name: ") + e.what(), pos);
  }
  std::string dst;
  try {
    if (expected && !filterFun) {
      std::string exp = nixstore::makeFixedOutputPath(st.store->storeDir(), name, method, *expected);
      if (st.store->isValidPath(exp)) dst = exp;
    }
    if (dst.empty())
      dst = st.store->addToStore(name, real, method,
                                 expected ? expected->algo : nixstore::HashAlgo::SHA256, filter, {}, expected);
  } catch (nixstore::Error &e) {
    throw EvalError(e.what(), pos);
  }
  st.mkStoreString(v, dst);
}

static std::string downloadToTemp(const std::string &url, PosPtr pos) {
  char tmpl[] = "/tmp/mlnix-dl-XXXXXX";
  int fd = mkstemp(tmpl);
  if (fd < 0) throw EvalError("cannot create temporary file", pos);
  close(fd);
  std::string out;
  int rc;
  if (url.rfind("file://", 0) == 0) {
    rc = nixstore::runProgram("cp", {url.substr(7), tmpl}, &out);
  } else {
    rc = nixstore::runProgram("curl", {"-fsSL", "--retry", "3", "-o", tmpl, url}, &out);
  }
  if (rc != 0) {
    unlink(tmpl);
    throw EvalError("unable to download '" + url + "': HTTP error (curl exit code " + std::to_string(rc) + ")", pos);
  }
  return tmpl;
}

static std::string urlBaseName(const std::string &url) {
  std::string u = url;
  auto q = u.find_first_of("?#");
  if (q != std::string::npos) u = u.substr(0, q);
  auto s = u.rfind('/');
  return s == std::string::npos ? u : u.substr(s + 1);
}

static void fetchImpl(EvalState &st, A args, Value &v, PosPtr pos, bool unpack, const char *who) {
  std::string url, name;
  std::optional<nixstore::Hash> expected;
  st.forceValue(*args[0], pos);
  if (args[0]->type == VType::Attrs) {
    for (auto &a : *args[0]->attrs) {
      auto n = st.symbols[a.name];
      if (n == "url") url = str(st.forceStringNoCtx(*a.value, pos));
      else if (n == "sha256") {
        auto h = st.forceStringNoCtx(*a.value, pos);
        try {
          expected = nixstore::parseHash(h, nixstore::HashAlgo::SHA256);
        } catch (nixstore::Error &e) {
          throw EvalError(e.what(), pos);
        }
      } else if (n == "hash") {
        auto h = st.forceStringNoCtx(*a.value, pos);
        try {
          expected = nixstore::parseHash(h, std::nullopt);
        } catch (nixstore::Error &e) {
          throw EvalError(e.what(), pos);
        }
      } else if (n == "name") name = str(st.forceStringNoCtx(*a.value, pos));
      else throw EvalError("unsupported argument '" + n.str() + "' to '" + who + "'", pos);
    }
    if (url.empty()) throw EvalError("'url' argument required", pos);
  } else {
    url = str(st.forceStringNoCtx(*args[0], pos));
  }
  if (name.empty()) name = unpack ? "source" : urlBaseName(url);
  if (st.settings.pureEval && !expected)
    throw EvalError("in pure evaluation mode, '" + std::string(who) + "' requires a 'sha256' argument", pos);
  auto method = unpack ? nixstore::FileIngestionMethod::NixArchive : nixstore::FileIngestionMethod::Flat;
  if (expected) {
    std::string exp = nixstore::makeFixedOutputPath(st.store->storeDir(), name, method, *expected);
    if (st.store->isValidPath(exp)) {
      st.mkStoreString(v, exp);
      return;
    }
  }
  std::string file = downloadToTemp(url, pos);
  std::string dst;
  try {
    if (unpack) {
      char dtmpl[] = "/tmp/mlnix-unpack-XXXXXX";
      if (!mkdtemp(dtmpl)) throw EvalError("cannot create temporary directory", pos);
      std::string out;
      int rc = nixstore::runProgram("tar", {"xf", file, "-C", dtmpl}, &out);
      unlink(file.c_str());
      if (rc != 0) {
        nixstore::deletePathRecursive(dtmpl);
        throw EvalError("failed to unpack '" + url + "'", pos);
      }
      // Use the single top-level directory if there is one.
      composite::MutableSeries<std::string> entries;
      if (DIR *d = opendir(dtmpl)) {
        while (auto *e = readdir(d)) {
          std::string n = e->d_name;
          if (n != "." && n != "..") entries.append(n);
        }
        closedir(d);
      }
      std::string root = dtmpl;
      if (entries.size() == 1 && fileTypeOf(root + "/" + entries[0]) == "directory") root += "/" + entries[0];
      dst = st.store->addToStore(name, root, method, nixstore::HashAlgo::SHA256, nullptr, {}, expected);
      nixstore::deletePathRecursive(dtmpl);
    } else {
      dst = st.store->addToStore(name, file, method, expected ? expected->algo : nixstore::HashAlgo::SHA256, nullptr, {},
                                 expected);
      unlink(file.c_str());
    }
  } catch (nixstore::Error &e) {
    throw EvalError(e.what(), pos);
  }
  st.mkStoreString(v, dst);
}

static void fetchGit(EvalState &st, A args, Value &v, PosPtr pos) {
  std::string url, ref, rev, name = "source";
  bool submodules = false, shallow = false, allRefs = false;
  st.forceValue(*args[0], pos);
  if (args[0]->type == VType::Attrs) {
    for (auto &a : *args[0]->attrs) {
      auto n = st.symbols[a.name];
      if (n == "url") {
        NixStringContext ctx;
        url = st.coerceToString(*a.value, ctx, false, false, pos);
      } else if (n == "ref") ref = str(st.forceStringNoCtx(*a.value, pos));
      else if (n == "rev") rev = str(st.forceStringNoCtx(*a.value, pos));
      else if (n == "name") name = str(st.forceStringNoCtx(*a.value, pos));
      else if (n == "submodules") submodules = st.forceBool(*a.value, pos);
      else if (n == "shallow") shallow = st.forceBool(*a.value, pos);
      else if (n == "allRefs") allRefs = st.forceBool(*a.value, pos);
      else if (n == "narHash" || n == "lastModified" || n == "revCount" || n == "exportIgnore") {
      } else throw EvalError("unsupported argument '" + n.str() + "' to 'fetchGit'", pos);
    }
  } else {
    NixStringContext ctx;
    url = st.coerceToString(*args[0], ctx, false, false, pos);
  }
  (void)allRefs;
  if (st.settings.pureEval && rev.empty())
    throw EvalError("in pure evaluation mode, 'fetchGit' requires a Git revision", pos);
  char tmpl[] = "/tmp/mlnix-git-XXXXXX";
  if (!mkdtemp(tmpl)) throw EvalError("cannot create temporary directory", pos);
  std::string dir = std::string(tmpl) + "/checkout";
  std::string out;
  composite::MutableSeries<std::string> cloneArgs = {"clone", "--quiet"};
  if (shallow && rev.empty()) cloneArgs.append("--depth=1");
  if (!ref.empty() && rev.empty()) {
    cloneArgs.append("--branch");
    cloneArgs.append(ref.rfind("refs/heads/", 0) == 0 ? ref.substr(11) : ref);
  }
  cloneArgs.append(url);
  cloneArgs.append(dir);
  if (nixstore::runProgram("git", cloneArgs, &out) != 0) {
    nixstore::deletePathRecursive(tmpl);
    throw EvalError("failed to clone '" + url + "'", pos);
  }
  if (!rev.empty() && nixstore::runProgram("git", {"-C", dir, "checkout", "--quiet", rev}, &out) != 0) {
    nixstore::deletePathRecursive(tmpl);
    throw EvalError("cannot find Git revision '" + rev + "' in '" + url + "'", pos);
  }
  if (submodules) nixstore::runProgram("git", {"-C", dir, "submodule", "update", "--init", "--recursive", "--quiet"}, &out);
  std::string headRev;
  nixstore::runProgram("git", {"-C", dir, "rev-parse", "HEAD"}, &headRev);
  while (!headRev.empty() && isspace((unsigned char)headRev.back())) headRev.pop_back();
  std::string countS, timeS;
  nixstore::runProgram("git", {"-C", dir, "rev-list", "--count", "HEAD"}, &countS);
  nixstore::runProgram("git", {"-C", dir, "log", "-1", "--format=%ct", "HEAD"}, &timeS);
  // Export the tree without .git.
  nixstore::deletePathRecursive(dir + "/.git");
  std::string dst;
  try {
    dst = st.store->addToStore(name, dir);
  } catch (nixstore::Error &e) {
    nixstore::deletePathRecursive(tmpl);
    throw EvalError(e.what(), pos);
  }
  auto [narHash, narSize] = nixstore::hashPath(st.store->toReal(dst));
  nixstore::deletePathRecursive(tmpl);
  EvalState::BindingsBuilder bb(st);
  st.mkStoreString(bb.alloc(st.s.outPath), dst);
  st.mkString(bb.alloc(st.s.rev), headRev);
  st.mkString(bb.alloc(st.s.shortRev), headRev.substr(0, 7));
  int64_t lm = atoll(timeS.c_str());
  st.mkInt(bb.alloc(st.s.revCount), atoll(countS.c_str()));
  st.mkInt(bb.alloc(st.s.lastModified), lm);
  char buf[32];
  time_t t = lm;
  struct tm tmv;
  gmtime_r(&t, &tmv);
  strftime(buf, sizeof buf, "%Y%m%d%H%M%S", &tmv);
  st.mkString(bb.alloc(st.s.lastModifiedDate), buf);
  st.mkString(bb.alloc(st.s.narHash), narHash.to_string(nixstore::HashFormat::SRI, true));
  st.mkBool(bb.alloc(st.s.submodules), submodules);
  st.mkAttrs(v, bb.finish());
}

void registerStoreBuiltins(EvalState &state) {
  auto &S = state;
  S.addPrimOp("derivationStrict", 1, derivationStrict);
  S.addPrimOp("placeholder", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto o = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.placeholder");
    st.mkString(v, nixstore::hashPlaceholder(o));
  });
  S.addPrimOp("__toFile", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto name = str(st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.toFile"));
    NixStringContext ctx;
    auto contents = str(st.forceString(*args[1], ctx, pos, "while evaluating the second argument passed to builtins.toFile"));
    std::set<std::string> refs;
    for (auto &c : ctx) {
      if (c[0] == '=' || c[0] == '!')
        throw EvalError("files created by builtins.toFile may not reference derivations, but " + name +
                            " references " + c,
                        pos);
      refs.insert(c);
    }
    std::string p;
    try {
      p = st.store->addTextToStore(name, contents, refs);
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
    st.mkStoreString(v, p);
  });
  S.addPrimOp("__storePath", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    if (st.settings.pureEval) throw EvalError("'builtins.storePath' is not allowed in pure evaluation mode", pos);
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.storePath");
    if (!nixstore::isInStore(st.store->storeDir(), p))
      throw EvalError("path '" + p + "' is not in the Nix store", pos);
    std::string sp = nixstore::toStorePath(st.store->storeDir(), p);
    if (!st.store->isValidPath(sp)) st.store->ensurePath(sp);
    ctx.insert(st.copyString(sp));
    st.mkString(v, p, ctx);
  });
  S.addPrimOp("__toPath", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.toPath");
    st.mkString(v, nixfe::canonPath(p), ctx);
  });
  S.addPrimOp("__pathExists", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceValue(*args[0], pos);
    NixStringContext ctx;
    bool mustBeDir = false;
    if (args[0]->type == VType::String) {
      auto sv = args[0]->sv();
      mustBeDir = (sv.size() >= 1 && sv.back() == '/') || (sv.size() >= 2 && sv.substr(sv.size() - 2) == "/.");
    }
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while realising the context of a path");
    try {
      st.realiseContext(ctx, pos);
    } catch (EvalError &) {
      st.mkBool(v, false);
      return;
    }
    std::string real = st.realisePath(nixfe::canonPath(p), pos);
    struct stat sb;
    nixprefetch::note('S', real.c_str());
    bool ok = mustBeDir ? (stat(real.c_str(), &sb) == 0 && S_ISDIR(sb.st_mode)) : (stat(real.c_str(), &sb) == 0 || nixstore::pathExists(real));
    st.mkBool(v, ok);
  });
  S.addPrimOp("__readFile", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.readFile");
    st.realiseContext(ctx, pos);
    std::string real = st.realisePath(p, pos);
    std::string s;
    try {
      s = nixstore::readFile(real);
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
    if (s.find('\0') != std::string::npos)
      throw EvalError("the contents of the file '" + p + "' cannot be represented as a Nix string", pos);
    NixStringContext refs;
    if (nixstore::isInStore(st.store->storeDir(), p)) {
      std::string sp = nixstore::toStorePath(st.store->storeDir(), p);
      if (auto info = st.store->queryPathInfo(sp))
        for (auto &r : info->references) refs.insert(st.copyString(r));
    }
    st.mkString(v, s, refs);
  });
  S.addPrimOp("__readDir", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.readDir");
    st.realiseContext(ctx, pos);
    std::string real = st.realisePath(p, pos);
    nixprefetch::note('D', real.c_str());
    DIR *d = opendir(real.c_str());
    if (!d) throw EvalError("cannot read directory '" + p + "': " + strerror(errno), pos);
    EvalState::BindingsBuilder bb(st);
    while (auto *e = readdir(d)) {
      std::string n = e->d_name;
      if (n == "." || n == "..") continue;
      Value &t = bb.alloc(n);
      st.mkString(t, dirEntryType(real, *e));
    }
    closedir(d);
    st.mkAttrs(v, bb.finish());
  });
  S.addPrimOp("__readFileType", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[0], ctx, pos, "while evaluating the first argument passed to builtins.readFileType");
    st.realiseContext(ctx, pos);
    std::string t = fileTypeOf(st.realisePath(p, pos));
    if (t.empty()) throw EvalError("getting status of '" + p + "': No such file or directory", pos);
    st.mkString(v, t);
  });
  S.addPrimOp("__hashFile", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto algoS = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.hashFile");
    auto algo = nixstore::parseHashAlgo(algoS);
    if (!algo) throw EvalError("unknown hash algorithm '" + str(algoS) + "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'", pos);
    NixStringContext ctx;
    std::string p = st.coerceToPath(*args[1], ctx, pos, "while evaluating the second argument passed to builtins.hashFile");
    st.realiseContext(ctx, pos);
    try {
      st.mkString(v, nixstore::hashFile(*algo, st.realisePath(p, pos)).to_string(nixstore::HashFormat::Base16, false));
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
  });
  S.addPrimOp("__hashString", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    auto algoS = st.forceStringNoCtx(*args[0], pos, "while evaluating the first argument passed to builtins.hashString");
    auto algo = nixstore::parseHashAlgo(algoS);
    if (!algo) throw EvalError("unknown hash algorithm '" + str(algoS) + "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'", pos);
    NixStringContext ctx;
    auto s = st.forceString(*args[1], ctx, pos, "while evaluating the second argument passed to builtins.hashString");
    st.mkString(v, nixstore::hashString(*algo, s).to_string(nixstore::HashFormat::Base16, false));
  });
  S.addPrimOp("__convertHash", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the first argument passed to builtins.convertHash");
    const Attr *h = args[0]->attrs->get(st.symbols.create("hash"));
    if (!h) throw EvalError("attribute 'hash' missing", pos);
    auto hs = st.forceStringNoCtx(*h->value, pos, "while evaluating the attribute 'hash'");
    std::optional<nixstore::HashAlgo> algo;
    if (const Attr *a = args[0]->attrs->get(st.symbols.create("hashAlgo"))) {
      auto as = st.forceStringNoCtx(*a->value, pos, "while evaluating the attribute 'hashAlgo'");
      algo = nixstore::parseHashAlgo(as);
      if (!algo) throw EvalError("unknown hash algorithm '" + str(as) + "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'", pos);
    }
    const Attr *f = args[0]->attrs->get(st.symbols.create("toHashFormat"));
    if (!f) throw EvalError("attribute 'toHashFormat' missing", pos);
    auto fs = st.forceStringNoCtx(*f->value, pos, "while evaluating the attribute 'toHashFormat'");
    nixstore::HashFormat fmt;
    if (fs == "base16") fmt = nixstore::HashFormat::Base16;
    else if (fs == "nix32" || fs == "base32") fmt = nixstore::HashFormat::Nix32;
    else if (fs == "base64") fmt = nixstore::HashFormat::Base64;
    else if (fs == "sri") fmt = nixstore::HashFormat::SRI;
    else throw EvalError("unknown hash format '" + str(fs) + "', expect 'base16', 'base32', 'base64', or 'sri'", pos);
    try {
      nixstore::Hash hash = nixstore::parseHash(hs, algo);
      st.mkString(v, hash.to_string(fmt, fmt == nixstore::HashFormat::SRI));
    } catch (nixstore::Error &e) {
      throw EvalError(e.what(), pos);
    }
  });
  S.addPrimOp("__path", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    st.forceAttrs(*args[0], pos, "while evaluating the argument passed to 'builtins.path'");
    std::string path, name;
    Value *filter = nullptr;
    auto method = nixstore::FileIngestionMethod::NixArchive;
    std::optional<nixstore::Hash> expected;
    NixStringContext ctx;
    for (auto &a : *args[0]->attrs) {
      auto n = st.symbols[a.name];
      if (n == "path") path = st.coerceToPath(*a.value, ctx, pos, "while evaluating the 'path' attribute passed to 'builtins.path'");
      else if (n == "name") name = str(st.forceStringNoCtx(*a.value, pos));
      else if (n == "filter") { st.forceFunction(*a.value, pos); filter = a.value; }
      else if (n == "recursive") method = st.forceBool(*a.value, pos) ? nixstore::FileIngestionMethod::NixArchive : nixstore::FileIngestionMethod::Flat;
      else if (n == "sha256") {
        try {
          expected = nixstore::parseHash(st.forceStringNoCtx(*a.value, pos), nixstore::HashAlgo::SHA256);
        } catch (nixstore::Error &e) {
          throw EvalError(e.what(), pos);
        }
      } else throw EvalError("unsupported argument '" + n.str() + "' to 'builtins.path'", pos);
    }
    if (path.empty()) throw EvalError("missing required 'path' attribute in the first argument to 'builtins.path'", pos);
    if (name.empty()) name = nixstore::baseNameOf(path);
    addPath(st, pos, name, path, filter, method, expected, v, ctx);
  });
  S.addPrimOp("__filterSource", 2, [](EvalState &st, A args, Value &v, PosPtr pos) {
    NixStringContext ctx;
    std::string path = st.coerceToPath(*args[1], ctx, pos, "while evaluating the second argument (the path to filter) passed to 'builtins.filterSource'");
    st.forceFunction(*args[0], pos);
    addPath(st, pos, nixstore::baseNameOf(path), path, args[0], nixstore::FileIngestionMethod::NixArchive,
            std::nullopt, v, ctx);
  });
  S.addPrimOp("__fetchurl", 1, [](EvalState &st, A args, Value &v, PosPtr pos) { fetchImpl(st, args, v, pos, false, "fetchurl"); });
  S.addPrimOp("fetchTarball", 1, [](EvalState &st, A args, Value &v, PosPtr pos) { fetchImpl(st, args, v, pos, true, "fetchTarball"); });
  S.addPrimOp("fetchGit", 1, fetchGit);
  S.addPrimOp("fetchMercurial", 1, [](EvalState &st, A args, Value &v, PosPtr pos) {
    throw EvalError("fetchMercurial is not supported by mlnix", pos);
  });
}

} // namespace nixev
