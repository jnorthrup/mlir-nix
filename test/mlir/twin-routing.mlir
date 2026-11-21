// A pair's representation is a property of its type (TrikeShed.td, !trikeshed.twin): two halves that fit a machine word
// are one integer, the first half high; wider halves lie apart, and a series of them is two columns.  A float half is
// packed as its bits.  And where every read of a series of pairs takes one half, trikeshed-route-twins makes it a column a
// half instead, whatever the width.  The answers were worked by hand first:
//   weights: the 4-bit codes [0, 5, 10, 15] of one group, its (scale, bias) = (0.5, -2.0): code * scale + bias
//            -> [-2, 0.5, 3, 5.5]
//   bytes:   (k, 2k + 1) as twin<i8>, k = 0..3; first * 16 + second -> [1, 19, 37, 55]
//   wide:    (k * 2^40, k + 7) as twin<i64>, k = 0..2; (first >> 40) * 100 + second -> [7, 108, 209]; the slice [1, 2] of
//            it, its seconds -> [8, 9]
//   edges:   (governor, dependent) = (k, k + 10), k = 0..3, read a half at a time: the governors [0, 1, 2, 3], and the
//            dependents of the same series -> [10, 11, 12, 13]
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-route-twins | FileCheck %s --check-prefix=ROUTED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-route-twins --trikeshed-lower-cursors | FileCheck %s --check-prefix=BOTH
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s
// RUN: mlnix-opt %s --trikeshed-route-twins --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.j %{{.*}}, %{{.*}} : f32, f32 -> !trikeshed.twin<f32>
// ROUND: trikeshed.j %{{.*}}, %{{.*}} : i64, i64 -> !trikeshed.twin<i64>

// The laws of j: a pair made and taken apart again is never made.
// ROUTED-LABEL: func.func @laws(
// ROUTED-SAME: %[[a:.*]]: i32, %[[b:.*]]: i32, %[[p:.*]]: !trikeshed.twin<i32>)
// ROUTED-NEXT: return %[[a]], %[[b]], %[[p]]

// A series whose reads take both halves together stays a series of pairs; one read a half at a time is a column a half.
// ROUTED-LABEL: func.func @weights(
// ROUTED: trikeshed.series %{{.*}} : <!trikeshed.twin<f32>>
// ROUTED-LABEL: func.func @edges(
// ROUTED-NOT: twin
// ROUTED: trikeshed.series %{{.*}} : <i32>
// ROUTED-NOT: twin
// ROUTED: trikeshed.series %{{.*}} : <i32>
// ROUTED-NOT: twin
// ROUTED: return

// The width rule, through a call: generic code keeps the layout.
// LOWERED-NOT: trikeshed.
// LOWERED-LABEL: func.func @laws(
// LOWERED-SAME: i32, %{{.*}}: i32, %{{.*}}: i64) -> (i32, i32, i64)
// LOWERED-LABEL: func.func @dequantize(
// LOWERED-SAME: memref<?xi8, strided<[1], offset: ?>>, %{{.*}}: memref<?xi64, strided<[1], offset: ?>>) -> memref<?xf32, strided<[1], offset: ?>>
// LOWERED: arith.bitcast %{{.*}} : i32 to f32
// LOWERED-LABEL: func.func @narrow(
// LOWERED-SAME: memref<?xi16, strided<[1], offset: ?>>
// LOWERED-LABEL: func.func @bits(
// LOWERED-SAME: i1, %{{.*}}: i1) -> i2
// LOWERED-LABEL: func.func @shorts(
// LOWERED-SAME: i16, %{{.*}}: i16) -> i32
// LOWERED-LABEL: func.func @wide(
// LOWERED-SAME: memref<?xi64, strided<[1], offset: ?>>, %{{.*}}: memref<?xi64, strided<[1], offset: ?>>) -> memref<?xi32, strided<[1], offset: ?>>
// LOWERED-LABEL: func.func @edges(
// LOWERED: memref.alloc(%{{.*}}) : memref<?xi64>

// Routed first, the edges are never packed: two i32 columns, and no shift to take a half out again.
// BOTH-NOT: trikeshed.
// BOTH-LABEL: func.func @edges(
// BOTH-NOT: memref<?xi64>
// BOTH-NOT: arith.shrui
// BOTH: return

