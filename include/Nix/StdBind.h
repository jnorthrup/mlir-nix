//===- StdBind.h - the one place the algebra meets the standard library --------------===//
//
// The algebra (Composite/*.h) includes nothing, so this adapter is on the Nix side of the line.  A structured binding is the language asking `std::tuple_size`, which only a standard header
// declares, so the glue that lets `auto [x, y] = a |j| b` destructure a packed pair lives here, in the headers of the code that wants it.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_STDBIND_H
#define NIX_STDBIND_H

#include "Composite/Pack.h"
#include "Composite/CharSeries.h"

#include <string_view>
#include <tuple>
#include <utility>

namespace std {
template <class A, class B> struct tuple_size<join::Dense<A, B>> : integral_constant<size_t, 2> {};
template <size_t I, class A, class B> struct tuple_element<I, join::Dense<A, B>> { using type = conditional_t<I == 0, A, B>; };
} // namespace std

namespace composite {
/// A window or a cursor as a std::string_view, for an API that wants one (the windows hold a pointer and a length, nothing more).
template <class W> constexpr std::string_view view(const W &w) { return {w.data(), w.size()}; }
/// A cursor's view is the characters between pos and limit (the window's own bytes are the whole root).
constexpr std::string_view view(const CharSeries &c) { return {c.data() + c.pos, c.rem()}; }
/// The other way: a window, or a cursor over it, on the characters of a std::string_view (nothing is copied).
constexpr CharWindow window(std::string_view s) { return CharWindow(s.data(), uint32_t(s.size())); }
constexpr CharSeries cseries(std::string_view s) { return CharSeries(s.data(), uint32_t(s.size())); }
} // namespace composite

#endif
