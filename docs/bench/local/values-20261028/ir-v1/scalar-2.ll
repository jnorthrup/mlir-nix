; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 80) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %39 [
    i32 0, label %36
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %13
    i32 6, label %22
    i32 7, label %30
    i32 8, label %.sink.split
    i32 9, label %34
    i32 10, label %36
  ]

common.ret:                                       ; preds = %.thread, %75, %57, %60, %36, %34, %49, %30, %46, %2, %42, %44, %39, %4, %3
  %common.ret.op = phi i64 [ 79, %57 ], [ 1, %3 ], [ 3, %4 ], [ 4, %39 ], [ 6, %44 ], [ 0, %2 ], [ 50, %30 ], [ 66, %34 ], [ 74, %36 ], [ 0, %42 ], [ 50, %46 ], [ 66, %49 ], [ 79, %60 ], [ 77, %75 ], [ 66, %.thread ]
  ret i64 %common.ret.op

3:                                                ; preds = %40, %2
  br label %common.ret

4:                                                ; preds = %52, %2
  br label %common.ret

5:                                                ; preds = %2
  %6 = getelementptr i8, ptr %1, i64 712
  %7 = load i32, ptr %6, align 4
  %8 = getelementptr i8, ptr %1, i64 716
  %9 = load i32, ptr %8, align 4
  %10 = icmp eq i32 %7, 1
  %11 = icmp eq i32 %9, 1
  %12 = and i1 %10, %11
  br i1 %12, label %40, label %39

13:                                               ; preds = %2
  %14 = getelementptr i8, ptr %1, i64 712
  %15 = load i32, ptr %14, align 4
  %16 = getelementptr i8, ptr %1, i64 716
  %17 = load i32, ptr %16, align 4
  %18 = icmp eq i32 %15, 1
  %19 = icmp eq i32 %17, 1
  %20 = and i1 %18, %19
  br i1 %20, label %42, label %39

.sink.split:                                      ; preds = %46, %2, %54
  %.sink = phi i32 [ 18, %2 ], [ 18, %54 ], [ 3, %46 ]
  %21 = getelementptr i8, ptr %1, i64 728
  store i32 %.sink, ptr %21, align 4
  br label %22

22:                                               ; preds = %.sink.split, %2
  %23 = getelementptr i8, ptr %1, i64 712
  %24 = load i32, ptr %23, align 4
  %25 = getelementptr i8, ptr %1, i64 716
  %26 = load i32, ptr %25, align 4
  %27 = icmp eq i32 %24, 1
  %28 = icmp eq i32 %26, 1
  %29 = and i1 %27, %28
  br i1 %29, label %44, label %39

30:                                               ; preds = %54, %2
  %31 = getelementptr i8, ptr %1, i64 24
  %32 = load ptr, ptr %31, align 8
  %33 = icmp eq ptr %32, null
  br i1 %33, label %common.ret, label %46

34:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 16
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %35 = icmp eq ptr %.pre, null
  br i1 %35, label %common.ret, label %49

36:                                               ; preds = %2, %2
  %37 = load ptr, ptr %1, align 8
  %38 = icmp eq ptr %37, null
  br i1 %38, label %common.ret, label %57

39:                                               ; preds = %22, %64, %5, %13, %2
  br label %common.ret

40:                                               ; preds = %5
  %41 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %41, align 1
  store i32 0, ptr %8, align 4
  store i32 0, ptr %6, align 4
  br label %3

42:                                               ; preds = %13
  %43 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %43, align 1
  store i32 0, ptr %16, align 4
  store i32 0, ptr %14, align 4
  br label %common.ret

44:                                               ; preds = %22
  %45 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %45, align 1
  store i32 0, ptr %25, align 4
  store i32 0, ptr %23, align 4
  br label %common.ret

46:                                               ; preds = %30
  %47 = load i8, ptr %32, align 1
  %48 = icmp ult i8 %47, 3
  br i1 %48, label %common.ret, label %.sink.split

49:                                               ; preds = %34
  %50 = load i8, ptr %.pre, align 1
  %51 = icmp ult i8 %50, 3
  br i1 %51, label %common.ret, label %52

52:                                               ; preds = %49
  %53 = icmp eq i8 %50, 5
  br i1 %53, label %54, label %4

54:                                               ; preds = %52
  %55 = getelementptr i8, ptr %.pre, i64 8
  %56 = load i8, ptr %55, align 1
  %.not5 = icmp eq i8 %56, 0
  br i1 %.not5, label %.sink.split, label %30

57:                                               ; preds = %36
  %58 = load i8, ptr %37, align 1
  %59 = icmp eq i8 %58, 11
  br i1 %59, label %60, label %common.ret

60:                                               ; preds = %57
  %61 = getelementptr i8, ptr %37, i64 8
  %62 = load ptr, ptr %61, align 8
  %63 = icmp eq ptr %62, inttoptr (i64 5685503168 to ptr)
  br i1 %63, label %64, label %common.ret

64:                                               ; preds = %60
  %65 = getelementptr i8, ptr %1, i64 712
  %66 = load i32, ptr %65, align 8
  %67 = getelementptr i8, ptr %1, i64 716
  %68 = load i32, ptr %67, align 4
  %69 = getelementptr i8, ptr %1, i64 640
  %70 = load i8, ptr %69, align 8
  %71 = or i32 %68, %66
  %72 = icmp eq i32 %71, 0
  %73 = icmp ne i8 %70, 0
  %74 = and i1 %72, %73
  br i1 %74, label %75, label %39

75:                                               ; preds = %64
  %76 = getelementptr i8, ptr %1, i64 704
  %77 = load i32, ptr %76, align 8
  %78 = getelementptr i8, ptr %1, i64 708
  %79 = load i32, ptr %78, align 4
  %.not = icmp ult i32 %77, %79
  br i1 %.not, label %.thread, label %common.ret

.thread:                                          ; preds = %75
  %80 = getelementptr i8, ptr %37, i64 16
  %81 = load ptr, ptr %80, align 8
  %82 = getelementptr i8, ptr %1, i64 136
  store ptr %81, ptr %82, align 8
  %83 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %83, align 1
  store i32 1, ptr %67, align 4
  store i32 1, ptr %65, align 8
  %84 = getelementptr i8, ptr %1, i64 720
  %85 = load i32, ptr %84, align 8
  %86 = add i32 %85, 1
  store i32 %86, ptr %84, align 8
  %87 = getelementptr i8, ptr %1, i64 16
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %87, i8 0, i64 16, i1 false)
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
