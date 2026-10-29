//===- Prefetch.cpp - Record and replay the file accesses of an evaluation ---------===//

#include "Composite/Mutable.h"
#include "Nix/Prefetch.h"

#include <atomic>
#include <chrono>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <fstream>
#include <memory>
#include <string>
#include <thread>
#include <unistd.h>
#include <unordered_set>
#include <vector>

#ifdef MLNIX_HAVE_URING
#include <liburing.h>
#endif

namespace nixprefetch {

bool recording = false;
composite::MutableSeries<std::string> replayFiles;
std::unordered_map<std::string, composite::MutableSeries<uint32_t>> replayMints;

namespace {

//===----------------------------------------------------------------------===//
// Recording
//===----------------------------------------------------------------------===//

struct Trace {
  composite::MutableSeries<std::string> order;
  std::unordered_set<std::string> seen;
  std::string file;
};
Trace *trace = nullptr; // never destroyed: it is written from an atexit handler

std::string absolute(const char *p) {
  if (p[0] == '/') return p;
  char cwd[PATH_MAX];
  if (!getcwd(cwd, sizeof cwd)) return p;
  return std::string(cwd) + "/" + p;
}

void save() {
  if (!trace) return;
  if (FILE *f = fopen(trace->file.c_str(), "w")) {
    for (const std::string &l : trace->order) fprintf(f, "%s\n", l.c_str());
    fclose(f);
  }
}

//===----------------------------------------------------------------------===//
// Replay
//===----------------------------------------------------------------------===//

struct Entry {
  char kind;
  std::string path;
};

/// Directory listings cannot go through the ring (no getdents opcode): a few threads do them.
void warmDirectories(const composite::MutableSeries<std::string> &dirs, unsigned threads) {
  std::atomic<size_t> next{0};
  composite::MutableSeries<std::thread> ts;
  for (unsigned t = 0; t < threads; t++)
    ts.emplace([&] {
      for (size_t i; (i = next.fetch_add(1)) < dirs.size();)
        if (DIR *d = opendir(dirs[i].c_str())) {
          while (readdir(d)) {}
          closedir(d);
        }
    });
  for (std::thread &t : ts) t.join();
}

#ifdef MLNIX_HAVE_URING
/// Files and stats through one ring.  A file is a linked chain openat(direct) -> read -> close(direct)
/// that reads (and discards) the first 128 KiB, which is what puts the file in the page cache; a
/// stat is one statx.  `W` slots are in flight at once, each reused as soon as its chain completes.
void warmFiles(const composite::MutableSeries<Entry> &es) {
  constexpr unsigned W = 64;
  constexpr size_t kBuf = 128 * 1024;
  io_uring ring;
  if (io_uring_queue_init(W * 3, &ring, 0) < 0) return; // no io_uring here: the evaluator just waits
  if (io_uring_register_files_sparse(&ring, W) < 0) {
    io_uring_queue_exit(&ring);
    return;
  }
  std::unique_ptr<char[]> bufs(new char[W * kBuf]);
  std::unique_ptr<struct statx[]> stx(new struct statx[W]);
  unsigned pending[W] = {};
  composite::MutableSeries<unsigned> freeSlots;
  for (unsigned s = 0; s < W; s++) freeSlots.append(s);
  size_t next = 0, inflight = 0;
  auto submit = [&](unsigned slot, const Entry &e) {
    if (e.kind == 'F') {
      io_uring_sqe *a = io_uring_get_sqe(&ring);
      io_uring_prep_openat_direct(a, AT_FDCWD, e.path.c_str(), O_RDONLY, 0, slot); // O_CLOEXEC is -EINVAL here
      io_uring_sqe_set_flags(a, IOSQE_IO_LINK);
      a->user_data = uint64_t(slot) << 2;
      io_uring_sqe *r = io_uring_get_sqe(&ring);
      io_uring_prep_read(r, int(slot), bufs.get() + size_t(slot) * kBuf, kBuf, 0);
      io_uring_sqe_set_flags(r, IOSQE_FIXED_FILE | IOSQE_IO_LINK);
      r->user_data = (uint64_t(slot) << 2) | 1;
      io_uring_sqe *c = io_uring_get_sqe(&ring);
      io_uring_prep_close_direct(c, slot);
      c->user_data = (uint64_t(slot) << 2) | 2;
      pending[slot] = 3;
    } else {
      io_uring_sqe *s = io_uring_get_sqe(&ring);
      io_uring_prep_statx(s, AT_FDCWD, e.path.c_str(), e.kind == 'L' ? AT_SYMLINK_NOFOLLOW : 0, STATX_TYPE | STATX_SIZE, &stx[slot]);
      s->user_data = uint64_t(slot) << 2;
      pending[slot] = 1;
    }
    inflight++;
  };
  while (next < es.size() || inflight) {
    while (!freeSlots.empty() && next < es.size()) {
      const Entry &e = es[next++];
      if (e.kind == 'D') continue;
      unsigned slot = freeSlots.back();
      freeSlots.pop();
      submit(slot, e);
    }
    if (!inflight) break;
    io_uring_submit_and_wait(&ring, 1);
    io_uring_cqe *cqe;
    unsigned head, seen = 0;
    io_uring_for_each_cqe(&ring, head, cqe) {
      unsigned slot = unsigned(cqe->user_data >> 2);
      if (--pending[slot] == 0) {
        freeSlots.append(slot);
        inflight--;
      }
      seen++;
    }
    io_uring_cq_advance(&ring, seen);
  }
  io_uring_queue_exit(&ring);
}
#endif

void replay(composite::MutableSeries<Entry> es) {
  auto t0 = std::chrono::steady_clock::now();
  composite::MutableSeries<std::string> dirs;
  for (const Entry &e : es)
    if (e.kind == 'D') dirs.append(e.path);
  std::thread dirThread([dirs = std::move(dirs)] { warmDirectories(dirs, 4); });
#ifdef MLNIX_HAVE_URING
  warmFiles(es);
#endif
  dirThread.join();
  if (getenv("MLNIX_PREFETCH_DEBUG"))
    fprintf(stderr, "prefetch: %zu entries in %.3f s\n", size_t(es.size()), std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
}

} // namespace

void noteSlow(char kind, const char *path) {
  std::string line;
  line.push_back(kind);
  line.push_back(' ');
  line += absolute(path);
  if (trace->seen.insert(line).second) trace->order.append(std::move(line));
}

void noteMintSlow(const char *path, uint32_t row) {
  std::string line = "M " + absolute(path) + " " + std::to_string(row);
  if (trace->seen.insert(line).second) trace->order.append(std::move(line));
}

/// auto: the list for this invocation (working directory + arguments) under the state directory.
std::string autoSpec(int argc, char **argv) {
  uint64_t h = 1469598103934665603ull; // FNV-1a
  auto mix = [&](const char *s) {
    for (; *s; s++) h = (h ^ uint8_t(*s)) * 1099511628211ull;
    h = (h ^ 0xff) * 1099511628211ull;
  };
  char cwd[PATH_MAX];
  if (getcwd(cwd, sizeof cwd)) mix(cwd);
  for (int i = 1; i < argc; i++) mix(argv[i]);
  const char *state = getenv("MLNIX_STATE_DIR"), *home = getenv("HOME");
  std::string dir = state ? std::string(state) : std::string(home ? home : "/tmp") + "/.cache/mlnix";
  dir += "/prefetch";
  std::string cmd = "mkdir -p '" + dir + "'";
  if (system(cmd.c_str()) != 0) return "";
  char name[32];
  snprintf(name, sizeof name, "/%016llx.list", (unsigned long long)h);
  std::string file = dir + name;
  return (access(file.c_str(), R_OK) == 0 ? "replay:" : "record:") + file;
}

void init(int argc, char **argv) {
  const char *env = getenv("MLNIX_PREFETCH");
  if (!env) return;
  std::string spec = env;
  if (spec == "auto") spec = autoSpec(argc, argv);
  if (spec.rfind("record:", 0) == 0) {
    trace = new Trace();
    trace->file = spec.substr(7);
    recording = true;
    atexit(save);
  } else if (spec.rfind("replay:", 0) == 0 || spec.rfind("replay-wait:", 0) == 0) {
    composite::MutableSeries<Entry> es;
    std::ifstream in(spec.substr(spec.find(':') + 1));
    for (std::string l; std::getline(in, l);)
      if (l.size() > 2 && l[1] == ' ' && l[0] == 'M') { // a minted body: for the prelowering helpers, nothing to read ahead
        size_t sp = l.rfind(' ');
        if (sp > 2) replayMints[l.substr(2, sp - 2)].append(uint32_t(strtoul(l.c_str() + sp + 1, nullptr, 10)));
      } else if (l.size() > 2 && l[1] == ' ') {
        es.append({l[0], l.substr(2)});
        if (l[0] == 'F' && l.size() > 6 && l.compare(l.size() - 4, 4, ".nix") == 0) replayFiles.append(l.substr(2));
      }
    // replay-wait: the evaluation starts when the whole list has been replayed (the best a prefetch can do)
    bool wait = spec.rfind("replay-wait:", 0) == 0;
    if (!es.empty()) {
      std::thread t(replay, std::move(es));
      if (wait) t.join();
      else t.detach();
    }
  }
}

} // namespace nixprefetch
