//===- Vocab.h - the small words a program says with: a callable passed down, a value that may be absent ---===//
//
// What std::function and std::optional were used for, in the pure zone.  Fn is a callable passed to a function that calls it before it
// returns: two words, the callable's address and a trampoline, nothing allocated and nothing owned (std::function copied the callable
// to the heap when it did not fit).  Maybe is a value or nothing, a flag beside it.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_VOCAB_H
#define COMPOSITE_VOCAB_H

#include "Composite/Core.h"

namespace composite {

template <class Sig> struct Fn;
/// A callable lent for the length of a call: the callee may call it, never keep it.  A null Fn is false and is not called.
template <class R, class... A> struct Fn<R(A...)> {
  constexpr Fn() = default;
  constexpr Fn(decltype(nullptr)) {}
  /// Any callable with this signature, by reference: it must outlive every call through the Fn.
  template <class F>
    requires(!same<bare_t<F>, Fn> && Callable<F &, A...>)
  constexpr Fn(F &&f) : obj(const_cast<void *>(static_cast<const void *>(&f))), call([](void *o, A... a) -> R {
                          return (*static_cast<remove_ref_t<F> *>(o))(fw<A>(a)...);
                        }) {}
  constexpr R operator()(A... a) const { return call(obj, fw<A>(a)...); }
  constexpr explicit operator bool() const { return call != nullptr; }

private:
  void *obj = nullptr;
  R (*call)(void *, A...) = nullptr;
};

/// A value or nothing.
template <class T> struct Maybe {
  constexpr Maybe() = default;
  constexpr Maybe(decltype(nullptr)) {}
  constexpr Maybe(T v) : has(true), v(mv(v)) {}
  constexpr explicit operator bool() const { return has; }
  constexpr T &operator*() { return v; }
  constexpr const T &operator*() const { return v; }
  constexpr T *operator->() { return &v; }
  constexpr const T *operator->() const { return &v; }
  constexpr T or_(T other) const { return has ? v : other; }
  // The words of the optional it replaces, so a caller reads the same.
  constexpr bool has_value() const { return has; }
  constexpr T &value() { return v; }
  constexpr const T &value() const { return v; }
  constexpr T value_or(T other) const { return has ? v : other; }
  constexpr bool operator==(const Maybe &o) const { return has == o.has && (!has || v == o.v); }
  constexpr bool operator!=(const Maybe &o) const { return !(*this == o); }

private:
  bool has = false;
  T v{};
};

} // namespace composite

#endif // COMPOSITE_VOCAB_H
