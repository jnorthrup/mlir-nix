; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem: none)
define range(i64 0, 35) i64 @scalar(i32 %0, ptr nofree readonly captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %9 [
    i32 0, label %6
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %.loopexit
    i32 4, label %4
    i32 5, label %6
  ]

common.ret:                                       ; preds = %28, %14, %6, %34, %4, %.thread, %2, %.thread.thread, %9, %.loopexit, %3
  %common.ret.op = phi i64 [ 26, %4 ], [ 1, %3 ], [ 3, %.loopexit ], [ 4, %9 ], [ 0, %2 ], [ 34, %6 ], [ 0, %.thread.thread ], [ 26, %.thread ], [ 34, %34 ], [ 0, %14 ], [ 0, %28 ]
  ret i64 %common.ret.op

3:                                                ; preds = %37, %2
  br label %common.ret

.loopexit:                                        ; preds = %.lr.ph, %14, %2
  br label %common.ret

4:                                                ; preds = %2
  %.pre = load ptr, ptr %1, align 8
  %5 = icmp eq ptr %.pre, null
  br i1 %5, label %common.ret, label %.thread

6:                                                ; preds = %2, %2
  %7 = load ptr, ptr %1, align 8
  %8 = icmp eq ptr %7, null
  br i1 %8, label %common.ret, label %34

9:                                                ; preds = %2
  br label %common.ret

.thread:                                          ; preds = %4
  %.pr = load i8, ptr %.pre, align 1
  %10 = icmp ult i8 %.pr, 3
  br i1 %10, label %common.ret, label %.thread.thread

.thread.thread:                                   ; preds = %37, %.thread
  %11 = phi ptr [ %.pre, %.thread ], [ %7, %37 ]
  %12 = phi i8 [ %.pr, %.thread ], [ %35, %37 ]
  %13 = icmp eq i8 %12, 9
  br i1 %13, label %14, label %common.ret

14:                                               ; preds = %.thread.thread
  %15 = getelementptr i8, ptr %11, i64 8
  %16 = load ptr, ptr %15, align 8
  %17 = load i32, ptr %16, align 4
  switch i32 %17, label %.lr.ph.preheader [
    i32 -1, label %.loopexit
    i32 0, label %common.ret
  ]

.lr.ph.preheader:                                 ; preds = %14
  %18 = zext i32 %17 to i64
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %28
  %19 = phi i64 [ %32, %28 ], [ %18, %.lr.ph.preheader ]
  %20 = phi i64 [ %31, %28 ], [ 0, %.lr.ph.preheader ]
  %21 = add nuw nsw i64 %19, %20
  %22 = lshr i64 %21, 1
  %23 = shl nuw nsw i64 %22, 4
  %24 = getelementptr i8, ptr %16, i64 %23
  %25 = getelementptr i8, ptr %24, i64 16
  %26 = load i32, ptr %25, align 4
  %27 = icmp eq i32 %26, 5
  br i1 %27, label %.loopexit, label %28

28:                                               ; preds = %.lr.ph
  %29 = icmp ult i32 %26, 5
  %30 = add nuw nsw i64 %22, 1
  %31 = select i1 %29, i64 %30, i64 %20
  %32 = select i1 %29, i64 %19, i64 %22
  %33 = icmp ult i64 %31, %32
  br i1 %33, label %.lr.ph, label %common.ret

34:                                               ; preds = %6
  %35 = load i8, ptr %7, align 1
  %36 = icmp ult i8 %35, 3
  br i1 %36, label %common.ret, label %37

37:                                               ; preds = %34
  %38 = add i8 %35, -11
  %39 = icmp ult i8 %38, 3
  br i1 %39, label %3, label %.thread.thread
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i32, ptr %2, align 4
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  %7 = tail call i64 @scalar(i32 %3, ptr %6)
  %8 = getelementptr i8, ptr %0, i64 16
  %9 = load ptr, ptr %8, align 8
  store i64 %7, ptr %9, align 8
  ret void
}

attributes #0 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem: none) }
attributes #1 = { nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
