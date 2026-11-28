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
#include <sys/stat.h>
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

// The build and add path is lowered/nixstore (StoreAdd.mlir: the paths added and the derivations realised; StoreRun.mlir: the builders;
// StoreWalks.mlir: the trees; their messages StoreWords.mlir, the system's words StoreBuildDarwin.mlir.in / StoreBuildLinux.mlir.in).  A
// lowered entry returns 1 with its error kept here, and what calls it throws it, once: no exception crosses the entry's frames, which hold
// rooms of their own, so the store's callbacks keep what they catch too.
namespace {
struct Sb {
  Store *st = nullptr;
  const PathFilter *filter = nullptr;
  composite::Text block[2];            // the rooms of a builder's environment and arguments (BuilderOps.mlir's cstrs)
  SortedSet set[3];                    // realise's inputs, their closure with the outputs, an output's references
  SortedMap<composite::Text> rewrites; // the outputs' placeholders and the paths they stand for
  composite::MutableSeries<composite::Text> texts; // what a callback made and the entry still reads
  composite::MutableSeries<SortedMap<composite::Text>> maps; // the outputs of the input derivations realised
  composite::Text file;                // the file read last
  std::exception_ptr err;
  explicit Sb(Store *s = nullptr, const PathFilter *f = nullptr) : st(s), filter(f) {}
  template <class F> int64_t guard(F f) { try { f(); return 0; } catch (...) { err = std::current_exception(); return 1; } }
  void done(int64_t failed) { if (failed) std::rethrow_exception(err); }
  const char *keep(composite::Text t, int64_t *len) { // kept as long as the call
    composite::Text &k = texts[texts.append(composite::mv(t))];
    *len = k.size();
    return k.data();
  }
};
} // namespace
static_assert(offsetof(Sb, block) == 16 && offsetof(Sb, set) == 48 && sizeof(SortedSet) == 16 && offsetof(Store, settings) == 16 && offsetof(StoreSettings, realRoot) == 16 &&
                  offsetof(StoreSettings, stateDir) == 32 && offsetof(StoreSettings, readOnly) == 48 && offsetof(StoreSettings, cores) == 52 &&
                  offsetof(StoreSettings, keepFailed) == 56 && sizeof(composite::MutableSeries<composite::Text>) == 16 && sizeof(SortedMap<composite::Text>::Row) == 32 &&
                  offsetof(Derivation, outputs) == 16 && offsetof(Derivation, inputDrvs) == 32 && offsetof(Derivation, inputSrcs) == 48 && sizeof(DrvInputs::Row) == 32 &&
                  sizeof(SortedMap<DerivationOutput>::Row) == 120 && offsetof(DerivationOutput, kind) == 0 && offsetof(DerivationOutput, path) == 8 &&
                  offsetof(DerivationOutput, method) == 24 && offsetof(DerivationOutput, hash) == 32 && sizeof(Hash) <= 72 && offsetof(Derivation, builder) == 80 &&
                  offsetof(Derivation, args) == 96 && offsetof(Derivation, env) == 112 && offsetof(Derivation, structuredAttrs) == 128 &&
                  offsetof(composite::Maybe<composite::Text>, v) == 8,
              "the places a lowered entry reads");
