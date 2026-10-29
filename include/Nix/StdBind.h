//===- StdBind.h - the one place the algebra meets the standard library --------------===//
//
// The algebra (Composite/*.h) includes nothing, so this adapter is on the Nix side of the line.  A structured binding is the language asking `std::tuple_size`, which only a standard header
// declares, so the glue that lets `auto [x, y] = a |j| b` destructure a packed pair lives here, in the headers of the code that wants it.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_STDBIND_H
#define NIX_STDBIND_H

#include "Composite/Pack.h"
#include "Composite/Series.h"

#include <string_view>
#include <tuple>
#include <utility>

namespace std {
template <class A, class B> struct tuple_size<join::Dense<A, B>> : integral_constant<size_t, 2> {};
template <size_t I, class A, class B> struct tuple_element<I, join::Dense<A, B>> { using type = conditional_t<I == 0, A, B>; };
} // namespace std

namespace composite {
/// A window as a std::string_view, for an API that wants one (a window holds a pointer and a length, nothing more).  Text with a cursor is
/// cast down to its window first (CharSeries::window(): the characters between pos and limit).
template <class W> constexpr std::string_view view(const W &w) { return {w.data(), w.size()}; }
/// The other way: the characters of a std::string_view as the hot Series<char> (nothing is copied); a CharSeries is made from one.
constexpr Chars chars(std::string_view s) { return series(s.data(), uint32_t(s.size())); }
} // namespace composite

#endif
