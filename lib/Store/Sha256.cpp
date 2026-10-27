//===- Sha256.cpp - SHA-256, with the CPU's own instructions where it has them -===//
//
// See Nix/Sha256.h.  The hardware path is the x86 SHA extensions (SHA256RNDS2, SHA256MSG1, SHA256MSG2), in the order of Intel's
// reference: the state is kept as ABEF and CDGH, four rounds are two RNDS2, and the message schedule of group g + 1 is made
// from groups g and g - 3 by MSG1 and MSG2.  test/sha256/ runs this very file against hashlib with the instructions replaced by
// plain C++ (scripts/check-sha256.py), so the shuffles are checked on any host; the self-test below checks the instructions
// themselves on the host that has them.
//
//===----------------------------------------------------------------------===//

#include "Nix/Sha256.h"

#include <cstring>

#if defined(NIX_SHA256_EMULATE_X86)
#include "emulate_x86.h"
#define NIX_SHA256_X86 1
#define NIX_TARGET_SHA
#elif defined(__x86_64__) && defined(__linux__) && (defined(__clang__) || defined(__GNUC__))
#include <cpuid.h>
#include <immintrin.h>
#define NIX_SHA256_X86 1
#define NIX_TARGET_SHA __attribute__((target("sha,sse4.1,ssse3")))
#endif

namespace nixstore {
namespace {

alignas(16) const uint32_t K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

inline uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
inline uint32_t loadBE32(const uint8_t *p) {
  return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | uint32_t(p[3]);
}

using CompressFn = void (*)(uint32_t st[8], const uint8_t *data, size_t nblocks);

const uint32_t kIV[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

//===----------------------------------------------------------------------===//
// Portable
//===----------------------------------------------------------------------===//

#define NIX_SHA_RND(a, b, c, d, e, f, g, h, i)                                                          \
  do {                                                                                                   \
    uint32_t t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + W[i];    \
    uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));             \
    d += t1;                                                                                             \
    h = t1 + t2;                                                                                         \
  } while (0)

void compressPortable(uint32_t st[8], const uint8_t *data, size_t nblocks) {
  while (nblocks--) {
    uint32_t W[64];
    for (int i = 0; i < 16; i++) W[i] = loadBE32(data + 4 * i);
    for (int i = 16; i < 64; i++) {
      uint32_t s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >> 3);
      uint32_t s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >> 10);
      W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }
    uint32_t a = st[0], b = st[1], c = st[2], d = st[3], e = st[4], f = st[5], g = st[6], h = st[7];
    for (int i = 0; i < 64; i += 8) {
      NIX_SHA_RND(a, b, c, d, e, f, g, h, i);
      NIX_SHA_RND(h, a, b, c, d, e, f, g, i + 1);
      NIX_SHA_RND(g, h, a, b, c, d, e, f, i + 2);
      NIX_SHA_RND(f, g, h, a, b, c, d, e, i + 3);
      NIX_SHA_RND(e, f, g, h, a, b, c, d, i + 4);
      NIX_SHA_RND(d, e, f, g, h, a, b, c, i + 5);
      NIX_SHA_RND(c, d, e, f, g, h, a, b, i + 6);
      NIX_SHA_RND(b, c, d, e, f, g, h, a, i + 7);
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e; st[5] += f; st[6] += g; st[7] += h;
    data += 64;
  }
}

//===----------------------------------------------------------------------===//
// x86 SHA extensions
//===----------------------------------------------------------------------===//

#ifdef NIX_SHA256_X86

// Group g is rounds 4g .. 4g + 3.  M[g & 3] holds the four message words of group g when its rounds run.
#define NIX_SHA_GROUP(g)                                                                                \
  {                                                                                                      \
    __m128i W = M[(g) & 3];                                                                              \
    __m128i MSG = _mm_add_epi32(W, _mm_loadu_si128(reinterpret_cast<const __m128i *>(&K[4 * (g)])));     \
    STATE1 = _mm_sha256rnds2_epu32(STATE1, STATE0, MSG);                                                 \
    if ((g) >= 3 && (g) <= 14) { /* the words of group g + 1, from the MSG1 of group g - 2 */            \
      __m128i T = _mm_alignr_epi8(W, M[((g) - 1) & 3], 4);                                               \
      M[((g) + 1) & 3] = _mm_sha256msg2_epu32(_mm_add_epi32(M[((g) + 1) & 3], T), W);                    \
    }                                                                                                    \
    MSG = _mm_shuffle_epi32(MSG, 0x0E);                                                                  \
    STATE0 = _mm_sha256rnds2_epu32(STATE0, STATE1, MSG);                                                 \
    if ((g) >= 1 && (g) <= 12) /* the first half of the words of group g + 3 */                          \
      M[((g) - 1) & 3] = _mm_sha256msg1_epu32(M[((g) - 1) & 3], W);                                      \
  }

