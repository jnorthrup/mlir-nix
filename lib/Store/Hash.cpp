//===- Hash.cpp - Hashes and encodings (bit-compatible with Nix) ----------===//

#include "Nix/Os.h"
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

#include <string.h>
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

std::string_view algoName(HashAlgo a) {
  switch (a) {
  case HashAlgo::MD5: return "md5";
  case HashAlgo::SHA1: return "sha1";
  case HashAlgo::SHA256: return "sha256";
  case HashAlgo::SHA512: return "sha512";
  }
  return "?";
}

composite::Maybe<HashAlgo> parseHashAlgo(std::string_view s) {
  if (s == "md5") return HashAlgo::MD5;
  if (s == "sha1") return HashAlgo::SHA1;
  if (s == "sha256") return HashAlgo::SHA256;
  if (s == "sha512") return HashAlgo::SHA512;
  return nullptr;
}

// SHA-512 is hollowed out to MLIR: lowered/nixstore/Sha512.mlir (the compression, update's buffering, final's padding),
// built into NixStore by lib/CMakeLists.txt.  Its context is plain state in HashSink::impl: h[8], buf[128], bufLen, totalLen.
extern "C" {
void mlnix_sha512_init(void *ctx);
void mlnix_sha512_update(void *ctx, const uint8_t *p, size_t n);
void mlnix_sha512_final(void *ctx, uint8_t *out);
}
constexpr size_t sha512CtxSize = 208;

namespace {
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
      CC_SHA256_Update(&c, p + off, (CC_LONG)composite::min<size_t>(1u << 30, n - off));
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
                  sizeof(Sha256Ctx) <= sizeof(HashSink::impl) && sha512CtxSize <= sizeof(HashSink::impl),
              "a hash context fits in its sink");
static_assert(alignof(llvm::MD5) <= 16 && alignof(llvm::SHA1) <= 16 && alignof(Sha256Ctx) <= 16);

HashSink::HashSink(HashAlgo a) : algo(a) {
  switch (a) {
  case HashAlgo::MD5: ::new (static_cast<void *>(impl)) llvm::MD5(); break;
  case HashAlgo::SHA1: ::new (static_cast<void *>(impl)) llvm::SHA1(); break;
  case HashAlgo::SHA256: ::new (static_cast<void *>(impl)) Sha256Ctx(); break;
  case HashAlgo::SHA512: mlnix_sha512_init(impl); break;
  }
}

HashSink::~HashSink() {
  switch (algo) {
  case HashAlgo::MD5: reinterpret_cast<llvm::MD5 *>(impl)->~MD5(); break;
  case HashAlgo::SHA1: reinterpret_cast<llvm::SHA1 *>(impl)->~SHA1(); break;
  case HashAlgo::SHA256: reinterpret_cast<Sha256Ctx *>(impl)->~Sha256Ctx(); break;
  case HashAlgo::SHA512: break;
  }
}

void HashSink::update(std::string_view data) {
  total += data.size();
  llvm::ArrayRef<uint8_t> a((const uint8_t *)data.data(), data.size());
  switch (algo) {
  case HashAlgo::MD5: reinterpret_cast<llvm::MD5 *>(impl)->update(a); break;
  case HashAlgo::SHA1: reinterpret_cast<llvm::SHA1 *>(impl)->update(a); break;
  case HashAlgo::SHA256: reinterpret_cast<Sha256Ctx *>(impl)->update(a.data(), a.size()); break;
  case HashAlgo::SHA512: mlnix_sha512_update(impl, a.data(), a.size()); break;
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
  case HashAlgo::SHA512: mlnix_sha512_final(impl, h.bytes); break;
  }
  return h;
}

Hash hashString(HashAlgo a, std::string_view s) {
  HashSink sink(a);
  sink.update(s);
  return sink.finish();
}

Hash hashFile(HashAlgo a, std::string_view path) {
  HashSink sink(a);
  nixsys::CStr file(path);
  nixprefetch::note('F', file);
  int fd = open(file, O_RDONLY | O_CLOEXEC);
  if (fd < 0) throw Error(composite::cat("opening file '", path, "': ", strerror(errno)));
  char buf[65536];
  while (true) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n < 0) { close(fd); throw Error(composite::cat("reading file '", path, "'")); }
    if (n == 0) break;
    sink.update(std::string_view(buf, n));
  }
  close(fd);
  return sink.finish();
}

// The byte encoders are hollowed out to the TrikeShed dialect: lowered/nixstore/Encoders.mlir, built into NixStore by
// lib/CMakeLists.txt.  The bridges only size the Text and call the compiled entries; the encoding algebra (series /
// at / alpha / drain over the byte series) is in the .mlir.  The entries write into the Text's own buffer, so the
// output is built where it is appended, as before.
extern "C" {
size_t mlnix_base16_encode(const uint8_t *d, size_t n, char *out);
size_t mlnix_nix32_encode(const uint8_t *d, size_t n, char *out);
size_t mlnix_base64_encode(const char *d, size_t n, char *out);
int mlnix_nix32_decode(const char *s, size_t n, size_t size, uint8_t *out); // 1 valid (bytes written), 0 invalid
int mlnix_base64_decode(const char *s, size_t n, uint8_t *out, size_t *outlen); // 1 valid, 0 invalid
}

