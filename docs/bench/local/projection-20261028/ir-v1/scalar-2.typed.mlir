module {
  func.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    cf.switch %arg0 : i32, [
      default: ^bb10,
      0: ^bb9,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6,
      7: ^bb7,
      8: ^bb8,
      9: ^bb9
    ]
  ^bb1:  // 2 preds: ^bb0, ^bb11
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb12
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb18, ^bb22
    %c3_i64 = arith.constant 3 : i64
    return %c3_i64 : i64
  ^bb4:  // 3 preds: ^bb0, ^bb15, ^bb19
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
    cf.cond_br %6, ^bb11, ^bb10
  ^bb5:  // 3 preds: ^bb0, ^bb15, ^bb19
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
    cf.cond_br %13, ^bb12, ^bb10
  ^bb6:  // 2 preds: ^bb0, ^bb23
    %c24_i64 = arith.constant 24 : i64
    %14 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %15 = llvm.load %14 : !llvm.ptr -> !llvm.ptr
    %16 = llvm.mlir.zero : !llvm.ptr
    %17 = llvm.icmp "eq" %15, %16 : !llvm.ptr
    cf.cond_br %17, ^bb13, ^bb14
  ^bb7:  // 2 preds: ^bb0, ^bb23
    %c40_i64 = arith.constant 40 : i64
    %18 = llvm.getelementptr %arg1[%c40_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %19 = llvm.load %18 : !llvm.ptr -> !llvm.ptr
    %20 = llvm.mlir.zero : !llvm.ptr
    %21 = llvm.icmp "eq" %19, %20 : !llvm.ptr
    cf.cond_br %21, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb31
    %c32_i64 = arith.constant 32 : i64
    %22 = llvm.getelementptr %arg1[%c32_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %23 = llvm.load %22 : !llvm.ptr -> !llvm.ptr
    %24 = llvm.mlir.zero : !llvm.ptr
    %25 = llvm.icmp "eq" %23, %24 : !llvm.ptr
    cf.cond_br %25, ^bb20, ^bb21
  ^bb9:  // 2 preds: ^bb0, ^bb0
    %c0_i64_5 = arith.constant 0 : i64
    %26 = llvm.getelementptr %arg1[%c0_i64_5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.mlir.zero : !llvm.ptr
    %29 = llvm.icmp "eq" %27, %28 : !llvm.ptr
    cf.cond_br %29, ^bb24, ^bb25
  ^bb10:  // 4 preds: ^bb0, ^bb4, ^bb5, ^bb28
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb11:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %30 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %30 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_6 = arith.constant 716 : i64
    %31 = llvm.getelementptr %arg1[%c716_i64_6] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %31 : i32, !llvm.ptr
    %c1_i32_7 = arith.constant 1 : i32
    %32 = arith.subi %1, %c1_i32_7 : i32
    %c712_i64_8 = arith.constant 712 : i64
    %33 = llvm.getelementptr %arg1[%c712_i64_8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %32, %33 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb12:  // pred: ^bb5
    %c0_i8_9 = arith.constant 0 : i8
    %c641_i64_10 = arith.constant 641 : i64
    %34 = llvm.getelementptr %arg1[%c641_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_9, %34 : i8, !llvm.ptr
    %c0_i32_11 = arith.constant 0 : i32
    %c716_i64_12 = arith.constant 716 : i64
    %35 = llvm.getelementptr %arg1[%c716_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_11, %35 : i32, !llvm.ptr
    %c1_i32_13 = arith.constant 1 : i32
    %36 = arith.subi %8, %c1_i32_13 : i32
    %c712_i64_14 = arith.constant 712 : i64
    %37 = llvm.getelementptr %arg1[%c712_i64_14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %36, %37 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb13:  // 2 preds: ^bb6, ^bb14
    %c42_i64 = arith.constant 42 : i64
    return %c42_i64 : i64
  ^bb14:  // pred: ^bb6
    %c0_i64_15 = arith.constant 0 : i64
    %38 = llvm.getelementptr %15[%c0_i64_15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %39 = llvm.load %38 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %40 = arith.cmpi ule, %39, %c2_i8 : i8
    cf.cond_br %40, ^bb13, ^bb15
  ^bb15:  // pred: ^bb14
    %c5_i8 = arith.constant 5 : i8
    %41 = arith.cmpi eq, %39, %c5_i8 : i8
    cf.cond_br %41, ^bb4, ^bb5
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb17:  // pred: ^bb7
    %c0_i64_16 = arith.constant 0 : i64
    %42 = llvm.getelementptr %19[%c0_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> i8
    %c2_i8_17 = arith.constant 2 : i8
    %44 = arith.cmpi ule, %43, %c2_i8_17 : i8
    cf.cond_br %44, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %c5_i8_18 = arith.constant 5 : i8
    %45 = arith.cmpi eq, %43, %c5_i8_18 : i8
    cf.cond_br %45, ^bb19, ^bb3
  ^bb19:  // pred: ^bb18
    %c8_i64 = arith.constant 8 : i64
    %46 = llvm.getelementptr %19[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %47 = llvm.load %46 : !llvm.ptr -> i8
    %c0_i8_19 = arith.constant 0 : i8
    %48 = arith.cmpi ne, %47, %c0_i8_19 : i8
    cf.cond_br %48, ^bb4, ^bb5
  ^bb20:  // 2 preds: ^bb8, ^bb21
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb21:  // pred: ^bb8
    %c0_i64_20 = arith.constant 0 : i64
    %49 = llvm.getelementptr %23[%c0_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %50 = llvm.load %49 : !llvm.ptr -> i8
    %c2_i8_21 = arith.constant 2 : i8
    %51 = arith.cmpi ule, %50, %c2_i8_21 : i8
    cf.cond_br %51, ^bb20, ^bb22
  ^bb22:  // pred: ^bb21
    %c5_i8_22 = arith.constant 5 : i8
    %52 = arith.cmpi eq, %50, %c5_i8_22 : i8
    cf.cond_br %52, ^bb23, ^bb3
  ^bb23:  // pred: ^bb22
    %c8_i64_23 = arith.constant 8 : i64
    %53 = llvm.getelementptr %23[%c8_i64_23] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %54 = llvm.load %53 : !llvm.ptr -> i8
    %c0_i8_24 = arith.constant 0 : i8
    %55 = arith.cmpi ne, %54, %c0_i8_24 : i8
    cf.cond_br %55, ^bb6, ^bb7
  ^bb24:  // pred: ^bb9
    %c66_i64 = arith.constant 66 : i64
    return %c66_i64 : i64
  ^bb25:  // pred: ^bb9
    %c0_i64_25 = arith.constant 0 : i64
    %56 = llvm.getelementptr %27[%c0_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %57 = llvm.load %56 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %58 = arith.cmpi eq, %57, %c11_i8 : i8
    cf.cond_br %58, ^bb26, ^bb27
  ^bb26:  // pred: ^bb25
    %c8_i64_26 = arith.constant 8 : i64
    %59 = llvm.getelementptr %27[%c8_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %60 = llvm.load %59 : !llvm.ptr -> !llvm.ptr
    %c5710640768_i64 = arith.constant 5710640768 : i64
    %61 = llvm.inttoptr %c5710640768_i64 : i64 to !llvm.ptr
    %62 = llvm.icmp "eq" %60, %61 : !llvm.ptr
    cf.cond_br %62, ^bb28, ^bb27
  ^bb27:  // 2 preds: ^bb25, ^bb26
    %c71_i64 = arith.constant 71 : i64
    return %c71_i64 : i64
  ^bb28:  // pred: ^bb26
    %c712_i64_27 = arith.constant 712 : i64
    %63 = llvm.getelementptr %arg1[%c712_i64_27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %64 = llvm.load %63 : !llvm.ptr -> i32
    %c716_i64_28 = arith.constant 716 : i64
    %65 = llvm.getelementptr %arg1[%c716_i64_28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %66 = llvm.load %65 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %67 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %68 = llvm.load %67 : !llvm.ptr -> i8
    %c0_i32_29 = arith.constant 0 : i32
    %69 = arith.cmpi eq, %64, %c0_i32_29 : i32
    %c0_i32_30 = arith.constant 0 : i32
    %70 = arith.cmpi eq, %66, %c0_i32_30 : i32
    %71 = arith.andi %69, %70 : i1
    %c0_i8_31 = arith.constant 0 : i8
    %72 = arith.cmpi ne, %68, %c0_i8_31 : i8
    %73 = arith.andi %71, %72 : i1
    cf.cond_br %73, ^bb29, ^bb10
  ^bb29:  // pred: ^bb28
    %c704_i64 = arith.constant 704 : i64
    %74 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %75 = llvm.load %74 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %76 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %77 = llvm.load %76 : !llvm.ptr -> i32
    %78 = arith.extui %75 : i32 to i64
    %79 = arith.extui %64 : i32 to i64
    %80 = arith.addi %78, %79 : i64
    %81 = arith.extui %77 : i32 to i64
    %82 = arith.cmpi uge, %80, %81 : i64
    cf.cond_br %82, ^bb30, ^bb31
  ^bb30:  // pred: ^bb29
    %c69_i64 = arith.constant 69 : i64
    return %c69_i64 : i64
  ^bb31:  // pred: ^bb29
    %c16_i64 = arith.constant 16 : i64
    %83 = llvm.getelementptr %27[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %84 = llvm.load %83 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %85 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %84, %85 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_32 = arith.constant 641 : i64
    %86 = llvm.getelementptr %arg1[%c641_i64_32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %86 : i8, !llvm.ptr
    %c1_i32_33 = arith.constant 1 : i32
    %c716_i64_34 = arith.constant 716 : i64
    %87 = llvm.getelementptr %arg1[%c716_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_33, %87 : i32, !llvm.ptr
    %c1_i32_35 = arith.constant 1 : i32
    %88 = arith.addi %64, %c1_i32_35 : i32
    %c712_i64_36 = arith.constant 712 : i64
    %89 = llvm.getelementptr %arg1[%c712_i64_36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %88, %89 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %90 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %91 = llvm.load %90 : !llvm.ptr -> i32
    %c1_i32_37 = arith.constant 1 : i32
    %92 = arith.addi %91, %c1_i32_37 : i32
    %c720_i64_38 = arith.constant 720 : i64
    %93 = llvm.getelementptr %arg1[%c720_i64_38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %92, %93 : i32, !llvm.ptr
    %c724_i64 = arith.constant 724 : i64
    %94 = llvm.getelementptr %arg1[%c724_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %95 = llvm.load %94 : !llvm.ptr -> i32
    %c1_i32_39 = arith.constant 1 : i32
    %96 = arith.addi %95, %c1_i32_39 : i32
    %c724_i64_40 = arith.constant 724 : i64
    %97 = llvm.getelementptr %arg1[%c724_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %96, %97 : i32, !llvm.ptr
    %98 = llvm.mlir.zero : !llvm.ptr
    %c32_i64_41 = arith.constant 32 : i64
    %99 = llvm.getelementptr %arg1[%c32_i64_41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %98, %99 : !llvm.ptr, !llvm.ptr
    %100 = llvm.mlir.zero : !llvm.ptr
    %c40_i64_42 = arith.constant 40 : i64
    %101 = llvm.getelementptr %arg1[%c40_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %100, %101 : !llvm.ptr, !llvm.ptr
    cf.br ^bb8
  }
}

