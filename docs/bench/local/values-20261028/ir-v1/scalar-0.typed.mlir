module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb7,
      0: ^bb6,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6
    ]
  ^bb1:  // pred: ^bb0
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // pred: ^bb0
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 2 preds: ^bb0, ^bb14
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb15
    %c16_i64 = arith.constant 16 : i64
    %0 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> !llvm.ptr
    %2 = llvm.mlir.zero : !llvm.ptr
    %3 = llvm.icmp "eq" %1, %2 : !llvm.ptr
    cf.cond_br %3, ^bb9, ^bb10
  ^bb5:  // 2 preds: ^bb0, ^bb15
    %c18_i32 = arith.constant 18 : i32
    %c728_i64 = arith.constant 728 : i64
    %4 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c18_i32, %4 : i32, !llvm.ptr
    cf.br ^bb8
  ^bb6:  // 2 preds: ^bb0, ^bb0
    %c0_i64_0 = arith.constant 0 : i64
    %5 = llvm.getelementptr %arg1[%c0_i64_0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %6 = llvm.load %5 : !llvm.ptr -> !llvm.ptr
    %7 = llvm.mlir.zero : !llvm.ptr
    %8 = llvm.icmp "eq" %6, %7 : !llvm.ptr
    cf.cond_br %8, ^bb12, ^bb13
  ^bb7:  // pred: ^bb0
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb8:  // 2 preds: ^bb5, ^bb11
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb9:  // 2 preds: ^bb4, ^bb10
    %c26_i64 = arith.constant 26 : i64
    return %c26_i64 : i64
  ^bb10:  // pred: ^bb4
    %c0_i64_1 = arith.constant 0 : i64
    %9 = llvm.getelementptr %1[%c0_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %11 = arith.cmpi ule, %10, %c2_i8 : i8
    cf.cond_br %11, ^bb9, ^bb11
  ^bb11:  // pred: ^bb10
    %c2_i32 = arith.constant 2 : i32
    %c728_i64_2 = arith.constant 728 : i64
    %12 = llvm.getelementptr %arg1[%c728_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c2_i32, %12 : i32, !llvm.ptr
    cf.br ^bb8
  ^bb12:  // 2 preds: ^bb6, ^bb13
    %c42_i64 = arith.constant 42 : i64
    return %c42_i64 : i64
  ^bb13:  // pred: ^bb6
    %c0_i64_3 = arith.constant 0 : i64
    %13 = llvm.getelementptr %6[%c0_i64_3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %14 = llvm.load %13 : !llvm.ptr -> i8
    %c2_i8_4 = arith.constant 2 : i8
    %15 = arith.cmpi ule, %14, %c2_i8_4 : i8
    cf.cond_br %15, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %c5_i8 = arith.constant 5 : i8
    %16 = arith.cmpi eq, %14, %c5_i8 : i8
    cf.cond_br %16, ^bb15, ^bb3
  ^bb15:  // pred: ^bb14
    %c8_i64 = arith.constant 8 : i64
    %17 = llvm.getelementptr %6[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %18 = llvm.load %17 : !llvm.ptr -> i8
    %c0_i8 = arith.constant 0 : i8
    %19 = arith.cmpi ne, %18, %c0_i8 : i8
    cf.cond_br %19, ^bb4, ^bb5
  }
}

