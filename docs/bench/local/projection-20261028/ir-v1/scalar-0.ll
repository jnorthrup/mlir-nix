; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem: none)
define range(i64 0, 43) i64 @scalar(i32 %0, ptr nofree readonly captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %16 [
    i32 0, label %13
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %9
    i32 6, label %13
  ]

common.ret:                                       ; preds = %13, %30, %9, %22, %5, %17, %2, %27, %20, %16, %4, %3
  %common.ret.op = phi i64 [ 34, %9 ], [ 1, %3 ], [ 3, %4 ], [ 4, %16 ], [ 0, %2 ], [ 26, %5 ], [ 0, %20 ], [ 0, %27 ], [ 26, %17 ], [ 34, %22 ], [ 42, %30 ], [ 42, %13 ]
  ret i64 %common.ret.op

3:                                                ; preds = %20, %27, %2
  br label %common.ret

4:                                                ; preds = %25, %33, %2
  br label %common.ret

5:                                                ; preds = %35, %2
  %6 = getelementptr i8, ptr %1, i64 8
  %7 = load ptr, ptr %6, align 8
  %8 = icmp eq ptr %7, null
  br i1 %8, label %common.ret, label %17

9:                                                ; preds = %35, %2
  %10 = getelementptr i8, ptr %1, i64 16
  %11 = load ptr, ptr %10, align 8
  %12 = icmp eq ptr %11, null
  br i1 %12, label %common.ret, label %22

13:                                               ; preds = %2, %2
  %14 = load ptr, ptr %1, align 8
  %15 = icmp eq ptr %14, null
  br i1 %15, label %common.ret, label %30

16:                                               ; preds = %2
  br label %common.ret

17:                                               ; preds = %5
  %18 = load i8, ptr %7, align 1
  %19 = icmp ult i8 %18, 3
  br i1 %19, label %common.ret, label %20

20:                                               ; preds = %17
  %21 = icmp eq i8 %18, 5
  br i1 %21, label %3, label %common.ret

22:                                               ; preds = %9
  %23 = load i8, ptr %11, align 1
  %24 = icmp ult i8 %23, 3
  br i1 %24, label %common.ret, label %25

25:                                               ; preds = %22
  %26 = icmp eq i8 %23, 5
  br i1 %26, label %27, label %4

27:                                               ; preds = %25
  %28 = getelementptr i8, ptr %11, i64 8
  %29 = load i8, ptr %28, align 1
  %.not6 = icmp eq i8 %29, 0
  br i1 %.not6, label %common.ret, label %3

30:                                               ; preds = %13
  %31 = load i8, ptr %14, align 1
  %32 = icmp ult i8 %31, 3
  br i1 %32, label %common.ret, label %33

33:                                               ; preds = %30
  %34 = icmp eq i8 %31, 5
  br i1 %34, label %35, label %4

35:                                               ; preds = %33
  %36 = getelementptr i8, ptr %14, i64 8
  %37 = load i8, ptr %36, align 1
  %.not = icmp eq i8 %37, 0
  br i1 %.not, label %9, label %5
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i32, ptr %2, align 4
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  switch i32 %3, label %20 [
    i32 0, label %17
    i32 1, label %scalar.exit
    i32 2, label %7
    i32 3, label %8
    i32 4, label %9
    i32 5, label %13
    i32 6, label %17
  ]

7:                                                ; preds = %31, %24, %1
  br label %scalar.exit

8:                                                ; preds = %37, %29, %1
  br label %scalar.exit

9:                                                ; preds = %39, %1
  %10 = getelementptr i8, ptr %6, i64 8
  %11 = load ptr, ptr %10, align 8
  %12 = icmp eq ptr %11, null
  br i1 %12, label %scalar.exit, label %21

13:                                               ; preds = %39, %1
  %14 = getelementptr i8, ptr %6, i64 16
  %15 = load ptr, ptr %14, align 8
  %16 = icmp eq ptr %15, null
  br i1 %16, label %scalar.exit, label %26

17:                                               ; preds = %1, %1
  %18 = load ptr, ptr %6, align 8
  %19 = icmp eq ptr %18, null
  br i1 %19, label %scalar.exit, label %34

20:                                               ; preds = %1
  br label %scalar.exit

21:                                               ; preds = %9
  %22 = load i8, ptr %11, align 1
  %23 = icmp ult i8 %22, 3
  br i1 %23, label %scalar.exit, label %24

24:                                               ; preds = %21
  %25 = icmp eq i8 %22, 5
  br i1 %25, label %7, label %scalar.exit

26:                                               ; preds = %13
  %27 = load i8, ptr %15, align 1
  %28 = icmp ult i8 %27, 3
  br i1 %28, label %scalar.exit, label %29

29:                                               ; preds = %26
  %30 = icmp eq i8 %27, 5
  br i1 %30, label %31, label %8

31:                                               ; preds = %29
  %32 = getelementptr i8, ptr %15, i64 8
  %33 = load i8, ptr %32, align 1
  %.not6.i = icmp eq i8 %33, 0
  br i1 %.not6.i, label %scalar.exit, label %7

34:                                               ; preds = %17
  %35 = load i8, ptr %18, align 1
  %36 = icmp ult i8 %35, 3
  br i1 %36, label %scalar.exit, label %37

37:                                               ; preds = %34
  %38 = icmp eq i8 %35, 5
  br i1 %38, label %39, label %8

39:                                               ; preds = %37
  %40 = getelementptr i8, ptr %18, i64 8
  %41 = load i8, ptr %40, align 1
  %.not.i = icmp eq i8 %41, 0
  br i1 %.not.i, label %13, label %9

scalar.exit:                                      ; preds = %1, %7, %8, %9, %13, %17, %20, %21, %24, %26, %31, %34
  %common.ret.op.i = phi i64 [ 34, %13 ], [ 1, %7 ], [ 3, %8 ], [ 4, %20 ], [ 0, %1 ], [ 26, %9 ], [ 0, %24 ], [ 0, %31 ], [ 26, %21 ], [ 34, %26 ], [ 42, %34 ], [ 42, %17 ]
  %42 = getelementptr i8, ptr %0, i64 16
  %43 = load ptr, ptr %42, align 8
  store i64 %common.ret.op.i, ptr %43, align 8
  ret void
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem: none) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
