//===- Hash.cpp - Hashes and encodings (bit-compatible with Nix) ----------===//

#include "Nix/Os.h"
#include "Nix/Prefetch.h"
#include "Nix/Store.h"

#include "llvm/ADT/ArrayRef.h"
#if defined(MLNIX_SHA256_OPENSSL)
#define OPENSSL_SUPPRESS_DEPRECATED // the low-level SHA256_* calls: no provider lookup per hash
#include <openssl/sha.h>
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

// The digests are hollowed out to MLIR, built into NixStore by lib/CMakeLists.txt; a context is plain state in HashSink::impl.
// SHA-512: lowered/nixstore/Sha512.mlir (the compression, update's buffering, final's padding; h[8], buf[128], bufLen,
// totalLen).  MD5 and SHA-1: Md5.mlir, Sha1.mlir (the same pattern: 112-byte contexts, h words @0, buf[64] @32, bufLen @96,
// totalLen @104).  SHA-256, where the hashing of a run goes (store paths, derivations, NARs): Sha256.mlir, its rounds the
// CPU's SHA-2 instructions (Sha256Arm64.mlir, Sha256X86.mlir) where it has them, else portable; 176 bytes, h[8] @0,
// bufLen @32, totalLen @40, buf[128] @48.
extern "C" {
void mlnix_md5_init(void *ctx);
void mlnix_md5_update(void *ctx, const uint8_t *p, size_t n);
void mlnix_md5_final(void *ctx, uint8_t *out);
void mlnix_sha1_init(void *ctx);
void mlnix_sha1_update(void *ctx, const uint8_t *p, size_t n);
void mlnix_sha1_final(void *ctx, uint8_t *out);
void mlnix_sha512_init(void *ctx);
void mlnix_sha512_update(void *ctx, const uint8_t *p, size_t n);
void mlnix_sha512_final(void *ctx, uint8_t *out);
}
constexpr size_t md5CtxSize = 112, sha1CtxSize = 112, sha512CtxSize = 208;
#if defined(MLNIX_SHA256_OPENSSL)
// x86_64 with libcrypto (lib/CMakeLists.txt): a CPU without SHA-NI runs the portable rounds, and OpenSSL's AVX2 code is faster.
static void mlnix_sha256_init(void *c) { SHA256_Init((SHA256_CTX *)c); }
static void mlnix_sha256_update(void *c, const uint8_t *p, size_t n) { SHA256_Update((SHA256_CTX *)c, p, n); }
static void mlnix_sha256_final(void *c, uint8_t *out) { SHA256_Final(out, (SHA256_CTX *)c); }
constexpr size_t sha256CtxSize = sizeof(SHA256_CTX);
#else
extern "C" {
void mlnix_sha256_init(void *ctx);
void mlnix_sha256_update(void *ctx, const uint8_t *p, size_t n);
void mlnix_sha256_final(void *ctx, uint8_t *out);
}
constexpr size_t sha256CtxSize = 176;
#endif

static_assert(md5CtxSize <= sizeof(HashSink::impl) && sha1CtxSize <= sizeof(HashSink::impl) &&
                  sha256CtxSize <= sizeof(HashSink::impl) && sha512CtxSize <= sizeof(HashSink::impl),
              "a hash context fits in its sink");

HashSink::HashSink(HashAlgo a) : algo(a) {
  switch (a) {
  case HashAlgo::MD5: mlnix_md5_init(impl); break;
  case HashAlgo::SHA1: mlnix_sha1_init(impl); break;
  case HashAlgo::SHA256: mlnix_sha256_init(impl); break;
  case HashAlgo::SHA512: mlnix_sha512_init(impl); break;
  }
}

HashSink::~HashSink() = default;

void HashSink::update(std::string_view data) {
  total += data.size();
  llvm::ArrayRef<uint8_t> a((const uint8_t *)data.data(), data.size());
  switch (algo) {
  case HashAlgo::MD5: mlnix_md5_update(impl, a.data(), a.size()); break;
  case HashAlgo::SHA1: mlnix_sha1_update(impl, a.data(), a.size()); break;
  case HashAlgo::SHA256: mlnix_sha256_update(impl, a.data(), a.size()); break;
  case HashAlgo::SHA512: mlnix_sha512_update(impl, a.data(), a.size()); break;
  }
}

Hash HashSink::finish() {
  Hash h;
  h.algo = algo;
  switch (algo) {
  case HashAlgo::MD5: mlnix_md5_final(impl, h.bytes); break;
  case HashAlgo::SHA1: mlnix_sha1_final(impl, h.bytes); break;
  case HashAlgo::SHA256: mlnix_sha256_final(impl, h.bytes); break;
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

composite::Text base64Encode(std::string_view s) {
  composite::Text res;
  size_t n = s.size();
  if (!n) return res;
  res.resize(((n + 2) / 3) * 4);
  mlnix_base64_encode(s.data(), n, res.begin());
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

// parseRest and parseHash are lowered/nixstore/HashParse.mlir (the prefixes, the type checks, the length dispatch and the
// digest).  The bridge sizes the scratch for the base64 decoder and throws the error wording: the code and the algorithm
// come back from the entry (info[0] = algorithm, info[1] = the colon's index for an unknown algorithm name).
extern "C" int64_t nixstore_ts_parsehash(const char *p, int64_t n, int64_t known, uint8_t *out, uint8_t *scratch,
                                         int64_t *info);
Hash parseHash(std::string_view s, composite::Maybe<HashAlgo> algo) {
  Hash h;
  composite::Text scratch;
  scratch.resize(s.size());
  int64_t info[3] = {0, 0, 0};
  int64_t known = !algo ? -1 : int64_t(*algo);
  int64_t code = nixstore_ts_parsehash(s.data(), int64_t(s.size()), known, h.bytes, (uint8_t *)scratch.begin(), info);
  std::string_view orig = s;
  switch (code) {
  case 0: h.algo = HashAlgo(info[0]); return h;
  case 1: throw Error(composite::cat("unknown hash algorithm '", s.substr(0, size_t(info[1])), "', expect 'blake3', 'md5', 'sha1', 'sha256', or 'sha512'"));
  case 2: throw Error(composite::cat("hash '", orig, "' should have type '", algoName(*algo), "'"));
  case 3: throw Error(composite::cat("hash '", orig, "' does not include a type, nor is the type otherwise known from context"));
  case 4: throw Error(composite::cat("hash '", orig, "' has wrong length for hash algorithm '", algoName(HashAlgo(info[0])), "'"));
  case 5: throw Error(composite::cat("invalid base-16 hash '", orig, "'"));
  case 6: throw Error(composite::cat("invalid nix32 hash '", orig, "'"));
  default: throw Error(composite::cat("invalid SRI hash '", orig, "'"));
  }
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

// compressHash is lowered/nixstore/HashParse.mlir's nixstore_ts_compress (the XOR fold; r.bytes is zeroed there).
extern "C" void nixstore_ts_compress(const uint8_t *in, int64_t n, int64_t newSize, uint8_t *out);
Hash compressHash(const Hash &h, size_t newSize) {
  Hash r;
  r.algo = h.algo;
  nixstore_ts_compress(h.bytes, int64_t(h.size()), int64_t(newSize), r.bytes);
  return r;
}

} // namespace nixstore
