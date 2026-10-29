; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: nofree norecurse nosync nounwind memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 75) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %36 [
    i32 0, label %33
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %.loopexit16
    i32 4, label %4
    i32 5, label %8
    i32 6, label %.loopexit
    i32 7, label %23
    i32 8, label %25
    i32 9, label %29
    i32 10, label %33
  ]

common.ret:                                       ; preds = %33, %110, %97, %79, %82, %29, %25, %73, %23, %.thread, %4, %37, %2, %45, %42, %36, %.loopexit16, %3
  %common.ret.op = phi i64 [ 69, %97 ], [ 1, %3 ], [ 3, %.loopexit16 ], [ 4, %36 ], [ 0, %2 ], [ 26, %4 ], [ 50, %23 ], [ 58, %25 ], [ 66, %29 ], [ 71, %79 ], [ 0, %42 ], [ 0, %45 ], [ 26, %37 ], [ 50, %.thread ], [ 58, %73 ], [ 71, %82 ], [ 74, %110 ], [ 74, %33 ]
  ret i64 %common.ret.op

3:                                                ; preds = %42, %47, %2
  br label %common.ret

.loopexit16:                                      ; preds = %.lr.ph, %53, %40, %113, %2
  br label %common.ret

4:                                                ; preds = %115, %2
  %5 = getelementptr i8, ptr %1, i64 8
  %6 = load ptr, ptr %5, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %common.ret, label %37

8:                                                ; preds = %76, %2
  %9 = getelementptr i8, ptr %1, i64 712
  %10 = load i32, ptr %9, align 4
  %11 = getelementptr i8, ptr %1, i64 716
  %12 = load i32, ptr %11, align 4
  %13 = icmp eq i32 %10, 1
  %14 = icmp eq i32 %12, 1
  %15 = and i1 %13, %14
  br i1 %15, label %45, label %36

.loopexit:                                        ; preds = %67, %53, %.thread.thread, %2
  %16 = getelementptr i8, ptr %1, i64 712
  %17 = load i32, ptr %16, align 4
  %18 = getelementptr i8, ptr %1, i64 716
  %19 = load i32, ptr %18, align 4
  %20 = icmp eq i32 %17, 1
  %21 = icmp eq i32 %19, 1
  %22 = and i1 %20, %21
  br i1 %22, label %47, label %36

23:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 24
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %24 = icmp eq ptr %.pre, null
  br i1 %24, label %common.ret, label %.thread

25:                                               ; preds = %102, %2
  %26 = getelementptr i8, ptr %1, i64 24
  %27 = load ptr, ptr %26, align 8
  %28 = icmp eq ptr %27, null
  br i1 %28, label %common.ret, label %73

29:                                               ; preds = %115, %2
  %30 = getelementptr i8, ptr %1, i64 16
  %31 = load ptr, ptr %30, align 8
  %32 = icmp eq ptr %31, null
  br i1 %32, label %common.ret, label %79

33:                                               ; preds = %2, %2
  %34 = load ptr, ptr %1, align 8
  %35 = icmp eq ptr %34, null
  br i1 %35, label %common.ret, label %110

36:                                               ; preds = %8, %.loopexit, %86, %2
  br label %common.ret

37:                                               ; preds = %4
  %38 = load i8, ptr %6, align 1
  %39 = icmp ult i8 %38, 3
  br i1 %39, label %common.ret, label %40

40:                                               ; preds = %37
  %41 = icmp eq i8 %38, 5
  br i1 %41, label %42, label %.loopexit16

42:                                               ; preds = %40
  %43 = getelementptr i8, ptr %6, i64 8
  %44 = load i8, ptr %43, align 1
  %.not15 = icmp eq i8 %44, 0
  br i1 %.not15, label %3, label %common.ret

45:                                               ; preds = %8
  %46 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %46, align 1
  store i32 0, ptr %11, align 4
  store i32 0, ptr %9, align 4
  br label %common.ret

47:                                               ; preds = %.loopexit
  %48 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %48, align 1
  store i32 0, ptr %18, align 4
  store i32 0, ptr %16, align 4
  br label %3

.thread:                                          ; preds = %23
  %.pr = load i8, ptr %.pre, align 1
  %49 = icmp ult i8 %.pr, 3
  br i1 %49, label %common.ret, label %.thread.thread

