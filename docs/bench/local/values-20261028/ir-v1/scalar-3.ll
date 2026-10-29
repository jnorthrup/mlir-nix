; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 112) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %55 [
    i32 0, label %52
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %9
    i32 6, label %13
    i32 7, label %17
    i32 8, label %25
    i32 9, label %34
    i32 10, label %42
    i32 11, label %.sink.split
    i32 12, label %46
    i32 13, label %48
    i32 14, label %52
  ]

common.ret:                                       ; preds = %.thread33, %135, %117, %120, %52, %101, %82, %85, %48, %46, %74, %42, %71, %2, %60, %64, %55, %4, %3
  %common.ret.op = phi i64 [ 111, %117 ], [ 1, %3 ], [ 3, %4 ], [ 4, %55 ], [ 6, %64 ], [ 0, %2 ], [ 74, %42 ], [ 90, %46 ], [ 98, %48 ], [ 103, %82 ], [ 101, %101 ], [ 106, %52 ], [ 0, %60 ], [ 74, %71 ], [ 90, %74 ], [ 103, %85 ], [ 111, %120 ], [ 109, %135 ], [ 90, %.thread33 ]
  ret i64 %common.ret.op

3:                                                ; preds = %56, %2
  br label %common.ret

4:                                                ; preds = %77, %2
  br label %common.ret

5:                                                ; preds = %2
  %.phi.trans.insert15 = getelementptr i8, ptr %1, i64 712
  %.pre16 = load i32, ptr %.phi.trans.insert15, align 4
  %.phi.trans.insert17 = getelementptr i8, ptr %1, i64 716
  %.pre18 = load i32, ptr %.phi.trans.insert17, align 4
  %6 = icmp eq i32 %.pre16, 1
  %7 = icmp eq i32 %.pre18, 1
  %8 = and i1 %6, %7
  br i1 %8, label %56, label %55

9:                                                ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 712
  %.pre = load i32, ptr %.phi.trans.insert, align 4
  %.phi.trans.insert12 = getelementptr i8, ptr %1, i64 716
  %.pre13 = load i32, ptr %.phi.trans.insert12, align 4
  %10 = icmp eq i32 %.pre, 1
  %11 = icmp eq i32 %.pre13, 1
  %12 = and i1 %10, %11
  br i1 %12, label %60, label %55

13:                                               ; preds = %2
  %.phi.trans.insert23 = getelementptr i8, ptr %1, i64 712
  %.pre24 = load i32, ptr %.phi.trans.insert23, align 4
  %.phi.trans.insert25 = getelementptr i8, ptr %1, i64 716
  %.pre26 = load i32, ptr %.phi.trans.insert25, align 4
  %14 = icmp eq i32 %.pre24, 1
  %15 = icmp eq i32 %.pre26, 1
  %16 = and i1 %14, %15
  br i1 %16, label %64, label %55

17:                                               ; preds = %2
  %18 = getelementptr i8, ptr %1, i64 712
  %19 = load i32, ptr %18, align 4
  %20 = getelementptr i8, ptr %1, i64 716
  %21 = load i32, ptr %20, align 4
  %22 = icmp eq i32 %19, 2
  %23 = icmp eq i32 %21, 2
  %24 = and i1 %22, %23
  br i1 %24, label %.thread, label %55

25:                                               ; preds = %2
  %26 = getelementptr i8, ptr %1, i64 712
  %27 = load i32, ptr %26, align 4
  %28 = getelementptr i8, ptr %1, i64 716
  %29 = load i32, ptr %28, align 4
  %30 = icmp eq i32 %27, 2
  %31 = icmp eq i32 %29, 2
  %32 = and i1 %30, %31
  br i1 %32, label %.thread31, label %55

.sink.split:                                      ; preds = %71, %2, %79
  %.sink = phi i32 [ 18, %2 ], [ 18, %79 ], [ 4, %71 ]
  %33 = getelementptr i8, ptr %1, i64 728
  store i32 %.sink, ptr %33, align 4
  br label %34

