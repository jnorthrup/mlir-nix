//===- LocalStore.cpp - A local Nix store with a builder ------------------===//
//
// Layout
//   <realRoot><storeDir>/<hash>-<name>     store objects
//   <stateDir>/info/<hash>-<name>          path metadata (valid paths)
//   <stateDir>/gcroots/                    GC roots (symlinks)
//
// `realRoot` allows a "chroot store" (like Nix's `--store local?root=...`):
// evaluation, instantiation and copying of sources work with the canonical
// /nix/store hashes even where /nix/store itself is not writable.  Building
// requires the logical store directory to be physically accessible, i.e.
// realRoot == "" (use --store-dir to pick a writable store directory).
//
//===----------------------------------------------------------------------===//

#include "Composite/Series.h"
#include "Nix/Store.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <sstream>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

namespace nixstore {

Store::Store(StoreSettings s) : settings(std::move(s)) {
  if (settings.stateDir.empty()) {
    const char *home = getenv("HOME");
    settings.stateDir = settings.realRoot.empty()
                            ? std::string(home ? home : "/tmp") + "/.local/state/mlnix"
                            : settings.realRoot + "/nix/var/mlnix";
  }
  if (!settings.cores) settings.cores = std::max(1u, std::thread::hardware_concurrency());
  log = [](const std::string &m) { std::cerr << m << "\n"; };
  try {
    createDirs(toReal(settings.storeDir));
  } catch (Error &) {
    // Not creatable (e.g. /nix/store on a read-only root): fine for evaluation.
  }
}

std::string Store::toReal(const std::string &logical) const {
  return settings.realRoot + logical;
}

std::string Store::infoFile(const std::string &path) const {
  return settings.stateDir + "/info/" + baseNameOf(path);
}

bool Store::isValidPath(const std::string &path) {
  if (drvCache.count(path)) return true;
  return pathExists(infoFile(path)) && pathExists(toReal(path));
}

std::optional<PathInfo> Store::queryPathInfo(const std::string &path) {
  std::string f = infoFile(path);
  if (!pathExists(f) || !pathExists(toReal(path))) return std::nullopt;
  PathInfo info;
  info.path = path;
  std::istringstream in(readFile(f));
  std::string line;
  while (std::getline(in, line)) {
    auto c = line.find(": ");
    if (c == std::string::npos) continue;
    std::string k = line.substr(0, c), v = line.substr(c + 2);
    if (k == "narHash") info.narHash = parseHash(v, std::nullopt);
    else if (k == "narSize") info.narSize = std::stoull(v);
    else if (k == "ref") info.references.insert(v);
    else if (k == "deriver") info.deriver = v;
    else if (k == "ca") info.ca = v;
  }
  return info;
}

void Store::registerValidPath(const PathInfo &info) {
  createDirs(settings.stateDir + "/info");
  std::string s = "path: " + info.path + "\nnarHash: " + info.narHash.to_string(HashFormat::Nix32, true) +
                  "\nnarSize: " + std::to_string(info.narSize) + "\n";
  for (auto &r : info.references) s += "ref: " + r + "\n";
  if (!info.deriver.empty()) s += "deriver: " + info.deriver + "\n";
  if (!info.ca.empty()) s += "ca: " + info.ca + "\n";
  std::string tmp = infoFile(info.path) + ".tmp";
  writeFile(tmp, s);
  rename(tmp.c_str(), infoFile(info.path).c_str());
}

composite::MutableSeries<std::string> Store::allValidPaths() {
  composite::MutableSeries<std::string> res;
  DIR *d = opendir((settings.stateDir + "/info").c_str());
  if (!d) return res;
  while (auto *e = readdir(d)) {
    std::string n = e->d_name;
    if (n == "." || n == ".." || n.size() < 34 || n.find(".tmp") != std::string::npos) continue;
    std::string p = settings.storeDir + "/" + n;
    if (pathExists(toReal(p))) res.append(p);
  }
  closedir(d);
  std::sort(res.begin(), res.end());
  return res;
}

std::set<std::string> Store::queryReferrers(const std::string &path) {
  std::set<std::string> res;
  for (auto &p : allValidPaths())
    if (auto info = queryPathInfo(p))
      if (info->references.count(path)) res.insert(p);
  return res;
}

/// Make a freshly created store object read-only with mtime 1, as Nix does.
static void canonicalisePathMetaData(const std::string &path) {
  struct stat st;
  if (lstat(path.c_str(), &st) != 0) throw Error("getting attributes of '" + path + "'");
  if (S_ISDIR(st.st_mode)) {
    DIR *d = opendir(path.c_str());
    if (d) {
      composite::MutableSeries<std::string> names;
      while (auto *e = readdir(d)) {
        std::string n = e->d_name;
        if (n != "." && n != "..") names.append(n);
      }
      closedir(d);
      for (auto &n : names) canonicalisePathMetaData(path + "/" + n);
    }
  }
  if (!S_ISLNK(st.st_mode)) {
    mode_t mode = (st.st_mode & S_IXUSR) || S_ISDIR(st.st_mode) ? 0555 : 0444;
    chmod(path.c_str(), mode);
  }
  struct timeval times[2] = {{1, 0}, {1, 0}};
  lutimes(path.c_str(), times);
}

static void copyRecursive(const std::string &from, const std::string &to, const PathFilter &filter,
                          bool top = true) {
  struct stat st;
  if (lstat(from.c_str(), &st) != 0) throw Error("getting status of '" + from + "': " + strerror(errno));
  if (S_ISREG(st.st_mode)) {
    writeFile(to, readFile(from), (st.st_mode & S_IXUSR) ? 0755 : 0644);
  } else if (S_ISDIR(st.st_mode)) {
    if (mkdir(to.c_str(), 0755) != 0) throw Error("creating directory '" + to + "': " + strerror(errno));
    DIR *d = opendir(from.c_str());
    if (!d) throw Error("opening directory '" + from + "'");
    composite::MutableSeries<std::string> names;
    while (auto *e = readdir(d)) {
      std::string n = e->d_name;
      if (n != "." && n != "..") names.append(n);
    }
    closedir(d);
    for (auto &n : names) {
      std::string c = from + "/" + n;
      if (filter && !filter(c)) continue;
      copyRecursive(c, to + "/" + n, filter, false);
    }
  } else if (S_ISLNK(st.st_mode)) {
    char buf[PATH_MAX + 1];
    ssize_t n = readlink(from.c_str(), buf, PATH_MAX);
    if (n < 0) throw Error("reading symlink '" + from + "'");
    if (symlink(std::string(buf, n).c_str(), to.c_str()) != 0)
      throw Error("creating symlink '" + to + "': " + strerror(errno));
  } else {
    throw Error("file '" + from + "' has an unsupported type");
  }
  (void)top;
}

std::string Store::computeStorePathForPath(std::string name, const std::string &srcPath,
                                           FileIngestionMethod method, HashAlgo algo,
                                           const PathFilter &filter) {
  Hash h = method == FileIngestionMethod::NixArchive ? hashPath(srcPath, filter, algo).first
                                                     : hashFile(algo, srcPath);
  return makeFixedOutputPath(settings.storeDir, name, method, h);
}

std::string Store::addToStore(std::string name, const std::string &srcPath, FileIngestionMethod method,
                              HashAlgo algo, const PathFilter &filter,
                              const std::set<std::string> &refs, std::optional<Hash> expected) {
  Hash h;
  if (method == FileIngestionMethod::NixArchive) h = hashPath(srcPath, filter, algo).first;
  else if (method == FileIngestionMethod::Text) h = hashString(HashAlgo::SHA256, readFile(srcPath));
  else h = hashFile(algo, srcPath);
  if (expected && !(*expected == h))
    throw Error("hash mismatch importing path '" + srcPath + "';\n  specified: " +
                expected->to_string(HashFormat::SRI, true) + "\n  got:       " +
                h.to_string(HashFormat::SRI, true));
  std::string dst = makeFixedOutputPath(settings.storeDir, name, method, h, refs);
  if (settings.readOnly || isValidPath(dst)) return dst;
  std::string real = toReal(dst);
  createDirs(toReal(settings.storeDir));
  if (pathExists(real)) deletePathRecursive(real);
  if (method == FileIngestionMethod::NixArchive) copyRecursive(srcPath, real, filter);
  else {
    struct stat st;
    stat(srcPath.c_str(), &st);
    writeFile(real, readFile(srcPath), (st.st_mode & S_IXUSR) ? 0755 : 0644);
  }
  canonicalisePathMetaData(real);
  PathInfo info;
  info.path = dst;
  auto [nh, ns] = hashPath(real);
  info.narHash = nh;
  info.narSize = ns;
  info.references = refs;
  info.ca = (method == FileIngestionMethod::NixArchive ? "fixed:r:" : method == FileIngestionMethod::Text ? "text:" : "fixed:") +
            h.to_string(HashFormat::Nix32, true);
  registerValidPath(info);
  return dst;
}

std::string Store::addTextToStore(std::string_view name, std::string_view text,
                                  const std::set<std::string> &refs) {
  Hash h = hashString(HashAlgo::SHA256, text);
  std::string dst = makeTextPath(settings.storeDir, name, h, refs);
  if (settings.readOnly || isValidPath(dst)) return dst;
  createDirs(toReal(settings.storeDir));
  std::string real = toReal(dst);
  if (pathExists(real)) deletePathRecursive(real);
  writeFile(real, text, 0644);
  canonicalisePathMetaData(real);
  PathInfo info;
  info.path = dst;
  auto [nh, ns] = hashPath(real);
  info.narHash = nh;
  info.narSize = ns;
  info.references = refs;
  info.ca = "text:" + h.to_string(HashFormat::Nix32, true);
  registerValidPath(info);
  return dst;
}

//===----------------------------------------------------------------------===//
// Derivations in the store
//===----------------------------------------------------------------------===//

static std::set<std::string> drvReferences(const Derivation &drv) {
  std::set<std::string> refs = drv.inputSrcs;
  for (auto &[p, o] : drv.inputDrvs) refs.insert(p);
  return refs;
}

std::string Store::computeDerivationPath(const Derivation &drv) const {
  return makeTextPath(settings.storeDir, drv.name + ".drv",
                      hashString(HashAlgo::SHA256, drv.unparse(false)), drvReferences(drv));
}

void Store::cacheDerivation(const std::string &drvPath, const Derivation &drv) {
  drvCache[drvPath] = drv;
}

std::string Store::writeDerivation(const Derivation &drv) {
  std::string path = computeDerivationPath(drv);
  drvCache[path] = drv;
  if (settings.readOnly) return path;
  addTextToStore(drv.name + ".drv", drv.unparse(false), drvReferences(drv));
  return path;
}

Derivation Store::readDerivation(const std::string &drvPath) {
  auto it = drvCache.find(drvPath);
  if (it != drvCache.end()) return it->second;
  std::string name = storePathName(drvPath);
  if (name.size() < 4 || name.substr(name.size() - 4) != ".drv")
    throw Error("store path '" + baseNameOf(drvPath) + "' is not a valid derivation path");
  std::string real = toReal(drvPath);
  if (!pathExists(real)) throw Error("path '" + drvPath + "' is not valid");
  Derivation d = parseDerivation(readFile(real), name.substr(0, name.size() - 4));
  drvCache[drvPath] = d;
  return d;
}

std::map<std::string, Hash> Store::hashDerivationModulo(const Derivation &drv, bool maskOutputs) {
  if (drv.isFixed()) {
    std::map<std::string, Hash> res;
    for (auto &[name, o] : drv.outputs) {
      std::string p = o.fixedPath(settings.storeDir, drv.name, name);
      res[name] = hashString(HashAlgo::SHA256, "fixed:out:" + o.methodAlgo() + ":" +
                                                   o.hash.to_string(HashFormat::Base16, false) + ":" + p);
    }
    return res;
  }
  for (auto &[n, o] : drv.outputs)
    if (o.kind == DerivationOutput::CAFloating || o.kind == DerivationOutput::Impure)
      throw Error("content-addressed and impure derivations are not supported (derivation '" + drv.name + "')");
  std::map<std::string, std::set<std::string>> inputs2;
  for (auto &[drvPath, outs] : drv.inputDrvs) {
    std::map<std::string, Hash> h;
    auto it = drvHashes.find(drvPath);
    if (it != drvHashes.end()) h = it->second;
    else {
      h = hashDerivationModulo(readDerivation(drvPath), false);
      drvHashes[drvPath] = h;
    }
    if (h.count("")) {
      inputs2[h[""].to_string(HashFormat::Base16, false)].insert(outs.begin(), outs.end());
    } else {
      for (auto &o : outs) {
        auto j = h.find(o);
        if (j == h.end()) throw Error("no hash for output '" + o + "' of derivation '" + drv.name + "'");
        inputs2[j->second.to_string(HashFormat::Base16, false)].insert("out");
      }
    }
  }
  return {{"", hashString(HashAlgo::SHA256, drv.unparse(maskOutputs, &inputs2))}};
}

void Store::fillInOutputPaths(Derivation &drv) {
  auto h = hashDerivationModulo(drv, true);
  for (auto &[name, o] : drv.outputs) {
    if (o.kind != DerivationOutput::Deferred) continue;
    std::string p = makeOutputPath(settings.storeDir, name, h.at(""), drv.name);
    o.kind = DerivationOutput::InputAddressed;
    o.path = p;
    auto e = drv.env.find(name);
    if (e == drv.env.end() || e->second.empty()) drv.env[name] = p;
  }
}

std::set<std::string> Store::computeFSClosure(const std::set<std::string> &paths, bool includeOutputs) {
  std::set<std::string> res;
  composite::MutableSeries<std::string> todo(paths.begin(), paths.end());
  while (!todo.empty()) {
    std::string p = todo.back();
    todo.pop();
    if (!res.insert(p).second) continue;
    if (auto info = queryPathInfo(p)) {
      for (auto &r : info->references) todo.append(r);
    } else if (drvCache.count(p)) {
      auto &d = drvCache[p];
      for (auto &r : drvReferences(d)) todo.append(r);
    }
    if (includeOutputs && p.size() > 4 && p.substr(p.size() - 4) == ".drv") {
      try {
        Derivation d = readDerivation(p);
        for (auto &[n, o] : d.outputs)
          if (!o.path.empty() && isValidPath(o.path)) todo.append(o.path);
      } catch (Error &) {
      }
    }
  }
  return res;
}

//===----------------------------------------------------------------------===//
// Building
//===----------------------------------------------------------------------===//

static std::set<std::string> scanForReferences(const std::string &path,
                                               const std::set<std::string> &candidates) {
  std::map<std::string, std::string> byHash;
  for (auto &c : candidates) byHash[storePathHashPart(c)] = c;
  std::set<std::string> found;
  std::function<void(const std::string &)> scan = [&](const std::string &p) {
    struct stat st;
    if (lstat(p.c_str(), &st) != 0) return;
    std::string data;
    if (S_ISREG(st.st_mode)) data = readFile(p);
    else if (S_ISLNK(st.st_mode)) {
      char buf[PATH_MAX + 1];
      ssize_t n = readlink(p.c_str(), buf, PATH_MAX);
      if (n > 0) data.assign(buf, n);
    } else if (S_ISDIR(st.st_mode)) {
      DIR *d = opendir(p.c_str());
      if (!d) return;
      composite::MutableSeries<std::string> names;
      while (auto *e = readdir(d)) {
        std::string n = e->d_name;
        if (n != "." && n != "..") names.append(n);
      }
      closedir(d);
      for (auto &n : names) scan(p + "/" + n);
      return;
    }
    // Scan for 32-character runs of nix32 characters.
    static bool isNix32[256] = {false};
    static bool init = false;
    if (!init) {
      for (const char *c = nix32Chars; *c; c++) isNix32[(unsigned char)*c] = true;
      init = true;
    }
    size_t run = 0;
    for (size_t i = 0; i < data.size(); i++) {
      if (isNix32[(unsigned char)data[i]]) {
        run++;
        if (run >= 32) {
          std::string h = data.substr(i + 1 - 32, 32);
          auto it = byHash.find(h);
          if (it != byHash.end()) found.insert(it->second);
        }
      } else {
        run = 0;
      }
    }
  };
  scan(path);
  return found;
}

void Store::ensurePath(const std::string &path) {
  if (isValidPath(path)) return;
  throw Error("path '" + path + "' is not valid and cannot be substituted (no binary caches)");
}

std::map<std::string, std::string> Store::buildDerivation(const std::string &drvPath) {
  std::set<std::string> visiting;
  return realise(drvPath, visiting);
}

std::map<std::string, std::string> Store::realise(const std::string &drvPath,
                                                  std::set<std::string> &visiting) {
  if (!visiting.insert(drvPath).second) throw Error("cycle in derivation graph at '" + drvPath + "'");
  Derivation drv = readDerivation(drvPath);
  std::map<std::string, std::string> outputs;
  for (auto &[name, o] : drv.outputs) {
    if (o.kind == DerivationOutput::InputAddressed || o.kind == DerivationOutput::CAFixed)
      outputs[name] = o.kind == DerivationOutput::CAFixed && o.path.empty()
                          ? o.fixedPath(settings.storeDir, drv.name, name) : o.path;
    else
      throw Error("cannot build derivation '" + drvPath + "': content-addressed/impure outputs are not supported");
  }
  bool allValid = true;
  for (auto &[n, p] : outputs) allValid &= isValidPath(p);
  if (allValid) {
    visiting.erase(drvPath);
    return outputs;
  }
  if (settings.readOnly) throw Error("cannot build '" + drvPath + "' in read-only mode");
  if (!settings.realRoot.empty())
    throw Error("cannot build '" + drvPath + "': the store directory '" + settings.storeDir +
                "' is not physically accessible (chroot store at '" + settings.realRoot +
                "'); use --store-dir with a writable directory to build");
  for (auto &[inDrv, outs] : drv.inputDrvs) {
    auto res = realise(inDrv, visiting);
    for (auto &o : outs)
      if (!res.count(o)) throw Error("derivation '" + inDrv + "' does not have output '" + o + "'");
  }
  for (auto &src : drv.inputSrcs) ensurePath(src);

  log("building '" + drvPath + "'...");
  if (drv.builder == "builtin:fetchurl") builtinFetchurl(drv, outputs);
  else runBuilder(drvPath, drv, outputs);

  // Post-process outputs.
  std::set<std::string> candidates;
  {
    std::set<std::string> inputs = drv.inputSrcs;
    for (auto &[inDrv, outs] : drv.inputDrvs) {
      Derivation d = readDerivation(inDrv);
      for (auto &o : outs) {
        auto &out = d.outputs.at(o);
        inputs.insert(out.kind == DerivationOutput::CAFixed && out.path.empty()
                          ? out.fixedPath(settings.storeDir, d.name, o) : out.path);
      }
    }
    candidates = computeFSClosure(inputs);
    for (auto &[n, p] : outputs) candidates.insert(p);
  }
  for (auto &[name, path] : outputs) {
    std::string real = toReal(path);
    if (!pathExists(real))
      throw Error("builder for '" + drvPath + "' failed to produce output path for output '" + name +
                  "' at '" + path + "'");
    canonicalisePathMetaData(real);
    auto &o = drv.outputs.at(name);
    if (o.kind == DerivationOutput::CAFixed) {
      Hash got = o.method == FileIngestionMethod::NixArchive ? hashPath(real, nullptr, o.hash.algo).first
                                                             : hashFile(o.hash.algo, real);
      if (!(got == o.hash)) {
        deletePathRecursive(real);
        throw Error("hash mismatch in fixed-output derivation '" + drvPath + "':\n         specified: " +
                    o.hash.to_string(HashFormat::SRI, true) + "\n            got:    " +
                    got.to_string(HashFormat::SRI, true));
      }
    }
    PathInfo info;
    info.path = path;
    auto [nh, ns] = hashPath(real);
    info.narHash = nh;
    info.narSize = ns;
    info.references = o.kind == DerivationOutput::CAFixed ? std::set<std::string>{}
                                                         : scanForReferences(real, candidates);
    info.deriver = drvPath;
    if (o.kind == DerivationOutput::CAFixed)
      info.ca = (o.method == FileIngestionMethod::NixArchive ? "fixed:r:" : "fixed:") +
                o.hash.to_string(HashFormat::Nix32, true);
    registerValidPath(info);
  }
  visiting.erase(drvPath);
  return outputs;
}


void Store::runBuilder(const std::string &drvPath, const Derivation &drv,
                       const std::map<std::string, std::string> &outputs) {
  const char *tmp = getenv("TMPDIR");
  std::string tmpBase = tmp && *tmp ? tmp : "/tmp";
  std::string tmpl = tmpBase + "/nix-build-" + drv.name + "-XXXXXX";
  composite::MutableSeries<char> buf(tmpl.begin(), tmpl.end());
  buf.append('\0');
  if (!mkdtemp(buf.data())) throw Error("creating build directory: " + std::string(strerror(errno)));
  std::string top = buf.data();

  std::map<std::string, std::string> env;
  env["PATH"] = "/path-not-set";
  env["HOME"] = "/homeless-shelter";
  env["NIX_STORE"] = settings.storeDir;
  env["NIX_BUILD_CORES"] = std::to_string(settings.cores);
  env["NIX_BUILD_TOP"] = top;
  env["TMPDIR"] = env["TEMPDIR"] = env["TMP"] = env["TEMP"] = top;
  env["PWD"] = top;
  env["NIX_LOG_FD"] = "2";
  env["TERM"] = "xterm-256color";
  bool fixed = drv.isFixed();
  if (fixed) {
    auto it = drv.env.find("impureEnvVars");
    if (it != drv.env.end()) {
      std::istringstream ss(it->second);
      std::string v;
      while (ss >> v)
        if (const char *val = getenv(v.c_str())) env[v] = val;
    }
  }
  // Output placeholders (builtins.placeholder) are rewritten to the real
  // output paths in the environment, arguments and structured attributes.
  std::map<std::string, std::string> rewrites;
  for (auto &[n, p] : outputs) rewrites[hashPlaceholder(n)] = p;
  auto rewrite = [&](std::string s) {
    for (auto &[from, to] : rewrites) {
      size_t pos = 0;
      while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
      }
    }
    return s;
  };
  for (auto &[k, v] : drv.env) env[k] = rewrite(v);
  if (drv.structuredAttrs) {
    auto [json, sh] = structuredAttrsFiles(*drv.structuredAttrs, outputs, rewrites);
    writeFile(top + "/.attrs.json", json);
    writeFile(top + "/.attrs.sh", sh);
    env["NIX_ATTRS_JSON_FILE"] = top + "/.attrs.json";
    env["NIX_ATTRS_SH_FILE"] = top + "/.attrs.sh";
  }

