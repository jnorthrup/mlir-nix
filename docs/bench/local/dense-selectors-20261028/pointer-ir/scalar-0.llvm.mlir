module {
  llvm.func @scalar(%arg0: i64, %arg1: !llvm.ptr, %arg2: !llvm.ptr) -> !llvm.ptr {
    %0 = llvm.mlir.constant(0 : i64) : i64
    %1 = llvm.icmp "ne" %arg0, %0 : i64
    %2 = llvm.select %1, %arg1, %arg2 : i1, !llvm.ptr
    llvm.return %2 : !llvm.ptr
  }
}

