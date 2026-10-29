//===- Mutable.h - MutableSeries and the bodies it is written against ---===//

#ifndef COMPOSITE_MUTABLE_H
#define COMPOSITE_MUTABLE_H

#include "Composite/Series.h"

namespace composite {

//===----------------------------------------------------------------------===//
// MutableSeries, ↺ and Cursor: where a Series is mutated, and says so
//===----------------------------------------------------------------------===//

/// The growable body: a pointer, a count and a capacity.  An append is a compare and a store; when the capacity is used up the buffer doubles
/// through the language's own operator new.  Cells are relocated when it grows (a memcpy for plain data, a move for the rest), so they are
/// never held by address across an append.  Move-only: the promotion of a built series to a const one is a move, and a copy would be a quiet
/// materialization, so it does not compile.
template <class T> struct Growable {
  static constexpr bool growable = true;
  static constexpr bool contiguous = true;
  T *p = nullptr;
  uint32_t n = 0, cap = 0;

  Growable() = default;
  Growable(const Growable &) = delete;
  Growable &operator=(const Growable &) = delete;
  Growable(Growable &&o) noexcept : p(o.p), n(o.n), cap(o.cap) { o.p = nullptr; o.n = o.cap = 0; }
  Growable &operator=(Growable &&o) noexcept {
    if (this != &o) {
      release();
      p = o.p; n = o.n; cap = o.cap;
      o.p = nullptr; o.n = o.cap = 0;
    }
    return *this;
  }
  ~Growable() { release(); }

  constexpr T *base() { return p; }
  constexpr const T *base() const { return p; }
  constexpr T &at(uint32_t i) { return p[i]; }
  constexpr const T &at(uint32_t i) const { return p[i]; }
  constexpr T *first() { return p; }
  constexpr T *last() { return p + n; }
  constexpr const T *first() const { return p; }
  constexpr const T *last() const { return p + n; }
  constexpr uint32_t count() const { return n; }
  constexpr bool room() const { return true; }
  void put(T v) {
    if (n == cap) [[unlikely]] grow(n + 1);
    ::new (At{p + n}) T(mv(v));
    ++n;
  }
  void dropLast() { p[--n].~T(); }
  /// Capacity for at least `need` cells: the buffer doubles (4 to start), the cells move across, the old buffer goes back.
  void grow(size_t need) {
    static_assert(alignof(T) <= 16, "the buffer comes from the default operator new"); // here, where a recursive T is complete
    size_t nc = cap ? size_t(cap) * 2 : 4;
    if (nc < need) nc = need;
    T *q = static_cast<T *>(::operator new(nc * sizeof(T)));
    if constexpr (plainData<T>) {
      for (uint32_t i = 0; i < n; i++) q[i] = p[i];
    } else {
      for (uint32_t i = 0; i < n; i++) { ::new (At{q + i}) T(mv(p[i])); p[i].~T(); }
    }
    ::operator delete(p);
    p = q;
    cap = uint32_t(nc);
  }
  void reserveCells(size_t m) { if (m > cap) grow(m); }
  /// Exactly `m` cells: new ones are value-initialized, extra ones destroyed.
  void sizeTo(size_t m) {
    reserveCells(m);
    while (n < m) { ::new (At{p + n}) T(); ++n; }
    while (n > m) p[--n].~T();
  }
  void fill(size_t m, const T &v) {
    dropAll();
    reserveCells(m);
    while (n < m) { ::new (At{p + n}) T(v); ++n; }
  }
  void dropAll() { while (n) p[--n].~T(); }

private:
  void release() { dropAll(); ::operator delete(p); p = nullptr; cap = 0; }
};

/// The body of a frozen Series: cells that were built and are now only read.  Move-only, so the promotion from MutableSeries
/// is a move and a stray copy is a compile error, not a quiet materialization.
template <class T> struct Cells {
  Growable<T> c;
  explicit Cells(Growable<T> &&g) : c(mv(g)) {}
  Cells(Cells &&) = default;
  Cells &operator=(Cells &&) = default;
  Cells(const Cells &) = delete;
  Cells &operator=(const Cells &) = delete;
  const T &operator()(uint32_t i) const { return c.base()[i]; }
};
template <class T> using Frozen = Series<Cells<T>>;

/// A known-size body: the array is the storage, on the stack, with no heap.
template <class T, size_t N> struct Slab {
  Arr<T, N> a;
  constexpr const T &operator()(uint32_t i) const { return a.a[i]; }
};
/// freeze(array): the handle for a body whose size is a constant.  vec<N>(f) builds one, freeze keeps it as a Series.
template <class T, size_t N> constexpr auto freeze(Arr<T, N> a) { return Size<uint32_t(N)>{} |j| Slab<T, N>{mv(a)}; }

// The bodies of a MutableSeries: where the cells live.  Each is a handful of lines and gives the same five primitives
// (base, count, room, put, dropLast); the one algorithm below is written against those, and what a body cannot do (grow, be
// reserved, be frozen) is not there to call.

/// The inline body: N cells and a count, on the stack, no heap.  Full is full.
template <class T, uint32_t N> struct Inline {
  static constexpr bool growable = false;
  static constexpr bool contiguous = true;
  T cells[N]{};
  uint32_t n = 0;
  constexpr T *base() { return cells; }
  constexpr const T *base() const { return cells; }
  constexpr T &at(uint32_t i) { return cells[i]; }
  constexpr const T &at(uint32_t i) const { return cells[i]; }
  constexpr T *first() { return cells; }
  constexpr T *last() { return cells + n; }
  constexpr const T *first() const { return cells; }
  constexpr const T *last() const { return cells + n; }
  constexpr uint32_t count() const { return n; }
  constexpr bool room() const { return n < N; }
  constexpr void put(T v) { cells[n++] = mv(v); }
  constexpr void dropLast() { --n; }
};

/// The chunked body: a table of fixed chunks of 2^K cells.  A cell never moves: when a chunk is full the next append opens a new one (the
/// overflow escapes into it), and only the small table of chunk pointers is ever relocated.  So a pointer to a cell stays good across any
/// number of appends, which is what a std::deque was used for, and nothing is copied when the series grows.  A series of chunks reads as
/// one through its index function: contiguity is not something this body gives and is not something its readers ask for.
template <class T, uint32_t K = 6> struct Chunked {
  static constexpr bool growable = true;
  static constexpr bool contiguous = false;
  static constexpr uint32_t kSize = 1u << K, kMask = kSize - 1;
  T **tab = nullptr;
  uint32_t n = 0, chunks = 0, tabCap = 0;

  Chunked() = default;
  Chunked(const Chunked &) = delete;
  Chunked &operator=(const Chunked &) = delete;
  Chunked(Chunked &&o) noexcept : tab(o.tab), n(o.n), chunks(o.chunks), tabCap(o.tabCap) { o.tab = nullptr; o.n = o.chunks = o.tabCap = 0; }
  Chunked &operator=(Chunked &&o) noexcept {
    if (this != &o) {
      release();
      tab = o.tab; n = o.n; chunks = o.chunks; tabCap = o.tabCap;
      o.tab = nullptr; o.n = o.chunks = o.tabCap = 0;
    }
    return *this;
  }
  ~Chunked() { release(); }

  constexpr uint32_t count() const { return n; }
  constexpr bool room() const { return true; }
  constexpr T &at(uint32_t i) { return tab[i >> K][i & kMask]; }
  constexpr const T &at(uint32_t i) const { return tab[i >> K][i & kMask]; }
  void put(T v) {
    if ((n >> K) == chunks) [[unlikely]] openChunk();
    ::new (At{&at(n)}) T(mv(v));
    ++n;
  }
  void dropLast() { at(--n).~T(); }
  /// One more chunk: the escape.  Only the table of pointers may be relocated (a memcpy of pointers).
  void openChunk() {
    if (chunks == tabCap) {
      uint32_t nc = tabCap ? tabCap * 2 : 4;
      T **q = static_cast<T **>(::operator new(size_t(nc) * sizeof(T *)));
      for (uint32_t i = 0; i < chunks; i++) q[i] = tab[i];
      ::operator delete(tab);
      tab = q;
      tabCap = nc;
    }
    tab[chunks++] = static_cast<T *>(::operator new(size_t(kSize) * sizeof(T)));
  }
  void reserveCells(size_t m) { while (size_t(chunks) * kSize < m) openChunk(); }
  void sizeTo(size_t m) {
    reserveCells(m);
    while (n < m) { ::new (At{&at(n)}) T(); ++n; }
    while (n > m) at(--n).~T();
  }
  void fill(size_t m, const T &v) {
    dropAll();
    reserveCells(m);
    while (n < m) { ::new (At{&at(n)}) T(v); ++n; }
  }
  void dropAll() { while (n) at(--n).~T(); }

  /// The iterator is an index into the series: a pointer cannot walk across chunks.
  template <class C, class V> struct It {
    C *c;
    uint32_t i;
    constexpr V &operator*() const { return c->at(i); }
    constexpr It &operator++() { ++i; return *this; }
    constexpr bool operator==(const It &o) const { return i == o.i; }
    constexpr bool operator!=(const It &o) const { return i != o.i; }
  };
  constexpr It<Chunked, T> first() { return {this, 0}; }
  constexpr It<Chunked, T> last() { return {this, n}; }
  constexpr It<const Chunked, const T> first() const { return {this, 0}; }
  constexpr It<const Chunked, const T> last() const { return {this, n}; }

private:
  void release() {
    dropAll();
    for (uint32_t i = 0; i < chunks; i++) ::operator delete(tab[i]);
    ::operator delete(tab);
    tab = nullptr; chunks = tabCap = 0;
  }
};

template <class T, class Body = Growable<T>> struct MutableSeries : Body {
  constexpr MutableSeries() = default;
  explicit MutableSeries(size_t n) requires Body::growable { this->sizeTo(n); }
  MutableSeries(size_t n, const T &v) requires Body::growable { this->fill(n, v); }
  /// A brace list of cells, `{"a", "b"}`: appended in order.  Not for integer cells, where `(n, v)` already means n copies of v.
  template <class... A> requires(sizeof...(A) >= 1 && !isInteger<T> && (... && __is_constructible(T, A)) &&
                                 !(sizeof...(A) == 1 && (... && same<bare_t<A>, MutableSeries>)))
  MutableSeries(A &&...a) { (append(T(fw<A>(a))), ...); }
  constexpr bool operator==(const MutableSeries &o) const {
    if (size() != o.size()) return false;
    for (uint32_t i = 0; i < size(); ++i) if (!((*this)[i] == o[i])) return false;
    return true;
  }
  constexpr uint32_t size() const { return this->count(); }
  constexpr T &operator[](uint32_t i) { return this->at(i); }
  constexpr const T &operator[](uint32_t i) const { return this->at(i); }
  /// Accumulate.  The result is the index of the new cell: the `b` of whatever refers back to it.  A body with no room says TODO.
  constexpr uint32_t append(T v) {
    if (!this->room()) [[unlikely]] TODO("append past the capacity of a fixed body");
    this->put(mv(v));
    return size() - 1;
  }
  /// Accumulate a cell built in place.
  template <class... A> constexpr uint32_t emplace(A &&...a) { return append(T(fw<A>(a)...)); }
  constexpr void pop() { this->dropLast(); }
  constexpr void clear() { while (size()) pop(); }
  /// Remove cell i by moving the last cell into its place: the order of the others is not kept.  A bag's algorithm, for any body.
  constexpr void removeSwap(uint32_t i) { (*this)[i] = mv((*this)[size() - 1]); pop(); }
  /// Drain a cell: its value leaves and a default cell stays, so the indices of the others do not move.
  constexpr T drain(uint32_t i) { return composite::exchange((*this)[i], T{}); }
  // The container surface of a list that is built and then read: pointers for iteration, the ends, the raw cells.
  constexpr auto begin() { return this->first(); }
  constexpr auto end() { return this->last(); }
  constexpr auto begin() const { return this->first(); }
  constexpr auto end() const { return this->last(); }
  constexpr bool empty() const { return size() == 0; }
  constexpr T &back() { return (*this)[size() - 1]; }
  constexpr const T &back() const { return (*this)[size() - 1]; }
  constexpr T &front() { return (*this)[0]; }
  constexpr const T &front() const { return (*this)[0]; }
  constexpr T *data() requires Body::contiguous { return this->base(); }
  constexpr const T *data() const requires Body::contiguous { return this->base(); }
  // Only a growable body can be sized, reserved or frozen: for the others these are not there.
  void reserve(size_t n) requires Body::growable { this->reserveCells(n); }
  uint32_t capacity() const requires Body::contiguous && Body::growable { return this->cap; }
  void resize(size_t n) requires Body::growable { this->sizeTo(n); }
  void assign(size_t n, const T &v) requires Body::growable { this->fill(n, v); }
  /// The promotion of the handle to its body: the cells move into a const Series.  Only an rvalue can be frozen, so the hand-over
  /// is written out (`mv(x).freeze()`), costs a pointer, and leaves this series valid and empty.
  Frozen<T> freeze() && requires Body::growable && Body::contiguous { uint32_t n = size(); return n |j| Cells<T>(mv(static_cast<Growable<T> &>(*this))); }
  Frozen<T> freeze() & = delete;
  /// The Series over the cells, as many as there are now.  It indexes through this series and holds no
  /// pointer into the cells, so an append that moves them does not leave it dangling.
  auto view() const {
    return size() |j| [this](uint32_t i) -> const T & { return (*this)[i]; };
  }
};

} // namespace composite

#endif
