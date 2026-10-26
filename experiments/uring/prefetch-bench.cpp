// What can the storage do with the files the evaluator opens?  Reads every path in a list
// (one per line, regular files) three ways and times each, cold (the caller drops the page
// cache before each run) or hot:
//   seq      one open/read/close at a time: what the evaluator does today
//   threads  N threads doing the same
//   uring    io_uring: W files in flight, each a linked chain openat(direct) -> read -> close(direct)
//
// build: clang++ -O2 -std=c++20 prefetch-bench.cpp -o prefetch-bench -luring -pthread
// usage: prefetch-bench MODE LIST [WIDTH]
#include <liburing.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

static constexpr size_t kBuf = 256 * 1024;

static size_t readOne(const std::string &p, char *buf) {
  int fd = ::open(p.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return 0;
  ssize_t n = ::read(fd, buf, kBuf);
  ::close(fd);
  return n > 0 ? size_t(n) : 0;
}

static size_t runThreads(const std::vector<std::string> &paths, unsigned width) {
  std::atomic<size_t> next{0}, bytes{0};
  std::vector<std::thread> ts;
  for (unsigned t = 0; t < width; t++)
    ts.emplace_back([&] {
      std::vector<char> buf(kBuf);
      for (size_t i; (i = next.fetch_add(1)) < paths.size();) bytes += readOne(paths[i], buf.data());
    });
  for (auto &t : ts) t.join();
  return bytes;
}

static size_t runUring(const std::vector<std::string> &paths, unsigned width) {
  io_uring ring;
  if (io_uring_queue_init(width * 4, &ring, 0) < 0) { perror("io_uring_queue_init"); exit(1); }
  if (io_uring_register_files_sparse(&ring, width) < 0) { perror("register_files_sparse"); exit(1); }
  std::vector<std::vector<char>> bufs(width, std::vector<char>(kBuf));
  std::vector<unsigned> pending(width, 0); // CQEs still owed per slot
  std::vector<size_t> freeSlots;
  for (unsigned s = 0; s < width; s++) freeSlots.push_back(s);
  size_t next = 0, bytes = 0, inflight = 0;
  auto submitFile = [&](unsigned slot, const std::string &p) {
    io_uring_sqe *a = io_uring_get_sqe(&ring);
    io_uring_prep_openat_direct(a, AT_FDCWD, p.c_str(), O_RDONLY, 0, slot); // no O_CLOEXEC: -EINVAL on a direct descriptor
    io_uring_sqe_set_flags(a, IOSQE_IO_LINK);
    a->user_data = (uint64_t(slot) << 2) | 0;
    io_uring_sqe *r = io_uring_get_sqe(&ring);
    io_uring_prep_read(r, int(slot), bufs[slot].data(), kBuf, 0);
    io_uring_sqe_set_flags(r, IOSQE_FIXED_FILE | IOSQE_IO_LINK);
    r->user_data = (uint64_t(slot) << 2) | 1;
    io_uring_sqe *c = io_uring_get_sqe(&ring);
    io_uring_prep_close_direct(c, slot);
    c->user_data = (uint64_t(slot) << 2) | 2;
    pending[slot] = 3;
    inflight++;
  };
  while (next < paths.size() || inflight) {
    while (!freeSlots.empty() && next < paths.size()) {
      unsigned s = unsigned(freeSlots.back());
      freeSlots.pop_back();
      submitFile(s, paths[next++]);
    }
    io_uring_submit_and_wait(&ring, 1);
    io_uring_cqe *cqe;
    unsigned head, seen = 0;
    io_uring_for_each_cqe(&ring, head, cqe) {
      unsigned slot = unsigned(cqe->user_data >> 2), stage = unsigned(cqe->user_data & 3);
      if (stage == 1 && cqe->res > 0) bytes += size_t(cqe->res);
      if (cqe->res < 0 && getenv("URING_DEBUG")) {
        static int shown = 0;
        if (shown++ < 6) fprintf(stderr, "stage %u res %d (%s)\n", stage, cqe->res, strerror(-cqe->res));
      }
      if (--pending[slot] == 0) { freeSlots.push_back(slot); inflight--; }
      seen++;
    }
    io_uring_cq_advance(&ring, seen);
  }
  io_uring_queue_exit(&ring);
  return bytes;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: prefetch-bench seq|threads|uring LIST [WIDTH]\n"); return 2; }
  std::string mode = argv[1];
  unsigned width = argc > 3 ? unsigned(atoi(argv[3])) : 64;
  std::vector<std::string> paths;
  std::ifstream in(argv[2]);
  for (std::string l; std::getline(in, l);) if (!l.empty()) paths.push_back(l);
  auto t0 = std::chrono::steady_clock::now();
  size_t bytes = mode == "seq" ? runThreads(paths, 1) : mode == "threads" ? runThreads(paths, width) : runUring(paths, width);
  double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  printf("%-8s width %-3u %zu files %6.1f MB  %7.3f s\n", mode.c_str(), mode == "seq" ? 1 : width, paths.size(), bytes / 1e6, s);
}
