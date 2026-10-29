module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb7 [
      0: ^bb6,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5,
      6: ^bb6
    ]
  ^bb1:  // pred: ^bb0
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // pred: ^bb0
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 2 preds: ^bb0, ^bb17
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb18
    %3 = llvm.mlir.constant(16 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    llvm.cond_br %7, ^bb9, ^bb10
  ^bb5:  // 2 preds: ^bb0, ^bb18
    %8 = llvm.mlir.constant(24 : i64) : i64
    %9 = llvm.getelementptr %arg1[%8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> !llvm.ptr
    %11 = llvm.mlir.zero : !llvm.ptr
    %12 = llvm.icmp "eq" %10, %11 : !llvm.ptr
    llvm.cond_br %12, ^bb12, ^bb13
  ^bb6:  // 2 preds: ^bb0, ^bb0
    %13 = llvm.mlir.constant(0 : i64) : i64
    %14 = llvm.getelementptr %arg1[%13] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %15 = llvm.load %14 : !llvm.ptr -> !llvm.ptr
    %16 = llvm.mlir.zero : !llvm.ptr
    %17 = llvm.icmp "eq" %15, %16 : !llvm.ptr
    llvm.cond_br %17, ^bb15, ^bb16
  ^bb7:  // pred: ^bb0
    %18 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %18 : i64
  ^bb8:  // 2 preds: ^bb11, ^bb14
    %19 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %19 : i64
  ^bb9:  // 2 preds: ^bb4, ^bb10
    %20 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %20 : i64
  ^bb10:  // pred: ^bb4
    %21 = llvm.mlir.constant(0 : i64) : i64
    %22 = llvm.getelementptr %5[%21] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %23 = llvm.load %22 : !llvm.ptr -> i8
    %24 = llvm.mlir.constant(2 : i8) : i8
    %25 = llvm.icmp "ule" %23, %24 : i8
    llvm.cond_br %25, ^bb9, ^bb11
  ^bb11:  // pred: ^bb10
    %26 = llvm.mlir.constant(2 : i32) : i32
    %27 = llvm.mlir.constant(728 : i64) : i64
    %28 = llvm.getelementptr %arg1[%27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %26, %28 : i32, !llvm.ptr
    llvm.br ^bb8
  ^bb12:  // 2 preds: ^bb5, ^bb13
    %29 = llvm.mlir.constant(34 : i64) : i64
    llvm.return %29 : i64
  ^bb13:  // pred: ^bb5
    %30 = llvm.mlir.constant(0 : i64) : i64
    %31 = llvm.getelementptr %10[%30] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %32 = llvm.load %31 : !llvm.ptr -> i8
    %33 = llvm.mlir.constant(2 : i8) : i8
    %34 = llvm.icmp "ule" %32, %33 : i8
    llvm.cond_br %34, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %35 = llvm.mlir.constant(3 : i32) : i32
    %36 = llvm.mlir.constant(728 : i64) : i64
    %37 = llvm.getelementptr %arg1[%36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %35, %37 : i32, !llvm.ptr
    llvm.br ^bb8
  ^bb15:  // 2 preds: ^bb6, ^bb16
    %38 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %38 : i64
  ^bb16:  // pred: ^bb6
    %39 = llvm.mlir.constant(0 : i64) : i64
    %40 = llvm.getelementptr %15[%39] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %41 = llvm.load %40 : !llvm.ptr -> i8
    %42 = llvm.mlir.constant(2 : i8) : i8
    %43 = llvm.icmp "ule" %41, %42 : i8
    llvm.cond_br %43, ^bb15, ^bb17
  ^bb17:  // pred: ^bb16
    %44 = llvm.mlir.constant(5 : i8) : i8
    %45 = llvm.icmp "eq" %41, %44 : i8
    llvm.cond_br %45, ^bb18, ^bb3
  ^bb18:  // pred: ^bb17
    %46 = llvm.mlir.constant(8 : i64) : i64
    %47 = llvm.getelementptr %15[%46] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %48 = llvm.load %47 : !llvm.ptr -> i8
    %49 = llvm.mlir.constant(0 : i8) : i8
    %50 = llvm.icmp "ne" %48, %49 : i8
    llvm.cond_br %50, ^bb4, ^bb5
  }
}

