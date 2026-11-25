// Either (Either.kt) lowered by trikeshed-lower-cursors: eitherLeft, eitherRight and eitherFold over a scalar Either, and over
// an Either whose left is a series (the Either lies as its tag, then the left's buffer, then the right's value).  The
// answers were worked by hand first:
//   fold of Left 7    -> 7 + 100 = 107
//   fold of Right 5   -> 5 * 2   = 10
//   eitherLeft of Left 7, eitherRight of Right 5 -> 7, 5
//   a series of 3 cells as the Left -> its size 3; a Right of 9 -> 0
//   an Either passed through a function that returns it -> fold of Right 5 -> 10
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

!e = !trikeshed.either<i64, i64>
!es = !trikeshed.either<!trikeshed.series<i32>, i64>

// LOWERED-LABEL: func.func @fold(
// LOWERED-SAME: %arg0: i1, %arg1: i64, %arg2: i64
// LOWERED: scf.if
// LOWERED-NOT: trikeshed.
func.func @fold(%e: !e) -> i64 {
  %r = trikeshed.eitherFold %e : !e -> i64 {
  ^bb0(%l: i64):
    %c = arith.constant 100 : i64
    %s = arith.addi %l, %c : i64
    trikeshed.yield %s : i64
  }, {
  ^bb0(%x: i64):
    %two = arith.constant 2 : i64
    %p = arith.muli %x, %two : i64
    trikeshed.yield %p : i64
  }
  return %r : i64
}

// LOWERED-LABEL: func.func @left(
// LOWERED-NOT: trikeshed.
func.func @left(%e: !e) -> i64 {
  %l = trikeshed.eitherLeft %e : !e -> i64
  return %l : i64
}

// LOWERED-LABEL: func.func @right(
// LOWERED-NOT: trikeshed.
func.func @right(%e: !e) -> i64 {
  %r = trikeshed.eitherRight %e : !e -> i64
  return %r : i64
}

// LOWERED-LABEL: func.func @size_of_left(
// LOWERED-SAME: %arg0: i1, %arg1: memref<?xi32, strided<[1], offset: ?>>, %arg2: i64
// LOWERED-NOT: trikeshed.
func.func @size_of_left(%e: !es) -> index {
  %r = trikeshed.eitherFold %e : !es -> index {
  ^bb0(%xs: !trikeshed.series<i32>):
    %n = trikeshed.size %xs : !trikeshed.series<i32>
    trikeshed.yield %n : index
  }, {
  ^bb0(%x: i64):
    %z = arith.constant 0 : index
    trikeshed.yield %z : index
  }
  return %r : index
}

// an Either returned by a function and passed on: the tag and the sides travel through the call
// LOWERED-LABEL: func.func @pass(
// LOWERED-NOT: trikeshed.
func.func @pass(%e: !e) -> !e {
  %f = func.call @id(%e) : (!e) -> !e
  return %f : !e
}
func.func private @id(%e: !e) -> !e {
  return %e : !e
}

func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

// prints one i64 as a one-cell memref: "[v]"
func.func @show(%x: i64) {
  %m = memref.alloc() : memref<1xi64>
  %c0 = arith.constant 0 : index
  memref.store %x, %m[%c0] : memref<1xi64>
  %u = memref.cast %m : memref<1xi64> to memref<*xi64>
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  return
}

func.func @main() {
  %t = arith.constant true
  %f = arith.constant false
  %seven = arith.constant 7 : i64
  %five = arith.constant 5 : i64
  %zero64 = arith.constant 0 : i64
  %nine = arith.constant 9 : i64
  %left = builtin.unrealized_conversion_cast %t, %seven, %zero64 : i1, i64, i64 to !e
  %right = builtin.unrealized_conversion_cast %f, %zero64, %five : i1, i64, i64 to !e
  %a = func.call @fold(%left) : (!e) -> i64
  %b = func.call @fold(%right) : (!e) -> i64
  func.call @show(%a) : (i64) -> ()
  func.call @show(%b) : (i64) -> ()
  %l = func.call @left(%left) : (!e) -> i64
  func.call @show(%l) : (i64) -> ()
  %r = func.call @right(%right) : (!e) -> i64
  func.call @show(%r) : (i64) -> ()

  %c4 = arith.constant 4 : i32
  %c5 = arith.constant 5 : i32
  %c6 = arith.constant 6 : i32
  %n3 = arith.constant 3 : index
  %buf = memref.alloc(%n3) : memref<?xi32>
  %bufs = memref.cast %buf : memref<?xi32> to memref<?xi32, strided<[1], offset: ?>>
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  memref.store %c4, %buf[%i0] : memref<?xi32>
  memref.store %c5, %buf[%i1] : memref<?xi32>
  memref.store %c6, %buf[%i2] : memref<?xi32>
  %lt = builtin.unrealized_conversion_cast %t, %bufs, %zero64 : i1, memref<?xi32, strided<[1], offset: ?>>, i64 to !es
  %rt = builtin.unrealized_conversion_cast %f, %bufs, %nine : i1, memref<?xi32, strided<[1], offset: ?>>, i64 to !es
  %m1 = func.call @size_of_left(%lt) : (!es) -> index
  %m2 = func.call @size_of_left(%rt) : (!es) -> index
  %m1i = arith.index_cast %m1 : index to i64
  %m2i = arith.index_cast %m2 : index to i64
  func.call @show(%m1i) : (i64) -> ()
  func.call @show(%m2i) : (i64) -> ()

  %p = func.call @pass(%right) : (!e) -> !e
  %q = func.call @fold(%p) : (!e) -> i64
  func.call @show(%q) : (i64) -> ()
  return
}

// CHECK: [107]
// CHECK: [10]
// CHECK: [7]
// CHECK: [5]
// CHECK: [3]
// CHECK: [0]
// CHECK: [10]
