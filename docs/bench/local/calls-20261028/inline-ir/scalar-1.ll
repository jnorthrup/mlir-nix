; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem: none)
define range(i64 0, 64) i64 @scalar(i32 %0, ptr nofree readonly captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %14 [
    i32 0, label %11
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %.loopexit9
    i32 4, label %4
    i32 5, label %.loopexit
    i32 6, label %5
    i32 7, label %7
    i32 8, label %11
  ]

common.ret:                                       ; preds = %48, %45, %11, %7, %39, %5, %.thread, %2, %14, %.loopexit, %4, %.loopexit9, %3
  %common.ret.op = phi i64 [ 63, %45 ], [ 1, %3 ], [ 3, %.loopexit9 ], [ 30, %4 ], [ 38, %.loopexit ], [ 4, %14 ], [ 0, %2 ], [ 42, %5 ], [ 50, %7 ], [ 58, %11 ], [ 42, %.thread ], [ 50, %39 ], [ %spec.select, %48 ]
  ret i64 %common.ret.op

3:                                                ; preds = %2
  br label %common.ret

.loopexit9:                                       ; preds = %.lr.ph, %19, %2
  br label %common.ret

4:                                                ; preds = %42, %2
  br label %common.ret

.loopexit:                                        ; preds = %33, %19, %.thread.thread, %2
  br label %common.ret

5:                                                ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 8
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %6 = icmp eq ptr %.pre, null
  br i1 %6, label %common.ret, label %.thread

7:                                                ; preds = %2
  %8 = getelementptr i8, ptr %1, i64 8
  %9 = load ptr, ptr %8, align 8
  %10 = icmp eq ptr %9, null
  br i1 %10, label %common.ret, label %39

11:                                               ; preds = %2, %2
  %12 = load ptr, ptr %1, align 8
  %13 = icmp eq ptr %12, null
  br i1 %13, label %common.ret, label %45

14:                                               ; preds = %2
  br label %common.ret

.thread:                                          ; preds = %5
  %.pr = load i8, ptr %.pre, align 1
  %15 = icmp ult i8 %.pr, 3
  br i1 %15, label %common.ret, label %.thread.thread

.thread.thread:                                   ; preds = %42, %.thread
  %16 = phi ptr [ %.pre, %.thread ], [ %9, %42 ]
  %17 = phi i8 [ %.pr, %.thread ], [ %40, %42 ]
  %18 = icmp eq i8 %17, 9
  br i1 %18, label %19, label %.loopexit

19:                                               ; preds = %.thread.thread
  %20 = getelementptr i8, ptr %16, i64 8
  %21 = load ptr, ptr %20, align 8
  %22 = load i32, ptr %21, align 4
  switch i32 %22, label %.lr.ph.preheader [
    i32 -1, label %.loopexit9
    i32 0, label %.loopexit
  ]

.lr.ph.preheader:                                 ; preds = %19
  %23 = zext i32 %22 to i64
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %33
  %24 = phi i64 [ %37, %33 ], [ %23, %.lr.ph.preheader ]
  %25 = phi i64 [ %36, %33 ], [ 0, %.lr.ph.preheader ]
  %26 = add nuw nsw i64 %24, %25
  %27 = lshr i64 %26, 1
  %28 = shl nuw nsw i64 %27, 4
  %29 = getelementptr i8, ptr %21, i64 %28
  %30 = getelementptr i8, ptr %29, i64 16
  %31 = load i32, ptr %30, align 4
  %32 = icmp eq i32 %31, 5
  br i1 %32, label %.loopexit9, label %33

33:                                               ; preds = %.lr.ph
  %34 = icmp ult i32 %31, 5
  %35 = add nuw nsw i64 %27, 1
  %36 = select i1 %34, i64 %35, i64 %25
  %37 = select i1 %34, i64 %24, i64 %27
  %38 = icmp ult i64 %36, %37
  br i1 %38, label %.lr.ph, label %.loopexit

39:                                               ; preds = %7
  %40 = load i8, ptr %9, align 1
  %41 = icmp ult i8 %40, 3
  br i1 %41, label %common.ret, label %42

42:                                               ; preds = %39
  %43 = add i8 %40, -11
  %44 = icmp ult i8 %43, 3
  br i1 %44, label %4, label %.thread.thread

45:                                               ; preds = %11
  %46 = load i8, ptr %12, align 1
  %47 = icmp eq i8 %46, 11
  br i1 %47, label %48, label %common.ret

48:                                               ; preds = %45
  %49 = getelementptr i8, ptr %12, i64 8
  %50 = load ptr, ptr %49, align 8
  %51 = icmp eq ptr %50, inttoptr (i64 5383500368 to ptr)
  %spec.select = select i1 %51, i64 61, i64 63
  br label %common.ret
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
