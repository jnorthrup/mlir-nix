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
  ^bb3:  // 2 preds: ^bb0, ^bb21
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
  ^bb6:  // 3 preds: ^bb0, ^bb8, ^bb18
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
  ^bb7:  // 2 preds: ^bb0, ^bb22
    %c24_i64 = arith.constant 24 : i64
    %21 = llvm.getelementptr %arg1[%c24_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %22 = llvm.load %21 : !llvm.ptr -> !llvm.ptr
    %23 = llvm.mlir.zero : !llvm.ptr
    %24 = llvm.icmp "eq" %22, %23 : !llvm.ptr
    cf.cond_br %24, ^bb16, ^bb17
  ^bb8:  // 2 preds: ^bb0, ^bb22
    %c18_i32 = arith.constant 18 : i32
    %c728_i64 = arith.constant 728 : i64
    %25 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c18_i32, %25 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb9:  // 2 preds: ^bb0, ^bb30
    %c16_i64 = arith.constant 16 : i64
    %26 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.mlir.zero : !llvm.ptr
    %29 = llvm.icmp "eq" %27, %28 : !llvm.ptr
    cf.cond_br %29, ^bb19, ^bb20
  ^bb10:  // 2 preds: ^bb0, ^bb0
    %c0_i64_9 = arith.constant 0 : i64
    %30 = llvm.getelementptr %arg1[%c0_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %31 = llvm.load %30 : !llvm.ptr -> !llvm.ptr
    %32 = llvm.mlir.zero : !llvm.ptr
    %33 = llvm.icmp "eq" %31, %32 : !llvm.ptr
    cf.cond_br %33, ^bb23, ^bb24
  ^bb11:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb27
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb12:  // pred: ^bb15
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb13:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %34 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %34 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_10 = arith.constant 716 : i64
    %35 = llvm.getelementptr %arg1[%c716_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %35 : i32, !llvm.ptr
    %c1_i32_11 = arith.constant 1 : i32
    %36 = arith.subi %1, %c1_i32_11 : i32
    %c712_i64_12 = arith.constant 712 : i64
    %37 = llvm.getelementptr %arg1[%c712_i64_12] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %36, %37 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb14:  // pred: ^bb5
    %c0_i8_13 = arith.constant 0 : i8
    %c641_i64_14 = arith.constant 641 : i64
    %38 = llvm.getelementptr %arg1[%c641_i64_14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_13, %38 : i8, !llvm.ptr
    %c0_i32_15 = arith.constant 0 : i32
    %c716_i64_16 = arith.constant 716 : i64
    %39 = llvm.getelementptr %arg1[%c716_i64_16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_15, %39 : i32, !llvm.ptr
    %c1_i32_17 = arith.constant 1 : i32
    %40 = arith.subi %8, %c1_i32_17 : i32
    %c712_i64_18 = arith.constant 712 : i64
    %41 = llvm.getelementptr %arg1[%c712_i64_18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %40, %41 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb15:  // pred: ^bb6
    %c0_i8_19 = arith.constant 0 : i8
    %c641_i64_20 = arith.constant 641 : i64
    %42 = llvm.getelementptr %arg1[%c641_i64_20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_19, %42 : i8, !llvm.ptr
    %c0_i32_21 = arith.constant 0 : i32
    %c716_i64_22 = arith.constant 716 : i64
    %43 = llvm.getelementptr %arg1[%c716_i64_22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_21, %43 : i32, !llvm.ptr
    %c1_i32_23 = arith.constant 1 : i32
    %44 = arith.subi %15, %c1_i32_23 : i32
    %c712_i64_24 = arith.constant 712 : i64
    %45 = llvm.getelementptr %arg1[%c712_i64_24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %44, %45 : i32, !llvm.ptr
    cf.br ^bb12
  ^bb16:  // 2 preds: ^bb7, ^bb17
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb17:  // pred: ^bb7
    %c0_i64_25 = arith.constant 0 : i64
    %46 = llvm.getelementptr %22[%c0_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %47 = llvm.load %46 : !llvm.ptr -> i8
    %c2_i8 = arith.constant 2 : i8
    %48 = arith.cmpi ule, %47, %c2_i8 : i8
    cf.cond_br %48, ^bb16, ^bb18
  ^bb18:  // pred: ^bb17
    %c3_i32 = arith.constant 3 : i32
    %c728_i64_26 = arith.constant 728 : i64
    %49 = llvm.getelementptr %arg1[%c728_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c3_i32, %49 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb19:  // 2 preds: ^bb9, ^bb20
    %c66_i64 = arith.constant 66 : i64
    return %c66_i64 : i64
  ^bb20:  // pred: ^bb9
    %c0_i64_27 = arith.constant 0 : i64
    %50 = llvm.getelementptr %27[%c0_i64_27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %51 = llvm.load %50 : !llvm.ptr -> i8
    %c2_i8_28 = arith.constant 2 : i8
    %52 = arith.cmpi ule, %51, %c2_i8_28 : i8
    cf.cond_br %52, ^bb19, ^bb21
  ^bb21:  // pred: ^bb20
    %c5_i8 = arith.constant 5 : i8
    %53 = arith.cmpi eq, %51, %c5_i8 : i8
    cf.cond_br %53, ^bb22, ^bb3
  ^bb22:  // pred: ^bb21
    %c8_i64 = arith.constant 8 : i64
    %54 = llvm.getelementptr %27[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %55 = llvm.load %54 : !llvm.ptr -> i8
    %c0_i8_29 = arith.constant 0 : i8
    %56 = arith.cmpi ne, %55, %c0_i8_29 : i8
    cf.cond_br %56, ^bb7, ^bb8
  ^bb23:  // pred: ^bb10
    %c74_i64 = arith.constant 74 : i64
    return %c74_i64 : i64
  ^bb24:  // pred: ^bb10
    %c0_i64_30 = arith.constant 0 : i64
    %57 = llvm.getelementptr %31[%c0_i64_30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %58 = llvm.load %57 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %59 = arith.cmpi eq, %58, %c11_i8 : i8
    cf.cond_br %59, ^bb25, ^bb26
  ^bb25:  // pred: ^bb24
    %c8_i64_31 = arith.constant 8 : i64
    %60 = llvm.getelementptr %31[%c8_i64_31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %61 = llvm.load %60 : !llvm.ptr -> !llvm.ptr
    %c5685503168_i64 = arith.constant 5685503168 : i64
    %62 = llvm.inttoptr %c5685503168_i64 : i64 to !llvm.ptr
    %63 = llvm.icmp "eq" %61, %62 : !llvm.ptr
    cf.cond_br %63, ^bb27, ^bb26
  ^bb26:  // 2 preds: ^bb24, ^bb25
    %c79_i64 = arith.constant 79 : i64
    return %c79_i64 : i64
  ^bb27:  // pred: ^bb25
    %c712_i64_32 = arith.constant 712 : i64
    %64 = llvm.getelementptr %arg1[%c712_i64_32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %65 = llvm.load %64 : !llvm.ptr -> i32
    %c716_i64_33 = arith.constant 716 : i64
    %66 = llvm.getelementptr %arg1[%c716_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %67 = llvm.load %66 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %68 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %69 = llvm.load %68 : !llvm.ptr -> i8
    %c0_i32_34 = arith.constant 0 : i32
    %70 = arith.cmpi eq, %65, %c0_i32_34 : i32
    %c0_i32_35 = arith.constant 0 : i32
    %71 = arith.cmpi eq, %67, %c0_i32_35 : i32
    %72 = arith.andi %70, %71 : i1
    %c0_i8_36 = arith.constant 0 : i8
    %73 = arith.cmpi ne, %69, %c0_i8_36 : i8
    %74 = arith.andi %72, %73 : i1
    cf.cond_br %74, ^bb28, ^bb11
  ^bb28:  // pred: ^bb27
    %c704_i64 = arith.constant 704 : i64
    %75 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %76 = llvm.load %75 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %77 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %78 = llvm.load %77 : !llvm.ptr -> i32
    %79 = arith.extui %76 : i32 to i64
    %80 = arith.extui %65 : i32 to i64
    %81 = arith.addi %79, %80 : i64
    %82 = arith.extui %78 : i32 to i64
    %83 = arith.cmpi uge, %81, %82 : i64
    cf.cond_br %83, ^bb29, ^bb30
  ^bb29:  // pred: ^bb28
    %c77_i64 = arith.constant 77 : i64
    return %c77_i64 : i64
  ^bb30:  // pred: ^bb28
    %c16_i64_37 = arith.constant 16 : i64
    %84 = llvm.getelementptr %31[%c16_i64_37] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %85 = llvm.load %84 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %86 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %85, %86 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_38 = arith.constant 641 : i64
    %87 = llvm.getelementptr %arg1[%c641_i64_38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %87 : i8, !llvm.ptr
    %c1_i32_39 = arith.constant 1 : i32
    %c716_i64_40 = arith.constant 716 : i64
    %88 = llvm.getelementptr %arg1[%c716_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_39, %88 : i32, !llvm.ptr
    %c1_i32_41 = arith.constant 1 : i32
    %89 = arith.addi %65, %c1_i32_41 : i32
    %c712_i64_42 = arith.constant 712 : i64
    %90 = llvm.getelementptr %arg1[%c712_i64_42] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %89, %90 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %91 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %92 = llvm.load %91 : !llvm.ptr -> i32
    %c1_i32_43 = arith.constant 1 : i32
    %93 = arith.addi %92, %c1_i32_43 : i32
    %c720_i64_44 = arith.constant 720 : i64
    %94 = llvm.getelementptr %arg1[%c720_i64_44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %93, %94 : i32, !llvm.ptr
    %95 = llvm.mlir.zero : !llvm.ptr
    %c16_i64_45 = arith.constant 16 : i64
    %96 = llvm.getelementptr %arg1[%c16_i64_45] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %95, %96 : !llvm.ptr, !llvm.ptr
    %97 = llvm.mlir.zero : !llvm.ptr
    %c24_i64_46 = arith.constant 24 : i64
    %98 = llvm.getelementptr %arg1[%c24_i64_46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %97, %98 : !llvm.ptr, !llvm.ptr
    cf.br ^bb9
  }
}

