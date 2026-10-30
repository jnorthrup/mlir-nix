//===- Numbers.h - numbers as the C library read them, by the facets of CharSeries ---===//
//
// strtoull, strtoll, atoll, atoi and the stoul family read a number out of text: whitespace, a sign, digits, a value that saturates, and
// where the reading stopped.  CharSeries has that as a facet (Integer<Base, Signed> in Composite/CharSeries.h), checked against the C
// library on 400,000 random strings in five bases (scripts/charseries-check.cc), so the evaluator asks the facet and calls none of them,
// and the bytes need no NUL after them: a window is read where it lies.  What stays with libc is the float: strtod is a correctly rounded
// decimal-to-double conversion, which is not hand-rolled here.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_NUMBERS_H
#define NIX_NUMBERS_H

#include "Composite/CharSeries.h"
#include "Composite/Text.h"

#include <stdint.h>
#include <stdexcept> // before the test of _LIBCPP_VERSION below, which this header defines in libc++

namespace nixsys {

/// The decimal number at the start of some bytes as strtoull (unsigned) and strtoll (signed) read it: leading whitespace, a sign, digits.
/// The reading says its value (the bits of a long long for a signed one), whether the value saturated (overflow: C's ERANGE) and how many
/// bytes it used (consumed: 0 when there was no number, and then the value is 0).
template <class V> requires composite::ByteView<V> inline composite::text::Reading readUnsigned(const V &v) {
  return composite::facet<composite::text::Integer<10, false>>(composite::chars(static_cast<const char *>(v.data()), uint32_t(v.size())));
}
template <class V> requires composite::ByteView<V> inline composite::text::Reading readSigned(const V &v) {
  return composite::facet<composite::text::Integer<10, true>>(composite::chars(static_cast<const char *>(v.data()), uint32_t(v.size())));
}
/// The same for a C string (the environment, an argument).
inline composite::text::Reading readUnsigned(const char *z) { return readUnsigned(composite::chars(z, uint32_t(__builtin_strlen(z)))); }
inline composite::text::Reading readSigned(const char *z) { return readSigned(composite::chars(z, uint32_t(__builtin_strlen(z)))); }

/// What the standard library's stoul, stoull and stoll made of a reading: its value, or the two exceptions they threw, std::invalid_argument
/// when nothing was read and std::out_of_range when the value did not fit, with the words of the library (libc++ says why, libstdc++ only
/// names the function).  `name` is the function being stood in for.
inline uint64_t stoValue(const char *name, const composite::text::Reading &r) {
  if (r.overflow || r.consumed == 0) {
    composite::Text what(name);
#ifdef _LIBCPP_VERSION
    what.put(r.overflow ? ": out of range" : ": no conversion");
#endif
    if (r.overflow) throw std::out_of_range(what.c_str());
    throw std::invalid_argument(what.c_str());
  }
  return r.value;
}

} // namespace nixsys

#endif
