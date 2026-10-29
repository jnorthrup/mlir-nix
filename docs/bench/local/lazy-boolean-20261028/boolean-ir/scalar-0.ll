; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem: none)
define range(i64 0, 35) i64 @scalar(i32 %0, ptr nofree readonly captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %common.ret [
    i32 0, label %5
    i32 3, label %3
    i32 4, label %5
  ]

common.ret.fold.split:                            ; preds = %12
  br label %common.ret

common.ret:                                       ; preds = %26, %.lr.ph, %12, %common.ret.fold.split, %35, %5, %32, %3, %.thread, %2, %.thread.thread
  %common.ret.op = phi i64 [ 26, %3 ], [ 0, %.thread.thread ], [ 1, %35 ], [ 3, %12 ], [ 4, %2 ], [ 34, %32 ], [ 34, %5 ], [ 26, %.thread ], [ 0, %common.ret.fold.split ], [ 3, %.lr.ph ], [ 0, %26 ]
  ret i64 %common.ret.op

3:                                                ; preds = %2
  %.pre = load ptr, ptr %1, align 8
  %4 = icmp eq ptr %.pre, null
  br i1 %4, label %common.ret, label %.thread

5:                                                ; preds = %2, %2
  %6 = load ptr, ptr %1, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %common.ret, label %32

.thread:                                          ; preds = %3
  %.pr = load i8, ptr %.pre, align 1
  %8 = icmp ult i8 %.pr, 3
  br i1 %8, label %common.ret, label %.thread.thread

.thread.thread:                                   ; preds = %35, %.thread
  %9 = phi ptr [ %.pre, %.thread ], [ %6, %35 ]
  %10 = phi i8 [ %.pr, %.thread ], [ %33, %35 ]
  %11 = icmp eq i8 %10, 9
  br i1 %11, label %12, label %common.ret

12:                                               ; preds = %.thread.thread
  %13 = getelementptr i8, ptr %9, i64 8
  %14 = load ptr, ptr %13, align 8
  %15 = load i32, ptr %14, align 4
  switch i32 %15, label %.lr.ph.preheader [
    i32 -1, label %common.ret
    i32 0, label %common.ret.fold.split
  ]

.lr.ph.preheader:                                 ; preds = %12
  %16 = zext i32 %15 to i64
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %26
  %17 = phi i64 [ %30, %26 ], [ %16, %.lr.ph.preheader ]
  %18 = phi i64 [ %29, %26 ], [ 0, %.lr.ph.preheader ]
  %19 = add nuw nsw i64 %17, %18
  %20 = lshr i64 %19, 1
  %21 = shl nuw nsw i64 %20, 4
  %22 = getelementptr i8, ptr %14, i64 %21
  %23 = getelementptr i8, ptr %22, i64 16
  %24 = load i32, ptr %23, align 4
  %25 = icmp eq i32 %24, 5
  br i1 %25, label %common.ret, label %26

26:                                               ; preds = %.lr.ph
  %27 = icmp ult i32 %24, 5
  %28 = add nuw nsw i64 %20, 1
  %29 = select i1 %27, i64 %28, i64 %18
  %30 = select i1 %27, i64 %17, i64 %20
  %31 = icmp ult i64 %29, %30
  br i1 %31, label %.lr.ph, label %common.ret

32:                                               ; preds = %5
  %33 = load i8, ptr %6, align 1
  %34 = icmp ult i8 %33, 3
  br i1 %34, label %common.ret, label %35

35:                                               ; preds = %32
  %36 = add i8 %33, -11
  %37 = icmp ult i8 %36, 3
  br i1 %37, label %common.ret, label %.thread.thread
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i32, ptr %2, align 4
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  switch i32 %3, label %scalar.exit [
    i32 0, label %9
    i32 3, label %7
    i32 4, label %9
  ]

common.ret.fold.split.i:                          ; preds = %16
  br label %scalar.exit

7:                                                ; preds = %1
  %.pre.i = load ptr, ptr %6, align 8
  %8 = icmp eq ptr %.pre.i, null
  br i1 %8, label %scalar.exit, label %.thread.i

9:                                                ; preds = %1, %1
  %10 = load ptr, ptr %6, align 8
  %11 = icmp eq ptr %10, null
  br i1 %11, label %scalar.exit, label %36

.thread.i:                                        ; preds = %7
  %.pr.i = load i8, ptr %.pre.i, align 1
  %12 = icmp ult i8 %.pr.i, 3
  br i1 %12, label %scalar.exit, label %.thread.thread.i

.thread.thread.i:                                 ; preds = %39, %.thread.i
  %13 = phi ptr [ %.pre.i, %.thread.i ], [ %10, %39 ]
  %14 = phi i8 [ %.pr.i, %.thread.i ], [ %37, %39 ]
  %15 = icmp eq i8 %14, 9
  br i1 %15, label %16, label %scalar.exit

16:                                               ; preds = %.thread.thread.i
  %17 = getelementptr i8, ptr %13, i64 8
  %18 = load ptr, ptr %17, align 8
  %19 = load i32, ptr %18, align 4
  switch i32 %19, label %.lr.ph.preheader.i [
    i32 -1, label %scalar.exit
    i32 0, label %common.ret.fold.split.i
  ]

.lr.ph.preheader.i:                               ; preds = %16
  %20 = zext i32 %19 to i64
  br label %.lr.ph.i

.lr.ph.i:                                         ; preds = %30, %.lr.ph.preheader.i
  %21 = phi i64 [ %34, %30 ], [ %20, %.lr.ph.preheader.i ]
  %22 = phi i64 [ %33, %30 ], [ 0, %.lr.ph.preheader.i ]
  %23 = add nuw nsw i64 %22, %21
  %24 = lshr i64 %23, 1
  %25 = shl nuw nsw i64 %24, 4
  %26 = getelementptr i8, ptr %18, i64 %25
  %27 = getelementptr i8, ptr %26, i64 16
  %28 = load i32, ptr %27, align 4
  %29 = icmp eq i32 %28, 5
  br i1 %29, label %scalar.exit, label %30

30:                                               ; preds = %.lr.ph.i
  %31 = icmp ult i32 %28, 5
  %32 = add nuw nsw i64 %24, 1
  %33 = select i1 %31, i64 %32, i64 %22
  %34 = select i1 %31, i64 %21, i64 %24
  %35 = icmp ult i64 %33, %34
  br i1 %35, label %.lr.ph.i, label %scalar.exit

36:                                               ; preds = %9
  %37 = load i8, ptr %10, align 1
  %38 = icmp ult i8 %37, 3
  br i1 %38, label %scalar.exit, label %39

39:                                               ; preds = %36
  %40 = add i8 %37, -11
  %41 = icmp ult i8 %40, 3
  br i1 %41, label %scalar.exit, label %.thread.thread.i

scalar.exit:                                      ; preds = %.lr.ph.i, %30, %1, %common.ret.fold.split.i, %7, %9, %.thread.i, %.thread.thread.i, %16, %36, %39
  %common.ret.op.i = phi i64 [ 26, %7 ], [ 0, %.thread.thread.i ], [ 1, %39 ], [ 3, %16 ], [ 4, %1 ], [ 34, %36 ], [ 34, %9 ], [ 26, %.thread.i ], [ 0, %common.ret.fold.split.i ], [ 0, %30 ], [ 3, %.lr.ph.i ]
  %42 = getelementptr i8, ptr %0, i64 16
  %43 = load ptr, ptr %42, align 8
  store i64 %common.ret.op.i, ptr %43, align 8
  ret void
}

attributes #0 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem: none) }
attributes #1 = { nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
