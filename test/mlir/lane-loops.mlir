// A lane through the loops: a lane is a value like any other (its cells are its maker's frame's), so it is carried as
// an iter_arg of scf.for and scf.while, handed to the functions that fill it, and filled from a function of cf blocks
// with two returns, the pages going back before each.  Worked beside it:
//   scf.for over 0 ..< 5001 carrying two lanes that change places each turn: the evens land in a (2501 rows, sum
//     6252500), the odds in b (2500 rows, sum 6250000); what the loop gives back are b and a, in that order
//   scf.while carrying a lane and a step: step k appends k, and -k too when 3 divides k, until the lane holds 4100
//     rows: 3075 steps, the rows' sum 3151875
//   cf blocks: with no rows asked the function returns -1 from its first return; with 5000 it fills, drains and
//     folds: 12497500
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --lift-cf-to-scf --convert-ub-to-llvm --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// A lane carried by a loop is its cells carried: the count and the box.
// LOWERED-LABEL: func.func private @lane_swap(
// LOWERED: scf.for {{.*}} iter_args({{.*}}) -> (memref<1xindex>, memref<1xmemref<?xmemref<2048xi64>>>, memref<1xindex>, memref<1xmemref<?xmemref<2048xi64>>>) {
// LOWERED-LABEL: func.func private @lane_while(
// LOWERED: scf.while ({{.*}}) : (memref<1xindex>, memref<1xmemref<?xmemref<2048xi64>>>, index) -> (memref<1xindex>, memref<1xmemref<?xmemref<2048xi64>>>, index) {
// The pages go back before each of the two returns.
// LOWERED-LABEL: func.func private @lane_blocks(
// LOWERED: memref.dealloc %{{.*}} {bufferization.manual_deallocation} : memref<2048xi64>
// LOWERED: return %{{.*}} : i64
// LOWERED: memref.dealloc %{{.*}} {bufferization.manual_deallocation} : memref<2048xi64>
// LOWERED: return %{{.*}} : i64
// LOWERED-NOT: trikeshed.

// CHECK: [2501,  2500,  2500,  2501,  6252500,  6250000,  3075,  4100,  3151875,  -1,  12497500]

!lane = !trikeshed.lane<i64>
!s64 = !trikeshed.series<i64>

// the rows of a lane, added up: drained, then folded
func.func private @lane_sum(%l: !lane) -> i64 {
  %z = arith.constant 0 : i64
  %xs = trikeshed.drain %l : !lane -> !s64
  %sum = trikeshed.fold %xs, %z : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %next = arith.addi %acc, %x : i64
    trikeshed.yield %next : i64
  }
  return %sum : i64
}
func.func private @lane_count(%l: !lane) -> i64 {
  %n = trikeshed.size %l : !lane
  %n64 = arith.index_cast %n : index to i64
  return %n64 : i64
}

// two lanes through an scf.for, changing places each turn: out[0 ..< 6]
func.func private @lane_swap(%n: index, %out: memref<11xi64>) {
  %a = trikeshed.lane : !lane
  %b = trikeshed.lane : !lane
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %x, %y = scf.for %i = %c0 to %n step %c1 iter_args(%cur = %a, %other = %b) -> (!lane, !lane) {
    %v = arith.index_cast %i : index to i64
    %r = trikeshed.append %cur, %v : !lane, i64 -> index
    scf.yield %other, %cur : !lane, !lane
  }
  %na = func.call @lane_count(%a) : (!lane) -> i64
  %nb = func.call @lane_count(%b) : (!lane) -> i64
  %nx = func.call @lane_count(%x) : (!lane) -> i64
  %ny = func.call @lane_count(%y) : (!lane) -> i64
  %sa = func.call @lane_sum(%a) : (!lane) -> i64
  %sb = func.call @lane_sum(%b) : (!lane) -> i64
  memref.store %na, %out[%c0] : memref<11xi64>
  memref.store %nb, %out[%c1] : memref<11xi64>
  memref.store %nx, %out[%c2] : memref<11xi64>
  memref.store %ny, %out[%c3] : memref<11xi64>
  memref.store %sa, %out[%c4] : memref<11xi64>
  memref.store %sb, %out[%c5] : memref<11xi64>
  return
}

// a lane and a step through an scf.while, until the lane holds `limit` rows: out[6 ..< 9]
func.func private @lane_while(%limit: index, %out: memref<11xi64>) {
  %l = trikeshed.lane : !lane
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c3 = arith.constant 3 : index
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %c8 = arith.constant 8 : index
  %w, %steps = scf.while (%lane = %l, %k = %c0) : (!lane, index) -> (!lane, index) {
    %held = trikeshed.size %lane : !lane
    %more = arith.cmpi ult, %held, %limit : index
    scf.condition(%more) %lane, %k : !lane, index
  } do {
  ^bb0(%lane2: !lane, %k2: index):
    %v = arith.index_cast %k2 : index to i64
    %r = trikeshed.append %lane2, %v : !lane, i64 -> index
    %rem = arith.remui %k2, %c3 : index
    %third = arith.cmpi eq, %rem, %c0 : index
    scf.if %third {
      %z = arith.constant 0 : i64
      %neg = arith.subi %z, %v : i64
      %r2 = trikeshed.append %lane2, %neg : !lane, i64 -> index
    }
    %k3 = arith.addi %k2, %c1 : index
    scf.yield %lane2, %k3 : !lane, index
  }
  %steps64 = arith.index_cast %steps : index to i64
  %nw = func.call @lane_count(%w) : (!lane) -> i64
  %sw = func.call @lane_sum(%l) : (!lane) -> i64
  memref.store %steps64, %out[%c6] : memref<11xi64>
  memref.store %nw, %out[%c7] : memref<11xi64>
  memref.store %sw, %out[%c8] : memref<11xi64>
  return
}

// a lane in a function of blocks: one return before anything is appended, one after the fill
func.func private @lane_blocks(%n: index) -> i64 {
  %l = trikeshed.lane : !lane
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %none = arith.cmpi eq, %n, %c0 : index
  cf.cond_br %none, ^empty, ^fill(%c0 : index)
^empty:
  %m1 = arith.constant -1 : i64
  return %m1 : i64
^fill(%i: index):
  %v = arith.index_cast %i : index to i64
  %r = trikeshed.append %l, %v : !lane, i64 -> index
  %i1 = arith.addi %i, %c1 : index
  %more = arith.cmpi ult, %i1, %n : index
  cf.cond_br %more, ^fill(%i1 : index), ^done
^done:
  %sum = func.call @lane_sum(%l) : (!lane) -> i64
  return %sum : i64
}

func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

func.func @main() {
  %out = memref.alloc() : memref<11xi64>
  %n = arith.constant 5001 : index
  %limit = arith.constant 4100 : index
  %c0 = arith.constant 0 : index
  %c5000 = arith.constant 5000 : index
  %c9 = arith.constant 9 : index
  %c10 = arith.constant 10 : index
  func.call @lane_swap(%n, %out) : (index, memref<11xi64>) -> ()
  func.call @lane_while(%limit, %out) : (index, memref<11xi64>) -> ()
  %b0 = func.call @lane_blocks(%c0) : (index) -> i64
  %b1 = func.call @lane_blocks(%c5000) : (index) -> i64
  memref.store %b0, %out[%c9] : memref<11xi64>
  memref.store %b1, %out[%c10] : memref<11xi64>
  %u = memref.cast %out : memref<11xi64> to memref<*xi64>
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  return
}
