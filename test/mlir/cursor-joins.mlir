// GroupBy.kt and KeyedJoin.kt, lowered: trikeshed.groupBy and trikeshed.keyedJoin rewritten by trikeshed-lower-cursors
// into sorted, where, project, bisect and series, taken to LLVM by the stock pipeline, executed.  Worked by hand first:
//   xs = [5, 3, 5, 1, 3, 5, 7]
//   groupBy xs                 groups 5, 3, 1, 7 by first appearance: codes [0, 1, 0, 2, 1, 0, 3], exemplars [0, 1, 3, 6]
//   groupBy xs ordered         groups 1, 3, 5, 7: codes [2, 1, 2, 0, 1, 2, 3], exemplars [3, 1, 0, 6]
//   the members of each group  adjacency(codes, 0 ..< 7, 4): ends [0, 2, 5, 1, 4, 3, 6]
//   groupBy xs by x mod 3      2, 0, 2, 1, 0, 2, 1: codes [0, 1, 0, 2, 1, 0, 2], exemplars [0, 1, 3]
//   keyedJoin l r              l = [3, 4, 5, 0, 9] into r = [1, 3, 3, 5, 7] (sorted): firsts [1, 3, 3, 0, 5], counts
//                              [2, 0, 1, 0, 0]
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.groupBy %{{.*}} : <i32> -> <i32>, <i32>
// ROUND: trikeshed.groupBy %{{.*}} ordered : <i32> -> <i32>, <i32>
// ROUND: trikeshed.groupBy %{{.*}} : <i32> -> <i32>, <i32> by {
// ROUND: trikeshed.keyedJoin %{{.*}}, %{{.*}} : <i32>, <i32> -> <!trikeshed.twinpacked<i32>>

// LOWERED-LABEL: func.func @joins(
// LOWERED-NOT: trikeshed.
// LOWERED: scf.while

// CHECK: [0,  1,  0,  2,  1,  0,  3]
// CHECK: [0,  1,  3,  6]
// CHECK: [2,  1,  2,  0,  1,  2,  3]
// CHECK: [3,  1,  0,  6]
// CHECK: [0,  2,  5,  1,  4,  3,  6]
// CHECK: [0,  1,  0,  2,  1,  0,  2]
// CHECK: [0,  1,  3]
// CHECK: [1,  3,  3,  0,  5]
// CHECK: [2,  0,  1,  0,  0]

!s = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!m = !trikeshed.series<!tp>
!out = memref<?xi32>

func.func @joins(%xs: !s, %l: !s, %r: !s, %o0: !out, %o1: !out, %o2: !out, %o3: !out, %o4: !out, %o5: !out, %o6: !out,
                 %o7: !out, %o8: !out) {
  %codes, %ex = trikeshed.groupBy %xs : !s -> !s, !s
  %oc, %oe = trikeshed.groupBy %xs ordered : !s -> !s, !s
  // the members of each group: the counting sort of the rows by their codes
  %n = trikeshed.size %xs : !s
  %ng = trikeshed.size %ex : !s
  %ids = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %r32 = arith.index_cast %i : index to i32
    trikeshed.yield %r32 : i32
  }
  %index, %ends = trikeshed.adjacency %codes, %ids over %ng : !s, !s -> !m, !s
  // two elements in one group when they are equal mod 3
  %mc, %me = trikeshed.groupBy %xs : !s -> !s, !s by {
  ^bb0(%a: i32, %b: i32):
    %three = arith.constant 3 : i32
    %ra = arith.remsi %a, %three : i32
    %rb = arith.remsi %b, %three : i32
    %lt = arith.cmpi slt, %ra, %rb : i32
    %gt = arith.cmpi sgt, %ra, %rb : i32
    %m1 = arith.constant -1 : i32
    %p1 = arith.constant 1 : i32
    %z = arith.constant 0 : i32
    %g = arith.select %gt, %p1, %z : i32
    %c = arith.select %lt, %m1, %g : i32
    trikeshed.yield %c : i32
  }
  %matches = trikeshed.keyedJoin %l, %r : !s, !s -> !m
  %firsts = trikeshed.alpha %matches : !m -> !s {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %counts = trikeshed.alpha %matches : !m -> !s {
  ^bb0(%p: !tp):
    %k = trikeshed.second %p : !tp -> i32
    trikeshed.yield %k : i32
  }
  %e0 = trikeshed.drain %codes, %o0 : !s, !out -> index
  %e1 = trikeshed.drain %ex, %o1 : !s, !out -> index
  %e2 = trikeshed.drain %oc, %o2 : !s, !out -> index
  %e3 = trikeshed.drain %oe, %o3 : !s, !out -> index
  %e4 = trikeshed.drain %ends, %o4 : !s, !out -> index
  %e5 = trikeshed.drain %mc, %o5 : !s, !out -> index
  %e6 = trikeshed.drain %me, %o6 : !s, !out -> index
  %e7 = trikeshed.drain %firsts, %o7 : !s, !out -> index
  %e8 = trikeshed.drain %counts, %o8 : !s, !out -> index
  return
}

