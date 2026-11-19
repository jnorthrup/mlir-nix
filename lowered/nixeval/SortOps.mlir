// __sort hollowed into the TrikeShed dialect: the sort is trikeshed.sorted (the stable bottom-up merge sort, as
// Kotlin's sortedWith and composite::sortRows are stable); the comparator is a Nix function, so each comparison calls
// back into the evaluator through nixev_sort_lt (callFunction + forceBool, or the lessThan fast path — the forcing
// that carries an error context stays in C++).  A list's cells (Value**) are a series<i64> of pointer bits, seen
// through the descriptor built inline, as ListOps.mlir does; the sorted series is drained into the result list's
// arena cells.  The bridge has forced the list, its elements (in order) and the function, and made the result list.
//
// The merge takes the left run's element unless the right one is strictly less, so the order region yields
// less(right, left) ? 1 : 0 — one comparator call per comparison, with the same arguments sortRows' merge gave it,
// and equal elements keep their order (a tie yields 0, which takes left).
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// 1 when a < b (the Nix comparator, or lessThan), else 0; may throw the evaluator's error
func.func private @nixev_sort_lt(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64

// the descriptor of n i64 cells at p (module-unique: ListOps.mlir has its own @desc)
func.func private @sort_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

func.func @nixev_ts_sort(%st: !llvm.ptr, %f: !llvm.ptr, %islt: i64, %from: !llvm.ptr, %n: i64, %into: !llvm.ptr, %pos: !llvm.ptr) {
  %df = func.call @sort_desc(%from, %n) : (!llvm.ptr, i64) -> !d
  %mf = builtin.unrealized_conversion_cast %df : !d to !m
  %ss = builtin.unrealized_conversion_cast %mf : !m to !s
  %sorted = trikeshed.sorted %ss : !s -> !s by {
  ^bb0(%l: i64, %r: i64):
    %lp = llvm.inttoptr %l : i64 to !llvm.ptr
    %rp = llvm.inttoptr %r : i64 to !llvm.ptr
    %c = func.call @nixev_sort_lt(%st, %f, %islt, %rp, %lp, %pos) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %c32 = arith.trunci %c : i64 to i32
    trikeshed.yield %c32 : i32
  }
  %di = func.call @sort_desc(%into, %n) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m
  %end = trikeshed.drain %sorted, %mi : !s, !m -> index
  return
}
