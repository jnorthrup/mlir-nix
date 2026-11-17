// Dictionary coding in TrikeShed's ops: a column of pieces of a text (!trikeshed.twinpacked<i32> (start, length))
// ordered by their bytes (trikeshed.sorted, its order an unsigned compare of two slices: Cursor.ordered), the place where
// each name's run starts (where: GroupBy.kt's groupClusters, whose first-occurrence order over ordered rows is the order
// of the names), each name's first row (project), and each row's code, its name's place among them (bisect).  The text
// holds UTF-8: unsigned, as Kotlin compares Chars, "é" (C3 A9) sorts after "z"; signed it would sort first.
// Expected values from a separate reader (Python, its sort stable as Kotlin's is):
//   pieces  kind é z kind "" Z éa a z zz é
//   order   4 5 7 0 3 2 8 9 1 10 6         ("" Z a kind kind z z zz é é éa)
//   starts  0 1 2 3 5 7 8 10               names 4 5 7 0 2 9 1 6
//   codes   3 6 4 3 0 1 7 2 4 5 6          é against z: signed -1, unsigned 1
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.compare %{{.*}}, %{{.*}} unsigned : <i8>, <i8>
// ROUND: trikeshed.compare %{{.*}}, %{{.*}} : <i8>, <i8>

// CHECK: data =
// CHECK-NEXT: [4,  5,  7,  0,  3,  2,  8,  9,  1,  10,  6]
// CHECK: data =
// CHECK-NEXT: [0,  1,  2,  3,  5,  7,  8,  10]
// CHECK: data =
// CHECK-NEXT: [4,  5,  7,  0,  2,  9,  1,  6]
// CHECK: data =
// CHECK-NEXT: [3,  6,  4,  3,  0,  1,  7,  2,  4,  5,  6]
// CHECK: data =
// CHECK-NEXT: [-1,  1]

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>

memref.global "private" constant @text : memref<18xi8> = dense<[107, 105, 110, 100, -61, -87, 122, 107, 105, 110, 100, 90, -61, -87, 97, 97, 122, 122]>
memref.global "private" constant @pieces : memref<11xi64> = dense<[4, 17179869186, 25769803777, 30064771076, 47244640256, 47244640257, 51539607555, 64424509441, 68719476737, 68719476738, 51539607554]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %buf = memref.alloc(%n) : memref<?xi32>
  %e = trikeshed.drain %xs, %buf : !s32, memref<?xi32> -> index
  %u = memref.cast %buf : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

// the order of the pieces of two rows: their bytes, unsigned (a slice is a view, so it stays in the function that
// makes it: a function's result is a buffer its caller owns, and a view returned would be copied)
func.func @piece_order(%t: !text, %pieces: !pieces, %a: i32, %b: i32) -> i32 {
  %pa = trikeshed.at %pieces[%a] : !pieces, i32 -> !tp
  %pb = trikeshed.at %pieces[%b] : !pieces, i32 -> !tp
  %sa = trikeshed.first %pa : !tp -> i32
  %na = trikeshed.second %pa : !tp -> i32
  %sb = trikeshed.first %pb : !tp -> i32
  %nb = trikeshed.second %pb : !tp -> i32
  %sai = arith.index_cast %sa : i32 to index
  %nai = arith.index_cast %na : i32 to index
  %sbi = arith.index_cast %sb : i32 to index
  %nbi = arith.index_cast %nb : i32 to index
  %ba = trikeshed.slice %t[%sai, %nai] : !text -> !text
  %bb = trikeshed.slice %t[%sbi, %nbi] : !text -> !text
  %c = trikeshed.compare %ba, %bb unsigned : !text, !text
  return %c : i32
}

func.func @main() {
  %gt = memref.get_global @text : memref<18xi8>
  %gp = memref.get_global @pieces : memref<11xi64>
  %dt = memref.cast %gt : memref<18xi8> to memref<?xi8, strided<[1], offset: ?>>
  %dp = memref.cast %gp : memref<11xi64> to memref<?xi64, strided<[1], offset: ?>>
  %t = builtin.unrealized_conversion_cast %dt : memref<?xi8, strided<[1], offset: ?>> to !text
  %pieces = builtin.unrealized_conversion_cast %dp : memref<?xi64, strided<[1], offset: ?>> to !pieces
  %n = trikeshed.size %pieces : !pieces
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  // Cursor.ordered: the rows by their pieces' bytes, stable
  %order = trikeshed.sorted %rows : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %c = func.call @piece_order(%t, %pieces, %a, %b) : (!text, !pieces, i32, i32) -> i32
    trikeshed.yield %c : i32
  }
  // groupClusters over the ordered rows: a run starts where the piece differs from the one before it
  %starts = trikeshed.where %rows : !s32 -> !s32 {
  ^bb0(%i: i32):
    %zero = arith.constant 0 : i32
    %first = arith.cmpi eq, %i, %zero : i32
    %start = scf.if %first -> (i1) {
      %yes = arith.constant true
      scf.yield %yes : i1
    } else {
      %one = arith.constant 1 : i32
      %ip = arith.subi %i, %one : i32
      %r = trikeshed.at %order[%i] : !s32, i32 -> i32
      %rp = trikeshed.at %order[%ip] : !s32, i32 -> i32
      %c = func.call @piece_order(%t, %pieces, %rp, %r) : (!text, !pieces, i32, i32) -> i32
      %differs = arith.cmpi ne, %c, %zero : i32
      scf.yield %differs : i1
    }
    trikeshed.yield %start : i1
  }
  %names = trikeshed.project %order[%starts] : !s32, !s32 -> !s32
  // a row's code: its name's place among the names
  %codes = trikeshed.alpha %rows : !s32 -> !s32 {
  ^bb0(%r: i32):
    %at = trikeshed.bisect %names, %r : !s32, i32 -> index by {
    ^bb0(%x: i32, %key: i32):
      %c = func.call @piece_order(%t, %pieces, %x, %key) : (!text, !pieces, i32, i32) -> i32
      trikeshed.yield %c : i32
    }
    %code = arith.index_cast %at : index to i32
    trikeshed.yield %code : i32
  }
  func.call @show(%order) : (!s32) -> ()
  func.call @show(%starts) : (!s32) -> ()
  func.call @show(%names) : (!s32) -> ()
  func.call @show(%codes) : (!s32) -> ()
  // é against z, signed and unsigned
  %two = arith.constant 2 : index
  %cmps = trikeshed.series %two : !s32 {
  ^bb0(%i: index):
    %c4 = arith.constant 4 : index
    %c6 = arith.constant 6 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
    %e = trikeshed.slice %t[%c4, %c2] : !text -> !text
    %z = trikeshed.slice %t[%c6, %c1] : !text -> !text
    %s = trikeshed.compare %e, %z : !text, !text
    %u = trikeshed.compare %e, %z unsigned : !text, !text
    %i0 = arith.constant 0 : index
    %isS = arith.cmpi eq, %i, %i0 : index
    %v = arith.select %isS, %s, %u : i32
    trikeshed.yield %v : i32
  }
  func.call @show(%cmps) : (!s32) -> ()
  return
}
