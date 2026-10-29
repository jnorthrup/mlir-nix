module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb9 [
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
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // pred: ^bb0
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb13, ^bb16
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb20
    %3 = llvm.mlir.constant(30 : i64) : i64
    llvm.return %3 : i64
  ^bb5:  // 3 preds: ^bb0, ^bb12, ^bb15
    %4 = llvm.mlir.constant(38 : i64) : i64
    llvm.return %4 : i64
  ^bb6:  // 2 preds: ^bb0, ^bb20
    %5 = llvm.mlir.constant(8 : i64) : i64
    %6 = llvm.getelementptr %arg1[%5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %7 = llvm.load %6 : !llvm.ptr -> !llvm.ptr
    %8 = llvm.mlir.zero : !llvm.ptr
    %9 = llvm.icmp "eq" %7, %8 : !llvm.ptr
    llvm.cond_br %9, ^bb10, ^bb11
  ^bb7:  // pred: ^bb0
    %10 = llvm.mlir.constant(8 : i64) : i64
    %11 = llvm.getelementptr %arg1[%10] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %12 = llvm.load %11 : !llvm.ptr -> !llvm.ptr
    %13 = llvm.mlir.zero : !llvm.ptr
    %14 = llvm.icmp "eq" %12, %13 : !llvm.ptr
    llvm.cond_br %14, ^bb18, ^bb19
  ^bb8:  // 2 preds: ^bb0, ^bb0
    %15 = llvm.mlir.constant(0 : i64) : i64
    %16 = llvm.getelementptr %arg1[%15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %17 = llvm.load %16 : !llvm.ptr -> !llvm.ptr
    %18 = llvm.mlir.zero : !llvm.ptr
    %19 = llvm.icmp "eq" %17, %18 : !llvm.ptr
    llvm.cond_br %19, ^bb21, ^bb22
  ^bb9:  // pred: ^bb0
    %20 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %20 : i64
  ^bb10:  // 2 preds: ^bb6, ^bb11
    %21 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %21 : i64
  ^bb11:  // pred: ^bb6
    %22 = llvm.mlir.constant(0 : i64) : i64
    %23 = llvm.getelementptr %7[%22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %24 = llvm.load %23 : !llvm.ptr -> i8
    %25 = llvm.mlir.constant(2 : i8) : i8
    %26 = llvm.icmp "ule" %24, %25 : i8
    llvm.cond_br %26, ^bb10, ^bb12
  ^bb12:  // pred: ^bb11
    %27 = llvm.mlir.constant(9 : i8) : i8
    %28 = llvm.icmp "eq" %24, %27 : i8
    llvm.cond_br %28, ^bb13, ^bb5
  ^bb13:  // pred: ^bb12
    %29 = llvm.mlir.constant(8 : i64) : i64
    %30 = llvm.getelementptr %7[%29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %31 = llvm.load %30 : !llvm.ptr -> !llvm.ptr
    %32 = llvm.mlir.constant(0 : i64) : i64
    %33 = llvm.getelementptr %31[%32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %34 = llvm.load %33 : !llvm.ptr -> i32
    %35 = llvm.mlir.constant(-1 : i32) : i32
    %36 = llvm.icmp "eq" %34, %35 : i32
    llvm.cond_br %36, ^bb3, ^bb14
  ^bb14:  // pred: ^bb13
    %37 = llvm.zext %34 : i32 to i64
    %38 = llvm.mlir.constant(0 : i64) : i64
    llvm.br ^bb15(%38, %37 : i64, i64)
  ^bb15(%39: i64, %40: i64):  // 2 preds: ^bb14, ^bb17
    %41 = llvm.icmp "ult" %39, %40 : i64
    llvm.cond_br %41, ^bb16, ^bb5
  ^bb16:  // pred: ^bb15
    %42 = llvm.add %39, %40 : i64
    %43 = llvm.mlir.constant(1 : i64) : i64
    %44 = llvm.lshr %42, %43 : i64
    %45 = llvm.mlir.constant(16 : i64) : i64
    %46 = llvm.mlir.constant(16 : i64) : i64
    %47 = llvm.mul %44, %46 : i64
    %48 = llvm.add %47, %45 : i64
    %49 = llvm.getelementptr %31[%48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %50 = llvm.load %49 : !llvm.ptr -> i32
    %51 = llvm.mlir.constant(5 : i32) : i32
    %52 = llvm.icmp "eq" %50, %51 : i32
    llvm.cond_br %52, ^bb3, ^bb17
  ^bb17:  // pred: ^bb16
    %53 = llvm.mlir.constant(5 : i32) : i32
    %54 = llvm.icmp "ult" %50, %53 : i32
    %55 = llvm.mlir.constant(1 : i64) : i64
    %56 = llvm.add %44, %55 : i64
    %57 = llvm.select %54, %56, %39 : i1, i64
    %58 = llvm.select %54, %40, %44 : i1, i64
    llvm.br ^bb15(%57, %58 : i64, i64)
  ^bb18:  // 2 preds: ^bb7, ^bb19
    %59 = llvm.mlir.constant(50 : i64) : i64
    llvm.return %59 : i64
  ^bb19:  // pred: ^bb7
    %60 = llvm.mlir.constant(0 : i64) : i64
    %61 = llvm.getelementptr %12[%60] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %62 = llvm.load %61 : !llvm.ptr -> i8
    %63 = llvm.mlir.constant(2 : i8) : i8
    %64 = llvm.icmp "ule" %62, %63 : i8
    llvm.cond_br %64, ^bb18, ^bb20
  ^bb20:  // pred: ^bb19
    %65 = llvm.mlir.constant(11 : i8) : i8
    %66 = llvm.icmp "eq" %62, %65 : i8
    %67 = llvm.mlir.constant(12 : i8) : i8
    %68 = llvm.icmp "eq" %62, %67 : i8
    %69 = llvm.mlir.constant(13 : i8) : i8
    %70 = llvm.icmp "eq" %62, %69 : i8
    %71 = llvm.or %68, %70 : i1
    %72 = llvm.or %66, %71 : i1
    llvm.cond_br %72, ^bb4, ^bb6
  ^bb21:  // pred: ^bb8
    %73 = llvm.mlir.constant(58 : i64) : i64
    llvm.return %73 : i64
  ^bb22:  // pred: ^bb8
    %74 = llvm.mlir.constant(0 : i64) : i64
    %75 = llvm.getelementptr %17[%74] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %76 = llvm.load %75 : !llvm.ptr -> i8
    %77 = llvm.mlir.constant(11 : i8) : i8
    %78 = llvm.icmp "eq" %76, %77 : i8
    llvm.cond_br %78, ^bb23, ^bb24
  ^bb23:  // pred: ^bb22
    %79 = llvm.mlir.constant(8 : i64) : i64
    %80 = llvm.getelementptr %17[%79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %81 = llvm.load %80 : !llvm.ptr -> !llvm.ptr
    %82 = llvm.mlir.constant(5383500368 : i64) : i64
    %83 = llvm.inttoptr %82 : i64 to !llvm.ptr
    %84 = llvm.icmp "eq" %81, %83 : !llvm.ptr
    llvm.cond_br %84, ^bb25, ^bb24
  ^bb24:  // 2 preds: ^bb22, ^bb23
    %85 = llvm.mlir.constant(63 : i64) : i64
    llvm.return %85 : i64
  ^bb25:  // pred: ^bb23
    %86 = llvm.mlir.constant(61 : i64) : i64
    llvm.return %86 : i64
  }
}

