//===- Vocab.h - the small words a program says with: a callable passed down, a value that may be absent ---===//
//
// What std::function, std::optional and std::unique_ptr were used for, in the pure zone.  Fn is a callable passed to a function that calls
// it before it returns: two words, the callable's address and a trampoline, nothing allocated and nothing owned (std::function copied the
// callable to the heap when it did not fit).  Maybe is a value or nothing, a flag beside it.  Own is the one owner of an object made with
// the language's new: a pointer, moved and never copied, that deletes what it holds when it goes.
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

/// The one owner of an object made with new.  A pointer is lent out with get(); the object goes with its owner, or is given up with
/// release().  T may be incomplete where an Own of it is declared, as long as it is complete where the Own is destroyed.
template <class T> struct Own {
  constexpr Own() = default;
  constexpr Own(decltype(nullptr)) {}
  explicit constexpr Own(T *p) : p(p) {}
  Own(const Own &) = delete;
  Own &operator=(const Own &) = delete;
  constexpr Own(Own &&o) : p(o.p) { o.p = nullptr; }
  /// From an owner of a derived type.
  template <class U> constexpr Own(Own<U> &&o) : p(o.release()) {}
  Own &operator=(Own &&o) {
    if (this != &o) {
      drop();
      p = o.p;
      o.p = nullptr;
    }
    return *this;
  }
  Own &operator=(decltype(nullptr)) {
    drop();
    p = nullptr;
    return *this;
  }
  ~Own() { drop(); }
  constexpr T *get() const { return p; }
  constexpr T *operator->() const { return p; }
  constexpr T &operator*() const { return *p; }
  constexpr explicit operator bool() const { return p != nullptr; }
  /// The object, no longer owned here.
  constexpr T *release() { return exchange(p, nullptr); }

private:
  void drop() {
    static_assert(sizeof(T) > 0, "an Own's object must be complete where it is deleted"); // delete of an incomplete type runs no destructor
    delete p;
  }
  T *p = nullptr;
};
/// A T made with new, owned: what std::make_unique made.
template <class T, class... A> Own<T> own(A &&...a) { return Own<T>(new T(fw<A>(a)...)); }

/// A word read and written by more than one thread: the compiler's __atomic builtins on it (what std::atomic was), sequentially consistent
/// unless an order is given.  Waiting for a change is not here: that is the system's (Nix/Os.h, a lock and a signal).
template <class T> struct Atomic {
  static_assert(plainData<T> && sizeof(T) <= 8, "a word");
  constexpr Atomic() = default;
  constexpr Atomic(T v) : v(v) {}
  Atomic(const Atomic &) = delete;
  Atomic &operator=(const Atomic &) = delete;
  T load(int order = __ATOMIC_SEQ_CST) const { return __atomic_load_n(&v, order); }
  void store(T x, int order = __ATOMIC_SEQ_CST) { __atomic_store_n(&v, x, order); }
  T fetch_add(T d, int order = __ATOMIC_SEQ_CST) { return __atomic_fetch_add(&v, d, order); }
  /// x for the old value, if the value is still `expected`; otherwise false, and `expected` is what the value is.
  bool compare_exchange(T &expected, T x) { return __atomic_compare_exchange_n(&v, &expected, x, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }

private:
  T v{};
};

} // namespace composite

#endif // COMPOSITE_VOCAB_H
