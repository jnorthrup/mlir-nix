module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb5,
      0: ^bb4,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4
    ]
  ^bb1:  // pred: ^bb0
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // pred: ^bb0
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // pred: ^bb0
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb0
    %true = arith.constant true
    %0 = llvm.mlir.zero : !llvm.ptr
    %c0_i64_0 = arith.constant 0 : i64
    %1 = llvm.getelementptr %arg1[%c0_i64_0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %2 = llvm.load %1 : !llvm.ptr -> !llvm.ptr
    %3 = llvm.icmp "ne" %2, %0 : !llvm.ptr
    %4 = arith.andi %true, %3 : i1
    %c8_i64 = arith.constant 8 : i64
    %5 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %6 = llvm.load %5 : !llvm.ptr -> !llvm.ptr
    %7 = llvm.icmp "ne" %6, %0 : !llvm.ptr
    %8 = arith.andi %4, %7 : i1
    %c0_i64_1 = arith.constant 0 : i64
    %9 = llvm.getelementptr %arg1[%c0_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> !llvm.ptr
    %11 = llvm.icmp "ne" %10, %0 : !llvm.ptr
    %12 = arith.andi %8, %11 : i1
    cf.cond_br %12, ^bb8, ^bb7
  ^bb5:  // pred: ^bb0
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb6:  // pred: ^bb8
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb7:  // pred: ^bb4
    %c26_i64 = arith.constant 26 : i64
    return %c26_i64 : i64
  ^bb8:  // pred: ^bb4
    %c20_i32 = arith.constant 20 : i32
    %c728_i64 = arith.constant 728 : i64
    %13 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c20_i32, %13 : i32, !llvm.ptr
    cf.br ^bb6
  }
}

