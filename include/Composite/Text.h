//===- Text.h - text: bytes that are owned and grow, and the words for reading, searching and building them ---===//
//
// What std::string, std::ostringstream, std::to_string and the searching members of std::string were used for, in the pure zone.  A Text
// owns its bytes (a MutableSeries of chars: move-only, so a copy is said out loud, clone()) and always keeps a NUL after the last, so
// c_str() is free and const.  What only reads is a window (Chars, CharSeries.h): a Text converts to one at no cost, and to the views of
// the standard library and of LLVM (anything of two words made from a pointer and a count), so an API that takes those takes a Text.
// Pieces are put one after another (put, +=, +, str for a number), a run at a time: one capacity check a run.  Floating point is not
// here: a shortest round trip needs a real algorithm, and the evaluator writes Nix's floats where it already does.  A pointer into a Text
// holds until the next write.
//
//===----------------------------------------------------------------------===//

#ifndef COMPOSITE_TEXT_H
#define COMPOSITE_TEXT_H

#include "Composite/Mutable.h"

namespace composite {

/// What std::string::npos was (and std::string_view's: the same word).
inline constexpr size_t npos = ~size_t(0);

/// Bytes read through data() and size(): a window, a Text, and the views of the standard library and of LLVM, which have the same two words.
template <class V> concept ByteView = requires(const V &v) { static_cast<const char *>(v.data()); static_cast<size_t>(v.size()); };
/// What a Text takes in a write: bytes, a C string, one byte.
template <class P> concept Piece = ByteView<P> || same<bare_t<P>, char> || requires(const P &p) { static_cast<const char *>(p); };

struct Text {
  Text() = default;
  Text(const char *s) { put(s); }
  Text(const char *p, size_t n) { put(p, n); }
  /// A copy of bytes.  Another Text is copied by clone(), where the copy is meant.
  template <class V> requires(ByteView<V> && !same<V, Text>) explicit Text(const V &v) { put(v); }
  Text(Text &&) = default;
  Text &operator=(Text &&) = default;
  Text clone() const { return Text(data(), size()); }

  // Writing.
  Text &put(const char *p, size_t n) {
    if (!n) return *this;
    size_t at = size();
    size_t into = bytes.p && p >= bytes.p && p <= bytes.p + at ? size_t(p - bytes.p) : npos; // a write of a part of itself
    room(at + n);
    if (into != npos) p = bytes.p + into;
    __builtin_memmove(bytes.p + at, p, n);
    bytes.n = uint32_t(at + n);
    bytes.p[bytes.n] = 0;
    return *this;
  }
  /// A C string, up to its NUL.
  Text &put(const char *s) { return put(s, __builtin_strlen(s)); }
  Text &put(char c) {
    room(size_t(size()) + 1);
    bytes.p[bytes.n++] = c;
    bytes.p[bytes.n] = 0;
    return *this;
  }
  template <class V> requires ByteView<V> Text &put(const V &v) { return put(static_cast<const char *>(v.data()), static_cast<size_t>(v.size())); }
  Text &put(size_t n, char c) { for (size_t i = 0; i < n; i++) put(c); return *this; }
  /// The decimal digits of x, with a '-' when negative (INT64_MIN too).
  Text &putInt(int64_t x) {
    uint64_t u = x < 0 ? 0 - uint64_t(x) : uint64_t(x);
    if (x < 0) put('-');
    return putUnsigned(u);
  }
  Text &putUnsigned(uint64_t u) {
    char buf[20], *e = buf + sizeof buf, *p = e;
    do *--p = char('0' + u % 10); while (u /= 10);
    return put(p, size_t(e - p));
  }
  /// x in lower-case hex, at least `digits` of them (zero-padded).
  Text &putHex(uint64_t x, unsigned digits = 1) {
    static constexpr char hex[] = "0123456789abcdef";
    char buf[16], *e = buf + sizeof buf, *p = e;
    do *--p = hex[x & 15]; while ((x >>= 4) || e - p < digits);
    return put(p, size_t(e - p));
  }
  Text &operator+=(const char *s) { return put(s); }
  Text &operator+=(char c) { return put(c); }
  template <class V> requires ByteView<V> Text &operator+=(const V &v) { return put(v); }
  Text &append(const char *p, size_t n) { return put(p, n); }
  Text &append(size_t n, char c) { return put(n, c); }
  template <class P> requires Piece<P> Text &append(const P &p) { return put(p); }
  void push_back(char c) { put(c); }
  template <class P> requires Piece<P> Text &assign(const P &p) { clear(); return put(p); }
  Text &assign(const char *p, size_t n) { clear(); return put(p, n); }
  void reserve(size_t n) { room(n); }
  void clear() { bytes.n = 0; terminate(); }
  /// Only the first n bytes stay (n at most the size).
  Text &truncate(size_t n) {
    if (n > size()) TODO("Text::truncate past the end");
    bytes.n = uint32_t(n);
    terminate();
    return *this;
  }
  /// n bytes: the new ones are c.
  void resize(size_t n, char c = 0) { if (n <= size()) truncate(n); else put(n - size(), c); }
  void pop_back() { truncate(size() - 1); }
  /// Remove n bytes from pos (to the end by default).
  Text &erase(size_t pos, size_t n = npos) {
    if (pos > size()) TODO("Text::erase past the end");
    if (n > size() - pos) n = size() - pos;
    if (!n) return *this; // also a Text that has not held a byte: there is no buffer to move within
    __builtin_memmove(bytes.p + pos, bytes.p + pos + n, size() - pos - n + 1);
    bytes.n -= uint32_t(n);
    return *this;
  }
  /// Put bytes in at pos.
  template <class P> requires Piece<P> Text &insert(size_t pos, const P &p) {
    Text tail(chars_(pos, npos));
    truncate(pos);
    put(p);
    return put(tail);
  }
  Text &insert(size_t pos, size_t n, char c) { Text tail(chars_(pos, npos)); truncate(pos); put(n, c); return put(tail); }
  void swap(Text &o) { Text t(mv(*this)); *this = mv(o); o = mv(t); }

