// ReifiedSplitSeries2's ops (joins, leftOf, rightOf, reify, splitSelect, take) and Series.kt's zipWithNext (zipnext),
// lowered by trikeshed-lower-cursors and run; and a series read where it is made (keys at a row stride, searched).
// The answers, worked by hand:
//   xs = [3, 1, 4, 1, 5]: zipnext's left [3, 1, 4, 1], right [1, 4, 1, 5]; the rows i+1 whose pair differs: all four;
//     zipnext of [7, 7, 8] keeps row 2 only ([2]); zipnext of [] and of [9] are empty: sizes [0, 0]
//   s = reify(joins(xs, [10, 11, 12, 13, 14])): splitSelect(s, [4, 0, 2]) is left [5, 3, 4], right [14, 10, 12];
//     take(s, 3) as the left element (valueAt) is 1, take(s, 1) as the right one (rightAt, B = i64) is 11
//   joins(a, b) with b longer than a: rightOf has size(a): [2]
//   a cursor's take at a constant column is that column: [20, 21]
//   rows of width 3 words, keys [2, 5, 5, 9]: the key series is read in place by bisect (the upper bound of k, then
//     the row before it if its key is k): find 5 -> 2 (the last 5), 9 -> 3, 2 -> 0, 1 -> -1, 6 -> -1, 10 -> -1;
//     the lower bound of 5 in the rows from 1 on (a slice of the key series) -> 0, of 6 -> 2
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.zipnext %{{.*}} : <i32> -> <i32, i32>
// ROUND: trikeshed.splitSelect %{{.*}}[%{{.*}}] : <i32, i64>, <i32> -> <i32, i64>
// ROUND: trikeshed.take %{{.*}}[%{{.*}}] : !trikeshed.split<i32, i64> -> i64

// zipnext is two views of its series: no buffer, no loop of its own
// LOWERED-LABEL: func.func @zip(
// LOWERED-NOT: trikeshed.
// LOWERED: memref.subview %arg0[%{{.*}}] [%{{.*}}] [1]
// LOWERED-NEXT: memref.subview %arg0[%{{.*}}] [%{{.*}}] [1]
// the keys at a stride are never made: the search reads them where the rows lie
// LOWERED-LABEL: func.func @find(
// LOWERED-NOT: memref.alloc
// LOWERED: scf.while
// LOWERED: memref.load
// LOWERED: return

// CHECK: [3,  1,  4,  1]
// CHECK: [1,  4,  1,  5]
// CHECK: [1,  2,  3,  4]
// CHECK: [2]
// CHECK: [0,  0]
// CHECK: [5,  3,  4]
// CHECK: [14,  10,  12]
// CHECK: [1,  11]
// CHECK: [2]
// CHECK: [20,  21]
// CHECK: [2,  3,  0,  -1,  -1,  -1]
// CHECK: [0,  2]

!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!z = !trikeshed.series2<i32, i32>
!j = !trikeshed.series2<i32, i64>
!sp = !trikeshed.split<i32, i64>
!cursor = !trikeshed.cursor<"T", [i32, i32]>

memref.global "private" constant @xs : memref<5xi32> = dense<[3, 1, 4, 1, 5]>
memref.global "private" constant @twice : memref<3xi32> = dense<[7, 7, 8]>
memref.global "private" constant @one : memref<1xi32> = dense<[9]>
memref.global "private" constant @ys : memref<5xi64> = dense<[10, 11, 12, 13, 14]>
memref.global "private" constant @pick : memref<3xi32> = dense<[4, 0, 2]>
memref.global "private" constant @c0 : memref<2xi32> = dense<[20, 21]>
memref.global "private" constant @c1 : memref<2xi32> = dense<[30, 31]>
// four rows of three words, the key first
memref.global "private" constant @rows : memref<12xi32> = dense<[2, 100, 101, 5, 102, 103, 5, 104, 105, 9, 106, 107]>
memref.global "private" constant @probes : memref<6xi32> = dense<[5, 9, 2, 1, 6, 10]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func private @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %out = memref.alloc(%n) : memref<?xi32>
  %end = trikeshed.drain %xs, %out : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func private @show64(%xs: !s64) {
  %as32 = trikeshed.alpha %xs : !s64 -> !s32 {
  ^bb0(%x: i64):
    %y = arith.trunci %x : i64 to i32
    trikeshed.yield %y : i32
  }
  func.call @show(%as32) : (!s32) -> ()
  return
}