extern "C" {
int64_t nixsb_add(Sb *c, const char *name, int64_t nn, const char *src, int64_t sn, int64_t method, int64_t algo, int64_t filtered, const SortedSet *refs, const Hash *expected,
                  composite::Text *dst);
int64_t nixsb_root(Sb *c, const char *storePath, int64_t sn, const char *link, int64_t ln);
int64_t nixsb_realise(Sb *c, const char *drvPath, int64_t dn, SortedSet *visiting, SortedMap<composite::Text> *outputs);
void nixsb_roots(const StoreSettings *s, SortedSet *roots);
int64_t nixsb_run(Sb *c, const char *prog, int64_t pn, const composite::Text *args, int64_t na, composite::Text *out, const composite::Text *input, const char *cwd, int64_t cn);
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
int64_t nixsb_set(SortedSet *s, int64_t op, const char *p, int64_t n) { // 0 put in: whether it was new; 3 put in; 1 taken out; 2 emptied
  std::string_view k(p, size_t(n));
  if (op == 2) return s->rows.clear(), 0;
  if (op == 1) return s->erase(k);
  return s->insert(k) && op == 0;
}
int64_t nixsb_exists(const char *p, int64_t n) { return pathExists(std::string_view(p, size_t(n))); }
void nixsb_put(composite::Text *t, const char *p, int64_t n) { t->put(p, size_t(n)); }
void nixsb_placeholder(Sb *c, const char *o, int64_t on, const char *p, int64_t pn) {
  c->rewrites[hashPlaceholder(std::string_view(o, size_t(on)))] = composite::Text(p, size_t(pn));
}
const char *nixsb_rewrite(Sb *c, const char *p, int64_t n, int64_t *len) { return c->keep(rewritePlaceholders(std::string_view(p, size_t(n)), c->rewrites), len); }
int64_t nixsb_sattrs(Sb *c, const char *j, int64_t jn, const SortedMap<composite::Text> *outputs, int64_t *w) { // .attrs.json, .attrs.sh: bytes and count each
  return c->guard([&] {
    auto [json, sh] = structuredAttrsFiles(std::string_view(j, size_t(jn)), *outputs, c->rewrites);
    w[0] = int64_t(intptr_t(c->keep(composite::mv(json), w + 1))), w[2] = int64_t(intptr_t(c->keep(composite::mv(sh), w + 3)));
  });
}
int64_t nixsb_write(Sb *c, const char *p, int64_t n, const char *d, int64_t dn, int64_t mode) {
  return c->guard([&] { writeFile(std::string_view(p, size_t(n)), std::string_view(d, size_t(dn)), mode_t(mode)); });
}
int64_t nixsb_delete(Sb *c, const char *p, int64_t n) { return c->guard([&] { deletePathRecursive(std::string_view(p, size_t(n))); }); }
int64_t nixsb_mkdirs(Sb *c, const char *p, int64_t n) { return c->guard([&] { createDirs(std::string_view(p, size_t(n))); }); }
int64_t nixsb_restore(Sb *c, const char *p, int64_t n, const char *nar, int64_t nn) {
  return c->guard([&] { restorePath(std::string_view(p, size_t(n)), std::string_view(nar, size_t(nn))); });
}
/// how 0: a file's hash; 1: a tree's NAR's, under the call's filter; 2: a file's bytes', as text (SHA-256); 3: these bytes'; 4: a tree's NAR's.
int64_t nixsb_hash(Sb *c, int64_t how, int64_t algo, const char *p, int64_t n, Hash *h, uint64_t *size) {
  return c->guard([&] {
    std::string_view v(p, size_t(n));
    if (how == 0) *h = hashFile(HashAlgo(algo), v);
    else if (how == 2) *h = hashString(HashAlgo::SHA256, readFile(v));
    else if (how == 3) *h = hashString(HashAlgo(algo), v);
    else {
      auto r = how == 1 ? hashPath(v, *c->filter, HashAlgo(algo)) : hashPath(v, nullptr, HashAlgo(algo));
      *h = r.a, *size = r.b;
    }
  });
}
const char *nixsb_hashtext(Sb *c, const Hash *h, int64_t format, int64_t withAlgo, int64_t *len) { return c->keep(h->to_string(HashFormat(format), withAlgo), len); }
const char *nixsb_fixedpath(Sb *c, const char *name, int64_t nn, int64_t method, const Hash *h, const SortedSet *refs, int64_t *len) { // no bytes and -1: the error is kept
  const char *p = nullptr;
  *len = -1;
  c->guard([&] {
    p = c->keep(makeFixedOutputPath(c->st->settings.storeDir, std::string_view(name, size_t(nn)), FileIngestionMethod(method), *h, refs ? *refs : SortedSet()), len);
  });
  return p;
}
int64_t nixsb_valid(Sb *c, const char *p, int64_t n) { return c->st->isValidPath(std::string_view(p, size_t(n))); }
int64_t nixsb_register(Sb *c, const char *p, int64_t pn, const Hash *narHash, uint64_t narSize, const SortedSet *refs, const char *d, int64_t dn, const char *ca, int64_t cn) {
  return c->guard([&] {
    PathInfo info;
    info.path = composite::Text(p, size_t(pn)), info.narHash = *narHash, info.narSize = narSize;
    if (refs) info.references = *refs;
    info.deriver = composite::Text(d, size_t(dn)), info.ca = composite::Text(ca, size_t(cn));
    c->st->registerValidPath(info);
  });
}
const Derivation *nixsb_drv(Sb *c, const char *p, int64_t n) { // null: the error is kept
  const Derivation *d = nullptr;
  c->guard([&] { d = &c->st->readDerivation(std::string_view(p, size_t(n))); });
  return d;
}
void nixsb_setout(SortedMap<composite::Text> *m, const char *k, int64_t kn, const char *v, int64_t vn) { (*m)[std::string_view(k, size_t(kn))] = composite::Text(v, size_t(vn)); }
const SortedMap<composite::Text> *nixsb_input(Sb *c, const char *p, int64_t n, SortedSet *visiting) { // an input's outputs, read before the next is realised
  const SortedMap<composite::Text> *r = nullptr;
  c->guard([&] { r = &c->maps[c->maps.append(c->st->realise(std::string_view(p, size_t(n)), *visiting))]; });
  return r;
}
int64_t nixsb_ensure(Sb *c, const char *p, int64_t n) { return c->guard([&] { c->st->ensurePath(std::string_view(p, size_t(n))); }); }
int64_t nixsb_closure(Sb *c, const SortedSet *in, SortedSet *out) { return c->guard([&] { *out = c->st->computeFSClosure(*in); }); }
}

