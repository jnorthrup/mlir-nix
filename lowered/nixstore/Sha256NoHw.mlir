// Sha256.mlir's hardware form on a processor that has none written (neither arm64 nor x86_64): the probe says 1, the
// portable rounds, so the blocks entry is never reached.  llvm dialect.
llvm.func @s256_hw_probe() -> i64 {
  %one = llvm.mlir.constant(1 : i64) : i64
  llvm.return %one : i64
}
llvm.func @s256_hw_blocks(%ctx: !llvm.ptr, %p: !llvm.ptr, %nb: i64) {
  llvm.unreachable
}
