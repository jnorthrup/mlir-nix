//===- Ed25519.cpp - signature verification for binary caches -------------===//
//
// Verification only (RFC 8032, Ed25519), after TweetNaCl's crypto_sign_open: a narinfo's `Sig:` is checked
// against the cache's public key, so that a path substituted from a cache is the one its key signed.  The field and
// point arithmetic, the reduction mod L, the base64 decoding of the signature and the key and the SHA-512 of R || A || M
// are hollowed out to MLIR: lowered/nixstore/Ed25519.mlir (beside Sha512.mlir), built into NixStore by lib/CMakeLists.txt.
//
//===----------------------------------------------------------------------===//

#include "Nix/Store.h"

namespace nixstore {

extern "C" int mlnix_ed25519_verify_b64(const char *sig, size_t siglen, const char *msg, size_t mlen, const char *key, size_t keylen);

bool ed25519VerifyBase64(std::string_view sig, std::string_view message, std::string_view publicKey) {
  return mlnix_ed25519_verify_b64(sig.data(), sig.size(), message.data(), message.size(), publicKey.data(), publicKey.size()) != 0;
}

} // namespace nixstore