.thread.thread:                                   ; preds = %76, %.thread
  %50 = phi ptr [ %.pre, %.thread ], [ %27, %76 ]
  %51 = phi i8 [ %.pr, %.thread ], [ %74, %76 ]
  %52 = icmp eq i8 %51, 9
  br i1 %52, label %53, label %.loopexit

53:                                               ; preds = %.thread.thread
  %54 = getelementptr i8, ptr %50, i64 8
  %55 = load ptr, ptr %54, align 8
  %56 = load i32, ptr %55, align 4
  switch i32 %56, label %.lr.ph.preheader [
    i32 -1, label %.loopexit16
    i32 0, label %.loopexit
  ]

.lr.ph.preheader:                                 ; preds = %53
  %57 = zext i32 %56 to i64
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %67
  %58 = phi i64 [ %71, %67 ], [ %57, %.lr.ph.preheader ]
  %59 = phi i64 [ %70, %67 ], [ 0, %.lr.ph.preheader ]
  %60 = add nuw nsw i64 %58, %59
  %61 = lshr i64 %60, 1
  %62 = shl nuw nsw i64 %61, 4
  %63 = getelementptr i8, ptr %55, i64 %62
  %64 = getelementptr i8, ptr %63, i64 16
  %65 = load i32, ptr %64, align 4
  %66 = icmp eq i32 %65, 5
  br i1 %66, label %.loopexit16, label %67

67:                                               ; preds = %.lr.ph
  %68 = icmp ult i32 %65, 5
  %69 = add nuw nsw i64 %61, 1
  %70 = select i1 %68, i64 %69, i64 %59
  %71 = select i1 %68, i64 %58, i64 %61
  %72 = icmp ult i64 %70, %71
  br i1 %72, label %.lr.ph, label %.loopexit

73:                                               ; preds = %25
  %74 = load i8, ptr %27, align 1
  %75 = icmp ult i8 %74, 3
  br i1 %75, label %common.ret, label %76

76:                                               ; preds = %73
  %77 = add i8 %74, -11
  %78 = icmp ult i8 %77, 3
  br i1 %78, label %8, label %.thread.thread

79:                                               ; preds = %29
  %80 = load i8, ptr %31, align 1
  %81 = icmp eq i8 %80, 11
  br i1 %81, label %82, label %common.ret

82:                                               ; preds = %79
  %83 = getelementptr i8, ptr %31, i64 8
  %84 = load ptr, ptr %83, align 8
  %85 = icmp eq ptr %84, inttoptr (i64 5366731072 to ptr)
  br i1 %85, label %86, label %common.ret

86:                                               ; preds = %82
  %87 = getelementptr i8, ptr %1, i64 712
  %88 = load i32, ptr %87, align 8
  %89 = getelementptr i8, ptr %1, i64 716
  %90 = load i32, ptr %89, align 4
  %91 = getelementptr i8, ptr %1, i64 640
  %92 = load i8, ptr %91, align 8
  %93 = or i32 %90, %88
  %94 = icmp eq i32 %93, 0
  %95 = icmp ne i8 %92, 0
  %96 = and i1 %94, %95
  br i1 %96, label %97, label %36

97:                                               ; preds = %86
  %98 = getelementptr i8, ptr %1, i64 704
  %99 = load i32, ptr %98, align 8
  %100 = getelementptr i8, ptr %1, i64 708
  %101 = load i32, ptr %100, align 4
  %.not14 = icmp ult i32 %99, %101
  br i1 %.not14, label %102, label %common.ret

102:                                              ; preds = %97
  %103 = getelementptr i8, ptr %31, i64 16
  %104 = load ptr, ptr %103, align 8
  %105 = getelementptr i8, ptr %1, i64 136
  store ptr %104, ptr %105, align 8
  %106 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %106, align 1
  store i32 1, ptr %89, align 4
  store i32 1, ptr %87, align 8
  %107 = getelementptr i8, ptr %1, i64 720
  %108 = load i32, ptr %107, align 8
  %109 = add i32 %108, 1
  store i32 %109, ptr %107, align 8
  br label %25

110:                                              ; preds = %33
  %111 = load i8, ptr %34, align 1
  %112 = icmp ult i8 %111, 3
  br i1 %112, label %common.ret, label %113

113:                                              ; preds = %110
  %114 = icmp eq i8 %111, 5
  br i1 %114, label %115, label %.loopexit16

115:                                              ; preds = %113
  %116 = getelementptr i8, ptr %34, i64 8
  %117 = load i8, ptr %116, align 1
  %.not = icmp eq i8 %117, 0
  br i1 %.not, label %29, label %4
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
