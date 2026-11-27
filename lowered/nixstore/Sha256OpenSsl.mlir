// A HashSink's SHA-256 (lowered/nixstore/HashOps.mlir calls nixstore_s256_*) where the build links libcrypto: on
// x86_64 a CPU without SHA-NI runs Sha256.mlir's portable rounds at about half the rate of OpenSSL's AVX2 code (230
// against 485 MB/s on a Skylake), so there the library stays (lib/CMakeLists.txt, MLNIX_SHA256).  The low-level
// SHA256_* calls: no provider lookup per hash.  The context is HashSink::impl (a SHA256_CTX is 112 bytes).
module {
  llvm.func @SHA256_Init(!llvm.ptr) -> i32
  llvm.func @SHA256_Update(!llvm.ptr, !llvm.ptr, i64) -> i32
  llvm.func @SHA256_Final(!llvm.ptr, !llvm.ptr) -> i32

  llvm.func @nixstore_s256_init(%ctx: !llvm.ptr) {
    %r = llvm.call @SHA256_Init(%ctx) : (!llvm.ptr) -> i32
    llvm.return
  }
  llvm.func @nixstore_s256_update(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
    %r = llvm.call @SHA256_Update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> i32
    llvm.return
  }
  llvm.func @nixstore_s256_final(%ctx: !llvm.ptr, %out: !llvm.ptr) {
    %r = llvm.call @SHA256_Final(%out, %ctx) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.return
  }
}
