module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb13,
      0: ^bb12,
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
      12: ^bb12
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb16
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb15
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // pred: ^bb0
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb18
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
    cf.cond_br %6, ^bb15, ^bb13
  ^bb5:  // 2 preds: ^bb0, ^bb19
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
    cf.cond_br %13, ^bb16, ^bb13
  ^bb6:  // 2 preds: ^bb0, ^bb20
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
    cf.cond_br %20, ^bb17, ^bb13
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
    cf.cond_br %27, ^bb18, ^bb13
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
    cf.cond_br %34, ^bb19, ^bb13
  ^bb9:  // 2 preds: ^bb0, ^bb22
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
    cf.cond_br %41, ^bb20, ^bb13
  ^bb10:  // 2 preds: ^bb0, ^bb30
    %true = arith.constant true
    %42 = llvm.mlir.zero : !llvm.ptr
    %c24_i64 = arith.constant 24 : i64
    %43 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %44 = llvm.load %43 : !llvm.ptr -> !llvm.ptr
    %45 = llvm.icmp "ne" %44, %42 : !llvm.ptr
    %46 = arith.andi %true, %45 : i1
    %c16_i64 = arith.constant 16 : i64
    %47 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %48 = llvm.load %47 : !llvm.ptr -> !llvm.ptr
    %49 = llvm.icmp "ne" %48, %42 : !llvm.ptr
    %50 = arith.andi %46, %49 : i1
    %c24_i64_20 = arith.constant 24 : i64
    %51 = llvm.getelementptr %arg1[%c24_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %52 = llvm.load %51 : !llvm.ptr -> !llvm.ptr
    %53 = llvm.icmp "ne" %52, %42 : !llvm.ptr
    %54 = arith.andi %50, %53 : i1
    cf.cond_br %54, ^bb22, ^bb21
  ^bb11:  // 2 preds: ^bb0, ^bb38
    %c8_i64 = arith.constant 8 : i64
    %55 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %56 = llvm.load %55 : !llvm.ptr -> !llvm.ptr
    %57 = llvm.mlir.zero : !llvm.ptr
    %58 = llvm.icmp "eq" %56, %57 : !llvm.ptr
    cf.cond_br %58, ^bb23, ^bb24
  ^bb12:  // 2 preds: ^bb0, ^bb0
    %c0_i64_21 = arith.constant 0 : i64
    %59 = llvm.getelementptr %arg1[%c0_i64_21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %60 = llvm.load %59 : !llvm.ptr -> !llvm.ptr
    %61 = llvm.mlir.zero : !llvm.ptr
    %62 = llvm.icmp "eq" %60, %61 : !llvm.ptr
    cf.cond_br %62, ^bb31, ^bb32
  ^bb13:  // 9 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb7, ^bb8, ^bb9, ^bb27, ^bb35
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb14:  // pred: ^bb17
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb15:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %63 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %63 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_22 = arith.constant 716 : i64
    %64 = llvm.getelementptr %arg1[%c716_i64_22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %64 : i32, !llvm.ptr
    %c1_i32_23 = arith.constant 1 : i32
    %65 = arith.subi %1, %c1_i32_23 : i32
    %c712_i64_24 = arith.constant 712 : i64
    %66 = llvm.getelementptr %arg1[%c712_i64_24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %65, %66 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb16:  // pred: ^bb5
    %c0_i8_25 = arith.constant 0 : i8
    %c641_i64_26 = arith.constant 641 : i64
    %67 = llvm.getelementptr %arg1[%c641_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_25, %67 : i8, !llvm.ptr
    %c0_i32_27 = arith.constant 0 : i32
    %c716_i64_28 = arith.constant 716 : i64
    %68 = llvm.getelementptr %arg1[%c716_i64_28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_27, %68 : i32, !llvm.ptr
    %c1_i32_29 = arith.constant 1 : i32
    %69 = arith.subi %8, %c1_i32_29 : i32
    %c712_i64_30 = arith.constant 712 : i64
    %70 = llvm.getelementptr %arg1[%c712_i64_30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %69, %70 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb17:  // pred: ^bb6
    %c0_i8_31 = arith.constant 0 : i8
    %c641_i64_32 = arith.constant 641 : i64
    %71 = llvm.getelementptr %arg1[%c641_i64_32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_31, %71 : i8, !llvm.ptr
    %c0_i32_33 = arith.constant 0 : i32
    %c716_i64_34 = arith.constant 716 : i64
    %72 = llvm.getelementptr %arg1[%c716_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_33, %72 : i32, !llvm.ptr
    %c1_i32_35 = arith.constant 1 : i32
    %73 = arith.subi %15, %c1_i32_35 : i32
    %c712_i64_36 = arith.constant 712 : i64
    %74 = llvm.getelementptr %arg1[%c712_i64_36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %73, %74 : i32, !llvm.ptr
    cf.br ^bb14
  ^bb18:  // pred: ^bb7
    %c0_i8_37 = arith.constant 0 : i8
    %c642_i64 = arith.constant 642 : i64
    %75 = llvm.getelementptr %arg1[%c642_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_37, %75 : i8, !llvm.ptr
    %c1_i32_38 = arith.constant 1 : i32
    %c716_i64_39 = arith.constant 716 : i64
    %76 = llvm.getelementptr %arg1[%c716_i64_39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_38, %76 : i32, !llvm.ptr
    %c1_i32_40 = arith.constant 1 : i32
    %77 = arith.subi %22, %c1_i32_40 : i32
    %c712_i64_41 = arith.constant 712 : i64
    %78 = llvm.getelementptr %arg1[%c712_i64_41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %77, %78 : i32, !llvm.ptr
    cf.br ^bb4
  ^bb19:  // pred: ^bb8
    %c0_i8_42 = arith.constant 0 : i8
    %c642_i64_43 = arith.constant 642 : i64
    %79 = llvm.getelementptr %arg1[%c642_i64_43] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_42, %79 : i8, !llvm.ptr
    %c1_i32_44 = arith.constant 1 : i32
    %c716_i64_45 = arith.constant 716 : i64
    %80 = llvm.getelementptr %arg1[%c716_i64_45] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_44, %80 : i32, !llvm.ptr
    %c1_i32_46 = arith.constant 1 : i32
    %81 = arith.subi %29, %c1_i32_46 : i32
    %c712_i64_47 = arith.constant 712 : i64
    %82 = llvm.getelementptr %arg1[%c712_i64_47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %81, %82 : i32, !llvm.ptr
    cf.br ^bb5
  ^bb20:  // pred: ^bb9
    %c0_i8_48 = arith.constant 0 : i8
    %c642_i64_49 = arith.constant 642 : i64
    %83 = llvm.getelementptr %arg1[%c642_i64_49] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_48, %83 : i8, !llvm.ptr
    %c1_i32_50 = arith.constant 1 : i32
    %c716_i64_51 = arith.constant 716 : i64
    %84 = llvm.getelementptr %arg1[%c716_i64_51] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_50, %84 : i32, !llvm.ptr
    %c1_i32_52 = arith.constant 1 : i32
    %85 = arith.subi %36, %c1_i32_52 : i32
    %c712_i64_53 = arith.constant 712 : i64
    %86 = llvm.getelementptr %arg1[%c712_i64_53] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %85, %86 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb21:  // pred: ^bb10
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb22:  // pred: ^bb10
    %c20_i32 = arith.constant 20 : i32
    %c728_i64 = arith.constant 728 : i64
    %87 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c20_i32, %87 : i32, !llvm.ptr
    cf.br ^bb9
  ^bb23:  // pred: ^bb11
    %c82_i64 = arith.constant 82 : i64
    return %c82_i64 : i64
  ^bb24:  // pred: ^bb11
    %c0_i64_54 = arith.constant 0 : i64
    %88 = llvm.getelementptr %56[%c0_i64_54] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %89 = llvm.load %88 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %90 = arith.cmpi eq, %89, %c11_i8 : i8
    cf.cond_br %90, ^bb25, ^bb26
  ^bb25:  // pred: ^bb24
    %c8_i64_55 = arith.constant 8 : i64
    %91 = llvm.getelementptr %56[%c8_i64_55] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %92 = llvm.load %91 : !llvm.ptr -> !llvm.ptr
    %c5089913888_i64 = arith.constant 5089913888 : i64
    %93 = llvm.inttoptr %c5089913888_i64 : i64 to !llvm.ptr
    %94 = llvm.icmp "eq" %92, %93 : !llvm.ptr
    cf.cond_br %94, ^bb27, ^bb26
  ^bb26:  // 2 preds: ^bb24, ^bb25
    %c87_i64 = arith.constant 87 : i64
    return %c87_i64 : i64
  ^bb27:  // pred: ^bb25
    %c712_i64_56 = arith.constant 712 : i64
    %95 = llvm.getelementptr %arg1[%c712_i64_56] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %96 = llvm.load %95 : !llvm.ptr -> i32
    %c716_i64_57 = arith.constant 716 : i64
    %97 = llvm.getelementptr %arg1[%c716_i64_57] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %98 = llvm.load %97 : !llvm.ptr -> i32
    %c641_i64_58 = arith.constant 641 : i64
    %99 = llvm.getelementptr %arg1[%c641_i64_58] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %100 = llvm.load %99 : !llvm.ptr -> i8
    %c1_i32_59 = arith.constant 1 : i32
    %101 = arith.cmpi eq, %96, %c1_i32_59 : i32
    %c1_i32_60 = arith.constant 1 : i32
    %102 = arith.cmpi eq, %98, %c1_i32_60 : i32
    %103 = arith.andi %101, %102 : i1
    %c0_i8_61 = arith.constant 0 : i8
    %104 = arith.cmpi ne, %100, %c0_i8_61 : i8
    %105 = arith.andi %103, %104 : i1
    cf.cond_br %105, ^bb28, ^bb13
  ^bb28:  // pred: ^bb27
    %c704_i64 = arith.constant 704 : i64
    %106 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %107 = llvm.load %106 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %108 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %109 = llvm.load %108 : !llvm.ptr -> i32
    %110 = arith.extui %107 : i32 to i64
    %111 = arith.extui %96 : i32 to i64
    %112 = arith.addi %110, %111 : i64
    %113 = arith.extui %109 : i32 to i64
    %114 = arith.cmpi uge, %112, %113 : i64
    cf.cond_br %114, ^bb29, ^bb30
  ^bb29:  // pred: ^bb28
    %c85_i64 = arith.constant 85 : i64
    return %c85_i64 : i64
  ^bb30:  // pred: ^bb28
    %c16_i64_62 = arith.constant 16 : i64
    %115 = llvm.getelementptr %56[%c16_i64_62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %116 = llvm.load %115 : !llvm.ptr -> !llvm.ptr
    %c144_i64 = arith.constant 144 : i64
    %117 = llvm.getelementptr %arg1[%c144_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %116, %117 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c642_i64_63 = arith.constant 642 : i64
    %118 = llvm.getelementptr %arg1[%c642_i64_63] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %118 : i8, !llvm.ptr
    %c2_i32_64 = arith.constant 2 : i32
    %c716_i64_65 = arith.constant 716 : i64
    %119 = llvm.getelementptr %arg1[%c716_i64_65] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c2_i32_64, %119 : i32, !llvm.ptr
    %c1_i32_66 = arith.constant 1 : i32
    %120 = arith.addi %96, %c1_i32_66 : i32
    %c712_i64_67 = arith.constant 712 : i64
    %121 = llvm.getelementptr %arg1[%c712_i64_67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %120, %121 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %122 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %123 = llvm.load %122 : !llvm.ptr -> i32
    %c1_i32_68 = arith.constant 1 : i32
    %124 = arith.addi %123, %c1_i32_68 : i32
    %c720_i64_69 = arith.constant 720 : i64
    %125 = llvm.getelementptr %arg1[%c720_i64_69] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %124, %125 : i32, !llvm.ptr
    %126 = llvm.mlir.zero : !llvm.ptr
    %c24_i64_70 = arith.constant 24 : i64
    %127 = llvm.getelementptr %arg1[%c24_i64_70] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %126, %127 : !llvm.ptr, !llvm.ptr
    cf.br ^bb10
  ^bb31:  // pred: ^bb12
    %c90_i64 = arith.constant 90 : i64
    return %c90_i64 : i64
  ^bb32:  // pred: ^bb12
    %c0_i64_71 = arith.constant 0 : i64
    %128 = llvm.getelementptr %60[%c0_i64_71] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %129 = llvm.load %128 : !llvm.ptr -> i8
    %c11_i8_72 = arith.constant 11 : i8
    %130 = arith.cmpi eq, %129, %c11_i8_72 : i8
    cf.cond_br %130, ^bb33, ^bb34
  ^bb33:  // pred: ^bb32
    %c8_i64_73 = arith.constant 8 : i64
    %131 = llvm.getelementptr %60[%c8_i64_73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %132 = llvm.load %131 : !llvm.ptr -> !llvm.ptr
    %c5089905984_i64 = arith.constant 5089905984 : i64
    %133 = llvm.inttoptr %c5089905984_i64 : i64 to !llvm.ptr
    %134 = llvm.icmp "eq" %132, %133 : !llvm.ptr
    cf.cond_br %134, ^bb35, ^bb34
  ^bb34:  // 2 preds: ^bb32, ^bb33
    %c95_i64 = arith.constant 95 : i64
    return %c95_i64 : i64
  ^bb35:  // pred: ^bb33
    %c712_i64_74 = arith.constant 712 : i64
    %135 = llvm.getelementptr %arg1[%c712_i64_74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %136 = llvm.load %135 : !llvm.ptr -> i32
    %c716_i64_75 = arith.constant 716 : i64
    %137 = llvm.getelementptr %arg1[%c716_i64_75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %138 = llvm.load %137 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %139 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %140 = llvm.load %139 : !llvm.ptr -> i8
    %c0_i32_76 = arith.constant 0 : i32
    %141 = arith.cmpi eq, %136, %c0_i32_76 : i32
    %c0_i32_77 = arith.constant 0 : i32
    %142 = arith.cmpi eq, %138, %c0_i32_77 : i32
    %143 = arith.andi %141, %142 : i1
    %c0_i8_78 = arith.constant 0 : i8
    %144 = arith.cmpi ne, %140, %c0_i8_78 : i8
    %145 = arith.andi %143, %144 : i1
    cf.cond_br %145, ^bb36, ^bb13
  ^bb36:  // pred: ^bb35
    %c704_i64_79 = arith.constant 704 : i64
    %146 = llvm.getelementptr %arg1[%c704_i64_79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %147 = llvm.load %146 : !llvm.ptr -> i32
    %c708_i64_80 = arith.constant 708 : i64
    %148 = llvm.getelementptr %arg1[%c708_i64_80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %149 = llvm.load %148 : !llvm.ptr -> i32
    %150 = arith.extui %147 : i32 to i64
    %151 = arith.extui %136 : i32 to i64
    %152 = arith.addi %150, %151 : i64
    %153 = arith.extui %149 : i32 to i64
    %154 = arith.cmpi uge, %152, %153 : i64
    cf.cond_br %154, ^bb37, ^bb38
  ^bb37:  // pred: ^bb36
    %c93_i64 = arith.constant 93 : i64
    return %c93_i64 : i64
  ^bb38:  // pred: ^bb36
    %c16_i64_81 = arith.constant 16 : i64
    %155 = llvm.getelementptr %60[%c16_i64_81] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %156 = llvm.load %155 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %157 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %156, %157 : !llvm.ptr, !llvm.ptr
    %c1_i8_82 = arith.constant 1 : i8
    %c641_i64_83 = arith.constant 641 : i64
    %158 = llvm.getelementptr %arg1[%c641_i64_83] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8_82, %158 : i8, !llvm.ptr
    %c1_i32_84 = arith.constant 1 : i32
    %c716_i64_85 = arith.constant 716 : i64
    %159 = llvm.getelementptr %arg1[%c716_i64_85] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_84, %159 : i32, !llvm.ptr
    %c1_i32_86 = arith.constant 1 : i32
    %160 = arith.addi %136, %c1_i32_86 : i32
    %c712_i64_87 = arith.constant 712 : i64
    %161 = llvm.getelementptr %arg1[%c712_i64_87] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %160, %161 : i32, !llvm.ptr
    %c720_i64_88 = arith.constant 720 : i64
    %162 = llvm.getelementptr %arg1[%c720_i64_88] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %163 = llvm.load %162 : !llvm.ptr -> i32
    %c1_i32_89 = arith.constant 1 : i32
    %164 = arith.addi %163, %c1_i32_89 : i32
    %c720_i64_90 = arith.constant 720 : i64
    %165 = llvm.getelementptr %arg1[%c720_i64_90] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %164, %165 : i32, !llvm.ptr
    %c724_i64 = arith.constant 724 : i64
    %166 = llvm.getelementptr %arg1[%c724_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %167 = llvm.load %166 : !llvm.ptr -> i32
    %c1_i32_91 = arith.constant 1 : i32
    %168 = arith.addi %167, %c1_i32_91 : i32
    %c724_i64_92 = arith.constant 724 : i64
    %169 = llvm.getelementptr %arg1[%c724_i64_92] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %168, %169 : i32, !llvm.ptr
    cf.br ^bb11
  }
}

