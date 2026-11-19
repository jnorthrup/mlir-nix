// The float->int rounding core of __ceil/__floor, hollowed from lib/Eval/Builtins.cpp's rounding template into MLIR
// (the ShowType.mlir / ArithOps.mlir recipe: a neutral C-ABI entry in the llvm dialect, linked by mlnix_lower_interface).
// The bridge keeps forceValue, the Int passthrough, forceFloat, mkInt and Nix's error wording (the out-of-range message
// quotes the ORIGINAL float via nixfe::fixedFloat); this entry computes ceil/floor, the range test and the cast exactly
// as the old body did:
//   r = up ? ceil(d) : floor(d)   (llvm.intr.ceil / llvm.intr.floor, GENERIC form: LLVM 23 has no custom assembly)
//   in range iff r >= -2^63 && r < 2^63   (ordered fcmp, so NaN/inf fall out as the C++ >= / < did)
//   *out = (int64_t)r   (fptosi; r is integer-valued and in [-2^63, 2^63), so the cast is exact)
// @mlnix_round(up, d, *out) -> 1 when in range (result stored), 0 when out of range (bridge throws before reading it).
// Both intrinsics are computed and selected (pure, no side effects); up != 0 picks ceil, else floor.
module {
  llvm.func @mlnix_round(%up: i32, %d: f64, %out: !llvm.ptr) -> i32 {
    %c0 = llvm.mlir.constant(0 : i32) : i32
    %c1 = llvm.mlir.constant(1 : i32) : i32
    %lo = llvm.mlir.constant(-9223372036854775808.0 : f64) : f64
    %hi = llvm.mlir.constant(9223372036854775808.0 : f64) : f64
    %rc = "llvm.intr.ceil"(%d) : (f64) -> f64
    %rf = "llvm.intr.floor"(%d) : (f64) -> f64
    %isup = llvm.icmp "ne" %up, %c0 : i32
    %r = llvm.select %isup, %rc, %rf : i1, f64
    %ge = llvm.fcmp "oge" %r, %lo : f64
    %lt = llvm.fcmp "olt" %r, %hi : f64
    %ok = llvm.and %ge, %lt : i1
    llvm.cond_br %ok, ^bb_ok, ^bb_bad
  ^bb_ok:
    %iv = llvm.fptosi %r : f64 to i64
    llvm.store %iv, %out : i64, !llvm.ptr
    llvm.return %c1 : i32
  ^bb_bad:
    llvm.return %c0 : i32
  }
}