// CHECK: data =
// CHECK-NEXT: [-2,  0.5,  3,  5.5]
// CHECK: data =
// CHECK-NEXT: [1,  19,  37,  55]
// CHECK: data =
// CHECK-NEXT: [7,  108,  209]
// CHECK: data =
// CHECK-NEXT: [8,  9]
// CHECK: data =
// CHECK-NEXT: [0,  1,  2,  3]
// CHECK: data =
// CHECK-NEXT: [10,  11,  12,  13]

!s32 = !trikeshed.series<i32>
!sf = !trikeshed.series<f32>
!codes = !trikeshed.series<i8>
!tf = !trikeshed.twin<f32>
!t8 = !trikeshed.twin<i8>
!t32 = !trikeshed.twin<i32>
!t64 = !trikeshed.twin<i64>

func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}
func.func private @printMemrefF32(memref<*xf32>) attributes {llvm.emit_c_interface}

func.func @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %buf = memref.alloc(%n) : memref<?xi32>
  %e = trikeshed.drain %xs, %buf : !s32, memref<?xi32> -> index
  %u = memref.cast %buf : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func @laws(%a: i32, %b: i32, %p: !t32) -> (i32, i32, !t32) {
  %ab = trikeshed.j %a, %b : i32, i32 -> !t32
  %x = trikeshed.first %ab : !t32 -> i32
  %y = trikeshed.second %ab : !t32 -> i32
  %pa = trikeshed.first %p : !t32 -> i32
  %pb = trikeshed.second %p : !t32 -> i32
  %q = trikeshed.j %pa, %pb : i32, i32 -> !t32
  return %x, %y, %q : i32, i32, !t32
}

// The 4-bit weights: each code times its group's scale, plus its bias.  Both halves are read together: one load.
func.func @dequantize(%codes: !codes, %groups: !trikeshed.series<!tf>) -> !sf {
  %c0 = arith.constant 0 : index
  %out = trikeshed.alpha %codes : !codes -> !sf {
  ^bb0(%code: i8):
    %g = trikeshed.at %groups[%c0] : !trikeshed.series<!tf>, index -> !tf
    %scale = trikeshed.first %g : !tf -> f32
    %bias = trikeshed.second %g : !tf -> f32
    %w = arith.uitofp %code : i8 to f32
    %m = arith.mulf %w, %scale : f32
    %v = arith.addf %m, %bias : f32
    trikeshed.yield %v : f32
  }
  return %out : !sf
}

func.func @weights() {
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %codes = trikeshed.series %c4 : !codes {
  ^bb0(%k: index):
    %k8 = arith.index_cast %k : index to i8
    %five = arith.constant 5 : i8
    %code = arith.muli %k8, %five : i8
    trikeshed.yield %code : i8
  }
  %groups = trikeshed.series %c1 : !trikeshed.series<!tf> {
  ^bb0(%k: index):
    %scale = arith.constant 0.5 : f32
    %bias = arith.constant -2.0 : f32
    %g = trikeshed.j %scale, %bias : f32, f32 -> !tf
    trikeshed.yield %g : !tf
  }
  %out = func.call @dequantize(%codes, %groups) : (!codes, !trikeshed.series<!tf>) -> !sf
  %buf = memref.alloc(%c4) : memref<?xf32>
  %e = trikeshed.drain %out, %buf : !sf, memref<?xf32> -> index
  %u = memref.cast %buf : memref<?xf32> to memref<*xf32>
  func.call @printMemrefF32(%u) : (memref<*xf32>) -> ()
  return
}

func.func @narrow(%xs: !trikeshed.series<!t8>) -> !s32 {
  %out = trikeshed.alpha %xs : !trikeshed.series<!t8> -> !s32 {
  ^bb0(%p: !t8):
    %a = trikeshed.first %p : !t8 -> i8
    %b = trikeshed.second %p : !t8 -> i8
    %a32 = arith.extui %a : i8 to i32
    %b32 = arith.extui %b : i8 to i32
    %c16 = arith.constant 16 : i32
    %hi = arith.muli %a32, %c16 : i32
    %v = arith.addi %hi, %b32 : i32
    trikeshed.yield %v : i32
  }
  return %out : !s32
}

func.func @bits(%a: i1, %b: i1) -> !trikeshed.twin<i1> {
  %p = trikeshed.j %a, %b : i1, i1 -> !trikeshed.twin<i1>
  return %p : !trikeshed.twin<i1>
}