  composite::MutableSeries<std::string> envStrs;
  for (auto &[k, v] : env) envStrs.append(k + "=" + v);
  composite::MutableSeries<char *> envp;
  for (auto &s : envStrs) envp.append(const_cast<char *>(s.c_str()));
  envp.append(nullptr);
  composite::MutableSeries<char *> argv;
  std::string builderBase = baseNameOf(drv.builder);
  argv.append(const_cast<char *>(builderBase.c_str()));
  composite::MutableSeries<std::string> args;
  for (auto &a : drv.args) args.append(rewrite(a));
  for (auto &a : args) argv.append(const_cast<char *>(a.c_str()));
  argv.append(nullptr);

  pid_t pid = fork();
  if (pid < 0) throw Error("fork failed");
  if (pid == 0) {
    if (chdir(top.c_str()) != 0) _exit(127);
    int nul = open("/dev/null", O_RDONLY);
    dup2(nul, 0);
    dup2(2, 1);
    setsid();
    execve(drv.builder.c_str(), argv.data(), envp.data());
    fprintf(stderr, "error: executing '%s': %s\n", drv.builder.c_str(), strerror(errno));
    _exit(127);
  }
  int status;
  while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
  }
  bool ok = WIFEXITED(status) && WEXITSTATUS(status) == 0;
  if (!ok) {
    for (auto &[n, p] : outputs)
      if (pathExists(toReal(p))) deletePathRecursive(toReal(p));
    std::string why = WIFEXITED(status) ? "failed with exit code " + std::to_string(WEXITSTATUS(status))
                                        : "was killed by signal " + std::to_string(WTERMSIG(status));
    if (settings.keepFailed) log("note: keeping build directory '" + top + "'");
    else deletePathRecursive(top);
    throw Error("builder for '" + drvPath + "' " + why);
  }
  deletePathRecursive(top);
}

