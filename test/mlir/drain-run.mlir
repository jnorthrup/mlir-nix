// trikeshed.drain's block move, run (its forms are in test/mlir/drain-block.mlir).  A drain reads its series whole
// before it writes the cells, so the cells may lie over the series either way: the cases here are the ones where an
// element-by-element copy from the front would smear (the cells ahead of the series, inside it), or from the back
// (behind it), and they give memmove's answer.
//   overlaps   over 0..9: the cells 2 ahead, 1 ahead (the tightest: a forward loop would write ten 0s), 2 behind, in place
//   sizes      an empty series writes nothing and ends at 0; one element; the ends are the sizes
//   elements   i8, i16, i64, f64 and index, each moved ahead over itself, so a wrong byte count would show
//   pointers   a memref cannot hold !llvm.ptr: pointers travel as words (i64), and after a move over themselves the
//              words still point at what they pointed at
//   offsets    a slice of a slice into a subview of a subview: the offsets of both sides count
//   loops      what is not a block of plain elements still moves by the element loop: cells of stride 2, i24 elements
//
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// overlaps
// CHECK: [0,  1,  0,  1,  2,  3,  4,  5,  8,  9]
// CHECK: [0,  0,  1,  2,  3,  4,  5,  6,  7,  8]
// CHECK: [2,  3,  4,  5,  6,  7,  6,  7,  8,  9]
// CHECK: [0,  1,  2,  3,  4,  5,  6,  7,  8,  9]
// sizes: nothing written; one element; the ends of the six drains so far
// CHECK: [0,  1,  2,  3,  4,  5,  6,  7,  8,  9]
// CHECK: [9,  1,  2,  3,  4,  5,  6,  7,  8,  9]
// CHECK: [6,  9,  6,  4,  0,  1]
// elements: i8, i16, i64, f64, index
// CHECK: [200,  201,  200,  201,  202,  203]
// CHECK: [40000,  40001,  40000,  40001,  40002,  40003]
// CHECK: [4294967296,  8589934593,  4294967296,  8589934593,  12884901890,  17179869187]
// CHECK: [0.25,  1.25,  0.25,  1.25,  2.25,  3.25]
// CHECK: [1000,  1001,  1000,  1001,  1002,  1003]
// pointers: the words moved one ahead over themselves, then read through
// CHECK: [7,  7,  8,  9]
// offsets
// CHECK: [0,  1,  2,  3,  4,  5,  3,  4,  5,  9]
// loops: stride 2, i24
// CHECK: [0,  0,  1,  0,  2,  0,  3,  0,  4,  0]
// CHECK: [70002,  70003,  70004,  70005,  70004,  70005]
// CHECK: 0

!s32 = !trikeshed.series<i32>
!m32 = memref<?xi32, strided<[1], offset: ?>>

memref.global "private" constant @drain_vals : memref<4xi32> = dense<[7, 8, 9, 10]>

func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}
func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}
func.func private @printMemrefF64(memref<*xf64>) attributes {llvm.emit_c_interface}
func.func private @printMemrefInd(memref<*xindex>) attributes {llvm.emit_c_interface}

func.func private @show(%m: memref<?xi32>) {
  %u = memref.cast %m : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

// m[i] = i
func.func private @iota(%m: memref<?xi32>) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %n = memref.dim %m, %c0 : memref<?xi32>
  scf.for %i = %c0 to %n step %c1 {
    %x = arith.index_cast %i : index to i32
    memref.store %x, %m[%i] : memref<?xi32>
  }
  return
}

// 0..9, then its rows [from, count) drained into its own cells at `to`; shown; the drain's end
func.func private @over(%from: index, %count: index, %to: index) -> i32 {
  %c10 = arith.constant 10 : index
  %a = memref.alloc(%c10) : memref<?xi32>
  func.call @iota(%a) : (memref<?xi32>) -> ()
  %as = trikeshed.text %a : memref<?xi32> -> !s32
  %rows = trikeshed.slice %as[%from, %count] : !s32 -> !s32
  %cells = memref.subview %a[%to] [%count] [1] : memref<?xi32> to !m32
  %end = trikeshed.drain %rows, %cells : !s32, !m32 -> i32
  func.call @show(%a) : (memref<?xi32>) -> ()
  return %end : i32
}

