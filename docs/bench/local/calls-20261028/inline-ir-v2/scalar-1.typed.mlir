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
  ^bb1:  // 2 preds: ^bb0, ^bb10
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb11
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb15, ^bb18
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb22
    %c712_i64 = arith.constant 712 : i64
    %0 = llvm.getelementptr %arg1[%c712_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> i32
    %c716_i64 = arith.constant 716 : i64
    %2 = llvm.getelementptr %arg1[%c716_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %3 = llvm.load %2 : !llvm.ptr -> i32
    %c1_i32 = arith.constant 1 : i32
    %4 = arith.cmpi eq, %1, %c1_i32 : i32
    %c1_i32_0 = arith.constant 1 : i32
    %5 = arith.cmpi eq, %3, %c1_i32_0 : i32
    %6 = arith.andi %4, %5 : i1
    cf.cond_br %6, ^bb10, ^bb9
  ^bb5:  // 3 preds: ^bb0, ^bb14, ^bb17
    %c712_i64_1 = arith.constant 712 : i64
    %7 = llvm.getelementptr %arg1[%c712_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %8 = llvm.load %7 : !llvm.ptr -> i32
    %c716_i64_2 = arith.constant 716 : i64
    %9 = llvm.getelementptr %arg1[%c716_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> i32
    %c1_i32_3 = arith.constant 1 : i32
    %11 = arith.cmpi eq, %8, %c1_i32_3 : i32
    %c1_i32_4 = arith.constant 1 : i32
    %12 = arith.cmpi eq, %10, %c1_i32_4 : i32
    %13 = arith.andi %11, %12 : i1
    cf.cond_br %13, ^bb11, ^bb9
  ^bb6:  // 2 preds: ^bb0, ^bb22
    %c8_i64 = arith.constant 8 : i64
    %14 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %15 = llvm.load %14 : !llvm.ptr -> !llvm.ptr
    %16 = llvm.mlir.zero : !llvm.ptr
    %17 = llvm.icmp "eq" %15, %16 : !llvm.ptr
    cf.cond_br %17, ^bb12, ^bb13
  ^bb7:  // 2 preds: ^bb0, ^bb30
    %c8_i64_5 = arith.constant 8 : i64
    %18 = llvm.getelementptr %arg1[%c8_i64_5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %19 = llvm.load %18 : !llvm.ptr -> !llvm.ptr
    %20 = llvm.mlir.zero : !llvm.ptr
    %21 = llvm.icmp "eq" %19, %20 : !llvm.ptr
    cf.cond_br %21, ^bb20, ^bb21
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %c0_i64_6 = arith.constant 0 : i64
    %22 = llvm.getelementptr %arg1[%c0_i64_6] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %23 = llvm.load %22 : !llvm.ptr -> !llvm.ptr
    %24 = llvm.mlir.zero : !llvm.ptr
    %25 = llvm.icmp "eq" %23, %24 : !llvm.ptr
    cf.cond_br %25, ^bb23, ^bb24
  ^bb9:  // 4 preds: ^bb0, ^bb4, ^bb5, ^bb27
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb10:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %26 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %26 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_7 = arith.constant 716 : i64
    %27 = llvm.getelementptr %arg1[%c716_i64_7] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %27 : i32, !llvm.ptr
    %c1_i32_8 = arith.constant 1 : i32
    %28 = arith.subi %1, %c1_i32_8 : i32
    %c712_i64_9 = arith.constant 712 : i64
    %29 = llvm.getelementptr %arg1[%c712_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %28, %29 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb11:  // pred: ^bb5
    %c0_i8_10 = arith.constant 0 : i8
    %c641_i64_11 = arith.constant 641 : i64
    %30 = llvm.getelementptr %arg1[%c641_i64_11] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_10, %30 : i8, !llvm.ptr
    %c0_i32_12 = arith.constant 0 : i32
    %c716_i64_13 = arith.constant 716 : i64
    %31 = llvm.getelementptr %arg1[%c716_i64_13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_12, %31 : i32, !llvm.ptr
    %c1_i32_14 = arith.constant 1 : i32
    %32 = arith.subi %8, %c1_i32_14 : i32
    %c712_i64_15 = arith.constant 712 : i64
    %33 = llvm.getelementptr %arg1[%c712_i64_15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %32, %33 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb12:  // 2 preds: ^bb6, ^bb13
    %c42_i64 = arith.constant 42 : i64
    return %c42_i64 : i64
  ^bb13:  // pred: ^bb6
    %c0_i64_16 = arith.constant 0 : i64
    %34 = llvm.getelementptr %15[%c0_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %35 = llvm.load %34 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %36 = arith.cmpi ule, %35, %c2_i8 : i8
    cf.cond_br %36, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %c9_i8 = arith.constant 9 : i8
    %37 = arith.cmpi eq, %35, %c9_i8 : i8
    cf.cond_br %37, ^bb15, ^bb5
  ^bb15:  // pred: ^bb14
    %c8_i64_17 = arith.constant 8 : i64
    %38 = llvm.getelementptr %15[%c8_i64_17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %39 = llvm.load %38 : !llvm.ptr -> !llvm.ptr
    %c0_i64_18 = arith.constant 0 : i64
    %40 = llvm.getelementptr %39[%c0_i64_18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %41 = llvm.load %40 : !llvm.ptr -> i32
    %c-1_i32 = arith.constant -1 : i32
    %42 = arith.cmpi eq, %41, %c-1_i32 : i32
    cf.cond_br %42, ^bb3, ^bb16
  ^bb16:  // pred: ^bb15
    %43 = arith.extui %41 : i32 to i64
    %c0_i64_19 = arith.constant 0 : i64
    cf.br ^bb17(%c0_i64_19, %43 : i64, i64)
  ^bb17(%44: i64, %45: i64):  // 2 preds: ^bb16, ^bb19
    %46 = arith.cmpi ult, %44, %45 : i64
    cf.cond_br %46, ^bb18, ^bb5
  ^bb18:  // pred: ^bb17
    %47 = arith.addi %44, %45 : i64
    %c1_i64_20 = arith.constant 1 : i64
    %48 = arith.shrui %47, %c1_i64_20 : i64
    %c16_i64 = arith.constant 16 : i64
    %c16_i64_21 = arith.constant 16 : i64
    %49 = arith.muli %48, %c16_i64_21 : i64
    %50 = arith.addi %c16_i64, %49 : i64
    %51 = llvm.getelementptr %39[%50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %52 = llvm.load %51 : !llvm.ptr -> i32
    %c5_i32 = arith.constant 5 : i32
    %53 = arith.cmpi eq, %52, %c5_i32 : i32
    cf.cond_br %53, ^bb3, ^bb19
  ^bb19:  // pred: ^bb18
    %c5_i32_22 = arith.constant 5 : i32
    %54 = arith.cmpi ult, %52, %c5_i32_22 : i32
    %c1_i64_23 = arith.constant 1 : i64
    %55 = arith.addi %48, %c1_i64_23 : i64
    %56 = arith.select %54, %55, %44 : i64
    %57 = arith.select %54, %45, %48 : i64
    cf.br ^bb17(%56, %57 : i64, i64)
  ^bb20:  // 2 preds: ^bb7, ^bb21
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb21:  // pred: ^bb7
    %c0_i64_24 = arith.constant 0 : i64
    %58 = llvm.getelementptr %19[%c0_i64_24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %59 = llvm.load %58 : !llvm.ptr -> i8
    %c2_i8_25 = arith.constant 2 : i8
    %60 = arith.cmpi ule, %59, %c2_i8_25 : i8
    cf.cond_br %60, ^bb20, ^bb22
  ^bb22:  // pred: ^bb21
    %c11_i8 = arith.constant 11 : i8
    %61 = arith.cmpi eq, %59, %c11_i8 : i8
    %c12_i8 = arith.constant 12 : i8
    %62 = arith.cmpi eq, %59, %c12_i8 : i8
    %c13_i8 = arith.constant 13 : i8
    %63 = arith.cmpi eq, %59, %c13_i8 : i8
    %64 = arith.ori %62, %63 : i1
    %65 = arith.ori %61, %64 : i1
    cf.cond_br %65, ^bb4, ^bb6
  ^bb23:  // pred: ^bb8
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb24:  // pred: ^bb8
    %c0_i64_26 = arith.constant 0 : i64
    %66 = llvm.getelementptr %23[%c0_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %67 = llvm.load %66 : !llvm.ptr -> i8
    %c11_i8_27 = arith.constant 11 : i8
    %68 = arith.cmpi eq, %67, %c11_i8_27 : i8
    cf.cond_br %68, ^bb25, ^bb26
  ^bb25:  // pred: ^bb24
    %c8_i64_28 = arith.constant 8 : i64
    %69 = llvm.getelementptr %23[%c8_i64_28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %70 = llvm.load %69 : !llvm.ptr -> !llvm.ptr
    %c5660331984_i64 = arith.constant 5660331984 : i64
    %71 = llvm.inttoptr %c5660331984_i64 : i64 to !llvm.ptr
    %72 = llvm.icmp "eq" %70, %71 : !llvm.ptr
    cf.cond_br %72, ^bb27, ^bb26
  ^bb26:  // 2 preds: ^bb24, ^bb25
    %c63_i64 = arith.constant 63 : i64
    return %c63_i64 : i64
  ^bb27:  // pred: ^bb25
    %c712_i64_29 = arith.constant 712 : i64
    %73 = llvm.getelementptr %arg1[%c712_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %74 = llvm.load %73 : !llvm.ptr -> i32
    %c716_i64_30 = arith.constant 716 : i64
    %75 = llvm.getelementptr %arg1[%c716_i64_30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %76 = llvm.load %75 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %77 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %78 = llvm.load %77 : !llvm.ptr -> i8
    %c0_i32_31 = arith.constant 0 : i32
    %79 = arith.cmpi eq, %74, %c0_i32_31 : i32
    %c0_i32_32 = arith.constant 0 : i32
    %80 = arith.cmpi eq, %76, %c0_i32_32 : i32
    %81 = arith.andi %79, %80 : i1
    %c0_i8_33 = arith.constant 0 : i8
    %82 = arith.cmpi ne, %78, %c0_i8_33 : i8
    %83 = arith.andi %81, %82 : i1
    cf.cond_br %83, ^bb28, ^bb9
  ^bb28:  // pred: ^bb27
    %c704_i64 = arith.constant 704 : i64
    %84 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %85 = llvm.load %84 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %86 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %87 = llvm.load %86 : !llvm.ptr -> i32
    %88 = arith.extui %85 : i32 to i64
    %89 = arith.extui %74 : i32 to i64
    %90 = arith.addi %88, %89 : i64
    %91 = arith.extui %87 : i32 to i64
    %92 = arith.cmpi uge, %90, %91 : i64
    cf.cond_br %92, ^bb29, ^bb30
  ^bb29:  // pred: ^bb28
    %c61_i64 = arith.constant 61 : i64
    return %c61_i64 : i64
  ^bb30:  // pred: ^bb28
    %c16_i64_34 = arith.constant 16 : i64
    %93 = llvm.getelementptr %23[%c16_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %94 = llvm.load %93 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %95 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %94, %95 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_35 = arith.constant 641 : i64
    %96 = llvm.getelementptr %arg1[%c641_i64_35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %96 : i8, !llvm.ptr
    %c1_i32_36 = arith.constant 1 : i32
    %c716_i64_37 = arith.constant 716 : i64
    %97 = llvm.getelementptr %arg1[%c716_i64_37] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_36, %97 : i32, !llvm.ptr
    %c1_i32_38 = arith.constant 1 : i32
    %98 = arith.addi %74, %c1_i32_38 : i32
    %c712_i64_39 = arith.constant 712 : i64
    %99 = llvm.getelementptr %arg1[%c712_i64_39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %98, %99 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %100 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %101 = llvm.load %100 : !llvm.ptr -> i32
    %c1_i32_40 = arith.constant 1 : i32
    %102 = arith.addi %101, %c1_i32_40 : i32
    %c720_i64_41 = arith.constant 720 : i64
    %103 = llvm.getelementptr %arg1[%c720_i64_41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %102, %103 : i32, !llvm.ptr
    cf.br ^bb7
  }
}

