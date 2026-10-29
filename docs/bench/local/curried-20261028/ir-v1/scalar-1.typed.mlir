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
  ^bb1:  // 3 preds: ^bb0, ^bb15, ^bb16
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 3 preds: ^bb0, ^bb15, ^bb17
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 5 preds: ^bb0, ^bb14, ^bb21, ^bb24, ^bb39
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb40
    %c8_i64 = arith.constant 8 : i64
    %0 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %1 = llvm.load %0 : !llvm.ptr -> !llvm.ptr
    %2 = llvm.mlir.zero : !llvm.ptr
    %3 = llvm.icmp "eq" %1, %2 : !llvm.ptr
    cf.cond_br %3, ^bb12, ^bb13
  ^bb5:  // 2 preds: ^bb0, ^bb28
    %c712_i64 = arith.constant 712 : i64
    %4 = llvm.getelementptr %arg1[%c712_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> i32
    %c716_i64 = arith.constant 716 : i64
    %6 = llvm.getelementptr %arg1[%c716_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %7 = llvm.load %6 : !llvm.ptr -> i32
    %c1_i32 = arith.constant 1 : i32
    %8 = arith.cmpi eq, %5, %c1_i32 : i32
    %c1_i32_0 = arith.constant 1 : i32
    %9 = arith.cmpi eq, %7, %c1_i32_0 : i32
    %10 = arith.andi %8, %9 : i1
    cf.cond_br %10, ^bb16, ^bb11
  ^bb6:  // 3 preds: ^bb0, ^bb20, ^bb23
    %c712_i64_1 = arith.constant 712 : i64
    %11 = llvm.getelementptr %arg1[%c712_i64_1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %12 = llvm.load %11 : !llvm.ptr -> i32
    %c716_i64_2 = arith.constant 716 : i64
    %13 = llvm.getelementptr %arg1[%c716_i64_2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %14 = llvm.load %13 : !llvm.ptr -> i32
    %c1_i32_3 = arith.constant 1 : i32
    %15 = arith.cmpi eq, %12, %c1_i32_3 : i32
    %c1_i32_4 = arith.constant 1 : i32
    %16 = arith.cmpi eq, %14, %c1_i32_4 : i32
    %17 = arith.andi %15, %16 : i1
    cf.cond_br %17, ^bb17, ^bb11
  ^bb7:  // 2 preds: ^bb0, ^bb28
    %c24_i64 = arith.constant 24 : i64
    %18 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %19 = llvm.load %18 : !llvm.ptr -> !llvm.ptr
    %20 = llvm.mlir.zero : !llvm.ptr
    %21 = llvm.icmp "eq" %19, %20 : !llvm.ptr
    cf.cond_br %21, ^bb18, ^bb19
  ^bb8:  // 2 preds: ^bb0, ^bb36
    %c24_i64_5 = arith.constant 24 : i64
    %22 = llvm.getelementptr %arg1[%c24_i64_5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %23 = llvm.load %22 : !llvm.ptr -> !llvm.ptr
    %24 = llvm.mlir.zero : !llvm.ptr
    %25 = llvm.icmp "eq" %23, %24 : !llvm.ptr
    cf.cond_br %25, ^bb26, ^bb27
  ^bb9:  // 2 preds: ^bb0, ^bb40
    %c16_i64 = arith.constant 16 : i64
    %26 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.mlir.zero : !llvm.ptr
    %29 = llvm.icmp "eq" %27, %28 : !llvm.ptr
    cf.cond_br %29, ^bb29, ^bb30
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %c0_i64_6 = arith.constant 0 : i64
    %30 = llvm.getelementptr %arg1[%c0_i64_6] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %31 = llvm.load %30 : !llvm.ptr -> !llvm.ptr
    %32 = llvm.mlir.zero : !llvm.ptr
    %33 = llvm.icmp "eq" %31, %32 : !llvm.ptr
    cf.cond_br %33, ^bb37, ^bb38
  ^bb11:  // 4 preds: ^bb0, ^bb5, ^bb6, ^bb33
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb12:  // 2 preds: ^bb4, ^bb13
    %c26_i64 = arith.constant 26 : i64
    return %c26_i64 : i64
  ^bb13:  // pred: ^bb4
    %c0_i64_7 = arith.constant 0 : i64
    %34 = llvm.getelementptr %1[%c0_i64_7] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %35 = llvm.load %34 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %36 = arith.cmpi ule, %35, %c2_i8 : i8
    cf.cond_br %36, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %c5_i8 = arith.constant 5 : i8
    %37 = arith.cmpi eq, %35, %c5_i8 : i8
    cf.cond_br %37, ^bb15, ^bb3
  ^bb15:  // pred: ^bb14
    %c8_i64_8 = arith.constant 8 : i64
    %38 = llvm.getelementptr %1[%c8_i64_8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %39 = llvm.load %38 : !llvm.ptr -> i8
    %c0_i8 = arith.constant 0 : i8
    %40 = arith.cmpi ne, %39, %c0_i8 : i8
    cf.cond_br %40, ^bb1, ^bb2
  ^bb16:  // pred: ^bb5
    %c0_i8_9 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %41 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_9, %41 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_10 = arith.constant 716 : i64
    %42 = llvm.getelementptr %arg1[%c716_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %42 : i32, !llvm.ptr
    %c1_i32_11 = arith.constant 1 : i32
    %43 = arith.subi %5, %c1_i32_11 : i32
    %c712_i64_12 = arith.constant 712 : i64
    %44 = llvm.getelementptr %arg1[%c712_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %43, %44 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb17:  // pred: ^bb6
    %c0_i8_13 = arith.constant 0 : i8
    %c641_i64_14 = arith.constant 641 : i64
    %45 = llvm.getelementptr %arg1[%c641_i64_14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_13, %45 : i8, !llvm.ptr
    %c0_i32_15 = arith.constant 0 : i32
    %c716_i64_16 = arith.constant 716 : i64
    %46 = llvm.getelementptr %arg1[%c716_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_15, %46 : i32, !llvm.ptr
    %c1_i32_17 = arith.constant 1 : i32
    %47 = arith.subi %12, %c1_i32_17 : i32
    %c712_i64_18 = arith.constant 712 : i64
    %48 = llvm.getelementptr %arg1[%c712_i64_18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %47, %48 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb18:  // 2 preds: ^bb7, ^bb19
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb19:  // pred: ^bb7
    %c0_i64_19 = arith.constant 0 : i64
    %49 = llvm.getelementptr %19[%c0_i64_19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %50 = llvm.load %49 : !llvm.ptr -> i8
    %c2_i8_20 = arith.constant 2 : i8
    %51 = arith.cmpi ule, %50, %c2_i8_20 : i8
    cf.cond_br %51, ^bb18, ^bb20
  ^bb20:  // pred: ^bb19
    %c9_i8 = arith.constant 9 : i8
    %52 = arith.cmpi eq, %50, %c9_i8 : i8
    cf.cond_br %52, ^bb21, ^bb6
  ^bb21:  // pred: ^bb20
    %c8_i64_21 = arith.constant 8 : i64
    %53 = llvm.getelementptr %19[%c8_i64_21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %54 = llvm.load %53 : !llvm.ptr -> !llvm.ptr
    %c0_i64_22 = arith.constant 0 : i64
    %55 = llvm.getelementptr %54[%c0_i64_22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %56 = llvm.load %55 : !llvm.ptr -> i32
    %c-1_i32 = arith.constant -1 : i32
    %57 = arith.cmpi eq, %56, %c-1_i32 : i32
    cf.cond_br %57, ^bb3, ^bb22
  ^bb22:  // pred: ^bb21
    %58 = arith.extui %56 : i32 to i64
    %c0_i64_23 = arith.constant 0 : i64
    cf.br ^bb23(%c0_i64_23, %58 : i64, i64)
  ^bb23(%59: i64, %60: i64):  // 2 preds: ^bb22, ^bb25
    %61 = arith.cmpi ult, %59, %60 : i64
    cf.cond_br %61, ^bb24, ^bb6
  ^bb24:  // pred: ^bb23
    %62 = arith.addi %59, %60 : i64
    %c1_i64_24 = arith.constant 1 : i64
    %63 = arith.shrui %62, %c1_i64_24 : i64
    %c16_i64_25 = arith.constant 16 : i64
    %c16_i64_26 = arith.constant 16 : i64
    %64 = arith.muli %63, %c16_i64_26 : i64
    %65 = arith.addi %c16_i64_25, %64 : i64
    %66 = llvm.getelementptr %54[%65] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %67 = llvm.load %66 : !llvm.ptr -> i32
    %c5_i32 = arith.constant 5 : i32
    %68 = arith.cmpi eq, %67, %c5_i32 : i32
    cf.cond_br %68, ^bb3, ^bb25
  ^bb25:  // pred: ^bb24
    %c5_i32_27 = arith.constant 5 : i32
    %69 = arith.cmpi ult, %67, %c5_i32_27 : i32
    %c1_i64_28 = arith.constant 1 : i64
    %70 = arith.addi %63, %c1_i64_28 : i64
    %71 = arith.select %69, %70, %59 : i64
    %72 = arith.select %69, %60, %63 : i64
    cf.br ^bb23(%71, %72 : i64, i64)
  ^bb26:  // 2 preds: ^bb8, ^bb27
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb27:  // pred: ^bb8
    %c0_i64_29 = arith.constant 0 : i64
    %73 = llvm.getelementptr %23[%c0_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %74 = llvm.load %73 : !llvm.ptr -> i8
    %c2_i8_30 = arith.constant 2 : i8
    %75 = arith.cmpi ule, %74, %c2_i8_30 : i8
    cf.cond_br %75, ^bb26, ^bb28
  ^bb28:  // pred: ^bb27
    %c11_i8 = arith.constant 11 : i8
    %76 = arith.cmpi eq, %74, %c11_i8 : i8
    %c12_i8 = arith.constant 12 : i8
    %77 = arith.cmpi eq, %74, %c12_i8 : i8
    %c13_i8 = arith.constant 13 : i8
    %78 = arith.cmpi eq, %74, %c13_i8 : i8
    %79 = arith.ori %77, %78 : i1
    %80 = arith.ori %76, %79 : i1
    cf.cond_br %80, ^bb5, ^bb7
  ^bb29:  // pred: ^bb9
    %c66_i64 = arith.constant 66 : i64
    return %c66_i64 : i64
  ^bb30:  // pred: ^bb9
    %c0_i64_31 = arith.constant 0 : i64
    %81 = llvm.getelementptr %27[%c0_i64_31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %82 = llvm.load %81 : !llvm.ptr -> i8
    %c11_i8_32 = arith.constant 11 : i8
    %83 = arith.cmpi eq, %82, %c11_i8_32 : i8
    cf.cond_br %83, ^bb31, ^bb32
  ^bb31:  // pred: ^bb30
    %c8_i64_33 = arith.constant 8 : i64
    %84 = llvm.getelementptr %27[%c8_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %85 = llvm.load %84 : !llvm.ptr -> !llvm.ptr
    %c5366731072_i64 = arith.constant 5366731072 : i64
    %86 = llvm.inttoptr %c5366731072_i64 : i64 to !llvm.ptr
    %87 = llvm.icmp "eq" %85, %86 : !llvm.ptr
    cf.cond_br %87, ^bb33, ^bb32
  ^bb32:  // 2 preds: ^bb30, ^bb31
    %c71_i64 = arith.constant 71 : i64
    return %c71_i64 : i64
  ^bb33:  // pred: ^bb31
    %c712_i64_34 = arith.constant 712 : i64
    %88 = llvm.getelementptr %arg1[%c712_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %89 = llvm.load %88 : !llvm.ptr -> i32
    %c716_i64_35 = arith.constant 716 : i64
    %90 = llvm.getelementptr %arg1[%c716_i64_35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %91 = llvm.load %90 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %92 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %93 = llvm.load %92 : !llvm.ptr -> i8
    %c0_i32_36 = arith.constant 0 : i32
    %94 = arith.cmpi eq, %89, %c0_i32_36 : i32
    %c0_i32_37 = arith.constant 0 : i32
    %95 = arith.cmpi eq, %91, %c0_i32_37 : i32
    %96 = arith.andi %94, %95 : i1
    %c0_i8_38 = arith.constant 0 : i8
    %97 = arith.cmpi ne, %93, %c0_i8_38 : i8
    %98 = arith.andi %96, %97 : i1
    cf.cond_br %98, ^bb34, ^bb11
  ^bb34:  // pred: ^bb33
    %c704_i64 = arith.constant 704 : i64
    %99 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %100 = llvm.load %99 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %101 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %102 = llvm.load %101 : !llvm.ptr -> i32
    %103 = arith.extui %100 : i32 to i64
    %104 = arith.extui %89 : i32 to i64
    %105 = arith.addi %103, %104 : i64
    %106 = arith.extui %102 : i32 to i64
    %107 = arith.cmpi uge, %105, %106 : i64
    cf.cond_br %107, ^bb35, ^bb36
  ^bb35:  // pred: ^bb34
    %c69_i64 = arith.constant 69 : i64
    return %c69_i64 : i64
  ^bb36:  // pred: ^bb34
    %c16_i64_39 = arith.constant 16 : i64
    %108 = llvm.getelementptr %27[%c16_i64_39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %109 = llvm.load %108 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %110 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %109, %110 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_40 = arith.constant 641 : i64
    %111 = llvm.getelementptr %arg1[%c641_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %111 : i8, !llvm.ptr
    %c1_i32_41 = arith.constant 1 : i32
    %c716_i64_42 = arith.constant 716 : i64
    %112 = llvm.getelementptr %arg1[%c716_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_41, %112 : i32, !llvm.ptr
    %c1_i32_43 = arith.constant 1 : i32
    %113 = arith.addi %89, %c1_i32_43 : i32
    %c712_i64_44 = arith.constant 712 : i64
    %114 = llvm.getelementptr %arg1[%c712_i64_44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %113, %114 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %115 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %116 = llvm.load %115 : !llvm.ptr -> i32
    %c1_i32_45 = arith.constant 1 : i32
    %117 = arith.addi %116, %c1_i32_45 : i32
    %c720_i64_46 = arith.constant 720 : i64
    %118 = llvm.getelementptr %arg1[%c720_i64_46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %117, %118 : i32, !llvm.ptr
    cf.br ^bb8
  ^bb37:  // 2 preds: ^bb10, ^bb38
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb38:  // pred: ^bb10
    %c0_i64_47 = arith.constant 0 : i64
    %119 = llvm.getelementptr %31[%c0_i64_47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %120 = llvm.load %119 : !llvm.ptr -> i8
    %c2_i8_48 = arith.constant 2 : i8
    %121 = arith.cmpi ule, %120, %c2_i8_48 : i8
    cf.cond_br %121, ^bb37, ^bb39
  ^bb39:  // pred: ^bb38
    %c5_i8_49 = arith.constant 5 : i8
    %122 = arith.cmpi eq, %120, %c5_i8_49 : i8
    cf.cond_br %122, ^bb40, ^bb3
  ^bb40:  // pred: ^bb39
    %c8_i64_50 = arith.constant 8 : i64
    %123 = llvm.getelementptr %31[%c8_i64_50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %124 = llvm.load %123 : !llvm.ptr -> i8
    %c0_i8_51 = arith.constant 0 : i8
    %125 = arith.cmpi ne, %124, %c0_i8_51 : i8
    cf.cond_br %125, ^bb4, ^bb9
  }
}

