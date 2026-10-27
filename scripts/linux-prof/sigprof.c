// A sampling profiler for hosts that have no perf (WSL2, containers).
//
//   cc -O1 -g -shared -fPIC -o libsigprof.so sigprof.c -ldl -lpthread -lrt
//   SIGPROF_OUT=run.prof LD_PRELOAD=$PWD/libsigprof.so mlnix instantiate ...
//   python3 report.py run.prof
//
// Every thread gets its own CPU-time timer (SIGEV_THREAD_ID), so a thread that is blocked costs
// nothing and a worker thread is sampled where it runs.  A process-wide ITIMER_PROF would deliver
// its signal to the main thread, which in mlnix only waits for the evaluator thread.
//
// The timers are one-shot and re-armed at the end of the handler.  Unwinding a deep stack with
// libgcc costs milliseconds; with a periodic timer the next signal would already be pending when
// the handler returns and would be taken at the same instruction, so the same place would be
// counted again and again.  Re-armed at the end, two samples are always SIGPROF_US of the
// thread's own work apart, and the handler's cost only stretches the run.
//
// Each sample is appended to the file with write() as it is taken, after a header that holds the
// executable mappings, so a crash loses nothing but the tail.  report.py symbolizes offline.
//
// SIGPROF_US sets the interval in microseconds of thread CPU time (default 2000).
// Not for programs that exec: a thread timer does not survive into the new image.
#ifndef __linux__
#error "sigprof needs Linux thread timers; on macOS use /usr/bin/sample"
#endif
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

enum { kDepth = 64 };

static int outFd = -1;
static long intervalNs = 2000 * 1000;
static __thread timer_t threadTimer;

static char *putHex(char *p, unsigned long v) {
  char digits[17];
  int n = 0;
  do {
    digits[n++] = "0123456789abcdef"[v & 15];
    v >>= 4;
  } while (v);
  while (n) *p++ = digits[--n];
  return p;
}

static void rearm(void) {
  struct itimerspec once;
  memset(&once, 0, sizeof once);
  once.it_value.tv_sec = intervalNs / 1000000000L;
  once.it_value.tv_nsec = intervalNs % 1000000000L;
  timer_settime(threadTimer, 0, &once, 0);
}

static void onProf(int sig) {
  (void)sig;
  int saved = errno;
  void *pc[kDepth];
  int n = backtrace(pc, kDepth);
  char line[32 + kDepth * 17];
  char *p = line;
  *p++ = 'S';
  *p++ = ' ';
  p = putHex(p, (unsigned long)syscall(SYS_gettid));
  for (int i = 0; i < n; i++) {
    *p++ = ' ';
    p = putHex(p, (unsigned long)pc[i]);
  }
  *p++ = '\n';
  if (write(outFd, line, (size_t)(p - line)) < 0) {
  }
  rearm();
  errno = saved;
}

static void armThisThread(void) {
  struct sigevent sev;
  memset(&sev, 0, sizeof sev);
  sev.sigev_notify = SIGEV_THREAD_ID;
  sev.sigev_signo = SIGPROF;
  sev._sigev_un._tid = (int)syscall(SYS_gettid);
  if (timer_create(CLOCK_THREAD_CPUTIME_ID, &sev, &threadTimer) != 0) return;
  rearm();
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
  if (outFd < 0) return real(th, attr, fn, arg);
  struct Start *s = (struct Start *)malloc(sizeof *s);
  s->fn = fn;
  s->arg = arg;
  return real(th, attr, trampoline, s);
}

__attribute__((constructor)) static void start(void) {
  const char *path = getenv("SIGPROF_OUT");
  if (!path) return;
  if (getenv("SIGPROF_US")) intervalNs = atol(getenv("SIGPROF_US")) * 1000;
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
  if (fd < 0) return;
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
  char head[128];
  int n = snprintf(head, sizeof head, "interval_ns %ld\nrestorer %lx\n", intervalNs, (unsigned long)got.sa_restorer);
  if (write(fd, head, (size_t)n) < 0) return;
  FILE *maps = fopen("/proc/self/maps", "r");
  char line[1024];
  while (maps && fgets(line, sizeof line, maps)) {
    char out[1100];
    n = snprintf(out, sizeof out, "M %s", line);
    if (write(fd, out, (size_t)n) < 0) break;
  }
  if (maps) fclose(maps);
  outFd = fd;
  armThisThread();
}

__attribute__((destructor)) static void finish(void) {
  if (outFd >= 0) signal(SIGPROF, SIG_IGN);
}
