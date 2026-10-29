module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb9,
      0: ^bb8,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8
    ]
  ^bb1:  // pred: ^bb0
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // pred: ^bb0
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb13, ^bb16
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb20
    %c30_i64 = arith.constant 30 : i64
    return %c30_i64 : i64
  ^bb5:  // 3 preds: ^bb0, ^bb12, ^bb15
    %c38_i64 = arith.constant 38 : i64
    return %c38_i64 : i64
  ^bb6:  // 2 preds: ^bb0, ^bb20
    %c8_i64 = arith.constant 8 : i64
    %0 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> !llvm.ptr
    %2 = llvm.mlir.zero : !llvm.ptr
    %3 = llvm.icmp "eq" %1, %2 : !llvm.ptr
    cf.cond_br %3, ^bb10, ^bb11
  ^bb7:  // pred: ^bb0
    %c8_i64_0 = arith.constant 8 : i64
    %4 = llvm.getelementptr %arg1[%c8_i64_0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    cf.cond_br %7, ^bb18, ^bb19
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %c0_i64_1 = arith.constant 0 : i64
    %8 = llvm.getelementptr %arg1[%c0_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %9 = llvm.load %8 : !llvm.ptr -> !llvm.ptr
    %10 = llvm.mlir.zero : !llvm.ptr
    %11 = llvm.icmp "eq" %9, %10 : !llvm.ptr
    cf.cond_br %11, ^bb21, ^bb22
  ^bb9:  // pred: ^bb0
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb10:  // 2 preds: ^bb6, ^bb11
    %c42_i64 = arith.constant 42 : i64
    return %c42_i64 : i64
  ^bb11:  // pred: ^bb6
    %c0_i64_2 = arith.constant 0 : i64
    %12 = llvm.getelementptr %1[%c0_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %13 = llvm.load %12 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %14 = arith.cmpi ule, %13, %c2_i8 : i8
    cf.cond_br %14, ^bb10, ^bb12
  ^bb12:  // pred: ^bb11
    %c9_i8 = arith.constant 9 : i8
    %15 = arith.cmpi eq, %13, %c9_i8 : i8
    cf.cond_br %15, ^bb13, ^bb5
  ^bb13:  // pred: ^bb12
    %c8_i64_3 = arith.constant 8 : i64
    %16 = llvm.getelementptr %1[%c8_i64_3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %17 = llvm.load %16 : !llvm.ptr -> !llvm.ptr
    %c0_i64_4 = arith.constant 0 : i64
    %18 = llvm.getelementptr %17[%c0_i64_4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %19 = llvm.load %18 : !llvm.ptr -> i32
    %c-1_i32 = arith.constant -1 : i32
    %20 = arith.cmpi eq, %19, %c-1_i32 : i32
    cf.cond_br %20, ^bb3, ^bb14
  ^bb14:  // pred: ^bb13
    %21 = arith.extui %19 : i32 to i64
    %c0_i64_5 = arith.constant 0 : i64
    cf.br ^bb15(%c0_i64_5, %21 : i64, i64)
  ^bb15(%22: i64, %23: i64):  // 2 preds: ^bb14, ^bb17
    %24 = arith.cmpi ult, %22, %23 : i64
    cf.cond_br %24, ^bb16, ^bb5
  ^bb16:  // pred: ^bb15
    %25 = arith.addi %22, %23 : i64
    %c1_i64_6 = arith.constant 1 : i64
    %26 = arith.shrui %25, %c1_i64_6 : i64
    %c16_i64 = arith.constant 16 : i64
    %c16_i64_7 = arith.constant 16 : i64
    %27 = arith.muli %26, %c16_i64_7 : i64
    %28 = arith.addi %c16_i64, %27 : i64
    %29 = llvm.getelementptr %17[%28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %30 = llvm.load %29 : !llvm.ptr -> i32
    %c5_i32 = arith.constant 5 : i32
    %31 = arith.cmpi eq, %30, %c5_i32 : i32
    cf.cond_br %31, ^bb3, ^bb17
  ^bb17:  // pred: ^bb16
    %c5_i32_8 = arith.constant 5 : i32
    %32 = arith.cmpi ult, %30, %c5_i32_8 : i32
    %c1_i64_9 = arith.constant 1 : i64
    %33 = arith.addi %26, %c1_i64_9 : i64
    %34 = arith.select %32, %33, %22 : i64
    %35 = arith.select %32, %23, %26 : i64
    cf.br ^bb15(%34, %35 : i64, i64)
  ^bb18:  // 2 preds: ^bb7, ^bb19
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb19:  // pred: ^bb7
    %c0_i64_10 = arith.constant 0 : i64
    %36 = llvm.getelementptr %5[%c0_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> i8
    %c2_i8_11 = arith.constant 2 : i8
    %38 = arith.cmpi ule, %37, %c2_i8_11 : i8
    cf.cond_br %38, ^bb18, ^bb20
  ^bb20:  // pred: ^bb19
    %c11_i8 = arith.constant 11 : i8
    %39 = arith.cmpi eq, %37, %c11_i8 : i8
    %c12_i8 = arith.constant 12 : i8
    %40 = arith.cmpi eq, %37, %c12_i8 : i8
    %c13_i8 = arith.constant 13 : i8
    %41 = arith.cmpi eq, %37, %c13_i8 : i8
    %42 = arith.ori %40, %41 : i1
    %43 = arith.ori %39, %42 : i1
    cf.cond_br %43, ^bb4, ^bb6
  ^bb21:  // pred: ^bb8
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb22:  // pred: ^bb8
    %c0_i64_12 = arith.constant 0 : i64
    %44 = llvm.getelementptr %9[%c0_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %45 = llvm.load %44 : !llvm.ptr -> i8
    %c11_i8_13 = arith.constant 11 : i8
    %46 = arith.cmpi eq, %45, %c11_i8_13 : i8
    cf.cond_br %46, ^bb23, ^bb24
  ^bb23:  // pred: ^bb22
    %c8_i64_14 = arith.constant 8 : i64
    %47 = llvm.getelementptr %9[%c8_i64_14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %48 = llvm.load %47 : !llvm.ptr -> !llvm.ptr
    %c5383500368_i64 = arith.constant 5383500368 : i64
    %49 = llvm.inttoptr %c5383500368_i64 : i64 to !llvm.ptr
    %50 = llvm.icmp "eq" %48, %49 : !llvm.ptr
    cf.cond_br %50, ^bb25, ^bb24
  ^bb24:  // 2 preds: ^bb22, ^bb23
    %c63_i64 = arith.constant 63 : i64
    return %c63_i64 : i64
  ^bb25:  // pred: ^bb23
    %c61_i64 = arith.constant 61 : i64
    return %c61_i64 : i64
  }
}

