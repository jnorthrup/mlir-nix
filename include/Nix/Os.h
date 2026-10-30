//===- Os.h - what the evaluator asks of the operating system, in its own words ---===//
//
// The pure zone (Composite/*.h) includes nothing.  On this side of the line the evaluator talks to the system through the C library and
// POSIX, not the C++ library's wrappers of them: a clock is clock_gettime, a thread is a pthread, a lock a pthread mutex, a wait a pthread
// condition, each a few lines where it is wanted.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_OS_H
#define NIX_OS_H

#include "Composite/Vocab.h"

#include <pthread.h>
#include <stdint.h>
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
