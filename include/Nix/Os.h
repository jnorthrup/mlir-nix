//===- Os.h - what the evaluator asks of the operating system, in its own words ---===//
//
// The pure zone (Composite/*.h) includes nothing.  On this side of the line the evaluator talks to the system through the C library and
// POSIX, not the C++ library's wrappers of them: a clock is clock_gettime, a thread is a pthread, a lock a pthread mutex, a wait a pthread
// condition, each a few lines where it is wanted.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_OS_H
#define NIX_OS_H

#include "Composite/Text.h"
#include "Composite/Vocab.h"

#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

namespace nixsys {

/// Nanoseconds on the monotonic clock (what std::chrono::steady_clock was read for): only differences mean anything.
inline uint64_t monotonicNs() {
  timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return uint64_t(t.tv_sec) * 1000000000u + uint64_t(t.tv_nsec);
}

/// The processors online (what std::thread::hardware_concurrency was), at least 1.
inline unsigned processors() {
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n > 0 ? unsigned(n) : 1u;
}

/// Bytes to standard output: the C library's stdout, which std::cout wrote through (the streams were synced to it).
inline void toStdout(const char *p, size_t n) { fwrite(p, 1, n, stdout); }
/// A line to standard output: the text and a newline.
inline void lineToStdout(const char *p, size_t n) {
  fwrite(p, 1, n, stdout);
  fputc('\n', stdout);
}
/// Bytes to standard error, at once (stdio's stderr is unbuffered), after what is pending on standard output: std::cerr was tied to
/// std::cout, so a warning or a trace printed between two writes of a result stays between them when both go to one pipe.
inline void toStderr(const char *p, size_t n) {
  fflush(stdout);
  fwrite(p, 1, n, stderr);
}
/// A line to standard error: the text and a newline, in one write.
inline void lineToStderr(const char *p, size_t n) {
  char *line = static_cast<char *>(malloc(n + 1));
  __builtin_memcpy(line, p, n);
  line[n] = '\n';
  toStderr(line, n + 1);
  free(line);
}

/// The same for any bytes (a Text, a window, a string_view) and for a C string.
template <class V> requires composite::ByteView<V> inline void toStdout(const V &v) { toStdout(v.data(), v.size()); }
template <class V> requires composite::ByteView<V> inline void lineToStdout(const V &v) { lineToStdout(v.data(), v.size()); }
template <class V> requires composite::ByteView<V> inline void toStderr(const V &v) { toStderr(v.data(), v.size()); }
template <class V> requires composite::ByteView<V> inline void lineToStderr(const V &v) { lineToStderr(v.data(), v.size()); }
inline void toStdout(const char *s) { toStdout(s, __builtin_strlen(s)); }
inline void lineToStdout(const char *s) { lineToStdout(s, __builtin_strlen(s)); }
inline void toStderr(const char *s) { toStderr(s, __builtin_strlen(s)); }
inline void lineToStderr(const char *s) { lineToStderr(s, __builtin_strlen(s)); }

/// A C string for a system call, from bytes that need not end in a NUL.  A Text always does, and is used as it lies; other bytes (a window, a
/// string_view) are copied, onto the stack when they are short: `open(nixsys::CStr(path), ...)`.  Not copyable: the pointer is the CStr's own.
class CStr {
public:
  CStr(const char *s) : p(s) {}
  CStr(const composite::Text &t) : p(t.c_str()) {}
  template <class V> requires(composite::ByteView<V> && !composite::same<V, composite::Text>) CStr(const V &v) {
    size_t n = static_cast<size_t>(v.size());
    const char *d = static_cast<const char *>(v.data());
    if (n < sizeof buf) {
      __builtin_memcpy(buf, d, n);
      buf[n] = 0;
      p = buf;
    } else {
      big.put(d, n);
      p = big.c_str();
    }
  }
  CStr(const CStr &) = delete;
  CStr &operator=(const CStr &) = delete;
  operator const char *() const { return p; }
  const char *c_str() const { return p; }

private:
  const char *p = nullptr;
  char buf[512];
  composite::Text big;
};

/// The bytes of a descriptor to its end, appended to `into` (what a stream's rdbuf copied); false when a read fails, the bytes before it kept.
inline bool readInto(int fd, composite::Text &into) {
  char buf[65536];
  for (;;) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) return false;
    if (n == 0) return true;
    into.put(buf, uint32_t(n));
  }
}
/// The bytes of the file at `path`, appended to `into` (what an ifstream's rdbuf copied); false when it cannot be opened or read.
inline bool readInto(const char *path, composite::Text &into) {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return false;
  bool ok = readInto(fd, into);
  close(fd);
  return ok;
}

