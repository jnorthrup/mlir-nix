// Sha256.mlir's @s256_hw_probe on macOS arm64: 2, the hardware rounds (Sha256Arm64.mlir).  Every Apple arm64 CPU has the
// SHA-2 instructions (the compiler's own baseline for the target assumes them).  llvm dialect.
llvm.func @s256_hw_probe() -> i64 {
  %two = llvm.mlir.constant(2 : i64) : i64
  llvm.return %two : i64
}