void Store::builtinFetchurl(const Derivation &drv, const std::map<std::string, std::string> &outputs) {
  auto get = [&](const std::string &k) {
    auto it = drv.env.find(k);
    return it == drv.env.end() ? std::string() : it->second;
  };
  std::string url = get("url");
  if (url.empty()) {
    std::istringstream ss(get("urls"));
    ss >> url;
  }
  if (url.empty()) throw Error("builtin:fetchurl: no URL specified");
  std::string out = outputs.at("out");
  std::string real = toReal(out);
  createDirs(toReal(settings.storeDir));
  std::string tmp = real + ".tmp";
  std::string curlOut;
  int rc = runProgram("curl", {"-fsSL", "--retry", "3", "-o", tmp, url}, &curlOut);
  if (rc != 0) {
    unlink(tmp.c_str());
    throw Error("unable to download '" + url + "': curl exited with code " + std::to_string(rc));
  }
  if (get("unpack") == "1") {
    std::string nar = readFile(tmp);
    unlink(tmp.c_str());
    restorePath(real, nar);
  } else {
    rename(tmp.c_str(), real.c_str());
    if (get("executable") == "1") chmod(real.c_str(), 0755);
  }
}

void Store::addPermRoot(const std::string &storePath, const std::string &link) {
  unlink(link.c_str());
  if (symlink(toReal(storePath).c_str(), link.c_str()) != 0)
    throw Error("creating symlink '" + link + "': " + strerror(errno));
  std::string rootDir = settings.stateDir + "/gcroots/auto";
  createDirs(rootDir);
  char absBuf[PATH_MAX];
  std::string abs = link;
  if (link[0] != '/' && getcwd(absBuf, sizeof absBuf)) abs = std::string(absBuf) + "/" + link;
  std::string rootLink = rootDir + "/" + hashString(HashAlgo::SHA256, abs).to_string(HashFormat::Nix32, false).substr(0, 32);
  unlink(rootLink.c_str());
  symlink(abs.c_str(), rootLink.c_str());
}