34:                                               ; preds = %.sink.split, %2
  %35 = getelementptr i8, ptr %1, i64 712
  %36 = load i32, ptr %35, align 4
  %37 = getelementptr i8, ptr %1, i64 716
  %38 = load i32, ptr %37, align 4
  %39 = icmp eq i32 %36, 2
  %40 = icmp eq i32 %38, 2
  %41 = and i1 %39, %40
  br i1 %41, label %.thread32, label %55

42:                                               ; preds = %79, %2
  %43 = getelementptr i8, ptr %1, i64 32
  %44 = load ptr, ptr %43, align 8
  %45 = icmp eq ptr %44, null
  br i1 %45, label %common.ret, label %71

46:                                               ; preds = %2
  %.phi.trans.insert20 = getelementptr i8, ptr %1, i64 24
  %.pre21 = load ptr, ptr %.phi.trans.insert20, align 8
  %47 = icmp eq ptr %.pre21, null
  br i1 %47, label %common.ret, label %74

48:                                               ; preds = %140, %2
  %49 = getelementptr i8, ptr %1, i64 8
  %50 = load ptr, ptr %49, align 8
  %51 = icmp eq ptr %50, null
  br i1 %51, label %common.ret, label %82

52:                                               ; preds = %2, %2
  %53 = load ptr, ptr %1, align 8
  %54 = icmp eq ptr %53, null
  br i1 %54, label %common.ret, label %117

55:                                               ; preds = %13, %34, %89, %124, %5, %9, %17, %25, %2
  br label %common.ret

56:                                               ; preds = %.thread, %5
  %57 = getelementptr i8, ptr %1, i64 716
  %58 = getelementptr i8, ptr %1, i64 712
  %59 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %59, align 1
  store i32 0, ptr %57, align 4
  store i32 0, ptr %58, align 4
  br label %3

60:                                               ; preds = %.thread31, %9
  %61 = getelementptr i8, ptr %1, i64 716
  %62 = getelementptr i8, ptr %1, i64 712
  %63 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %63, align 1
  store i32 0, ptr %61, align 4
  store i32 0, ptr %62, align 4
  br label %common.ret

64:                                               ; preds = %.thread32, %13
  %65 = getelementptr i8, ptr %1, i64 716
  %66 = getelementptr i8, ptr %1, i64 712
  %67 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %67, align 1
  store i32 0, ptr %65, align 4
  store i32 0, ptr %66, align 4
  br label %common.ret

.thread:                                          ; preds = %17
  %68 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %68, align 2
  br label %56

.thread31:                                        ; preds = %25
  %69 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %69, align 2
  br label %60

.thread32:                                        ; preds = %34
  %70 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %70, align 2
  br label %64

71:                                               ; preds = %42
  %72 = load i8, ptr %44, align 1
  %73 = icmp ult i8 %72, 3
  br i1 %73, label %common.ret, label %.sink.split

74:                                               ; preds = %46
  %75 = load i8, ptr %.pre21, align 1
  %76 = icmp ult i8 %75, 3
  br i1 %76, label %common.ret, label %77

77:                                               ; preds = %74
  %78 = icmp eq i8 %75, 5
  br i1 %78, label %79, label %4

79:                                               ; preds = %77
  %80 = getelementptr i8, ptr %.pre21, i64 8
  %81 = load i8, ptr %80, align 1
  %.not11 = icmp eq i8 %81, 0
  br i1 %.not11, label %.sink.split, label %42

82:                                               ; preds = %48
  %83 = load i8, ptr %50, align 1
  %84 = icmp eq i8 %83, 11
  br i1 %84, label %85, label %common.ret

85:                                               ; preds = %82
  %86 = getelementptr i8, ptr %50, i64 8
  %87 = load ptr, ptr %86, align 8
  %88 = icmp eq ptr %87, inttoptr (i64 5685503168 to ptr)
  br i1 %88, label %89, label %common.ret

