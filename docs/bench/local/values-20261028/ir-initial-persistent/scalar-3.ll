; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 112) i64 @scalar(i32 %0, ptr nofree %1) local_unnamed_addr #0 {
  switch i32 %0, label %59 [
    i32 0, label %56
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
    i32 11, label %46
    i32 12, label %50
    i32 13, label %52
    i32 14, label %56
  ]

common.ret:                                       ; preds = %.thread35, %142, %124, %127, %56, %108, %89, %92, %52, %50, %81, %46, %78, %42, %75, %2, %64, %68, %59, %4, %3
  %common.ret.op = phi i64 [ 111, %124 ], [ 1, %3 ], [ 3, %4 ], [ 4, %59 ], [ 6, %68 ], [ 0, %2 ], [ 74, %42 ], [ 82, %46 ], [ 90, %50 ], [ 98, %52 ], [ 103, %89 ], [ 101, %108 ], [ 106, %56 ], [ 0, %64 ], [ 74, %75 ], [ 82, %78 ], [ 90, %81 ], [ 103, %92 ], [ 111, %127 ], [ 109, %142 ], [ 90, %.thread35 ]
  ret i64 %common.ret.op

3:                                                ; preds = %60, %2
  br label %common.ret

4:                                                ; preds = %84, %2
  br label %common.ret

5:                                                ; preds = %2
  %.phi.trans.insert16 = getelementptr i8, ptr %1, i64 712
  %.pre17 = load i32, ptr %.phi.trans.insert16, align 4
  %.phi.trans.insert18 = getelementptr i8, ptr %1, i64 716
  %.pre19 = load i32, ptr %.phi.trans.insert18, align 4
  %6 = icmp eq i32 %.pre17, 1
  %7 = icmp eq i32 %.pre19, 1
  %8 = and i1 %6, %7
  br i1 %8, label %60, label %59

9:                                                ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 712
  %.pre = load i32, ptr %.phi.trans.insert, align 4
  %.phi.trans.insert13 = getelementptr i8, ptr %1, i64 716
  %.pre14 = load i32, ptr %.phi.trans.insert13, align 4
  %10 = icmp eq i32 %.pre, 1
  %11 = icmp eq i32 %.pre14, 1
  %12 = and i1 %10, %11
  br i1 %12, label %64, label %59

13:                                               ; preds = %2
  %.phi.trans.insert24 = getelementptr i8, ptr %1, i64 712
  %.pre25 = load i32, ptr %.phi.trans.insert24, align 4
  %.phi.trans.insert26 = getelementptr i8, ptr %1, i64 716
  %.pre27 = load i32, ptr %.phi.trans.insert26, align 4
  %14 = icmp eq i32 %.pre25, 1
  %15 = icmp eq i32 %.pre27, 1
  %16 = and i1 %14, %15
  br i1 %16, label %68, label %59

17:                                               ; preds = %2
  %18 = getelementptr i8, ptr %1, i64 712
  %19 = load i32, ptr %18, align 4
  %20 = getelementptr i8, ptr %1, i64 716
  %21 = load i32, ptr %20, align 4
  %22 = icmp eq i32 %19, 2
  %23 = icmp eq i32 %21, 2
  %24 = and i1 %22, %23
  br i1 %24, label %.thread, label %59

25:                                               ; preds = %2
  %26 = getelementptr i8, ptr %1, i64 712
  %27 = load i32, ptr %26, align 4
  %28 = getelementptr i8, ptr %1, i64 716
  %29 = load i32, ptr %28, align 4
  %30 = icmp eq i32 %27, 2
  %31 = icmp eq i32 %29, 2
  %32 = and i1 %30, %31
  br i1 %32, label %.thread33, label %59

.sink.split:                                      ; preds = %78, %75
  %.sink = phi i32 [ 4, %75 ], [ 5, %78 ]
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
  br i1 %41, label %.thread34, label %59

