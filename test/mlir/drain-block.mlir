// trikeshed.drain lowered by trikeshed-lower-cursors: a drain of plain elements is ONE block move, and the element
// loop stays only where the elements are not a block of bytes.
//   plain      a series of i64 into cells of unit stride: one llvm.intr.memmove between the two addresses (each
//              descriptor's aligned pointer and offset), size(xs) * 8 bytes, and no loop.  memmove, not memcpy: a
//              drain reads the series whole before it writes the cells (test/mlir/drain-run.mlir runs the overlaps)
//   bytes      i8 elements: the length is the count
//   view       a combine's drain is its parts' block moves in turn, each where the one before ended
//   made       a part that is a series of the cells' type is computed where it goes, element by element: its loop stays
//   strided    cells of another stride: the element loop
//   odd        elements whose bits are not whole bytes of value (i24): the element loop
//   constant counts (the FOLDED lines, after the pipeline's --canonicalize): a slice of a constant length, a series
//              of a constant size and a constant text reach the move as a constant length, which clang moves in registers
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --canonicalize | FileCheck %s --check-prefix=FOLDED

!s = !trikeshed.series<i64>
!b = !trikeshed.series<i8>
!m = memref<?xi64, strided<[1], offset: ?>>

// CHECK-LABEL: func.func @plain(
// CHECK-SAME:      %[[XS:.*]]: memref<?xi64, strided<[1], offset: ?>>, %[[INTO:.*]]: memref<?xi64>)
// CHECK-NOT:   scf.for
// CHECK:       %[[N:.*]] = memref.dim %[[XS]], %{{.*}}
// CHECK:       %[[SA:.*]] = memref.extract_aligned_pointer_as_index %[[XS]]
// CHECK:       %[[SW:.*]] = arith.index_castui %[[SA]] : index to i64
// CHECK:       %{{.*}}, %[[SO:.*]], %{{.*}}, %{{.*}} = memref.extract_strided_metadata %[[XS]]
// CHECK:       %[[SP:.*]] = llvm.inttoptr %[[SW]] : i64 to !llvm.ptr
// CHECK:       %[[SO64:.*]] = arith.index_cast %[[SO]] : index to i64
// CHECK:       %[[SRC:.*]] = llvm.getelementptr %[[SP]][%[[SO64]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
// CHECK:       %[[DA:.*]] = memref.extract_aligned_pointer_as_index %[[INTO]]
// CHECK:       %[[DW:.*]] = arith.index_castui %[[DA]] : index to i64
// CHECK:       %{{.*}}, %[[DO:.*]], %{{.*}}, %{{.*}} = memref.extract_strided_metadata %[[INTO]]
// CHECK:       %[[DP:.*]] = llvm.inttoptr %[[DW]] : i64 to !llvm.ptr
// CHECK:       %[[DO64:.*]] = arith.index_cast %[[DO]] : index to i64
// CHECK:       %[[DST:.*]] = llvm.getelementptr %[[DP]][%[[DO64]]] : (!llvm.ptr, i64) -> !llvm.ptr, i64
// CHECK:       %[[N64:.*]] = arith.index_cast %[[N]] : index to i64
// CHECK:       %[[EIGHT:.*]] = arith.constant 8 : i64
// CHECK:       %[[BYTES:.*]] = arith.muli %[[N64]], %[[EIGHT]] : i64
// CHECK:       "llvm.intr.memmove"(%[[DST]], %[[SRC]], %[[BYTES]]) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
// CHECK-NOT:   scf.for
// CHECK:       return %[[N]] : index
func.func @plain(%xs: !s, %into: memref<?xi64>) -> index {
  %e = trikeshed.drain %xs, %into : !s, memref<?xi64> -> index
  return %e : index
}

// CHECK-LABEL: func.func @bytes(
// CHECK-NOT:   scf.for
// CHECK:       %[[ONE:.*]] = arith.constant 1 : i64
// CHECK:       %[[BYTES:.*]] = arith.muli %{{.*}}, %[[ONE]] : i64
// CHECK:       "llvm.intr.memmove"(%{{.*}}, %{{.*}}, %[[BYTES]])
// CHECK-NOT:   scf.for
// CHECK:       return
// FOLDED-LABEL: func.func @bytes(
// FOLDED:       %[[N:.*]] = memref.dim
// FOLDED:       %[[N64:.*]] = arith.index_cast %[[N]] : index to i64
// FOLDED:       "llvm.intr.memmove"(%{{.*}}, %{{.*}}, %[[N64]])
func.func @bytes(%xs: !b, %into: memref<?xi8>) -> i32 {
  %e = trikeshed.drain %xs, %into : !b, memref<?xi8> -> i32
  return %e : i32
}

// CHECK-LABEL: func.func @view(
// CHECK-NOT:   scf.for
// CHECK:       "llvm.intr.memmove"
// CHECK-NOT:   scf.for
// CHECK:       "llvm.intr.memmove"
// CHECK-NOT:   scf.for
// CHECK:       return
func.func @view(%a: !s, %c: !s, %into: memref<?xi64>) -> index {
  %ac = trikeshed.combine %a, %c : !s, !s -> !s
  %e = trikeshed.drain %ac, %into : !s, memref<?xi64> -> index
  return %e : index
}