/// The same for a path that is any bytes (a Text, a window, a string_view).
template <class V> requires composite::ByteView<V> inline bool readInto(const V &path, composite::Text &into) {
  return readInto(static_cast<const char *>(CStr(path)), into);
}

/// A mutual-exclusion lock (what std::mutex was).
struct Lock {
  Lock() { pthread_mutex_init(&m, nullptr); }
  ~Lock() { pthread_mutex_destroy(&m); }
  Lock(const Lock &) = delete;
  Lock &operator=(const Lock &) = delete;
  void lock() { pthread_mutex_lock(&m); }
  void unlock() { pthread_mutex_unlock(&m); }
  pthread_mutex_t m;
};

/// A lock held for a scope (what std::lock_guard and std::unique_lock were).
struct Held {
  explicit Held(Lock &l) : l(l) { l.lock(); }
  ~Held() { l.unlock(); }
  Held(const Held &) = delete;
  Held &operator=(const Held &) = delete;
  Lock &l;
};

/// A condition waited for under a lock (what std::condition_variable was): the waiter holds the lock, the one who makes the condition true
/// changes it under the lock (or takes the lock after changing it) and then signals, so no wake-up is lost.
struct Signal {
  Signal() { pthread_cond_init(&c, nullptr); }
  ~Signal() { pthread_cond_destroy(&c); }
  Signal(const Signal &) = delete;
  Signal &operator=(const Signal &) = delete;
  /// Until `ready()` is true, with `l` held (as the caller holds it).
  template <class Ready> void waitFor(Lock &l, Ready ready) {
    while (!ready()) pthread_cond_wait(&c, &l.m);
  }
  void notifyAll() { pthread_cond_broadcast(&c); }
  void notifyOne() { pthread_cond_signal(&c); }
  pthread_cond_t c;
};

/// A thread running a callable it owns (what std::thread was).  Its owner joins it or lets it go (detach); one that is neither when its
/// owner goes is let go.  `stack` asks for a stack of that many bytes (0: the system's default).
struct Thread {
  Thread() = default;
  Thread(const Thread &) = delete;
  Thread &operator=(const Thread &) = delete;
  Thread(Thread &&o) : id(o.id), live(o.live) { o.live = false; }
  Thread &operator=(Thread &&o) {
    if (this != &o) {
      detach();
      id = o.id;
      live = o.live;
      o.live = false;
    }
    return *this;
  }
  ~Thread() { detach(); }

  /// f moved to the heap and run there; false (and nothing running) when the system makes no thread.
  template <class F> static Thread start(F f, size_t stack = 0) {
    Thread t;
    F *owned = new F(composite::mv(f));
    pthread_attr_t a;
    pthread_attr_init(&a);
    if (stack) pthread_attr_setstacksize(&a, stack);
    auto run = [](void *p) -> void * {
      composite::Own<F> fn(static_cast<F *>(p)); // the thread's now: deleted when it returns
      (*fn)();
      return nullptr;
    };
    if (pthread_create(&t.id, &a, run, owned) == 0) t.live = true;
    else delete owned;
    pthread_attr_destroy(&a);
    return t;
  }
  explicit operator bool() const { return live; }
  void join() {
    if (live) pthread_join(id, nullptr);
    live = false;
  }
  void detach() {
    if (live) pthread_detach(id);
    live = false;
  }

private:
  pthread_t id{};
  bool live = false;
};

} // namespace nixsys

#endif // NIX_OS_H
