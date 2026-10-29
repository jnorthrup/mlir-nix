module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb6,
      0: ^bb5,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5
    ]
  ^bb1:  // 3 preds: ^bb0, ^bb9, ^bb12
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb17
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb10, ^bb13
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb17
    %c0_i64_0 = arith.constant 0 : i64
    %0 = llvm.getelementptr %arg1[%c0_i64_0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> !llvm.ptr
    %2 = llvm.mlir.zero : !llvm.ptr
    %3 = llvm.icmp "eq" %1, %2 : !llvm.ptr
    cf.cond_br %3, ^bb7, ^bb8
  ^bb5:  // 2 preds: ^bb0, ^bb0
    %c0_i64_1 = arith.constant 0 : i64
    %4 = llvm.getelementptr %arg1[%c0_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    cf.cond_br %7, ^bb15, ^bb16
  ^bb6:  // pred: ^bb0
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb7:  // 2 preds: ^bb4, ^bb8
    %c26_i64 = arith.constant 26 : i64
    return %c26_i64 : i64
  ^bb8:  // pred: ^bb4
    %c0_i64_2 = arith.constant 0 : i64
    %8 = llvm.getelementptr %1[%c0_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %9 = llvm.load %8 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %10 = arith.cmpi ule, %9, %c2_i8 : i8
    cf.cond_br %10, ^bb7, ^bb9
  ^bb9:  // pred: ^bb8
    %c9_i8 = arith.constant 9 : i8
    %11 = arith.cmpi eq, %9, %c9_i8 : i8
    cf.cond_br %11, ^bb10, ^bb1
  ^bb10:  // pred: ^bb9
    %c8_i64 = arith.constant 8 : i64
    %12 = llvm.getelementptr %1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %13 = llvm.load %12 : !llvm.ptr -> !llvm.ptr
    %c0_i64_3 = arith.constant 0 : i64
    %14 = llvm.getelementptr %13[%c0_i64_3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %15 = llvm.load %14 : !llvm.ptr -> i32
    %c-1_i32 = arith.constant -1 : i32
    %16 = arith.cmpi eq, %15, %c-1_i32 : i32
    cf.cond_br %16, ^bb3, ^bb11
  ^bb11:  // pred: ^bb10
    %17 = arith.extui %15 : i32 to i64
    %c0_i64_4 = arith.constant 0 : i64
    cf.br ^bb12(%c0_i64_4, %17 : i64, i64)
  ^bb12(%18: i64, %19: i64):  // 2 preds: ^bb11, ^bb14
    %20 = arith.cmpi ult, %18, %19 : i64
    cf.cond_br %20, ^bb13, ^bb1
  ^bb13:  // pred: ^bb12
    %21 = arith.addi %18, %19 : i64
    %c1_i64_5 = arith.constant 1 : i64
    %22 = arith.shrui %21, %c1_i64_5 : i64
    %c16_i64 = arith.constant 16 : i64
    %c16_i64_6 = arith.constant 16 : i64
    %23 = arith.muli %22, %c16_i64_6 : i64
    %24 = arith.addi %c16_i64, %23 : i64
    %25 = llvm.getelementptr %13[%24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %26 = llvm.load %25 : !llvm.ptr -> i32
    %c5_i32 = arith.constant 5 : i32
    %27 = arith.cmpi eq, %26, %c5_i32 : i32
    cf.cond_br %27, ^bb3, ^bb14
  ^bb14:  // pred: ^bb13
    %c5_i32_7 = arith.constant 5 : i32
    %28 = arith.cmpi ult, %26, %c5_i32_7 : i32
    %c1_i64_8 = arith.constant 1 : i64
    %29 = arith.addi %22, %c1_i64_8 : i64
    %30 = arith.select %28, %29, %18 : i64
    %31 = arith.select %28, %19, %22 : i64
    cf.br ^bb12(%30, %31 : i64, i64)
  ^bb15:  // 2 preds: ^bb5, ^bb16
    %c34_i64 = arith.constant 34 : i64
    return %c34_i64 : i64
  ^bb16:  // pred: ^bb5
    %c0_i64_9 = arith.constant 0 : i64
    %32 = llvm.getelementptr %5[%c0_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %33 = llvm.load %32 : !llvm.ptr -> i8
    %c2_i8_10 = arith.constant 2 : i8
    %34 = arith.cmpi ule, %33, %c2_i8_10 : i8
    cf.cond_br %34, ^bb15, ^bb17
  ^bb17:  // pred: ^bb16
    %c11_i8 = arith.constant 11 : i8
    %35 = arith.cmpi eq, %33, %c11_i8 : i8
    %c12_i8 = arith.constant 12 : i8
    %36 = arith.cmpi eq, %33, %c12_i8 : i8
    %c13_i8 = arith.constant 13 : i8
    %37 = arith.cmpi eq, %33, %c13_i8 : i8
    %38 = arith.ori %36, %37 : i1
    %39 = arith.ori %35, %38 : i1
    cf.cond_br %39, ^bb2, ^bb4
  }
}

