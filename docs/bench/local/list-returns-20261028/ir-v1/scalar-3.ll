; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: readwrite, inaccessiblemem: none, target_mem: none)
define range(i64 0, 96) i64 @scalar(i32 %0, ptr nofree captures(none) %1) local_unnamed_addr #0 {
  switch i32 %0, label %54 [
    i32 0, label %51
    i32 1, label %common.ret
    i32 2, label %3
    i32 3, label %4
    i32 4, label %5
    i32 5, label %9
    i32 6, label %13
    i32 7, label %17
    i32 8, label %25
    i32 9, label %33
    i32 10, label %41
    i32 11, label %47
    i32 12, label %51
  ]

common.ret:                                       ; preds = %.thread26, %125, %107, %110, %51, %91, %72, %75, %47, %41, %2, %59, %63, %54, %4, %3
  %common.ret.op = phi i64 [ 95, %107 ], [ 1, %3 ], [ 3, %4 ], [ 4, %54 ], [ 6, %63 ], [ 0, %2 ], [ 74, %41 ], [ 82, %47 ], [ 87, %72 ], [ 85, %91 ], [ 90, %51 ], [ 0, %59 ], [ 87, %75 ], [ 95, %110 ], [ 93, %125 ], [ 74, %.thread26 ]
  ret i64 %common.ret.op

3:                                                ; preds = %55, %2
  br label %common.ret

4:                                                ; preds = %2
  br label %common.ret

5:                                                ; preds = %2
  %.phi.trans.insert11 = getelementptr i8, ptr %1, i64 712
  %.pre12 = load i32, ptr %.phi.trans.insert11, align 4
  %.phi.trans.insert13 = getelementptr i8, ptr %1, i64 716
  %.pre14 = load i32, ptr %.phi.trans.insert13, align 4
  %6 = icmp eq i32 %.pre12, 1
  %7 = icmp eq i32 %.pre14, 1
  %8 = and i1 %6, %7
  br i1 %8, label %55, label %54

9:                                                ; preds = %2
  %.phi.trans.insert = getelementptr i8, ptr %1, i64 712
  %.pre = load i32, ptr %.phi.trans.insert, align 4
  %.phi.trans.insert8 = getelementptr i8, ptr %1, i64 716
  %.pre9 = load i32, ptr %.phi.trans.insert8, align 4
  %10 = icmp eq i32 %.pre, 1
  %11 = icmp eq i32 %.pre9, 1
  %12 = and i1 %10, %11
  br i1 %12, label %59, label %54

13:                                               ; preds = %2
  %.phi.trans.insert19 = getelementptr i8, ptr %1, i64 712
  %.pre20 = load i32, ptr %.phi.trans.insert19, align 4
  %.phi.trans.insert21 = getelementptr i8, ptr %1, i64 716
  %.pre22 = load i32, ptr %.phi.trans.insert21, align 4
  %14 = icmp eq i32 %.pre20, 1
  %15 = icmp eq i32 %.pre22, 1
  %16 = and i1 %14, %15
  br i1 %16, label %63, label %54

17:                                               ; preds = %2
  %18 = getelementptr i8, ptr %1, i64 712
  %19 = load i32, ptr %18, align 4
  %20 = getelementptr i8, ptr %1, i64 716
  %21 = load i32, ptr %20, align 4
  %22 = icmp eq i32 %19, 2
  %23 = icmp eq i32 %21, 2
  %24 = and i1 %22, %23
  br i1 %24, label %.thread, label %54

25:                                               ; preds = %2
  %26 = getelementptr i8, ptr %1, i64 712
  %27 = load i32, ptr %26, align 4
  %28 = getelementptr i8, ptr %1, i64 716
  %29 = load i32, ptr %28, align 4
  %30 = icmp eq i32 %27, 2
  %31 = icmp eq i32 %29, 2
  %32 = and i1 %30, %31
  br i1 %32, label %.thread24, label %54

33:                                               ; preds = %70, %2
  %34 = getelementptr i8, ptr %1, i64 712
  %35 = load i32, ptr %34, align 4
  %36 = getelementptr i8, ptr %1, i64 716
  %37 = load i32, ptr %36, align 4
  %38 = icmp eq i32 %35, 2
  %39 = icmp eq i32 %37, 2
  %40 = and i1 %38, %39
  br i1 %40, label %.thread25, label %54

41:                                               ; preds = %2
  %.phi.trans.insert16 = getelementptr i8, ptr %1, i64 24
  %.pre17 = load ptr, ptr %.phi.trans.insert16, align 8
  %42 = icmp ne ptr %.pre17, null
  %43 = getelementptr i8, ptr %1, i64 16
  %44 = load ptr, ptr %43, align 8
  %45 = icmp ne ptr %44, null
  %46 = and i1 %42, %45
  br i1 %46, label %70, label %common.ret

47:                                               ; preds = %130, %2
  %48 = getelementptr i8, ptr %1, i64 8
  %49 = load ptr, ptr %48, align 8
  %50 = icmp eq ptr %49, null
  br i1 %50, label %common.ret, label %72

51:                                               ; preds = %2, %2
  %52 = load ptr, ptr %1, align 8
  %53 = icmp eq ptr %52, null
  br i1 %53, label %common.ret, label %107

54:                                               ; preds = %13, %33, %79, %114, %5, %9, %17, %25, %2
  br label %common.ret

55:                                               ; preds = %.thread, %5
  %56 = getelementptr i8, ptr %1, i64 716
  %57 = getelementptr i8, ptr %1, i64 712
  %58 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %58, align 1
  store i32 0, ptr %56, align 4
  store i32 0, ptr %57, align 4
  br label %3

