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

#include "Composite/Mutable.h"
#include "Composite/Rows.h"
#include "Composite/Text.h"
#include "Nix/Numbers.h"
#include "Nix/Os.h"
#include "Nix/Store.h"
#include "llvm/ADT/ArrayRef.h" // xxh3_64bits' ArrayRef overload lives here from LLVM 23, in xxhash.h before
#include "llvm/Support/xxhash.h"
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <exception>
#include <unistd.h>

namespace nixstore {

Store::Store(StoreSettings s) : settings(std::move(s)) {
  if (settings.stateDir.empty()) {
    const char *home = getenv("HOME");
    settings.stateDir = settings.realRoot.empty()
                            ? composite::cat(home ? home : "/tmp", "/.local/state/mlnix")
                            : settings.realRoot + "/nix/var/mlnix";
  }
  if (!settings.cores) settings.cores = nixsys::processors();
  log = [](std::string_view m) { nixsys::lineToStderr(m.data(), m.size()); };
  try {
    createDirs(toReal(settings.storeDir));
  } catch (Error &) {
    // Not creatable (e.g. /nix/store on a read-only root): fine for evaluation.
  }
}

composite::Text Store::toReal(std::string_view logical) const {
  return settings.realRoot + logical;
}

composite::Text Store::infoFile(std::string_view path) const {
  return settings.stateDir + "/info/" + baseNameOf(path);
}

Store::DrvRecord *Store::drvAt(std::string_view path) {
  DrvRecord **r = drvs.find(path.data(), uint32_t(path.size()));
  return r ? *r : nullptr;
}

Store::DrvRecord &Store::keepDerivation(std::string_view path, Derivation &&drv, bool replace) {
  if (DrvRecord *r = drvAt(path)) {
    if (replace) r->drv = std::move(drv);
    return *r;
  }
  auto *r = new DrvRecord{composite::Text(path), std::move(drv)};
  drvs.set(r->path.data(), uint32_t(r->path.size()), r, [r] { return r->path.c_str(); }); // the key is the record's own path
  return *r;
}

bool Store::isValidPath(std::string_view path) {
  if (drvAt(path)) return true;
  return pathExists(infoFile(path)) && pathExists(toReal(path));
}

composite::Maybe<PathInfo> Store::queryPathInfo(std::string_view path) {
  composite::Text f = infoFile(path);
  if (!pathExists(f) || !pathExists(toReal(path))) return nullptr;
  PathInfo info;
  info.path = composite::Text(path);
  composite::Text text = readFile(f);
  composite::eachLine(text.data(), uint32_t(text.size()), [&](const char *p, uint32_t n) {
    std::string_view line(p, n);
    auto c = line.find(": ");
    if (c == std::string_view::npos) return;
    std::string_view k = line.substr(0, c);
    std::string_view v = line.substr(c + 2);
    if (k == "narHash") info.narHash = parseHash(v, nullptr);
    else if (k == "narSize") info.narSize = nixsys::stoValue("stoull", nixsys::readUnsigned(v));
    else if (k == "ref") info.references.insert(v);
    else if (k == "deriver") info.deriver = composite::Text(v);
    else if (k == "ca") info.ca = composite::Text(v);
  });
  return info;
}

void Store::registerValidPath(const PathInfo &info) {
  createDirs(settings.stateDir + "/info");
  composite::Text s = composite::cat("path: ", info.path, "\nnarHash: ", info.narHash.to_string(HashFormat::Nix32, true),
                                     "\nnarSize: ", info.narSize, "\n");
  for (auto &r : info.references) s.put("ref: ").put(r).put("\n");
  if (!info.deriver.empty()) s.put("deriver: ").put(info.deriver).put("\n");
  if (!info.ca.empty()) s.put("ca: ").put(info.ca).put("\n");
  composite::Text tmp = infoFile(info.path) + ".tmp";
  writeFile(tmp, s);
  rename(tmp.c_str(), infoFile(info.path).c_str());
}

composite::MutableSeries<composite::Text> Store::allValidPaths() {
  composite::MutableSeries<composite::Text> res;
  DIR *d = opendir((settings.stateDir + "/info").c_str());
  if (!d) return res;
  while (auto *e = readdir(d)) {
    std::string_view n = e->d_name;
    if (n == "." || n == ".." || n.size() < 34 || n.find(".tmp") != std::string_view::npos) continue;
    composite::Text p = settings.storeDir + "/" + n;
    if (pathExists(toReal(p))) res.append(composite::mv(p));
  }
  closedir(d);
  composite::MutableSeries<composite::Text *> order; // rows of pointers are sorted, then each path moves once, into its place
  for (auto &p : res) order.append(&p);
  composite::sortRows(order.data(), order.size(), [](const composite::Text *a, const composite::Text *b) {
    return composite::lessChars(composite::series(a->data(), uint32_t(a->size())), composite::series(b->data(), uint32_t(b->size())));
  });
  composite::MutableSeries<composite::Text> sorted;
  sorted.reserve(res.size());
  for (composite::Text *p : order) sorted.append(composite::mv(*p));
  return sorted;
}

SortedSet Store::queryReferrers(std::string_view path) {
  SortedSet res;
  for (auto &p : allValidPaths())
    if (auto info = queryPathInfo(p))
      if (info->references.count(path)) res.insert(p);
  return res;
}

/// Make a freshly created store object read-only with mtime 1, as Nix does.
static void canonicalisePathMetaData(const composite::Text &path) {
  struct stat st;
  if (lstat(path.c_str(), &st) != 0) throw Error(composite::cat("getting attributes of '", path, "'"));
  if (S_ISDIR(st.st_mode)) {
    DIR *d = opendir(path.c_str());
    if (d) {
      composite::MutableSeries<composite::Text> names;
      while (auto *e = readdir(d)) {
        std::string_view n = e->d_name;
        if (n != "." && n != "..") names.append(composite::Text(n));
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

static void copyRecursive(const composite::Text &from, const composite::Text &to, const PathFilter &filter,
                          bool top = true) {
  struct stat st;
  if (lstat(from.c_str(), &st) != 0) throw Error(composite::cat("getting status of '", from, "': ", strerror(errno)));
  if (S_ISREG(st.st_mode)) {
    writeFile(to, readFile(from), (st.st_mode & S_IXUSR) ? 0755 : 0644);
  } else if (S_ISDIR(st.st_mode)) {
    if (mkdir(to.c_str(), 0755) != 0) throw Error(composite::cat("creating directory '", to, "': ", strerror(errno)));
    DIR *d = opendir(from.c_str());
    if (!d) throw Error(composite::cat("opening directory '", from, "'"));
    composite::MutableSeries<composite::Text> names;
    while (auto *e = readdir(d)) {
      std::string_view n = e->d_name;
      if (n != "." && n != "..") names.append(composite::Text(n));
    }
    closedir(d);
    for (auto &n : names) {
      composite::Text c = from + "/" + n;
      if (filter && !filter(c, {})) continue;
      copyRecursive(c, to + "/" + n, filter, false);
    }
  } else if (S_ISLNK(st.st_mode)) {
    char buf[PATH_MAX + 1];
    ssize_t n = readlink(from.c_str(), buf, PATH_MAX);
    if (n < 0) throw Error(composite::cat("reading symlink '", from, "'"));
    if (symlink(composite::Text(buf, size_t(n)).c_str(), to.c_str()) != 0)
      throw Error(composite::cat("creating symlink '", to, "': ", strerror(errno)));
  } else {
    throw Error(composite::cat("file '", from, "' has an unsupported type"));
  }
  (void)top;
}

composite::Text Store::computeStorePathForPath(std::string_view name, std::string_view srcPath,
                                               FileIngestionMethod method, HashAlgo algo,
                                               const PathFilter &filter) {
  Hash h = method == FileIngestionMethod::NixArchive ? hashPath(srcPath, filter, algo).a
                                                     : hashFile(algo, srcPath);
  return makeFixedOutputPath(settings.storeDir, name, method, h);
}

composite::Text Store::addToStore(std::string_view name, std::string_view srcPath, FileIngestionMethod method,
                                 HashAlgo algo, const PathFilter &filter,
                                 const SortedSet &refs, composite::Maybe<Hash> expected) {
  Hash h;
  if (method == FileIngestionMethod::NixArchive) h = hashPath(srcPath, filter, algo).a;
  else if (method == FileIngestionMethod::Text) h = hashString(HashAlgo::SHA256, readFile(srcPath));
  else h = hashFile(algo, srcPath);
  if (expected && !(*expected == h))
    throw Error(composite::cat("hash mismatch importing path '", srcPath, "';\n  specified: ",
                               expected->to_string(HashFormat::SRI, true), "\n  got:       ",
                               h.to_string(HashFormat::SRI, true)));
  composite::Text dst = makeFixedOutputPath(settings.storeDir, name, method, h, refs);
  if (settings.readOnly || isValidPath(dst)) return dst;
  composite::Text real = toReal(dst);
  createDirs(toReal(settings.storeDir));
  if (pathExists(real)) deletePathRecursive(real);
  if (method == FileIngestionMethod::NixArchive) copyRecursive(composite::Text(srcPath), real, filter);
  else {
    struct stat st;
    stat(nixsys::CStr(srcPath), &st);
    writeFile(real, readFile(srcPath), (st.st_mode & S_IXUSR) ? 0755 : 0644);
  }
  canonicalisePathMetaData(real);
  PathInfo info;
  info.path = dst.clone();
  auto [nh, ns] = hashPath(real);
  info.narHash = nh;
  info.narSize = ns;
  info.references = refs;
  info.ca = composite::cat(method == FileIngestionMethod::NixArchive ? "fixed:r:" : method == FileIngestionMethod::Text ? "text:" : "fixed:",
                           h.to_string(HashFormat::Nix32, true));
  registerValidPath(info);
  return dst;
}

composite::Text Store::addTextToStore(std::string_view name, std::string_view text,
                                      const SortedSet &refs) {
  Hash h = hashString(HashAlgo::SHA256, text);
  composite::Text dst = makeTextPath(settings.storeDir, name, h, refs);
  if (settings.readOnly || isValidPath(dst)) return dst;
  createDirs(toReal(settings.storeDir));
  composite::Text real = toReal(dst);
  if (pathExists(real)) deletePathRecursive(real);
  writeFile(real, text, 0644);
  canonicalisePathMetaData(real);
  PathInfo info;
  info.path = dst.clone();
  auto [nh, ns] = hashPath(real);
  info.narHash = nh;
  info.narSize = ns;
  info.references = refs;
  info.ca = composite::cat("text:", h.to_string(HashFormat::Nix32, true));
  registerValidPath(info);
  return dst;
}

//===----------------------------------------------------------------------===//
// Derivations in the store
//===----------------------------------------------------------------------===//

static SortedSet drvReferences(const Derivation &drv) {
  SortedSet refs(drv.inputSrcs.begin(), drv.inputSrcs.end());
  for (auto &[p, o] : drv.inputDrvs) refs.insert(p);
  return refs;
}

composite::Text Store::computeDerivationPath(const Derivation &drv) const {
  return makeTextPath(settings.storeDir, drv.name + ".drv", drv.hashUnparsed(false), drvReferences(drv));
}

void Store::cacheDerivation(std::string_view drvPath, const Derivation &drv) {
  keepDerivation(drvPath, Derivation(drv), true);
}

composite::Text Store::writeDerivation(Derivation &&drv) {
  // The text's hash names the path; a store that writes keeps the text too, made once, and a read-only one only feeds the hash with it.
  composite::Text text = settings.readOnly ? composite::Text() : drv.unparse(false);
  // The path's type is `text` and its references: the input sources and the input derivations, both sorted, merged here (a path in both
  // once), as makeTextPath would join drvReferences' set, without building the set.
  composite::Text type = "text";
  auto src = drv.inputSrcs.begin(), srcEnd = drv.inputSrcs.end();
  auto in = drv.inputDrvs.begin(), inEnd = drv.inputDrvs.end();
  while (src != srcEnd || in != inEnd) {
    const composite::Text *r;
    if (in == inEnd || (src != srcEnd && *src < in->first)) r = &*src++;
    else if (src == srcEnd || in->first < *src) r = &(in++)->first;
    else { r = &*src++; ++in; }
    type += ':';
    type += *r;
  }
  composite::Text path = makeStorePath(settings.storeDir, type, settings.readOnly ? drv.hashUnparsed(false) : hashString(HashAlgo::SHA256, text),
                                       drv.name + ".drv");
  const Derivation &kept = keepDerivation(path, std::move(drv), false).drv; // a path names its text: the first is kept, never rewritten
  if (!settings.readOnly) addTextToStore(kept.name + ".drv", text, drvReferences(kept));
  return path;
}

/// A fingerprint of a derivation's content: each of its strings through xxh3, in order, with the counts that delimit its lists.  Equal content
/// gives equal fingerprints; sameContent checks the converse.
static uint64_t contentFingerprint(const Derivation &drv) {
  uint64_t h = 0;
  auto word = [&](uint64_t w) { h = (h ^ w) * 0x9e3779b97f4a7c15ull; h ^= h >> 29; };
  auto str = [&](std::string_view s) { word(llvm::xxh3_64bits(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(s.data()), s.size()))); };
  str(drv.name), str(drv.platform), str(drv.builder);
  word(drv.args.size());
  for (const composite::Text &a : drv.args) str(a);
  word(drv.inputSrcs.size());
  for (const composite::Text &s : drv.inputSrcs) str(s);
  word(drv.inputDrvs.size());
  for (auto &[p, outs] : drv.inputDrvs) {
    str(p), word(outs.size());
    for (const composite::Text &o : outs) str(o);
  }
  word(drv.outputs.size());
  for (auto &[n, o] : drv.outputs) str(n), word(o.kind), str(o.path);
  word(drv.env.size());
  for (auto &[k, v] : drv.env) str(k), str(v);
  word(drv.structuredAttrs.has_value());
  if (drv.structuredAttrs) str(*drv.structuredAttrs);
  return h;
}

/// Whether `c`, a derivation as writeDerivation keeps it, is `n` with its output paths filled in: equal in every field but what filling in
/// writes, an input-addressed output's path and its env entry (empty in n, as derivationStrict leaves them).
static bool sameContent(const Derivation &n, const Derivation &c) {
  if (n.name != c.name || n.platform != c.platform || n.builder != c.builder || n.structuredAttrs != c.structuredAttrs ||
      n.args.size() != c.args.size() || !(n.inputSrcs == c.inputSrcs) || n.inputDrvs.size() != c.inputDrvs.size() ||
      n.outputs.size() != c.outputs.size() || n.env.size() != c.env.size())
    return false;
  for (uint32_t i = 0; i < n.args.size(); i++)
    if (n.args[i] != c.args[i]) return false;
  for (size_t i = 0; i < n.inputDrvs.size(); i++) {
    auto &a = n.inputDrvs.begin()[i], &b = c.inputDrvs.begin()[i];
    if (a.first != b.first || !(a.second == b.second)) return false;
  }
  for (size_t i = 0; i < n.outputs.size(); i++) {
    auto &[an, a] = n.outputs.begin()[i];
    auto &[bn, b] = c.outputs.begin()[i];
    if (an != bn) return false;
    if (a.kind == DerivationOutput::Deferred) {
      if (b.kind != DerivationOutput::InputAddressed) return false;
    } else if (a.kind != b.kind || a.path != b.path || a.method != b.method || a.hashAlgo != b.hashAlgo || !(a.hash == b.hash)) {
      return false;
    }
  }
  for (size_t i = 0; i < n.env.size(); i++) {
    auto &[ak, av] = n.env.begin()[i];
    auto &[bk, bv] = c.env.begin()[i];
    if (ak != bk) return false;
    if (av != bv) { // only an output's entry may differ, which filling in wrote
      auto o = n.outputs.find(ak);
      if (o == n.outputs.end() || o->second.kind != DerivationOutput::Deferred || !av.empty()) return false;
    }
  }
  return true;
}

const composite::Text *Store::sameDerivation(const Derivation &drv, uint64_t &fingerprint) const {
  fingerprint = contentFingerprint(drv);
  const ContentRow *r = drvByContent.get(ContentRow{fingerprint, nullptr});
  if (!r) return nullptr;
  return sameContent(drv, r->rec->drv) ? &r->rec->path : nullptr;
}

void Store::rememberDerivation(uint64_t fingerprint, std::string_view drvPath) {
  if (DrvRecord *rec = drvAt(drvPath)) drvByContent.put(ContentRow{fingerprint, rec}); // a fingerprint's first derivation stays
}

const Derivation &Store::readDerivation(std::string_view drvPath) {
  if (DrvRecord *rec = drvAt(drvPath)) return rec->drv;
  composite::Text name = storePathName(drvPath);
  if (name.size() < 4 || name.substr(name.size() - 4) != ".drv")
    throw Error(composite::cat("store path '", baseNameOf(drvPath), "' is not a valid derivation path"));
  composite::Text real = toReal(drvPath);
  if (!pathExists(real)) throw Error(composite::cat("path '", drvPath, "' is not valid"));
  return keepDerivation(drvPath, parseDerivation(readFile(real), composite::Text(name.substr(0, name.size() - 4))), true).drv;
}

struct Store::LaterHashes {
  struct Answer { bool done = false, taken = false; Hash hash; std::exception_ptr error; };
  struct Job { Answer *answer; const Derivation *drv; DrvInputs inputs; };
  nixsys::Lock m;
  nixsys::Signal cv; // a job queued (the hasher waits for one) or an answer made (a dependent waits for it)
  composite::MutableSeries<Job> queue;
  uint32_t head = 0, pending = 0; // pending: queued or being hashed (a store torn down waits for none, as the jobs read its cache)
  /// By path, the derivation record's own bytes (they never move): queued, then done, then taken by the dependent that asks first.  The
  /// trie is the evaluator's alone (under the lock); the hasher writes an answer through its job.  Never freed, as the store's thread may
  /// still wait on them when the process ends.
  composite::Patricia<Answer *> answers;
};

Store::~Store() {
  if (later) {
    nixsys::Held lk(later->m);
    later->cv.waitFor(later->m, [&] { return later->pending == 0; });
  }
  drvs.prefix("", 0, [](const composite::Patricia<DrvRecord *>::Row &r) { delete r.v; }); // no job of the hasher reads one now
}

void Store::hashLater(std::string_view drvPath, DrvInputs &&inputs) {
  if (DrvRecord *rec = drvAt(drvPath); rec && rec->hasModulo) return;
  if (!later) {
    later = new LaterHashes();
    nixsys::Thread::start([L = later] {
      for (;;) {
        LaterHashes::Job job;
        {
          nixsys::Held lk(L->m);
          L->cv.waitFor(L->m, [&] { return L->head < L->queue.size(); });
          job = std::move(L->queue[L->head++]);
          if (L->head == L->queue.size()) { L->queue.clear(); L->head = 0; }
        }
        Hash h;
        std::exception_ptr error;
        try {
          h = job.drv->hashUnparsed(false, &job.inputs);
        } catch (...) {
          error = std::current_exception();
        }
        {
          nixsys::Held lk(L->m);
          job.answer->hash = h;
          job.answer->error = error;
          job.answer->done = true;
          --L->pending;
        }
        L->cv.notifyAll();
      }
    }).detach();
  }
  DrvRecord *rec = drvAt(drvPath); // written just before
  {
    nixsys::Held lk(later->m);
    if (later->answers.find(drvPath.data(), uint32_t(drvPath.size()))) return; // queued already
    auto *a = new LaterHashes::Answer();
    later->answers.set(rec->path.data(), uint32_t(rec->path.size()), a, [rec] { return rec->path.c_str(); });
    later->queue.append({a, &rec->drv, std::move(inputs)});
    ++later->pending;
  }
  later->cv.notifyAll();
}

SortedMap<Hash> Store::hashDerivationModulo(const Derivation &drv, bool maskOutputs, DrvInputs *inputsOut) {
  if (drv.isFixed()) {
    SortedMap<Hash> res;
    for (auto &[name, o] : drv.outputs) {
      composite::Text p = o.fixedPath(settings.storeDir, drv.name, name);
      res[name] = hashString(HashAlgo::SHA256, composite::cat("fixed:out:", o.methodAlgo(), ":",
                                                              o.hash.to_string(HashFormat::Base16, false), ":", p));
    }
    return res;
  }
  for (auto &[n, o] : drv.outputs)
    if (o.kind == DerivationOutput::CAFloating || o.kind == DerivationOutput::Impure)
      throw Error(composite::cat("content-addressed and impure derivations are not supported (derivation '", drv.name, "')"));
  DrvInputs inputs2;
  for (auto &[drvPath, outs] : drv.inputDrvs) {
    DrvRecord *rec = drvAt(drvPath);
    if (!rec || !rec->hasModulo) { // an input's modulo hash: the hasher's, or made here; kept, with its base 16, for every later dependent
      DrvModulo m;
      if (!takeLater(drvPath, m.hashes)) m.hashes = hashDerivationModulo(readDerivation(drvPath), false);
      if (auto e = m.hashes.find(""); e != m.hashes.end()) m.hex = e->second.to_string(HashFormat::Base16, false);
      rec = drvAt(drvPath); // the record of a derivation written here, or the one read just above
      rec->modulo = std::move(m);
      rec->hasModulo = true;
    }
    const DrvModulo &m = rec->modulo;
    if (!m.hex.empty()) {
      inputs2[m.hex].insert(outs.begin(), outs.end());
    } else {
      for (auto &o : outs) {
        auto j = m.hashes.find(o);
        if (j == m.hashes.end()) throw Error(composite::cat("no hash for output '", o, "' of derivation '", drv.name, "'"));
        inputs2[j->second.to_string(HashFormat::Base16, false)].insert("out");
      }
    }
  }
  SortedMap<Hash> res;
  res[""] = drv.hashUnparsed(maskOutputs, &inputs2);
  if (inputsOut) *inputsOut = std::move(inputs2);
  return res;
}

/// The hasher's answer for `drvPath`, if it was asked for one: waited for when it is not made yet, and taken out (a path's hash is asked
/// for once; drvHashes keeps it from then on).
bool Store::takeLater(std::string_view drvPath, SortedMap<Hash> &out) {
  if (!later) return false;
  std::exception_ptr error;
  {
    nixsys::Held lk(later->m);
    LaterHashes::Answer **found = later->answers.find(drvPath.data(), uint32_t(drvPath.size()));
    if (!found || (*found)->taken) return false;
    LaterHashes::Answer *a = *found;
    later->cv.waitFor(later->m, [&] { return a->done; });
    if (a->error) error = a->error;
    else {
      out = SortedMap<Hash>();
      out[""] = a->hash;
    }
    a->taken = true;
  }
  if (error) std::rethrow_exception(error);
  return true;
}

void Store::fillInOutputPaths(Derivation &drv, DrvInputs *inputsOut) {
  auto h = hashDerivationModulo(drv, true, inputsOut);
  for (auto &[name, o] : drv.outputs) {
    if (o.kind != DerivationOutput::Deferred) continue;
    composite::Text p = makeOutputPath(settings.storeDir, name, h.at(""), drv.name);
    o.kind = DerivationOutput::InputAddressed;
    o.path = p.clone();
    auto e = drv.env.find(name);
    if (e == drv.env.end() || e->second.empty()) drv.env[name] = composite::mv(p);
  }
}

SortedSet Store::computeFSClosure(const SortedSet &paths, bool includeOutputs) {
  SortedSet res;
  composite::MutableSeries<composite::Text> todo;
  for (const auto &pth : paths) todo.append(pth.clone());
  while (!todo.empty()) {
    composite::Text p = composite::mv(todo.back());
    todo.pop();
    if (!res.insert(p)) continue;
    if (auto info = queryPathInfo(p)) {
      for (auto &r : info->references) todo.append(r.clone());
    } else if (DrvRecord *rec = drvAt(p)) {
      auto &d = rec->drv;
      for (auto &r : drvReferences(d)) todo.append(r.clone());
    }
    if (includeOutputs && p.size() > 4 && p.substr(p.size() - 4) == ".drv") {
      try {
        const Derivation &d = readDerivation(p);
        for (auto &[n, o] : d.outputs)
          if (!o.path.empty() && isValidPath(o.path)) todo.append(o.path.clone());
      } catch (Error &) {
      }
    }
  }
  return res;
}

//===----------------------------------------------------------------------===//
// Building
//===----------------------------------------------------------------------===//

static SortedSet scanForReferences(const composite::Text &path,
                                               const SortedSet &candidates) {
  SortedMap<composite::Text> byHash;
  for (auto &c : candidates) byHash[storePathHashPart(c)] = c.clone();
  SortedSet found;
  auto scan = [&](auto &self, const composite::Text &p) -> void { // a walk that calls itself: no std::function to hold it
    struct stat st;
    if (lstat(p.c_str(), &st) != 0) return;
    composite::Text data;
    if (S_ISREG(st.st_mode)) data = readFile(p);
    else if (S_ISLNK(st.st_mode)) {
      char buf[PATH_MAX + 1];
      ssize_t n = readlink(p.c_str(), buf, PATH_MAX);
      if (n > 0) data.assign(buf, n);
    } else if (S_ISDIR(st.st_mode)) {
      DIR *d = opendir(p.c_str());
      if (!d) return;
      composite::MutableSeries<composite::Text> names;
      while (auto *e = readdir(d)) {
        std::string_view n = e->d_name;
        if (n != "." && n != "..") names.append(composite::Text(n));
      }
      closedir(d);
      for (auto &n : names) self(self, p + "/" + n);
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
          std::string_view h = data.substr(i + 1 - 32, 32);
          auto it = byHash.find(h);
          if (it != byHash.end()) found.insert(it->second);
        }
      } else {
        run = 0;
      }
    }
  };
  scan(scan, path);
  return found;
}

void Store::ensurePath(std::string_view path) {
  if (isValidPath(path)) return;
  throw Error(composite::cat("path '", path, "' is not valid and cannot be substituted (no binary caches)"));
}

SortedMap<composite::Text> Store::buildDerivation(std::string_view drvPath) {
  SortedSet visiting;
  return realise(drvPath, visiting);
}

SortedMap<composite::Text> Store::realise(std::string_view drvPath,
                                          SortedSet &visiting) {
  if (!visiting.insert(drvPath)) throw Error(composite::cat("cycle in derivation graph at '", drvPath, "'"));
  Derivation drv = readDerivation(drvPath);
  SortedMap<composite::Text> outputs;
  for (auto &[name, o] : drv.outputs) {
    if (o.kind == DerivationOutput::InputAddressed || o.kind == DerivationOutput::CAFixed)
      outputs[name] = o.kind == DerivationOutput::CAFixed && o.path.empty()
                          ? o.fixedPath(settings.storeDir, drv.name, name) : o.path.clone();
    else
      throw Error(composite::cat("cannot build derivation '", drvPath, "': content-addressed/impure outputs are not supported"));
  }
  bool allValid = true;
  for (auto &[n, p] : outputs) allValid &= isValidPath(p);
  if (allValid) {
    visiting.erase(drvPath);
    return outputs;
  }
  if (settings.readOnly) throw Error(composite::cat("cannot build '", drvPath, "' in read-only mode"));
  if (!settings.realRoot.empty())
    throw Error(composite::cat("cannot build '", drvPath, "': the store directory '", settings.storeDir,
                               "' is not physically accessible (chroot store at '", settings.realRoot,
                               "'); use --store-dir with a writable directory to build"));
  for (auto &[inDrv, outs] : drv.inputDrvs) {
    auto res = realise(inDrv, visiting);
    for (auto &o : outs)
      if (!res.count(o)) throw Error(composite::cat("derivation '", inDrv, "' does not have output '", o, "'"));
  }
  for (auto &src : drv.inputSrcs) ensurePath(src);

  log(composite::cat("building '", drvPath, "'..."));
  if (drv.builder == "builtin:fetchurl") builtinFetchurl(drv, outputs);
  else runBuilder(drvPath, drv, outputs);

  // Post-process outputs.
  SortedSet candidates;
  {
    SortedSet inputs(drv.inputSrcs.begin(), drv.inputSrcs.end());
    for (auto &[inDrv, outs] : drv.inputDrvs) {
      Derivation d = readDerivation(inDrv);
      for (auto &o : outs) {
        auto &out = d.outputs.at(o);
        inputs.insert(out.kind == DerivationOutput::CAFixed && out.path.empty()
                          ? out.fixedPath(settings.storeDir, d.name, o) : out.path.clone());
      }
    }
    candidates = computeFSClosure(inputs);
    for (auto &[n, p] : outputs) candidates.insert(p);
  }
  for (auto &[name, path] : outputs) {
    composite::Text real = toReal(path);
    if (!pathExists(real))
      throw Error(composite::cat("builder for '", drvPath, "' failed to produce output path for output '", name,
                                 "' at '", path, "'"));
    canonicalisePathMetaData(real);
    auto &o = drv.outputs.at(name);
    if (o.kind == DerivationOutput::CAFixed) {
      Hash got = o.method == FileIngestionMethod::NixArchive ? hashPath(real, nullptr, o.hash.algo).a
                                                             : hashFile(o.hash.algo, real);
      if (!(got == o.hash)) {
        deletePathRecursive(real);
        throw Error(composite::cat("hash mismatch in fixed-output derivation '", drvPath, "':\n         specified: ",
                                   o.hash.to_string(HashFormat::SRI, true), "\n            got:    ",
                                   got.to_string(HashFormat::SRI, true)));
      }
    }
    PathInfo info;
    info.path = path.clone();
    auto [nh, ns] = hashPath(real);
    info.narHash = nh;
    info.narSize = ns;
    info.references = o.kind == DerivationOutput::CAFixed ? SortedSet{}
                                                         : scanForReferences(real, candidates);
    info.deriver = composite::Text(drvPath);
    if (o.kind == DerivationOutput::CAFixed)
      info.ca = composite::cat(o.method == FileIngestionMethod::NixArchive ? "fixed:r:" : "fixed:",
                               o.hash.to_string(HashFormat::Nix32, true));
    registerValidPath(info);
  }
  visiting.erase(drvPath);
  return outputs;
}


void Store::runBuilder(std::string_view drvPath, const Derivation &drv,
                       const SortedMap<composite::Text> &outputs) {
  const char *tmp = getenv("TMPDIR");
  composite::Text tmpBase = tmp && *tmp ? tmp : "/tmp";
  composite::Text tmpl = tmpBase + "/nix-build-" + drv.name + "-XXXXXX";
  composite::MutableSeries<char> buf;
  for (char ch : tmpl) buf.append(ch);
  buf.append('\0');
  if (!mkdtemp(buf.data())) throw Error(composite::cat("creating build directory: ", strerror(errno)));
  composite::Text top = buf.data();

  SortedMap<composite::Text> env;
  env["PATH"] = "/path-not-set";
  env["HOME"] = "/homeless-shelter";
  env["NIX_STORE"] = settings.storeDir.clone();
  env["NIX_BUILD_CORES"] = composite::str(settings.cores);
  env["NIX_BUILD_TOP"] = top.clone();
  env["TMPDIR"] = top.clone();
  env["TEMPDIR"] = top.clone();
  env["TMP"] = top.clone();
  env["TEMP"] = top.clone();
  env["PWD"] = top.clone();
  env["NIX_LOG_FD"] = "2";
  env["TERM"] = "xterm-256color";
  bool fixed = drv.isFixed();
  if (fixed) {
    auto it = drv.env.find("impureEnvVars");
    if (it != drv.env.end()) {
      composite::eachWord(it->second.data(), uint32_t(it->second.size()), [&](const char *p, uint32_t n) {
        composite::Text v(p, n);
        if (const char *val = getenv(v.c_str())) env[v] = val;
      });
    }
  }
  // Output placeholders (builtins.placeholder) are rewritten to the real
  // output paths in the environment, arguments and structured attributes.
  SortedMap<composite::Text> rewrites;
  for (auto &[n, p] : outputs) rewrites[hashPlaceholder(n)] = p.clone();
  auto rewrite = [&](std::string_view in) {
    composite::Text s(in);
    for (auto &[from, to] : rewrites) {
      size_t pos = 0;
      while ((pos = s.find(from, pos)) != composite::npos) {
        s.erase(pos, from.size());
        s.insert(pos, to);
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

  composite::MutableSeries<composite::Text> envStrs;
  for (auto &[k, v] : env) envStrs.append(composite::cat(k, "=", v));
  composite::MutableSeries<char *> envp;
  for (auto &s : envStrs) envp.append(const_cast<char *>(s.c_str()));
  envp.append(nullptr);
  composite::MutableSeries<char *> argv;
  composite::Text builderBase = baseNameOf(drv.builder);
  argv.append(const_cast<char *>(builderBase.c_str()));
  composite::MutableSeries<composite::Text> args;
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
    composite::Text why = WIFEXITED(status) ? composite::cat("failed with exit code ", WEXITSTATUS(status))
                                            : composite::cat("was killed by signal ", WTERMSIG(status));
    if (settings.keepFailed) log(composite::cat("note: keeping build directory '", top, "'"));
    else deletePathRecursive(top);
    throw Error(composite::cat("builder for '", drvPath, "' ", why));
  }
  deletePathRecursive(top);
}

void Store::builtinFetchurl(const Derivation &drv, const SortedMap<composite::Text> &outputs) {
  auto get = [&](std::string_view k) {
    auto it = drv.env.find(k);
    return it == drv.env.end() ? std::string_view() : std::string_view(it->second);
  };
  composite::Text url(get("url"));
  if (url.empty()) {
    std::string_view urls = get("urls");
    composite::eachWord(urls.data(), uint32_t(urls.size()), [&](const char *p, uint32_t n) { // the first
      if (url.empty()) url.assign(p, n);
    });
  }
  if (url.empty()) throw Error("builtin:fetchurl: no URL specified");
  const composite::Text &out = outputs.at("out");
  composite::Text real = toReal(out);
  createDirs(toReal(settings.storeDir));
  composite::Text tmp = real + ".tmp";
  composite::Text curlOut;
  int rc = runProgram("curl", {"-fsSL", "--retry", "3", "-o", tmp.clone(), url.clone()}, &curlOut);
  if (rc != 0) {
    unlink(tmp.c_str());
    throw Error(composite::cat("unable to download '", url, "': curl exited with code ", rc));
  }
  if (get("unpack") == "1") {
    composite::Text nar = readFile(tmp);
    unlink(tmp.c_str());
    restorePath(real, nar);
  } else {
    rename(tmp.c_str(), real.c_str());
    if (get("executable") == "1") chmod(real.c_str(), 0755);
  }
}

void Store::addPermRoot(std::string_view storePath, std::string_view link) {
  nixsys::CStr linkC(link);
  unlink(linkC);
  if (symlink(toReal(storePath).c_str(), linkC) != 0)
    throw Error(composite::cat("creating symlink '", link, "': ", strerror(errno)));
  composite::Text rootDir = settings.stateDir + "/gcroots/auto";
  createDirs(rootDir);
  char absBuf[PATH_MAX];
  composite::Text abs(link);
  if (!link.starts_with('/') && getcwd(absBuf, sizeof absBuf)) abs = composite::cat(absBuf, "/", link);
  composite::Text rootLink = rootDir + "/" + hashString(HashAlgo::SHA256, abs).to_string(HashFormat::Nix32, false).substr(0, 32);
  unlink(rootLink.c_str());
  symlink(abs.c_str(), rootLink.c_str());
}

bool Store::deletePath(std::string_view path) {
  if (!queryReferrers(path).empty()) return false;
  deletePathRecursive(toReal(path));
  unlink(infoFile(path).c_str());
  return true;
}

bool Store::collectGarbage(bool dryRun, composite::MutableSeries<composite::Text> &deleted) {
  SortedSet roots;
  auto scanRoots = [&](auto &self, const composite::Text &dir) -> void {
    DIR *d = opendir(dir.c_str());
    if (!d) return;
    composite::MutableSeries<composite::Text> names;
    while (auto *e = readdir(d)) {
      std::string_view n = e->d_name;
      if (n != "." && n != "..") names.append(composite::Text(n));
    }
    closedir(d);
    for (auto &n : names) {
      composite::Text p = dir + "/" + n;
      struct stat st;
      if (lstat(p.c_str(), &st) != 0) continue;
      if (S_ISDIR(st.st_mode)) { self(self, p); continue; }
      if (!S_ISLNK(st.st_mode)) continue;
      char buf[PATH_MAX + 1];
      ssize_t len = readlink(p.c_str(), buf, PATH_MAX);
      if (len <= 0) continue;
      composite::Text target(buf, size_t(len));
      // Indirect root: a symlink to a symlink into the store.
      char buf2[PATH_MAX + 1];
      ssize_t len2 = readlink(target.c_str(), buf2, PATH_MAX);
      if (len2 > 0) target.assign(buf2, len2);
      const composite::Text &real = settings.realRoot;
      if (!real.empty() && target.rfind(real, 0) == 0) target = composite::Text(target.substr(real.size()));
      if (isInStore(settings.storeDir, target)) roots.insert(toStorePath(settings.storeDir, target));
      else if (len2 <= 0 && !pathExists(target)) unlink(p.c_str());
    }
  };
  scanRoots(scanRoots, settings.stateDir + "/gcroots");
  auto live = computeFSClosure(roots, true);
  composite::MutableSeries<composite::Text> dead;
  for (auto &p : allValidPaths())
    if (!live.count(p)) dead.append(composite::mv(p));
  // Delete in referrer-safe order: repeat until no progress.
  bool progress = true;
  SortedSet remaining(dead.begin(), dead.end());
  while (progress && !remaining.empty()) {
    progress = false;
    SortedSet kept, gone; // still referenced by another dead path (the next round's); deleted in this round (no longer a referrer)
    for (const composite::Text &p : remaining) {
      bool referenced = false;
      for (const composite::Text &q : remaining) {
        if (q == p || gone.contains(q)) continue;
        if (auto info = queryPathInfo(q))
          if (info->references.count(p)) { referenced = true; break; }
      }
      if (referenced) { kept.insert(p); continue; }
      if (!dryRun) {
        deletePathRecursive(toReal(p));
        unlink(infoFile(p).c_str());
      }
      deleted.append(p.clone());
      gone.insert(p);
      progress = true;
    }
    remaining = std::move(kept);
  }
  return true;
}

} // namespace nixstore