bool Store::deletePath(const std::string &path) {
  if (!queryReferrers(path).empty()) return false;
  deletePathRecursive(toReal(path));
  unlink(infoFile(path).c_str());
  return true;
}

bool Store::collectGarbage(bool dryRun, std::vector<std::string> &deleted) {
  std::set<std::string> roots;
  std::function<void(const std::string &)> scanRoots = [&](const std::string &dir) {
    DIR *d = opendir(dir.c_str());
    if (!d) return;
    composite::MutableSeries<std::string> names;
    while (auto *e = readdir(d)) {
      std::string n = e->d_name;
      if (n != "." && n != "..") names.append(n);
    }
    closedir(d);
    for (auto &n : names) {
      std::string p = dir + "/" + n;
      struct stat st;
      if (lstat(p.c_str(), &st) != 0) continue;
      if (S_ISDIR(st.st_mode)) { scanRoots(p); continue; }
      if (!S_ISLNK(st.st_mode)) continue;
      char buf[PATH_MAX + 1];
      ssize_t len = readlink(p.c_str(), buf, PATH_MAX);
      if (len <= 0) continue;
      std::string target(buf, len);
      // Indirect root: a symlink to a symlink into the store.
      char buf2[PATH_MAX + 1];
      ssize_t len2 = readlink(target.c_str(), buf2, PATH_MAX);
      if (len2 > 0) target.assign(buf2, len2);
      std::string real = settings.realRoot;
      if (!real.empty() && target.rfind(real, 0) == 0) target = target.substr(real.size());
      if (isInStore(settings.storeDir, target)) roots.insert(toStorePath(settings.storeDir, target));
      else if (len2 <= 0 && !pathExists(target)) unlink(p.c_str());
    }
  };
  scanRoots(settings.stateDir + "/gcroots");
  auto live = computeFSClosure(roots, true);
  composite::MutableSeries<std::string> dead;
  for (auto &p : allValidPaths())
    if (!live.count(p)) dead.append(p);
  // Delete in referrer-safe order: repeat until no progress.
  bool progress = true;
  std::set<std::string> remaining(dead.begin(), dead.end());
  while (progress && !remaining.empty()) {
    progress = false;
    for (auto it = remaining.begin(); it != remaining.end();) {
      bool referenced = false;
      for (auto &q : remaining) {
        if (q == *it) continue;
        if (auto info = queryPathInfo(q))
          if (info->references.count(*it)) { referenced = true; break; }
      }
      if (referenced) { ++it; continue; }
      if (!dryRun) {
        deletePathRecursive(toReal(*it));
        unlink(infoFile(*it).c_str());
      }
      deleted.push_back(*it);
      it = remaining.erase(it);
      progress = true;
    }
  }
  return true;
}

} // namespace nixstore
