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
  ^bb3:  // 2 preds: ^bb0, ^bb17
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb18
    %c16_i64 = arith.constant 16 : i64
    %0 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> !llvm.ptr
    %2 = llvm.mlir.zero : !llvm.ptr
    %3 = llvm.icmp "eq" %1, %2 : !llvm.ptr
    cf.cond_br %3, ^bb9, ^bb10
  ^bb5:  // 2 preds: ^bb0, ^bb18
    %c24_i64 = arith.constant 24 : i64
    %4 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    cf.cond_br %7, ^bb12, ^bb13
  ^bb6:  // 2 preds: ^bb0, ^bb0
    %c0_i64_0 = arith.constant 0 : i64
    %8 = llvm.getelementptr %arg1[%c0_i64_0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %9 = llvm.load %8 : !llvm.ptr -> !llvm.ptr
    %10 = llvm.mlir.zero : !llvm.ptr
    %11 = llvm.icmp "eq" %9, %10 : !llvm.ptr
    cf.cond_br %11, ^bb15, ^bb16
  ^bb7:  // pred: ^bb0
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb8:  // 2 preds: ^bb11, ^bb14
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb9:  // 2 preds: ^bb4, ^bb10
    %c26_i64 = arith.constant 26 : i64
    return %c26_i64 : i64
  ^bb10:  // pred: ^bb4
    %c0_i64_1 = arith.constant 0 : i64
    %12 = llvm.getelementptr %1[%c0_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %13 = llvm.load %12 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %14 = arith.cmpi ule, %13, %c2_i8 : i8
    cf.cond_br %14, ^bb9, ^bb11
  ^bb11:  // pred: ^bb10
    %c2_i32 = arith.constant 2 : i32
    %c728_i64 = arith.constant 728 : i64
    %15 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c2_i32, %15 : i32, !llvm.ptr
    cf.br ^bb8
  ^bb12:  // 2 preds: ^bb5, ^bb13
    %c34_i64 = arith.constant 34 : i64
    return %c34_i64 : i64
  ^bb13:  // pred: ^bb5
    %c0_i64_2 = arith.constant 0 : i64
    %16 = llvm.getelementptr %5[%c0_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %17 = llvm.load %16 : !llvm.ptr -> i8
    %c2_i8_3 = arith.constant 2 : i8
    %18 = arith.cmpi ule, %17, %c2_i8_3 : i8
    cf.cond_br %18, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %c3_i32 = arith.constant 3 : i32
    %c728_i64_4 = arith.constant 728 : i64
    %19 = llvm.getelementptr %arg1[%c728_i64_4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c3_i32, %19 : i32, !llvm.ptr
    cf.br ^bb8
  ^bb15:  // 2 preds: ^bb6, ^bb16
    %c42_i64 = arith.constant 42 : i64
    return %c42_i64 : i64
  ^bb16:  // pred: ^bb6
    %c0_i64_5 = arith.constant 0 : i64
    %20 = llvm.getelementptr %9[%c0_i64_5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %21 = llvm.load %20 : !llvm.ptr -> i8
    %c2_i8_6 = arith.constant 2 : i8
    %22 = arith.cmpi ule, %21, %c2_i8_6 : i8
    cf.cond_br %22, ^bb15, ^bb17
  ^bb17:  // pred: ^bb16
    %c5_i8 = arith.constant 5 : i8
    %23 = arith.cmpi eq, %21, %c5_i8 : i8
    cf.cond_br %23, ^bb18, ^bb3
  ^bb18:  // pred: ^bb17
    %c8_i64 = arith.constant 8 : i64
    %24 = llvm.getelementptr %9[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %25 = llvm.load %24 : !llvm.ptr -> i8
    %c0_i8 = arith.constant 0 : i8
    %26 = arith.cmpi ne, %25, %c0_i8 : i8
    cf.cond_br %26, ^bb4, ^bb5
  }
}

