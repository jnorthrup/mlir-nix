module {
  func.func @scalar(%arg0: i64, %arg1: !llvm.ptr) -> i64 {
    %false = arith.constant false
    %c1_i64 = arith.constant 1 : i64
    %0 = arith.extsi %arg0 : i64 to i128
    %1 = arith.extsi %c1_i64 : i64 to i128
    %2 = arith.addi %0, %1 : i128
    %3 = arith.trunci %2 : i128 to i64
    %4 = arith.extsi %3 : i64 to i128
    %5 = arith.cmpi ne, %2, %4 : i128
    %6 = arith.ori %false, %5 : i1
    llvm.store %3, %arg1 : i64, !llvm.ptr
    %7 = arith.extui %6 : i1 to i64
    return %7 : i64
  }
}

