// The self-tests that Laws.h (deleted by the tokenmax joins lane, 71eaf9c) ran at compile time, as MLIR: the Series laws
// are checked by running them.  Worked by hand (the values Laws.h used):
//   xs = [0, 10, 20];  inc x = x + 1;  dbl x = x * 2
//   project:  (xs α inc)[2] = 21, and the projection has xs's size, 3
//   fuse:     ((xs α inc) α dbl)[1] = (10 + 1) * 2 = 22      (α of α reads as α of the composition)
//   pair:     1 j 2: first = 1, second = 2
//   sum:      the fold of xs is 0 + 10 + 20 = 30
//   select:   a = [10, 30, 50], b = [20], sel = [0 j 0, 0 j 1, 1 j 0] (row j side): the rows are a[0], b[0], a[1]
//             = [10, 20, 30], size 3, sum 60.  trikeshed.select has no lowering (trikeshed-lower-cursors leaves it, and
//             no pattern has ever lowered it), so the select law is written as its law states it: a series of at.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --convert-bufferization-to-memref --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_c_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.alpha %{{.*}} : <i32> -> <i32>
// ROUND: trikeshed.j %{{.*}}, %{{.*}} : i32, i32 ->
// ROUND: trikeshed.fold %{{.*}}, %{{.*}} : <i32>, i32 -> i32

// CHECK: 3
// CHECK: 21
// CHECK: 22
// CHECK: 1
// CHECK: 2
// CHECK: 30
// CHECK: 3
// CHECK: 10
// CHECK: 20
// CHECK: 30
// CHECK: 60

!s = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>

memref.global "private" constant @xs : memref<3xi32> = dense<[0, 10, 20]>
memref.global "private" constant @a : memref<3xi32> = dense<[10, 30, 50]>
memref.global "private" constant @b : memref<1xi32> = dense<[20]>
memref.global "private" constant @selRow : memref<3xi32> = dense<[0, 0, 1]>
memref.global "private" constant @selSide : memref<3xi32> = dense<[0, 1, 0]>
func.func private @printI64(i64)
func.func private @printNewline()

func.func private @say(%x: i32) {
  %x64 = arith.extsi %x : i32 to i64
  func.call @printI64(%x64) : (i64) -> ()
  func.call @printNewline() : () -> ()
  return
}

func.func private @series_of(%g: memref<3xi32>) -> !s {
  %d = memref.cast %g : memref<3xi32> to memref<?xi32>
  %s = builtin.unrealized_conversion_cast %d : memref<?xi32> to !s
  return %s : !s
}

func.func @main() {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %dbl = arith.constant 2 : i32
  %zero = arith.constant 0 : i32

  %xs3 = memref.get_global @xs : memref<3xi32>
  %xsd = memref.cast %xs3 : memref<3xi32> to memref<?xi32>
  %xs = builtin.unrealized_conversion_cast %xsd : memref<?xi32> to !s

  // project: (xs α inc), its size and its element 2
  %p = trikeshed.alpha %xs : !s -> !s {
  ^bb0(%x: i32):
    %y = arith.addi %x, %one : i32
    trikeshed.yield %y : i32
  }
  %pn = trikeshed.size %p : !s
  %pn32 = arith.index_cast %pn : index to i32
  func.call @say(%pn32) : (i32) -> ()
  %p2 = trikeshed.at %p[%c2] : !s, index -> i32
  func.call @say(%p2) : (i32) -> ()

  // fuse: α of α is α of the composition, read at 1
  %f = trikeshed.alpha %p : !s -> !s {
  ^bb0(%x: i32):
    %y = arith.muli %x, %dbl : i32
    trikeshed.yield %y : i32
  }
  %f1 = trikeshed.at %f[%c1] : !s, index -> i32
  func.call @say(%f1) : (i32) -> ()

  // pair: 1 j 2
  %pr = trikeshed.j %one, %two : i32, i32 -> !tp
  %pf = trikeshed.first %pr : !tp -> i32
  %ps = trikeshed.second %pr : !tp -> i32
  func.call @say(%pf) : (i32) -> ()
  func.call @say(%ps) : (i32) -> ()

  // sum: the fold of xs
  %sum = trikeshed.fold %xs, %zero : !s, i32 -> i32 {
  ^bb0(%acc: i32, %x: i32):
    %next = arith.addi %acc, %x : i32
    trikeshed.yield %next : i32
  }
  func.call @say(%sum) : (i32) -> ()

  // select, as its law states it: row i of the result is a[r] when sel[i] = r j 0, else b[r], where sel[i] = (r, side)
  %as3 = memref.get_global @a : memref<3xi32>
  %as = func.call @series_of(%as3) : (memref<3xi32>) -> !s
  %bs1 = memref.get_global @b : memref<1xi32>
  %bd = memref.cast %bs1 : memref<1xi32> to memref<?xi32>
  %bs = builtin.unrealized_conversion_cast %bd : memref<?xi32> to !s
  %rowG = memref.get_global @selRow : memref<3xi32>
  %sideG = memref.get_global @selSide : memref<3xi32>
  %rows = func.call @series_of(%rowG) : (memref<3xi32>) -> !s
  %sides = func.call @series_of(%sideG) : (memref<3xi32>) -> !s
  %m = trikeshed.series %c3 : !s {
  ^bb0(%i: index):
    %r = trikeshed.at %rows[%i] : !s, index -> i32
    %sd = trikeshed.at %sides[%i] : !s, index -> i32
    %ri = arith.index_cast %r : i32 to index
    %isB = arith.cmpi ne, %sd, %zero : i32
    %v = scf.if %isB -> (i32) {
      %bv = trikeshed.at %bs[%ri] : !s, index -> i32
      scf.yield %bv : i32
    } else {
      %av = trikeshed.at %as[%ri] : !s, index -> i32
      scf.yield %av : i32
    }
    trikeshed.yield %v : i32
  }
  %mn = trikeshed.size %m : !s
  %mn32 = arith.index_cast %mn : index to i32
  func.call @say(%mn32) : (i32) -> ()
  %m0 = trikeshed.at %m[%c0] : !s, index -> i32
  func.call @say(%m0) : (i32) -> ()
  %m1 = trikeshed.at %m[%c1] : !s, index -> i32
  func.call @say(%m1) : (i32) -> ()
  %m2 = trikeshed.at %m[%c2] : !s, index -> i32
  func.call @say(%m2) : (i32) -> ()
  %msum = trikeshed.fold %m, %zero : !s, i32 -> i32 {
  ^bb0(%acc: i32, %x: i32):
    %next = arith.addi %acc, %x : i32
    trikeshed.yield %next : i32
  }
  func.call @say(%msum) : (i32) -> ()
  return
}
