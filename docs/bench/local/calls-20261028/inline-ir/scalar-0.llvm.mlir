module {
  llvm.func @scalar(%arg0: i32, %arg1: !llvm.ptr) -> i64 {
    llvm.switch %arg0 : i32, ^bb6 [
      0: ^bb5,
      1: ^bb1,
      2: ^bb2,
      3: ^bb3,
      4: ^bb4,
      5: ^bb5
    ]
  ^bb1:  // 3 preds: ^bb0, ^bb9, ^bb12
    %0 = llvm.mlir.constant(0 : i64) : i64
    llvm.return %0 : i64
  ^bb2:  // 2 preds: ^bb0, ^bb17
    %1 = llvm.mlir.constant(1 : i64) : i64
    llvm.return %1 : i64
  ^bb3:  // 3 preds: ^bb0, ^bb10, ^bb13
    %2 = llvm.mlir.constant(3 : i64) : i64
    llvm.return %2 : i64
  ^bb4:  // 2 preds: ^bb0, ^bb17
    %3 = llvm.mlir.constant(0 : i64) : i64
    %4 = llvm.getelementptr %arg1[%3] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %5 = llvm.load %4 : !llvm.ptr -> !llvm.ptr
    %6 = llvm.mlir.zero : !llvm.ptr
    %7 = llvm.icmp "eq" %5, %6 : !llvm.ptr
    llvm.cond_br %7, ^bb7, ^bb8
  ^bb5:  // 2 preds: ^bb0, ^bb0
    %8 = llvm.mlir.constant(0 : i64) : i64
    %9 = llvm.getelementptr %arg1[%8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %10 = llvm.load %9 : !llvm.ptr -> !llvm.ptr
    %11 = llvm.mlir.zero : !llvm.ptr
    %12 = llvm.icmp "eq" %10, %11 : !llvm.ptr
    llvm.cond_br %12, ^bb15, ^bb16
  ^bb6:  // pred: ^bb0
    %13 = llvm.mlir.constant(4 : i64) : i64
    llvm.return %13 : i64
  ^bb7:  // 2 preds: ^bb4, ^bb8
    %14 = llvm.mlir.constant(26 : i64) : i64
    llvm.return %14 : i64
  ^bb8:  // pred: ^bb4
    %15 = llvm.mlir.constant(0 : i64) : i64
    %16 = llvm.getelementptr %5[%15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %17 = llvm.load %16 : !llvm.ptr -> i8
    %18 = llvm.mlir.constant(2 : i8) : i8
    %19 = llvm.icmp "ule" %17, %18 : i8
    llvm.cond_br %19, ^bb7, ^bb9
  ^bb9:  // pred: ^bb8
    %20 = llvm.mlir.constant(9 : i8) : i8
    %21 = llvm.icmp "eq" %17, %20 : i8
    llvm.cond_br %21, ^bb10, ^bb1
  ^bb10:  // pred: ^bb9
    %22 = llvm.mlir.constant(8 : i64) : i64
    %23 = llvm.getelementptr %5[%22] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %24 = llvm.load %23 : !llvm.ptr -> !llvm.ptr
    %25 = llvm.mlir.constant(0 : i64) : i64
    %26 = llvm.getelementptr %24[%25] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %27 = llvm.load %26 : !llvm.ptr -> i32
    %28 = llvm.mlir.constant(-1 : i32) : i32
    %29 = llvm.icmp "eq" %27, %28 : i32
    llvm.cond_br %29, ^bb3, ^bb11
  ^bb11:  // pred: ^bb10
    %30 = llvm.zext %27 : i32 to i64
    %31 = llvm.mlir.constant(0 : i64) : i64
    llvm.br ^bb12(%31, %30 : i64, i64)
  ^bb12(%32: i64, %33: i64):  // 2 preds: ^bb11, ^bb14
    %34 = llvm.icmp "ult" %32, %33 : i64
    llvm.cond_br %34, ^bb13, ^bb1
  ^bb13:  // pred: ^bb12
    %35 = llvm.add %32, %33 : i64
    %36 = llvm.mlir.constant(1 : i64) : i64
    %37 = llvm.lshr %35, %36 : i64
    %38 = llvm.mlir.constant(16 : i64) : i64
    %39 = llvm.mlir.constant(16 : i64) : i64
    %40 = llvm.mul %37, %39 : i64
    %41 = llvm.add %40, %38 : i64
    %42 = llvm.getelementptr %24[%41] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %43 = llvm.load %42 : !llvm.ptr -> i32
    %44 = llvm.mlir.constant(5 : i32) : i32
    %45 = llvm.icmp "eq" %43, %44 : i32
    llvm.cond_br %45, ^bb3, ^bb14
  ^bb14:  // pred: ^bb13
    %46 = llvm.mlir.constant(5 : i32) : i32
    %47 = llvm.icmp "ult" %43, %46 : i32
    %48 = llvm.mlir.constant(1 : i64) : i64
    %49 = llvm.add %37, %48 : i64
    %50 = llvm.select %47, %49, %32 : i1, i64
    %51 = llvm.select %47, %33, %37 : i1, i64
    llvm.br ^bb12(%50, %51 : i64, i64)
  ^bb15:  // 2 preds: ^bb5, ^bb16
    %52 = llvm.mlir.constant(34 : i64) : i64
    llvm.return %52 : i64
  ^bb16:  // pred: ^bb5
    %53 = llvm.mlir.constant(0 : i64) : i64
    %54 = llvm.getelementptr %10[%53] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %55 = llvm.load %54 : !llvm.ptr -> i8
    %56 = llvm.mlir.constant(2 : i8) : i8
    %57 = llvm.icmp "ule" %55, %56 : i8
    llvm.cond_br %57, ^bb15, ^bb17
  ^bb17:  // pred: ^bb16
    %58 = llvm.mlir.constant(11 : i8) : i8
    %59 = llvm.icmp "eq" %55, %58 : i8
    %60 = llvm.mlir.constant(12 : i8) : i8
    %61 = llvm.icmp "eq" %55, %60 : i8
    %62 = llvm.mlir.constant(13 : i8) : i8
    %63 = llvm.icmp "eq" %55, %62 : i8
    %64 = llvm.or %61, %63 : i1
    %65 = llvm.or %59, %64 : i1
    llvm.cond_br %65, ^bb2, ^bb4
  }
}