// the rows i + 1 whose pair (xs[i], xs[i + 1]) differs: uniqueFirst's test, in zipnext's two sides
func.func @zip(%xs: !s32) {
  %z = trikeshed.zipnext %xs : !s32 -> !z
  %l = trikeshed.leftOf %z : !z -> !s32
  %r = trikeshed.rightOf %z : !z -> !s32
  %n = trikeshed.size %l : !s32
  %idx = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %c1 = arith.constant 1 : index
    %k = arith.addi %i, %c1 : index
    %k32 = arith.index_cast %k : index to i32
    trikeshed.yield %k32 : i32
  }
  %kept = trikeshed.where %idx : !s32 -> !s32 {
  ^bb0(%k: i32):
    %c1 = arith.constant 1 : i32
    %i = arith.subi %k, %c1 : i32
    %a = trikeshed.at %l[%i] : !s32, i32 -> i32
    %b = trikeshed.at %r[%i] : !s32, i32 -> i32
    %d = arith.cmpi ne, %a, %b : i32
    trikeshed.yield %d : i1
  }
  func.call @show(%l) : (!s32) -> ()
  func.call @show(%r) : (!s32) -> ()
  func.call @show(%kept) : (!s32) -> ()
  return
}

func.func @zipKept(%xs: !s32) {
  %z = trikeshed.zipnext %xs : !s32 -> !z
  %l = trikeshed.leftOf %z : !z -> !s32
  %r = trikeshed.rightOf %z : !z -> !s32
  %n = trikeshed.size %l : !s32
  %idx = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %c1 = arith.constant 1 : index
    %k = arith.addi %i, %c1 : index
    %k32 = arith.index_cast %k : index to i32
    trikeshed.yield %k32 : i32
  }
  %kept = trikeshed.where %idx : !s32 -> !s32 {
  ^bb0(%k: i32):
    %c1 = arith.constant 1 : i32
    %i = arith.subi %k, %c1 : i32
    %a = trikeshed.at %l[%i] : !s32, i32 -> i32
    %b = trikeshed.at %r[%i] : !s32, i32 -> i32
    %d = arith.cmpi ne, %a, %b : i32
    trikeshed.yield %d : i1
  }
  func.call @show(%kept) : (!s32) -> ()
  return
}

func.func @sizes(%a: !s32, %b: !s32) {
  %za = trikeshed.zipnext %a : !s32 -> !z
  %zb = trikeshed.zipnext %b : !s32 -> !z
  %la = trikeshed.leftOf %za : !z -> !s32
  %rb = trikeshed.rightOf %zb : !z -> !s32
  %na = trikeshed.size %la : !s32
  %nb = trikeshed.size %rb : !s32
  %c2 = arith.constant 2 : index
  %out = trikeshed.series %c2 : !s32 {
  ^bb0(%i: index):
    %c0 = arith.constant 0 : index
    %first = arith.cmpi eq, %i, %c0 : index
    %v = arith.select %first, %na, %nb : index
    %v32 = arith.index_cast %v : index to i32
    trikeshed.yield %v32 : i32
  }
  func.call @show(%out) : (!s32) -> ()
  return
}