func.func @shorts(%a: i16, %b: i16) -> !trikeshed.join<i16, i16> {
  %p = trikeshed.j %a, %b : i16, i16 -> !trikeshed.join<i16, i16>
  return %p : !trikeshed.join<i16, i16>
}

// Two i64 do not fit a word: the series is two columns, through the call.
func.func @wide(%xs: !trikeshed.series<!t64>) -> !s32 {
  %out = trikeshed.alpha %xs : !trikeshed.series<!t64> -> !s32 {
  ^bb0(%p: !t64):
    %a = trikeshed.first %p : !t64 -> i64
    %b = trikeshed.second %p : !t64 -> i64
    %c40 = arith.constant 40 : i64
    %c100 = arith.constant 100 : i64
    %k = arith.shrui %a, %c40 : i64
    %h = arith.muli %k, %c100 : i64
    %v = arith.addi %h, %b : i64
    %v32 = arith.trunci %v : i64 to i32
    trikeshed.yield %v32 : i32
  }
  return %out : !s32
}

func.func @seconds(%xs: !trikeshed.series<!t64>) -> !s32 {
  %n = trikeshed.size %xs : !trikeshed.series<!t64>
  %out = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %p = trikeshed.at %xs[%i] : !trikeshed.series<!t64>, index -> !t64
    %b = trikeshed.second %p : !t64 -> i64
    %b32 = arith.trunci %b : i64 to i32
    trikeshed.yield %b32 : i32
  }
  return %out : !s32
}

// Dependency edges, (governor, dependent): the two scans below each take one half.
func.func @edges() {
  %c4 = arith.constant 4 : index
  %edges = trikeshed.series %c4 : !trikeshed.series<!t32> {
  ^bb0(%k: index):
    %g = arith.index_cast %k : index to i32
    %ten = arith.constant 10 : i32
    %d = arith.addi %g, %ten : i32
    %e = trikeshed.j %g, %d : i32, i32 -> !t32
    trikeshed.yield %e : !t32
  }
  %governors = trikeshed.alpha %edges : !trikeshed.series<!t32> -> !s32 {
  ^bb0(%e: !t32):
    %g = trikeshed.first %e : !t32 -> i32
    trikeshed.yield %g : i32
  }
  %n = trikeshed.size %edges : !trikeshed.series<!t32>
  %dependents = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %e = trikeshed.at %edges[%i] : !trikeshed.series<!t32>, index -> !t32
    %d = trikeshed.second %e : !t32 -> i32
    trikeshed.yield %d : i32
  }
  func.call @show(%governors) : (!s32) -> ()
  func.call @show(%dependents) : (!s32) -> ()
  return
}

func.func @main() {
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  func.call @weights() : () -> ()

  %bytes = trikeshed.series %c4 : !trikeshed.series<!t8> {
  ^bb0(%k: index):
    %a = arith.index_cast %k : index to i8
    %one = arith.constant 1 : i8
    %two = arith.constant 2 : i8
    %a2 = arith.muli %a, %two : i8
    %b = arith.addi %a2, %one : i8
    %p = trikeshed.j %a, %b : i8, i8 -> !t8
    trikeshed.yield %p : !t8
  }
  %nb = func.call @narrow(%bytes) : (!trikeshed.series<!t8>) -> !s32
  func.call @show(%nb) : (!s32) -> ()

  %pairs = trikeshed.series %c3 : !trikeshed.series<!t64> {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %c40 = arith.constant 40 : i64
    %seven = arith.constant 7 : i64
    %a = arith.shli %k64, %c40 : i64
    %b = arith.addi %k64, %seven : i64
    %p = trikeshed.j %a, %b : i64, i64 -> !t64
    trikeshed.yield %p : !t64
  }
  %w = func.call @wide(%pairs) : (!trikeshed.series<!t64>) -> !s32
  func.call @show(%w) : (!s32) -> ()
  %tail = trikeshed.slice %pairs[%c1, %c2] : !trikeshed.series<!t64> -> !trikeshed.series<!t64>
  %ws = func.call @seconds(%tail) : (!trikeshed.series<!t64>) -> !s32
  func.call @show(%ws) : (!s32) -> ()

  func.call @edges() : () -> ()
  return
}
