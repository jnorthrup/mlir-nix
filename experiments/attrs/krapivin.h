// Funnel hashing and elastic hashing, from
//   Farach-Colton, Krapivin, Kuszmaul: "Optimal Bounds for Open Addressing Without
//   Reordering" (arXiv:2501.02305v2), sections 3 and 2.
// Written from the paper's text, not ported from another implementation (the C++ one
// we found says its elastic tests "always fail").  Keys are 32-bit, values 32-bit,
// the table is built for a known number of keys and never deletes or reorders, which is
// exactly the paper's setting.
//
// Deviations, all forced by the paper being asymptotic (n -> infinity, delta > 1/n^o(1)):
//   * Level / array sizes are rounded; for small n there are fewer than alpha levels.
//   * Funnel: log log n is clamped to >= 2; the special array A_{alpha+1} is B (uniform
//     probing, log log n attempts) + C (two-choice buckets of 2 log log n slots).
//   * Elastic: "uniform probing" is capped at 64 + 8|A| attempts (insert() returns false
//     instead of looping); f(eps) uses c = 4; a search scans depth-major
//     (probe depth 1 of every array, then depth 2, ...) rather than in phi order, and an
//     absent key needs the per-array maximum probe depth recorded at insertion
//     (the paper bounds only successful searches for elastic hashing).
//   * insert() returns false on overflow; the replay counts those and falls back.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace krapivin {

constexpr uint32_t EMPTY = 0xFFFFFFFFu;
struct Slot {
  uint32_t key = EMPTY, val = 0;
};

#ifdef KRAPIVIN_COUNT
#define KRAPIVIN_PROBE() (++probes_)
#else
#define KRAPIVIN_PROBE() ((void)0)
#endif

inline uint64_t mix64(uint64_t z) {
  z += 0x9E3779B97F4A7C15ull;
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
  return z ^ (z >> 31);
}
/// hash(key, salt) reduced to [0, n) without a division (Lemire's fast range).
inline uint32_t hashTo(uint32_t key, uint64_t salt, uint32_t n) {
  uint32_t h = (uint32_t)(mix64(((uint64_t)key << 32) ^ (salt * 0xD6E8FEB86659FD93ull)) >> 32);
  return (uint32_t)(((uint64_t)h * n) >> 32);
}
/// Smallest n with n - floor(n/den) >= m: the array size for m keys at delta = 1/den.
inline uint32_t capacityFor(uint32_t m, uint32_t den) {
  uint64_t n = m + m / (den - 1) + 1;
  while (n - n / den < m) n++;
  while (n > 1 && (n - 1) - (n - 1) / den >= m) n--;
  return (uint32_t)n;
}
inline uint32_t log2ceil(uint32_t x) {
  uint32_t l = 0;
  while ((1ull << l) < x) l++;
  return l;
}

//===----------------------------------------------------------------------===//
// Plain linear probing (the baseline everything is compared with)
//===----------------------------------------------------------------------===//
class LinearTable {
public:
  explicit LinearTable(uint32_t n) : slots_(std::max<uint32_t>(n, 1)) {}
  bool insert(uint32_t key, uint32_t val) {
    uint32_t n = slots_.size(), p = hashTo(key, 0, n);
    for (uint32_t i = 0; i < n; i++, p = (p + 1 == n ? 0 : p + 1))
      if (slots_[p].key == EMPTY) return slots_[p] = {key, val}, true;
    return false;
  }
  const Slot *find(uint32_t key) const {
    uint32_t n = slots_.size(), p = hashTo(key, 0, n);
    for (uint32_t i = 0; i < n; i++, p = (p + 1 == n ? 0 : p + 1)) {
      KRAPIVIN_PROBE();
      if (slots_[p].key == key) return &slots_[p];
      if (slots_[p].key == EMPTY) return nullptr;
    }
    return nullptr;
  }
  size_t bytes() const { return slots_.size() * sizeof(Slot); }
  mutable uint64_t probes_ = 0;

private:
  std::vector<Slot> slots_;
};

