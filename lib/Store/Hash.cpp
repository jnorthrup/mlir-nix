//===- Hash.cpp - Hashes and encodings (bit-compatible with Nix) ----------===//

#include "Nix/Prefetch.h"
#include "Nix/Store.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/Support/MD5.h"
#include "llvm/Support/SHA1.h"
// SHA-256 is where the hashing of a run goes (53 MB of a run of nixos-toplevel), so it is not LLVM's portable C: libcrypto where there
// is one (it picks the SHA extensions or the AVX2 code of the CPU; it is what Nix hashes with), CommonCrypto on macOS.  lib/CMakeLists.txt.
#if defined(MLNIX_SHA256_OPENSSL)
#define OPENSSL_SUPPRESS_DEPRECATED // the low-level SHA256_* calls: no provider lookup per hash
#include <openssl/sha.h>
#elif defined(__APPLE__) && !defined(MLNIX_SHA256_LLVM)
#include <CommonCrypto/CommonDigest.h>
#else
#include "llvm/Support/SHA256.h"
#endif

#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace nixstore {

const char nix32Chars[33] = "0123456789abcdfghijklmnpqrsvwxyz";

size_t hashSize(HashAlgo a) {
  switch (a) {
  case HashAlgo::MD5: return 16;
  case HashAlgo::SHA1: return 20;
  case HashAlgo::SHA256: return 32;
  case HashAlgo::SHA512: return 64;
  }
  return 0;
}

std::string algoName(HashAlgo a) {
  switch (a) {
  case HashAlgo::MD5: return "md5";
  case HashAlgo::SHA1: return "sha1";
  case HashAlgo::SHA256: return "sha256";
  case HashAlgo::SHA512: return "sha512";
  }
  return "?";
}

std::optional<HashAlgo> parseHashAlgo(std::string_view s) {
  if (s == "md5") return HashAlgo::MD5;
  if (s == "sha1") return HashAlgo::SHA1;
  if (s == "sha256") return HashAlgo::SHA256;
  if (s == "sha512") return HashAlgo::SHA512;
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// SHA-512 (LLVM does not provide one)
//===----------------------------------------------------------------------===//

namespace {
struct SHA512Ctx {
  uint64_t h[8];
  uint8_t buf[128];
  size_t bufLen = 0;
  uint64_t totalLen = 0;
  SHA512Ctx() {
    static const uint64_t init[8] = {
        0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL,
        0xa54ff53a5f1d36f1ULL, 0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
        0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};
    memcpy(h, init, sizeof h);
  }
  static uint64_t rotr(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }
  void block(const uint8_t *p) {
    static const uint64_t k[80] = {
        0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
        0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
        0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
        0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
        0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
        0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
        0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
        0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
        0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
        0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
        0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
        0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
        0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
        0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
        0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
        0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
        0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
        0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
        0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
        0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};
    uint64_t w[80];
    for (int i = 0; i < 16; i++) {
      w[i] = 0;
      for (int j = 0; j < 8; j++) w[i] = (w[i] << 8) | p[i * 8 + j];
    }
    for (int i = 16; i < 80; i++) {
      uint64_t s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7);
      uint64_t s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint64_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 80; i++) {
      uint64_t S1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41);
      uint64_t ch = (e & f) ^ (~e & g);
      uint64_t t1 = hh + S1 + ch + k[i] + w[i];
      uint64_t S0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39);
      uint64_t mj = (a & b) ^ (a & c) ^ (b & c);
      uint64_t t2 = S0 + mj;
      hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }
  void update(const uint8_t *d, size_t n) {
    totalLen += n;
    while (n) {
      size_t take = std::min(n, 128 - bufLen);
      memcpy(buf + bufLen, d, take);
      bufLen += take; d += take; n -= take;
      if (bufLen == 128) { block(buf); bufLen = 0; }
    }
  }
  void final(uint8_t out[64]) {
    uint64_t bits = totalLen * 8;
    uint8_t pad = 0x80;
    update(&pad, 1);
    uint8_t zero = 0;
    while (bufLen != 112) update(&zero, 1);
    uint8_t len[16] = {0};
    for (int i = 0; i < 8; i++) len[15 - i] = uint8_t(bits >> (8 * i));
    update(len, 16);
    for (int i = 0; i < 8; i++)
      for (int j = 0; j < 8; j++) out[i * 8 + j] = uint8_t(h[i] >> (56 - 8 * j));
  }
};