42:                                               ; preds = %86, %2
  %43 = getelementptr i8, ptr %1, i64 32
  %44 = load ptr, ptr %43, align 8
  %45 = icmp eq ptr %44, null
  br i1 %45, label %common.ret, label %75

46:                                               ; preds = %86, %2
  %47 = getelementptr i8, ptr %1, i64 40
  %48 = load ptr, ptr %47, align 8
  %49 = icmp eq ptr %48, null
  br i1 %49, label %common.ret, label %78

50:                                               ; preds = %2
  %.phi.trans.insert21 = getelementptr i8, ptr %1, i64 24
  %.pre22 = load ptr, ptr %.phi.trans.insert21, align 8
  %51 = icmp eq ptr %.pre22, null
  br i1 %51, label %common.ret, label %81

52:                                               ; preds = %147, %2
  %53 = getelementptr i8, ptr %1, i64 8
  %54 = load ptr, ptr %53, align 8
  %55 = icmp eq ptr %54, null
  br i1 %55, label %common.ret, label %89

56:                                               ; preds = %2, %2
  %57 = load ptr, ptr %1, align 8
  %58 = icmp eq ptr %57, null
  br i1 %58, label %common.ret, label %124

59:                                               ; preds = %13, %34, %96, %131, %5, %9, %17, %25, %2
  br label %common.ret

60:                                               ; preds = %.thread, %5
  %61 = getelementptr i8, ptr %1, i64 716
  %62 = getelementptr i8, ptr %1, i64 712
  %63 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %63, align 1
  store i32 0, ptr %61, align 4
  store i32 0, ptr %62, align 4
  br label %3

64:                                               ; preds = %.thread33, %9
  %65 = getelementptr i8, ptr %1, i64 716
  %66 = getelementptr i8, ptr %1, i64 712
  %67 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %67, align 1
  store i32 0, ptr %65, align 4
  store i32 0, ptr %66, align 4
  br label %common.ret

68:                                               ; preds = %.thread34, %13
  %69 = getelementptr i8, ptr %1, i64 716
  %70 = getelementptr i8, ptr %1, i64 712
  %71 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %71, align 1
  store i32 0, ptr %69, align 4
  store i32 0, ptr %70, align 4
  br label %common.ret

.thread:                                          ; preds = %17
  %72 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %72, align 2
  br label %60

.thread33:                                        ; preds = %25
  %73 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %73, align 2
  br label %64

.thread34:                                        ; preds = %34
  %74 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %74, align 2
  br label %68

75:                                               ; preds = %42
  %76 = load i8, ptr %44, align 1
  %77 = icmp ult i8 %76, 3
  br i1 %77, label %common.ret, label %.sink.split

78:                                               ; preds = %46
  %79 = load i8, ptr %48, align 1
  %80 = icmp ult i8 %79, 3
  br i1 %80, label %common.ret, label %.sink.split

81:                                               ; preds = %50
  %82 = load i8, ptr %.pre22, align 1
  %83 = icmp ult i8 %82, 3
  br i1 %83, label %common.ret, label %84

84:                                               ; preds = %81
  %85 = icmp eq i8 %82, 5
  br i1 %85, label %86, label %4

86:                                               ; preds = %84
  %87 = getelementptr i8, ptr %.pre22, i64 8
  %88 = load i8, ptr %87, align 1
  %.not12 = icmp eq i8 %88, 0
  br i1 %.not12, label %46, label %42

89:                                               ; preds = %52
  %90 = load i8, ptr %54, align 1
  %91 = icmp eq i8 %90, 11
  br i1 %91, label %92, label %common.ret

92:                                               ; preds = %89
  %93 = getelementptr i8, ptr %54, i64 8
  %94 = load ptr, ptr %93, align 8
  %95 = icmp eq ptr %94, inttoptr (i64 5417056880 to ptr)
  br i1 %95, label %96, label %common.ret

