module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb15,
      0: ^bb14,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8,
      9: ^bb9,
      10: ^bb10,
      11: ^bb11,
      12: ^bb12,
      13: ^bb13,
      14: ^bb14
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb18
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb17
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 2 preds: ^bb0, ^bb31
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb20
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
    cf.cond_br %6, ^bb17, ^bb15
  ^bb5:  // 2 preds: ^bb0, ^bb21
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
    cf.cond_br %13, ^bb18, ^bb15
  ^bb6:  // 2 preds: ^bb0, ^bb22
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
    cf.cond_br %20, ^bb19, ^bb15
  ^bb7:  // pred: ^bb0
    %c712_i64_9 = arith.constant 712 : i64
    %21 = llvm.getelementptr %arg1[%c712_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %22 = llvm.load %21 : !llvm.ptr -> i32
    %c716_i64_10 = arith.constant 716 : i64
    %23 = llvm.getelementptr %arg1[%c716_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %24 = llvm.load %23 : !llvm.ptr -> i32
    %c2_i32 = arith.constant 2 : i32
    %25 = arith.cmpi eq, %22, %c2_i32 : i32
    %c2_i32_11 = arith.constant 2 : i32
    %26 = arith.cmpi eq, %24, %c2_i32_11 : i32
    %27 = arith.andi %25, %26 : i1
    cf.cond_br %27, ^bb20, ^bb15
  ^bb8:  // pred: ^bb0
    %c712_i64_12 = arith.constant 712 : i64
    %28 = llvm.getelementptr %arg1[%c712_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %29 = llvm.load %28 : !llvm.ptr -> i32
    %c716_i64_13 = arith.constant 716 : i64
    %30 = llvm.getelementptr %arg1[%c716_i64_13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %31 = llvm.load %30 : !llvm.ptr -> i32
    %c2_i32_14 = arith.constant 2 : i32
    %32 = arith.cmpi eq, %29, %c2_i32_14 : i32
    %c2_i32_15 = arith.constant 2 : i32
    %33 = arith.cmpi eq, %31, %c2_i32_15 : i32
    %34 = arith.andi %32, %33 : i1
    cf.cond_br %34, ^bb21, ^bb15
  ^bb9:  // 3 preds: ^bb0, ^bb25, ^bb28
    %c712_i64_16 = arith.constant 712 : i64
    %35 = llvm.getelementptr %arg1[%c712_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %36 = llvm.load %35 : !llvm.ptr -> i32
    %c716_i64_17 = arith.constant 716 : i64
    %37 = llvm.getelementptr %arg1[%c716_i64_17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %38 = llvm.load %37 : !llvm.ptr -> i32
    %c2_i32_18 = arith.constant 2 : i32
    %39 = arith.cmpi eq, %36, %c2_i32_18 : i32
    %c2_i32_19 = arith.constant 2 : i32
    %40 = arith.cmpi eq, %38, %c2_i32_19 : i32
    %41 = arith.andi %39, %40 : i1
    cf.cond_br %41, ^bb22, ^bb15
  ^bb10:  // 2 preds: ^bb0, ^bb32
    %c32_i64 = arith.constant 32 : i64
    %42 = llvm.getelementptr %arg1[%c32_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> !llvm.ptr
    %44 = llvm.mlir.zero : !llvm.ptr
    %45 = llvm.icmp "eq" %43, %44 : !llvm.ptr
    cf.cond_br %45, ^bb23, ^bb24
  ^bb11:  // 2 preds: ^bb0, ^bb32
    %c40_i64 = arith.constant 40 : i64
    %46 = llvm.getelementptr %arg1[%c40_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %47 = llvm.load %46 : !llvm.ptr -> !llvm.ptr
    %48 = llvm.mlir.zero : !llvm.ptr
    %49 = llvm.icmp "eq" %47, %48 : !llvm.ptr
    cf.cond_br %49, ^bb26, ^bb27
  ^bb12:  // 2 preds: ^bb0, ^bb40
    %c24_i64 = arith.constant 24 : i64
    %50 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %51 = llvm.load %50 : !llvm.ptr -> !llvm.ptr
    %52 = llvm.mlir.zero : !llvm.ptr
    %53 = llvm.icmp "eq" %51, %52 : !llvm.ptr
    cf.cond_br %53, ^bb29, ^bb30
  ^bb13:  // 2 preds: ^bb0, ^bb48
    %c8_i64 = arith.constant 8 : i64
    %54 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %55 = llvm.load %54 : !llvm.ptr -> !llvm.ptr
    %56 = llvm.mlir.zero : !llvm.ptr
    %57 = llvm.icmp "eq" %55, %56 : !llvm.ptr
    cf.cond_br %57, ^bb33, ^bb34
  ^bb14:  // 2 preds: ^bb0, ^bb0
    %c0_i64_20 = arith.constant 0 : i64
    %58 = llvm.getelementptr %arg1[%c0_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %59 = llvm.load %58 : !llvm.ptr -> !llvm.ptr
    %60 = llvm.mlir.zero : !llvm.ptr
    %61 = llvm.icmp "eq" %59, %60 : !llvm.ptr
    cf.cond_br %61, ^bb41, ^bb42
  ^bb15:  // 9 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb7, ^bb8, ^bb9, ^bb37, ^bb45
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb16:  // pred: ^bb19
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb17:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %62 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %62 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_21 = arith.constant 716 : i64
    %63 = llvm.getelementptr %arg1[%c716_i64_21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %63 : i32, !llvm.ptr
    %c1_i32_22 = arith.constant 1 : i32
    %64 = arith.subi %1, %c1_i32_22 : i32
    %c712_i64_23 = arith.constant 712 : i64
    %65 = llvm.getelementptr %arg1[%c712_i64_23] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %64, %65 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb18:  // pred: ^bb5
    %c0_i8_24 = arith.constant 0 : i8
    %c641_i64_25 = arith.constant 641 : i64
    %66 = llvm.getelementptr %arg1[%c641_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_24, %66 : i8, !llvm.ptr
    %c0_i32_26 = arith.constant 0 : i32
    %c716_i64_27 = arith.constant 716 : i64
    %67 = llvm.getelementptr %arg1[%c716_i64_27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_26, %67 : i32, !llvm.ptr
    %c1_i32_28 = arith.constant 1 : i32
    %68 = arith.subi %8, %c1_i32_28 : i32
    %c712_i64_29 = arith.constant 712 : i64
    %69 = llvm.getelementptr %arg1[%c712_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %68, %69 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb19:  // pred: ^bb6
    %c0_i8_30 = arith.constant 0 : i8
    %c641_i64_31 = arith.constant 641 : i64
    %70 = llvm.getelementptr %arg1[%c641_i64_31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_30, %70 : i8, !llvm.ptr
    %c0_i32_32 = arith.constant 0 : i32
    %c716_i64_33 = arith.constant 716 : i64
    %71 = llvm.getelementptr %arg1[%c716_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_32, %71 : i32, !llvm.ptr
    %c1_i32_34 = arith.constant 1 : i32
    %72 = arith.subi %15, %c1_i32_34 : i32
    %c712_i64_35 = arith.constant 712 : i64
    %73 = llvm.getelementptr %arg1[%c712_i64_35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %72, %73 : i32, !llvm.ptr
    cf.br ^bb16
  ^bb20:  // pred: ^bb7
    %c0_i8_36 = arith.constant 0 : i8
    %c642_i64 = arith.constant 642 : i64
    %74 = llvm.getelementptr %arg1[%c642_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_36, %74 : i8, !llvm.ptr
    %c1_i32_37 = arith.constant 1 : i32
    %c716_i64_38 = arith.constant 716 : i64
    %75 = llvm.getelementptr %arg1[%c716_i64_38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_37, %75 : i32, !llvm.ptr
    %c1_i32_39 = arith.constant 1 : i32
    %76 = arith.subi %22, %c1_i32_39 : i32
    %c712_i64_40 = arith.constant 712 : i64
    %77 = llvm.getelementptr %arg1[%c712_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %76, %77 : i32, !llvm.ptr
    cf.br ^bb4
  ^bb21:  // pred: ^bb8
    %c0_i8_41 = arith.constant 0 : i8
    %c642_i64_42 = arith.constant 642 : i64
    %78 = llvm.getelementptr %arg1[%c642_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_41, %78 : i8, !llvm.ptr
    %c1_i32_43 = arith.constant 1 : i32
    %c716_i64_44 = arith.constant 716 : i64
    %79 = llvm.getelementptr %arg1[%c716_i64_44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_43, %79 : i32, !llvm.ptr
    %c1_i32_45 = arith.constant 1 : i32
    %80 = arith.subi %29, %c1_i32_45 : i32
    %c712_i64_46 = arith.constant 712 : i64
    %81 = llvm.getelementptr %arg1[%c712_i64_46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %80, %81 : i32, !llvm.ptr
    cf.br ^bb5
  ^bb22:  // pred: ^bb9
    %c0_i8_47 = arith.constant 0 : i8
    %c642_i64_48 = arith.constant 642 : i64
    %82 = llvm.getelementptr %arg1[%c642_i64_48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_47, %82 : i8, !llvm.ptr
    %c1_i32_49 = arith.constant 1 : i32
    %c716_i64_50 = arith.constant 716 : i64
    %83 = llvm.getelementptr %arg1[%c716_i64_50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_49, %83 : i32, !llvm.ptr
    %c1_i32_51 = arith.constant 1 : i32
    %84 = arith.subi %36, %c1_i32_51 : i32
    %c712_i64_52 = arith.constant 712 : i64
    %85 = llvm.getelementptr %arg1[%c712_i64_52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %84, %85 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb23:  // 2 preds: ^bb10, ^bb24
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb24:  // pred: ^bb10
    %c0_i64_53 = arith.constant 0 : i64
    %86 = llvm.getelementptr %43[%c0_i64_53] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %87 = llvm.load %86 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %88 = arith.cmpi ule, %87, %c2_i8 : i8
    cf.cond_br %88, ^bb23, ^bb25
  ^bb25:  // pred: ^bb24
    %c4_i32 = arith.constant 4 : i32
    %c728_i64 = arith.constant 728 : i64
    %89 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c4_i32, %89 : i32, !llvm.ptr
    cf.br ^bb9
  ^bb26:  // 2 preds: ^bb11, ^bb27
    %c82_i64 = arith.constant 82 : i64
    return %c82_i64 : i64
  ^bb27:  // pred: ^bb11
    %c0_i64_54 = arith.constant 0 : i64
    %90 = llvm.getelementptr %47[%c0_i64_54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %91 = llvm.load %90 : !llvm.ptr -> i8
    %c2_i8_55 = arith.constant 2 : i8
    %92 = arith.cmpi ule, %91, %c2_i8_55 : i8
    cf.cond_br %92, ^bb26, ^bb28
  ^bb28:  // pred: ^bb27
    %c5_i32 = arith.constant 5 : i32
    %c728_i64_56 = arith.constant 728 : i64
    %93 = llvm.getelementptr %arg1[%c728_i64_56] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c5_i32, %93 : i32, !llvm.ptr
    cf.br ^bb9
  ^bb29:  // 2 preds: ^bb12, ^bb30
    %c90_i64 = arith.constant 90 : i64
    return %c90_i64 : i64
  ^bb30:  // pred: ^bb12
    %c0_i64_57 = arith.constant 0 : i64
    %94 = llvm.getelementptr %51[%c0_i64_57] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %95 = llvm.load %94 : !llvm.ptr -> i8
    %c2_i8_58 = arith.constant 2 : i8
    %96 = arith.cmpi ule, %95, %c2_i8_58 : i8
    cf.cond_br %96, ^bb29, ^bb31
  ^bb31:  // pred: ^bb30
    %c5_i8 = arith.constant 5 : i8
    %97 = arith.cmpi eq, %95, %c5_i8 : i8
    cf.cond_br %97, ^bb32, ^bb3
  ^bb32:  // pred: ^bb31
    %c8_i64_59 = arith.constant 8 : i64
    %98 = llvm.getelementptr %51[%c8_i64_59] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %99 = llvm.load %98 : !llvm.ptr -> i8
    %c0_i8_60 = arith.constant 0 : i8
    %100 = arith.cmpi ne, %99, %c0_i8_60 : i8
    cf.cond_br %100, ^bb10, ^bb11
  ^bb33:  // pred: ^bb13
    %c98_i64 = arith.constant 98 : i64
    return %c98_i64 : i64
  ^bb34:  // pred: ^bb13
    %c0_i64_61 = arith.constant 0 : i64
    %101 = llvm.getelementptr %55[%c0_i64_61] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %102 = llvm.load %101 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %103 = arith.cmpi eq, %102, %c11_i8 : i8
    cf.cond_br %103, ^bb35, ^bb36
  ^bb35:  // pred: ^bb34
    %c8_i64_62 = arith.constant 8 : i64
    %104 = llvm.getelementptr %55[%c8_i64_62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %105 = llvm.load %104 : !llvm.ptr -> !llvm.ptr
    %c5417056880_i64 = arith.constant 5417056880 : i64
    %106 = llvm.inttoptr %c5417056880_i64 : i64 to !llvm.ptr
    %107 = llvm.icmp "eq" %105, %106 : !llvm.ptr
    cf.cond_br %107, ^bb37, ^bb36
  ^bb36:  // 2 preds: ^bb34, ^bb35
    %c103_i64 = arith.constant 103 : i64
    return %c103_i64 : i64
  ^bb37:  // pred: ^bb35
    %c712_i64_63 = arith.constant 712 : i64
    %108 = llvm.getelementptr %arg1[%c712_i64_63] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %109 = llvm.load %108 : !llvm.ptr -> i32
    %c716_i64_64 = arith.constant 716 : i64
    %110 = llvm.getelementptr %arg1[%c716_i64_64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %111 = llvm.load %110 : !llvm.ptr -> i32
    %c641_i64_65 = arith.constant 641 : i64
    %112 = llvm.getelementptr %arg1[%c641_i64_65] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %113 = llvm.load %112 : !llvm.ptr -> i8
    %c1_i32_66 = arith.constant 1 : i32
    %114 = arith.cmpi eq, %109, %c1_i32_66 : i32
    %c1_i32_67 = arith.constant 1 : i32
    %115 = arith.cmpi eq, %111, %c1_i32_67 : i32
    %116 = arith.andi %114, %115 : i1
    %c0_i8_68 = arith.constant 0 : i8
    %117 = arith.cmpi ne, %113, %c0_i8_68 : i8
    %118 = arith.andi %116, %117 : i1
    cf.cond_br %118, ^bb38, ^bb15
  ^bb38:  // pred: ^bb37
    %c704_i64 = arith.constant 704 : i64
    %119 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %120 = llvm.load %119 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %121 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %122 = llvm.load %121 : !llvm.ptr -> i32
    %123 = arith.extui %120 : i32 to i64
    %124 = arith.extui %109 : i32 to i64
    %125 = arith.addi %123, %124 : i64
    %126 = arith.extui %122 : i32 to i64
    %127 = arith.cmpi uge, %125, %126 : i64
    cf.cond_br %127, ^bb39, ^bb40
  ^bb39:  // pred: ^bb38
    %c101_i64 = arith.constant 101 : i64
    return %c101_i64 : i64
  ^bb40:  // pred: ^bb38
    %c16_i64 = arith.constant 16 : i64
    %128 = llvm.getelementptr %55[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %129 = llvm.load %128 : !llvm.ptr -> !llvm.ptr
    %c144_i64 = arith.constant 144 : i64
    %130 = llvm.getelementptr %arg1[%c144_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %129, %130 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c642_i64_69 = arith.constant 642 : i64
    %131 = llvm.getelementptr %arg1[%c642_i64_69] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %131 : i8, !llvm.ptr
    %c2_i32_70 = arith.constant 2 : i32
    %c716_i64_71 = arith.constant 716 : i64
    %132 = llvm.getelementptr %arg1[%c716_i64_71] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c2_i32_70, %132 : i32, !llvm.ptr
    %c1_i32_72 = arith.constant 1 : i32
    %133 = arith.addi %109, %c1_i32_72 : i32
    %c712_i64_73 = arith.constant 712 : i64
    %134 = llvm.getelementptr %arg1[%c712_i64_73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %133, %134 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %135 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %136 = llvm.load %135 : !llvm.ptr -> i32
    %c1_i32_74 = arith.constant 1 : i32
    %137 = arith.addi %136, %c1_i32_74 : i32
    %c720_i64_75 = arith.constant 720 : i64
    %138 = llvm.getelementptr %arg1[%c720_i64_75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %137, %138 : i32, !llvm.ptr
    %139 = llvm.mlir.zero : !llvm.ptr
    %c24_i64_76 = arith.constant 24 : i64
    %140 = llvm.getelementptr %arg1[%c24_i64_76] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %139, %140 : !llvm.ptr, !llvm.ptr
    %141 = llvm.mlir.zero : !llvm.ptr
    %c32_i64_77 = arith.constant 32 : i64
    %142 = llvm.getelementptr %arg1[%c32_i64_77] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %141, %142 : !llvm.ptr, !llvm.ptr
    %143 = llvm.mlir.zero : !llvm.ptr
    %c40_i64_78 = arith.constant 40 : i64
    %144 = llvm.getelementptr %arg1[%c40_i64_78] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %143, %144 : !llvm.ptr, !llvm.ptr
    cf.br ^bb12
  ^bb41:  // pred: ^bb14
    %c106_i64 = arith.constant 106 : i64
    return %c106_i64 : i64
  ^bb42:  // pred: ^bb14
    %c0_i64_79 = arith.constant 0 : i64
    %145 = llvm.getelementptr %59[%c0_i64_79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %146 = llvm.load %145 : !llvm.ptr -> i8
    %c11_i8_80 = arith.constant 11 : i8
    %147 = arith.cmpi eq, %146, %c11_i8_80 : i8
    cf.cond_br %147, ^bb43, ^bb44
  ^bb43:  // pred: ^bb42
    %c8_i64_81 = arith.constant 8 : i64
    %148 = llvm.getelementptr %59[%c8_i64_81] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %149 = llvm.load %148 : !llvm.ptr -> !llvm.ptr
    %c5417101712_i64 = arith.constant 5417101712 : i64
    %150 = llvm.inttoptr %c5417101712_i64 : i64 to !llvm.ptr
    %151 = llvm.icmp "eq" %149, %150 : !llvm.ptr
    cf.cond_br %151, ^bb45, ^bb44
  ^bb44:  // 2 preds: ^bb42, ^bb43
    %c111_i64 = arith.constant 111 : i64
    return %c111_i64 : i64
  ^bb45:  // pred: ^bb43
    %c712_i64_82 = arith.constant 712 : i64
    %152 = llvm.getelementptr %arg1[%c712_i64_82] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %153 = llvm.load %152 : !llvm.ptr -> i32
    %c716_i64_83 = arith.constant 716 : i64
    %154 = llvm.getelementptr %arg1[%c716_i64_83] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %155 = llvm.load %154 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %156 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %157 = llvm.load %156 : !llvm.ptr -> i8
    %c0_i32_84 = arith.constant 0 : i32
    %158 = arith.cmpi eq, %153, %c0_i32_84 : i32
    %c0_i32_85 = arith.constant 0 : i32
    %159 = arith.cmpi eq, %155, %c0_i32_85 : i32
    %160 = arith.andi %158, %159 : i1
    %c0_i8_86 = arith.constant 0 : i8
    %161 = arith.cmpi ne, %157, %c0_i8_86 : i8
    %162 = arith.andi %160, %161 : i1
    cf.cond_br %162, ^bb46, ^bb15
  ^bb46:  // pred: ^bb45
    %c704_i64_87 = arith.constant 704 : i64
    %163 = llvm.getelementptr %arg1[%c704_i64_87] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %164 = llvm.load %163 : !llvm.ptr -> i32
    %c708_i64_88 = arith.constant 708 : i64
    %165 = llvm.getelementptr %arg1[%c708_i64_88] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %166 = llvm.load %165 : !llvm.ptr -> i32
    %167 = arith.extui %164 : i32 to i64
    %168 = arith.extui %153 : i32 to i64
    %169 = arith.addi %167, %168 : i64
    %170 = arith.extui %166 : i32 to i64
    %171 = arith.cmpi uge, %169, %170 : i64
    cf.cond_br %171, ^bb47, ^bb48
  ^bb47:  // pred: ^bb46
    %c109_i64 = arith.constant 109 : i64
    return %c109_i64 : i64
  ^bb48:  // pred: ^bb46
    %c16_i64_89 = arith.constant 16 : i64
    %172 = llvm.getelementptr %59[%c16_i64_89] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %173 = llvm.load %172 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %174 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %173, %174 : !llvm.ptr, !llvm.ptr
    %c1_i8_90 = arith.constant 1 : i8
    %c641_i64_91 = arith.constant 641 : i64
    %175 = llvm.getelementptr %arg1[%c641_i64_91] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8_90, %175 : i8, !llvm.ptr
    %c1_i32_92 = arith.constant 1 : i32
    %c716_i64_93 = arith.constant 716 : i64
    %176 = llvm.getelementptr %arg1[%c716_i64_93] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_92, %176 : i32, !llvm.ptr
    %c1_i32_94 = arith.constant 1 : i32
    %177 = arith.addi %153, %c1_i32_94 : i32
    %c712_i64_95 = arith.constant 712 : i64
    %178 = llvm.getelementptr %arg1[%c712_i64_95] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %177, %178 : i32, !llvm.ptr
    %c720_i64_96 = arith.constant 720 : i64
    %179 = llvm.getelementptr %arg1[%c720_i64_96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %180 = llvm.load %179 : !llvm.ptr -> i32
    %c1_i32_97 = arith.constant 1 : i32
    %181 = arith.addi %180, %c1_i32_97 : i32
    %c720_i64_98 = arith.constant 720 : i64
    %182 = llvm.getelementptr %arg1[%c720_i64_98] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %181, %182 : i32, !llvm.ptr
    %c724_i64 = arith.constant 724 : i64
    %183 = llvm.getelementptr %arg1[%c724_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %184 = llvm.load %183 : !llvm.ptr -> i32
    %c1_i32_99 = arith.constant 1 : i32
    %185 = arith.addi %184, %c1_i32_99 : i32
    %c724_i64_100 = arith.constant 724 : i64
    %186 = llvm.getelementptr %arg1[%c724_i64_100] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %185, %186 : i32, !llvm.ptr
    cf.br ^bb13
  }
}

