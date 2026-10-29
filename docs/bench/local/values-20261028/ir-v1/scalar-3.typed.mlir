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
  ^bb3:  // 2 preds: ^bb0, ^bb28
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
  ^bb9:  // 3 preds: ^bb0, ^bb11, ^bb25
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
  ^bb10:  // 2 preds: ^bb0, ^bb29
    %c32_i64 = arith.constant 32 : i64
    %42 = llvm.getelementptr %arg1[%c32_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> !llvm.ptr
    %44 = llvm.mlir.zero : !llvm.ptr
    %45 = llvm.icmp "eq" %43, %44 : !llvm.ptr
    cf.cond_br %45, ^bb23, ^bb24
  ^bb11:  // 2 preds: ^bb0, ^bb29
    %c18_i32 = arith.constant 18 : i32
    %c728_i64 = arith.constant 728 : i64
    %46 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c18_i32, %46 : i32, !llvm.ptr
    cf.br ^bb9
  ^bb12:  // 2 preds: ^bb0, ^bb37
    %c24_i64 = arith.constant 24 : i64
    %47 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %48 = llvm.load %47 : !llvm.ptr -> !llvm.ptr
    %49 = llvm.mlir.zero : !llvm.ptr
    %50 = llvm.icmp "eq" %48, %49 : !llvm.ptr
    cf.cond_br %50, ^bb26, ^bb27
  ^bb13:  // 2 preds: ^bb0, ^bb45
    %c8_i64 = arith.constant 8 : i64
    %51 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %52 = llvm.load %51 : !llvm.ptr -> !llvm.ptr
    %53 = llvm.mlir.zero : !llvm.ptr
    %54 = llvm.icmp "eq" %52, %53 : !llvm.ptr
    cf.cond_br %54, ^bb30, ^bb31
  ^bb14:  // 2 preds: ^bb0, ^bb0
    %c0_i64_20 = arith.constant 0 : i64
    %55 = llvm.getelementptr %arg1[%c0_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %56 = llvm.load %55 : !llvm.ptr -> !llvm.ptr
    %57 = llvm.mlir.zero : !llvm.ptr
    %58 = llvm.icmp "eq" %56, %57 : !llvm.ptr
    cf.cond_br %58, ^bb38, ^bb39
  ^bb15:  // 9 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb7, ^bb8, ^bb9, ^bb34, ^bb42
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb16:  // pred: ^bb19
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb17:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %59 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %59 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_21 = arith.constant 716 : i64
    %60 = llvm.getelementptr %arg1[%c716_i64_21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %60 : i32, !llvm.ptr
    %c1_i32_22 = arith.constant 1 : i32
    %61 = arith.subi %1, %c1_i32_22 : i32
    %c712_i64_23 = arith.constant 712 : i64
    %62 = llvm.getelementptr %arg1[%c712_i64_23] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %61, %62 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb18:  // pred: ^bb5
    %c0_i8_24 = arith.constant 0 : i8
    %c641_i64_25 = arith.constant 641 : i64
    %63 = llvm.getelementptr %arg1[%c641_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_24, %63 : i8, !llvm.ptr
    %c0_i32_26 = arith.constant 0 : i32
    %c716_i64_27 = arith.constant 716 : i64
    %64 = llvm.getelementptr %arg1[%c716_i64_27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_26, %64 : i32, !llvm.ptr
    %c1_i32_28 = arith.constant 1 : i32
    %65 = arith.subi %8, %c1_i32_28 : i32
    %c712_i64_29 = arith.constant 712 : i64
    %66 = llvm.getelementptr %arg1[%c712_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %65, %66 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb19:  // pred: ^bb6
    %c0_i8_30 = arith.constant 0 : i8
    %c641_i64_31 = arith.constant 641 : i64
    %67 = llvm.getelementptr %arg1[%c641_i64_31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_30, %67 : i8, !llvm.ptr
    %c0_i32_32 = arith.constant 0 : i32
    %c716_i64_33 = arith.constant 716 : i64
    %68 = llvm.getelementptr %arg1[%c716_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_32, %68 : i32, !llvm.ptr
    %c1_i32_34 = arith.constant 1 : i32
    %69 = arith.subi %15, %c1_i32_34 : i32
    %c712_i64_35 = arith.constant 712 : i64
    %70 = llvm.getelementptr %arg1[%c712_i64_35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %69, %70 : i32, !llvm.ptr
    cf.br ^bb16
  ^bb20:  // pred: ^bb7
    %c0_i8_36 = arith.constant 0 : i8
    %c642_i64 = arith.constant 642 : i64
    %71 = llvm.getelementptr %arg1[%c642_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_36, %71 : i8, !llvm.ptr
    %c1_i32_37 = arith.constant 1 : i32
    %c716_i64_38 = arith.constant 716 : i64
    %72 = llvm.getelementptr %arg1[%c716_i64_38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_37, %72 : i32, !llvm.ptr
    %c1_i32_39 = arith.constant 1 : i32
    %73 = arith.subi %22, %c1_i32_39 : i32
    %c712_i64_40 = arith.constant 712 : i64
    %74 = llvm.getelementptr %arg1[%c712_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %73, %74 : i32, !llvm.ptr
    cf.br ^bb4
  ^bb21:  // pred: ^bb8
    %c0_i8_41 = arith.constant 0 : i8
    %c642_i64_42 = arith.constant 642 : i64
    %75 = llvm.getelementptr %arg1[%c642_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_41, %75 : i8, !llvm.ptr
    %c1_i32_43 = arith.constant 1 : i32
    %c716_i64_44 = arith.constant 716 : i64
    %76 = llvm.getelementptr %arg1[%c716_i64_44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_43, %76 : i32, !llvm.ptr
    %c1_i32_45 = arith.constant 1 : i32
    %77 = arith.subi %29, %c1_i32_45 : i32
    %c712_i64_46 = arith.constant 712 : i64
    %78 = llvm.getelementptr %arg1[%c712_i64_46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %77, %78 : i32, !llvm.ptr
    cf.br ^bb5
  ^bb22:  // pred: ^bb9
    %c0_i8_47 = arith.constant 0 : i8
    %c642_i64_48 = arith.constant 642 : i64
    %79 = llvm.getelementptr %arg1[%c642_i64_48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_47, %79 : i8, !llvm.ptr
    %c1_i32_49 = arith.constant 1 : i32
    %c716_i64_50 = arith.constant 716 : i64
    %80 = llvm.getelementptr %arg1[%c716_i64_50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_49, %80 : i32, !llvm.ptr
    %c1_i32_51 = arith.constant 1 : i32
    %81 = arith.subi %36, %c1_i32_51 : i32
    %c712_i64_52 = arith.constant 712 : i64
    %82 = llvm.getelementptr %arg1[%c712_i64_52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %81, %82 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb23:  // 2 preds: ^bb10, ^bb24
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb24:  // pred: ^bb10
    %c0_i64_53 = arith.constant 0 : i64
    %83 = llvm.getelementptr %43[%c0_i64_53] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %84 = llvm.load %83 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %85 = arith.cmpi ule, %84, %c2_i8 : i8
    cf.cond_br %85, ^bb23, ^bb25
  ^bb25:  // pred: ^bb24
    %c4_i32 = arith.constant 4 : i32
    %c728_i64_54 = arith.constant 728 : i64
    %86 = llvm.getelementptr %arg1[%c728_i64_54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c4_i32, %86 : i32, !llvm.ptr
    cf.br ^bb9
  ^bb26:  // 2 preds: ^bb12, ^bb27
    %c90_i64 = arith.constant 90 : i64
    return %c90_i64 : i64
  ^bb27:  // pred: ^bb12
    %c0_i64_55 = arith.constant 0 : i64
    %87 = llvm.getelementptr %48[%c0_i64_55] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %88 = llvm.load %87 : !llvm.ptr -> i8
    %c2_i8_56 = arith.constant 2 : i8
    %89 = arith.cmpi ule, %88, %c2_i8_56 : i8
    cf.cond_br %89, ^bb26, ^bb28
  ^bb28:  // pred: ^bb27
    %c5_i8 = arith.constant 5 : i8
    %90 = arith.cmpi eq, %88, %c5_i8 : i8
    cf.cond_br %90, ^bb29, ^bb3
  ^bb29:  // pred: ^bb28
    %c8_i64_57 = arith.constant 8 : i64
    %91 = llvm.getelementptr %48[%c8_i64_57] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %92 = llvm.load %91 : !llvm.ptr -> i8
    %c0_i8_58 = arith.constant 0 : i8
    %93 = arith.cmpi ne, %92, %c0_i8_58 : i8
    cf.cond_br %93, ^bb10, ^bb11
  ^bb30:  // pred: ^bb13
    %c98_i64 = arith.constant 98 : i64
    return %c98_i64 : i64
  ^bb31:  // pred: ^bb13
    %c0_i64_59 = arith.constant 0 : i64
    %94 = llvm.getelementptr %52[%c0_i64_59] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %95 = llvm.load %94 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %96 = arith.cmpi eq, %95, %c11_i8 : i8
    cf.cond_br %96, ^bb32, ^bb33
  ^bb32:  // pred: ^bb31
    %c8_i64_60 = arith.constant 8 : i64
    %97 = llvm.getelementptr %52[%c8_i64_60] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %98 = llvm.load %97 : !llvm.ptr -> !llvm.ptr
    %c5685503168_i64 = arith.constant 5685503168 : i64
    %99 = llvm.inttoptr %c5685503168_i64 : i64 to !llvm.ptr
    %100 = llvm.icmp "eq" %98, %99 : !llvm.ptr
    cf.cond_br %100, ^bb34, ^bb33
  ^bb33:  // 2 preds: ^bb31, ^bb32
    %c103_i64 = arith.constant 103 : i64
    return %c103_i64 : i64
  ^bb34:  // pred: ^bb32
    %c712_i64_61 = arith.constant 712 : i64
    %101 = llvm.getelementptr %arg1[%c712_i64_61] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %102 = llvm.load %101 : !llvm.ptr -> i32
    %c716_i64_62 = arith.constant 716 : i64
    %103 = llvm.getelementptr %arg1[%c716_i64_62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %104 = llvm.load %103 : !llvm.ptr -> i32
    %c641_i64_63 = arith.constant 641 : i64
    %105 = llvm.getelementptr %arg1[%c641_i64_63] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %106 = llvm.load %105 : !llvm.ptr -> i8
    %c1_i32_64 = arith.constant 1 : i32
    %107 = arith.cmpi eq, %102, %c1_i32_64 : i32
    %c1_i32_65 = arith.constant 1 : i32
    %108 = arith.cmpi eq, %104, %c1_i32_65 : i32
    %109 = arith.andi %107, %108 : i1
    %c0_i8_66 = arith.constant 0 : i8
    %110 = arith.cmpi ne, %106, %c0_i8_66 : i8
    %111 = arith.andi %109, %110 : i1
    cf.cond_br %111, ^bb35, ^bb15
  ^bb35:  // pred: ^bb34
    %c704_i64 = arith.constant 704 : i64
    %112 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %113 = llvm.load %112 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %114 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %115 = llvm.load %114 : !llvm.ptr -> i32
    %116 = arith.extui %113 : i32 to i64
    %117 = arith.extui %102 : i32 to i64
    %118 = arith.addi %116, %117 : i64
    %119 = arith.extui %115 : i32 to i64
    %120 = arith.cmpi uge, %118, %119 : i64
    cf.cond_br %120, ^bb36, ^bb37
  ^bb36:  // pred: ^bb35
    %c101_i64 = arith.constant 101 : i64
    return %c101_i64 : i64
  ^bb37:  // pred: ^bb35
    %c16_i64 = arith.constant 16 : i64
    %121 = llvm.getelementptr %52[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %122 = llvm.load %121 : !llvm.ptr -> !llvm.ptr
    %c144_i64 = arith.constant 144 : i64
    %123 = llvm.getelementptr %arg1[%c144_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %122, %123 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c642_i64_67 = arith.constant 642 : i64
    %124 = llvm.getelementptr %arg1[%c642_i64_67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %124 : i8, !llvm.ptr
    %c2_i32_68 = arith.constant 2 : i32
    %c716_i64_69 = arith.constant 716 : i64
    %125 = llvm.getelementptr %arg1[%c716_i64_69] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c2_i32_68, %125 : i32, !llvm.ptr
    %c1_i32_70 = arith.constant 1 : i32
    %126 = arith.addi %102, %c1_i32_70 : i32
    %c712_i64_71 = arith.constant 712 : i64
    %127 = llvm.getelementptr %arg1[%c712_i64_71] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %126, %127 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %128 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %129 = llvm.load %128 : !llvm.ptr -> i32
    %c1_i32_72 = arith.constant 1 : i32
    %130 = arith.addi %129, %c1_i32_72 : i32
    %c720_i64_73 = arith.constant 720 : i64
    %131 = llvm.getelementptr %arg1[%c720_i64_73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %130, %131 : i32, !llvm.ptr
    %132 = llvm.mlir.zero : !llvm.ptr
    %c24_i64_74 = arith.constant 24 : i64
    %133 = llvm.getelementptr %arg1[%c24_i64_74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %132, %133 : !llvm.ptr, !llvm.ptr
    %134 = llvm.mlir.zero : !llvm.ptr
    %c32_i64_75 = arith.constant 32 : i64
    %135 = llvm.getelementptr %arg1[%c32_i64_75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %134, %135 : !llvm.ptr, !llvm.ptr
    cf.br ^bb12
  ^bb38:  // pred: ^bb14
    %c106_i64 = arith.constant 106 : i64
    return %c106_i64 : i64
  ^bb39:  // pred: ^bb14
    %c0_i64_76 = arith.constant 0 : i64
    %136 = llvm.getelementptr %56[%c0_i64_76] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %137 = llvm.load %136 : !llvm.ptr -> i8
    %c11_i8_77 = arith.constant 11 : i8
    %138 = arith.cmpi eq, %137, %c11_i8_77 : i8
    cf.cond_br %138, ^bb40, ^bb41
  ^bb40:  // pred: ^bb39
    %c8_i64_78 = arith.constant 8 : i64
    %139 = llvm.getelementptr %56[%c8_i64_78] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %140 = llvm.load %139 : !llvm.ptr -> !llvm.ptr
    %c5685531712_i64 = arith.constant 5685531712 : i64
    %141 = llvm.inttoptr %c5685531712_i64 : i64 to !llvm.ptr
    %142 = llvm.icmp "eq" %140, %141 : !llvm.ptr
    cf.cond_br %142, ^bb42, ^bb41
  ^bb41:  // 2 preds: ^bb39, ^bb40
    %c111_i64 = arith.constant 111 : i64
    return %c111_i64 : i64
  ^bb42:  // pred: ^bb40
    %c712_i64_79 = arith.constant 712 : i64
    %143 = llvm.getelementptr %arg1[%c712_i64_79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %144 = llvm.load %143 : !llvm.ptr -> i32
    %c716_i64_80 = arith.constant 716 : i64
    %145 = llvm.getelementptr %arg1[%c716_i64_80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %146 = llvm.load %145 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %147 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %148 = llvm.load %147 : !llvm.ptr -> i8
    %c0_i32_81 = arith.constant 0 : i32
    %149 = arith.cmpi eq, %144, %c0_i32_81 : i32
    %c0_i32_82 = arith.constant 0 : i32
    %150 = arith.cmpi eq, %146, %c0_i32_82 : i32
    %151 = arith.andi %149, %150 : i1
    %c0_i8_83 = arith.constant 0 : i8
    %152 = arith.cmpi ne, %148, %c0_i8_83 : i8
    %153 = arith.andi %151, %152 : i1
    cf.cond_br %153, ^bb43, ^bb15
  ^bb43:  // pred: ^bb42
    %c704_i64_84 = arith.constant 704 : i64
    %154 = llvm.getelementptr %arg1[%c704_i64_84] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %155 = llvm.load %154 : !llvm.ptr -> i32
    %c708_i64_85 = arith.constant 708 : i64
    %156 = llvm.getelementptr %arg1[%c708_i64_85] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %157 = llvm.load %156 : !llvm.ptr -> i32
    %158 = arith.extui %155 : i32 to i64
    %159 = arith.extui %144 : i32 to i64
    %160 = arith.addi %158, %159 : i64
    %161 = arith.extui %157 : i32 to i64
    %162 = arith.cmpi uge, %160, %161 : i64
    cf.cond_br %162, ^bb44, ^bb45
  ^bb44:  // pred: ^bb43
    %c109_i64 = arith.constant 109 : i64
    return %c109_i64 : i64
  ^bb45:  // pred: ^bb43
    %c16_i64_86 = arith.constant 16 : i64
    %163 = llvm.getelementptr %56[%c16_i64_86] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %164 = llvm.load %163 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %165 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %164, %165 : !llvm.ptr, !llvm.ptr
    %c1_i8_87 = arith.constant 1 : i8
    %c641_i64_88 = arith.constant 641 : i64
    %166 = llvm.getelementptr %arg1[%c641_i64_88] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8_87, %166 : i8, !llvm.ptr
    %c1_i32_89 = arith.constant 1 : i32
    %c716_i64_90 = arith.constant 716 : i64
    %167 = llvm.getelementptr %arg1[%c716_i64_90] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_89, %167 : i32, !llvm.ptr
    %c1_i32_91 = arith.constant 1 : i32
    %168 = arith.addi %144, %c1_i32_91 : i32
    %c712_i64_92 = arith.constant 712 : i64
    %169 = llvm.getelementptr %arg1[%c712_i64_92] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %168, %169 : i32, !llvm.ptr
    %c720_i64_93 = arith.constant 720 : i64
    %170 = llvm.getelementptr %arg1[%c720_i64_93] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %171 = llvm.load %170 : !llvm.ptr -> i32
    %c1_i32_94 = arith.constant 1 : i32
    %172 = arith.addi %171, %c1_i32_94 : i32
    %c720_i64_95 = arith.constant 720 : i64
    %173 = llvm.getelementptr %arg1[%c720_i64_95] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %172, %173 : i32, !llvm.ptr
    %c724_i64 = arith.constant 724 : i64
    %174 = llvm.getelementptr %arg1[%c724_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %175 = llvm.load %174 : !llvm.ptr -> i32
    %c1_i32_96 = arith.constant 1 : i32
    %176 = arith.addi %175, %c1_i32_96 : i32
    %c724_i64_97 = arith.constant 724 : i64
    %177 = llvm.getelementptr %arg1[%c724_i64_97] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %176, %177 : i32, !llvm.ptr
    cf.br ^bb13
  }
}

