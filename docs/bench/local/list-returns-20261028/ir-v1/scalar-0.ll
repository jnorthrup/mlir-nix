; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite)
define range(i64 0, 27) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %12 [
    i32 0, label %5
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
  ]

common.ret:                                       ; preds = %5, %2, %13, %12, %4, %3
  %common.ret.op = phi i64 [ 0, %2 ], [ 1, %3 ], [ 3, %4 ], [ 4, %12 ], [ 6, %13 ], [ 26, %5 ]
  ret i64 %common.ret.op

3:                                                ; preds = %2
  br label %common.ret

4:                                                ; preds = %2
  br label %common.ret

5:                                                ; preds = %2, %2
  %6 = load ptr, ptr %1, align 8
  %7 = icmp ne ptr %6, null
  %8 = getelementptr i8, ptr %1, i64 8
  %9 = load ptr, ptr %8, align 8
  %10 = icmp ne ptr %9, null
  %11 = and i1 %7, %10
  br i1 %11, label %13, label %common.ret

12:                                               ; preds = %2
  br label %common.ret

13:                                               ; preds = %5
  %14 = getelementptr i8, ptr %1, i64 728
  store i32 20, ptr %14, align 8
  br label %common.ret
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i32, ptr %2, align 4
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  switch i32 %3, label %16 [
    i32 0, label %9
    i32 1, label %scalar.exit
    i32 2, label %7
    i32 3, label %8
    i32 4, label %9
  ]

7:                                                ; preds = %1
  br label %scalar.exit

8:                                                ; preds = %1
  br label %scalar.exit

9:                                                ; preds = %1, %1
  %10 = load ptr, ptr %6, align 8
  %11 = icmp ne ptr %10, null
  %12 = getelementptr i8, ptr %6, i64 8
  %13 = load ptr, ptr %12, align 8
  %14 = icmp ne ptr %13, null
  %15 = and i1 %11, %14
  br i1 %15, label %17, label %scalar.exit

16:                                               ; preds = %1
  br label %scalar.exit

17:                                               ; preds = %9
  %18 = getelementptr i8, ptr %6, i64 728
  store i32 20, ptr %18, align 8
  br label %scalar.exit

scalar.exit:                                      ; preds = %1, %7, %8, %9, %16, %17
  %common.ret.op.i = phi i64 [ 0, %1 ], [ 1, %7 ], [ 3, %8 ], [ 4, %16 ], [ 6, %17 ], [ 26, %9 ]
  %19 = getelementptr i8, ptr %0, i64 16
  %20 = load ptr, ptr %19, align 8
  store i64 %common.ret.op.i, ptr %20, align 8
  ret void
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
