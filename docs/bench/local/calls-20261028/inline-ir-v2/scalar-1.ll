; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: nofree norecurse nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 64) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %28 [
    i32 0, label %25
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %.loopexit10
    i32 4, label %4
    i32 5, label %.loopexit
    i32 6, label %19
    i32 7, label %21
    i32 8, label %25
  ]

common.ret:                                       ; preds = %81, %63, %66, %25, %21, %57, %19, %.thread, %2, %29, %28, %.loopexit10, %3
  %common.ret.op = phi i64 [ 63, %63 ], [ 1, %3 ], [ 3, %.loopexit10 ], [ 4, %28 ], [ 0, %2 ], [ 42, %19 ], [ 50, %21 ], [ 58, %25 ], [ 0, %29 ], [ 42, %.thread ], [ 50, %57 ], [ 63, %66 ], [ 61, %81 ]
  ret i64 %common.ret.op

3:                                                ; preds = %31, %2
  br label %common.ret

.loopexit10:                                      ; preds = %.lr.ph, %37, %2
  br label %common.ret

4:                                                ; preds = %60, %2
  %5 = getelementptr i8, ptr %1, i64 712
  %6 = load i32, ptr %5, align 4
  %7 = getelementptr i8, ptr %1, i64 716
  %8 = load i32, ptr %7, align 4
  %9 = icmp eq i32 %6, 1
  %10 = icmp eq i32 %8, 1
  %11 = and i1 %9, %10
  br i1 %11, label %29, label %28

.loopexit:                                        ; preds = %51, %37, %.thread.thread, %2
  %12 = getelementptr i8, ptr %1, i64 712
  %13 = load i32, ptr %12, align 4
  %14 = getelementptr i8, ptr %1, i64 716
  %15 = load i32, ptr %14, align 4
  %16 = icmp eq i32 %13, 1
  %17 = icmp eq i32 %15, 1
  %18 = and i1 %16, %17
  br i1 %18, label %31, label %28

19:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 8
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %20 = icmp eq ptr %.pre, null
  br i1 %20, label %common.ret, label %.thread

21:                                               ; preds = %86, %2
  %22 = getelementptr i8, ptr %1, i64 8
  %23 = load ptr, ptr %22, align 8
  %24 = icmp eq ptr %23, null
  br i1 %24, label %common.ret, label %57

25:                                               ; preds = %2, %2
  %26 = load ptr, ptr %1, align 8
  %27 = icmp eq ptr %26, null
  br i1 %27, label %common.ret, label %63

28:                                               ; preds = %4, %.loopexit, %70, %2
  br label %common.ret

29:                                               ; preds = %4
  %30 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %30, align 1
  store i32 0, ptr %7, align 4
  store i32 0, ptr %5, align 4
  br label %common.ret

31:                                               ; preds = %.loopexit
  %32 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %32, align 1
  store i32 0, ptr %14, align 4
  store i32 0, ptr %12, align 4
  br label %3

.thread:                                          ; preds = %19
  %.pr = load i8, ptr %.pre, align 1
  %33 = icmp ult i8 %.pr, 3
  br i1 %33, label %common.ret, label %.thread.thread

.thread.thread:                                   ; preds = %60, %.thread
  %34 = phi ptr [ %.pre, %.thread ], [ %23, %60 ]
  %35 = phi i8 [ %.pr, %.thread ], [ %58, %60 ]
  %36 = icmp eq i8 %35, 9
  br i1 %36, label %37, label %.loopexit

37:                                               ; preds = %.thread.thread
  %38 = getelementptr i8, ptr %34, i64 8
  %39 = load ptr, ptr %38, align 8
  %40 = load i32, ptr %39, align 4
  switch i32 %40, label %.lr.ph.preheader [
    i32 -1, label %.loopexit10
    i32 0, label %.loopexit
  ]

.lr.ph.preheader:                                 ; preds = %37
  %41 = zext i32 %40 to i64
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %51
  %42 = phi i64 [ %55, %51 ], [ %41, %.lr.ph.preheader ]
  %43 = phi i64 [ %54, %51 ], [ 0, %.lr.ph.preheader ]
  %44 = add nuw nsw i64 %42, %43
  %45 = lshr i64 %44, 1
  %46 = shl nuw nsw i64 %45, 4
  %47 = getelementptr i8, ptr %39, i64 %46
  %48 = getelementptr i8, ptr %47, i64 16
  %49 = load i32, ptr %48, align 4
  %50 = icmp eq i32 %49, 5
  br i1 %50, label %.loopexit10, label %51

51:                                               ; preds = %.lr.ph
  %52 = icmp ult i32 %49, 5
  %53 = add nuw nsw i64 %45, 1
  %54 = select i1 %52, i64 %53, i64 %43
  %55 = select i1 %52, i64 %42, i64 %45
  %56 = icmp ult i64 %54, %55
  br i1 %56, label %.lr.ph, label %.loopexit

57:                                               ; preds = %21
  %58 = load i8, ptr %23, align 1
  %59 = icmp ult i8 %58, 3
  br i1 %59, label %common.ret, label %60

60:                                               ; preds = %57
  %61 = add i8 %58, -11
  %62 = icmp ult i8 %61, 3
  br i1 %62, label %4, label %.thread.thread

63:                                               ; preds = %25
  %64 = load i8, ptr %26, align 1
  %65 = icmp eq i8 %64, 11
  br i1 %65, label %66, label %common.ret

66:                                               ; preds = %63
  %67 = getelementptr i8, ptr %26, i64 8
  %68 = load ptr, ptr %67, align 8
  %69 = icmp eq ptr %68, inttoptr (i64 5660331984 to ptr)
  br i1 %69, label %70, label %common.ret

70:                                               ; preds = %66
  %71 = getelementptr i8, ptr %1, i64 712
  %72 = load i32, ptr %71, align 8
  %73 = getelementptr i8, ptr %1, i64 716
  %74 = load i32, ptr %73, align 4
  %75 = getelementptr i8, ptr %1, i64 640
  %76 = load i8, ptr %75, align 8
  %77 = or i32 %74, %72
  %78 = icmp eq i32 %77, 0
  %79 = icmp ne i8 %76, 0
  %80 = and i1 %78, %79
  br i1 %80, label %81, label %28

81:                                               ; preds = %70
  %82 = getelementptr i8, ptr %1, i64 704
  %83 = load i32, ptr %82, align 8
  %84 = getelementptr i8, ptr %1, i64 708
  %85 = load i32, ptr %84, align 4
  %.not = icmp ult i32 %83, %85
  br i1 %.not, label %86, label %common.ret

86:                                               ; preds = %81
  %87 = getelementptr i8, ptr %26, i64 16
  %88 = load ptr, ptr %87, align 8
  %89 = getelementptr i8, ptr %1, i64 136
  store ptr %88, ptr %89, align 8
  %90 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %90, align 1
  store i32 1, ptr %73, align 4
  store i32 1, ptr %71, align 8
  %91 = getelementptr i8, ptr %1, i64 720
  %92 = load i32, ptr %91, align 8
  %93 = add i32 %92, 1
  store i32 %93, ptr %91, align 8
  br label %21
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

attributes #0 = { nofree norecurse nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none) }
attributes #1 = { nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
