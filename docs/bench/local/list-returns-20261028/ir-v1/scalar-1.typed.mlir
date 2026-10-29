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
  ^bb1:  // 2 preds: ^bb0, ^bb12
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb11
    %c1_i64 = arith.constant 1 : i64
    return %c1_i64 : i64
  ^bb3:  // pred: ^bb0
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
    cf.cond_br %6, ^bb11, ^bb9
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
    cf.cond_br %13, ^bb12, ^bb9
  ^bb6:  // 2 preds: ^bb0, ^bb15
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
    cf.cond_br %20, ^bb13, ^bb9
  ^bb7:  // 2 preds: ^bb0, ^bb23
    %true = arith.constant true
    %21 = llvm.mlir.zero : !llvm.ptr
    %c16_i64 = arith.constant 16 : i64
    %22 = llvm.getelementptr %arg1[%c16_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %23 = llvm.load %22 : !llvm.ptr -> !llvm.ptr
    %24 = llvm.icmp "ne" %23, %21 : !llvm.ptr
    %25 = arith.andi %true, %24 : i1
    %c8_i64 = arith.constant 8 : i64
    %26 = llvm.getelementptr %arg1[%c8_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> !llvm.ptr
    %28 = llvm.icmp "ne" %27, %21 : !llvm.ptr
    %29 = arith.andi %25, %28 : i1
    %c16_i64_9 = arith.constant 16 : i64
    %30 = llvm.getelementptr %arg1[%c16_i64_9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %31 = llvm.load %30 : !llvm.ptr -> !llvm.ptr
    %32 = llvm.icmp "ne" %31, %21 : !llvm.ptr
    %33 = arith.andi %29, %32 : i1
    cf.cond_br %33, ^bb15, ^bb14
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %c0_i64_10 = arith.constant 0 : i64
    %34 = llvm.getelementptr %arg1[%c0_i64_10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %35 = llvm.load %34 : !llvm.ptr -> !llvm.ptr
    %36 = llvm.mlir.zero : !llvm.ptr
    %37 = llvm.icmp "eq" %35, %36 : !llvm.ptr
    cf.cond_br %37, ^bb16, ^bb17
  ^bb9:  // 5 preds: ^bb0, ^bb4, ^bb5, ^bb6, ^bb20
    %c4_i64 = arith.constant 4 : i64
    return %c4_i64 : i64
  ^bb10:  // pred: ^bb13
    %c6_i64 = arith.constant 6 : i64
    return %c6_i64 : i64
  ^bb11:  // pred: ^bb4
    %c0_i8 = arith.constant 0 : i8
    %c641_i64 = arith.constant 641 : i64
    %38 = llvm.getelementptr %arg1[%c641_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8, %38 : i8, !llvm.ptr
    %c0_i32 = arith.constant 0 : i32
    %c716_i64_11 = arith.constant 716 : i64
    %39 = llvm.getelementptr %arg1[%c716_i64_11] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32, %39 : i32, !llvm.ptr
    %c1_i32_12 = arith.constant 1 : i32
    %40 = arith.subi %1, %c1_i32_12 : i32
    %c712_i64_13 = arith.constant 712 : i64
    %41 = llvm.getelementptr %arg1[%c712_i64_13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %40, %41 : i32, !llvm.ptr
    cf.br ^bb2
  ^bb12:  // pred: ^bb5
    %c0_i8_14 = arith.constant 0 : i8
    %c641_i64_15 = arith.constant 641 : i64
    %42 = llvm.getelementptr %arg1[%c641_i64_15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_14, %42 : i8, !llvm.ptr
    %c0_i32_16 = arith.constant 0 : i32
    %c716_i64_17 = arith.constant 716 : i64
    %43 = llvm.getelementptr %arg1[%c716_i64_17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_16, %43 : i32, !llvm.ptr
    %c1_i32_18 = arith.constant 1 : i32
    %44 = arith.subi %8, %c1_i32_18 : i32
    %c712_i64_19 = arith.constant 712 : i64
    %45 = llvm.getelementptr %arg1[%c712_i64_19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %44, %45 : i32, !llvm.ptr
    cf.br ^bb1
  ^bb13:  // pred: ^bb6
    %c0_i8_20 = arith.constant 0 : i8
    %c641_i64_21 = arith.constant 641 : i64
    %46 = llvm.getelementptr %arg1[%c641_i64_21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i8_20, %46 : i8, !llvm.ptr
    %c0_i32_22 = arith.constant 0 : i32
    %c716_i64_23 = arith.constant 716 : i64
    %47 = llvm.getelementptr %arg1[%c716_i64_23] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c0_i32_22, %47 : i32, !llvm.ptr
    %c1_i32_24 = arith.constant 1 : i32
    %48 = arith.subi %15, %c1_i32_24 : i32
    %c712_i64_25 = arith.constant 712 : i64
    %49 = llvm.getelementptr %arg1[%c712_i64_25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %48, %49 : i32, !llvm.ptr
    cf.br ^bb10
  ^bb14:  // pred: ^bb7
    %c50_i64 = arith.constant 50 : i64
    return %c50_i64 : i64
  ^bb15:  // pred: ^bb7
    %c20_i32 = arith.constant 20 : i32
    %c728_i64 = arith.constant 728 : i64
    %50 = llvm.getelementptr %arg1[%c728_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c20_i32, %50 : i32, !llvm.ptr
    cf.br ^bb6
  ^bb16:  // pred: ^bb8
    %c58_i64 = arith.constant 58 : i64
    return %c58_i64 : i64
  ^bb17:  // pred: ^bb8
    %c0_i64_26 = arith.constant 0 : i64
    %51 = llvm.getelementptr %35[%c0_i64_26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %52 = llvm.load %51 : !llvm.ptr -> i8
    %c11_i8 = arith.constant 11 : i8
    %53 = arith.cmpi eq, %52, %c11_i8 : i8
    cf.cond_br %53, ^bb18, ^bb19
  ^bb18:  // pred: ^bb17
    %c8_i64_27 = arith.constant 8 : i64
    %54 = llvm.getelementptr %35[%c8_i64_27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %55 = llvm.load %54 : !llvm.ptr -> !llvm.ptr
    %c5089913888_i64 = arith.constant 5089913888 : i64
    %56 = llvm.inttoptr %c5089913888_i64 : i64 to !llvm.ptr
    %57 = llvm.icmp "eq" %55, %56 : !llvm.ptr
    cf.cond_br %57, ^bb20, ^bb19
  ^bb19:  // 2 preds: ^bb17, ^bb18
    %c63_i64 = arith.constant 63 : i64
    return %c63_i64 : i64
  ^bb20:  // pred: ^bb18
    %c712_i64_28 = arith.constant 712 : i64
    %58 = llvm.getelementptr %arg1[%c712_i64_28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %59 = llvm.load %58 : !llvm.ptr -> i32
    %c716_i64_29 = arith.constant 716 : i64
    %60 = llvm.getelementptr %arg1[%c716_i64_29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %61 = llvm.load %60 : !llvm.ptr -> i32
    %c640_i64 = arith.constant 640 : i64
    %62 = llvm.getelementptr %arg1[%c640_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %63 = llvm.load %62 : !llvm.ptr -> i8
    %c0_i32_30 = arith.constant 0 : i32
    %64 = arith.cmpi eq, %59, %c0_i32_30 : i32
    %c0_i32_31 = arith.constant 0 : i32
    %65 = arith.cmpi eq, %61, %c0_i32_31 : i32
    %66 = arith.andi %64, %65 : i1
    %c0_i8_32 = arith.constant 0 : i8
    %67 = arith.cmpi ne, %63, %c0_i8_32 : i8
    %68 = arith.andi %66, %67 : i1
    cf.cond_br %68, ^bb21, ^bb9
  ^bb21:  // pred: ^bb20
    %c704_i64 = arith.constant 704 : i64
    %69 = llvm.getelementptr %arg1[%c704_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %70 = llvm.load %69 : !llvm.ptr -> i32
    %c708_i64 = arith.constant 708 : i64
    %71 = llvm.getelementptr %arg1[%c708_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %72 = llvm.load %71 : !llvm.ptr -> i32
    %73 = arith.extui %70 : i32 to i64
    %74 = arith.extui %59 : i32 to i64
    %75 = arith.addi %73, %74 : i64
    %76 = arith.extui %72 : i32 to i64
    %77 = arith.cmpi uge, %75, %76 : i64
    cf.cond_br %77, ^bb22, ^bb23
  ^bb22:  // pred: ^bb21
    %c61_i64 = arith.constant 61 : i64
    return %c61_i64 : i64
  ^bb23:  // pred: ^bb21
    %c16_i64_33 = arith.constant 16 : i64
    %78 = llvm.getelementptr %35[%c16_i64_33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %79 = llvm.load %78 : !llvm.ptr -> !llvm.ptr
    %c136_i64 = arith.constant 136 : i64
    %80 = llvm.getelementptr %arg1[%c136_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %79, %80 : !llvm.ptr, !llvm.ptr
    %c1_i8 = arith.constant 1 : i8
    %c641_i64_34 = arith.constant 641 : i64
    %81 = llvm.getelementptr %arg1[%c641_i64_34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i8, %81 : i8, !llvm.ptr
    %c1_i32_35 = arith.constant 1 : i32
    %c716_i64_36 = arith.constant 716 : i64
    %82 = llvm.getelementptr %arg1[%c716_i64_36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %c1_i32_35, %82 : i32, !llvm.ptr
    %c1_i32_37 = arith.constant 1 : i32
    %83 = arith.addi %59, %c1_i32_37 : i32
    %c712_i64_38 = arith.constant 712 : i64
    %84 = llvm.getelementptr %arg1[%c712_i64_38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %83, %84 : i32, !llvm.ptr
    %c720_i64 = arith.constant 720 : i64
    %85 = llvm.getelementptr %arg1[%c720_i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %86 = llvm.load %85 : !llvm.ptr -> i32
    %c1_i32_39 = arith.constant 1 : i32
    %87 = arith.addi %86, %c1_i32_39 : i32
    %c720_i64_40 = arith.constant 720 : i64
    %88 = llvm.getelementptr %arg1[%c720_i64_40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %87, %88 : i32, !llvm.ptr
    %89 = llvm.mlir.zero : !llvm.ptr
    %c16_i64_41 = arith.constant 16 : i64
    %90 = llvm.getelementptr %arg1[%c16_i64_41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %89, %90 : !llvm.ptr, !llvm.ptr
    cf.br ^bb7
  }
}

