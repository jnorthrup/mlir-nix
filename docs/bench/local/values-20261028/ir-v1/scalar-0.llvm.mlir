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
  ^bb3:  // 2 preds: ^bb0, ^bb14
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb15
    %3 = llvm.mlir.constant(16 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    llvm.cond_br %7, ^bb9, ^bb10
  ^bb5:  // 2 preds: ^bb0, ^bb15
    %8 = llvm.mlir.constant(18 : i32) : i32
    %9 = llvm.mlir.constant(728 : i64) : i64
    %10 = llvm.getelementptr %arg1[%9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %8, %10 : i32, !llvm.ptr
    llvm.br ^bb8
  ^bb6:  // 2 preds: ^bb0, ^bb0
    %11 = llvm.mlir.constant(0 : i64) : i64
    %12 = llvm.getelementptr %arg1[%11] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %13 = llvm.load %12 : !llvm.ptr -> !llvm.ptr
    %14 = llvm.mlir.zero : !llvm.ptr
    %15 = llvm.icmp "eq" %13, %14 : !llvm.ptr
    llvm.cond_br %15, ^bb12, ^bb13
  ^bb7:  // pred: ^bb0
    %16 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %16 : i64
  ^bb8:  // 2 preds: ^bb5, ^bb11
    %17 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %17 : i64
  ^bb9:  // 2 preds: ^bb4, ^bb10
    %18 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %18 : i64
  ^bb10:  // pred: ^bb4
    %19 = llvm.mlir.constant(0 : i64) : i64
    %20 = llvm.getelementptr %5[%19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %21 = llvm.load %20 : !llvm.ptr -> i8
    %22 = llvm.mlir.constant(2 : i8) : i8
    %23 = llvm.icmp "ule" %21, %22 : i8
    llvm.cond_br %23, ^bb9, ^bb11
  ^bb11:  // pred: ^bb10
    %24 = llvm.mlir.constant(2 : i32) : i32
    %25 = llvm.mlir.constant(728 : i64) : i64
    %26 = llvm.getelementptr %arg1[%25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %24, %26 : i32, !llvm.ptr
    llvm.br ^bb8
  ^bb12:  // 2 preds: ^bb6, ^bb13
    %27 = llvm.mlir.constant(42 : i64) : i64
    llvm.return %27 : i64
  ^bb13:  // pred: ^bb6
    %28 = llvm.mlir.constant(0 : i64) : i64
    %29 = llvm.getelementptr %13[%28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %30 = llvm.load %29 : !llvm.ptr -> i8
    %31 = llvm.mlir.constant(2 : i8) : i8
    %32 = llvm.icmp "ule" %30, %31 : i8
    llvm.cond_br %32, ^bb12, ^bb14
  ^bb14:  // pred: ^bb13
    %33 = llvm.mlir.constant(5 : i8) : i8
    %34 = llvm.icmp "eq" %30, %33 : i8
    llvm.cond_br %34, ^bb15, ^bb3
  ^bb15:  // pred: ^bb14
    %35 = llvm.mlir.constant(8 : i64) : i64
    %36 = llvm.getelementptr %13[%35] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %37 = llvm.load %36 : !llvm.ptr -> i8
    %38 = llvm.mlir.constant(0 : i8) : i8
    %39 = llvm.icmp "ne" %37, %38 : i8
    llvm.cond_br %39, ^bb4, ^bb5
  }
}

