module {
  func.func @scalar(%arg0: i64, %arg1: !llvm.ptr) -> i64 {
    %false = arith.constant false
    %c3_i64 = arith.constant 3 : i64
    %0 = arith.extsi %arg0 : i64 to i128
    %1 = arith.extsi %c3_i64 : i64 to i128
    %2 = arith.muli %0, %1 : i128
    %3 = arith.trunci %2 : i128 to i64
    %4 = arith.extsi %3 : i64 to i128
    %5 = arith.cmpi ne, %2, %4 : i128
    %6 = arith.ori %false, %5 : i1
    %c1_i64 = arith.constant 1 : i64
    %7 = arith.extsi %3 : i64 to i128
    %8 = arith.extsi %c1_i64 : i64 to i128
    %9 = arith.subi %7, %8 : i128
    %10 = arith.trunci %9 : i128 to i64
    %11 = arith.extsi %10 : i64 to i128
    %12 = arith.cmpi ne, %9, %11 : i128
    %13 = arith.ori %6, %12 : i1
    %c7_i64 = arith.constant 7 : i64
    %14 = arith.extsi %10 : i64 to i128
    %15 = arith.extsi %c7_i64 : i64 to i128
    %16 = arith.addi %14, %15 : i128
    %17 = arith.trunci %16 : i128 to i64
    %18 = arith.extsi %17 : i64 to i128
    %19 = arith.cmpi ne, %16, %18 : i128
    %20 = arith.ori %13, %19 : i1
    llvm.store %17, %arg1 : i64, !llvm.ptr
    %21 = arith.extui %20 : i1 to i64
    return %21 : i64
  }
}

