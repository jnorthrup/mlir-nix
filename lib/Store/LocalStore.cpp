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
#include "Composite/Text.h"
#include "Nix/Numbers.h"
#include "Nix/Os.h"
#include "Nix/Store.h"
#include <errno.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <exception>
#include <unistd.h>

namespace nixstore {

// The store's graph and content algorithms are lowered/nixstore/StoreGraph.mlir (built into NixStore by lib/CMakeLists.txt): the set
// algebra, computeFSClosure's worklist, collectGarbage's rounds, contentFingerprint (xxh3 too) and sameContent, and
// queryPathInfo's lines; the builder's are BuilderOps.mlir, the index of the info files StoreIndex.mlir.  What stays here hands the sorted sets over as windows and answers the callbacks, which read and write the store.
namespace {
struct GWin { const char *p; int64_t n; };
template <class C> composite::MutableSeries<GWin> wins(const C &texts) {
  composite::MutableSeries<GWin> w;
  for (const composite::Text &t : texts) w.append({t.data(), int64_t(t.size())});
  return w;
}
} // namespace

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

// The store's index is lowered/nixstore/StoreIndex.mlir: `<stateDir>/info.trie`, the info directory's entries as a trie keyed by the hash
// part (and the references as a second relation, by the reference), derived from the info files, which stay as they are and are what an
// older mlnix reads and writes.  Its calls take a path's info file; it answers only for the directory as it is when asked.
extern "C" int64_t nixstore_ts_infolines(const char *p, int64_t n, int64_t *recs); // {key 0-4, value offset, value length}, in line order
extern "C" int64_t nixsi_info(const char *infoFile, const char **text); // the path's info text as the index holds it, or -1: the file is read
extern "C" int64_t nixsi_register(const char *infoFile, const char *text, int64_t n); // the file written through `infoFile.tmp`: 0, 1 not made, 2 not written
extern "C" void nixsi_unlink(const char *infoFile);
/// Every entry's name in byte order, or (referring) those whose info may refer to the path, each given to nixsi_name.
extern "C" void nixsi_names(const char *infoFile, int64_t referring, Store *st, composite::MutableSeries<composite::Text> *res);
extern "C" void nixsi_name(Store *st, composite::MutableSeries<composite::Text> *res, const char *p, int64_t n) { // a valid path when its store object is there
  if (composite::Text path = st->settings.storeDir + "/" + std::string_view(p, size_t(n)); pathExists(st->toReal(path))) res->append(composite::mv(path));
}
composite::Maybe<PathInfo> Store::queryPathInfo(std::string_view path) {
  composite::Text f = infoFile(path), text;
  const char *tp = nullptr;
  int64_t tn = nixsi_info(f.c_str(), &tp);
  if ((tn < 0 && !pathExists(f)) || !pathExists(toReal(path))) return nullptr;
  if (tn < 0) text = readFile(f), tp = text.data(), tn = text.size();
  PathInfo info;
  info.path = composite::Text(path);
  composite::MutableSeries<int64_t> r(3 * (size_t(tn) / 2 + 2));
  for (uint32_t i = 0, k = uint32_t(nixstore_ts_infolines(tp, tn, r.data())); i < k; i++) {
    std::string_view v(tp + r[3 * i + 1], size_t(r[3 * i + 2]));
    if (r[3 * i] == 0) info.narHash = parseHash(v, nullptr);
    else if (r[3 * i] == 1) info.narSize = nixsys::stoValue("stoull", nixsys::readUnsigned(v));
    else if (r[3 * i] == 2) info.references.insert(v);
    else if (r[3 * i] == 3) info.deriver = composite::Text(v);
    else info.ca = composite::Text(v);
  }
  return info;
}

// The info file's lines (BuilderOps.mlir, one combine drained once); the room is the Text's.
extern "C" char *nixbo_room(composite::Text *t, uint64_t n) { t->resize(n); return t->begin(); }
extern "C" int64_t nixstore_ts_infotext(composite::Text *t, const char *, int64_t, const char *, int64_t, uint64_t narSize,
                                        const composite::Text *refs, int64_t, const char *, int64_t, const char *, int64_t);
void Store::registerValidPath(const PathInfo &info) {
  createDirs(settings.stateDir + "/info");
  composite::Text s, h = info.narHash.to_string(HashFormat::Nix32, true);
  nixstore_ts_infotext(&s, info.path.data(), info.path.size(), h.data(), h.size(), info.narSize, info.references.begin(),
                       info.references.size(), info.deriver.data(), info.deriver.size(), info.ca.data(), info.ca.size());
  composite::Text f = infoFile(info.path); // written through `f.tmp` and renamed, and the index told (StoreIndex.mlir)
  if (int64_t rc = nixsi_register(f.c_str(), s.data(), s.size()))
    throw Error(composite::cat(rc == 1 ? "creating" : "writing", " file '", f, ".tmp': ", strerror(errno)));
}

composite::MutableSeries<composite::Text> Store::allValidPaths(std::string_view referringTo) {
  composite::MutableSeries<composite::Text> res;
  nixsi_names(infoFile(referringTo).c_str(), !referringTo.empty(), this, &res);
  return res;
}

SortedSet Store::queryReferrers(std::string_view path) {
  SortedSet res;
  for (auto &p : allValidPaths(path))
    if (auto info = queryPathInfo(p))
      if (info->references.count(path)) res.insert(p);
  return res;
}

// The build and add path is lowered/nixstore/StoreWalks.mlir and the modules beside it (their messages StoreWords.mlir, the system's words
// StoreBuildDarwin.mlir.in / StoreBuildLinux.mlir.in).  A lowered entry returns 1 with its error kept here, and what calls it throws it,
// once: no exception crosses the entry's frames, which hold rooms of their own, so the store's callbacks keep what they catch too.
namespace {
struct Sb {
  Store *st = nullptr;
  const PathFilter *filter = nullptr;
  std::exception_ptr err;
  composite::Text file; // the file a walk read last
  template <class F> int64_t guard(F f) { try { f(); return 0; } catch (...) { err = std::current_exception(); return 1; } }
  void done(int64_t failed) { if (failed) std::rethrow_exception(err); }
};
} // namespace
static_assert(offsetof(StoreSettings, realRoot) == 16 && offsetof(StoreSettings, stateDir) == 32, "the settings a lowered entry reads");
extern "C" {
int64_t nixsb_canon(Sb *c, const char *p, int64_t n);
int64_t nixsb_copy(Sb *c, const char *from, int64_t fn, const char *to, int64_t tn, int64_t filtered);
int64_t nixsb_refs(Sb *c, const char *p, int64_t n, const composite::Text *candidates, int64_t nc, SortedSet *refs);
void nixsb_roots(const StoreSettings *s, SortedSet *roots);
void nixsb_fail(Sb *c, int64_t kind, const char *m, int64_t n) { // kind 1: SortedMap::at's
  composite::Text t(m, size_t(n));
  c->err = kind ? std::make_exception_ptr(std::out_of_range(t.c_str())) : std::make_exception_ptr(Error(t));
}
void nixsb_log(Sb *c, const char *m, int64_t n) { c->st->log(std::string_view(m, size_t(n))); }
int64_t nixsb_copyfile(Sb *c, const char *f, int64_t fn, const char *t, int64_t tn, int64_t mode) {
  return c->guard([&] { writeFile(std::string_view(t, size_t(tn)), readFile(std::string_view(f, size_t(fn))), mode_t(mode)); });
}
int64_t nixsb_keep(Sb *c, const char *p, int64_t n) { // 1 kept, 0 not, -1 the filter threw
  int64_t k = -1;
  c->guard([&] { k = (*c->filter)(std::string_view(p, size_t(n)), {}); });
  return k;
}
const char *nixsb_read(Sb *c, const char *p, int64_t n, int64_t *len) {
  *len = c->guard([&] { c->file = readFile(std::string_view(p, size_t(n))); }) ? -1 : int64_t(c->file.size());
  return c->file.data();
}
void nixsb_ref(SortedSet *s, const char *p, int64_t n) { s->insert(std::string_view(p, size_t(n))); }
int64_t nixsb_exists(const char *p, int64_t n) { return pathExists(std::string_view(p, size_t(n))); }
}

/// Make a freshly created store object read-only with mtime 1, as Nix does.
static void canonicalisePathMetaData(const composite::Text &path) {
  Sb c;
  c.done(nixsb_canon(&c, path.data(), path.size()));
}

static void copyRecursive(const composite::Text &from, const composite::Text &to, const PathFilter &filter) {
  Sb c;
  c.filter = &filter;
  c.done(nixsb_copy(&c, from.data(), from.size(), to.data(), to.size(), bool(filter)));
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

extern "C" int64_t nixstore_ts_union(const GWin *a, int64_t na, const GWin *b, int64_t nb, GWin *out);
/// A derivation's references: its input sources and input derivations, both sorted, merged (a path in both once).
static composite::MutableSeries<GWin> drvRefs(const Derivation &drv) {
  composite::MutableSeries<GWin> srcs = wins(drv.inputSrcs), ins, out(srcs.size() + drv.inputDrvs.size());
  for (auto &[p, o] : drv.inputDrvs) ins.append({p.data(), int64_t(p.size())});
  out.resize(size_t(nixstore_ts_union(srcs.data(), srcs.size(), ins.data(), ins.size(), out.data())));
  return out;
}
static SortedSet drvReferences(const Derivation &drv) {
  SortedSet refs;
  for (GWin r : drvRefs(drv)) refs.rows.append(composite::Text(r.p, size_t(r.n)));
  return refs;
}

composite::Text Store::writeDerivation(Derivation &&drv) {
  // The text's hash names the path; a store that writes keeps the text too, made once, and a read-only one only feeds the hash with it.
  composite::Text text = settings.readOnly ? composite::Text() : drv.unparse(false);
  // The path's type is `text` and its references (drvRefs' windows), as makeTextPath would join drvReferences' set, without building the set.
  composite::Text type = "text";
  for (GWin r : drvRefs(drv)) type.put(':').put(r.p, size_t(r.n));
  composite::Text path = makeStorePath(settings.storeDir, type, settings.readOnly ? drv.hashUnparsed(false) : hashString(HashAlgo::SHA256, text),
                                       drv.name + ".drv");
  // The text first: a kept derivation's path is valid (isValidPath), and addTextToStore writes no valid path.
  if (!settings.readOnly) addTextToStore(drv.name + ".drv", text, drvReferences(drv));
  keepDerivation(path, std::move(drv), false); // a path names its text: the first is kept, never rewritten
  return path;
}

/// A derivation as tokens {tag, a, b} in contentFingerprint's order, which StoreGraph.mlir folds into the fingerprint (each string through
/// xxh3, with the counts that delimit its lists) and walks in step with another's for sameContent: whether `c`, a derivation as
/// writeDerivation keeps it, is `n` with its output paths filled in (an input-addressed output's path and its env entry, empty in n).
/// Tags: 0 word, 1 string, 2 word not fingerprinted, 3 Hash*, 4 an output's kind, 5 an env value, 6 an output's path, 7 the outputs' count.
namespace {
struct GTok { int64_t tag, a, b; };
}
extern "C" uint64_t nixstore_ts_fingerprint(const GTok *t, int64_t n);
extern "C" int64_t nixstore_ts_samecontent(const GTok *n, int64_t nn, const GTok *c, int64_t nc);
static composite::MutableSeries<GTok> drvTokens(const Derivation &d) {
  composite::MutableSeries<GTok> t;
  auto w = [&](int64_t tag, uint64_t v) { t.append({tag, int64_t(v), 0}); };
  auto s = [&](int64_t tag, std::string_view v) { t.append({tag, int64_t(uintptr_t(v.data())), int64_t(v.size())}); };
  auto all = [&](const auto &xs) { w(0, xs.size()); for (const composite::Text &x : xs) s(1, x); };
  s(1, d.name), s(1, d.platform), s(1, d.builder), all(d.args), all(d.inputSrcs), w(0, d.inputDrvs.size());
  for (auto &[p, outs] : d.inputDrvs) s(1, p), all(outs);
  w(7, d.outputs.size());
  for (auto &[n, o] : d.outputs) s(1, n), w(4, o.kind), s(6, o.path), w(2, uint64_t(o.method)), w(2, uint64_t(o.hashAlgo)), w(3, uintptr_t(&o.hash));
  w(0, d.env.size());
  for (auto &[k, v] : d.env) s(1, k), s(5, v);
  w(0, d.structuredAttrs.has_value());
  if (d.structuredAttrs) s(1, *d.structuredAttrs);
  return t;
}

const composite::Text *Store::sameDerivation(const Derivation &drv, uint64_t &fingerprint) const {
  composite::MutableSeries<GTok> t = drvTokens(drv);
  fingerprint = nixstore_ts_fingerprint(t.data(), t.size());
  const ContentRow *r = drvByContent.get(ContentRow{fingerprint, nullptr});
  if (!r) return nullptr;
  composite::MutableSeries<GTok> c = drvTokens(r->rec->drv);
  return nixstore_ts_samecontent(t.data(), t.size(), c.data(), c.size()) ? &r->rec->path : nullptr;
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

// computeFSClosure's walk is nixstore_ts_closure (the worklist and the visited set, room 0, sorted), collectGarbage's past the roots
// nixstore_ts_gc (the dead paths deleted in referrer-safe rounds).  The callbacks read a path's references or a derivation's valid
// outputs, kept here as long as the walk, and delete a path.
namespace {
struct Walk {
  Store *st;
  composite::MutableSeries<GWin> room[2]; // the visited windows, the walk's frames
  composite::MutableSeries<SortedSet> sets;
  composite::MutableSeries<composite::MutableSeries<GWin>> got;
  bool dryRun = false;
  composite::MutableSeries<composite::Text> *deleted = nullptr;
};
} // namespace
extern "C" {
int64_t nixstore_ts_closure(Walk *c, const GWin *seeds, int64_t n, int64_t includeOutputs);
int64_t nixstore_ts_gc(Walk *c, const GWin *valid, int64_t nv, const GWin *live, int64_t nl);
GWin *nixstore_walk_room(Walk *c, int64_t which, int64_t need) {
  if (c->room[which].size() < need) c->room[which].resize(size_t(need) * 2);
  return c->room[which].data();
}
/// which 0: the path's info's references, else a cached derivation's; 1: a derivation's valid outputs; 2: the info's references.
const GWin *nixstore_walk_next(Walk *c, const char *p, int64_t n, int64_t which, int64_t *count) {
  std::string_view path(p, size_t(n));
  composite::MutableSeries<GWin> &w = c->got[c->got.append(composite::MutableSeries<GWin>())];
  if (which == 3) { // gc_fast's first pass: a read that fails is count -1; the GC then keeps the rounds that read on demand
    composite::Maybe<PathInfo> info;
    try { info = c->st->queryPathInfo(path); } catch (...) { *count = -1; return nullptr; }
    if (info) w = wins(c->sets[c->sets.append(composite::mv(info->references))]);
  } else if (which == 1) {
    try {
      for (auto &[name, o] : c->st->readDerivation(path).outputs)
        if (!o.path.empty() && c->st->isValidPath(o.path)) w.append({o.path.data(), int64_t(o.path.size())});
    } catch (Error &) {
    }
  } else if (auto info = c->st->queryPathInfo(path)) {
    w = wins(c->sets[c->sets.append(composite::mv(info->references))]);
  } else if (Store::DrvRecord *rec = which == 0 ? c->st->drvAt(path) : nullptr) {
    w = drvRefs(rec->drv);
  }
  *count = w.size();
  return w.data();
}
void nixstore_walk_gone(Walk *c, const char *p, int64_t n) {
  std::string_view path(p, size_t(n));
  if (!c->dryRun) deletePathRecursive(c->st->toReal(path)), unlink(c->st->infoFile(path).c_str());
  c->deleted->append(composite::Text(path));
}
}

SortedSet Store::computeFSClosure(const SortedSet &paths, bool includeOutputs) {
  Walk c{this};
  int64_t n = nixstore_ts_closure(&c, wins(paths).data(), paths.size(), includeOutputs);
  SortedSet res;
  for (uint32_t i = 0; i < n; i++) res.rows.append(composite::Text(c.room[0][i].p, size_t(c.room[0][i].n)));
  return res;
}

//===----------------------------------------------------------------------===//
// Building
//===----------------------------------------------------------------------===//

// The scan of an output's bytes for its references is StoreWalks.mlir's nixsb_refs: the candidates' hash parts sorted once (BuilderOps.mlir's
// refindex), the tree walked, each file's 32-digit nix32 windows bisected into them (refscan), the candidates found put in their order.
static SortedSet scanForReferences(const composite::Text &path, const SortedSet &candidates) {
  Sb c;
  SortedSet refs;
  c.done(nixsb_refs(&c, path.data(), path.size(), candidates.rows.data(), candidates.size(), &refs));
  return refs;
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


extern "C" int64_t nixstore_ts_cstrs(composite::Text *t, const void *rows, int64_t n, int64_t pairs, char **ptrs);
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
  // In a chroot on a Mac with SIP on, dyld has no shared cache in the shared region (the kernel maps only SIP-protected
  // cache files, and a chroot's is a copy), so each process maps the copy itself, which DYLD_SHARED_REGION=private asks
  // for (utils/mlnixos-darwin/mlnixos-chroot.c).  A builder without it could not load libSystem.
  if (const char *dsr = getenv("DYLD_SHARED_REGION")) env["DYLD_SHARED_REGION"] = dsr;
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
  for (auto &[k, v] : drv.env) env[k] = rewritePlaceholders(v, rewrites);
  if (drv.structuredAttrs) {
    auto [json, sh] = structuredAttrsFiles(*drv.structuredAttrs, outputs, rewrites);
    writeFile(top + "/.attrs.json", json);
    writeFile(top + "/.attrs.sh", sh);
    env["NIX_ATTRS_JSON_FILE"] = top + "/.attrs.json";
    env["NIX_ATTRS_SH_FILE"] = top + "/.attrs.sh";
  }

  composite::MutableSeries<composite::Text> args; // argv: the builder's base name, then the arguments, rewritten
  args.append(baseNameOf(drv.builder));
  for (auto &a : drv.args) args.append(rewritePlaceholders(a, rewrites));
  composite::Text envBlock, argBlock; // the strings, `k=v` and the arguments, each NUL-ended in one room (BuilderOps.mlir)
  composite::MutableSeries<char *> envp(env.size() + 1), argv(args.size() + 1);
  nixstore_ts_cstrs(&envBlock, env.rows.data(), env.size(), 1, envp.data());
  nixstore_ts_cstrs(&argBlock, args.data(), args.size(), 0, argv.data());

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
  nixsi_unlink(infoFile(path).c_str());
  return true;
}

bool Store::collectGarbage(bool dryRun, composite::MutableSeries<composite::Text> &deleted) {
  SortedSet roots; // the store paths the links under <stateDir>/gcroots lead to (StoreWalks.mlir)
  nixsb_roots(&settings, &roots);
  composite::MutableSeries<composite::Text> valid = allValidPaths(); // before the closure: the list makes the index hold the directory, and the closure's infos are read from it
  SortedSet live = computeFSClosure(roots, true);
  Walk g{this, {}, {}, {}, dryRun, &deleted};
  nixstore_ts_gc(&g, wins(valid).data(), valid.size(), wins(live).data(), live.size());
  return true;
}

} // namespace nixstore
