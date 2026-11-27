// Fill, then drain: the drain of a lane is one buffer of exactly its count, an ordinary !trikeshed.series, and the ops that
// read a series read it unchanged (size, at, fold, where, sorted, bisect, slice, combine, drain).  The lane holds 5000
// rows, v(i) = (7919 i) mod 10007 (all different: 10007 is prime), over three pages of 2048.  Worked beside it:
//   size 5000;  sum 25031078;  2496 rows below 5000;  sorted, no row above the next
//   bisect in the sorted rows: v(1234) = 5214 is row 2603; -5 belongs before row 0 (-1), 20000 after the last (-5001),
//   5004 is not a row and belongs at 2500 (-2501)
//   sorted[10, 5] = 19 25 26 27 28;  the two smallest and the two greatest: 0 5 10005 10006
// And the drain is MutableSeries.kt's snapshot: a row appended after it is in the lane (5001) and not in the series (5000).
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// The drained rows are a series' buffer: what the series ops below take.
// LOWERED-LABEL: func.func @main(
// LOWERED: memref.cast %{{.*}} : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
// LOWERED-NOT: trikeshed.

// CHECK: [5000,  25031078,  2496,  0,  2603,  -1,  -5001,  -2501,  5001,  5000]
// CHECK: [19,  25,  26,  27,  28]
// CHECK: [0,  5,  10005,  10006]

!lane = !trikeshed.lane<i64>
!s64 = !trikeshed.series<i64>

// the fill: n rows, row i = (7919 i) mod 10007
func.func private @lane_fill(%l: !lane, %n: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %a = arith.constant 7919 : i64
  %p = arith.constant 10007 : i64
  scf.for %i = %c0 to %n step %c1 {
    %x = arith.index_cast %i : index to i64
    %m = arith.muli %x, %a : i64
    %v = arith.remui %m, %p : i64
    %r = trikeshed.append %l, %v : !lane, i64 -> index
  }
  return
}

func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

func.func @main() {
  %l = trikeshed.lane : !lane
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %c10 = arith.constant 10 : index
  %z = arith.constant 0 : i64
  %n = arith.constant 5000 : index
  func.call @lane_fill(%l, %n) : (!lane, index) -> ()
  // the drain: where the fill stops and cells begin
  %xs = trikeshed.drain %l : !lane -> !s64
  %size = trikeshed.size %xs : !s64
  %sum = trikeshed.fold %xs, %z : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %next = arith.addi %acc, %x : i64
    trikeshed.yield %next : i64
  }
  %low = trikeshed.where %xs : !s64 -> !s64 {
  ^bb0(%x: i64):
    %half = arith.constant 5000 : i64
    %lt = arith.cmpi slt, %x, %half : i64
    trikeshed.yield %lt : i1
  }
  %nlow = trikeshed.size %low : !s64
  %sorted = trikeshed.sorted %xs : !s64 -> !s64
  %last = arith.subi %size, %c1 : index
  %inversions = scf.for %i = %c0 to %last step %c1 iter_args(%bad = %z) -> (i64) {
    %i1 = arith.addi %i, %c1 : index
    %a = trikeshed.at %sorted[%i] : !s64, index -> i64
    %b = trikeshed.at %sorted[%i1] : !s64, index -> i64
    %gt = arith.cmpi sgt, %a, %b : i64
    %w = arith.extui %gt : i1 to i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %k1234 = arith.constant 1234 : index
  %key = trikeshed.at %xs[%k1234] : !s64, index -> i64
  %below = arith.constant -5 : i64
  %above = arith.constant 20000 : i64
  %absent = arith.constant 5004 : i64
  %found = trikeshed.bisect %sorted, %key : !s64, i64 -> index
  %before = trikeshed.bisect %sorted, %below : !s64, i64 -> index
  %after = trikeshed.bisect %sorted, %above : !s64, i64 -> index
  %between = trikeshed.bisect %sorted, %absent : !s64, i64 -> index
  // the lane after its drain: an append reaches the lane, not the series
  %more = arith.constant 77 : i64
  %row = trikeshed.append %l, %more : !lane, i64 -> index
  %grown = trikeshed.size %l : !lane
  %still = trikeshed.size %xs : !s64
  %out = memref.alloc() : memref<10xi64>
  %size64 = arith.index_cast %size : index to i64
  %nlow64 = arith.index_cast %nlow : index to i64
  %found64 = arith.index_cast %found : index to i64
  %before64 = arith.index_cast %before : index to i64
  %after64 = arith.index_cast %after : index to i64
  %between64 = arith.index_cast %between : index to i64
  %grown64 = arith.index_cast %grown : index to i64
  %still64 = arith.index_cast %still : index to i64
  memref.store %size64, %out[%c0] : memref<10xi64>
  memref.store %sum, %out[%c1] : memref<10xi64>
  memref.store %nlow64, %out[%c2] : memref<10xi64>
  memref.store %inversions, %out[%c3] : memref<10xi64>
  memref.store %found64, %out[%c4] : memref<10xi64>
  memref.store %before64, %out[%c5] : memref<10xi64>
  memref.store %after64, %out[%c6] : memref<10xi64>
  memref.store %between64, %out[%c7] : memref<10xi64>
  memref.store %grown64, %out[%c8] : memref<10xi64>
  memref.store %still64, %out[%c9] : memref<10xi64>
  %u = memref.cast %out : memref<10xi64> to memref<*xi64>
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  // views of the drained, sorted rows, drained into cells
  %mid = trikeshed.slice %sorted[%c10, %c5] : !s64 -> !s64
  %five = memref.alloc(%c5) : memref<?xi64>
  %e5 = trikeshed.drain %mid, %five : !s64, memref<?xi64> -> index
  %u5 = memref.cast %five : memref<?xi64> to memref<*xi64>
  func.call @printMemrefI64(%u5) : (memref<*xi64>) -> ()
  %top = arith.subi %size, %c2 : index
  %least = trikeshed.slice %sorted[%c0, %c2] : !s64 -> !s64
  %most = trikeshed.slice %sorted[%top, %c2] : !s64 -> !s64
  %ends = trikeshed.combine %least, %most : !s64, !s64 -> !s64
  %four = memref.alloc(%c4) : memref<?xi64>
  %e4 = trikeshed.drain %ends, %four : !s64, memref<?xi64> -> index
  %u4 = memref.cast %four : memref<?xi64> to memref<*xi64>
  func.call @printMemrefI64(%u4) : (memref<*xi64>) -> ()
  return
}
