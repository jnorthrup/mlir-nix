; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 64) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %38 [
    i32 0, label %35
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %13
    i32 6, label %21
    i32 7, label %29
    i32 8, label %35
  ]

common.ret:                                       ; preds = %.thread, %65, %47, %50, %35, %29, %2, %41, %43, %38, %4, %3
  %common.ret.op = phi i64 [ 63, %47 ], [ 1, %3 ], [ 3, %4 ], [ 4, %38 ], [ 6, %43 ], [ 0, %2 ], [ 50, %29 ], [ 58, %35 ], [ 0, %41 ], [ 63, %50 ], [ 61, %65 ], [ 50, %.thread ]
  ret i64 %common.ret.op

3:                                                ; preds = %39, %2
  br label %common.ret

4:                                                ; preds = %2
  br label %common.ret

5:                                                ; preds = %2
  %6 = getelementptr i8, ptr %1, i64 712
  %7 = load i32, ptr %6, align 4
  %8 = getelementptr i8, ptr %1, i64 716
  %9 = load i32, ptr %8, align 4
  %10 = icmp eq i32 %7, 1
  %11 = icmp eq i32 %9, 1
  %12 = and i1 %10, %11
  br i1 %12, label %39, label %38

13:                                               ; preds = %2
  %14 = getelementptr i8, ptr %1, i64 712
  %15 = load i32, ptr %14, align 4
  %16 = getelementptr i8, ptr %1, i64 716
  %17 = load i32, ptr %16, align 4
  %18 = icmp eq i32 %15, 1
  %19 = icmp eq i32 %17, 1
  %20 = and i1 %18, %19
  br i1 %20, label %41, label %38

21:                                               ; preds = %45, %2
  %22 = getelementptr i8, ptr %1, i64 712
  %23 = load i32, ptr %22, align 4
  %24 = getelementptr i8, ptr %1, i64 716
  %25 = load i32, ptr %24, align 4
  %26 = icmp eq i32 %23, 1
  %27 = icmp eq i32 %25, 1
  %28 = and i1 %26, %27
  br i1 %28, label %43, label %38

29:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 16
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %30 = icmp ne ptr %.pre, null
  %31 = getelementptr i8, ptr %1, i64 8
  %32 = load ptr, ptr %31, align 8
  %33 = icmp ne ptr %32, null
  %34 = and i1 %30, %33
  br i1 %34, label %45, label %common.ret

35:                                               ; preds = %2, %2
  %36 = load ptr, ptr %1, align 8
  %37 = icmp eq ptr %36, null
  br i1 %37, label %common.ret, label %47

38:                                               ; preds = %21, %54, %5, %13, %2
  br label %common.ret

39:                                               ; preds = %5
  %40 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %40, align 1
  store i32 0, ptr %8, align 4
  store i32 0, ptr %6, align 4
  br label %3

41:                                               ; preds = %13
  %42 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %42, align 1
  store i32 0, ptr %16, align 4
  store i32 0, ptr %14, align 4
  br label %common.ret

43:                                               ; preds = %21
  %44 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %44, align 1
  store i32 0, ptr %24, align 4
  store i32 0, ptr %22, align 4
  br label %common.ret

45:                                               ; preds = %29
  %46 = getelementptr i8, ptr %1, i64 728
  store i32 20, ptr %46, align 8
  br label %21

47:                                               ; preds = %35
  %48 = load i8, ptr %36, align 1
  %49 = icmp eq i8 %48, 11
  br i1 %49, label %50, label %common.ret

50:                                               ; preds = %47
  %51 = getelementptr i8, ptr %36, i64 8
  %52 = load ptr, ptr %51, align 8
  %53 = icmp eq ptr %52, inttoptr (i64 5089913888 to ptr)
  br i1 %53, label %54, label %common.ret

54:                                               ; preds = %50
  %55 = getelementptr i8, ptr %1, i64 712
  %56 = load i32, ptr %55, align 8
  %57 = getelementptr i8, ptr %1, i64 716
  %58 = load i32, ptr %57, align 4
  %59 = getelementptr i8, ptr %1, i64 640
  %60 = load i8, ptr %59, align 8
  %61 = or i32 %58, %56
  %62 = icmp eq i32 %61, 0
  %63 = icmp ne i8 %60, 0
  %64 = and i1 %62, %63
  br i1 %64, label %65, label %38

65:                                               ; preds = %54
  %66 = getelementptr i8, ptr %1, i64 704
  %67 = load i32, ptr %66, align 8
  %68 = getelementptr i8, ptr %1, i64 708
  %69 = load i32, ptr %68, align 4
  %.not = icmp ult i32 %67, %69
  br i1 %.not, label %.thread, label %common.ret

.thread:                                          ; preds = %65
  %70 = getelementptr i8, ptr %36, i64 16
  %71 = load ptr, ptr %70, align 8
  %72 = getelementptr i8, ptr %1, i64 136
  store ptr %71, ptr %72, align 8
  %73 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %73, align 1
  store i32 1, ptr %57, align 4
  store i32 1, ptr %55, align 8
  %74 = getelementptr i8, ptr %1, i64 720
  %75 = load i32, ptr %74, align 8
  %76 = add i32 %75, 1
  store i32 %76, ptr %74, align 8
  %77 = getelementptr i8, ptr %1, i64 16
  store ptr null, ptr %77, align 8
  br label %common.ret
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
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

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
