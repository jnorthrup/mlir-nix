// trikeshed.parts: Series.div, the lazy split (CharSeries.kt), lowered by trikeshed-lower-cursors and run.  A part is a
// (start, length) within the series split: "a/bc//d" (a constant read by trikeshed.text) at '/' is a, bc, the empty part
// between the two slashes, d; the slice "bc/" of it is bc and an empty last part (its starts are within the slice); an
// empty series is one empty part.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.parts %{{.*}}, %{{.*}} : <i8>, i8 -> <!trikeshed.twinpacked<i32>>

// "a/bc//d": starts, lengths
// CHECK: [0,  2,  5,  6]
// CHECK: [1,  2,  0,  1]
// its slice "bc/"
// CHECK: [0,  3]
// CHECK: [2,  0]
// an empty slice
// CHECK: [0]
// CHECK: [0]
// CHECK: 0

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>

memref.global "private" constant @path : memref<7xi8> = dense<[97, 47, 98, 99, 47, 47, 100]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %out = memref.alloc(%n) : memref<?xi32>
  %end = trikeshed.drain %xs, %out : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

// the parts of a text at a delimiter, printed as their starts, then their lengths
func.func private @show_parts(%t: !text, %d: i8) {
  %ps = trikeshed.parts %t, %d : !text, i8 -> !sp
  %starts = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %lengths = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%p: !tp):
    %c = trikeshed.second %p : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%starts) : (!s32) -> ()
  func.call @show(%lengths) : (!s32) -> ()
  return
}

func.func @main() -> i32 {
  %g = memref.get_global @path : memref<7xi8>
  %t = trikeshed.text %g : memref<7xi8> -> !text
  %slash = arith.constant 47 : i8
  func.call @show_parts(%t, %slash) : (!text, i8) -> ()
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c0 = arith.constant 0 : index
  %bc = trikeshed.slice %t[%c2, %c3] : !text -> !text
  %bcp = trikeshed.parts %bc, %slash : !text, i8 -> !sp
  %bcs = trikeshed.alpha %bcp : !sp -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %bcl = trikeshed.alpha %bcp : !sp -> !s32 {
  ^bb0(%p: !tp):
    %c = trikeshed.second %p : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%bcs) : (!s32) -> ()
  func.call @show(%bcl) : (!s32) -> ()
  %none = trikeshed.slice %t[%c3, %c0] : !text -> !text
  %np = trikeshed.parts %none, %slash : !text, i8 -> !sp
  %ns = trikeshed.alpha %np : !sp -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %nl = trikeshed.alpha %np : !sp -> !s32 {
  ^bb0(%p: !tp):
    %c = trikeshed.second %p : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%ns) : (!s32) -> ()
  func.call @show(%nl) : (!s32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
