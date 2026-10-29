; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-darwin24.6.0"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write)
define range(i64 0, 2) i64 @scalar(i64 %0, ptr nofree writeonly captures(none) initializes((0, 8)) %1) local_unnamed_addr #0 {
  %3 = sext i64 %0 to i128
  %4 = mul nsw i128 %3, 3
  %5 = mul i128 %3, 55340232221128654848
  %6 = ashr exact i128 %5, 64
  %7 = icmp ne i128 %4, %6
  %8 = add nsw i128 %6, -1
  %9 = shl i128 %8, 64
  %10 = ashr exact i128 %9, 64
  %11 = icmp ne i128 %8, %10
  %12 = or i1 %7, %11
  %13 = add nsw i128 %10, 7
  %14 = trunc i128 %13 to i64
  %15 = sext i64 %14 to i128
  %16 = icmp ne i128 %13, %15
  %17 = or i1 %12, %16
  store i64 %14, ptr %1, align 4
  %18 = zext i1 %17 to i64
  ret i64 %18
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none)
define void @_mlir_scalar(ptr nofree readonly captures(none) %0) local_unnamed_addr #1 {
  %2 = load ptr, ptr %0, align 8
  %3 = load i64, ptr %2, align 8
  %4 = getelementptr i8, ptr %0, i64 8
  %5 = load ptr, ptr %4, align 8
  %6 = load ptr, ptr %5, align 8
  %7 = sext i64 %3 to i128
  %8 = mul nsw i128 %7, 3
  %9 = mul i128 %7, 55340232221128654848
  %10 = ashr exact i128 %9, 64
  %11 = icmp ne i128 %8, %10
  %12 = add nsw i128 %10, -1
  %13 = shl i128 %12, 64
  %14 = ashr exact i128 %13, 64
  %15 = icmp ne i128 %12, %14
  %16 = or i1 %11, %15
  %17 = add nsw i128 %14, 7
  %18 = trunc i128 %17 to i64
  %19 = sext i64 %18 to i128
  %20 = icmp ne i128 %17, %19
  %21 = or i1 %16, %20
  store i64 %18, ptr %6, align 4
  %22 = zext i1 %21 to i64
  %23 = getelementptr i8, ptr %0, i64 16
  %24 = load ptr, ptr %23, align 8
  store i64 %22, ptr %24, align 8
  ret void
}

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: write) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem: none) }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