#if defined(MLNIX_SHA256_OPENSSL)
struct Sha256Ctx {
  SHA256_CTX c;
  Sha256Ctx() { SHA256_Init(&c); }
  void update(const uint8_t *p, size_t n) { SHA256_Update(&c, p, n); }
  void final(uint8_t *out) { SHA256_Final(out, &c); }
};
#elif defined(__APPLE__) && !defined(MLNIX_SHA256_LLVM)
struct Sha256Ctx {
  CC_SHA256_CTX c;
  Sha256Ctx() { CC_SHA256_Init(&c); }
  void update(const uint8_t *p, size_t n) {
    for (size_t off = 0; off < n; off += 1u << 30)
      CC_SHA256_Update(&c, p + off, (CC_LONG)std::min<size_t>(1u << 30, n - off));
  }
  void final(uint8_t *out) { CC_SHA256_Final(out, &c); }
};
#else
struct Sha256Ctx {
  llvm::SHA256 c;
  void update(const uint8_t *p, size_t n) { c.update(llvm::ArrayRef<uint8_t>(p, n)); }
  void final(uint8_t *out) {
    auto r = c.final();
    memcpy(out, r.data(), 32);
  }
};
#endif
} // namespace

static_assert(sizeof(llvm::MD5) <= sizeof(HashSink::impl) && sizeof(llvm::SHA1) <= sizeof(HashSink::impl) &&
                  sizeof(Sha256Ctx) <= sizeof(HashSink::impl) && sizeof(SHA512Ctx) <= sizeof(HashSink::impl),
              "a hash context fits in its sink");
static_assert(alignof(llvm::MD5) <= 16 && alignof(llvm::SHA1) <= 16 && alignof(Sha256Ctx) <= 16 && alignof(SHA512Ctx) <= 16);

HashSink::HashSink(HashAlgo a) : algo(a) {
  switch (a) {
  case HashAlgo::MD5: ::new (static_cast<void *>(impl)) llvm::MD5(); break;
  case HashAlgo::SHA1: ::new (static_cast<void *>(impl)) llvm::SHA1(); break;
  case HashAlgo::SHA256: ::new (static_cast<void *>(impl)) Sha256Ctx(); break;
  case HashAlgo::SHA512: ::new (static_cast<void *>(impl)) SHA512Ctx(); break;
  }
}

HashSink::~HashSink() {
  switch (algo) {
  case HashAlgo::MD5: reinterpret_cast<llvm::MD5 *>(impl)->~MD5(); break;
  case HashAlgo::SHA1: reinterpret_cast<llvm::SHA1 *>(impl)->~SHA1(); break;
  case HashAlgo::SHA256: reinterpret_cast<Sha256Ctx *>(impl)->~Sha256Ctx(); break;
  case HashAlgo::SHA512: reinterpret_cast<SHA512Ctx *>(impl)->~SHA512Ctx(); break;
  }
}

void HashSink::update(std::string_view data) {
  total += data.size();
  llvm::ArrayRef<uint8_t> a((const uint8_t *)data.data(), data.size());
  switch (algo) {
  case HashAlgo::MD5: reinterpret_cast<llvm::MD5 *>(impl)->update(a); break;
  case HashAlgo::SHA1: reinterpret_cast<llvm::SHA1 *>(impl)->update(a); break;
  case HashAlgo::SHA256: reinterpret_cast<Sha256Ctx *>(impl)->update(a.data(), a.size()); break;
  case HashAlgo::SHA512: reinterpret_cast<SHA512Ctx *>(impl)->update(a.data(), a.size()); break;
  }
}

