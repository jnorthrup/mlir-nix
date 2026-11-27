// A HashSink's SHA-256 (lowered/nixstore/HashOps.mlir calls nixstore_s256_*): this build's own module, Sha256.mlir (the
// CPU's SHA-2 instructions where the processor has them).  The build links this module or Sha256OpenSsl.mlir
// (lib/CMakeLists.txt: libcrypto on x86_64 where it is found).  The context is HashSink::impl, 16-aligned.
module {
  llvm.func @mlnix_sha256_init(!llvm.ptr)
  llvm.func @mlnix_sha256_update(!llvm.ptr, !llvm.ptr, i64)
  llvm.func @mlnix_sha256_final(!llvm.ptr, !llvm.ptr)

  llvm.func @nixstore_s256_init(%ctx: !llvm.ptr) {
    llvm.call @mlnix_sha256_init(%ctx) : (!llvm.ptr) -> ()
    llvm.return
  }
  llvm.func @nixstore_s256_update(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
    llvm.call @mlnix_sha256_update(%ctx, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.return
  }
  llvm.func @nixstore_s256_final(%ctx: !llvm.ptr, %out: !llvm.ptr) {
    llvm.call @mlnix_sha256_final(%ctx, %out) : (!llvm.ptr, !llvm.ptr) -> ()
    llvm.return
  }
}
