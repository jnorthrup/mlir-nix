//===- Core.h - what the TrikeShed algebra stands on: nothing --------------------===//
//
// No #include, no std::, no libc.  The algebra is pointers, counts and the compiler's own builtins: a series over contiguous memory is a
// pointer and a length, an iterator is a pointer, a fixed array is a C array in a struct (so it can be returned), and a cast is a cast.
// Everything here is a few lines, so the optimizer sees through it and nothing in it can add a call, an exception path or a vtable to a
// caller.  Memory is the language's own operator new and delete, and TODO()'s sink is the host's.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_CORE_H
#define COMPOSITE_CORE_H

// The fixed-width types, from the compiler: the same types <cstdint> names, so a header that includes it agrees.
#define COMPOSITE_TYPES                                                                                                \
  using int8_t = __INT8_TYPE__;                                                                                        \
  using int16_t = __INT16_TYPE__;                                                                                      \
  using int32_t = __INT32_TYPE__;                                                                                      \
  using int64_t = __INT64_TYPE__;                                                                                      \
  using uint8_t = __UINT8_TYPE__;                                                                                      \
  using uint16_t = __UINT16_TYPE__;                                                                                    \
  using uint32_t = __UINT32_TYPE__;                                                                                    \
  using uint64_t = __UINT64_TYPE__;                                                                                    \
  using uintptr_t = __UINTPTR_TYPE__;                                                                                  \
  using size_t = __SIZE_TYPE__;                                                                                        \
  using u128 = unsigned __int128;

namespace composite {
COMPOSITE_TYPES

// -- casts and traits, without <utility> or <type_traits> ----------------------------------------------------------------

template <class T> struct RemoveRef { using type = T; };
template <class T> struct RemoveRef<T &> { using type = T; };
template <class T> struct RemoveRef<T &&> { using type = T; };
template <class T> using remove_ref_t = typename RemoveRef<T>::type;
template <class T> struct RemoveCv { using type = T; };
template <class T> struct RemoveCv<const T> { using type = T; };
template <class T> struct RemoveCv<volatile T> { using type = T; };
template <class T> struct RemoveCv<const volatile T> { using type = T; };
/// The type with its reference and cv-qualifiers gone: what a value of it is.
template <class T> using bare_t = typename RemoveCv<remove_ref_t<T>>::type;

/// mv and fw are std::move and std::forward as the casts they are (short names, so an argument of a std type never makes the call ambiguous).
template <class T> constexpr remove_ref_t<T> &&mv(T &&t) noexcept { return static_cast<remove_ref_t<T> &&>(t); }
template <class T> constexpr T &&fw(remove_ref_t<T> &t) noexcept { return static_cast<T &&>(t); }
template <class T> constexpr T &&fw(remove_ref_t<T> &&t) noexcept { return static_cast<T &&>(t); }
/// The old value out, a new one in.
template <class T, class U> constexpr T exchange(T &x, U &&v) {
  T old = mv(x);
  x = fw<U>(v);
  return old;
}
/// A value of type T in an unevaluated context.
template <class T> T &&declval() noexcept;

template <class T, T V> struct Const { static constexpr T value = V; constexpr operator T() const { return V; } };
template <class A, class B> inline constexpr bool same = false;
template <class A> inline constexpr bool same<A, A> = true;
template <bool C, class A, class B> struct Pick { using type = A; };
template <class A, class B> struct Pick<false, A, B> { using type = B; };
template <bool C, class A, class B> using pick_t = typename Pick<C, A, B>::type;

template <class T> inline constexpr bool isPointer = false;
template <class T> inline constexpr bool isPointer<T *> = true;
template <class T> inline constexpr bool isEnum = __is_enum(T);
template <class T> inline constexpr bool plainData = __is_trivially_copyable(T);
template <class T> using underlying_t = __underlying_type(T);

/// The integer types, by name: a concept needs no header.
template <class T> inline constexpr bool isInteger = same<T, bool> || same<T, char> || same<T, signed char> || same<T, unsigned char> ||
    same<T, short> || same<T, unsigned short> || same<T, int> || same<T, unsigned> || same<T, long> || same<T, unsigned long> ||
    same<T, long long> || same<T, unsigned long long>;
template <class T> concept Integer = isInteger<T>; // bool included, as std::integral and std::unsigned_integral have it
template <class T> concept UnsignedInteger = Integer<T> && T(-1) > T(0);
template <class T> concept SignedInteger = Integer<T> && T(-1) < T(0);
template <class T> concept Enum = isEnum<T>;
template <class F, class... A> concept Callable = requires(F f, A... a) { f(a...); };

/// The unsigned type of the same size as T.
template <unsigned Bytes> struct UnsignedOfSize;
template <> struct UnsignedOfSize<1> { using type = uint8_t; };
template <> struct UnsignedOfSize<2> { using type = uint16_t; };
template <> struct UnsignedOfSize<4> { using type = uint32_t; };
template <> struct UnsignedOfSize<8> { using type = uint64_t; };
template <class T> using unsigned_of_t = typename UnsignedOfSize<sizeof(T)>::type;

/// The six comparisons of a type ordered by one member: what `operator<=>(...) const = default` would give, without <compare>.
#define COMPOSITE_ORDER(T, m)                                                                                          \
  constexpr bool operator==(const T &o) const { return m == o.m; }                                                     \
  constexpr bool operator!=(const T &o) const { return m != o.m; }                                                     \
  constexpr bool operator<(const T &o) const { return m < o.m; }                                                       \
  constexpr bool operator<=(const T &o) const { return m <= o.m; }                                                     \
  constexpr bool operator>(const T &o) const { return m > o.m; }                                                       \
  constexpr bool operator>=(const T &o) const { return m >= o.m; }

// -- the array: a C array in a struct, so it can be returned and copied, and its iterators are pointers --------------------

template <class T, size_t N> struct Arr {
  T a[N];
  constexpr T *begin() { return a; }
  constexpr T *end() { return a + N; }
  constexpr const T *begin() const { return a; }
  constexpr const T *end() const { return a + N; }
  constexpr T *data() { return a; }
  constexpr const T *data() const { return a; }
  constexpr size_t size() const { return N; }
  constexpr T &operator[](size_t i) { return a[i]; }
  constexpr const T &operator[](size_t i) const { return a[i]; }
};

// -- memory: the language's own operator new and delete, implicitly declared in every translation unit (no header) ----------------

/// TrikeShed's TODO(): the operation a body cannot do yet, said out loud instead of done wrongly.  The host installs a sink that says it (the
/// evaluator prints through LLVM's stream; a test prints through stdio); the trap that follows is a compiler builtin.
using TodoSink = void (*)(const char *what);
inline TodoSink todoSink = nullptr;
[[noreturn, gnu::cold, gnu::noinline]] inline void TODO(const char *what) {
  if (todoSink) todoSink(what);
  __builtin_trap();
}

/// Placement: construct a T in the block at p.  A tag type, so it can never be mistaken for (or collide with) the library's placement new.
struct At { void *p; };
} // namespace composite

inline void *operator new(composite::size_t, composite::At at) noexcept { return at.p; }
inline void operator delete(void *, composite::At) noexcept {}

/// A transform over a handful of registers must dissolve into its caller: a call per fold step costs more than the step.
#define COMPOSITE_INLINE [[gnu::always_inline]] inline

#endif