//===----------------------------------------------------------------------===//
// Funnel hashing (section 3): greedy, O(log^2 1/delta) worst-case expected probes
//===----------------------------------------------------------------------===//
class Funnel {
public:
  /// n slots, delta = 1/den (den a power of two >= 8).
  Funnel(uint32_t n, uint32_t den = 8) {
    uint32_t lg = log2ceil(den);
    uint32_t alpha = 4 * lg + 10;
    beta_ = 2 * lg;
    uint32_t special = (uint32_t)std::ceil(n / (2.0 * den)); // |A_{alpha+1}| >= ceil(delta n / 2)
    uint32_t nb = n > special ? (n - special) / beta_ : 0;   // buckets in A'
    special = n - nb * beta_;                                // whatever is left is special
    uint32_t L = std::min(alpha, nb);
    std::vector<uint32_t> a(L);
    double sum = 0, w = 1;
    for (uint32_t i = 0; i < L; i++, w *= 0.75) sum += w;
    uint32_t used = 0;
    w = 1;
    for (uint32_t i = 0; i < L; i++, w *= 0.75) used += a[i] = std::max<uint32_t>(1, (uint32_t)(nb * w / sum));
    while (used > nb) {
      if (a.back() > 1) a.back()--, used--;
      else used -= a.back(), a.pop_back();
    }
    for (uint32_t i = 0; used < nb && !a.empty(); i = (i + 1) % a.size()) a[i]++, used++;
    uint32_t off = 0;
    for (uint32_t b : a) levels_.push_back({off, b}), off += b * beta_;
    loglog_ = std::max<uint32_t>(2, log2ceil(std::max<uint32_t>(2, log2ceil(std::max<uint32_t>(n, 4)))));
    nB_ = special / 2;
    offB_ = off;
    uint32_t nC = special - nB_;
    cBucket_ = std::max<uint32_t>(1, std::min(2 * loglog_, nC));
    nCB_ = nC / cBucket_;
    offC_ = offB_ + nB_;
    slots_.assign(n, Slot{});
  }

  bool insert(uint32_t key, uint32_t val) {
    for (uint32_t i = 0; i < levels_.size(); i++) {
      Slot *b = &slots_[levels_[i].off + hashTo(key, i + 1, levels_[i].buckets) * beta_];
      for (uint32_t k = 0; k < beta_; k++)
        if (b[k].key == EMPTY) return b[k] = {key, val}, true;
    }
    for (uint32_t t = 0; t < loglog_ && nB_; t++) {
      Slot &s = slots_[offB_ + hashTo(key, 1000 + t, nB_)];
      if (s.key == EMPTY) return s = {key, val}, true;
    }
    if (!nCB_) return false;
    Slot *a = &slots_[offC_ + hashTo(key, 2000, nCB_) * cBucket_], *b = &slots_[offC_ + hashTo(key, 2001, nCB_) * cBucket_];
    for (uint32_t k = 0; k < cBucket_; k++) {
      if (a[k].key == EMPTY) return a[k] = {key, val}, true;
      if (b[k].key == EMPTY) return b[k] = {key, val}, true;
    }
    return false;
  }

  /// A bucket with a free slot proves the key is absent from this level on, because a
  /// key goes to the first level whose bucket has room and buckets fill in slot order.
  const Slot *find(uint32_t key) const {
    for (uint32_t i = 0; i < levels_.size(); i++) {
      const Slot *b = &slots_[levels_[i].off + hashTo(key, i + 1, levels_[i].buckets) * beta_];
      for (uint32_t k = 0; k < beta_; k++) {
        KRAPIVIN_PROBE();
        if (b[k].key == key) return &b[k];
        if (b[k].key == EMPTY) return nullptr;
      }
    }
    for (uint32_t t = 0; t < loglog_ && nB_; t++) {
      const Slot &s = slots_[offB_ + hashTo(key, 1000 + t, nB_)];
      KRAPIVIN_PROBE();
      if (s.key == key) return &s;
      if (s.key == EMPTY) return nullptr;
    }
    if (!nCB_) return nullptr;
    const Slot *a = &slots_[offC_ + hashTo(key, 2000, nCB_) * cBucket_], *b = &slots_[offC_ + hashTo(key, 2001, nCB_) * cBucket_];
    for (uint32_t k = 0; k < cBucket_; k++) {
      KRAPIVIN_PROBE();
      if (a[k].key == key) return &a[k];
      if (a[k].key == EMPTY) return nullptr;
      KRAPIVIN_PROBE();
      if (b[k].key == key) return &b[k];
      if (b[k].key == EMPTY) return nullptr;
    }
    return nullptr;
  }
  size_t bytes() const { return slots_.size() * sizeof(Slot); }
  uint32_t levels() const { return levels_.size(); }
  mutable uint64_t probes_ = 0;

private:
  struct Level {
    uint32_t off, buckets;
  };
  std::vector<Slot> slots_;
  std::vector<Level> levels_;
  uint32_t beta_, loglog_, offB_, nB_, offC_, nCB_, cBucket_;
};