func.func @split(%xs: !s32, %ys: !s64, %pick: !s32) {
  %j = trikeshed.joins %xs, %ys : !s32, !s64 -> !j
  %s = trikeshed.reify %j : !j -> !sp
  %sel = trikeshed.splitSelect %s[%pick] : !sp, !s32 -> !sp
  %l = trikeshed.leftOf %sel : !sp -> !s32
  %r = trikeshed.rightOf %sel : !sp -> !s64
  %c1 = arith.constant 1 : index
  %c3 = arith.constant 3 : index
  %v = trikeshed.take %s[%c3] : !sp -> i32
  %w = trikeshed.take %s[%c1] : !sp -> i64
  %c2 = arith.constant 2 : index
  %t = trikeshed.series %c2 : !s32 {
  ^bb0(%i: index):
    %c0 = arith.constant 0 : index
    %first = arith.cmpi eq, %i, %c0 : index
    %w32 = arith.trunci %w : i64 to i32
    %e = arith.select %first, %v, %w32 : i32
    trikeshed.yield %e : i32
  }
  func.call @show(%l) : (!s32) -> ()
  func.call @show64(%r) : (!s64) -> ()
  func.call @show(%t) : (!s32) -> ()
  return
}

// joins keeps a's rows: b's side is viewed to size(a)
func.func @short(%a: !s32, %b: !s64) {
  %j = trikeshed.joins %a, %b : !s32, !s64 -> !j
  %r = trikeshed.rightOf %j : !j -> !s64
  %n = trikeshed.size %r : !s64
  %c1 = arith.constant 1 : index
  %out = trikeshed.series %c1 : !s32 {
  ^bb0(%i: index):
    %n32 = arith.index_cast %n : index to i32
    trikeshed.yield %n32 : i32
  }
  func.call @show(%out) : (!s32) -> ()
  return
}

func.func @column(%c: !cursor) {
  %c0 = arith.constant 0 : index
  %col = trikeshed.take %c[%c0] : !cursor -> !s32
  func.call @show(%col) : (!s32) -> ()
  return
}

// the row whose key is k among rows of w words sorted by key (the last such row), or -1: the keys are a series made
// where it is read, so the search reads log n keys and no buffer of keys is made
func.func @find(%words: !s32, %w: index, %k: i32) -> i32 {
  %nw = trikeshed.size %words : !s32
  %n = arith.divui %nw, %w : index
  %keys = trikeshed.series %n : !s32 {
  ^bb0(%r: index):
    %at = arith.muli %r, %w : index
    %key = trikeshed.at %words[%at] : !s32, index -> i32
    trikeshed.yield %key : i32
  }
  // the upper bound of k: an order that is never 0
  %ub = trikeshed.bisect %keys, %k : !s32, i32 -> index by {
  ^bb0(%x: i32, %key: i32):
    %le = arith.cmpi ule, %x, %key : i32
    %m1 = arith.constant -1 : i32
    %p1 = arith.constant 1 : i32
    %c = arith.select %le, %m1, %p1 : i32
    trikeshed.yield %c : i32
  }
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %ins = arith.subi %c0, %ub : index
  %ins1 = arith.subi %ins, %c1 : index
  %any = arith.cmpi ugt, %ins1, %c0 : index
  %r = scf.if %any -> i32 {
    %last = arith.subi %ins1, %c1 : index
    %key = trikeshed.at %keys[%last] : !s32, index -> i32
    %eq = arith.cmpi eq, %key, %k : i32
    %last32 = arith.index_cast %last : index to i32
    %m1 = arith.constant -1 : i32
    %v = arith.select %eq, %last32, %m1 : i32
    scf.yield %v : i32
  } else {
    %m1 = arith.constant -1 : i32
    scf.yield %m1 : i32
  }
  return %r : i32
}

// the lower bound of k among the keys of the rows from `from` on: a slice of the key series, still read in place
func.func @lower(%words: !s32, %w: index, %from: index, %k: i32) -> i32 {
  %nw = trikeshed.size %words : !s32
  %n = arith.divui %nw, %w : index
  %keys = trikeshed.series %n : !s32 {
  ^bb0(%r: index):
    %at = arith.muli %r, %w : index
    %key = trikeshed.at %words[%at] : !s32, index -> i32
    trikeshed.yield %key : i32
  }
  %rest = arith.subi %n, %from : index
  %tail = trikeshed.slice %keys[%from, %rest] : !s32 -> !s32
  %lb = trikeshed.bisect %tail, %k : !s32, i32 -> index by {
  ^bb0(%x: i32, %key: i32):
    %lt = arith.cmpi ult, %x, %key : i32
    %m1 = arith.constant -1 : i32
    %p1 = arith.constant 1 : i32
    %c = arith.select %lt, %m1, %p1 : i32
    trikeshed.yield %c : i32
  }
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %ins = arith.subi %c0, %lb : index
  %ins1 = arith.subi %ins, %c1 : index
  %r = arith.index_cast %ins1 : index to i32
  return %r : i32
}