int runProgram(std::string_view prog, const composite::MutableSeries<composite::Text> &args, composite::Text *out, const composite::Text *input,
               std::string_view cwd) {
  Sb c;
  int64_t rc = nixsb_run(&c, prog.data(), prog.size(), args.data(), args.size(), out, input, cwd.data(), cwd.size());
  c.done(rc < 0);
  return int(rc);
}

composite::Text Store::addToStore(std::string_view name, std::string_view srcPath, FileIngestionMethod method, HashAlgo algo, const PathFilter &filter,
                                  const SortedSet &refs, composite::Maybe<Hash> expected) {
  Sb c(this, &filter);
  composite::Text dst;
  c.done(nixsb_add(&c, name.data(), name.size(), srcPath.data(), srcPath.size(), int64_t(method), int64_t(algo), bool(filter), &refs, expected ? &*expected : nullptr, &dst));
  return dst;
}

composite::Text Store::addTextToStore(std::string_view name, std::string_view text, const SortedSet &refs) {
  Sb c(this);
  composite::Text dst;
  c.done(nixsb_add(&c, name.data(), name.size(), text.data(), text.size(), 3, 0, 0, &refs, nullptr, &dst)); // 3: the text itself
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
extern "C" int64_t nixsb_tokcount(const Derivation *d);
extern "C" int64_t nixsb_tokens(const Derivation *d, GTok *room, int64_t n);
static composite::MutableSeries<GTok> drvTokens(const Derivation &d) { // lowered/nixstore/StoreModulo.mlir: the room sized ahead, then filled once
  composite::MutableSeries<GTok> t(size_t(nixsb_tokcount(&d)));
  nixsb_tokens(&d, t.data(), t.size());
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

// hashDerivationModulo is lowered/nixstore/StoreModulo.mlir's nixsb_modulo: a fixed-output derivation's text composed and hashed there, any
// other's input derivations folded into the inputs its text is hashed with.  What stays here is the records' and the maps' own.
static_assert(offsetof(Store::DrvRecord, modulo) == 176 && offsetof(Store::DrvModulo, hex) == 16 && sizeof(SortedMap<Hash>::Row) == 88 &&
                  offsetof(SortedMap<Hash>::Row, second) == 16 && offsetof(Hash, bytes) == 4 && sizeof(GTok) == 24 && offsetof(Derivation, platform) == 64,
              "the places StoreModulo.mlir reads");
extern "C" {
int64_t nixsb_modulo(Sb *c, const Derivation *drv, int64_t mask, DrvInputs *inputs, SortedMap<Hash> *res);
/// The record of an input derivation with its modulo hashes: the hasher's answer, or made here; kept, with the one hash's base 16, for every
/// later dependent.  Null: the error is kept.
Store::DrvRecord *nixsb_modrec(Sb *c, const char *p, int64_t n) {
  Store::DrvRecord *made = nullptr;
  c->guard([&] {
    std::string_view drvPath(p, size_t(n));
    Store::DrvRecord *rec = c->st->drvAt(drvPath);
    if (!rec || !rec->hasModulo) {
      Store::DrvModulo m;
      if (!c->st->takeLater(drvPath, m.hashes)) m.hashes = c->st->hashDerivationModulo(c->st->readDerivation(drvPath), false);
      if (auto e = m.hashes.find(""); e != m.hashes.end()) m.hex = e->second.to_string(HashFormat::Base16, false);
      rec = c->st->drvAt(drvPath); // the record of a derivation written here, or the one read just above
      rec->modulo = std::move(m);
      rec->hasModulo = true;
    }
    made = rec;
  });
  return made;
}
void nixsb_merge(DrvInputs *in, const char *hex, int64_t hn, const SortedSet *outs) { // no set: the one output "out"
  SortedSet &s = (*in)[std::string_view(hex, size_t(hn))];
  if (outs) s.insert(outs->begin(), outs->end());
  else s.insert("out");
}
void nixsb_sethash(SortedMap<Hash> *m, const char *k, int64_t kn, const Hash *h) { (*m)[std::string_view(k, size_t(kn))] = *h; }
int64_t nixsb_hashdrv(Sb *c, const Derivation *d, int64_t mask, const DrvInputs *in, SortedMap<Hash> *res) {
  return c->guard([&] { (*res)[""] = d->hashUnparsed(mask, in); });
}
}
SortedMap<Hash> Store::hashDerivationModulo(const Derivation &drv, bool maskOutputs, DrvInputs *inputsOut) {
  Sb c(this);
  SortedMap<Hash> res;
  DrvInputs inputs;
  int64_t s = nixsb_modulo(&c, &drv, maskOutputs, &inputs, &res); // 2: a fixed-output derivation, which has no inputs to give
  c.done(s == 1);
  if (inputsOut && s == 0) *inputsOut = std::move(inputs);
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


void Store::ensurePath(std::string_view path) {
  if (isValidPath(path)) return;
  throw Error(composite::cat("path '", path, "' is not valid and cannot be substituted (no binary caches)"));
}

SortedMap<composite::Text> Store::buildDerivation(std::string_view drvPath) {
  SortedSet visiting;
  return realise(drvPath, visiting);
}

// realise is lowered/nixstore/StoreAdd.mlir's nixsb_realise; an input derivation is realised through this name (nixsb_input).
SortedMap<composite::Text> Store::realise(std::string_view drvPath, SortedSet &visiting) {
  Sb c(this);
  SortedMap<composite::Text> outputs;
  c.done(nixsb_realise(&c, drvPath.data(), drvPath.size(), &visiting, &outputs));
  return outputs;
}

void Store::addPermRoot(std::string_view storePath, std::string_view link) {
  Sb c(this);
  c.done(nixsb_root(&c, storePath.data(), storePath.size(), link.data(), link.size()));
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
