module {
  llvm.func @scalar(%arg0: i64, %arg1: !llvm.ptr) -> i64 {
    %0 = llvm.mlir.constant(false) : i1
    %1 = llvm.mlir.constant(3 : i64) : i64
    %2 = llvm.sext %arg0 : i64 to i128
    %3 = llvm.mlir.constant(3 : i128) : i128
    %4 = llvm.mul %2, %3 : i128
    %5 = llvm.trunc %4 : i128 to i64
    %6 = llvm.sext %5 : i64 to i128
    %7 = llvm.icmp "ne" %4, %6 : i128
    %8 = llvm.mlir.constant(1 : i64) : i64
    %9 = llvm.sext %5 : i64 to i128
    %10 = llvm.mlir.constant(1 : i128) : i128
    %11 = llvm.sub %9, %10 : i128
    %12 = llvm.trunc %11 : i128 to i64
    %13 = llvm.sext %12 : i64 to i128
    %14 = llvm.icmp "ne" %11, %13 : i128
    %15 = llvm.or %7, %14 : i1
    %16 = llvm.mlir.constant(7 : i64) : i64
    %17 = llvm.sext %12 : i64 to i128
    %18 = llvm.mlir.constant(7 : i128) : i128
    %19 = llvm.add %17, %18 : i128
    %20 = llvm.trunc %19 : i128 to i64
    %21 = llvm.sext %20 : i64 to i128
    %22 = llvm.icmp "ne" %19, %21 : i128
    %23 = llvm.or %15, %22 : i1
    llvm.store %20, %arg1 : i64, !llvm.ptr
    %24 = llvm.zext %23 : i1 to i64
    llvm.return %24 : i64
  }
}