//===----------------------------------------------------------------------===//
// Elastic hashing (section 2): non-greedy, O(1) amortized, O(log 1/delta) worst case
//===----------------------------------------------------------------------===//
class Elastic {
public:
  Elastic(uint32_t n, uint32_t den = 8, double c = 4.0) : den_(den), c_(c), lgden_(log2ceil(den)) {
    uint32_t rem = n, s = (n + 1) / 2, off = 0;
    while (rem > 0) {
      if (s == 0 || s > rem) s = rem;
      arr_.push_back({off, s, 0, 0});
      off += s, rem -= s, s /= 2;
    }
    if (arr_.empty()) arr_.push_back({0, 1, 0, 0}), off = 1;
    slots_.assign(off, Slot{});
  }

  bool insert(uint32_t key, uint32_t val) {
    uint32_t L = arr_.size();
    int b = batch();
    if (b == 0) return placeUniform(0, key, val, cap(0));
    if (b >= (int)L) return placeUniform(L - 1, key, val, cap(L - 1));
    Arr &A = arr_[b - 1], &N = arr_[b];
    double e1 = 1.0 - (double)A.count / A.size, e2 = 1.0 - (double)N.count / N.size;
    double half = 1.0 / (2.0 * den_);
    if (e1 <= half) return placeUniform(b, key, val, cap(b));         // case 2
    if (e2 <= 0.25) return placeUniform(b - 1, key, val, cap(b - 1)); // case 3 (the expensive one)
    uint32_t f = std::max(1.0, c_ * std::min(std::pow(std::log2(1.0 / e1), 2), (double)lgden_)); // case 1
    if (placeUniform(b - 1, key, val, f)) return true;
    return placeUniform(b, key, val, cap(b));
  }

  const Slot *find(uint32_t key) const {
    for (uint32_t d = 1; d <= maxDepth_; d++)
      for (uint32_t i = 0; i < arr_.size(); i++)
        if (d <= arr_[i].maxDepth) {
          const Slot &s = slots_[pos(i, d, key)];
          KRAPIVIN_PROBE();
          if (s.key == key) return &s;
        }
    return nullptr;
  }
  size_t bytes() const { return slots_.size() * sizeof(Slot); }
  mutable uint64_t probes_ = 0;

private:
  struct Arr {
    uint32_t off, size, count, maxDepth;
  };
  uint32_t pos(uint32_t i, uint32_t j, uint32_t key) const {
    return arr_[i].off + hashTo(key, ((uint64_t)(i + 1) << 40) ^ j, arr_[i].size);
  }
  uint32_t cap(uint32_t i) const { return 64 + 8 * arr_[i].size; }
  bool placeUniform(uint32_t i, uint32_t key, uint32_t val, uint32_t maxProbes) {
    for (uint32_t j = 1; j <= maxProbes; j++) {
      Slot &s = slots_[pos(i, j, key)];
      if (s.key == EMPTY) {
        s = {key, val};
        arr_[i].count++;
        arr_[i].maxDepth = std::max(arr_[i].maxDepth, j);
        maxDepth_ = std::max(maxDepth_, j);
        return true;
      }
    }
    return false;
  }
  /// Batch 0 fills A_1 to 3/4; batch b >= 1 fills A_b to (1 - delta/2) and A_{b+1} to 3/4.
  int batch() const {
    const Arr &a0 = arr_[0];
    if (a0.count < (3 * a0.size + 3) / 4) return 0;
    for (uint32_t b = 1; b < arr_.size(); b++) {
      const Arr &A = arr_[b - 1], &N = arr_[b];
      if (A.count < A.size - A.size / (2 * den_) || N.count < (3 * N.size + 3) / 4) return b;
    }
    return arr_.size();
  }
  uint32_t den_;
  double c_;
  uint32_t lgden_, maxDepth_ = 0;
  std::vector<Arr> arr_;
  std::vector<Slot> slots_;
};

} // namespace krapivin
