; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 43) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %14 [
    i32 0, label %11
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %9
    i32 6, label %11
  ]

common.ret:                                       ; preds = %11, %20, %5, %15, %9, %18, %2, %14, %4, %3
  %common.ret.op = phi i64 [ 26, %5 ], [ 1, %3 ], [ 3, %4 ], [ 4, %14 ], [ 0, %2 ], [ 6, %9 ], [ 6, %18 ], [ 26, %15 ], [ 42, %20 ], [ 42, %11 ]
  ret i64 %common.ret.op

3:                                                ; preds = %2
  br label %common.ret

4:                                                ; preds = %23, %2
  br label %common.ret

5:                                                ; preds = %25, %2
  %6 = getelementptr i8, ptr %1, i64 16
  %7 = load ptr, ptr %6, align 8
  %8 = icmp eq ptr %7, null
  br i1 %8, label %common.ret, label %15

9:                                                ; preds = %25, %2
  %10 = getelementptr i8, ptr %1, i64 728
  store i32 18, ptr %10, align 4
  br label %common.ret

11:                                               ; preds = %2, %2
  %12 = load ptr, ptr %1, align 8
  %13 = icmp eq ptr %12, null
  br i1 %13, label %common.ret, label %20

14:                                               ; preds = %2
  br label %common.ret

15:                                               ; preds = %5
  %16 = load i8, ptr %7, align 1
  %17 = icmp ult i8 %16, 3
  br i1 %17, label %common.ret, label %18

18:                                               ; preds = %15
  %19 = getelementptr i8, ptr %1, i64 728
  store i32 2, ptr %19, align 8
  br label %common.ret

20:                                               ; preds = %11
  %21 = load i8, ptr %12, align 1
  %22 = icmp ult i8 %21, 3
  br i1 %22, label %common.ret, label %23

23:                                               ; preds = %20
  %24 = icmp eq i8 %21, 5
  br i1 %24, label %25, label %4

25:                                               ; preds = %23
  %26 = getelementptr i8, ptr %12, i64 8
  %27 = load i8, ptr %26, align 1
  %.not = icmp eq i8 %27, 0
  br i1 %.not, label %9, label %5
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i32, ptr %2, align 4
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  switch i32 %3, label %18 [
    i32 0, label %15
    i32 1, label %scalar.exit
    i32 2, label %7
    i32 3, label %8
    i32 4, label %9
    i32 5, label %13
    i32 6, label %15
  ]

7:                                                ; preds = %1
  br label %scalar.exit

8:                                                ; preds = %27, %1
  br label %scalar.exit

9:                                                ; preds = %29, %1
  %10 = getelementptr i8, ptr %6, i64 16
  %11 = load ptr, ptr %10, align 8
  %12 = icmp eq ptr %11, null
  br i1 %12, label %scalar.exit, label %19

13:                                               ; preds = %29, %1
  %14 = getelementptr i8, ptr %6, i64 728
  store i32 18, ptr %14, align 4
  br label %scalar.exit

15:                                               ; preds = %1, %1
  %16 = load ptr, ptr %6, align 8
  %17 = icmp eq ptr %16, null
  br i1 %17, label %scalar.exit, label %24

18:                                               ; preds = %1
  br label %scalar.exit

19:                                               ; preds = %9
  %20 = load i8, ptr %11, align 1
  %21 = icmp ult i8 %20, 3
  br i1 %21, label %scalar.exit, label %22

22:                                               ; preds = %19
  %23 = getelementptr i8, ptr %6, i64 728
  store i32 2, ptr %23, align 8
  br label %scalar.exit

24:                                               ; preds = %15
  %25 = load i8, ptr %16, align 1
  %26 = icmp ult i8 %25, 3
  br i1 %26, label %scalar.exit, label %27

27:                                               ; preds = %24
  %28 = icmp eq i8 %25, 5
  br i1 %28, label %29, label %8

29:                                               ; preds = %27
  %30 = getelementptr i8, ptr %16, i64 8
  %31 = load i8, ptr %30, align 1
  %.not.i = icmp eq i8 %31, 0
  br i1 %.not.i, label %13, label %9

scalar.exit:                                      ; preds = %1, %7, %8, %9, %13, %15, %18, %19, %22, %24
  %common.ret.op.i = phi i64 [ 26, %9 ], [ 1, %7 ], [ 3, %8 ], [ 4, %18 ], [ 0, %1 ], [ 6, %13 ], [ 6, %22 ], [ 26, %19 ], [ 42, %24 ], [ 42, %15 ]
  %32 = getelementptr i8, ptr %0, i64 16
  %33 = load ptr, ptr %32, align 8
  store i64 %common.ret.op.i, ptr %33, align 8
  ret void
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
