module {
  llvm.func @scalar(%arg0: i64, %arg1: !llvm.ptr) -> i64 {
    %0 = llvm.mlir.constant(false) : i1
    %1 = llvm.mlir.constant(1 : i64) : i64
    %2 = llvm.sext %arg0 : i64 to i128
    %3 = llvm.mlir.constant(1 : i128) : i128
    %4 = llvm.add %2, %3 : i128
    %5 = llvm.trunc %4 : i128 to i64
    %6 = llvm.sext %5 : i64 to i128
    %7 = llvm.icmp "ne" %4, %6 : i128
    llvm.store %5, %arg1 : i64, !llvm.ptr
    %8 = llvm.zext %7 : i1 to i64
    llvm.return %8 : i64
  }
}

