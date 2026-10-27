// A sampling profiler for hosts that have no perf (WSL2, containers).
//
//   cc -O1 -g -shared -fPIC -o libsigprof.so sigprof.c -ldl -lpthread -lrt
//   SIGPROF_OUT=run.prof LD_PRELOAD=$PWD/libsigprof.so mlnix instantiate ...
//   python3 report.py run.prof
//
// Every thread gets its own CPU-time timer (SIGEV_THREAD_ID), so a thread that is blocked costs
// nothing and a worker thread is sampled where it runs.  A process-wide ITIMER_PROF would deliver
// its signal to the main thread, which in mlnix only waits for the evaluator thread.  The handler
// stores the stack; the destructor writes the stacks and /proc/self/maps, and report.py
// symbolizes them offline.
//
// SIGPROF_US sets the interval in microseconds of thread CPU time (default 1000).
// Not for programs that exec: a thread timer does not survive into the new image.
#ifndef __linux__
#error "sigprof needs Linux thread timers; on macOS use /usr/bin/sample"
#endif
#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

enum { kMaxSamples = 1 << 20, kDepth = 64 };

struct Sample {
  int tid;
  int depth;
  void *pc[kDepth];
};

static struct Sample *samples;
static int taken;
static long intervalNs = 1000 * 1000;
static void *restorer;

static void onProf(int sig) {
  (void)sig;
  int i = __atomic_fetch_add(&taken, 1, __ATOMIC_RELAXED);
  if (i >= kMaxSamples) return;
  samples[i].tid = (int)syscall(SYS_gettid);
  samples[i].depth = backtrace(samples[i].pc, kDepth);
}

static void armThisThread(void) {
  struct sigevent sev;
  memset(&sev, 0, sizeof sev);
  sev.sigev_notify = SIGEV_THREAD_ID;
  sev.sigev_signo = SIGPROF;
  sev._sigev_un._tid = (int)syscall(SYS_gettid);
  timer_t timer;
  if (timer_create(CLOCK_THREAD_CPUTIME_ID, &sev, &timer) != 0) return;
  struct itimerspec its;
  its.it_interval.tv_sec = intervalNs / 1000000000L;
  its.it_interval.tv_nsec = intervalNs % 1000000000L;
  its.it_value = its.it_interval;
  timer_settime(timer, 0, &its, 0);
}

struct Start {
  void *(*fn)(void *);
  void *arg;
};

static void *trampoline(void *p) {
  struct Start s = *(struct Start *)p;
  free(p);
  armThisThread();
  return s.fn(s.arg);
}

int pthread_create(pthread_t *th, const pthread_attr_t *attr, void *(*fn)(void *), void *arg) {
  static int (*real)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
  if (!real) real = (int (*)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *))dlsym(RTLD_NEXT, "pthread_create");
  if (!samples) return real(th, attr, fn, arg);
  struct Start *s = (struct Start *)malloc(sizeof *s);
  s->fn = fn;
  s->arg = arg;
  return real(th, attr, trampoline, s);
}

__attribute__((constructor)) static void start(void) {
  if (!getenv("SIGPROF_OUT")) return;
  if (getenv("SIGPROF_US")) intervalNs = atol(getenv("SIGPROF_US")) * 1000;
  samples = (struct Sample *)mmap(0, sizeof(struct Sample) * kMaxSamples, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
  if (samples == MAP_FAILED) {
    samples = 0;
    return;
  }
  void *warm[8]; // load the unwinder before the first signal can arrive
  backtrace(warm, 8);
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = onProf;
  sa.sa_flags = SA_RESTART;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGPROF, &sa, 0);
  struct sigaction got;
  sigaction(SIGPROF, 0, &got);
  restorer = (void *)got.sa_restorer;
  armThisThread();
}

__attribute__((destructor)) static void finish(void) {
  const char *path = getenv("SIGPROF_OUT");
  if (!path || !samples) return;
  signal(SIGPROF, SIG_IGN);
  FILE *f = fopen(path, "w");
  if (!f) return;
  int n = taken < kMaxSamples ? taken : kMaxSamples;
  fprintf(f, "interval_ns %ld\nrestorer %lx\nsamples %d\n", intervalNs, (unsigned long)restorer, n);
  for (int i = 0; i < n; i++) {
    fprintf(f, "S %d", samples[i].tid);
    for (int j = 0; j < samples[i].depth; j++) fprintf(f, " %lx", (unsigned long)samples[i].pc[j]);
    fputc('\n', f);
  }
  FILE *maps = fopen("/proc/self/maps", "r");
  char line[1024];
  while (maps && fgets(line, sizeof line, maps)) fprintf(f, "M %s", line);
  if (maps) fclose(maps);
  fclose(f);
}
