// ↺ over a lane: trikeshed.anchor, Series.h's anchor(cells, i, mint).  The first force of a cell mints it, every read
// after is the constant the mint produced, and the mint may append to the very lane it anchors in (a lambda nested in a
// body defers a row of its own pool): the cell is found by its index again after the mint.  Here the lane holds 8192
// cells never forced (0), four pages, which fill the frame's directory, so the row the first mint appends opens a fifth
// page in a directory replaced under the anchor:
//   force(0)      mints: appends row 8192 (holding 100) and yields 7000 + 8192 = 15192; the size is 8193
//   force(0)      again: 15192, and nothing appended (8193)
//   force(8191)   mints: appends row 8193 (holding 8291), yields 15193; the size is 8194
//   the cells read back: 15192 at 0, 15193 at 8191, the appended 100 and 8291, and 0 at 5, never forced
//   a mint that takes no index: cell 7 is 5, and stays 5 under a second anchor whose mint would give 9
//   a mint that forces another cell: cell 20 is 501, cell 21 the 500 its mint yielded after appending row 8194 (8195)
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.anchor %{{.*}}[%{{.*}}] : <i64> -> i64 {

// The cell read, the mint only where it is 0, the minted value stored where the cell lies then.
// LOWERED-LABEL: func.func private @lane_force(
// LOWERED: %[[CELL:.*]] = memref.load %{{.*}} : memref<2048xi64>
// LOWERED: %[[FORCED:.*]] = arith.cmpi ne, %[[CELL]], %{{.*}} : i64
// LOWERED: scf.if %[[FORCED]] -> (i64) {
// LOWERED: scf.yield %[[CELL]] : i64
// LOWERED: } else {
// LOWERED: memref.store %{{.*}} : memref<1xindex>
// LOWERED: memref.store %[[MINT:.*]], %{{.*}} : memref<2048xi64>
// LOWERED: scf.yield %[[MINT]] : i64
// LOWERED-NOT: trikeshed.

// CHECK: [15192,  8193,  15192,  8193,  15193,  8194,  15192,  15193,  100,  8291,  0,  5,  5,  501,  500,  8195]

!cells = !trikeshed.lane<i64>

// cell i forced: its mint appends a row (holding i + 100) to the lane it anchors in, and yields 7000 + that row
func.func private @lane_force(%l: !cells, %i: index) -> i64 {
  %v = trikeshed.anchor %l[%i] : !cells -> i64 {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %c100 = arith.constant 100 : i64
    %held = arith.addi %k64, %c100 : i64
    %row = trikeshed.append %l, %held : !cells, i64 -> index
    %r64 = arith.index_cast %row : index to i64
    %base = arith.constant 7000 : i64
    %m = arith.addi %base, %r64 : i64
    trikeshed.yield %m : i64
  }
  return %v : i64
}

// cell i forced by a mint that takes no index and yields c
func.func private @lane_const(%l: !cells, %i: index, %c: i64) -> i64 {
  %v = trikeshed.anchor %l[%i] : !cells -> i64 {
    trikeshed.yield %c : i64
  }
  return %v : i64
}

// cell i forced by a mint that forces cell i + 1 (whose mint appends a row and yields 500) and yields one more
func.func private @lane_chain(%l: !cells, %i: index) -> i64 {
  %v = trikeshed.anchor %l[%i] : !cells -> i64 {
  ^bb0(%k: index):
    %one = arith.constant 1 : index
    %j = arith.addi %k, %one : index
    %inner = trikeshed.anchor %l[%j] : !cells -> i64 {
      %m1 = arith.constant -1 : i64
      %row = trikeshed.append %l, %m1 : !cells, i64 -> index
      %c500 = arith.constant 500 : i64
      trikeshed.yield %c500 : i64
    }
    %one64 = arith.constant 1 : i64
    %m = arith.addi %inner, %one64 : i64
    trikeshed.yield %m : i64
  }
  return %v : i64
}

func.func private @lane_size(%l: !cells) -> i64 {
  %n = trikeshed.size %l : !cells
  %n64 = arith.index_cast %n : index to i64
  return %n64 : i64
}

func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

func.func @main() {
  %l = trikeshed.lane : !cells
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %n = arith.constant 8192 : index
  scf.for %i = %c0 to %n step %c1 {
    %r = trikeshed.append %l, %z : !cells, i64 -> index
  }
  %out = memref.alloc() : memref<16xi64>
  %k5 = arith.constant 5 : index
  %k7 = arith.constant 7 : index
  %k20 = arith.constant 20 : index
  %k21 = arith.constant 21 : index
  %k8191 = arith.constant 8191 : index
  %k8192 = arith.constant 8192 : index
  %k8193 = arith.constant 8193 : index
  %five = arith.constant 5 : i64
  %nine = arith.constant 9 : i64
  %f1 = func.call @lane_force(%l, %c0) : (!cells, index) -> i64
  %s1 = func.call @lane_size(%l) : (!cells) -> i64
  %f2 = func.call @lane_force(%l, %c0) : (!cells, index) -> i64
  %s2 = func.call @lane_size(%l) : (!cells) -> i64
  %f3 = func.call @lane_force(%l, %k8191) : (!cells, index) -> i64
  %s3 = func.call @lane_size(%l) : (!cells) -> i64
  %a0 = trikeshed.at %l[%c0] : !cells, index -> i64
  %a8191 = trikeshed.at %l[%k8191] : !cells, index -> i64
  %a8192 = trikeshed.at %l[%k8192] : !cells, index -> i64
  %a8193 = trikeshed.at %l[%k8193] : !cells, index -> i64
  %a5 = trikeshed.at %l[%k5] : !cells, index -> i64
  %g1 = func.call @lane_const(%l, %k7, %five) : (!cells, index, i64) -> i64
  %g2 = func.call @lane_const(%l, %k7, %nine) : (!cells, index, i64) -> i64
  %h = func.call @lane_chain(%l, %k20) : (!cells, index) -> i64
  %a21 = trikeshed.at %l[%k21] : !cells, index -> i64
  %s4 = func.call @lane_size(%l) : (!cells) -> i64
  %o1 = arith.constant 1 : index
  %o2 = arith.constant 2 : index
  %o3 = arith.constant 3 : index
  %o4 = arith.constant 4 : index
  %o5 = arith.constant 5 : index
  %o6 = arith.constant 6 : index
  %o7 = arith.constant 7 : index
  %o8 = arith.constant 8 : index
  %o9 = arith.constant 9 : index
  %o10 = arith.constant 10 : index
  %o11 = arith.constant 11 : index
  %o12 = arith.constant 12 : index
  %o13 = arith.constant 13 : index
  %o14 = arith.constant 14 : index
  %o15 = arith.constant 15 : index
  memref.store %f1, %out[%c0] : memref<16xi64>
  memref.store %s1, %out[%o1] : memref<16xi64>
  memref.store %f2, %out[%o2] : memref<16xi64>
  memref.store %s2, %out[%o3] : memref<16xi64>
  memref.store %f3, %out[%o4] : memref<16xi64>
  memref.store %s3, %out[%o5] : memref<16xi64>
  memref.store %a0, %out[%o6] : memref<16xi64>
  memref.store %a8191, %out[%o7] : memref<16xi64>
  memref.store %a8192, %out[%o8] : memref<16xi64>
  memref.store %a8193, %out[%o9] : memref<16xi64>
  memref.store %a5, %out[%o10] : memref<16xi64>
  memref.store %g1, %out[%o11] : memref<16xi64>
  memref.store %g2, %out[%o12] : memref<16xi64>
  memref.store %h, %out[%o13] : memref<16xi64>
  memref.store %a21, %out[%o14] : memref<16xi64>
  memref.store %s4, %out[%o15] : memref<16xi64>
  %u = memref.cast %out : memref<16xi64> to memref<*xi64>
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  return
}