  // Reading.
  uint32_t size() const { return bytes.size(); }
  uint32_t length() const { return bytes.size(); }
  bool empty() const { return bytes.empty(); }
  /// Never null, and a NUL follows the last byte.
  const char *data() const { return bytes.p ? bytes.p : ""; }
  const char *c_str() const { return data(); }
  const char *cstr() const { return data(); }
  Chars chars() const { return composite::chars(data(), size()); }
  operator Chars() const { return chars(); }
  /// Any view of two words made from a pointer and a count (std::string_view, llvm::StringRef).
  template <class V> requires(!same<V, Chars> && __is_trivially_copyable(V) && sizeof(V) == 2 * sizeof(void *) && __is_constructible(V, const char *, size_t))
  operator V() const { return V(data(), size()); }
  const char &operator[](size_t i) const { return data()[i]; }
  /// Like std::string's: s[size()] is the NUL, also for a Text that has not held a byte (its buffer is made here, the one case a read allocates).
  char &operator[](size_t i) {
    if (!bytes.p) { room(0); terminate(); }
    return bytes.p[i];
  }
  const char &front() const { return data()[0]; }
  const char &back() const { return data()[size() - 1]; }
  char &front() { return (*this)[0]; }
  char &back() { return (*this)[size() - 1]; }
  const char *begin() const { return data(); }
  const char *end() const { return data() + size(); }
  char *begin() { return bytes.p; }
  char *end() { return bytes.p + size(); }
  /// The window from pos, n bytes at most (the rest by default): no copy.
  Chars substr(size_t pos, size_t n = npos) const { return chars_(pos, n); }

