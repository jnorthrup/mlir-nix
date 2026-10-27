// The x86 intrinsics lib/Store/Sha256.cpp uses, as plain C++ (test only: scripts/check-sha256.py compiles Sha256.cpp against this on any
// host).  Each function is the pseudo-code of Intel's Intrinsics Guide for the instruction of that name; lane 0 is bits 31:0.
#ifndef NIX_EMULATE_X86_H
#define NIX_EMULATE_X86_H

#include <cstdint>
#include <cstring>

struct __m128i {
  uint32_t l[4];
};

inline __m128i _mm_loadu_si128(const __m128i *p) {
  __m128i r;
  memcpy(&r, p, 16);
  return r;
}
inline void _mm_storeu_si128(__m128i *p, __m128i a) { memcpy(p, &a, 16); }
inline __m128i _mm_set_epi64x(long long hi, long long lo) {
  return {{uint32_t(lo), uint32_t(uint64_t(lo) >> 32), uint32_t(hi), uint32_t(uint64_t(hi) >> 32)}};
}
inline __m128i _mm_add_epi32(__m128i a, __m128i b) {
  return {{a.l[0] + b.l[0], a.l[1] + b.l[1], a.l[2] + b.l[2], a.l[3] + b.l[3]}};
}
inline __m128i _mm_shuffle_epi32(__m128i a, int imm) {
  return {{a.l[imm & 3], a.l[(imm >> 2) & 3], a.l[(imm >> 4) & 3], a.l[(imm >> 6) & 3]}};
}
inline __m128i _mm_shuffle_epi8(__m128i a, __m128i mask) {
  uint8_t in[16], m[16], out[16];
  memcpy(in, &a, 16);
  memcpy(m, &mask, 16);
  for (int j = 0; j < 16; j++) out[j] = (m[j] & 0x80) ? 0 : in[m[j] & 15];
  __m128i r;
  memcpy(&r, out, 16);
  return r;
}
// the low 128 bits of (a:b) >> (8 * n), a the high half
inline __m128i _mm_alignr_epi8(__m128i a, __m128i b, int n) {
  uint8_t cat[32], out[16];
  memcpy(cat, &b, 16);
  memcpy(cat + 16, &a, 16);
  for (int j = 0; j < 16; j++) out[j] = j + n < 32 ? cat[j + n] : 0;
  __m128i r;
  memcpy(&r, out, 16);
  return r;
}
// 16-bit lanes: lane i from b when bit i of imm is set
inline __m128i _mm_blend_epi16(__m128i a, __m128i b, int imm) {
  uint16_t x[8], y[8], out[8];
  memcpy(x, &a, 16);
  memcpy(y, &b, 16);
  for (int i = 0; i < 8; i++) out[i] = ((imm >> i) & 1) ? y[i] : x[i];
  __m128i r;
  memcpy(&r, out, 16);
  return r;
}

namespace emu_sha {
inline uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
inline uint32_t Ch(uint32_t e, uint32_t f, uint32_t g) { return (e & f) ^ (~e & g); }
inline uint32_t Maj(uint32_t a, uint32_t b, uint32_t c) { return (a & b) ^ (a & c) ^ (b & c); }
inline uint32_t S0(uint32_t a) { return rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22); }
inline uint32_t S1(uint32_t e) { return rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25); }
inline uint32_t s0(uint32_t x) { return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3); }
inline uint32_t s1(uint32_t x) { return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10); }
} // namespace emu_sha

// dst = new (A,B,E,F) from a = (C,D,G,H) in lanes (3,2,1,0), b = (A,B,E,F) in lanes (3,2,1,0), two rounds with k lanes 0 and 1
inline __m128i _mm_sha256rnds2_epu32(__m128i a, __m128i b, __m128i k) {
  using namespace emu_sha;
  uint32_t A = b.l[3], B = b.l[2], C = a.l[3], D = a.l[2], E = b.l[1], F = b.l[0], G = a.l[1], H = a.l[0];
  for (int i = 0; i < 2; i++) {
    uint32_t t = Ch(E, F, G) + S1(E) + k.l[i] + H;
    uint32_t nA = t + Maj(A, B, C) + S0(A);
    uint32_t nE = t + D;
    H = G; G = F; F = E; E = nE;
    D = C; C = B; B = A; A = nA;
  }
  return {{F, E, B, A}};
}
inline __m128i _mm_sha256msg1_epu32(__m128i a, __m128i b) {
  using namespace emu_sha;
  return {{a.l[0] + s0(a.l[1]), a.l[1] + s0(a.l[2]), a.l[2] + s0(a.l[3]), a.l[3] + s0(b.l[0])}};
}
inline __m128i _mm_sha256msg2_epu32(__m128i a, __m128i b) {
  using namespace emu_sha;
  uint32_t w16 = a.l[0] + s1(b.l[2]);
  uint32_t w17 = a.l[1] + s1(b.l[3]);
  uint32_t w18 = a.l[2] + s1(w16);
  uint32_t w19 = a.l[3] + s1(w17);
  return {{w16, w17, w18, w19}};
}

#endif