96:                                               ; preds = %92
  %97 = getelementptr i8, ptr %1, i64 712
  %98 = load i32, ptr %97, align 8
  %99 = getelementptr i8, ptr %1, i64 716
  %100 = load i32, ptr %99, align 4
  %101 = getelementptr i8, ptr %1, i64 641
  %102 = load i8, ptr %101, align 1
  %103 = icmp eq i32 %98, 1
  %104 = icmp eq i32 %100, 1
  %105 = and i1 %103, %104
  %106 = icmp ne i8 %102, 0
  %107 = and i1 %105, %106
  br i1 %107, label %108, label %59

108:                                              ; preds = %96
  %109 = getelementptr i8, ptr %1, i64 704
  %110 = load i32, ptr %109, align 8
  %111 = getelementptr i8, ptr %1, i64 708
  %112 = load i32, ptr %111, align 4
  %113 = zext i32 %110 to i64
  %114 = add nuw nsw i64 %113, 1
  %115 = zext i32 %112 to i64
  %.not11 = icmp samesign ult i64 %114, %115
  br i1 %.not11, label %.thread35, label %common.ret

.thread35:                                        ; preds = %108
  %116 = getelementptr i8, ptr %54, i64 16
  %117 = load ptr, ptr %116, align 8
  %118 = getelementptr i8, ptr %1, i64 144
  store ptr %117, ptr %118, align 8
  %119 = getelementptr i8, ptr %1, i64 642
  store i8 1, ptr %119, align 2
  store i32 2, ptr %99, align 4
  store i32 2, ptr %97, align 8
  %120 = getelementptr i8, ptr %1, i64 720
  %121 = load i32, ptr %120, align 8
  %122 = add i32 %121, 1
  store i32 %122, ptr %120, align 8
  %123 = getelementptr i8, ptr %1, i64 24
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %123, i8 0, i64 24, i1 false)
  br label %common.ret

124:                                              ; preds = %56
  %125 = load i8, ptr %57, align 1
  %126 = icmp eq i8 %125, 11
  br i1 %126, label %127, label %common.ret

127:                                              ; preds = %124
  %128 = getelementptr i8, ptr %57, i64 8
  %129 = load ptr, ptr %128, align 8
  %130 = icmp eq ptr %129, inttoptr (i64 5417101712 to ptr)
  br i1 %130, label %131, label %common.ret

131:                                              ; preds = %127
  %132 = getelementptr i8, ptr %1, i64 712
  %133 = load i32, ptr %132, align 8
  %134 = getelementptr i8, ptr %1, i64 716
  %135 = load i32, ptr %134, align 4
  %136 = getelementptr i8, ptr %1, i64 640
  %137 = load i8, ptr %136, align 8
  %138 = or i32 %135, %133
  %139 = icmp eq i32 %138, 0
  %140 = icmp ne i8 %137, 0
  %141 = and i1 %139, %140
  br i1 %141, label %142, label %59

142:                                              ; preds = %131
  %143 = getelementptr i8, ptr %1, i64 704
  %144 = load i32, ptr %143, align 8
  %145 = getelementptr i8, ptr %1, i64 708
  %146 = load i32, ptr %145, align 4
  %.not = icmp ult i32 %144, %146
  br i1 %.not, label %147, label %common.ret

147:                                              ; preds = %142
  %148 = getelementptr i8, ptr %57, i64 16
  %149 = load ptr, ptr %148, align 8
  %150 = getelementptr i8, ptr %1, i64 136
  store ptr %149, ptr %150, align 8
  %151 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %151, align 1
  store i32 1, ptr %134, align 4
  store i32 1, ptr %132, align 8
  %152 = getelementptr i8, ptr %1, i64 720
  %153 = load i32, ptr %152, align 8
  %154 = add i32 %153, 1
  store i32 %154, ptr %152, align 8
  %155 = getelementptr i8, ptr %1, i64 724
  %156 = load i32, ptr %155, align 4
  %157 = add i32 %156, 1
  store i32 %157, ptr %155, align 4
  br label %52
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