func.func @main() -> i32 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %c9 = arith.constant 9 : index
  %c10 = arith.constant 10 : index

  // overlaps: 2 ahead, 1 ahead, 2 behind, in place; then an empty series (ahead) and one element
  %e0 = func.call @over(%c0, %c6, %c2) : (index, index, index) -> i32
  %e1 = func.call @over(%c0, %c9, %c1) : (index, index, index) -> i32
  %e2 = func.call @over(%c2, %c6, %c0) : (index, index, index) -> i32
  %e3 = func.call @over(%c3, %c4, %c3) : (index, index, index) -> i32
  %e4 = func.call @over(%c5, %c0, %c6) : (index, index, index) -> i32
  %e5 = func.call @over(%c9, %c1, %c0) : (index, index, index) -> i32
  %ends = memref.alloc(%c6) : memref<?xi32>
  memref.store %e0, %ends[%c0] : memref<?xi32>
  memref.store %e1, %ends[%c1] : memref<?xi32>
  memref.store %e2, %ends[%c2] : memref<?xi32>
  memref.store %e3, %ends[%c3] : memref<?xi32>
  memref.store %e4, %ends[%c4] : memref<?xi32>
  memref.store %e5, %ends[%c5] : memref<?xi32>
  func.call @show(%ends) : (memref<?xi32>) -> ()

  // i8: 200 + i, rows [0, 4) into the cells at 2; shown widened
  %b8 = memref.alloc(%c6) : memref<?xi8>
  scf.for %i = %c0 to %c6 step %c1 {
    %x = arith.index_cast %i : index to i8
    %k = arith.constant 200 : i8
    %y = arith.addi %x, %k : i8
    memref.store %y, %b8[%i] : memref<?xi8>
  }
  %s8 = trikeshed.text %b8 : memref<?xi8> -> !trikeshed.series<i8>
  %r8 = trikeshed.slice %s8[%c0, %c4] : !trikeshed.series<i8> -> !trikeshed.series<i8>
  %v8 = memref.subview %b8[%c2] [%c4] [1] : memref<?xi8> to memref<?xi8, strided<[1], offset: ?>>
  %x8 = trikeshed.drain %r8, %v8 : !trikeshed.series<i8>, memref<?xi8, strided<[1], offset: ?>> -> index
  %w8 = trikeshed.alpha %s8 : !trikeshed.series<i8> -> !s32 {
  ^bb0(%b: i8):
    %w = arith.extui %b : i8 to i32
    trikeshed.yield %w : i32
  }
  %o8 = memref.alloc(%c6) : memref<?xi32>
  %y8 = trikeshed.drain %w8, %o8 : !s32, memref<?xi32> -> index
  func.call @show(%o8) : (memref<?xi32>) -> ()

  // i16: 40000 + i
  %b16 = memref.alloc(%c6) : memref<?xi16>
  scf.for %i = %c0 to %c6 step %c1 {
    %x = arith.index_cast %i : index to i16
    %k = arith.constant 40000 : i16
    %y = arith.addi %x, %k : i16
    memref.store %y, %b16[%i] : memref<?xi16>
  }
  %s16 = trikeshed.text %b16 : memref<?xi16> -> !trikeshed.series<i16>
  %r16 = trikeshed.slice %s16[%c0, %c4] : !trikeshed.series<i16> -> !trikeshed.series<i16>
  %v16 = memref.subview %b16[%c2] [%c4] [1] : memref<?xi16> to memref<?xi16, strided<[1], offset: ?>>
  %x16 = trikeshed.drain %r16, %v16 : !trikeshed.series<i16>, memref<?xi16, strided<[1], offset: ?>> -> index
  %w16 = trikeshed.alpha %s16 : !trikeshed.series<i16> -> !s32 {
  ^bb0(%h: i16):
    %w = arith.extui %h : i16 to i32
    trikeshed.yield %w : i32
  }
  %o16 = memref.alloc(%c6) : memref<?xi32>
  %y16 = trikeshed.drain %w16, %o16 : !s32, memref<?xi32> -> index
  func.call @show(%o16) : (memref<?xi32>) -> ()

  // i64: (i + 1) * 2^32 + i, so every byte of a word counts
  %b64 = memref.alloc(%c6) : memref<?xi64>
  scf.for %i = %c0 to %c6 step %c1 {
    %x = arith.index_cast %i : index to i64
    %one = arith.constant 1 : i64
    %sh = arith.constant 32 : i64
    %x1 = arith.addi %x, %one : i64
    %hi = arith.shli %x1, %sh : i64
    %y = arith.ori %hi, %x : i64
    memref.store %y, %b64[%i] : memref<?xi64>
  }
  %s64 = trikeshed.text %b64 : memref<?xi64> -> !trikeshed.series<i64>
  %r64 = trikeshed.slice %s64[%c0, %c4] : !trikeshed.series<i64> -> !trikeshed.series<i64>
  %v64 = memref.subview %b64[%c2] [%c4] [1] : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
  %x64 = trikeshed.drain %r64, %v64 : !trikeshed.series<i64>, memref<?xi64, strided<[1], offset: ?>> -> index
  %u64 = memref.cast %b64 : memref<?xi64> to memref<*xi64>
  func.call @printMemrefI64(%u64) : (memref<*xi64>) -> ()

  // f64: i + 0.25
  %bf = memref.alloc(%c6) : memref<?xf64>
  scf.for %i = %c0 to %c6 step %c1 {
    %x = arith.index_cast %i : index to i64
    %f = arith.sitofp %x : i64 to f64
    %q = arith.constant 0.25 : f64
    %y = arith.addf %f, %q : f64
    memref.store %y, %bf[%i] : memref<?xf64>
  }
  %sf = trikeshed.text %bf : memref<?xf64> -> !trikeshed.series<f64>
  %rf = trikeshed.slice %sf[%c0, %c4] : !trikeshed.series<f64> -> !trikeshed.series<f64>
  %vf = memref.subview %bf[%c2] [%c4] [1] : memref<?xf64> to memref<?xf64, strided<[1], offset: ?>>
  %xf = trikeshed.drain %rf, %vf : !trikeshed.series<f64>, memref<?xf64, strided<[1], offset: ?>> -> index
  %uf = memref.cast %bf : memref<?xf64> to memref<*xf64>
  func.call @printMemrefF64(%uf) : (memref<*xf64>) -> ()

  // index: 1000 + i
  %bi = memref.alloc(%c6) : memref<?xindex>
  scf.for %i = %c0 to %c6 step %c1 {
    %k = arith.constant 1000 : index
    %y = arith.addi %i, %k : index
    memref.store %y, %bi[%i] : memref<?xindex>
  }
  %si = trikeshed.text %bi : memref<?xindex> -> !trikeshed.series<index>
  %ri = trikeshed.slice %si[%c0, %c4] : !trikeshed.series<index> -> !trikeshed.series<index>
  %vi = memref.subview %bi[%c2] [%c4] [1] : memref<?xindex> to memref<?xindex, strided<[1], offset: ?>>
  %xi = trikeshed.drain %ri, %vi : !trikeshed.series<index>, memref<?xindex, strided<[1], offset: ?>> -> index
  %ui = memref.cast %bi : memref<?xindex> to memref<*xindex>
  func.call @printMemrefInd(%ui) : (memref<*xindex>) -> ()

  // pointers as words: the addresses of @drain_vals' four cells, rows [0, 3) moved to the cells at 1, then each word
  // read as a pointer
  %g = memref.get_global @drain_vals : memref<4xi32>
  %gp = memref.extract_aligned_pointer_as_index %g : memref<4xi32> -> index
  %ps = memref.alloc(%c4) : memref<?xi64>
  scf.for %i = %c0 to %c4 step %c1 {
    %four = arith.constant 4 : index
    %off = arith.muli %i, %four : index
    %at = arith.addi %gp, %off : index
    %word = arith.index_cast %at : index to i64
    memref.store %word, %ps[%i] : memref<?xi64>
  }
  %pss = trikeshed.text %ps : memref<?xi64> -> !trikeshed.series<i64>
  %pr = trikeshed.slice %pss[%c0, %c3] : !trikeshed.series<i64> -> !trikeshed.series<i64>
  %pv = memref.subview %ps[%c1] [%c3] [1] : memref<?xi64> to memref<?xi64, strided<[1], offset: ?>>
  %px = trikeshed.drain %pr, %pv : !trikeshed.series<i64>, memref<?xi64, strided<[1], offset: ?>> -> index
  %pointees = memref.alloc(%c4) : memref<?xi32>
  scf.for %i = %c0 to %c4 step %c1 {
    %word = memref.load %ps[%i] : memref<?xi64>
    %p = llvm.inttoptr %word : i64 to !llvm.ptr
    %v = llvm.load %p : !llvm.ptr -> i32
    memref.store %v, %pointees[%i] : memref<?xi32>
  }
  func.call @show(%pointees) : (memref<?xi32>) -> ()

  // offsets on both sides: rows 3..5 (a slice of a slice) into the cells 6..8 (a subview of a subview)
  %a = memref.alloc(%c10) : memref<?xi32>
  func.call @iota(%a) : (memref<?xi32>) -> ()
  %as = trikeshed.text %a : memref<?xi32> -> !s32
  %mid = trikeshed.slice %as[%c2, %c7] : !s32 -> !s32
  %rows = trikeshed.slice %mid[%c1, %c3] : !s32 -> !s32
  %tail = memref.subview %a[%c4] [%c6] [1] : memref<?xi32> to !m32
  %cells = memref.subview %tail[%c2] [%c3] [1] : !m32 to !m32
  %xo = trikeshed.drain %rows, %cells : !s32, !m32 -> index
  func.call @show(%a) : (memref<?xi32>) -> ()

  // the element loop: every second cell of ten zeros takes 0..4
  %z = memref.alloc(%c10) : memref<?xi32>
  scf.for %i = %c0 to %c10 step %c1 {
    %zero = arith.constant 0 : i32
    memref.store %zero, %z[%i] : memref<?xi32>
  }
  %five = trikeshed.slice %as[%c0, %c5] : !s32 -> !s32
  %even = memref.subview %z[%c0] [%c5] [%c2] : memref<?xi32> to memref<?xi32, strided<[?], offset: ?>>
  %xe = trikeshed.drain %five, %even : !s32, memref<?xi32, strided<[?], offset: ?>> -> index
  func.call @show(%z) : (memref<?xi32>) -> ()

  // the element loop: i24 elements, 70000 + i, rows [2, 6) moved to the front (the loop stores from the front, so cells
  // behind the series are safe with it too)
  %b24 = memref.alloc(%c6) : memref<?xi24>
  scf.for %i = %c0 to %c6 step %c1 {
    %x = arith.index_cast %i : index to i24
    %k = arith.constant 70000 : i24
    %y = arith.addi %x, %k : i24
    memref.store %y, %b24[%i] : memref<?xi24>
  }
  %s24 = trikeshed.text %b24 : memref<?xi24> -> !trikeshed.series<i24>
  %r24 = trikeshed.slice %s24[%c2, %c4] : !trikeshed.series<i24> -> !trikeshed.series<i24>
  %v24 = memref.subview %b24[%c0] [%c4] [1] : memref<?xi24> to memref<?xi24, strided<[1], offset: ?>>
  %x24 = trikeshed.drain %r24, %v24 : !trikeshed.series<i24>, memref<?xi24, strided<[1], offset: ?>> -> index
  %w24 = trikeshed.alpha %s24 : !trikeshed.series<i24> -> !s32 {
  ^bb0(%t: i24):
    %w = arith.extui %t : i24 to i32
    trikeshed.yield %w : i32
  }
  %o24 = memref.alloc(%c6) : memref<?xi32>
  %y24 = trikeshed.drain %w24, %o24 : !s32, memref<?xi32> -> index
  func.call @show(%o24) : (memref<?xi32>) -> ()

  %ok = arith.constant 0 : i32
  return %ok : i32
}
