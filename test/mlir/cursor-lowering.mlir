// The cursor lowering, run: a faceted query over a two-column cursor written in TrikeShed's ops, lowered by
// trikeshed-lower-cursors, taken to LLVM by the stock pipeline, executed.  The answers were worked by hand first:
//   a = [0, 1, 0, 2, 1, 0]   (codes 0..2, nothing selected)
//   b = [0, 0, 1, 1, 1, 0]   (codes 0..1, only 1 selected)
//   rows passing both: 2, 3, 4                              -> rows [2, 3, 4], total 3
//   a's counts over the rows b passes (2, 3, 4: a = 0, 2, 1) -> [1, 1, 1]
//   b's counts over the rows a passes (all six)               -> [3, 3]
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// LOWERED-LABEL: func.func @query(
// LOWERED-SAME: memref<?xi32, strided<[1], offset: ?>>, %{{.*}}: memref<?xi32, strided<[1], offset: ?>>, %{{.*}}: memref<?xi32, strided<[1], offset: ?>>, %{{.*}}: memref<?xi32, strided<[1], offset: ?>>
// LOWERED-NOT: trikeshed.
// LOWERED: scf.for
// LOWERED: memref.subview

// CHECK: [3]
// CHECK: [2,  3,  4]
// CHECK: [1,  1,  1]
// CHECK: [3,  3]

!cursor = !trikeshed.cursor<"T", [i32, i32]>
!col = !trikeshed.series<i32>
!key = !trikeshed.colkey<"T">