void appendBase16(composite::Text &out, const uint8_t *d, size_t n) {
  if (!n) return;
  size_t at = out.size();
  out.resize(at + n * 2);
  mlnix_base16_encode(d, n, out.begin() + at);
}

void appendNix32(composite::Text &out, const uint8_t *d, size_t n) {
  if (!n) return;
  size_t at = out.size();
  out.resize(at + (n * 8 + 4) / 5); // ceil(8n/5), the old (8n-1)/5+1 for n > 0
  mlnix_nix32_encode(d, n, out.begin() + at);
}

composite::Maybe<composite::Text> nix32Decode(std::string_view s, size_t size) {
  composite::Text out;
  out.resize(size); // zero-filled: the entry ORs the digit contributions in, as the old loop did
  if (!mlnix_nix32_decode(s.data(), s.size(), size, (uint8_t *)out.begin())) return nullptr;
  return out;
}

composite::Text base64Encode(std::string_view s) {
  composite::Text res;
  size_t n = s.size();
  if (!n) return res;
  res.resize(((n + 2) / 3) * 4);
  mlnix_base64_encode(s.data(), n, res.begin());
  return res;
}

composite::Maybe<composite::Text> base64Decode(std::string_view s) {
  composite::Text res;
  res.resize(s.size()); // capacity: <= 6 bits per input char, so never more than s.size() bytes
  size_t len = 0;
  if (!mlnix_base64_decode(s.data(), s.size(), (uint8_t *)res.begin(), &len)) return nullptr;
  res.truncate(len);
  return res;
}

composite::Text Hash::to_string(HashFormat f, bool includeAlgo) const {
  composite::Text s;
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

// Hash::operator== is hollowed out to MLIR: lowered/nixstore/HashEq.mlir, built into NixStore by lib/CMakeLists.txt.
bool Hash::operator<(const Hash &o) const {
  if (algo != o.algo) return algo < o.algo;
  return memcmp(bytes, o.bytes, size()) < 0;
}

static Hash parseRest(std::string_view rest, HashAlgo algo, bool isSRI, std::string_view orig) {
  Hash h;
  h.algo = algo;
  size_t sz = h.size();
  auto bad = [&]() -> Error {
    return Error(composite::cat("hash '", orig, "' has wrong length for hash algorithm '", algoName(algo), "'"));
  };
  if (!isSRI && rest.size() == sz * 2) {
    for (size_t i = 0; i < sz; i++) {
      auto hexv = [&](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        throw Error(composite::cat("invalid base-16 hash '", orig, "'"));
      };
      h.bytes[i] = uint8_t(hexv(rest[2 * i]) << 4 | hexv(rest[2 * i + 1]));
    }
    return h;
  }
  if (!isSRI && rest.size() == (sz * 8 - 1) / 5 + 1) {
    auto d = nix32Decode(rest, sz);
    if (!d) throw Error(composite::cat("invalid nix32 hash '", orig, "'"));
    memcpy(h.bytes, d->data(), sz);
    return h;
  }
  if (isSRI || rest.size() == ((4 * sz / 3) + 3) / 4 * 4) {
    auto d = base64Decode(rest);
    if (!d || d->size() != sz) {
      if (isSRI) throw Error(composite::cat("invalid SRI hash '", orig, "'"));
      throw bad();
    }
    memcpy(h.bytes, d->data(), sz);
    return h;
  }
  throw bad();
}

Hash parseHash(std::string_view s, composite::Maybe<HashAlgo> algo) {
  std::string_view orig = s;
  auto colon = s.find(':');
  bool isSRI = false;
  composite::Maybe<HashAlgo> parsed;
  if (colon != std::string_view::npos) {
    parsed = parseHashAlgo(s.substr(0, colon));
    if (!parsed) throw Error(composite::cat("unknown hash algorithm '", s.substr(0, colon), "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'"));
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
    throw Error(composite::cat("hash '", orig, "' should have type '", algoName(*algo), "'"));
  if (!parsed && !algo)
    throw Error(composite::cat("hash '", orig, "' does not include a type, nor is the type otherwise known from context"));
  return parseRest(s, parsed ? *parsed : *algo, isSRI, orig);
}

Hash parseHashAllowEmpty(std::string_view s, composite::Maybe<HashAlgo> algo, composite::Text *warning) {
  if (s.empty()) {
    if (!algo) throw Error("empty hash requires explicit hash algorithm");
    Hash h;
    h.algo = *algo;
    if (warning) *warning = composite::cat("found empty hash, assuming '", h.to_string(HashFormat::SRI, true), "'");
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
