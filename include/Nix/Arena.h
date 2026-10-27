//===- Arena.h - The evaluator's bump arena, faulted in ahead of use -----*- C++ -*-===//
//
// Everything the evaluator builds (values, frames, attribute sets, strings, lists) lives in one bump arena that is
// never freed.  The first touch of each of its pages is a page fault: the kernel zero-fills the page, which on a
// NixOS evaluation is 1.1 GB of the 1.5 GB footprint and a tenth of the run, spent by the one thread that
// evaluates while the other cores idle.
//
// The slabs are therefore carved one after another, 4 MiB at a time, from large ranges of address space reserved
// with mmap, and a helper thread touches the pages of the slab after the one being filled, so that by the time the
// evaluator gets there they are already resident.  The touch is an atomic add of zero: it faults the page in for
// writing and cannot change a byte the evaluator may be storing at the same time.  Nothing is ever freed.
//
// Carving the slabs without the helper is slower than the malloc slabs it replaced (+2%); the helper is what pays.
// MLNIX_NO_PREFAULT=1 switches it off, to measure.
//
//===----------------------------------------------------------------------===//
#ifndef NIX_ARENA_H
#define NIX_ARENA_H

#include "llvm/Support/Allocator.h"
#include "llvm/Support/ErrorHandling.h"
#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <mutex>
#include <sys/mman.h>
#include <thread>
#include <unistd.h>

namespace nixev {

namespace arena_detail {

inline size_t pageSize() {
  static const size_t page = static_cast<size_t>(sysconf(_SC_PAGESIZE));
  return page;
}

/// One helper thread that makes ranges of fresh memory resident.
class Prefaulter {
public:
  static Prefaulter &get() {
    static Prefaulter *p = new Prefaulter(); // never destroyed: the thread may outlive main()
    return *p;
  }
  void request(char *p, size_t n) {
    if (disabled) return;
    {
      std::lock_guard<std::mutex> g(m);
      queue.emplace_back(p, n);
      if (!started) {
        started = true;
        std::thread([this] { run(); }).detach();
      }
    }
    cv.notify_one();
  }

private:
  Prefaulter() : disabled(getenv("MLNIX_NO_PREFAULT") != nullptr) {}
  void run() {
    for (;;) {
      std::pair<char *, size_t> job;
      {
        std::unique_lock<std::mutex> g(m);
        cv.wait(g, [this] { return !queue.empty(); });
        job = queue.front();
        queue.pop_front();
      }
      touch(job.first, job.second);
    }
  }
  static void touch(char *p, size_t n) {
#if defined(__linux__) && defined(MADV_POPULATE_WRITE)
    if (madvise(p, n, MADV_POPULATE_WRITE) == 0) return;
#endif
    const size_t page = pageSize();
    for (size_t off = 0; off < n; off += page)
      __atomic_fetch_add(reinterpret_cast<uint8_t *>(p + off), uint8_t(0), __ATOMIC_RELAXED);
  }
  std::mutex m;
  std::condition_variable cv;
  std::deque<std::pair<char *, size_t>> queue;
  bool started = false;
  const bool disabled;
};

} // namespace arena_detail

/// The slab source of the arena.  Slabs are page multiples, carved from reserved ranges of address space in order.
class PrefaultSlabs {
public:
  static constexpr size_t kSlab = 4u << 20;         // the size of an ordinary slab, and how far ahead pages are touched
  static constexpr size_t kChunk = size_t(1) << 30; // address space reserved at a time

  void *Allocate(size_t size, size_t /*alignment: slabs are page aligned*/) {
    const size_t page = arena_detail::pageSize();
    size = (size + page - 1) & ~(page - 1);
    if (static_cast<size_t>(end - cur) < size) {
      size_t chunk = std::max(kChunk, size);
#ifdef __linux__
      // Transparent huge pages back a 2 MiB aligned range with 2 MiB pages: 512 times fewer faults, which the helper
      // takes for the evaluator anyway, but also one TLB entry for 2 MiB of values.  Most kernels ship THP as "madvise".
      constexpr size_t kHuge = size_t(2) << 20;
      size_t reserve = chunk + kHuge;
#else
      size_t reserve = chunk;
#endif
      void *p = mmap(nullptr, reserve, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
      if (p == MAP_FAILED) llvm::report_fatal_error("cannot reserve memory for the evaluator");
      cur = static_cast<char *>(p);
#ifdef __linux__
      cur = reinterpret_cast<char *>((reinterpret_cast<uintptr_t>(cur) + kHuge - 1) & ~(kHuge - 1));
      madvise(cur, chunk, MADV_HUGEPAGE); // advice only: failure changes nothing
#endif
      end = cur + chunk;
    }
    char *slab = cur;
    cur += size;
    // The evaluator will fill this slab; make the next one resident meanwhile.  Not for the first: a run that never
    // needs a second slab (`eval -E 1`) should not pay for one.
    if (carved++ > 0) {
      size_t ahead = std::min<size_t>(kSlab, static_cast<size_t>(end - cur));
      if (ahead >= page) arena_detail::Prefaulter::get().request(cur, ahead & ~(page - 1));
    }
    return slab;
  }
  void Deallocate(const void *, size_t, size_t) {} // never freed

private:
  char *cur = nullptr;
  char *end = nullptr;
  unsigned carved = 0;
};

/// The evaluator's arena: 4 MiB slabs that do not grow; an allocation over 256 KiB gets a slab of its own.
using Arena = llvm::BumpPtrAllocatorImpl<PrefaultSlabs, PrefaultSlabs::kSlab, 256u << 10, size_t(1) << 20>;

} // namespace nixev

#endif // NIX_ARENA_H
