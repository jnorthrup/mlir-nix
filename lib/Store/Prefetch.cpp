//===- Prefetch.cpp - Record and replay the file accesses of an evaluation ---------===//
//
// The list's row and order algebra is lowered/nixstore/PrefetchOps.mlir: the lines read into records, the minted bodies
// grouped by file and found by bisect, the entries split into directories and files, the ring's slot driver, the recorded
// lines, the list's text and auto's list name.  Here: the file I/O, the threads, the io_uring requests, getcwd, getenv and
// system, and the Texts the evaluator reads.
//
//===----------------------------------------------------------------------===//

#include "Composite/Mutable.h"
#include "Composite/Patricia.h"
#include "Composite/Text.h"
#include "Nix/Os.h"
#include "Nix/Prefetch.h"

#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

#ifdef MLNIX_HAVE_URING
#include <liburing.h>
#endif

namespace nixprefetch {

bool recording = false;
composite::MutableSeries<composite::Text> replayFiles;
composite::MutableSeries<ReplayHash> replayHashes;

namespace {
/// A key's bytes, copied once where they never move: the keys of the trie below live as long as the process.
const char *keep(std::string_view s) {
  char *p = static_cast<char *>(::operator new(s.size() + 1));
  memcpy(p, s.data(), s.size());
  p[s.size()] = 0;
  return p;
}

/// The replayed list, never freed (the replay thread and the prelowering helpers read it to the end): its text, an entry's
/// line end made a NUL; its records {cls, at = start << 32 | length, val}; the minted bodies by file, columns path | first
/// | count over rows.
struct Replay {
  composite::Text text;
  int64_t *recs = nullptr, *groups = nullptr, k = 0, ng = 0;
  uint32_t *rows = nullptr;
  const char *path(int64_t r) const { return text.data() + (recs[3 * r + 1] >> 32); }
  composite::Text window(int64_t r) const { return composite::Text(path(r), size_t(recs[3 * r + 1] & 0xffffffff)); }
};
Replay *list = nullptr;
} // namespace

extern "C" int64_t nixstore_pf_find(const char *text, int64_t n, const int64_t *groups, int64_t ng, const char *key, int64_t kn);
composite::Series<composite::Ptr<const uint32_t>> replayMints(std::string_view path) {
  int64_t g = list ? nixstore_pf_find(list->text.data(), list->text.size(), list->groups, list->ng, path.data(), int64_t(path.size())) : -1;
  if (g < 0) return composite::series<const uint32_t>(nullptr, 0);
  return composite::series<const uint32_t>(list->rows + list->groups[list->ng + g], uint32_t(list->groups[2 * list->ng + g]));
}

namespace {

//===----------------------------------------------------------------------===//
// Recording
//===----------------------------------------------------------------------===//

struct Trace {
  composite::MutableSeries<composite::Text> order;
  composite::Patricia<char> seen; // the lines kept so far, each once (their bytes copied where they never move)
  composite::Text file;
};
Trace *trace = nullptr; // never destroyed: it is written from an atexit handler

/// True the first time the trace meets this line, which is then kept in `seen` and appended.
bool kept(composite::Text line) {
  if (trace->seen.find(line.data(), uint32_t(line.size()))) return false;
  trace->seen.set(line.data(), uint32_t(line.size()), 1, [&] { return keep(line); });
  trace->order.append(composite::mv(line));
  return true;
}

/// `kind path [row]`, the path made absolute when the working directory is known: on the stack when it is short.
extern "C" int64_t nixstore_pf_line(int64_t kind, const char *pre, int64_t pn, int64_t slash, const char *p, int64_t pl, int64_t row,
                                    char *into, int64_t room);
composite::Text line(char kind, const char *path, int64_t row) {
  char cwd[PATH_MAX], room[512];
  bool rel = path[0] != '/' && getcwd(cwd, sizeof cwd);
  int64_t pn = rel ? int64_t(strlen(cwd)) : 0, pl = int64_t(strlen(path));
  int64_t n = nixstore_pf_line(uint8_t(kind), cwd, pn, rel, path, pl, row, room, sizeof room);
  if (n <= int64_t(sizeof room)) return composite::Text(room, size_t(n));
  composite::Text t;
  t.resize(size_t(n));
  nixstore_pf_line(uint8_t(kind), cwd, pn, rel, path, pl, row, &t[0], n);
  return t;
}

extern "C" int64_t nixstore_pf_join(const composite::Text *cells, int64_t n, char *into, int64_t room);
void save() {
  if (!trace) return;
  if (FILE *f = fopen(trace->file.c_str(), "w")) {
    static_assert(sizeof(composite::Text) == 16, "a line crosses as its bytes' pointer and count");
    int64_t n = nixstore_pf_join(trace->order.p, trace->order.size(), nullptr, 0);
    char *all = static_cast<char *>(::operator new(size_t(n) + 1));
    nixstore_pf_join(trace->order.p, trace->order.size(), all, n);
    fwrite(all, 1, size_t(n), f);
    ::operator delete(all);
    fclose(f);
  }
}

//===----------------------------------------------------------------------===//
// Replay
//===----------------------------------------------------------------------===//

/// Directory listings cannot go through the ring (no getdents opcode): a few threads do them.
void warmDirectories(const int64_t *dirs, int64_t nd, unsigned threads) {
  composite::Atomic<int64_t> next{0};
  composite::MutableSeries<nixsys::Thread> ts;
  auto run = [&] { // the next directory not taken, until none is left
    for (int64_t i; (i = next.fetch_add(1)) < nd;)
      if (DIR *d = opendir(list->path(dirs[i]))) {
        while (readdir(d)) {}
        closedir(d);
      }
  };
  for (unsigned t = 0; t < threads; t++) ts.append(nixsys::Thread::start(run));
  for (nixsys::Thread &t : ts) t.join();
}

#ifdef MLNIX_HAVE_URING
/// Files and stats through one ring, its slots driven by nixstore_pf_warm.  A file is a linked chain openat(direct) -> read
/// -> close(direct) that reads (and discards) the first 128 KiB, which is what puts the file in the page cache; a stat is
/// one statx.  A read's bytes and a stat's answer have a slot each, for this warm-up (not zeroed: the kernel writes them).
struct Ring {
  static constexpr unsigned W = 64;
  static constexpr size_t kBuf = 128 * 1024;
  io_uring ring;
  char *bytes = new char[W * kBuf];
  struct statx *stat = new struct statx[W];
  ~Ring() {
    delete[] bytes;
    delete[] stat;
  }
};
/// Record r's requests into slot `slot`: the completions it waits for.
int64_t submitEntry(void *ctx, int64_t slot, int64_t r) {
  Ring &g = *static_cast<Ring *>(ctx);
  const char *path = list->path(r);
  char kind = char(list->recs[3 * r + 2]);
  if (kind == 'F') {
    io_uring_sqe *a = io_uring_get_sqe(&g.ring);
    io_uring_prep_openat_direct(a, AT_FDCWD, path, O_RDONLY, 0, unsigned(slot)); // O_CLOEXEC is -EINVAL here
    io_uring_sqe_set_flags(a, IOSQE_IO_LINK);
    a->user_data = uint64_t(slot) << 2;
    io_uring_sqe *rd = io_uring_get_sqe(&g.ring);
    io_uring_prep_read(rd, int(slot), g.bytes + size_t(slot) * Ring::kBuf, Ring::kBuf, 0);
    io_uring_sqe_set_flags(rd, IOSQE_FIXED_FILE | IOSQE_IO_LINK);
    rd->user_data = (uint64_t(slot) << 2) | 1;
    io_uring_sqe *c = io_uring_get_sqe(&g.ring);
    io_uring_prep_close_direct(c, unsigned(slot));
    c->user_data = (uint64_t(slot) << 2) | 2;
    return 3;
  }
  io_uring_sqe *s = io_uring_get_sqe(&g.ring);
  io_uring_prep_statx(s, AT_FDCWD, path, kind == 'L' ? AT_SYMLINK_NOFOLLOW : 0, STATX_TYPE | STATX_SIZE, &g.stat[slot]);
  s->user_data = uint64_t(slot) << 2;
  return 1;
}
/// Wait for a completion; the slots of those come, in order.
int64_t reapSlots(void *ctx, int64_t *done, int64_t cap) {
  Ring &g = *static_cast<Ring *>(ctx);
  io_uring_submit_and_wait(&g.ring, 1);
  io_uring_cqe *cqe;
  unsigned head, seen = 0;
  io_uring_for_each_cqe(&g.ring, head, cqe) {
    if (seen == cap) break;
    done[seen++] = int64_t(cqe->user_data >> 2);
  }
  io_uring_cq_advance(&g.ring, seen);
  return seen;
}
extern "C" void nixstore_pf_warm(void *ctx, const int64_t *files, int64_t nf, int64_t w, int64_t (*submit)(void *, int64_t, int64_t),
                                 int64_t (*reap)(void *, int64_t *, int64_t));
void warmFiles(const int64_t *files, int64_t nf) {
  Ring g;
  if (io_uring_queue_init(Ring::W * 3, &g.ring, 0) < 0) return; // no io_uring here: the evaluator just waits
  if (io_uring_register_files_sparse(&g.ring, Ring::W) >= 0) nixstore_pf_warm(&g, files, nf, Ring::W, submitEntry, reapSlots);
  io_uring_queue_exit(&g.ring);
}
#endif

void replay(const int64_t *dirs, int64_t nd, const int64_t *files, int64_t nf) {
  nixsys::Thread dirThread = nixsys::Thread::start([=] { warmDirectories(dirs, nd, 4); });
#ifdef MLNIX_HAVE_URING
  warmFiles(files, nf);
#else
  (void)files, (void)nf;
#endif
  dirThread.join();
}

} // namespace

void noteSlow(char kind, const char *path) { kept(line(kind, path, -1)); }
void noteMintSlow(const char *path, uint32_t row) { kept(line('M', path, row)); }
bool noteRootSlow(char kind, const char *path) { return kept(line(kind, path, -1)); }
void noteKeptSlow(const char *path) { trace->order.append(line('g', path, -1)); }

/// auto: the list for this invocation (working directory + arguments) under the state directory.
extern "C" int64_t nixstore_pf_listname(const void *wins, int64_t n, char *into);
composite::Text autoSpec(int argc, char **argv) {
  struct Window {
    const char *p;
    int64_t n;
  };
  composite::MutableSeries<Window> named; // what names the list: the working directory, the arguments
  char cwd[PATH_MAX], name[32];
  if (getcwd(cwd, sizeof cwd)) named.append({cwd, int64_t(strlen(cwd))});
  for (int i = 1; i < argc; i++) named.append({argv[i], int64_t(strlen(argv[i]))});
  const char *state = getenv("MLNIX_STATE_DIR"), *home = getenv("HOME");
  composite::Text dir = state ? composite::Text(state) : composite::cat(home ? home : "/tmp", "/.cache/mlnix");
  dir += "/prefetch";
  composite::Text cmd = composite::cat("mkdir -p '", dir, "'");
  if (system(cmd.c_str()) != 0) return "";
  composite::Text file = composite::cat(dir, std::string_view(name, size_t(nixstore_pf_listname(named.p, named.size(), name))));
  return composite::cat(access(file.c_str(), R_OK) == 0 ? "replay:" : "record:", file);
}

extern "C" int64_t nixstore_pf_count(const char *text, int64_t n);
extern "C" int64_t nixstore_pf_parse(char *text, int64_t n, int64_t *recs);
extern "C" int64_t nixstore_pf_mints(const char *text, int64_t n, const int64_t *recs, int64_t k, int64_t *groups, uint32_t *rows);
extern "C" int64_t nixstore_pf_split(const int64_t *recs, int64_t k, int64_t *dirs, int64_t *files, int64_t *nfiles);
void init(int argc, char **argv) {
  const char *env = getenv("MLNIX_PREFETCH");
  if (!env) return;
  composite::Text spec(env);
  if (spec == "auto") spec = autoSpec(argc, argv);
  if (spec.rfind("record:", 0) == 0) {
    trace = new Trace();
    trace->file = composite::Text(spec.substr(7));
    recording = true;
    atexit(save);
  } else if (spec.rfind("replay:", 0) == 0 || spec.rfind("replay-wait:", 0) == 0) {
    Replay &l = *(list = new Replay());
    nixsys::readInto(spec.c_str() + spec.find(':') + 1, l.text); // no list: nothing to replay
    int64_t n = l.text.size();
    l.recs = new int64_t[3 * nixstore_pf_count(l.text.data(), n)];
    l.k = nixstore_pf_parse(n ? &l.text[0] : nullptr, n, l.recs);
    l.groups = new int64_t[3 * l.k + 1];
    l.rows = new uint32_t[l.k + 1];
    l.ng = nixstore_pf_mints(l.text.data(), n, l.recs, l.k, l.groups, l.rows);
    // a .nix file for the prelowering helpers; a hashed tree and the entries its filter kept for the prehashing helper
    for (int64_t r = 0; r < l.k; r++) {
      int64_t cls = l.recs[3 * r], val = l.recs[3 * r + 2];
      if (cls == 1 && (val & 256)) replayFiles.append(l.window(r));
      else if (cls == 3 || cls == 4) replayHashes.append({l.window(r), cls == 4, {}});
      else if (cls == 5) replayHashes[uint32_t(val)].kept.append(l.window(r));
    }
    int64_t *dirs = new int64_t[l.k + 1], *files = new int64_t[l.k + 1], nf = 0;
    int64_t nd = nixstore_pf_split(l.recs, l.k, dirs, files, &nf);
    // replay-wait: the evaluation starts when the whole list has been replayed (the best a prefetch can do)
    bool wait = spec.rfind("replay-wait:", 0) == 0;
    if (nd + nf) {
      nixsys::Thread t = nixsys::Thread::start([=] { replay(dirs, nd, files, nf); });
      if (wait) t.join();
      else t.detach();
    }
  }
}

} // namespace nixprefetch
