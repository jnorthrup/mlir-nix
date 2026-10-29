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
  ^bb1:  // 3 preds: ^bb0, ^bb10, ^bb14
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 3 preds: ^bb0, ^bb10, ^bb14
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb13, ^bb17
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb18
    %3 = llvm.mlir.constant(8 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    llvm.cond_br %7, ^bb8, ^bb9
  ^bb5:  // 2 preds: ^bb0, ^bb18
    %8 = llvm.mlir.constant(16 : i64) : i64
    %9 = llvm.getelementptr %arg1[%8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> !llvm.ptr
    %11 = llvm.mlir.zero : !llvm.ptr
    %12 = llvm.icmp "eq" %10, %11 : !llvm.ptr
    llvm.cond_br %12, ^bb11, ^bb12
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
  ^bb8:  // 2 preds: ^bb4, ^bb9
    %19 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %19 : i64
  ^bb9:  // pred: ^bb4
    %20 = llvm.mlir.constant(0 : i64) : i64
    %21 = llvm.getelementptr %5[%20] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %22 = llvm.load %21 : !llvm.ptr -> i8
    %23 = llvm.mlir.constant(2 : i8) : i8
    %24 = llvm.icmp "ule" %22, %23 : i8
    llvm.cond_br %24, ^bb8, ^bb10
  ^bb10:  // pred: ^bb9
    %25 = llvm.mlir.constant(5 : i8) : i8
    %26 = llvm.icmp "eq" %22, %25 : i8
    llvm.cond_br %26, ^bb2, ^bb1
  ^bb11:  // 2 preds: ^bb5, ^bb12
    %27 = llvm.mlir.constant(34 : i64) : i64
    llvm.return %27 : i64
  ^bb12:  // pred: ^bb5
    %28 = llvm.mlir.constant(0 : i64) : i64
    %29 = llvm.getelementptr %10[%28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %30 = llvm.load %29 : !llvm.ptr -> i8
    %31 = llvm.mlir.constant(2 : i8) : i8
    %32 = llvm.icmp "ule" %30, %31 : i8
    llvm.cond_br %32, ^bb11, ^bb13
  ^bb13:  // pred: ^bb12
    %33 = llvm.mlir.constant(5 : i8) : i8
    %34 = llvm.icmp "eq" %30, %33 : i8
    llvm.cond_br %34, ^bb14, ^bb3
  ^bb14:  // pred: ^bb13
    %35 = llvm.mlir.constant(8 : i64) : i64
    %36 = llvm.getelementptr %10[%35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> i8
    %38 = llvm.mlir.constant(0 : i8) : i8
    %39 = llvm.icmp "ne" %37, %38 : i8
    llvm.cond_br %39, ^bb2, ^bb1
  ^bb15:  // 2 preds: ^bb6, ^bb16
    %40 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %40 : i64
  ^bb16:  // pred: ^bb6
    %41 = llvm.mlir.constant(0 : i64) : i64
    %42 = llvm.getelementptr %15[%41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> i8
    %44 = llvm.mlir.constant(2 : i8) : i8
    %45 = llvm.icmp "ule" %43, %44 : i8
    llvm.cond_br %45, ^bb15, ^bb17
  ^bb17:  // pred: ^bb16
    %46 = llvm.mlir.constant(5 : i8) : i8
    %47 = llvm.icmp "eq" %43, %46 : i8
    llvm.cond_br %47, ^bb18, ^bb3
  ^bb18:  // pred: ^bb17
    %48 = llvm.mlir.constant(8 : i64) : i64
    %49 = llvm.getelementptr %15[%48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %50 = llvm.load %49 : !llvm.ptr -> i8
    %51 = llvm.mlir.constant(0 : i8) : i8
    %52 = llvm.icmp "ne" %50, %51 : i8
    llvm.cond_br %52, ^bb4, ^bb5
  }
}

