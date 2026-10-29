; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 80) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %43 [
    i32 0, label %40
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %13
    i32 6, label %22
    i32 7, label %30
    i32 8, label %34
    i32 9, label %38
    i32 10, label %40
  ]

common.ret:                                       ; preds = %.thread, %82, %64, %67, %40, %38, %56, %34, %53, %30, %50, %2, %46, %48, %43, %4, %3
  %common.ret.op = phi i64 [ 79, %64 ], [ 1, %3 ], [ 3, %4 ], [ 4, %43 ], [ 6, %48 ], [ 0, %2 ], [ 50, %30 ], [ 58, %34 ], [ 66, %38 ], [ 74, %40 ], [ 0, %46 ], [ 50, %50 ], [ 58, %53 ], [ 66, %56 ], [ 79, %67 ], [ 77, %82 ], [ 66, %.thread ]
  ret i64 %common.ret.op

3:                                                ; preds = %44, %2
  br label %common.ret

4:                                                ; preds = %59, %2
  br label %common.ret

5:                                                ; preds = %2
  %6 = getelementptr i8, ptr %1, i64 712
  %7 = load i32, ptr %6, align 4
  %8 = getelementptr i8, ptr %1, i64 716
  %9 = load i32, ptr %8, align 4
  %10 = icmp eq i32 %7, 1
  %11 = icmp eq i32 %9, 1
  %12 = and i1 %10, %11
  br i1 %12, label %44, label %43

13:                                               ; preds = %2
  %14 = getelementptr i8, ptr %1, i64 712
  %15 = load i32, ptr %14, align 4
  %16 = getelementptr i8, ptr %1, i64 716
  %17 = load i32, ptr %16, align 4
  %18 = icmp eq i32 %15, 1
  %19 = icmp eq i32 %17, 1
  %20 = and i1 %18, %19
  br i1 %20, label %46, label %43

.sink.split:                                      ; preds = %53, %50
  %.sink = phi i32 [ 3, %50 ], [ 4, %53 ]
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
  br i1 %29, label %48, label %43

30:                                               ; preds = %61, %2
  %31 = getelementptr i8, ptr %1, i64 24
  %32 = load ptr, ptr %31, align 8
  %33 = icmp eq ptr %32, null
  br i1 %33, label %common.ret, label %50

34:                                               ; preds = %61, %2
  %35 = getelementptr i8, ptr %1, i64 32
  %36 = load ptr, ptr %35, align 8
  %37 = icmp eq ptr %36, null
  br i1 %37, label %common.ret, label %53

38:                                               ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 16
  %.pre = load ptr, ptr %.phi.trans.insert, align 8
  %39 = icmp eq ptr %.pre, null
  br i1 %39, label %common.ret, label %56

40:                                               ; preds = %2, %2
  %41 = load ptr, ptr %1, align 8
  %42 = icmp eq ptr %41, null
  br i1 %42, label %common.ret, label %64

43:                                               ; preds = %22, %71, %5, %13, %2
  br label %common.ret

44:                                               ; preds = %5
  %45 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %45, align 1
  store i32 0, ptr %8, align 4
  store i32 0, ptr %6, align 4
  br label %3

46:                                               ; preds = %13
  %47 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %47, align 1
  store i32 0, ptr %16, align 4
  store i32 0, ptr %14, align 4
  br label %common.ret

48:                                               ; preds = %22
  %49 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %49, align 1
  store i32 0, ptr %25, align 4
  store i32 0, ptr %23, align 4
  br label %common.ret

50:                                               ; preds = %30
  %51 = load i8, ptr %32, align 1
  %52 = icmp ult i8 %51, 3
  br i1 %52, label %common.ret, label %.sink.split

53:                                               ; preds = %34
  %54 = load i8, ptr %36, align 1
  %55 = icmp ult i8 %54, 3
  br i1 %55, label %common.ret, label %.sink.split

56:                                               ; preds = %38
  %57 = load i8, ptr %.pre, align 1
  %58 = icmp ult i8 %57, 3
  br i1 %58, label %common.ret, label %59

59:                                               ; preds = %56
  %60 = icmp eq i8 %57, 5
  br i1 %60, label %61, label %4

61:                                               ; preds = %59
  %62 = getelementptr i8, ptr %.pre, i64 8
  %63 = load i8, ptr %62, align 1
  %.not6 = icmp eq i8 %63, 0
  br i1 %.not6, label %34, label %30

64:                                               ; preds = %40
  %65 = load i8, ptr %41, align 1
  %66 = icmp eq i8 %65, 11
  br i1 %66, label %67, label %common.ret

67:                                               ; preds = %64
  %68 = getelementptr i8, ptr %41, i64 8
  %69 = load ptr, ptr %68, align 8
  %70 = icmp eq ptr %69, inttoptr (i64 5417056880 to ptr)
  br i1 %70, label %71, label %common.ret

71:                                               ; preds = %67
  %72 = getelementptr i8, ptr %1, i64 712
  %73 = load i32, ptr %72, align 8
  %74 = getelementptr i8, ptr %1, i64 716
  %75 = load i32, ptr %74, align 4
  %76 = getelementptr i8, ptr %1, i64 640
  %77 = load i8, ptr %76, align 8
  %78 = or i32 %75, %73
  %79 = icmp eq i32 %78, 0
  %80 = icmp ne i8 %77, 0
  %81 = and i1 %79, %80
  br i1 %81, label %82, label %43

82:                                               ; preds = %71
  %83 = getelementptr i8, ptr %1, i64 704
  %84 = load i32, ptr %83, align 8
  %85 = getelementptr i8, ptr %1, i64 708
  %86 = load i32, ptr %85, align 4
  %.not = icmp ult i32 %84, %86
  br i1 %.not, label %.thread, label %common.ret

.thread:                                          ; preds = %82
  %87 = getelementptr i8, ptr %41, i64 16
  %88 = load ptr, ptr %87, align 8
  %89 = getelementptr i8, ptr %1, i64 136
  store ptr %88, ptr %89, align 8
  %90 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %90, align 1
  store i32 1, ptr %74, align 4
  store i32 1, ptr %72, align 8
  %91 = getelementptr i8, ptr %1, i64 720
  %92 = load i32, ptr %91, align 8
  %93 = add i32 %92, 1
  store i32 %93, ptr %91, align 8
  %94 = getelementptr i8, ptr %1, i64 16
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %94, i8 0, i64 24, i1 false)
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
