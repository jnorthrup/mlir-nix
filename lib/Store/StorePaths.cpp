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
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace nixstore {

//===----------------------------------------------------------------------===//
// File utilities
//===----------------------------------------------------------------------===//

// The store's files are lowered/nixstore/FileOps.mlir: the system calls (through the C library, the system's words in
// FileOs<System>.mlir.in), a directory's names filled and folded over, and the wording of what fails.  A forward makes
// the path a C string and throws the message an entry leaves; nixstore_text_sized is how an entry sizes a Text once.
extern "C" {
char *nixstore_text_sized(composite::Text *t, int64_t n) { t->room(size_t(n)), t->bytes.n = uint32_t(n), t->terminate(); return t->begin(); }
int64_t nixstore_fs_read(const char *path, int64_t n, composite::Text *out);
int64_t nixstore_fs_write(const char *path, int64_t n, const char *data, int64_t dn, int64_t mode, composite::Text *err);
int64_t nixstore_fs_exists(const char *path);
int64_t nixstore_fs_mkdirs(const char *path, int64_t n, composite::Text *err);
int64_t nixstore_fs_delete(const char *path, int64_t n, composite::Text *err);
}
composite::Text readFile(std::string_view path) { composite::Text s; if (nixstore_fs_read(nixsys::CStr(path), path.size(), &s)) throw Error(s); return s; }
void writeFile(std::string_view path, std::string_view data, mode_t mode) { composite::Text e; if (nixstore_fs_write(nixsys::CStr(path), path.size(), data.data(), data.size(), mode, &e)) throw Error(e); }
bool pathExists(std::string_view path) { return nixstore_fs_exists(nixsys::CStr(path)); }
void createDirs(std::string_view path) { composite::Text e; if (nixstore_fs_mkdirs(nixsys::CStr(path), path.size(), &e)) throw Error(e); }
void deletePathRecursive(std::string_view path) { composite::Text e; if (nixstore_fs_delete(nixsys::CStr(path), path.size(), &e)) throw Error(e); }

// baseNameOf and dirOf are lowered/nixstore/PathOps.mlir (the slash algebra) and jsonFloat is JsonFloat.mlir (the
// shortest round-tripping digits, format_buffer's layout, one combine drained once); StorePathMake.mlir's nixstore_tx_*
// size the Text to the entry's bound and cut it to what was written.  The snprintf, a variadic call, is this callback.
extern "C" {
int64_t nixstore_jf_sci(double d, int64_t prec, char *buf) { return snprintf(buf, 64, "%.*e", int(prec - 1), d); }
void nixstore_tx_basename(const char *p, int64_t n, composite::Text *out);
void nixstore_tx_dirname(const char *p, int64_t n, composite::Text *out);
void nixstore_tx_jsonfloat(double d, composite::Text *out);
}
composite::Text baseNameOf(std::string_view p) { composite::Text t; nixstore_tx_basename(p.data(), p.size(), &t); return t; }
composite::Text dirOf(std::string_view p) { composite::Text t; nixstore_tx_dirname(p.data(), p.size(), &t); return t; }
composite::Text jsonFloat(double d) { composite::Text t; nixstore_tx_jsonfloat(d, &t); return t; }

// runProgram's argv pointer fill is lowered/nixstore/StorePathOps.mlir (allocation-free, it runs in the fork child):
// into[0]=prog, into[k+1]=args[k].c_str() (the Text row's NUL-terminated data ptr), into[n+1]=null.
extern "C" int64_t nixstore_ts_argv(const char *, const void *, int64_t, char **);

int runProgram(std::string_view prog, const composite::MutableSeries<composite::Text> &args, composite::Text *out,
               const composite::Text *input, std::string_view cwd) {
  int outPipe[2], inPipe[2];
  if (pipe(outPipe) != 0) throw Error("pipe failed");
  if (input && pipe(inPipe) != 0) throw Error("pipe failed");
  nixsys::CStr progC(prog), cwdC(cwd); // made before the fork, where an allocation is safe: the child only reads them
  pid_t pid = fork();
  if (pid < 0) throw Error("fork failed");
  if (pid == 0) {
    if (!cwd.empty() && chdir(cwdC) != 0) _exit(127);
    dup2(outPipe[1], 1);
    close(outPipe[0]);
    close(outPipe[1]);
    if (input) {
      dup2(inPipe[0], 0);
      close(inPipe[0]);
      close(inPipe[1]);
    } else {
      int nul = open("/dev/null", O_RDONLY);
      dup2(nul, 0);
    }
    composite::MutableSeries<char *> argv(args.size() + 2);
    nixstore_ts_argv(progC.c_str(), args.data(), int64_t(args.size()), argv.data());
    execvp(progC, argv.data());
    _exit(127);
  }
  close(outPipe[1]);
  if (input) {
    close(inPipe[0]);
    size_t off = 0;
    while (off < input->size()) {
      ssize_t n = write(inPipe[1], input->data() + off, input->size() - off);
      if (n <= 0) break;
      off += n;
    }
    close(inPipe[1]);
  }
  char buf[65536];
  while (true) {
    ssize_t n = read(outPipe[0], buf, sizeof buf);
    if (n <= 0) break;
    if (out) out->put(buf, size_t(n));
  }
  close(outPipe[0]);
  int status;
  waitpid(pid, &status, 0);
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
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

// The store's path names are lowered/nixstore/StorePathMake.mlir: checkName's wording over StoreName.mlir's scan; a
// path made of its fingerprint `type:algo:hex:storeDir:name` (StorePathOps.mlir), that fingerprint's SHA-256 folded to 20
// bytes, and `storeDir/nix32-name`; the types `text[:ref]*`, `source[:ref]*`, `output:<output>`; the placeholder; a
// path cut to its store path.  An entry that can fail leaves its message in the Text, which the forward throws.
// nixstore::isInStore is IsInStore.mlir under its own name.
extern "C" {
int64_t nixstore_ts_namecheck(const char *p, int64_t n, composite::Text *err);
int64_t nixstore_ts_makestorepath(const char *sd, int64_t sdn, const char *type, int64_t tn, const Hash *h, const char *name, int64_t nn, composite::Text *out);
int64_t nixstore_ts_textpath(const char *sd, int64_t sdn, const char *name, int64_t nn, const Hash *h, const void *refs, int64_t nrefs, composite::Text *out);
int64_t nixstore_ts_fixedpath(const char *sd, int64_t sdn, const char *name, int64_t nn, int64_t method, const Hash *h, const void *refs, int64_t nrefs, composite::Text *out);
int64_t nixstore_ts_outputpath(const char *sd, int64_t sdn, const char *output, int64_t on, const Hash *h, const char *drvName, int64_t dn, composite::Text *out);
void nixstore_ts_placeholder(const char *output, int64_t on, composite::Text *out);
int64_t nixstore_ts_tostorepath(const char *sd, int64_t sdn, const char *p, int64_t n, composite::Text *out);
bool nixstore_ts_isstorepath(const char *sd, size_t ss, const char *pd, size_t ps);
void nixstore_tx_outputname(const char *d, int64_t dn, const char *o, int64_t on, composite::Text *out);
void nixstore_tx_storename(const char *p, int64_t n, composite::Text *out);
void nixstore_tx_storehash(const char *p, int64_t n, composite::Text *out);
}
static_assert(sizeof(composite::Text) == 16 && offsetof(composite::Growable<char>, n) == 8, "a set's rows as StorePathOps.mlir reads them");

void checkName(std::string_view name) { composite::Text e; if (nixstore_ts_namecheck(name.data(), name.size(), &e)) throw Error(e); }
composite::Text makeStorePath(std::string_view storeDir, std::string_view type, const Hash &hash, std::string_view name) {
  composite::Text s; if (nixstore_ts_makestorepath(storeDir.data(), storeDir.size(), type.data(), type.size(), &hash, name.data(), name.size(), &s)) throw Error(s); return s;
}
composite::Text makeTextPath(std::string_view storeDir, std::string_view name, const Hash &hash, const SortedSet &refs) {
  composite::Text s; if (nixstore_ts_textpath(storeDir.data(), storeDir.size(), name.data(), name.size(), &hash, refs.rows.data(), int64_t(refs.size()), &s)) throw Error(s); return s;
}
composite::Text makeFixedOutputPath(std::string_view storeDir, std::string_view name, FileIngestionMethod method, const Hash &hash, const SortedSet &refs) {
  composite::Text s; if (nixstore_ts_fixedpath(storeDir.data(), storeDir.size(), name.data(), name.size(), int64_t(method), &hash, refs.rows.data(), int64_t(refs.size()), &s)) throw Error(s); return s;
}
composite::Text outputPathName(std::string_view drvName, std::string_view output) { composite::Text t; nixstore_tx_outputname(drvName.data(), drvName.size(), output.data(), output.size(), &t); return t; }
composite::Text makeOutputPath(std::string_view storeDir, std::string_view output, const Hash &drvHash, std::string_view drvName) {
  composite::Text s; if (nixstore_ts_outputpath(storeDir.data(), storeDir.size(), output.data(), output.size(), &drvHash, drvName.data(), drvName.size(), &s)) throw Error(s); return s;
}
composite::Text hashPlaceholder(std::string_view output) { composite::Text t; nixstore_ts_placeholder(output.data(), output.size(), &t); return t; }
composite::Text toStorePath(std::string_view storeDir, std::string_view path) { composite::Text t; if (nixstore_ts_tostorepath(storeDir.data(), storeDir.size(), path.data(), path.size(), &t)) throw Error(t); return t; }
bool isStorePath(std::string_view storeDir, std::string_view path) { return nixstore_ts_isstorepath(storeDir.data(), storeDir.size(), path.data(), path.size()); }
composite::Text storePathName(std::string_view storePath) { composite::Text t; nixstore_tx_storename(storePath.data(), storePath.size(), &t); return t; }
composite::Text storePathHashPart(std::string_view storePath) { composite::Text t; nixstore_tx_storehash(storePath.data(), storePath.size(), &t); return t; }

//===----------------------------------------------------------------------===//
// Derivations
//===----------------------------------------------------------------------===//

// What stands between a Derivation and its texts is lowered/nixstore/DrvMarshal.mlir: it reads the Derivation's rows
// where they lie, gives them to the ATerm writer (DrvUnparse.mlir) and the JSON writer (DrvJson.mlir), and takes the
// ATerm reader's strings (DrvParse.mlir).  Here: a forward each, the layouts DrvMarshal.mlir reads held by a
// static_assert, and the callbacks that make a row in the Derivation the reader fills (a row allocates).
static_assert(sizeof(Derivation) == 152 && offsetof(Derivation, outputs) == 16 && offsetof(Derivation, inputDrvs) == 32 && offsetof(Derivation, inputSrcs) == 48 &&
                  offsetof(Derivation, platform) == 64 && offsetof(Derivation, builder) == 80 && offsetof(Derivation, args) == 96 && offsetof(Derivation, env) == 112 &&
                  offsetof(Derivation, structuredAttrs) == 128 && offsetof(composite::Maybe<composite::Text>, v) == 8 &&
                  sizeof(SortedMap<DerivationOutput>::Row) == 120 && offsetof(SortedMap<DerivationOutput>::Row, second) == 16 && offsetof(DerivationOutput, kind) == 0 &&
                  offsetof(DerivationOutput, path) == 8 && offsetof(DerivationOutput, method) == 24 && offsetof(DerivationOutput, hashAlgo) == 28 &&
                  offsetof(DerivationOutput, hash) == 32 && sizeof(SortedMap<SortedSet>::Row) == 32 && sizeof(SortedMap<composite::Text>::Row) == 32 &&
                  sizeof(SortedSet) == 16 && sizeof(composite::MutableSeries<composite::Text>) == 16 && sizeof(Hash) == 68,
              "DrvMarshal.mlir reads a Derivation where it lies");
extern "C" {
void nixstore_ts_methodalgo(const DerivationOutput *o, composite::Text *out);
int64_t nixstore_ts_drvfixedpath(const DerivationOutput *o, const char *sd, int64_t sdn, const char *drvName, int64_t dn, const char *output, int64_t on, composite::Text *out);
int64_t nixstore_ts_isfixed(const Derivation *d);
void nixstore_ts_drvtext(const Derivation *d, int64_t mask, const DrvInputs *inputs, composite::Text *out);
void nixstore_ts_drvhash(const Derivation *d, int64_t mask, const DrvInputs *inputs, Hash *h);
void nixstore_ts_drvjsontext(const char *path, int64_t pn, const Derivation *d, composite::Text *out);
int64_t nixstore_ts_drvread(const char *text, int64_t n, Derivation *d, composite::Text *err);
void nixstore_drv_out(Derivation *d, const char *id, int64_t idn, int64_t kind, int64_t method, int64_t algo, const Hash *h, const char *path, int64_t pn) {
  DerivationOutput o;
  o.kind = DerivationOutput::Kind(kind), o.method = FileIngestionMethod(method), o.hashAlgo = HashAlgo(algo);
  if (h) o.hash = *h;
  if (pn) o.path = composite::Text(std::string_view(path, size_t(pn)));
  d->outputs[std::string_view(id, size_t(idn))] = composite::mv(o);
}
SortedSet *nixstore_drv_in(Derivation *d, const char *p, int64_t n) { SortedSet &s = d->inputDrvs[std::string_view(p, size_t(n))]; s = SortedSet(); return &s; }
void nixstore_set_insert(SortedSet *s, const char *p, int64_t n) { s->insert(std::string_view(p, size_t(n))); }
void nixstore_texts_append(composite::MutableSeries<composite::Text> *a, const char *p, int64_t n) { a->append(composite::Text(std::string_view(p, size_t(n)))); }
void nixstore_drv_env(Derivation *d, const char *k, int64_t kn, const char *v, int64_t vn) { d->env[std::string_view(k, size_t(kn))] = composite::Text(std::string_view(v, size_t(vn))); }
}

composite::Text DerivationOutput::methodAlgo() const { composite::Text t; nixstore_ts_methodalgo(this, &t); return t; }
composite::Text DerivationOutput::fixedPath(std::string_view storeDir, std::string_view drvName, std::string_view output) const {
  composite::Text t; if (nixstore_ts_drvfixedpath(this, storeDir.data(), storeDir.size(), drvName.data(), drvName.size(), output.data(), output.size(), &t)) throw Error(t); return t;
}
bool Derivation::isFixed() const { return nixstore_ts_isfixed(this); }
composite::Text Derivation::unparse(bool maskOutputs, const DrvInputs *actualInputs) const { composite::Text t; nixstore_ts_drvtext(this, maskOutputs, actualInputs, &t); return t; }
Hash Derivation::hashUnparsed(bool maskOutputs, const DrvInputs *actualInputs) const { Hash h; nixstore_ts_drvhash(this, maskOutputs, actualInputs, &h); return h; }
Derivation parseDerivation(std::string_view text, composite::Text name) {
  Derivation d;
  composite::Text e;
  d.name = composite::mv(name);
  if (nixstore_ts_drvread(text.data(), text.size(), &d, &e)) throw Error(e);
  return d;
}
composite::Text derivationToJSON(std::string_view storeDir, std::string_view drvPath, const Derivation &drv) { composite::Text t; nixstore_ts_drvjsontext(drvPath.data(), drvPath.size(), &drv, &t); return t; }

} // namespace nixstore
