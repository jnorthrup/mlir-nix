// alloc-sites: which call sites allocate, by count and bytes.  A macOS interposer (DYLD_INSERT_LIBRARIES) over malloc, calloc and
// realloc that records every Nth call's stack (frame pointers: arm64 macOS keeps them everywhere, the system libraries included) and
// size, and at exit writes "count bytes evaluator pc0 pc1 ..." per distinct stack to $ALLOC_SITES_OUT, with the executable's load address so
// scripts/alloc-report.py can symbolize the pcs with atos.
//
//   cc -O2 -dynamiclib -o alloc-sites.dylib scripts/alloc-sites.c
//   ALLOC_SITES_OUT=out.txt ALLOC_SITES_EVERY=97 DYLD_INSERT_LIBRARIES=$PWD/alloc-sites.dylib build/bin/mlnix ...
#include <execinfo.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <malloc/malloc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DYLD_INTERPOSE(_replacement, _replacee)                                                                        \
  __attribute__((used)) static struct { const void *replacement, *replacee; } _interpose_##_replacee                \
      __attribute__((section("__DATA,__interpose"))) = {(const void *)(unsigned long)&_replacement,                    \
                                                         (const void *)(unsigned long)&_replacee};

enum { kDepth = 12, kSkip = 2, kSlots = 1 << 16 };
struct Site { uint64_t hash, count, bytes; void *pc[kDepth]; int n, evaluator; };
static struct Site sites[kSlots];
static atomic_flag lock = ATOMIC_FLAG_INIT;
static _Atomic uint64_t calls;
static uint64_t every = 97;
static __thread int inside; // backtrace may allocate: do not record our own allocations
static __thread int role = -1; // 1 on the evaluator thread (runWithLargeStack gives it a 1 GiB stack), 0 elsewhere

static void record(size_t size) {
  if (inside || atomic_fetch_add_explicit(&calls, 1, memory_order_relaxed) % every) return;
  inside = 1;
  void *frames[kDepth + kSkip];
  int n = backtrace(frames, kDepth + kSkip) - kSkip;
  if (n < 1) { inside = 0; return; }
  if (role < 0) role = pthread_get_stacksize_np(pthread_self()) >= ((size_t)512 << 20);
  uint64_t h = 1469598103934665603ull ^ (uint64_t)role;
  for (int i = 0; i < n; i++) h = (h ^ (uint64_t)frames[i + kSkip]) * 1099511628211ull;
  while (atomic_flag_test_and_set_explicit(&lock, memory_order_acquire)) {}
  for (uint64_t i = h;; i++) {
    struct Site *s = &sites[i & (kSlots - 1)];
    if (s->count == 0) { s->hash = h; s->n = n; s->evaluator = role; memcpy(s->pc, frames + kSkip, sizeof(void *) * (size_t)n); }
    if (s->hash == h) { s->count++; s->bytes += size; break; }
  }
  atomic_flag_clear_explicit(&lock, memory_order_release);
  inside = 0;
}

static void *my_malloc(size_t n) { record(n); return malloc(n); }
static void *my_calloc(size_t c, size_t n) { record(c * n); return calloc(c, n); }
static void *my_realloc(void *p, size_t n) { record(n); return realloc(p, n); }
DYLD_INTERPOSE(my_malloc, malloc)
DYLD_INTERPOSE(my_calloc, calloc)
DYLD_INTERPOSE(my_realloc, realloc)

__attribute__((constructor)) static void start(void) {
  const char *e = getenv("ALLOC_SITES_EVERY");
  if (e && atoi(e) > 0) every = (uint64_t)atoi(e);
}

__attribute__((destructor)) static void finish(void) {
  const char *path = getenv("ALLOC_SITES_OUT");
  if (!path) return;
  inside = 1;
  FILE *f = fopen(path, "w");
  if (!f) return;
  uintptr_t base = 0; // the executable's Mach-O header: where atos is told it was loaded (an inserted library may be image 0)
  for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++)
    if (_dyld_get_image_header(i)->filetype == MH_EXECUTE) { base = (uintptr_t)_dyld_get_image_header(i); break; }
  fprintf(f, "# every %llu calls; %llu calls; base %lx\n", (unsigned long long)every, (unsigned long long)atomic_load(&calls),
          (unsigned long)base);
  for (int i = 0; i < kSlots; i++) {
    if (!sites[i].count) continue;
    fprintf(f, "%llu %llu %d", (unsigned long long)sites[i].count, (unsigned long long)sites[i].bytes, sites[i].evaluator);
    for (int k = 0; k < sites[i].n; k++) fprintf(f, " %lx", (unsigned long)sites[i].pc[k]);
    fputc('\n', f);
  }
  fclose(f);
}
