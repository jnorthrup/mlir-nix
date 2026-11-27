// The views that Views.h's take, drop, takeLast, dropLast, reversed, erased and inserted were (deleted with Laws.h and
// scripts/views-check.cc by the tokenmax joins lane, 71eaf9c; the stdlib was their oracle).  Now they are the trikeshed
// dialect's slice and combine, lowered by trikeshed-lower-cursors and run.  Checked as views-check.cc checked them: each
// cut of a five-row series is printed, and its rows are the rows the stdlib's list slicing and insert give (the reference
// is resume/joins/views-oracle.py, which computes the same sequence with Python lists; the CHECK lines are its output):
//   xs = [0, 10, 20, 30, 40]
//   for k in 0, 1, 3, 5, 7:   take k, drop k, takeLast k, dropLast k      (k past the end clamps to the whole series)
//   for at in 0, 2, 4, 5, 7:  erased at (past the end: all of xs), inserted at 99
//   reversed xs; reversed(dropLast(drop(xs, 1), 1)) = [30, 20, 10]
//   inserted(erased(xs, 1), 2, 99) = [0, 20, 99, 30, 40]
//   the empty series: take 3 is empty; inserted 0 99 is [99]; erased 0 of a one-row series is empty
//   xs itself is untouched after all of it.
//
// Each view is made and shown in the function that makes it: a slice is never returned from a function (its copy would
// be a bufferization.clone, which the standard pipeline does not lower).
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_c_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.slice %{{.*}}[%{{.*}}, %{{.*}}] : <i32> -> <i32>
// ROUND: trikeshed.at %{{.*}}[%{{.*}}] : !trikeshed.series<i32>, index -> i32
// ROUND: trikeshed.combine %{{.*}}, %{{.*}}, %{{.*}} : !trikeshed.series<i32>, !trikeshed.series<i32>, !trikeshed.series<i32> -> <i32>
//
// the printed sequence: each show is its count, then its rows (none when there are none)
// CHECK: 0
// CHECK: 1
// CHECK: [0]
// CHECK: 3
// CHECK: [0,  10,  20]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 4
// CHECK: [10,  20,  30,  40]
// CHECK: 2
// CHECK: [30,  40]
// CHECK: 0
// CHECK: 0
// CHECK: 1
// CHECK: [40]
// CHECK: 3
// CHECK: [20,  30,  40]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 4
// CHECK: [0,  10,  20,  30]
// CHECK: 2
// CHECK: [0,  10]
// CHECK: 0
// CHECK: 4
// CHECK: [10,  20,  30,  40]
// CHECK: 4
// CHECK: [0,  10,  30,  40]
// CHECK: 4
// CHECK: [0,  10,  20,  30]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]
// CHECK: 6
// CHECK: [99,  0,  10,  20,  30,  40]
// CHECK: 6
// CHECK: [0,  10,  99,  20,  30,  40]
// CHECK: 6
// CHECK: [0,  10,  20,  30,  99,  40]
// CHECK: 6
// CHECK: [0,  10,  20,  30,  40,  99]
// CHECK: 6
// CHECK: [0,  10,  20,  30,  40,  99]
// CHECK: 5
// CHECK: [40,  30,  20,  10,  0]
// CHECK: 3
// CHECK: [30,  20,  10]
// CHECK: 5
// CHECK: [0,  20,  99,  30,  40]
// CHECK: 0
// CHECK: 1
// CHECK: [99]
// CHECK: 0
// CHECK: 5
// CHECK: [0,  10,  20,  30,  40]

!s = !trikeshed.series<i32>

memref.global "private" constant @xs : memref<5xi32> = dense<[0, 10, 20, 30, 40]>
memref.global "private" constant @one : memref<1xi32> = dense<[7]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}
func.func private @printI64(i64)
func.func private @printNewline()

// the rows of a series: its count, then the rows (none for an empty series: a printed empty buffer shows a stray cell)
func.func private @show(%xs: !s) {
  %c0 = arith.constant 0 : index
  %n = trikeshed.size %xs : !s
  %n64 = arith.index_cast %n : index to i64
  func.call @printI64(%n64) : (i64) -> ()
  func.call @printNewline() : () -> ()
  %some = arith.cmpi ugt, %n, %c0 : index
  scf.if %some {
    %out = memref.alloc(%n) : memref<?xi32>
    %end = trikeshed.drain %xs, %out : !s, memref<?xi32> -> index
    %u = memref.cast %out : memref<?xi32> to memref<*xi32>
    func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  }
  return
}