func.func @main() {
  %gx = memref.get_global @xs : memref<5xi32>
  %bx = memref.cast %gx : memref<5xi32> to memref<?xi32>
  %xs = trikeshed.text %bx : memref<?xi32> -> !s32
  func.call @zip(%xs) : (!s32) -> ()
  %gt = memref.get_global @twice : memref<3xi32>
  %bt = memref.cast %gt : memref<3xi32> to memref<?xi32>
  %tw = trikeshed.text %bt : memref<?xi32> -> !s32
  func.call @zipKept(%tw) : (!s32) -> ()
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %empty = trikeshed.slice %xs[%c0, %c0] : !s32 -> !s32
  %g1 = memref.get_global @one : memref<1xi32>
  %b1 = memref.cast %g1 : memref<1xi32> to memref<?xi32>
  %one = trikeshed.text %b1 : memref<?xi32> -> !s32
  func.call @sizes(%empty, %one) : (!s32, !s32) -> ()
  %gy = memref.get_global @ys : memref<5xi64>
  %by = memref.cast %gy : memref<5xi64> to memref<?xi64>
  %ys = trikeshed.text %by : memref<?xi64> -> !s64
  %gp = memref.get_global @pick : memref<3xi32>
  %bp = memref.cast %gp : memref<3xi32> to memref<?xi32>
  %pick = trikeshed.text %bp : memref<?xi32> -> !s32
  func.call @split(%xs, %ys, %pick) : (!s32, !s64, !s32) -> ()
  %c2 = arith.constant 2 : index
  %two = trikeshed.slice %xs[%c0, %c2] : !s32 -> !s32
  func.call @short(%two, %ys) : (!s32, !s64) -> ()
  %gc0 = memref.get_global @c0 : memref<2xi32>
  %gc1 = memref.get_global @c1 : memref<2xi32>
  %bc0 = memref.cast %gc0 : memref<2xi32> to memref<?xi32>
  %bc1 = memref.cast %gc1 : memref<2xi32> to memref<?xi32>
  %cur = builtin.unrealized_conversion_cast %bc0, %bc1 : memref<?xi32>, memref<?xi32> to !cursor
  func.call @column(%cur) : (!cursor) -> ()
  %gr = memref.get_global @rows : memref<12xi32>
  %br = memref.cast %gr : memref<12xi32> to memref<?xi32>
  %words = trikeshed.text %br : memref<?xi32> -> !s32
  %gq = memref.get_global @probes : memref<6xi32>
  %bq = memref.cast %gq : memref<6xi32> to memref<?xi32>
  %probes = trikeshed.text %bq : memref<?xi32> -> !s32
  %c3 = arith.constant 3 : index
  %found = trikeshed.alpha %probes : !s32 -> !s32 {
  ^bb0(%k: i32):
    %f = func.call @find(%words, %c3, %k) : (!s32, index, i32) -> i32
    trikeshed.yield %f : i32
  }
  func.call @show(%found) : (!s32) -> ()
  %c5 = arith.constant 5 : i32
  %c6 = arith.constant 6 : i32
  %lb5 = func.call @lower(%words, %c3, %c1, %c5) : (!s32, index, index, i32) -> i32
  %lb6 = func.call @lower(%words, %c3, %c1, %c6) : (!s32, index, index, i32) -> i32
  %lbs = trikeshed.series %c2 : !s32 {
  ^bb0(%i: index):
    %first = arith.cmpi eq, %i, %c0 : index
    %v = arith.select %first, %lb5, %lb6 : i32
    trikeshed.yield %v : i32
  }
  func.call @show(%lbs) : (!s32) -> ()
  return
}
