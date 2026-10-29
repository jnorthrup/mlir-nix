; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 72) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %34 [
    i32 0, label %31
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %13
    i32 6, label %21
    i32 7, label %25
    i32 8, label %29
    i32 9, label %31
  ]

common.ret:                                       ; preds = %.thread, %78, %60, %63, %31, %29, %52, %25, %44, %21, %39, %2, %35, %34, %4, %3
  %common.ret.op = phi i64 [ 71, %60 ], [ 1, %3 ], [ 3, %4 ], [ 4, %34 ], [ 0, %2 ], [ 42, %21 ], [ 50, %25 ], [ 58, %29 ], [ 66, %31 ], [ 0, %35 ], [ 42, %39 ], [ 50, %44 ], [ 58, %52 ], [ 71, %63 ], [ 69, %78 ], [ 58, %.thread ]
  ret i64 %common.ret.op

3:                                                ; preds = %37, %2
  br label %common.ret

4:                                                ; preds = %47, %55, %2
  br label %common.ret

5:                                                ; preds = %42, %49, %2
  %6 = getelementptr i8, ptr %1, i64 712
  %7 = load i32, ptr %6, align 4
  %8 = getelementptr i8, ptr %1, i64 716
  %9 = load i32, ptr %8, align 4
  %10 = icmp eq i32 %7, 1
  %11 = icmp eq i32 %9, 1
  %12 = and i1 %10, %11
  br i1 %12, label %35, label %34

13:                                               ; preds = %42, %49, %2
  %14 = getelementptr i8, ptr %1, i64 712
  %15 = load i32, ptr %14, align 4
  %16 = getelementptr i8, ptr %1, i64 716
  %17 = load i32, ptr %16, align 4
  %18 = icmp eq i32 %15, 1
  %19 = icmp eq i32 %17, 1
  %20 = and i1 %18, %19
  br i1 %20, label %37, label %34

21:                                               ; preds = %57, %2
  %22 = getelementptr i8, ptr %1, i64 24
  %23 = load ptr, ptr %22, align 8
  %24 = icmp eq ptr %23, null
  br i1 %24, label %common.ret, label %39

25:                                               ; preds = %57, %2
  %26 = getelementptr i8, ptr %1, i64 40
  %27 = load ptr, ptr %26, align 8
  %28 = icmp eq ptr %27, null
  br i1 %28, label %common.ret, label %44

29:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 32
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %30 = icmp eq ptr %.pre, null
  br i1 %30, label %common.ret, label %52

31:                                               ; preds = %2, %2
  %32 = load ptr, ptr %1, align 8
  %33 = icmp eq ptr %32, null
  br i1 %33, label %common.ret, label %60

34:                                               ; preds = %5, %13, %67, %2
  br label %common.ret

35:                                               ; preds = %5
  %36 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %36, align 1
  store i32 0, ptr %8, align 4
  store i32 0, ptr %6, align 4
  br label %common.ret

37:                                               ; preds = %13
  %38 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %38, align 1
  store i32 0, ptr %16, align 4
  store i32 0, ptr %14, align 4
  br label %3

39:                                               ; preds = %21
  %40 = load i8, ptr %23, align 1
  %41 = icmp ult i8 %40, 3
  br i1 %41, label %common.ret, label %42

42:                                               ; preds = %39
  %43 = icmp eq i8 %40, 5
  br i1 %43, label %5, label %13

44:                                               ; preds = %25
  %45 = load i8, ptr %27, align 1
  %46 = icmp ult i8 %45, 3
  br i1 %46, label %common.ret, label %47

47:                                               ; preds = %44
  %48 = icmp eq i8 %45, 5
  br i1 %48, label %49, label %4

49:                                               ; preds = %47
  %50 = getelementptr i8, ptr %27, i64 8
  %51 = load i8, ptr %50, align 1
  %.not9 = icmp eq i8 %51, 0
  br i1 %.not9, label %13, label %5

52:                                               ; preds = %29
  %53 = load i8, ptr %.pre, align 1
  %54 = icmp ult i8 %53, 3
  br i1 %54, label %common.ret, label %55

55:                                               ; preds = %52
  %56 = icmp eq i8 %53, 5
  br i1 %56, label %57, label %4

57:                                               ; preds = %55
  %58 = getelementptr i8, ptr %.pre, i64 8
  %59 = load i8, ptr %58, align 1
  %.not8 = icmp eq i8 %59, 0
  br i1 %.not8, label %25, label %21

60:                                               ; preds = %31
  %61 = load i8, ptr %32, align 1
  %62 = icmp eq i8 %61, 11
  br i1 %62, label %63, label %common.ret

63:                                               ; preds = %60
  %64 = getelementptr i8, ptr %32, i64 8
  %65 = load ptr, ptr %64, align 8
  %66 = icmp eq ptr %65, inttoptr (i64 5710640768 to ptr)
  br i1 %66, label %67, label %common.ret

67:                                               ; preds = %63
  %68 = getelementptr i8, ptr %1, i64 712
  %69 = load i32, ptr %68, align 8
  %70 = getelementptr i8, ptr %1, i64 716
  %71 = load i32, ptr %70, align 4
  %72 = getelementptr i8, ptr %1, i64 640
  %73 = load i8, ptr %72, align 8
  %74 = or i32 %71, %69
  %75 = icmp eq i32 %74, 0
  %76 = icmp ne i8 %73, 0
  %77 = and i1 %75, %76
  br i1 %77, label %78, label %34

78:                                               ; preds = %67
  %79 = getelementptr i8, ptr %1, i64 704
  %80 = load i32, ptr %79, align 8
  %81 = getelementptr i8, ptr %1, i64 708
  %82 = load i32, ptr %81, align 4
  %.not = icmp ult i32 %80, %82
  br i1 %.not, label %.thread, label %common.ret

.thread:                                          ; preds = %78
  %83 = getelementptr i8, ptr %32, i64 16
  %84 = load ptr, ptr %83, align 8
  %85 = getelementptr i8, ptr %1, i64 136
  store ptr %84, ptr %85, align 8
  %86 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %86, align 1
  store i32 1, ptr %70, align 4
  store i32 1, ptr %68, align 8
  %87 = getelementptr i8, ptr %1, i64 720
  %88 = load i32, ptr %87, align 8
  %89 = add i32 %88, 1
  store i32 %89, ptr %87, align 8
  %90 = getelementptr i8, ptr %1, i64 724
  %91 = load i32, ptr %90, align 4
  %92 = add i32 %91, 1
  store i32 %92, ptr %90, align 4
  %93 = getelementptr i8, ptr %1, i64 32
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %93, i8 0, i64 16, i1 false)
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

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #2

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }
attributes #2 = { nocallback nofree nosync nounwind willreturn memory(argmem: write) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