// Each row's passes as bits: 1 if a's code is selected, 2 if b's is.  A facet counts the rows that pass every other facet.
func.func @query(%c: !cursor, %selA: !col, %selB: !col, %outA: memref<?xi32>, %outB: memref<?xi32>, %rows: memref<?xi32>) -> index {
  %ka = trikeshed.key 0 : !key
  %kb = trikeshed.key 1 : !key
  %a = trikeshed.column %c[%ka] : !cursor, !key -> !col
  %b = trikeshed.column %c[%kb] : !cursor, !key -> !col
  %n = trikeshed.size %a : !col
  %ids = trikeshed.series %n : !col {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %bits = trikeshed.alpha %ids : !col -> !col {
  ^bb0(%r: i32):
    %zero = arith.constant 0 : i32
    %two = arith.constant 2 : i32
    %va = trikeshed.at %a[%r] : !col, i32 -> i32
    %sa = trikeshed.at %selA[%va] : !col, i32 -> i32
    %vb = trikeshed.at %b[%r] : !col, i32 -> i32
    %sb = trikeshed.at %selB[%vb] : !col, i32 -> i32
    %pa = arith.cmpi ne, %sa, %zero : i32
    %pb = arith.cmpi ne, %sb, %zero : i32
    %ba = arith.extui %pa : i1 to i32
    %eb = arith.extui %pb : i1 to i32
    %bb = arith.muli %eb, %two : i32
    %m = arith.ori %ba, %bb : i32
    trikeshed.yield %m : i32
  }
  // the rows that pass both
  %hits = trikeshed.where %ids : !col -> !col {
  ^bb0(%r: i32):
    %all = arith.constant 3 : i32
    %m = trikeshed.at %bits[%r] : !col, i32 -> i32
    %ok = arith.cmpi eq, %m, %all : i32
    trikeshed.yield %ok : i1
  }
  %total = trikeshed.drain %hits, %rows : !col, memref<?xi32> -> index
  // a's counts: the rows b passes, then a fold per code
  %countsA = trikeshed.facet %c[%ka] : !cursor, !key -> !col {
  ^bb0(%col: !col):
    %passB = trikeshed.where %ids : !col -> !col {
    ^bb0(%r: i32):
      %two = arith.constant 2 : i32
      %m = trikeshed.at %bits[%r] : !col, i32 -> i32
      %x = arith.andi %m, %two : i32
      %ok = arith.cmpi eq, %x, %two : i32
      trikeshed.yield %ok : i1
    }
    %codes = trikeshed.project %col[%passB] : !col, !col -> !col
    %nc = trikeshed.size %selA : !col
    %counts = trikeshed.series %nc : !col {
    ^bb0(%v: index):
      %vv = arith.index_cast %v : index to i32
      %zero = arith.constant 0 : i32
      %k = trikeshed.fold %codes, %zero : !col, i32 -> i32 {
      ^bb0(%acc: i32, %x: i32):
        %eq = arith.cmpi eq, %x, %vv : i32
        %one = arith.extui %eq : i1 to i32
        %next = arith.addi %acc, %one : i32
        trikeshed.yield %next : i32
      }
      trikeshed.yield %k : i32
    }
    trikeshed.yield %counts : !col
  }
  %ea = trikeshed.drain %countsA, %outA : !col, memref<?xi32> -> index
  // b's counts: the rows a passes
  %countsB = trikeshed.facet %c[%kb] : !cursor, !key -> !col {
  ^bb0(%col: !col):
    %passA = trikeshed.where %ids : !col -> !col {
    ^bb0(%r: i32):
      %one = arith.constant 1 : i32
      %m = trikeshed.at %bits[%r] : !col, i32 -> i32
      %x = arith.andi %m, %one : i32
      %ok = arith.cmpi eq, %x, %one : i32
      trikeshed.yield %ok : i1
    }
    %codes = trikeshed.project %col[%passA] : !col, !col -> !col
    %nc = trikeshed.size %selB : !col
    %counts = trikeshed.series %nc : !col {
    ^bb0(%v: index):
      %vv = arith.index_cast %v : index to i32
      %zero = arith.constant 0 : i32
      %k = trikeshed.fold %codes, %zero : !col, i32 -> i32 {
      ^bb0(%acc: i32, %x: i32):
        %eq = arith.cmpi eq, %x, %vv : i32
        %one = arith.extui %eq : i1 to i32
        %next = arith.addi %acc, %one : i32
        trikeshed.yield %next : i32
      }
      trikeshed.yield %k : i32
    }
    trikeshed.yield %counts : !col
  }
  %eb = trikeshed.drain %countsB, %outB : !col, memref<?xi32> -> index
  return %total : index
}

memref.global "private" constant @a : memref<6xi32> = dense<[0, 1, 0, 2, 1, 0]>
memref.global "private" constant @b : memref<6xi32> = dense<[0, 0, 1, 1, 1, 0]>
memref.global "private" constant @selA : memref<3xi32> = dense<[1, 1, 1]>
memref.global "private" constant @selB : memref<2xi32> = dense<[0, 1]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

func.func @main() {
  %a6 = memref.get_global @a : memref<6xi32>
  %b6 = memref.get_global @b : memref<6xi32>
  %sa3 = memref.get_global @selA : memref<3xi32>
  %sb2 = memref.get_global @selB : memref<2xi32>
  %a = memref.cast %a6 : memref<6xi32> to memref<?xi32>
  %b = memref.cast %b6 : memref<6xi32> to memref<?xi32>
  %sa = memref.cast %sa3 : memref<3xi32> to memref<?xi32>
  %sb = memref.cast %sb2 : memref<2xi32> to memref<?xi32>
  // the columns as the cursor and the selections as series: what the lowering takes apart again
  %c = builtin.unrealized_conversion_cast %a, %b : memref<?xi32>, memref<?xi32> to !cursor
  %selA = builtin.unrealized_conversion_cast %sa : memref<?xi32> to !col
  %selB = builtin.unrealized_conversion_cast %sb : memref<?xi32> to !col
  %c3 = arith.constant 3 : index
  %c2 = arith.constant 2 : index
  %c6 = arith.constant 6 : index
  %outA = memref.alloc(%c3) : memref<?xi32>
  %outB = memref.alloc(%c2) : memref<?xi32>
  %rows = memref.alloc(%c6) : memref<?xi32>
  %total = func.call @query(%c, %selA, %selB, %outA, %outB, %rows) : (!cursor, !col, !col, memref<?xi32>, memref<?xi32>, memref<?xi32>) -> index
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %t = memref.alloc(%c1) : memref<?xi32>
  %t32 = arith.index_cast %total : index to i32
  memref.store %t32, %t[%c0] : memref<?xi32>
  %ut = memref.cast %t : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%ut) : (memref<*xi32>) -> ()
  %hits = memref.subview %rows[0] [%total] [1] : memref<?xi32> to memref<?xi32, strided<[1]>>
  %hitsCopy = memref.alloc(%total) : memref<?xi32>
  memref.copy %hits, %hitsCopy : memref<?xi32, strided<[1]>> to memref<?xi32>
  %h = memref.cast %hitsCopy : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%h) : (memref<*xi32>) -> ()
  %ua = memref.cast %outA : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%ua) : (memref<*xi32>) -> ()
  %ub = memref.cast %outB : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%ub) : (memref<*xi32>) -> ()
  return
}
