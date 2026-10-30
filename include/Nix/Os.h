//===- Os.h - what the evaluator asks of the operating system, in its own words ---===//
//
// The pure zone (Composite/*.h) includes nothing.  On this side of the line the evaluator talks to the system through the C library and
// POSIX, not the C++ library's wrappers of them: a clock is clock_gettime, read where it is wanted.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_OS_H
#define NIX_OS_H

#include <stdint.h>
#include <time.h>

namespace nixsys {

/// Nanoseconds on the monotonic clock (what std::chrono::steady_clock was read for): only differences mean anything.
inline uint64_t monotonicNs() {
  timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return uint64_t(t.tv_sec) * 1000000000u + uint64_t(t.tv_nsec);
}

} // namespace nixsys

#endif // NIX_OS_H