Hash HashSink::finish() {
  Hash h;
  h.algo = algo;
  switch (algo) {
  case HashAlgo::MD5: {
    llvm::MD5::MD5Result r;
    reinterpret_cast<llvm::MD5 *>(impl)->final(r);
    memcpy(h.bytes, r.data(), 16);
    break;
  }
  case HashAlgo::SHA1: {
    auto r = reinterpret_cast<llvm::SHA1 *>(impl)->final();
    memcpy(h.bytes, r.data(), 20);
    break;
  }
  case HashAlgo::SHA256: reinterpret_cast<Sha256Ctx *>(impl)->final(h.bytes); break;
  case HashAlgo::SHA512:
    reinterpret_cast<SHA512Ctx *>(impl)->final(h.bytes);
    break;
  }
  return h;
}

Hash hashString(HashAlgo a, std::string_view s) {
  HashSink sink(a);
  sink.update(s);
  return sink.finish();
}

Hash hashFile(HashAlgo a, const std::string &path) {
  HashSink sink(a);
  nixprefetch::note('F', path.c_str());
  int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error("opening file '" + path + "': " + strerror(errno));
  char buf[65536];
  while (true) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) { close(fd); throw Error("reading file '" + path + "'"); }
    if (n == 0) break;
    sink.update(std::string_view(buf, n));
  }
  close(fd);
  return sink.finish();
}

void appendBase16(std::string &out, const uint8_t *d, size_t n) {
  static const char hex[] = "0123456789abcdef";
  size_t at = out.size();
  out.resize(at + n * 2);
  for (size_t i = 0; i < n; i++) {
    out[at + 2 * i] = hex[d[i] >> 4];
    out[at + 2 * i + 1] = hex[d[i] & 0xf];
  }
}

std::string base16Encode(const uint8_t *d, size_t n) {
  std::string s;
  appendBase16(s, d, n);
  return s;
}

void appendNix32(std::string &out, const uint8_t *d, size_t n) {
  size_t len = (n * 8 - 1) / 5 + 1, at = out.size();
  out.resize(at + len);
  for (int i = (int)len - 1; i >= 0; i--) {
    unsigned b = i * 5;
    unsigned bi = b / 8, bj = b % 8;
    unsigned c = (d[bi] >> bj) | (bi >= n - 1 ? 0 : d[bi + 1] << (8 - bj));
    out[at + len - 1 - i] = nix32Chars[c & 0x1f];
  }
}

std::string nix32Encode(const uint8_t *d, size_t n) {
  std::string s;
  appendNix32(s, d, n);
  return s;
}

std::optional<std::string> nix32Decode(std::string_view s, size_t size) {
  std::string out(size, '\0');
  for (size_t n = 0; n < s.size(); n++) {
    char c = s[s.size() - n - 1];
    const char *p = strchr(nix32Chars, c);
    if (!p || !c) return std::nullopt;
    unsigned digit = p - nix32Chars;
    unsigned b = n * 5, i = b / 8, j = b % 8;
    if (i >= size) return std::nullopt;
    out[i] = char((unsigned char)out[i] | (digit << j));
    if (i + 1 < size) out[i + 1] = char((unsigned char)out[i + 1] | (digit >> (8 - j)));
    else if (digit >> (8 - j)) return std::nullopt;
  }
  return out;
}

static const char b64chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(std::string_view s) {
  std::string res;
  int data = 0, nbits = 0;
  for (unsigned char c : s) {
    data = data << 8 | c;
    nbits += 8;
    while (nbits >= 6) {
      nbits -= 6;
      res.push_back(b64chars[data >> nbits & 0x3f]);
    }
  }
  if (nbits) res.push_back(b64chars[data << (6 - nbits) & 0x3f]);
  while (res.size() % 4) res.push_back('=');
  return res;
}

std::optional<std::string> base64Decode(std::string_view s) {
  int decode[256];
  for (int i = 0; i < 256; i++) decode[i] = -1;
  for (int i = 0; i < 64; i++) decode[(unsigned char)b64chars[i]] = i;
  std::string res;
  unsigned d = 0, bits = 0;
  for (char c : s) {
    if (c == '=') break;
    if (c == '\n') continue;
    int digit = decode[(unsigned char)c];
    if (digit < 0) return std::nullopt;
    bits += 6;
    d = d << 6 | digit;
    if (bits >= 8) {
      res.push_back(char(d >> (bits - 8) & 0xff));
      bits -= 8;
    }
  }
  return res;
}

