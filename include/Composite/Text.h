//===- Text.h - text being written: a growing run of bytes, and the numbers written into it ---===//
//
// What a std::ostringstream, a std::string built by appends and std::to_string were used for, in the pure zone.  The bytes are a
// MutableSeries of chars, written a run at a time (one capacity check a run); integers are written by hand, a digit a step.  The text is
// not NUL-terminated until cstr() asks for it, and a pointer into it holds until the next write.  Floating point is not here: a shortest
// round trip needs a real algorithm, and the evaluator writes Nix's floats where it already does.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_TEXT_H
#define COMPOSITE_TEXT_H

#include "Composite/Mutable.h"

namespace composite {

struct Text {
  Text() = default;
  Text(const char *p, uint32_t n) { put(p, n); }

  Text &put(const char *p, uint32_t n) {
    if (n) bytes.appendAll(p, n);
    return *this;
  }
  Text &put(Chars c) { return put(c.data(), c.size()); }
  /// A C string, up to its NUL.
  Text &put(const char *s) { return put(s, uint32_t(__builtin_strlen(s))); }
  Text &put(char c) {
    bytes.append(c);
    return *this;
  }
  Text &put(const Text &t) { return put(t.data(), t.size()); }
  /// The decimal digits of x, with a '-' when negative (INT64_MIN too).
  Text &putInt(int64_t x) {
    uint64_t u = x < 0 ? 0 - uint64_t(x) : uint64_t(x);
    if (x < 0) put('-');
    return putUnsigned(u);
  }
  Text &putUnsigned(uint64_t u) {
    char buf[20], *e = buf + sizeof buf, *p = e;
    do *--p = char('0' + u % 10); while (u /= 10);
    return put(p, uint32_t(e - p));
  }
  /// x in lower-case hex, at least `digits` of them (zero-padded).
  Text &putHex(uint64_t x, unsigned digits = 1) {
    static constexpr char hex[] = "0123456789abcdef";
    char buf[16], *e = buf + sizeof buf, *p = e;
    do *--p = hex[x & 15]; while ((x >>= 4) || e - p < digits);
    return put(p, uint32_t(e - p));
  }

  uint32_t size() const { return bytes.size(); }
  bool empty() const { return bytes.empty(); }
  const char *data() const { return bytes.data(); }
  Chars chars() const { return composite::chars(bytes.data(), bytes.size()); }
  /// The text as a C string: a NUL after the last byte, not counted.
  const char *cstr() {
    bytes.append(0);
    bytes.pop();
    return bytes.data();
  }
  void clear() { bytes.clear(); }
  bool operator==(const Text &o) const { return size() == o.size() && (!size() || __builtin_memcmp(data(), o.data(), size()) == 0); }

private:
  MutableSeries<char> bytes;
};

} // namespace composite

#endif // COMPOSITE_TEXT_H
