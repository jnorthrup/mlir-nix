module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb5 [
      0: ^bb4,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4
    ]
  ^bb1:  // pred: ^bb0
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // pred: ^bb0
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // pred: ^bb0
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb0
    %3 = llvm.mlir.constant(true) : i1
    %4 = llvm.mlir.zero : !llvm.ptr
    %5 = llvm.mlir.constant(0 : i64) : i64
    %6 = llvm.getelementptr %arg1[%5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %7 = llvm.load %6 : !llvm.ptr -> !llvm.ptr
    %8 = llvm.icmp "ne" %7, %4 : !llvm.ptr
    %9 = llvm.mlir.constant(8 : i64) : i64
    %10 = llvm.getelementptr %arg1[%9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %11 = llvm.load %10 : !llvm.ptr -> !llvm.ptr
    %12 = llvm.icmp "ne" %11, %4 : !llvm.ptr
    %13 = llvm.and %8, %12 : i1
    %14 = llvm.mlir.constant(0 : i64) : i64
    %15 = llvm.getelementptr %arg1[%14] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %16 = llvm.load %15 : !llvm.ptr -> !llvm.ptr
    %17 = llvm.icmp "ne" %16, %4 : !llvm.ptr
    %18 = llvm.and %13, %17 : i1
    llvm.cond_br %18, ^bb8, ^bb7
  ^bb5:  // pred: ^bb0
    %19 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %19 : i64
  ^bb6:  // pred: ^bb8
    %20 = llvm.mlir.constant(6 : i64) : i64
    llvm.return %20 : i64
  ^bb7:  // pred: ^bb4
    %21 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %21 : i64
  ^bb8:  // pred: ^bb4
    %22 = llvm.mlir.constant(20 : i32) : i32
    %23 = llvm.mlir.constant(728 : i64) : i64
    %24 = llvm.getelementptr %arg1[%23] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %22, %24 : i32, !llvm.ptr
    llvm.br ^bb6
  }
}