89:                                               ; preds = %85
  %90 = getelementptr i8, ptr %1, i64 712
  %91 = load i32, ptr %90, align 8
  %92 = getelementptr i8, ptr %1, i64 716
  %93 = load i32, ptr %92, align 4
  %94 = getelementptr i8, ptr %1, i64 641
  %95 = load i8, ptr %94, align 1
  %96 = icmp eq i32 %91, 1
  %97 = icmp eq i32 %93, 1
  %98 = and i1 %96, %97
  %99 = icmp ne i8 %95, 0
  %100 = and i1 %98, %99
  br i1 %100, label %101, label %55

101:                                              ; preds = %89
  %102 = getelementptr i8, ptr %1, i64 704
  %103 = load i32, ptr %102, align 8
  %104 = getelementptr i8, ptr %1, i64 708
  %105 = load i32, ptr %104, align 4
  %106 = zext i32 %103 to i64
  %107 = add nuw nsw i64 %106, 1
  %108 = zext i32 %105 to i64
  %.not10 = icmp samesign ult i64 %107, %108
  br i1 %.not10, label %.thread33, label %common.ret

.thread33:                                        ; preds = %101
  %109 = getelementptr i8, ptr %50, i64 16
  %110 = load ptr, ptr %109, align 8
  %111 = getelementptr i8, ptr %1, i64 144
  store ptr %110, ptr %111, align 8
  %112 = getelementptr i8, ptr %1, i64 642
  store i8 1, ptr %112, align 2
  store i32 2, ptr %92, align 4
  store i32 2, ptr %90, align 8
  %113 = getelementptr i8, ptr %1, i64 720
  %114 = load i32, ptr %113, align 8
  %115 = add i32 %114, 1
  store i32 %115, ptr %113, align 8
  %116 = getelementptr i8, ptr %1, i64 24
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %116, i8 0, i64 16, i1 false)
  br label %common.ret

117:                                              ; preds = %52
  %118 = load i8, ptr %53, align 1
  %119 = icmp eq i8 %118, 11
  br i1 %119, label %120, label %common.ret

120:                                              ; preds = %117
  %121 = getelementptr i8, ptr %53, i64 8
  %122 = load ptr, ptr %121, align 8
  %123 = icmp eq ptr %122, inttoptr (i64 5685531712 to ptr)
  br i1 %123, label %124, label %common.ret

124:                                              ; preds = %120
  %125 = getelementptr i8, ptr %1, i64 712
  %126 = load i32, ptr %125, align 8
  %127 = getelementptr i8, ptr %1, i64 716
  %128 = load i32, ptr %127, align 4
  %129 = getelementptr i8, ptr %1, i64 640
  %130 = load i8, ptr %129, align 8
  %131 = or i32 %128, %126
  %132 = icmp eq i32 %131, 0
  %133 = icmp ne i8 %130, 0
  %134 = and i1 %132, %133
  br i1 %134, label %135, label %55

135:                                              ; preds = %124
  %136 = getelementptr i8, ptr %1, i64 704
  %137 = load i32, ptr %136, align 8
  %138 = getelementptr i8, ptr %1, i64 708
  %139 = load i32, ptr %138, align 4
  %.not = icmp ult i32 %137, %139
  br i1 %.not, label %140, label %common.ret

140:                                              ; preds = %135
  %141 = getelementptr i8, ptr %53, i64 16
  %142 = load ptr, ptr %141, align 8
  %143 = getelementptr i8, ptr %1, i64 136
  store ptr %142, ptr %143, align 8
  %144 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %144, align 1
  store i32 1, ptr %127, align 4
  store i32 1, ptr %125, align 8
  %145 = getelementptr i8, ptr %1, i64 720
  %146 = load i32, ptr %145, align 8
  %147 = add i32 %146, 1
  store i32 %147, ptr %145, align 8
  %148 = getelementptr i8, ptr %1, i64 724
  %149 = load i32, ptr %148, align 4
  %150 = add i32 %149, 1
  store i32 %150, ptr %148, align 4
  br label %48
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
