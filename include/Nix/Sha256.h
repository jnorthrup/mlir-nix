//===- Sha256.h - SHA-256, with the CPU's own instructions where it has them -===//
//
// macOS hashes with CommonCrypto (Hash.cpp); this is for the rest.  llvm::SHA256 is portable C and takes the part of an update
// that does not fill a block one byte at a time, and an NAR stream is mostly small updates: a run of nixos-toplevel makes 144,000
// updates of 53 MB, 129,000 of them under 256 bytes.  The compression function is chosen once per process: the x86 SHA
// extensions when the CPU reports them and a self-test on the first use agrees with the portable code (a hardware path that
// disagrees is not used), the portable code otherwise.
//
// Plain C++, no LLVM.
//
//===----------------------------------------------------------------------===//

#ifndef NIX_SHA256_H
#define NIX_SHA256_H

#include <cstddef>
#include <cstdint>

namespace nixstore {

class Sha256 {
public:
  Sha256() { init(); }
  void init();
  void update(const uint8_t *data, size_t n);
  void final(uint8_t out[32]);
  /// Whether this process hashes with the SHA instructions (decided on the first call of anything here).
  static bool hardware();

private:
  void feed(const uint8_t *data, size_t n);
  uint32_t state[8];
  uint8_t buf[64];
  uint32_t buffered;
  uint64_t total;
};

} // namespace nixstore

#endif
