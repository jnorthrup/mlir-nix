// Sha256.mlir's @s256_hw_probe on Linux arm64: 2 (the hardware rounds, Sha256Arm64.mlir) where the kernel reports the SHA-2
// instructions, getauxval(AT_HWCAP = 16) & HWCAP_SHA2 (1 << 6), else 1 (the portable rounds).  llvm dialect.
llvm.func @getauxval(i64) -> i64
llvm.func @s256_hw_probe() -> i64 {
  %at = llvm.mlir.constant(16 : i64) : i64
  %six = llvm.mlir.constant(6 : i64) : i64
  %one = llvm.mlir.constant(1 : i64) : i64
  %cap = llvm.call @getauxval(%at) : (i64) -> i64
  %bit = llvm.lshr %cap, %six : i64
  %has = llvm.and %bit, %one : i64
  %form = llvm.add %has, %one : i64
  llvm.return %form : i64
}
