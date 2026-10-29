; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write)
define range(i64 0, 2) i64 @scalar(i64 %0, ptr nofree writeonly captures(none) initializes((0, 8)) %1) local_unnamed_addr #0 {
  %3 = sext i64 %0 to i128
  %4 = add nsw i128 %3, 1
  %5 = trunc i128 %4 to i64
  %6 = sext i64 %5 to i128
  %7 = icmp ne i128 %4, %6
  store i64 %5, ptr %1, align 4
  %8 = zext i1 %7 to i64
  ret i64 %8
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i64, ptr %2, align 8
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  %7 = sext i64 %3 to i128
  %8 = add nsw i128 %7, 1
  %9 = trunc i128 %8 to i64
  %10 = sext i64 %9 to i128
  %11 = icmp ne i128 %8, %10
  store i64 %9, ptr %6, align 4
  %12 = zext i1 %11 to i64
  %13 = getelementptr i8, ptr %0, i64 16
  %14 = load ptr, ptr %13, align 8
  store i64 %12, ptr %14, align 8
  ret void
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
