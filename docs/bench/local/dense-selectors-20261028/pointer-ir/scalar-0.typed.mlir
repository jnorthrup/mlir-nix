module {
  func.func @scalar(%arg0: i64, %arg1: !llvm.ptr, %arg2: !llvm.ptr) -> !llvm.ptr {
    %c0_i64 = arith.constant 0 : i64
    %0 = arith.cmpi ne, %arg0, %c0_i64 : i64
    %1 = llvm.select %0, %arg1, %arg2 : i1, !llvm.ptr
    return %1 : !llvm.ptr
  }
}

