module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb11,
      0: ^bb10,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8,
      9: ^bb9,
      10: ^bb10
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb14
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb13
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 2 preds: ^bb0, ^bb24
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // pred: ^bb0
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
    cf.cond_br %6, ^bb13, ^bb11
  ^bb5:  // pred: ^bb0
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
    cf.cond_br %13, ^bb14, ^bb11
  ^bb6:  // 3 preds: ^bb0, ^bb18, ^bb21
    %c712_i64_5 = arith.constant 712 : i64
    %14 = llvm.getelementptr %arg1[%c712_i64_5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %15 = llvm.load %14 : !llvm.ptr -> i32
    %c716_i64_6 = arith.constant 716 : i64
    %16 = llvm.getelementptr %arg1[%c716_i64_6] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %17 = llvm.load %16 : !llvm.ptr -> i32
    %c1_i32_7 = arith.constant 1 : i32
    %18 = arith.cmpi eq, %15, %c1_i32_7 : i32
    %c1_i32_8 = arith.constant 1 : i32
    %19 = arith.cmpi eq, %17, %c1_i32_8 : i32
    %20 = arith.andi %18, %19 : i1
    cf.cond_br %20, ^bb15, ^bb11
  ^bb7:  // 2 preds: ^bb0, ^bb25
    %c24_i64 = arith.constant 24 : i64
    %21 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %22 = llvm.load %21 : !llvm.ptr -> !llvm.ptr
    %23 = llvm.mlir.zero : !llvm.ptr
    %24 = llvm.icmp "eq" %22, %23 : !llvm.ptr
    cf.cond_br %24, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb25
    %c32_i64 = arith.constant 32 : i64
    %25 = llvm.getelementptr %arg1[%c32_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %26 = llvm.load %25 : !llvm.ptr -> !llvm.ptr
    %27 = llvm.mlir.zero : !llvm.ptr
    %28 = llvm.icmp "eq" %26, %27 : !llvm.ptr
    cf.cond_br %28, ^bb19, ^bb20
  ^bb9:  // 2 preds: ^bb0, ^bb33
    %c16_i64 = arith.constant 16 : i64
    %29 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %30 = llvm.load %29 : !llvm.ptr -> !llvm.ptr
    %31 = llvm.mlir.zero : !llvm.ptr
    %32 = llvm.icmp "eq" %30, %31 : !llvm.ptr
    cf.cond_br %32, ^bb22, ^bb23
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %c0_i64_9 = arith.constant 0 : i64
    %33 = llvm.getelementptr %arg1[%c0_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %34 = llvm.load %33 : !llvm.ptr -> !llvm.ptr
    %35 = llvm.mlir.zero : !llvm.ptr
    %36 = llvm.icmp "eq" %34, %35 : !llvm.ptr
    cf.cond_br %36, ^bb26, ^bb27
  ^bb11:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb30
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb12:  // pred: ^bb15
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb13:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %37 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %37 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_10 = arith.constant 716 : i64
    %38 = llvm.getelementptr %arg1[%c716_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %38 : i32, !llvm.ptr
    %c1_i32_11 = arith.constant 1 : i32
    %39 = arith.subi %1, %c1_i32_11 : i32
    %c712_i64_12 = arith.constant 712 : i64
    %40 = llvm.getelementptr %arg1[%c712_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %39, %40 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb14:  // pred: ^bb5
    %c0_i8_13 = arith.constant 0 : i8
    %c641_i64_14 = arith.constant 641 : i64
    %41 = llvm.getelementptr %arg1[%c641_i64_14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_13, %41 : i8, !llvm.ptr
    %c0_i32_15 = arith.constant 0 : i32
    %c716_i64_16 = arith.constant 716 : i64
    %42 = llvm.getelementptr %arg1[%c716_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_15, %42 : i32, !llvm.ptr
    %c1_i32_17 = arith.constant 1 : i32
    %43 = arith.subi %8, %c1_i32_17 : i32
    %c712_i64_18 = arith.constant 712 : i64
    %44 = llvm.getelementptr %arg1[%c712_i64_18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %43, %44 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb15:  // pred: ^bb6
    %c0_i8_19 = arith.constant 0 : i8
    %c641_i64_20 = arith.constant 641 : i64
    %45 = llvm.getelementptr %arg1[%c641_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_19, %45 : i8, !llvm.ptr
    %c0_i32_21 = arith.constant 0 : i32
    %c716_i64_22 = arith.constant 716 : i64
    %46 = llvm.getelementptr %arg1[%c716_i64_22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_21, %46 : i32, !llvm.ptr
    %c1_i32_23 = arith.constant 1 : i32
    %47 = arith.subi %15, %c1_i32_23 : i32
    %c712_i64_24 = arith.constant 712 : i64
    %48 = llvm.getelementptr %arg1[%c712_i64_24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %47, %48 : i32, !llvm.ptr
    cf.br ^bb12
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb17:  // pred: ^bb7
    %c0_i64_25 = arith.constant 0 : i64
    %49 = llvm.getelementptr %22[%c0_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %50 = llvm.load %49 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %51 = arith.cmpi ule, %50, %c2_i8 : i8
    cf.cond_br %51, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %c3_i32 = arith.constant 3 : i32
    %c728_i64 = arith.constant 728 : i64
    %52 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c3_i32, %52 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb19:  // 2 preds: ^bb8, ^bb20
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb20:  // pred: ^bb8
    %c0_i64_26 = arith.constant 0 : i64
    %53 = llvm.getelementptr %26[%c0_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %54 = llvm.load %53 : !llvm.ptr -> i8
    %c2_i8_27 = arith.constant 2 : i8
    %55 = arith.cmpi ule, %54, %c2_i8_27 : i8
    cf.cond_br %55, ^bb19, ^bb21
  ^bb21:  // pred: ^bb20
    %c4_i32 = arith.constant 4 : i32
    %c728_i64_28 = arith.constant 728 : i64
    %56 = llvm.getelementptr %arg1[%c728_i64_28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c4_i32, %56 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb22:  // 2 preds: ^bb9, ^bb23
    %c66_i64 = arith.constant 66 : i64
    return %c66_i64 : i64
  ^bb23:  // pred: ^bb9
    %c0_i64_29 = arith.constant 0 : i64
    %57 = llvm.getelementptr %30[%c0_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %58 = llvm.load %57 : !llvm.ptr -> i8
    %c2_i8_30 = arith.constant 2 : i8
    %59 = arith.cmpi ule, %58, %c2_i8_30 : i8
    cf.cond_br %59, ^bb22, ^bb24
  ^bb24:  // pred: ^bb23
    %c5_i8 = arith.constant 5 : i8
    %60 = arith.cmpi eq, %58, %c5_i8 : i8
    cf.cond_br %60, ^bb25, ^bb3
  ^bb25:  // pred: ^bb24
    %c8_i64 = arith.constant 8 : i64
    %61 = llvm.getelementptr %30[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %62 = llvm.load %61 : !llvm.ptr -> i8
    %c0_i8_31 = arith.constant 0 : i8
    %63 = arith.cmpi ne, %62, %c0_i8_31 : i8
    cf.cond_br %63, ^bb7, ^bb8
  ^bb26:  // pred: ^bb10
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb27:  // pred: ^bb10
    %c0_i64_32 = arith.constant 0 : i64
    %64 = llvm.getelementptr %34[%c0_i64_32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %65 = llvm.load %64 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %66 = arith.cmpi eq, %65, %c11_i8 : i8
    cf.cond_br %66, ^bb28, ^bb29
  ^bb28:  // pred: ^bb27
    %c8_i64_33 = arith.constant 8 : i64
    %67 = llvm.getelementptr %34[%c8_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %68 = llvm.load %67 : !llvm.ptr -> !llvm.ptr
    %c5417056880_i64 = arith.constant 5417056880 : i64
    %69 = llvm.inttoptr %c5417056880_i64 : i64 to !llvm.ptr
    %70 = llvm.icmp "eq" %68, %69 : !llvm.ptr
    cf.cond_br %70, ^bb30, ^bb29
  ^bb29:  // 2 preds: ^bb27, ^bb28
    %c79_i64 = arith.constant 79 : i64
    return %c79_i64 : i64
  ^bb30:  // pred: ^bb28
    %c712_i64_34 = arith.constant 712 : i64
    %71 = llvm.getelementptr %arg1[%c712_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %72 = llvm.load %71 : !llvm.ptr -> i32
    %c716_i64_35 = arith.constant 716 : i64
    %73 = llvm.getelementptr %arg1[%c716_i64_35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %74 = llvm.load %73 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %75 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %76 = llvm.load %75 : !llvm.ptr -> i8
    %c0_i32_36 = arith.constant 0 : i32
    %77 = arith.cmpi eq, %72, %c0_i32_36 : i32
    %c0_i32_37 = arith.constant 0 : i32
    %78 = arith.cmpi eq, %74, %c0_i32_37 : i32
    %79 = arith.andi %77, %78 : i1
    %c0_i8_38 = arith.constant 0 : i8
    %80 = arith.cmpi ne, %76, %c0_i8_38 : i8
    %81 = arith.andi %79, %80 : i1
    cf.cond_br %81, ^bb31, ^bb11
  ^bb31:  // pred: ^bb30
    %c704_i64 = arith.constant 704 : i64
    %82 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %83 = llvm.load %82 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %84 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %85 = llvm.load %84 : !llvm.ptr -> i32
    %86 = arith.extui %83 : i32 to i64
    %87 = arith.extui %72 : i32 to i64
    %88 = arith.addi %86, %87 : i64
    %89 = arith.extui %85 : i32 to i64
    %90 = arith.cmpi uge, %88, %89 : i64
    cf.cond_br %90, ^bb32, ^bb33
  ^bb32:  // pred: ^bb31
    %c77_i64 = arith.constant 77 : i64
    return %c77_i64 : i64
  ^bb33:  // pred: ^bb31
    %c16_i64_39 = arith.constant 16 : i64
    %91 = llvm.getelementptr %34[%c16_i64_39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %92 = llvm.load %91 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %93 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %92, %93 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_40 = arith.constant 641 : i64
    %94 = llvm.getelementptr %arg1[%c641_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %94 : i8, !llvm.ptr
    %c1_i32_41 = arith.constant 1 : i32
    %c716_i64_42 = arith.constant 716 : i64
    %95 = llvm.getelementptr %arg1[%c716_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_41, %95 : i32, !llvm.ptr
    %c1_i32_43 = arith.constant 1 : i32
    %96 = arith.addi %72, %c1_i32_43 : i32
    %c712_i64_44 = arith.constant 712 : i64
    %97 = llvm.getelementptr %arg1[%c712_i64_44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %96, %97 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %98 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %99 = llvm.load %98 : !llvm.ptr -> i32
    %c1_i32_45 = arith.constant 1 : i32
    %100 = arith.addi %99, %c1_i32_45 : i32
    %c720_i64_46 = arith.constant 720 : i64
    %101 = llvm.getelementptr %arg1[%c720_i64_46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %100, %101 : i32, !llvm.ptr
    %102 = llvm.mlir.zero : !llvm.ptr
    %c16_i64_47 = arith.constant 16 : i64
    %103 = llvm.getelementptr %arg1[%c16_i64_47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %102, %103 : !llvm.ptr, !llvm.ptr
    %104 = llvm.mlir.zero : !llvm.ptr
    %c24_i64_48 = arith.constant 24 : i64
    %105 = llvm.getelementptr %arg1[%c24_i64_48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %104, %105 : !llvm.ptr, !llvm.ptr
    %106 = llvm.mlir.zero : !llvm.ptr
    %c32_i64_49 = arith.constant 32 : i64
    %107 = llvm.getelementptr %arg1[%c32_i64_49] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %106, %107 : !llvm.ptr, !llvm.ptr
    cf.br ^bb9
  }
}