// take, drop, takeLast, dropLast: the slice of the rows the cut keeps (k clamped to the size)
func.func private @take_show(%xs: !s, %k: index) {
  %c0 = arith.constant 0 : index
  %n = trikeshed.size %xs : !s
  %m = arith.minui %k, %n : index
  %v = trikeshed.slice %xs[%c0, %m] : !s -> !s
  func.call @show(%v) : (!s) -> ()
  return
}

func.func private @drop_show(%xs: !s, %k: index) {
  %n = trikeshed.size %xs : !s
  %m = arith.minui %k, %n : index
  %rest = arith.subi %n, %m : index
  %v = trikeshed.slice %xs[%m, %rest] : !s -> !s
  func.call @show(%v) : (!s) -> ()
  return
}

func.func private @takeLast_show(%xs: !s, %k: index) {
  %n = trikeshed.size %xs : !s
  %m = arith.minui %k, %n : index
  %off = arith.subi %n, %m : index
  %v = trikeshed.slice %xs[%off, %m] : !s -> !s
  func.call @show(%v) : (!s) -> ()
  return
}

func.func private @dropLast_show(%xs: !s, %k: index) {
  %c0 = arith.constant 0 : index
  %n = trikeshed.size %xs : !s
  %m = arith.minui %k, %n : index
  %keep = arith.subi %n, %m : index
  %v = trikeshed.slice %xs[%c0, %keep] : !s -> !s
  func.call @show(%v) : (!s) -> ()
  return
}

// erased: the rows before `at`, then the rows after it (all of xs when `at` is past the end).  Uniform, with no branch:
// past the end the head is all of xs and the tail is empty.
func.func private @erased_show(%xs: !s, %at: index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %n = trikeshed.size %xs : !s
  %headLen = arith.minui %at, %n : index
  %after = arith.addi %at, %c1 : index
  %tailOff = arith.minui %after, %n : index
  %tailLen = arith.subi %n, %tailOff : index
  %head = trikeshed.slice %xs[%c0, %headLen] : !s -> !s
  %tail = trikeshed.slice %xs[%tailOff, %tailLen] : !s -> !s
  %c = trikeshed.combine %head, %tail : !s, !s -> !s
  func.call @show(%c) : (!s) -> ()
  return
}

// inserted: the rows before `at`, the row v, then the rows from `at` on (at past the end appends)
func.func private @inserted_show(%xs: !s, %at: index, %v: i32) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %n = trikeshed.size %xs : !s
  %pos = arith.minui %at, %n : index
  %head = trikeshed.slice %xs[%c0, %pos] : !s -> !s
  %rest = arith.subi %n, %pos : index
  %tail = trikeshed.slice %xs[%pos, %rest] : !s -> !s
  %row = trikeshed.series %c1 : !s {
  ^bb0(%i: index):
    trikeshed.yield %v : i32
  }
  %c = trikeshed.combine %head, %row, %tail : !s, !s, !s -> !s
  func.call @show(%c) : (!s) -> ()
  return
}

// reversed, as its law states it: at(reversed xs, i) = at(xs, size(xs) - 1 - i).  trikeshed.reversed has no lowering
// (trikeshed-lower-cursors leaves it, and no pattern has ever lowered it), so the test writes the law as a series.
func.func private @reversed_show(%xs: !s) {
  %c1 = arith.constant 1 : index
  %n = trikeshed.size %xs : !s
  %r = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %last = arith.subi %n, %c1 : index
    %j = arith.subi %last, %i : index
    %x = trikeshed.at %xs[%j] : !s, index -> i32
    trikeshed.yield %x : i32
  }
  func.call @show(%r) : (!s) -> ()
  return
}

// reversed(dropLast(drop(xs, 1), 1))
func.func private @composed_reversed_show(%xs: !s) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %n = trikeshed.size %xs : !s
  %nd = arith.subi %n, %c1 : index
  %d = trikeshed.slice %xs[%c1, %nd] : !s -> !s
  %dn = trikeshed.size %d : !s
  %keep = arith.subi %dn, %c1 : index
  %dd = trikeshed.slice %d[%c0, %keep] : !s -> !s
  %ddn = trikeshed.size %dd : !s
  %r = trikeshed.series %ddn : !s {
  ^bb0(%i: index):
    %last = arith.subi %ddn, %c1 : index
    %j = arith.subi %last, %i : index
    %x = trikeshed.at %dd[%j] : !s, index -> i32
    trikeshed.yield %x : i32
  }
  func.call @show(%r) : (!s) -> ()
  return
}