// CHECK-LABEL: func.func @made(
// CHECK:       "llvm.intr.memmove"
// CHECK:       scf.for %[[K:.*]] = %{{.*}} to %{{.*}} step
// CHECK:       %[[X:.*]] = arith.index_cast %[[K]] : index to i64
// CHECK:       memref.store %[[X]], %{{.*}}[%{{.*}}]
// CHECK-NOT:   "llvm.intr.memmove"
// CHECK:       return
func.func @made(%a: !s, %n: index, %into: memref<?xi64>) -> index {
  %ks = trikeshed.series %n : !s {
  ^bb0(%k: index):
    %x = arith.index_cast %k : index to i64
    trikeshed.yield %x : i64
  }
  %both = trikeshed.combine %a, %ks : !s, !s -> !s
  %e = trikeshed.drain %both, %into : !s, memref<?xi64> -> index
  return %e : index
}

// CHECK-LABEL: func.func @strided(
// CHECK-NOT:   "llvm.intr.memmove"
// CHECK:       scf.for %[[I:.*]] = %{{.*}} to %{{.*}} step
// CHECK:       %[[X:.*]] = memref.load %{{.*}}[%[[I]]] : memref<?xi64, strided<[1], offset: ?>>
// CHECK:       memref.store %[[X]], %{{.*}}[%[[I]]] : memref<?xi64, strided<[2], offset: ?>>
// CHECK-NOT:   "llvm.intr.memmove"
// CHECK:       return
func.func @strided(%xs: !s, %into: memref<?xi64, strided<[2], offset: ?>>) -> index {
  %e = trikeshed.drain %xs, %into : !s, memref<?xi64, strided<[2], offset: ?>> -> index
  return %e : index
}

// CHECK-LABEL: func.func @odd(
// CHECK-NOT:   "llvm.intr.memmove"
// CHECK:       scf.for %[[I:.*]] = %{{.*}} to %{{.*}} step
// CHECK:       %[[X:.*]] = memref.load %{{.*}}[%[[I]]] : memref<?xi24, strided<[1], offset: ?>>
// CHECK:       memref.store %[[X]], %{{.*}}[%[[I]]] : memref<?xi24>
// CHECK-NOT:   "llvm.intr.memmove"
// CHECK:       return
func.func @odd(%xs: !trikeshed.series<i24>, %into: memref<?xi24>) -> index {
  %e = trikeshed.drain %xs, %into : !trikeshed.series<i24>, memref<?xi24> -> index
  return %e : index
}

// a row of two words: a slice of a constant length into the cells at a constant place
// FOLDED-LABEL: func.func @two_words(
// FOLDED:       %[[C16:.*]] = arith.constant 16 : i64
// FOLDED-NOT:   arith.muli
// FOLDED:       "llvm.intr.memmove"(%{{.*}}, %{{.*}}, %[[C16]]) <{isVolatile = false}>
// FOLDED:       return
func.func @two_words(%xs: !s, %into: !m, %at: index) -> index {
  %c2 = arith.constant 2 : index
  %row = trikeshed.slice %xs[%at, %c2] : !s -> !s
  %cells = memref.subview %into[%c2] [%c2] [1] : !m to !m
  %e = trikeshed.drain %row, %cells : !s, !m -> index
  return %e : index
}

// a series of a constant size, made and then drained: 3 * 8 bytes
// FOLDED-LABEL: func.func @three_made(
// FOLDED:       %[[C24:.*]] = arith.constant 24 : i64
// FOLDED:       "llvm.intr.memmove"(%{{.*}}, %{{.*}}, %[[C24]]) <{isVolatile = false}>
// FOLDED:       return
func.func @three_made(%into: memref<?xi64>) -> index {
  %c3 = arith.constant 3 : index
  %ks = trikeshed.series %c3 : !s {
  ^bb0(%k: index):
    %x = arith.index_cast %k : index to i64
    trikeshed.yield %x : i64
  }
  %e = trikeshed.drain %ks, %into : !s, memref<?xi64> -> index
  return %e : index
}

// a constant text into cells of a static shape: 5 bytes
memref.global "private" constant @drain_word : memref<5xi8> = dense<[100, 114, 97, 105, 110]>
// FOLDED-LABEL: func.func @text(
// FOLDED:       %[[C5:.*]] = arith.constant 5 : i64
// FOLDED:       "llvm.intr.memmove"(%{{.*}}, %{{.*}}, %[[C5]]) <{isVolatile = false}>
// FOLDED:       return
func.func @text(%into: memref<8xi8>) -> index {
  %g = memref.get_global @drain_word : memref<5xi8>
  %t = trikeshed.text %g : memref<5xi8> -> !b
  %e = trikeshed.drain %t, %into : !b, memref<8xi8> -> index
  return %e : index
}