59:                                               ; preds = %.thread24, %9
  %60 = getelementptr i8, ptr %1, i64 716
  %61 = getelementptr i8, ptr %1, i64 712
  %62 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %62, align 1
  store i32 0, ptr %60, align 4
  store i32 0, ptr %61, align 4
  br label %common.ret

63:                                               ; preds = %.thread25, %13
  %64 = getelementptr i8, ptr %1, i64 716
  %65 = getelementptr i8, ptr %1, i64 712
  %66 = getelementptr i8, ptr %1, i64 641
  store i8 0, ptr %66, align 1
  store i32 0, ptr %64, align 4
  store i32 0, ptr %65, align 4
  br label %common.ret

.thread:                                          ; preds = %17
  %67 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %67, align 2
  br label %55

.thread24:                                        ; preds = %25
  %68 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %68, align 2
  br label %59

.thread25:                                        ; preds = %33
  %69 = getelementptr i8, ptr %1, i64 642
  store i8 0, ptr %69, align 2
  br label %63

70:                                               ; preds = %41
  %71 = getelementptr i8, ptr %1, i64 728
  store i32 20, ptr %71, align 8
  br label %33

72:                                               ; preds = %47
  %73 = load i8, ptr %49, align 1
  %74 = icmp eq i8 %73, 11
  br i1 %74, label %75, label %common.ret

75:                                               ; preds = %72
  %76 = getelementptr i8, ptr %49, i64 8
  %77 = load ptr, ptr %76, align 8
  %78 = icmp eq ptr %77, inttoptr (i64 5089913888 to ptr)
  br i1 %78, label %79, label %common.ret

79:                                               ; preds = %75
  %80 = getelementptr i8, ptr %1, i64 712
  %81 = load i32, ptr %80, align 8
  %82 = getelementptr i8, ptr %1, i64 716
  %83 = load i32, ptr %82, align 4
  %84 = getelementptr i8, ptr %1, i64 641
  %85 = load i8, ptr %84, align 1
  %86 = icmp eq i32 %81, 1
  %87 = icmp eq i32 %83, 1
  %88 = and i1 %86, %87
  %89 = icmp ne i8 %85, 0
  %90 = and i1 %88, %89
  br i1 %90, label %91, label %54

91:                                               ; preds = %79
  %92 = getelementptr i8, ptr %1, i64 704
  %93 = load i32, ptr %92, align 8
  %94 = getelementptr i8, ptr %1, i64 708
  %95 = load i32, ptr %94, align 4
  %96 = zext i32 %93 to i64
  %97 = add nuw nsw i64 %96, 1
  %98 = zext i32 %95 to i64
  %.not7 = icmp samesign ult i64 %97, %98
  br i1 %.not7, label %.thread26, label %common.ret

.thread26:                                        ; preds = %91
  %99 = getelementptr i8, ptr %49, i64 16
  %100 = load ptr, ptr %99, align 8
  %101 = getelementptr i8, ptr %1, i64 144
  store ptr %100, ptr %101, align 8
  %102 = getelementptr i8, ptr %1, i64 642
  store i8 1, ptr %102, align 2
  store i32 2, ptr %82, align 4
  store i32 2, ptr %80, align 8
  %103 = getelementptr i8, ptr %1, i64 720
  %104 = load i32, ptr %103, align 8
  %105 = add i32 %104, 1
  store i32 %105, ptr %103, align 8
  %106 = getelementptr i8, ptr %1, i64 24
  store ptr null, ptr %106, align 8
  br label %common.ret

107:                                              ; preds = %51
  %108 = load i8, ptr %52, align 1
  %109 = icmp eq i8 %108, 11
  br i1 %109, label %110, label %common.ret

110:                                              ; preds = %107
  %111 = getelementptr i8, ptr %52, i64 8
  %112 = load ptr, ptr %111, align 8
  %113 = icmp eq ptr %112, inttoptr (i64 5089905984 to ptr)
  br i1 %113, label %114, label %common.ret

114:                                              ; preds = %110
  %115 = getelementptr i8, ptr %1, i64 712
  %116 = load i32, ptr %115, align 8
  %117 = getelementptr i8, ptr %1, i64 716
  %118 = load i32, ptr %117, align 4
  %119 = getelementptr i8, ptr %1, i64 640
  %120 = load i8, ptr %119, align 8
  %121 = or i32 %118, %116
  %122 = icmp eq i32 %121, 0
  %123 = icmp ne i8 %120, 0
  %124 = and i1 %122, %123
  br i1 %124, label %125, label %54

125:                                              ; preds = %114
  %126 = getelementptr i8, ptr %1, i64 704
  %127 = load i32, ptr %126, align 8
  %128 = getelementptr i8, ptr %1, i64 708
  %129 = load i32, ptr %128, align 4
  %.not = icmp ult i32 %127, %129
  br i1 %.not, label %130, label %common.ret

130:                                              ; preds = %125
  %131 = getelementptr i8, ptr %52, i64 16
  %132 = load ptr, ptr %131, align 8
  %133 = getelementptr i8, ptr %1, i64 136
  store ptr %132, ptr %133, align 8
  %134 = getelementptr i8, ptr %1, i64 641
  store i8 1, ptr %134, align 1
  store i32 1, ptr %117, align 4
  store i32 1, ptr %115, align 8
  %135 = getelementptr i8, ptr %1, i64 720
  %136 = load i32, ptr %135, align 8
  %137 = add i32 %136, 1
  store i32 %137, ptr %135, align 8
  %138 = getelementptr i8, ptr %1, i64 724
  %139 = load i32, ptr %138, align 4
  %140 = add i32 %139, 1
  store i32 %140, ptr %138, align 4
  br label %47
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
