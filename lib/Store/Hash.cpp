//===- Hash.cpp - Hashes and encodings (bit-compatible with Nix) ----------===//
//
// The bodies are lowered/nixstore/HashOps.mlir: a sink's dispatch to the digests' modules (Md5, Sha1, Sha256, Sha512),
// hashString and hashFile, a hash's text (the digits Encoders.mlir's), parseHash's wording over HashParse.mlir's
// parser; nixstore::hashSize is defined there under its own name, Hash::operator== in HashEq.mlir.  What is here is
// a forward where a C++ type crosses: a string_view in, a Text or a Hash out, the message of a failure thrown.
//
//===----------------------------------------------------------------------===//

#include "Nix/Os.h"
#include "Nix/Store.h"

namespace nixstore {

extern "C" {
const char *nixstore_ts_algoname(int64_t algo);
int64_t nixstore_ts_algoof(const char *p, int64_t n);
void nixstore_hs_init(HashSink *s);
void nixstore_hs_update(HashSink *s, const char *p, int64_t n);
void nixstore_hs_finish(HashSink *s, Hash *h);
void nixstore_ts_hashstring(int64_t algo, const char *p, int64_t n, Hash *h);
int64_t nixstore_ts_hashfile(int64_t algo, const char *path, int64_t n, Hash *h, composite::Text *err);
void nixstore_ts_hashtext(const Hash *h, int64_t format, int64_t includeAlgo, composite::Text *out);
int64_t nixstore_ts_hashparse(const char *p, int64_t n, int64_t known, Hash *h, composite::Text *err);
int64_t nixstore_ts_hashparse0(const char *p, int64_t n, int64_t known, Hash *h, composite::Text *warning, composite::Text *err);
void nixstore_ts_compress(const uint8_t *in, int64_t n, int64_t newSize, uint8_t *out);
}
static_assert(sizeof(Hash) == 68 && __builtin_offsetof(Hash, bytes) == 4 && sizeof(HashSink) == 352 && alignof(HashSink) >= 16 &&
                  __builtin_offsetof(HashSink, impl) == 16 && __builtin_offsetof(HashSink, total) == 336,
              "HashOps.mlir's Hash and HashSink: a digest's context (208 bytes at most; SHA-256's is read as two aligned vectors) lies in impl");

std::string_view algoName(HashAlgo a) { return nixstore_ts_algoname(int64_t(a)); }
composite::Maybe<HashAlgo> parseHashAlgo(std::string_view s) { int64_t a = nixstore_ts_algoof(s.data(), s.size()); return a < 0 ? composite::Maybe<HashAlgo>() : composite::Maybe<HashAlgo>(HashAlgo(a)); }
HashSink::HashSink(HashAlgo a) : algo(a) { nixstore_hs_init(this); }
HashSink::~HashSink() = default;
void HashSink::update(std::string_view data) { nixstore_hs_update(this, data.data(), data.size()); }
Hash HashSink::finish() { Hash h; nixstore_hs_finish(this, &h); return h; }
Hash hashString(HashAlgo a, std::string_view s) { Hash h; nixstore_ts_hashstring(int64_t(a), s.data(), s.size(), &h); return h; }
Hash hashFile(HashAlgo a, std::string_view path) { Hash h; composite::Text e; if (nixstore_ts_hashfile(int64_t(a), nixsys::CStr(path), path.size(), &h, &e)) throw Error(e); return h; }
composite::Text Hash::to_string(HashFormat f, bool includeAlgo) const { composite::Text s; nixstore_ts_hashtext(this, int64_t(f), includeAlgo, &s); return s; }
Hash parseHash(std::string_view s, composite::Maybe<HashAlgo> algo) { Hash h; composite::Text e; if (nixstore_ts_hashparse(s.data(), s.size(), algo ? int64_t(*algo) : -1, &h, &e)) throw Error(e); return h; }
Hash parseHashAllowEmpty(std::string_view s, composite::Maybe<HashAlgo> algo, composite::Text *warning) { Hash h; composite::Text e; if (nixstore_ts_hashparse0(s.data(), s.size(), algo ? int64_t(*algo) : -1, &h, warning, &e)) throw Error(e); return h; }
Hash compressHash(const Hash &h, size_t newSize) { Hash r; r.algo = h.algo; nixstore_ts_compress(h.bytes, int64_t(h.size()), int64_t(newSize), r.bytes); return r; }

} // namespace nixstore