  size_t find(char c, size_t from = 0) const;
  template <class P> requires Piece<P> size_t find(const P &p, size_t from = 0) const;
  size_t rfind(char c, size_t from = npos) const;
  template <class P> requires Piece<P> size_t rfind(const P &p, size_t from = npos) const;
  template <class P> requires Piece<P> size_t find_first_of(const P &set, size_t from = 0) const;
  template <class P> requires Piece<P> size_t find_last_of(const P &set, size_t from = npos) const;
  template <class P> requires Piece<P> size_t find_first_not_of(const P &set, size_t from = 0) const;
  template <class P> requires Piece<P> size_t find_last_not_of(const P &set, size_t from = npos) const;
  bool starts_with(char c) const { return size() && data()[0] == c; }
  template <class P> requires Piece<P> bool starts_with(const P &p) const;
  bool ends_with(char c) const { return size() && data()[size() - 1] == c; }
  template <class P> requires Piece<P> bool ends_with(const P &p) const;
  bool contains(char c) const { return find(c) != npos; }
  template <class P> requires Piece<P> bool contains(const P &p) const { return find(p) != npos; }

private:
  /// Capacity for m bytes and the NUL.  The first allocation is 32: a path or a name rarely grows past it.
  void room(size_t m) {
    if (m >= 0xFFFFFFFFull) TODO("a Text past 4 GiB");
    if (m + 1 > bytes.cap) bytes.reserve(m + 1 < 32 ? 32 : m + 1);
  }
  void terminate() { if (bytes.p) bytes.p[bytes.n] = 0; }
  Chars chars_(size_t pos, size_t n) const {
    if (pos > size()) TODO("Text::substr past the end");
    return composite::chars(data() + pos, uint32_t(n > size() - pos ? size() - pos : n));
  }
  MutableSeries<char> bytes;
};

//===----------------------------------------------------------------------===//
// Searching a window: what the members of std::string and std::string_view were
//===----------------------------------------------------------------------===//

/// The window from pos, n bytes at most (the rest by default).
inline Chars substr(Chars s, size_t pos, size_t n = npos) {
  if (pos > s.size()) TODO("substr past the end");
  return chars(s.data() + pos, uint32_t(n > s.size() - pos ? s.size() - pos : n));
}
inline size_t find(Chars h, char c, size_t from = 0) {
  if (from >= h.size()) return npos;
  const void *r = __builtin_memchr(h.data() + from, c, h.size() - from);
  return r ? size_t(static_cast<const char *>(r) - h.data()) : npos;
}
inline size_t find(Chars h, Chars n, size_t from = 0) {
  if (n.size() == 0) return from <= h.size() ? from : npos;
  for (size_t at = find(h, n[0], from); at != npos && at + n.size() <= h.size(); at = find(h, n[0], at + 1))
    if (__builtin_memcmp(h.data() + at, n.data(), n.size()) == 0) return at;
  return npos;
}
inline size_t rfind(Chars h, char c, size_t from = npos) {
  for (size_t i = from >= h.size() ? h.size() : from + 1; i-- > 0;) if (h[uint32_t(i)] == c) return i;
  return npos;
}
inline size_t rfind(Chars h, Chars n, size_t from = npos) {
  if (n.size() > h.size()) return npos;
  size_t last = h.size() - n.size(), k = from < last ? from : last;
  for (;; k--) {
    if (__builtin_memcmp(h.data() + k, n.data(), n.size()) == 0) return k;
    if (k == 0) return npos;
  }
}
inline size_t findFirstOf(Chars h, Chars set, size_t from = 0) {
  for (size_t i = from; i < h.size(); i++) if (find(set, h[uint32_t(i)]) != npos) return i;
  return npos;
}
inline size_t findLastOf(Chars h, Chars set, size_t from = npos) {
  for (size_t i = from >= h.size() ? h.size() : from + 1; i-- > 0;) if (find(set, h[uint32_t(i)]) != npos) return i;
  return npos;
}
inline size_t findFirstNotOf(Chars h, Chars set, size_t from = 0) {
  for (size_t i = from; i < h.size(); i++) if (find(set, h[uint32_t(i)]) == npos) return i;
  return npos;
}
inline size_t findLastNotOf(Chars h, Chars set, size_t from = npos) {
  for (size_t i = from >= h.size() ? h.size() : from + 1; i-- > 0;) if (find(set, h[uint32_t(i)]) == npos) return i;
  return npos;
}
inline bool startsWith(Chars h, Chars p) { return p.size() <= h.size() && __builtin_memcmp(h.data(), p.data(), p.size()) == 0; }
inline bool endsWith(Chars h, Chars p) { return p.size() <= h.size() && __builtin_memcmp(h.data() + h.size() - p.size(), p.data(), p.size()) == 0; }

/// A piece as a window: bytes as they lie, a C string up to its NUL, a byte as a window of itself (the byte must outlive the window).
template <class P> requires Piece<P>
inline Chars windowOf(const P &p) {
  if constexpr (ByteView<P>) return chars(static_cast<const char *>(p.data()), uint32_t(p.size()));
  else if constexpr (same<bare_t<P>, char>) return chars(&p, 1);
  else { const char *s = p; return chars(s, uint32_t(__builtin_strlen(s))); }
}

template <class P> requires Piece<P> size_t Text::find(const P &p, size_t from) const {
  if constexpr (same<bare_t<P>, char>) return composite::find(chars(), p, from);
  else return composite::find(chars(), windowOf(p), from);
}
template <class P> requires Piece<P> size_t Text::rfind(const P &p, size_t from) const {
  if constexpr (same<bare_t<P>, char>) return composite::rfind(chars(), p, from);
  else return composite::rfind(chars(), windowOf(p), from);
}
inline size_t Text::find(char c, size_t from) const { return composite::find(chars(), c, from); }
inline size_t Text::rfind(char c, size_t from) const { return composite::rfind(chars(), c, from); }
template <class P> requires Piece<P> size_t Text::find_first_of(const P &set, size_t from) const { return findFirstOf(chars(), windowOf(set), from); }
template <class P> requires Piece<P> size_t Text::find_last_of(const P &set, size_t from) const { return findLastOf(chars(), windowOf(set), from); }
template <class P> requires Piece<P> size_t Text::find_first_not_of(const P &set, size_t from) const { return findFirstNotOf(chars(), windowOf(set), from); }
template <class P> requires Piece<P> size_t Text::find_last_not_of(const P &set, size_t from) const { return findLastNotOf(chars(), windowOf(set), from); }
template <class P> requires Piece<P> bool Text::starts_with(const P &p) const { return startsWith(chars(), windowOf(p)); }
template <class P> requires Piece<P> bool Text::ends_with(const P &p) const { return endsWith(chars(), windowOf(p)); }

//===----------------------------------------------------------------------===//
// Comparing and joining: the operators the standard library's strings had
//===----------------------------------------------------------------------===//

/// What compares and joins: Text and Chars, and a C string beside one of them (never two C strings, which are pointers).
template <class A, class B>
concept TextPair = (same<A, Text> || same<A, Chars> || same<B, Text> || same<B, Chars>) && (ByteView<A> || requires(const A &a) { static_cast<const char *>(a); }) &&
                   (ByteView<B> || requires(const B &b) { static_cast<const char *>(b); });

template <class A, class B> requires TextPair<A, B> bool operator==(const A &a, const B &b) {
  Chars x = windowOf(a), y = windowOf(b);
  return x.size() == y.size() && (x.size() == 0 || __builtin_memcmp(x.data(), y.data(), x.size()) == 0);
}
template <class A, class B> requires TextPair<A, B> bool operator<(const A &a, const B &b) { return lessChars(windowOf(a), windowOf(b)); }
template <class A, class B> requires TextPair<A, B> bool operator>(const A &a, const B &b) { return lessChars(windowOf(b), windowOf(a)); }
template <class A, class B> requires TextPair<A, B> bool operator<=(const A &a, const B &b) { return !lessChars(windowOf(b), windowOf(a)); }
template <class A, class B> requires TextPair<A, B> bool operator>=(const A &a, const B &b) { return !lessChars(windowOf(a), windowOf(b)); }
/// memcmp's sign, then the shorter first.
inline int compare(Chars a, Chars b) { return lessChars(a, b) ? -1 : lessChars(b, a) ? 1 : 0; }

/// Pieces joined: `dir + "/" + name` is one Text, built in a run.  A Text on the left is written to and handed on, so a chain copies once.
template <class A, class B> requires(Piece<A> && Piece<B> && (ByteView<A> || ByteView<B>) && !same<A, Text>) Text operator+(const A &a, const B &b) {
  Text t;
  t.put(a).put(b);
  return t;
}
template <class A, class B> requires(same<A, Text> && Piece<B>) Text operator+(const A &a, const B &b) {
  Text t(a.data(), a.size());
  t.put(b);
  return t;
}
template <class B> requires Piece<B> Text operator+(Text &&a, const B &b) {
  a.put(b);
  return mv(a);
}
template <class A> requires Piece<A> Text operator+(const A &a, Text &&b) {
  Text t;
  t.put(a).put(b);
  return t;
}
inline Text operator+(Text &&a, Text &&b) {
  a.put(b);
  return mv(a);
}

/// Pieces of any kind, joined: cat("dir/", name, '/', 12).  A number is written in decimal.
template <class P> void putPiece(Text &t, const P &p) {
  if constexpr (Integer<P> && !same<P, char>) {
    if constexpr (SignedInteger<P>) t.putInt(int64_t(p));
    else t.putUnsigned(uint64_t(p));
  } else t.put(p);
}
template <class... P> Text cat(const P &...p) {
  Text t;
  (putPiece(t, p), ...);
  return t;
}

/// The decimal digits of x: what std::to_string(x) was.
template <class T> requires(Integer<T> && !same<T, char> && !same<T, bool>) Text str(T x) {
  Text t;
  if constexpr (SignedInteger<T>) t.putInt(int64_t(x));
  else t.putUnsigned(uint64_t(x));
  return t;
}

/// Each word of the n bytes at s, as a stream's >> splits them (at ' ' and \t \n \v \f \r): emit(const char *word, uint32_t length).
template <class Emit> void eachWord(const char *s, uint32_t n, Emit &&emit) {
  auto space = [](char c) { return c == ' ' || (c >= '\t' && c <= '\r'); };
  for (uint32_t k = 0; k < n;) {
    while (k < n && space(s[k])) k++;
    uint32_t b = k;
    while (k < n && !space(s[k])) k++;
    if (k > b) emit(s + b, k - b);
  }
}
/// Each line of the n bytes at s, without its '\n', as getline splits them (a last line with no '\n' is one; nothing follows a final '\n').
template <class Emit> void eachLine(const char *s, uint32_t n, Emit &&emit) {
  for (uint32_t b = 0; b < n;) {
    const void *nl = __builtin_memchr(s + b, '\n', n - b);
    uint32_t e = nl ? uint32_t(static_cast<const char *>(nl) - s) : n;
    emit(s + b, e - b);
    b = e + 1;
  }
}

} // namespace composite

#endif // COMPOSITE_TEXT_H