memref.global "private" constant @xs : memref<7xi32> = dense<[5, 3, 5, 1, 3, 5, 7]>
memref.global "private" constant @l : memref<5xi32> = dense<[3, 4, 5, 0, 9]>
memref.global "private" constant @r : memref<5xi32> = dense<[1, 3, 3, 5, 7]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @print(%b: !out, %n: index) {
  %c0 = arith.constant 0 : index
  %v = memref.subview %b[0] [%n] [1] : !out to memref<?xi32, strided<[1]>>
  %copy = memref.alloc(%n) : !out
  memref.copy %v, %copy : memref<?xi32, strided<[1]>> to !out
  %u = memref.cast %copy : !out to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  memref.dealloc %copy : !out
  return
}

func.func @main() {
  %x7 = memref.get_global @xs : memref<7xi32>
  %l5 = memref.get_global @l : memref<5xi32>
  %r5 = memref.get_global @r : memref<5xi32>
  %x = memref.cast %x7 : memref<7xi32> to !out
  %lb = memref.cast %l5 : memref<5xi32> to !out
  %rb = memref.cast %r5 : memref<5xi32> to !out
  %xs = builtin.unrealized_conversion_cast %x : !out to !s
  %l = builtin.unrealized_conversion_cast %lb : !out to !s
  %r = builtin.unrealized_conversion_cast %rb : !out to !s
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c7 = arith.constant 7 : index
  %o0 = memref.alloc(%c7) : !out
  %o1 = memref.alloc(%c7) : !out
  %o2 = memref.alloc(%c7) : !out
  %o3 = memref.alloc(%c7) : !out
  %o4 = memref.alloc(%c7) : !out
  %o5 = memref.alloc(%c7) : !out
  %o6 = memref.alloc(%c7) : !out
  %o7 = memref.alloc(%c5) : !out
  %o8 = memref.alloc(%c5) : !out
  func.call @joins(%xs, %l, %r, %o0, %o1, %o2, %o3, %o4, %o5, %o6, %o7, %o8)
      : (!s, !s, !s, !out, !out, !out, !out, !out, !out, !out, !out, !out) -> ()
  func.call @print(%o0, %c7) : (!out, index) -> ()
  func.call @print(%o1, %c4) : (!out, index) -> ()
  func.call @print(%o2, %c7) : (!out, index) -> ()
  func.call @print(%o3, %c4) : (!out, index) -> ()
  func.call @print(%o4, %c7) : (!out, index) -> ()
  func.call @print(%o5, %c7) : (!out, index) -> ()
  func.call @print(%o6, %c3) : (!out, index) -> ()
  func.call @print(%o7, %c5) : (!out, index) -> ()
  func.call @print(%o8, %c5) : (!out, index) -> ()
  return
}