NIX_TARGET_SHA
void compressNi(uint32_t st[8], const uint8_t *data, size_t nblocks) {
  const __m128i MASK = _mm_set_epi64x(0x0c0d0e0f08090a0bULL, 0x0405060700010203ULL); // big-endian words
  __m128i TMP = _mm_loadu_si128(reinterpret_cast<const __m128i *>(&st[0]));
  __m128i STATE1 = _mm_loadu_si128(reinterpret_cast<const __m128i *>(&st[4]));
  TMP = _mm_shuffle_epi32(TMP, 0xB1);                // CDAB
  STATE1 = _mm_shuffle_epi32(STATE1, 0x1B);          // EFGH
  __m128i STATE0 = _mm_alignr_epi8(TMP, STATE1, 8);  // ABEF
  STATE1 = _mm_blend_epi16(STATE1, TMP, 0xF0);       // CDGH
  while (nblocks--) {
    const __m128i ABEF = STATE0, CDGH = STATE1;
    __m128i M[4];
    for (int i = 0; i < 4; i++)
      M[i] = _mm_shuffle_epi8(_mm_loadu_si128(reinterpret_cast<const __m128i *>(data + 16 * i)), MASK);
    NIX_SHA_GROUP(0) NIX_SHA_GROUP(1) NIX_SHA_GROUP(2) NIX_SHA_GROUP(3)
    NIX_SHA_GROUP(4) NIX_SHA_GROUP(5) NIX_SHA_GROUP(6) NIX_SHA_GROUP(7)
    NIX_SHA_GROUP(8) NIX_SHA_GROUP(9) NIX_SHA_GROUP(10) NIX_SHA_GROUP(11)
    NIX_SHA_GROUP(12) NIX_SHA_GROUP(13) NIX_SHA_GROUP(14) NIX_SHA_GROUP(15)
    STATE0 = _mm_add_epi32(STATE0, ABEF);
    STATE1 = _mm_add_epi32(STATE1, CDGH);
    data += 64;
  }
  TMP = _mm_shuffle_epi32(STATE0, 0x1B);             // FEBA
  STATE1 = _mm_shuffle_epi32(STATE1, 0xB1);          // DCHG
  STATE0 = _mm_blend_epi16(TMP, STATE1, 0xF0);       // DCBA
  STATE1 = _mm_alignr_epi8(STATE1, TMP, 8);          // HGFE
  _mm_storeu_si128(reinterpret_cast<__m128i *>(&st[0]), STATE0);
  _mm_storeu_si128(reinterpret_cast<__m128i *>(&st[4]), STATE1);
}

bool cpuHasSha() {
#ifdef NIX_SHA256_EMULATE_X86
  return true;
#else
  unsigned eax, ebx, ecx, edx;
  if (!__get_cpuid(1, &eax, &ebx, &ecx, &edx)) return false;
  const bool ssse3 = ecx & (1u << 9), sse41 = ecx & (1u << 19);
  if (!__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) return false;
  return ssse3 && sse41 && (ebx & (1u << 29));
#endif
}

/// The candidate and the portable code over the same three blocks, from the initial state: equal; and the candidate's digest of "abc"
/// is the known one.
bool agrees(CompressFn candidate) {
  uint8_t data[192];
  for (unsigned i = 0; i < sizeof data; i++) data[i] = uint8_t(i * 7 + 3);
  uint32_t a[8], b[8];
  memcpy(a, kIV, sizeof a);
  memcpy(b, kIV, sizeof b);
  compressPortable(a, data, 3);
  candidate(b, data, 3);
  if (memcmp(a, b, sizeof a) != 0) return false;
  uint8_t abc[64] = {'a', 'b', 'c', 0x80};
  abc[63] = 24; // the length in bits
  uint32_t c[8];
  memcpy(c, kIV, sizeof c);
  candidate(c, abc, 1);
  return c[0] == 0xba7816bf && c[1] == 0x8f01cfea && c[2] == 0x414140de && c[3] == 0x5dae2223 && c[4] == 0xb00361a3 &&
         c[5] == 0x96177a9c && c[6] == 0xb410ff61 && c[7] == 0xf20015ad;
}

#endif // NIX_SHA256_X86

CompressFn pick(bool &hardware) {
#ifdef NIX_SHA256_X86
  if (cpuHasSha() && agrees(compressNi)) {
    hardware = true;
    return compressNi;
  }
#endif
  hardware = false;
  return compressPortable;
}

struct Choice {
  CompressFn fn;
  bool hardware;
  Choice() : fn(pick(hardware)) {}
};

const Choice &choice() {
  static const Choice c;
  return c;
}

} // namespace

bool Sha256::hardware() { return choice().hardware; }

void Sha256::init() {
  memcpy(state, kIV, sizeof state);
  buffered = 0;
  total = 0;
}

void Sha256::feed(const uint8_t *p, size_t n) {
  CompressFn compress = choice().fn;
  if (buffered) {
    size_t take = n < 64 - buffered ? n : 64 - buffered;
    memcpy(buf + buffered, p, take);
    buffered += take;
    p += take;
    n -= take;
    if (buffered < 64) return;
    compress(state, buf, 1);
    buffered = 0;
  }
  if (n >= 64) {
    size_t blocks = n / 64;
    compress(state, p, blocks);
    p += blocks * 64;
    n -= blocks * 64;
  }
  if (n) {
    memcpy(buf, p, n);
    buffered = uint32_t(n);
  }
}

void Sha256::update(const uint8_t *p, size_t n) {
  total += n;
  feed(p, n);
}

void Sha256::final(uint8_t out[32]) {
  const uint64_t bits = total * 8;
  uint8_t pad[72] = {0x80};
  const size_t padLen = buffered < 56 ? 56 - buffered : 120 - buffered;
  for (int i = 0; i < 8; i++) pad[padLen + i] = uint8_t(bits >> (56 - 8 * i));
  feed(pad, padLen + 8);
  for (int i = 0; i < 8; i++) {
    out[4 * i] = uint8_t(state[i] >> 24);
    out[4 * i + 1] = uint8_t(state[i] >> 16);
    out[4 * i + 2] = uint8_t(state[i] >> 8);
    out[4 * i + 3] = uint8_t(state[i]);
  }
}

} // namespace nixstore
