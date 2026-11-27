// Sha256.mlir's hardware rounds on a processor that has none written (neither arm64 nor x86_64): the probe says 1, the
// portable rounds, so the block entry is never reached.  llvm dialect.
llvm.func @s256_hw_probe() -> i64 {
  %one = llvm.mlir.constant(1 : i64) : i64
  llvm.return %one : i64
}
llvm.func @s256_hw_block(%abcd: vector<4xi32>, %efgh: vector<4xi32>, %p: !llvm.ptr, %k: !llvm.ptr) -> !llvm.struct<(vector<4xi32>, vector<4xi32>)> {
  llvm.unreachable
}
