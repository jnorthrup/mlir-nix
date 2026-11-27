//===- StorePaths.cpp - NAR, store paths, ATerm derivations, utilities ----===//

#include "Composite/Mutable.h"
#include "Composite/Patricia.h"
#include "Composite/Rows.h"
#include "Composite/Text.h"
#include "Nix/Numbers.h"
#include "Nix/Os.h"
#include "Nix/Prefetch.h"
#include "Nix/Store.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace nixstore {

//===----------------------------------------------------------------------===//
// File utilities
//===----------------------------------------------------------------------===//

composite::Text readFile(std::string_view path) {
  nixsys::CStr file(path);
  nixprefetch::note('F', file);
  int fd = open(file, O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error(composite::cat("opening file '", path, "': ", strerror(errno)));
  composite::Text s;
  char buf[65536];
  while (true) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) {
      int e = errno;
      close(fd);
      throw Error(composite::cat("reading file '", path, "': ", strerror(e)));
    }
    if (n == 0) break;
    s.put(buf, size_t(n));
  }
  close(fd);
  return s;
}

void writeFile(std::string_view path, std::string_view data, mode_t mode) {
  nixsys::CStr file(path);
  int fd = open(file, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
  if (fd < 0) throw Error(composite::cat("creating file '", path, "': ", strerror(errno)));
  size_t off = 0;
  while (off < data.size()) {
    ssize_t n = write(fd, data.data() + off, data.size() - off);
    if (n < 0) {
      close(fd);
      throw Error(composite::cat("writing file '", path, "': ", strerror(errno)));
    }
    off += n;
  }
  close(fd);
}

bool pathExists(std::string_view path) {
  struct stat st;
  nixsys::CStr file(path);
  nixprefetch::note('L', file);
  return lstat(file, &st) == 0;
}

void createDirs(std::string_view path) {
  if (path.empty() || path == "/") return;
  struct stat st;
  nixsys::CStr file(path);
  if (lstat(file, &st) == 0) {
    if (S_ISDIR(st.st_mode)) return;
    if (S_ISLNK(st.st_mode) && stat(file, &st) == 0 && S_ISDIR(st.st_mode)) return;
    throw Error(composite::cat("'", path, "' is not a directory"));
  }
  createDirs(dirOf(path));
  if (mkdir(file, 0777) != 0 && errno != EEXIST)
    throw Error(composite::cat("creating directory '", path, "': ", strerror(errno)));
}

void deletePathRecursive(std::string_view path) {
  struct stat st;
  nixsys::CStr file(path);
  if (lstat(file, &st) != 0) return;
  if (S_ISDIR(st.st_mode)) {
    chmod(file, st.st_mode | S_IRWXU);
    if (DIR *d = opendir(file)) {
      composite::MutableSeries<composite::Text> names;
      while (auto *e = readdir(d)) {
        std::string_view n = e->d_name;
        if (n != "." && n != "..") names.append(composite::Text(n));
      }
      closedir(d);
      for (auto &n : names) deletePathRecursive(composite::cat(path, '/', n));
    }
    if (rmdir(file) != 0) throw Error(composite::cat("removing '", path, "': ", strerror(errno)));
  } else {
    if (unlink(file) != 0) throw Error(composite::cat("removing '", path, "': ", strerror(errno)));
  }
}

// nixstore::baseNameOf and dirOf are hollowed out to MLIR: lowered/nixstore/PathOps.mlir (trikeshed.at / slice / text /
// drain over the byte series), built into NixStore by lib/CMakeLists.txt.  The bridges size the Text and adopt the
// drained bytes; the slash algebra is gone from here.
extern "C" size_t nixstore_ts_basename(const char *p, size_t n, char *out);
extern "C" size_t nixstore_ts_dirname(const char *p, size_t n, char *out);

composite::Text baseNameOf(std::string_view p) {
  composite::Text t;
  t.resize(p.size());
  t.truncate(nixstore_ts_basename(p.data(), p.size(), t.begin()));
  return t;
}

composite::Text dirOf(std::string_view p) {
  composite::Text t;
  t.resize(p.size() + 1); // "." when there is no slash
  t.truncate(nixstore_ts_dirname(p.data(), p.size(), t.begin()));
  return t;
}

// jsonFloat is lowered/nixstore/JsonFloat.mlir (the shortest round-tripping digits, format_buffer's layout, one combine
// drained once); the snprintf, a variadic call, is this callback.
extern "C" int64_t nixstore_jf_sci(double d, int64_t prec, char *buf) { return snprintf(buf, 64, "%.*e", int(prec - 1), d); }
extern "C" int64_t nixstore_ts_jsonfloat(double, char *, char *);

composite::Text jsonFloat(double d) {
  char buf[64];
  composite::Text out;
  out.resize(32);
  out.truncate(size_t(nixstore_ts_jsonfloat(d, out.begin(), buf)));
  return out;
}

//===----------------------------------------------------------------------===//
// NAR
//===----------------------------------------------------------------------===//

// The NAR is lowered/nixstore/NarFraming.mlir: the framed tokens (constant slices), the node framing (one combine each),
// and the walk (nixstore_ts_nardump:
// a node's type decides its framing, a directory's names are put in byte order, each entry's path `path/name` is composed
// into `path` with a NUL after it, the filter is asked, a kept entry framed and walked).  What stays here is what the walk
// asks for: lstat, the listing, the file's bytes, readlink, the PathFilter, the prefetch notes, the Sink and the wording.
// The framing of a node is flushed to the Sink before each call that may throw, as the tokens were.
struct NarWin { const char *p; int64_t n; };
struct NarDir { composite::MutableSeries<composite::Text> names; composite::MutableSeries<NarWin> wins; composite::MutableSeries<int64_t> order; };
struct NarWriter;
extern "C" void nixstore_ts_nardump(NarWriter *, composite::Text *, char *, char *, const char *, int64_t);
struct NarWriter {
  const Sink &sink;
  const PathFilter &filter;
  bool noteKept = false; // a recorded run's first walk of a filtered tree: each entry the filter keeps goes into the list
  composite::Text path;                  // the entry's path, a NUL after it (the walk writes it)
  composite::MutableSeries<NarDir> dirs; // a directory's names, by depth
  char out[PATH_MAX + 512], link[PATH_MAX];
  NarWriter(const Sink &s, const PathFilter &f) : sink(s), filter(f) {}
  std::string_view at(int64_t n) const { return {path.data(), size_t(n)}; }
  void dump(std::string_view root) { nixstore_ts_nardump(this, &path, out, link, root.data(), int64_t(root.size())); }
};
extern "C" char *nixstore_nar_room(composite::Text *t, int64_t need) {
  if (t->size() < size_t(need)) t->resize(size_t(need) < 256 ? 256 : size_t(need) * 2);
  return t->begin();
}
extern "C" void nixstore_nw_sink(NarWriter *w, int64_t n) { w->sink(std::string_view(w->out, size_t(n))); }
extern "C" int64_t nixstore_nw_stat(NarWriter *w, int64_t n, int64_t *size) {
  struct stat st;
  nixprefetch::note('L', w->path.data());
  if (lstat(w->path.data(), &st) != 0) throw Error(composite::cat("getting attributes of path '", w->at(n), "': ", strerror(errno)));
  *size = int64_t(st.st_size);
  return S_ISREG(st.st_mode) ? (st.st_mode & S_IXUSR ? 1 : 0) : S_ISDIR(st.st_mode) ? 2 : S_ISLNK(st.st_mode) ? 3 : 4;
}
extern "C" void nixstore_nw_file(NarWriter *w, int64_t n, uint64_t left) {
  nixprefetch::note('F', w->path.data());
  int fd = open(w->path.data(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error(composite::cat("opening file '", w->at(n), "': ", strerror(errno)));
  char buf[65536];
  while (left) {
    ssize_t k = read(fd, buf, composite::min<uint64_t>(sizeof buf, left));
    if (k <= 0) { close(fd); throw Error(composite::cat("reading file '", w->at(n), "'")); }
    w->sink(std::string_view(buf, k));
    left -= k;
  }
  close(fd);
}
extern "C" int64_t nixstore_nw_dir(NarWriter *w, int64_t depth, int64_t n, void **wo) {
  while (w->dirs.size() <= size_t(depth)) w->dirs.append(NarDir{});
  NarDir &d = w->dirs[depth];
  d.names.clear(), d.wins.clear();
  nixprefetch::note('D', w->path.data());
  DIR *dp = opendir(w->path.data());
  if (!dp) throw Error(composite::cat("opening directory '", w->at(n), "': ", strerror(errno)));
  while (auto *e = readdir(dp))
    if (std::string_view s = e->d_name; s != "." && s != "..") d.names.append(composite::Text(s));
  closedir(dp);
  for (const composite::Text &s : d.names) d.wins.append(NarWin{s.data(), int64_t(s.size())});
  d.order.resize(d.names.size());
  wo[0] = d.wins.data(), wo[1] = d.order.data();
  return d.names.size();
}
extern "C" int64_t nixstore_nw_keep(NarWriter *w, int64_t n) {
  if (w->filter && !w->filter(w->at(n), {})) return 0;
  if (w->noteKept) nixprefetch::noteKept(w->path.data());
  return 1;
}
extern "C" int64_t nixstore_nw_link(NarWriter *w, int64_t n) {
  ssize_t k = readlink(w->path.data(), w->link, PATH_MAX);
  if (k < 0) throw Error(composite::cat("reading symlink '", w->at(n), "'"));
  return k;
}
extern "C" void nixstore_nw_odd(NarWriter *w, int64_t n) { throw Error(composite::cat("file '", w->at(n), "' has an unsupported type")); }

void dumpPath(std::string_view path, const Sink &sink, const PathFilter &filter) {
  NarWriter w{sink, filter};
  w.dump(path);
}

namespace {
/// A tree a recorded run hashed, hashed again by the helper.  The helper writes it while Hashing; once Done it is only read.
struct Prehash {
  enum : uint8_t { Queued, Hashing, Done, Claimed }; // Claimed: asked for before the helper began it, and hashed by the asker
  composite::Atomic<uint8_t> state{Queued};
  bool filtered = false;
  composite::Text root;
  composite::Patricia<char> kept; // a filtered tree: the entries the recorded run's filter kept, keyed by bytes of its own (`names`)
  bool ok = false;
  Hash hash;
  uint64_t size = 0;
  struct Seen {
    uint32_t off, len; // the entry's path, in `text`
    char type;         // 'r', 'd', 's', 'u', or 0 when lstat failed
    bool kept;
  };
  composite::MutableSeries<char> text;
  composite::MutableSeries<Seen> seen; // a filtered tree: every entry the walk asked about, in its order, which is a walk's
  std::string_view path(const Seen &s) const { return {text.data() + s.off, s.len}; }
};
/// The trees by root, filtered or not; built before the helper starts and only read after, so the tries need no lock.
composite::Patricia<Prehash *> *prehashes = nullptr; // [2]

char typeOf(std::string_view path) {
  struct stat st;
  if (lstat(nixsys::CStr(path), &st) != 0) return 0;
  return S_ISREG(st.st_mode) ? 'r' : S_ISDIR(st.st_mode) ? 'd' : S_ISLNK(st.st_mode) ? 's' : 'u';
}
std::string_view typeName(char t) {
  switch (t) {
  case 'r': return "regular";
  case 'd': return "directory";
  case 's': return "symlink";
  case 'u': return "unknown";
  default: return {}; // the filter finds it itself
  }
}

/// A tree being hashed is waited for here (the evaluator asks for one now and then): the helper signals after each tree it finishes.
nixsys::Lock prehashLock;
nixsys::Signal prehashDone;

/// The helper's answer for the tree at `path`: waited for while it is being made, null when there is none or it failed.  One the helper has
/// not begun is claimed instead, and hashed by the caller.
Prehash *takePrehash(std::string_view path, bool filtered) {
  Prehash **pp = prehashes[filtered].find(path.data(), uint32_t(path.size()));
  if (!pp) return nullptr;
  Prehash *p = *pp;
  uint8_t s = Prehash::Queued;
  if (p->state.compare_exchange(s, Prehash::Claimed) || s == Prehash::Claimed) return nullptr;
  if (s == Prehash::Hashing) {
    nixsys::Held g(prehashLock);
    prehashDone.waitFor(prehashLock, [p] { return p->state.load(__ATOMIC_ACQUIRE) != Prehash::Hashing; });
  }
  return p->ok ? p : nullptr;
}
} // namespace

void startPrehash() {
  if (prehashes || nixprefetch::replayHashes.empty()) return;
  prehashes = new composite::Patricia<Prehash *>[2];
  composite::MutableSeries<Prehash *> order;
  for (const nixprefetch::ReplayHash &r : nixprefetch::replayHashes) {
    auto &byRoot = prehashes[r.filtered];
    if (byRoot.find(r.root.data(), uint32_t(r.root.size()))) continue; // a root is recorded once (noteRoot)
    // A tree and its kept names are the helper's own, never freed: the helper may still be hashing when the process ends, after the
    // replay list is gone.  The names go in one buffer, made once at its size, so a key never moves.
    auto *p = new Prehash();
    p->filtered = r.filtered;
    p->root = r.root.clone();
    size_t bytes = 0;
    for (const composite::Text &k : r.kept) bytes += k.size();
    char *names = static_cast<char *>(::operator new(bytes ? bytes : 1)), *at = names;
    for (const composite::Text &k : r.kept) {
      memcpy(at, k.data(), k.size());
      p->kept.set(at, uint32_t(k.size()), 1, [at] { return at; });
      at += k.size();
    }
    byRoot.set(p->root.data(), uint32_t(p->root.size()), p, [p] { return p->root.c_str(); });
    order.append(p);
  }
  nixsys::Thread::start([order = std::move(order)]() mutable {
    for (Prehash *p : order) {
      uint8_t s = Prehash::Queued;
      if (!p->state.compare_exchange(s, Prehash::Hashing)) continue; // claimed: the evaluator got there first
      try {
        HashSink hs(HashAlgo::SHA256);
        auto update = [&](std::string_view d) { hs.update(d); }; // the callables a Sink and a PathFilter lend: named, so they outlive the walk
        auto keepIt = [p](std::string_view c, std::string_view) {
          bool k = p->kept.find(c.data(), uint32_t(c.size())) != nullptr;
          uint32_t off = p->text.size();
          p->text.appendAll(c.data(), uint32_t(c.size()));
          p->seen.append({off, uint32_t(c.size()), typeOf(c), k});
          return k;
        };
        Sink sink = update;
        PathFilter keep = keepIt, none;
        NarWriter w{sink, p->filtered ? keep : none};
        w.dump(p->root);
        p->size = hs.bytes();
        p->hash = hs.finish();
        p->ok = true;
      } catch (...) {
        p->ok = false;
      }
      p->state.store(Prehash::Done, __ATOMIC_RELEASE);
      { nixsys::Held g(prehashLock); } // a waiter that saw Hashing under the lock is asleep before the signal, so it is woken
      prehashDone.notifyAll();
    }
  }).detach();
}

composite::Join<Hash, uint64_t> hashPath(std::string_view path, const PathFilter &filter, HashAlgo algo) {
  composite::Patricia<char> given; // a prehashed tree whose filter answered otherwise: the answers it gave (1 kept, 2 not), then the filter
  auto answerIt = [&given, &filter](std::string_view c, std::string_view t) {
    char *a = given.find(c.data(), uint32_t(c.size()));
    return a ? *a == 1 : filter(c, t);
  };
  PathFilter answered;
  if (prehashes && algo == HashAlgo::SHA256)
    if (Prehash *p = takePrehash(path, bool(filter))) {
      if (!filter) return composite::Join<Hash, uint64_t>{p->hash, p->size};
      uint32_t k = 0;
      bool d = false;
      for (; k < p->seen.size(); k++) {
        const Prehash::Seen &s = p->seen[k];
        if ((d = filter(p->path(s), typeName(s.type))) != s.kept) break;
      }
      if (k == p->seen.size()) return composite::Join<Hash, uint64_t>{p->hash, p->size};
      // Entry k is answered otherwise: the tree is walked here.  The entries asked about so far come first in the walk too, and keep
      // their answers, so the filter is asked about each entry once.
      for (uint32_t i = 0; i <= k; i++) {
        std::string_view e = p->path(p->seen[i]);
        given.set(e.data(), uint32_t(e.size()), (i < k ? p->seen[i].kept : d) ? 1 : 2, [&] { return e.data(); }); // `text` is done growing
      }
      answered = answerIt;
    }
  HashSink hs(algo);
  auto update = [&](std::string_view d) { hs.update(d); };
  Sink sink = update;
  const PathFilter &f = answered ? answered : filter;
  NarWriter w{sink, f};
  w.noteKept = algo == HashAlgo::SHA256 && nixprefetch::noteRoot(filter ? 'G' : 'H', nixsys::CStr(path)) && filter;
  w.dump(path);
  uint64_t n = hs.bytes();
  return {hs.finish(), n};
}

// restorePath's reader is lowered/nixstore/NarFraming.mlir's nixstore_ts_narrestore (the strings, their bounds, the
// tokens expected, the names checked, `dst/name` composed into `dst`); the files, links and directories it makes and the
// wording of its errors are these callbacks.
extern "C" void nixstore_ts_narrestore(composite::Text *, const char *, int64_t, const char *, int64_t);
extern "C" [[noreturn]] void nixstore_nr_fail(composite::Text *, int64_t code, const char *p, int64_t n) {
  std::string_view s(p, size_t(n));
  if (code == 0) throw Error("NAR truncated");
  if (code == 1) throw Error(composite::cat("bad NAR: expected '", s, "'"));
  if (code == 3) throw Error(composite::cat("NAR contains invalid file name '", s, "'"));
  throw Error(code == 2 ? "bad NAR" : "bad NAR: unknown file type");
}
extern "C" void nixstore_nr_file(composite::Text *dst, int64_t n, const char *p, int64_t k, int64_t exec) {
  writeFile(std::string_view(dst->data(), size_t(n)), std::string_view(p, size_t(k)), exec ? 0755 : 0644);
}
extern "C" void nixstore_nr_link(composite::Text *dst, int64_t n, const char *p, int64_t k) {
  if (symlink(nixsys::CStr(std::string_view(p, size_t(k))), dst->data()) != 0)
    throw Error(composite::cat("creating symlink '", std::string_view(dst->data(), size_t(n)), "'"));
}
extern "C" void nixstore_nr_dir(composite::Text *dst, int64_t n) {
  if (mkdir(dst->data(), 0755) != 0) throw Error(composite::cat("creating directory '", std::string_view(dst->data(), size_t(n)), "'"));
}

void restorePath(std::string_view path, std::string_view nar) {
  composite::Text dst;
  nixstore_ts_narrestore(&dst, nar.data(), int64_t(nar.size()), path.data(), int64_t(path.size()));
}

//===----------------------------------------------------------------------===//
// Store paths
//===----------------------------------------------------------------------===//

// nixstore::checkName / outputPathName / isStorePath / storePathName / storePathHashPart are hollowed out to MLIR:
// lowered/nixstore/StoreName.mlir (trikeshed.at / slice / text / compare / combine / drain over the byte series), built
// into NixStore by lib/CMakeLists.txt.  checkName's scan answers a code and the first illegal index; the error wording
// stays here.  The other bridges size the Text and adopt the drained bytes; the naming algebra is gone from here.
extern "C" int nixstore_ts_checkname(const char *p, size_t n, size_t *bad);
extern "C" size_t nixstore_ts_outputname(const char *d, size_t dn, const char *o, size_t on, char *out);
extern "C" bool nixstore_ts_isstorepath(const char *sd, size_t ss, const char *pd, size_t ps);
extern "C" size_t nixstore_ts_storename(const char *p, size_t n, char *out);
extern "C" size_t nixstore_ts_storehash(const char *p, size_t n, char *out);

void checkName(std::string_view name) {
  size_t bad = 0;
  int r = nixstore_ts_checkname(name.data(), name.size(), &bad);
  if (r == 0) return;
  auto q = [&](std::string_view n) { return composite::cat("'", n, "'"); };
  if (r == 1) throw Error("name must not be empty");
  if (r == 2) throw Error(composite::cat("name ", q(name), " must be no longer than 211 characters"));
  if (r == 3 || r == 5) throw Error(composite::cat("name ", q(name), " is not valid"));
  if (r == 4) throw Error(composite::cat("name ", q(name), " is not valid: first dash-separated component must not be '.'"));
  if (r == 6) throw Error(composite::cat("name ", q(name), " is not valid: first dash-separated component must not be '..'"));
  throw Error(composite::cat("name ", q(name), " contains illegal character '", name[bad], "'"));
}

// The store-path name algebra is lowered/nixstore/StorePathOps.mlir (one lazy combine of the pieces drained once,
// fill-drain): the fingerprint `type:algo:hex:storeDir:name`, the path `storeDir/nix32-name`, makeType's
// `type[:ref]*[:self]`.  The hex/nix32 digits are composed in the entry; checkName/compressHash/hashString and the
// error wording stay here.  The store path hashes stay byte-identical (the fingerprint is what is hashed).
extern "C" int64_t nixstore_ts_pathfp(const char *, int64_t, const char *, int64_t, const char *, int64_t,
                                           const char *, int64_t, const char *, int64_t, char *, int64_t);
extern "C" int64_t nixstore_ts_storepath(const char *, int64_t, const char *, int64_t, const char *, int64_t, char *, int64_t);
extern "C" int64_t nixstore_ts_maketype(const char *, int64_t, const void *, int64_t, int64_t, char *, int64_t);
static_assert(sizeof(composite::Text) == 16 && offsetof(composite::Growable<char>, n) == 8, "Text row layout the entry reads");
namespace {
// A Text drained by an entry that answers the bytes written, or -needed when the room (bound) is short.
template <class F> composite::Text drained(size_t bound, F call) {
  composite::Text s;
  s.resize(bound);
  int64_t w = call(s.begin(), int64_t(bound));
  if (w < 0) { s.resize(size_t(-w)); w = call(s.begin(), -w); }
  s.truncate(size_t(w));
  return s;
}
} // namespace

composite::Text makeStorePath(std::string_view storeDir, std::string_view type, const Hash &hash,
                              std::string_view name) {
  checkName(name);
  std::string_view algo = algoName(hash.algo);
  size_t hn = hash.size();
  composite::Text s;
  s.resize(type.size() + algo.size() + 2 * hn + storeDir.size() + name.size() + 4);
  s.truncate(size_t(nixstore_ts_pathfp(type.data(), type.size(), algo.data(), algo.size(),
      reinterpret_cast<const char *>(hash.bytes), int64_t(hn), storeDir.data(), storeDir.size(), name.data(),
      name.size(), s.begin(), s.size())));
  Hash h = compressHash(hashString(HashAlgo::SHA256, s), 20);
  composite::Text path;
  path.resize(storeDir.size() + 34 + name.size());
  path.truncate(size_t(nixstore_ts_storepath(storeDir.data(), storeDir.size(),
      reinterpret_cast<const char *>(h.bytes), 20, name.data(), name.size(), path.begin(), path.size())));
  return path;
}

composite::Text makeType(std::string_view storeDir, std::string_view type, const SortedSet &refs,
                         bool hasSelfRef) {
  return drained(type.size() + 5, [&](char *into, int64_t cap) {
    return nixstore_ts_maketype(type.data(), type.size(), refs.rows.data(), int64_t(refs.size()), hasSelfRef, into, cap);
  });
}

composite::Text makeTextPath(std::string_view storeDir, std::string_view name, const Hash &hash,
                             const SortedSet &refs) {
  return makeStorePath(storeDir, makeType(storeDir, "text", refs, false), hash, name);
}

composite::Text makeFixedOutputPath(std::string_view storeDir, std::string_view name,
                                    FileIngestionMethod method, const Hash &hash,
                                    const SortedSet &refs) {
  if (method == FileIngestionMethod::Text) return makeTextPath(storeDir, name, hash, refs);
  if (method == FileIngestionMethod::NixArchive && hash.algo == HashAlgo::SHA256)
    return makeStorePath(storeDir, makeType(storeDir, "source", refs, false), hash, name);
  if (!refs.empty())
    throw Error(composite::cat("fixed output derivation '", name,
                               "' is not allowed to refer to other store paths."));
  composite::Text payload = composite::cat("fixed:out:", method == FileIngestionMethod::NixArchive ? "r:" : "",
                                           hash.to_string(HashFormat::Base16, true), ":");
  return makeStorePath(storeDir, "output:out", hashString(HashAlgo::SHA256, payload), name);
}

composite::Text outputPathName(std::string_view drvName, std::string_view output) {
  composite::Text t;
  t.resize(drvName.size() + 1 + output.size());
  t.truncate(nixstore_ts_outputname(drvName.data(), drvName.size(), output.data(), output.size(), t.begin()));
  return t;
}

composite::Text makeOutputPath(std::string_view storeDir, std::string_view output, const Hash &drvHash,
                               std::string_view drvName) {
  return makeStorePath(storeDir, composite::cat("output:", output), drvHash,
                       outputPathName(drvName, output));
}

composite::Text hashPlaceholder(std::string_view output) {
  Hash h = hashString(HashAlgo::SHA256, composite::cat("nix-output:", output));
  return composite::cat("/", h.to_string(HashFormat::Nix32, false));
}

// nixstore::isInStore is hollowed out to MLIR: lowered/nixstore/IsInStore.mlir, built into NixStore by lib/CMakeLists.txt.

composite::Text toStorePath(std::string_view storeDir, std::string_view path) {
  if (!isInStore(storeDir, path)) throw Error(composite::cat("path '", path, "' is not in the Nix store"));
  auto slash = path.find('/', storeDir.size() + 1);
  return composite::Text(slash == std::string_view::npos ? path : path.substr(0, slash));
}

bool isStorePath(std::string_view storeDir, std::string_view path) {
  return nixstore_ts_isstorepath(storeDir.data(), storeDir.size(), path.data(), path.size());
}

composite::Text storePathName(std::string_view storePath) {
  composite::Text t;
  t.resize(storePath.size());
  t.truncate(nixstore_ts_storename(storePath.data(), storePath.size(), t.begin()));
  return t;
}

composite::Text storePathHashPart(std::string_view storePath) {
  composite::Text t;
  t.resize(32);
  t.truncate(nixstore_ts_storehash(storePath.data(), storePath.size(), t.begin()));
  return t;
}

//===----------------------------------------------------------------------===//
// Derivations
//===----------------------------------------------------------------------===//

composite::Text DerivationOutput::methodAlgo() const {
  std::string_view prefix = method == FileIngestionMethod::NixArchive ? "r:"
                            : method == FileIngestionMethod::Text      ? "text:"
                                                                       : "";
  return composite::cat(prefix, algoName(kind == CAFixed ? hash.algo : hashAlgo));
}

composite::Text DerivationOutput::fixedPath(std::string_view storeDir, std::string_view drvName,
                                            std::string_view output) const {
  return makeFixedOutputPath(storeDir, outputPathName(drvName, output), method, hash);
}

bool Derivation::isFixed() const {
  return outputs.size() == 1 && outputs.begin()->first == "out" &&
         outputs.begin()->second.kind == DerivationOutput::CAFixed;
}

// The derivation ATerm text is composed in lowered/nixstore/DrvUnparse.mlir (trikeshed.combineAll + combine + drain over
// series<i8>, built into NixStore by lib/CMakeLists.txt): one lazy composition of the whole ATerm drained once into a
// pre-sized buffer.  The bridge here only marshals the Derivation into flat record arrays -- normalizing each output's
// kind to its (name,path,algo,hash) fields, applying maskOutputs and slotting __json into the env order -- sizes the Text
// and adopts the drained bytes.  The composition loop, the two Out sinks and the ATerm escape helpers are gone from here.
namespace {
struct DrvWin { const char *p; size_t n; };
struct DrvOut { DrvWin name, path, algo, hash; };
struct DrvIn { DrvWin path; const DrvWin *outs; size_t nouts; };
struct DrvEnv { DrvWin key, val; };
struct DrvBuf {
  composite::MutableSeries<DrvOut> outs;
  composite::MutableSeries<composite::Text> owned; // the methodAlgo / hash strings the records point into
  composite::MutableSeries<DrvIn> ins;
  composite::MutableSeries<DrvWin> inouts, srcs, args;
  composite::MutableSeries<DrvEnv> env;
  composite::MutableSeries<int64_t> kinds; // each output's DerivationOutput::Kind (the JSON writer's fields)
  DrvWin platform, builder;
  size_t bound = 0;
};
} // namespace
extern "C" int64_t nixstore_ts_unparse(const DrvOut *, int64_t, const DrvIn *, int64_t, const DrvWin *, int64_t,
                                       const char *, int64_t, const char *, int64_t, const DrvWin *, int64_t,
                                       const DrvEnv *, int64_t, char *, int64_t);

namespace {
void marshalDrv(const Derivation &d, bool maskOutputs, const DrvInputs *actualInputs, DrvBuf &b) {
  auto win = [](const composite::Text &t) { return DrvWin{t.data(), t.size()}; };
  auto winv = [](std::string_view v) { return DrvWin{v.data(), v.size()}; };
  const DrvWin empty{"", 0};
  const auto &inputs = actualInputs ? *actualInputs : d.inputDrvs;
  b.outs.reserve(d.outputs.size());
  b.owned.reserve(2 * d.outputs.size());
  b.ins.reserve(inputs.size());
  size_t totalOuts = 0;
  for (const auto &[path, outs] : inputs) totalOuts += outs.size();
  b.inouts.reserve(totalOuts);
  b.srcs.reserve(d.inputSrcs.size());
  b.args.reserve(d.args.size());
  b.env.reserve(d.env.size() + 1);
  for (const auto &[name, o] : d.outputs) {
    DrvWin pw = empty, aw = empty, hw = empty;
    switch (o.kind) {
    case DerivationOutput::InputAddressed:
      pw = maskOutputs ? empty : win(o.path);
      break;
    case DerivationOutput::CAFixed: {
      pw = maskOutputs ? empty : win(o.path);
      composite::Text a = o.methodAlgo(), h = o.hash.to_string(HashFormat::Base16, false);
      aw = win(a); hw = win(h); b.owned.append(composite::mv(a)); b.owned.append(composite::mv(h));
      break;
    }
    case DerivationOutput::CAFloating: {
      composite::Text a = o.methodAlgo(); aw = win(a); b.owned.append(composite::mv(a));
      break;
    }
    case DerivationOutput::Deferred:
      break;
    case DerivationOutput::Impure: {
      composite::Text a = o.methodAlgo(); aw = win(a); b.owned.append(composite::mv(a)); hw = winv("impure");
      break;
    }
    }
    b.outs.append(DrvOut{win(name), pw, aw, hw}); b.kinds.append(int64_t(o.kind));
  }
  for (const auto &[path, outs] : inputs) {
    const DrvWin *base = b.inouts.data() + b.inouts.size();
    for (const composite::Text &o : outs) b.inouts.append(win(o));
    b.ins.append(DrvIn{win(path), base, outs.size()});
  }
  for (const composite::Text &p : d.inputSrcs) b.srcs.append(win(p));
  b.platform = win(d.platform);
  b.builder = win(d.builder);
  for (const composite::Text &a : d.args) b.args.append(win(a));
  // The environment in key order, with __json (the structured attributes, which win over an env entry of that name) at
  // its place in that order; an output's value is masked when maskOutputs.  Nothing is copied and no map is built.
  auto isOutput = [&](std::string_view k) {
    for (const auto &[name, o] : d.outputs)
      if (name == k) return true;
    return false;
  };
  auto addEnv = [&](std::string_view k, std::string_view v) {
    b.env.append(DrvEnv{winv(k), maskOutputs && isOutput(k) ? empty : winv(v)});
  };
  constexpr std::string_view kJson = "__json";
  bool json = d.structuredAttrs.has_value();
  for (const auto &[k, v] : d.env) {
    if (json && std::string_view(k) >= kJson) { addEnv(kJson, *d.structuredAttrs); json = false; }
    if (d.structuredAttrs && k == kJson) continue;
    addEnv(k, v);
  }
  if (json) addEnv(kJson, *d.structuredAttrs);
  // A worst-case bound: every field quoted (2 + n) or escaped (2 + 2n), plus structural slack per element.  The entry
  // also answers -needed when cap is short, so the bridge retries; the bound only keeps that to one call.
  size_t bytes = b.platform.n + b.builder.n, fields = 2;
  for (const DrvOut &o : b.outs) { bytes += o.name.n + o.path.n + o.algo.n + o.hash.n; fields += 4; }
  for (const DrvIn &i : b.ins) { bytes += i.path.n; fields += 1; for (size_t j = 0; j < i.nouts; j++) { bytes += i.outs[j].n; fields += 1; } }
  for (const DrvWin &s : b.srcs) { bytes += s.n; fields += 1; }
  for (const DrvWin &a : b.args) { bytes += a.n; fields += 1; }
  for (const DrvEnv &e : b.env) { bytes += e.key.n + e.val.n; fields += 2; }
  b.bound = 2 * bytes + 2 * fields + 16 * (b.outs.size() + b.ins.size() + b.srcs.size() + b.args.size() + b.env.size() + 1) + 64;
}
} // namespace

composite::Text Derivation::unparse(bool maskOutputs, const DrvInputs *actualInputs) const {
  DrvBuf b;
  marshalDrv(*this, maskOutputs, actualInputs, b);
  return drained(b.bound, [&](char *into, int64_t cap) {
    return nixstore_ts_unparse(b.outs.data(), b.outs.size(), b.ins.data(), b.ins.size(), b.srcs.data(), b.srcs.size(),
                               b.platform.p, b.platform.n, b.builder.p, b.builder.n, b.args.data(), b.args.size(),
                               b.env.data(), b.env.size(), into, cap);
  });
}

Hash Derivation::hashUnparsed(bool maskOutputs, const DrvInputs *actualInputs) const {
  composite::Text t = unparse(maskOutputs, actualInputs);
  HashSink h(HashAlgo::SHA256);
  h.update(std::string_view(t.data(), t.size()));
  return h.finish();
}

// parseDerivation's walk over the ATerm text is lowered/nixstore/DrvParse.mlir: it decodes every string into the room,
// records it in `wins` in text order, counts the lists ([outputs, inputs, srcs, args, env, each input's outputs]) and
// answers -1 or the old parser's failure offset.  Building the Derivation stays here: the outputs' kinds and methods,
// parseHashAlgo/parseHash and their errors (first, for the outputs the walk read before an ATerm error: the old parser
// classified each output as it went), __json, and the sorted maps and sets.
extern "C" int64_t nixstore_ts_drvparse(const char *, int64_t, char *, DrvWin *, int64_t *);

Derivation parseDerivation(std::string_view text, composite::Text name) {
  Derivation d;
  d.name = composite::mv(name);
  size_t half = text.size() / 2 + 2;
  composite::Text room;
  room.resize(text.size());
  composite::MutableSeries<DrvWin> wins(half);
  composite::MutableSeries<int64_t> counts(half + 5);
  int64_t fail = nixstore_ts_drvparse(text.data(), int64_t(text.size()), room.begin(), wins.data(), counts.data());
  const DrvWin *w = wins.data();
  const int64_t *c = counts.data();
  auto next = [&] { const DrvWin &x = *w++; return std::string_view(x.p, x.n); };
  for (int64_t i = 0; i < c[0]; i++) {
    std::string_view id = next(), path = next(), a = next(), hash = next();
    DerivationOutput o;
    if (!a.empty()) {
      o.method = FileIngestionMethod::Flat;
      if (a.rfind("r:", 0) == 0) { o.method = FileIngestionMethod::NixArchive; a = a.substr(2); }
      else if (a.rfind("text:", 0) == 0) { o.method = FileIngestionMethod::Text; a = a.substr(5); }
      auto ha = parseHashAlgo(a);
      if (!ha) throw Error(composite::cat("unknown hash algorithm '", a, "' in derivation"));
      o.hashAlgo = *ha;
      if (hash == "impure") o.kind = DerivationOutput::Impure;
      else if (!hash.empty()) {
        o.kind = DerivationOutput::CAFixed;
        o.hash = parseHash(hash, *ha);
        o.path = composite::Text(path);
      } else o.kind = DerivationOutput::CAFloating;
    } else if (path.empty()) {
      o.kind = DerivationOutput::Deferred;
    } else {
      o.kind = DerivationOutput::InputAddressed;
      o.path = composite::Text(path);
    }
    d.outputs[id] = composite::mv(o);
  }
  if (fail >= 0) throw Error(composite::cat("invalid derivation (ATerm parse error at offset ", size_t(fail), ")"));
  for (int64_t i = 0; i < c[1]; i++) {
    std::string_view path = next();
    SortedSet outs;
    for (int64_t j = 0; j < c[5 + i]; j++) outs.insert(next());
    d.inputDrvs[path] = composite::mv(outs);
  }
  for (int64_t i = 0; i < c[2]; i++) d.inputSrcs.insert(next());
  d.platform = composite::Text(next());
  d.builder = composite::Text(next());
  for (int64_t i = 0; i < c[3]; i++) d.args.append(composite::Text(next()));
  for (int64_t i = 0; i < c[4]; i++) {
    std::string_view k = next(), v = next();
    if (k == "__json") d.structuredAttrs = composite::Text(v);
    else d.env[k] = composite::Text(v);
  }
  return d;
}

// derivationToJSON's whole composition is lowered/nixstore/DrvJson.mlir (fill-drain over the record arrays marshalDrv
// makes with maskOutputs off, where __json sits in the env at its place in key order, plus each output's kind).
extern "C" int64_t nixstore_ts_drvjson(const char *, int64_t, const DrvOut *, int64_t, const int64_t *, const DrvIn *,
                                       int64_t, const DrvWin *, int64_t, const char *, int64_t, const char *, int64_t,
                                       const char *, int64_t, const DrvWin *, int64_t, const DrvEnv *, int64_t, char *,
                                       int64_t);

composite::Text derivationToJSON(std::string_view storeDir, std::string_view drvPath, const Derivation &drv) {
  DrvBuf b;
  marshalDrv(drv, false, nullptr, b);
  (void)storeDir;
  return drained(3 * b.bound + 6 * (drvPath.size() + drv.name.size()) + 128, [&](char *into, int64_t cap) {
    return nixstore_ts_drvjson(drvPath.data(), drvPath.size(), b.outs.data(), b.outs.size(), b.kinds.data(),
                               b.ins.data(), b.ins.size(), b.srcs.data(), b.srcs.size(), drv.name.data(),
                               drv.name.size(), b.platform.p, b.platform.n, b.builder.p, b.builder.n, b.args.data(),
                               b.args.size(), b.env.data(), b.env.size(), into, cap);
  });
}

} // namespace nixstore