std::string Hash::to_string(HashFormat f, bool includeAlgo) const {
  std::string s;
  if (f == HashFormat::SRI || includeAlgo) {
    s += algoName(algo);
    s += f == HashFormat::SRI ? '-' : ':';
  }
  switch (f) {
  case HashFormat::Base16: appendBase16(s, bytes, size()); break;
  case HashFormat::Nix32: appendNix32(s, bytes, size()); break;
  case HashFormat::Base64:
  case HashFormat::SRI:
    s += base64Encode(std::string_view((const char *)bytes, size()));
    break;
  }
  return s;
}

bool Hash::operator==(const Hash &o) const {
  return algo == o.algo && memcmp(bytes, o.bytes, size()) == 0;
}
bool Hash::operator<(const Hash &o) const {
  if (algo != o.algo) return algo < o.algo;
  return memcmp(bytes, o.bytes, size()) < 0;
}

static Hash parseRest(std::string_view rest, HashAlgo algo, bool isSRI, std::string_view orig) {
  Hash h;
  h.algo = algo;
  size_t sz = h.size();
  auto bad = [&]() -> Error {
    return Error("hash '" + std::string(orig) + "' has wrong length for hash algorithm '" + algoName(algo) + "'");
  };
  if (!isSRI && rest.size() == sz * 2) {
    for (size_t i = 0; i < sz; i++) {
      auto hexv = [&](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        throw Error("invalid base-16 hash '" + std::string(orig) + "'");
      };
      h.bytes[i] = uint8_t(hexv(rest[2 * i]) << 4 | hexv(rest[2 * i + 1]));
    }
    return h;
  }
  if (!isSRI && rest.size() == (sz * 8 - 1) / 5 + 1) {
    auto d = nix32Decode(rest, sz);
    if (!d) throw Error("invalid nix32 hash '" + std::string(orig) + "'");
    memcpy(h.bytes, d->data(), sz);
    return h;
  }
  if (isSRI || rest.size() == ((4 * sz / 3) + 3) / 4 * 4) {
    auto d = base64Decode(rest);
    if (!d || d->size() != sz) {
      if (isSRI) throw Error("invalid SRI hash '" + std::string(orig) + "'");
      throw bad();
    }
    memcpy(h.bytes, d->data(), sz);
    return h;
  }
  throw bad();
}

Hash parseHash(std::string_view s, std::optional<HashAlgo> algo) {
  std::string_view orig = s;
  auto colon = s.find(':');
  bool isSRI = false;
  std::optional<HashAlgo> parsed;
  if (colon != std::string_view::npos) {
    parsed = parseHashAlgo(s.substr(0, colon));
    if (!parsed) throw Error("unknown hash algorithm '" + std::string(s.substr(0, colon)) + "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'");
    s = s.substr(colon + 1);
  } else {
    auto dash = s.find('-');
    if (dash != std::string_view::npos) {
      parsed = parseHashAlgo(s.substr(0, dash));
      if (parsed) {
        s = s.substr(dash + 1);
        isSRI = true;
      }
    }
  }
  if (parsed && algo && *parsed != *algo)
    throw Error("hash '" + std::string(orig) + "' should have type '" + algoName(*algo) + "'");
  if (!parsed && !algo)
    throw Error("hash '" + std::string(orig) + "' does not include a type, nor is the type otherwise known from context");
  return parseRest(s, parsed ? *parsed : *algo, isSRI, orig);
}

Hash parseHashAllowEmpty(std::string_view s, std::optional<HashAlgo> algo, std::string *warning) {
  if (s.empty()) {
    if (!algo) throw Error("empty hash requires explicit hash algorithm");
    Hash h;
    h.algo = *algo;
    if (warning) *warning = "found empty hash, assuming '" + h.to_string(HashFormat::SRI, true) + "'";
    return h;
  }
  return parseHash(s, algo);
}

Hash compressHash(const Hash &h, size_t newSize) {
  Hash r;
  r.algo = h.algo;
  memset(r.bytes, 0, sizeof r.bytes);
  for (size_t i = 0; i < h.size(); i++) r.bytes[i % newSize] ^= h.bytes[i];
  return r;
}

} // namespace nixstore