// inserted(erased(xs, 1), 2, 99)
func.func private @composed_insert_show(%xs: !s, %v: i32) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %n = trikeshed.size %xs : !s
  %headLen = arith.minui %c1, %n : index
  %tailOff = arith.minui %c2, %n : index
  %tailLen = arith.subi %n, %tailOff : index
  %head = trikeshed.slice %xs[%c0, %headLen] : !s -> !s
  %tail = trikeshed.slice %xs[%tailOff, %tailLen] : !s -> !s
  %er = trikeshed.combine %head, %tail : !s, !s -> !s
  %en = trikeshed.size %er : !s
  %pos = arith.minui %c2, %en : index
  %eh = trikeshed.slice %er[%c0, %pos] : !s -> !s
  %erest = arith.subi %en, %pos : index
  %et = trikeshed.slice %er[%pos, %erest] : !s -> !s
  %row = trikeshed.series %c1 : !s {
  ^bb0(%i: index):
    trikeshed.yield %v : i32
  }
  %c = trikeshed.combine %eh, %row, %et : !s, !s, !s -> !s
  func.call @show(%c) : (!s) -> ()
  return
}

func.func @main() {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c7 = arith.constant 7 : index
  %v99 = arith.constant 99 : i32

  %xs5 = memref.get_global @xs : memref<5xi32>
  %xsd = memref.cast %xs5 : memref<5xi32> to memref<?xi32>
  %xs = builtin.unrealized_conversion_cast %xsd : memref<?xi32> to !s
  %empty = memref.alloc(%c0) : memref<?xi32>
  %none = builtin.unrealized_conversion_cast %empty : memref<?xi32> to !s
  %one1 = memref.get_global @one : memref<1xi32>
  %oned = memref.cast %one1 : memref<1xi32> to memref<?xi32>
  %one = builtin.unrealized_conversion_cast %oned : memref<?xi32> to !s

  func.call @take_show(%xs, %c0) : (!s, index) -> ()
  func.call @take_show(%xs, %c1) : (!s, index) -> ()
  func.call @take_show(%xs, %c3) : (!s, index) -> ()
  func.call @take_show(%xs, %c5) : (!s, index) -> ()
  func.call @take_show(%xs, %c7) : (!s, index) -> ()

  func.call @drop_show(%xs, %c0) : (!s, index) -> ()
  func.call @drop_show(%xs, %c1) : (!s, index) -> ()
  func.call @drop_show(%xs, %c3) : (!s, index) -> ()
  func.call @drop_show(%xs, %c5) : (!s, index) -> ()
  func.call @drop_show(%xs, %c7) : (!s, index) -> ()

  func.call @takeLast_show(%xs, %c1) : (!s, index) -> ()
  func.call @takeLast_show(%xs, %c3) : (!s, index) -> ()
  func.call @takeLast_show(%xs, %c7) : (!s, index) -> ()

  func.call @dropLast_show(%xs, %c1) : (!s, index) -> ()
  func.call @dropLast_show(%xs, %c3) : (!s, index) -> ()
  func.call @dropLast_show(%xs, %c7) : (!s, index) -> ()

  func.call @erased_show(%xs, %c0) : (!s, index) -> ()
  func.call @erased_show(%xs, %c2) : (!s, index) -> ()
  func.call @erased_show(%xs, %c4) : (!s, index) -> ()
  func.call @erased_show(%xs, %c5) : (!s, index) -> ()
  func.call @erased_show(%xs, %c7) : (!s, index) -> ()

  func.call @inserted_show(%xs, %c0, %v99) : (!s, index, i32) -> ()
  func.call @inserted_show(%xs, %c2, %v99) : (!s, index, i32) -> ()
  func.call @inserted_show(%xs, %c4, %v99) : (!s, index, i32) -> ()
  func.call @inserted_show(%xs, %c5, %v99) : (!s, index, i32) -> ()
  func.call @inserted_show(%xs, %c7, %v99) : (!s, index, i32) -> ()

  func.call @reversed_show(%xs) : (!s) -> ()
  func.call @composed_reversed_show(%xs) : (!s) -> ()
  func.call @composed_insert_show(%xs, %v99) : (!s, i32) -> ()

  // the empty series, and a one-row series: the same views
  func.call @take_show(%none, %c3) : (!s, index) -> ()
  func.call @inserted_show(%none, %c0, %v99) : (!s, index, i32) -> ()
  func.call @erased_show(%one, %c0) : (!s, index) -> ()

  // xs itself is untouched
  func.call @show(%xs) : (!s) -> ()
  return
}
