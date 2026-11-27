// A lane, run: MutableSeries.kt's series that takes appends, kept as cas/CursorTrie.kt's LaneTrie keeps a relation's rows
// (pages that never move, one published count), lowered by trikeshed-lower-cursors and executed.  Rows of 1, 8, 24 and
// 13 bytes (three columns of 8; and a column each of 1, 4 and 8, whose pages hold 4096, 4096 and 2048 rows), filled to
// 0, 1, a page less one, a page, a page and one, and ten pages and three rows (the frame's directory holds four pages:
// ten replace it twice).  Each fill is held to the laws of TrikeShed.td:
//   append gives the row's index, the size before it;  size is the rows appended;
//   at(l, i) is row i where it lies, before any drain;  take is one column over the same count;
//   drain makes one series of exactly the count, row for row;  drain into cells writes the same rows and gives the count.
// Each case prints its size and the number of laws it broke.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --cse | FileCheck %s --check-prefix=CSE
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.lane : <i8>
// ROUND: trikeshed.append %{{.*}}, %{{.*}} : <i8>, i8 -> index
// ROUND: trikeshed.at %{{.*}}[%{{.*}}] : !trikeshed.lane<i8>, index -> i8
// ROUND: trikeshed.drain %{{.*}} : !trikeshed.lane<i8> -> !trikeshed.series<i8>
// ROUND: trikeshed.drain %{{.*}}, %{{.*}} : !trikeshed.lane<i8>, memref<?xi8> -> index
// ROUND: trikeshed.take %{{.*}}[%{{.*}}] : !trikeshed.lane<i64, i64, i64> -> !trikeshed.lane<i64>

// size and at of a lane read what an append changes: either side of one they stay two (of a series they are pure, one).
// CSE-LABEL: func.func private @lane_reads(
// CSE: trikeshed.size
// CSE: trikeshed.at
// CSE: trikeshed.append
// CSE: trikeshed.size
// CSE: trikeshed.at
// CSE-LABEL: func.func private @lane_series_reads(
// CSE: trikeshed.size
// CSE-NOT: trikeshed.size
// CSE: return

// The count and a box a column, in the frame, with a first directory and the first page; a column's pages by its own
// width; the pages after the first allocated and given back by hand.
// LOWERED-LABEL: func.func private @lane_bytes(
// LOWERED: memref.alloca() : memref<1xindex>
// LOWERED: memref.alloca() : memref<1xmemref<?xmemref<4096xi8>>>
// LOWERED: memref.alloca() : memref<4xmemref<4096xi8>>
// LOWERED: memref.alloca() : memref<4096xi8>
// LOWERED: memref.alloc() {bufferization.manual_deallocation} : memref<4096xi8>
// LOWERED: memref.dealloc %{{.*}} {bufferization.manual_deallocation} : memref<4096xi8>
// LOWERED-LABEL: func.func private @lane_mixed(
// LOWERED-DAG: memref.alloca() : memref<1xmemref<?xmemref<4096xi8>>>
// LOWERED-DAG: memref.alloca() : memref<1xmemref<?xmemref<4096xi32>>>
// LOWERED-DAG: memref.alloca() : memref<1xmemref<?xmemref<2048xi64>>>
// LOWERED-NOT: trikeshed.

// bytes: 4096 rows a page
// CHECK: [0,  0,  1,  0,  4095,  0,  4096,  0,  4097,  0,  40963,  0]
// words: 2048 rows a page
// CHECK: [0,  0,  1,  0,  2047,  0,  2048,  0,  2049,  0,  20483,  0]
// rows of three words
// CHECK: [0,  0,  1,  0,  2047,  0,  2048,  0,  2049,  0,  20483,  0]
// rows of a byte, an i32 and a word: the columns' pages open at their own rows
// CHECK: [0,  0,  1,  0,  2047,  0,  2048,  0,  4097,  0,  40963,  0]

!bytes = !trikeshed.lane<i8>
!words = !trikeshed.lane<i64>
!ints = !trikeshed.lane<i32>
!rows = !trikeshed.lane<i64, i64, i64>
!mixed = !trikeshed.lane<i8, i32, i64>
!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>

// the size and the first row, before an append and after it
func.func private @lane_reads(%x: i64) -> (index, index, i64, i64) {
  %l = trikeshed.lane : !words
  %z = arith.constant 0 : index
  %r0 = trikeshed.append %l, %x : !words, i64 -> index
  %n0 = trikeshed.size %l : !words
  %a0 = trikeshed.at %l[%z] : !words, index -> i64
  %r1 = trikeshed.append %l, %x : !words, i64 -> index
  %n1 = trikeshed.size %l : !words
  %a1 = trikeshed.at %l[%z] : !words, index -> i64
  return %n0, %n1, %a0, %a1 : index, index, i64, i64
}
func.func private @lane_series_reads(%s: !s64) -> (index, index) {
  %n0 = trikeshed.size %s : !s64
  %n1 = trikeshed.size %s : !s64
  return %n0, %n1 : index, index
}

// row i of the bytes: the low byte of 7 i + 3
func.func private @lane_byte(%i: index) -> i8 {
  %x = arith.index_cast %i : index to i64
  %c7 = arith.constant 7 : i64
  %c3 = arith.constant 3 : i64
  %m = arith.muli %x, %c7 : i64
  %a = arith.addi %m, %c3 : i64
  %b = arith.trunci %a : i64 to i8
  return %b : i8
}
// row i of the words: i * i + 1
func.func private @lane_word(%i: index) -> i64 {
  %x = arith.index_cast %i : index to i64
  %one = arith.constant 1 : i64
  %sq = arith.muli %x, %x : i64
  %v = arith.addi %sq, %one : i64
  return %v : i64
}
// 1 when the two differ
func.func private @lane_ne(%a: i64, %b: i64) -> i64 {
  %ne = arith.cmpi ne, %a, %b : i64
  %w = arith.extui %ne : i1 to i64
  return %w : i64
}

// n rows of one byte: the size, and the laws broken
func.func private @lane_bytes(%n: index) -> (i64, i64) {
  %l = trikeshed.lane : !bytes
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %n64 = arith.index_cast %n : index to i64
  %empty = trikeshed.size %l : !bytes
  %e64 = arith.index_cast %empty : index to i64
  %b0 = func.call @lane_ne(%e64, %z) : (i64, i64) -> i64
  %b1 = scf.for %i = %c0 to %n step %c1 iter_args(%bad = %b0) -> (i64) {
    %v = func.call @lane_byte(%i) : (index) -> i8
    %r = trikeshed.append %l, %v : !bytes, i8 -> index
    %r64 = arith.index_cast %r : index to i64
    %i64 = arith.index_cast %i : index to i64
    %w = func.call @lane_ne(%r64, %i64) : (i64, i64) -> i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %size = trikeshed.size %l : !bytes
  %size64 = arith.index_cast %size : index to i64
  %b2 = scf.for %i = %c0 to %size step %c1 iter_args(%bad = %b1) -> (i64) {
    %v = func.call @lane_byte(%i) : (index) -> i8
    %got = trikeshed.at %l[%i] : !bytes, index -> i8
    %ne = arith.cmpi ne, %got, %v : i8
    %w = arith.extui %ne : i1 to i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %xs = trikeshed.drain %l : !bytes -> !s8
  %m = trikeshed.size %xs : !s8
  %m64 = arith.index_cast %m : index to i64
  %w3 = func.call @lane_ne(%m64, %n64) : (i64, i64) -> i64
  %b3 = arith.addi %b2, %w3 : i64
  %cells = memref.alloc(%n) : memref<?xi8>
  %end = trikeshed.drain %l, %cells : !bytes, memref<?xi8> -> index
  %end64 = arith.index_cast %end : index to i64
  %w4 = func.call @lane_ne(%end64, %n64) : (i64, i64) -> i64
  %b4 = arith.addi %b3, %w4 : i64
  %b5 = scf.for %i = %c0 to %m step %c1 iter_args(%bad = %b4) -> (i64) {
    %v = func.call @lane_byte(%i) : (index) -> i8
    %got = trikeshed.at %xs[%i] : !s8, index -> i8
    %cell = memref.load %cells[%i] : memref<?xi8>
    %ne = arith.cmpi ne, %got, %v : i8
    %ne2 = arith.cmpi ne, %cell, %v : i8
    %w = arith.extui %ne : i1 to i64
    %w2 = arith.extui %ne2 : i1 to i64
    %next0 = arith.addi %bad, %w : i64
    %next = arith.addi %next0, %w2 : i64
    scf.yield %next : i64
  }
  return %size64, %b5 : i64, i64
}

// n rows of one word
func.func private @lane_words(%n: index) -> (i64, i64) {
  %l = trikeshed.lane : !words
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %n64 = arith.index_cast %n : index to i64
  %empty = trikeshed.size %l : !words
  %e64 = arith.index_cast %empty : index to i64
  %b0 = func.call @lane_ne(%e64, %z) : (i64, i64) -> i64
  %b1 = scf.for %i = %c0 to %n step %c1 iter_args(%bad = %b0) -> (i64) {
    %v = func.call @lane_word(%i) : (index) -> i64
    %r = trikeshed.append %l, %v : !words, i64 -> index
    %r64 = arith.index_cast %r : index to i64
    %i64 = arith.index_cast %i : index to i64
    %w = func.call @lane_ne(%r64, %i64) : (i64, i64) -> i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %size = trikeshed.size %l : !words
  %size64 = arith.index_cast %size : index to i64
  %b2 = scf.for %i = %c0 to %size step %c1 iter_args(%bad = %b1) -> (i64) {
    %v = func.call @lane_word(%i) : (index) -> i64
    %got = trikeshed.at %l[%i] : !words, index -> i64
    %w = func.call @lane_ne(%got, %v) : (i64, i64) -> i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %xs = trikeshed.drain %l : !words -> !s64
  %m = trikeshed.size %xs : !s64
  %m64 = arith.index_cast %m : index to i64
  %w3 = func.call @lane_ne(%m64, %n64) : (i64, i64) -> i64
  %b3 = arith.addi %b2, %w3 : i64
  %cells = memref.alloc(%n) : memref<?xi64>
  %end = trikeshed.drain %l, %cells : !words, memref<?xi64> -> i64
  %w4 = func.call @lane_ne(%end, %n64) : (i64, i64) -> i64
  %b4 = arith.addi %b3, %w4 : i64
  %b5 = scf.for %i = %c0 to %m step %c1 iter_args(%bad = %b4) -> (i64) {
    %v = func.call @lane_word(%i) : (index) -> i64
    %got = trikeshed.at %xs[%i] : !s64, index -> i64
    %cell = memref.load %cells[%i] : memref<?xi64>
    %w = func.call @lane_ne(%got, %v) : (i64, i64) -> i64
    %w2 = func.call @lane_ne(%cell, %v) : (i64, i64) -> i64
    %next0 = arith.addi %bad, %w : i64
    %next = arith.addi %next0, %w2 : i64
    scf.yield %next : i64
  }
  return %size64, %b5 : i64, i64
}

// n rows of three words (i, i * i + 1, -i): a cursor's rows while they are filled, read and drained a column at a time
func.func private @lane_rows(%n: index) -> (i64, i64) {
  %l = trikeshed.lane : !rows
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %z = arith.constant 0 : i64
  %n64 = arith.index_cast %n : index to i64
  %b1 = scf.for %i = %c0 to %n step %c1 iter_args(%bad = %z) -> (i64) {
    %a = arith.index_cast %i : index to i64
    %b = func.call @lane_word(%i) : (index) -> i64
    %c = arith.subi %z, %a : i64
    %r = trikeshed.append %l, %a, %b, %c : !rows, i64, i64, i64 -> index
    %r64 = arith.index_cast %r : index to i64
    %w = func.call @lane_ne(%r64, %a) : (i64, i64) -> i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %as = trikeshed.take %l[%c0] : !rows -> !words
  %bs = trikeshed.take %l[%c1] : !rows -> !words
  %cs = trikeshed.take %l[%c2] : !rows -> !words
  %size = trikeshed.size %bs : !words
  %size64 = arith.index_cast %size : index to i64
  %b2 = scf.for %i = %c0 to %size step %c1 iter_args(%bad = %b1) -> (i64) {
    %a = arith.index_cast %i : index to i64
    %b = func.call @lane_word(%i) : (index) -> i64
    %c = arith.subi %z, %a : i64
    %ga = trikeshed.at %as[%i] : !words, index -> i64
    %gb = trikeshed.at %bs[%i] : !words, index -> i64
    %gc = trikeshed.at %cs[%i] : !words, index -> i64
    %wa = func.call @lane_ne(%ga, %a) : (i64, i64) -> i64
    %wb = func.call @lane_ne(%gb, %b) : (i64, i64) -> i64
    %wc = func.call @lane_ne(%gc, %c) : (i64, i64) -> i64
    %n0 = arith.addi %bad, %wa : i64
    %n1 = arith.addi %n0, %wb : i64
    %next = arith.addi %n1, %wc : i64
    scf.yield %next : i64
  }
  %xa = trikeshed.drain %as : !words -> !s64
  %xb = trikeshed.drain %bs : !words -> !s64
  %xc = trikeshed.drain %cs : !words -> !s64
  %m = trikeshed.size %xc : !s64
  %m64 = arith.index_cast %m : index to i64
  %w3 = func.call @lane_ne(%m64, %n64) : (i64, i64) -> i64
  %b3 = arith.addi %b2, %w3 : i64
  %b4 = scf.for %i = %c0 to %m step %c1 iter_args(%bad = %b3) -> (i64) {
    %a = arith.index_cast %i : index to i64
    %b = func.call @lane_word(%i) : (index) -> i64
    %c = arith.subi %z, %a : i64
    %ga = trikeshed.at %xa[%i] : !s64, index -> i64
    %gb = trikeshed.at %xb[%i] : !s64, index -> i64
    %gc = trikeshed.at %xc[%i] : !s64, index -> i64
    %wa = func.call @lane_ne(%ga, %a) : (i64, i64) -> i64
    %wb = func.call @lane_ne(%gb, %b) : (i64, i64) -> i64
    %wc = func.call @lane_ne(%gc, %c) : (i64, i64) -> i64
    %n0 = arith.addi %bad, %wa : i64
    %n1 = arith.addi %n0, %wb : i64
    %next = arith.addi %n1, %wc : i64
    scf.yield %next : i64
  }
  return %size64, %b4 : i64, i64
}

// n rows of a byte, an i32 and a word: a page of the bytes and of the i32s is 4096 rows, of the words 2048
func.func private @lane_mixed(%n: index) -> (i64, i64) {
  %l = trikeshed.lane : !mixed
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %z = arith.constant 0 : i64
  %n64 = arith.index_cast %n : index to i64
  %b1 = scf.for %i = %c0 to %n step %c1 iter_args(%bad = %z) -> (i64) {
    %a = func.call @lane_byte(%i) : (index) -> i8
    %b = arith.index_cast %i : index to i32
    %c = func.call @lane_word(%i) : (index) -> i64
    %r = trikeshed.append %l, %a, %b, %c : !mixed, i8, i32, i64 -> index
    %ne = arith.cmpi ne, %r, %i : index
    %w = arith.extui %ne : i1 to i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  %as = trikeshed.take %l[%c0] : !mixed -> !bytes
  %bs = trikeshed.take %l[%c1] : !mixed -> !ints
  %cs = trikeshed.take %l[%c2] : !mixed -> !words
  %size = trikeshed.size %l : !mixed
  %size64 = arith.index_cast %size : index to i64
  %xa = trikeshed.drain %as : !bytes -> !s8
  %xb = trikeshed.drain %bs : !ints -> !s32
  %xc = trikeshed.drain %cs : !words -> !s64
  %m = trikeshed.size %xa : !s8
  %m64 = arith.index_cast %m : index to i64
  %w3 = func.call @lane_ne(%m64, %n64) : (i64, i64) -> i64
  %b3 = arith.addi %b1, %w3 : i64
  %b4 = scf.for %i = %c0 to %size step %c1 iter_args(%bad = %b3) -> (i64) {
    %a = func.call @lane_byte(%i) : (index) -> i8
    %b = arith.index_cast %i : index to i32
    %c = func.call @lane_word(%i) : (index) -> i64
    %ga = trikeshed.at %as[%i] : !bytes, index -> i8
    %gb = trikeshed.at %bs[%i] : !ints, index -> i32
    %gc = trikeshed.at %cs[%i] : !words, index -> i64
    %da = trikeshed.at %xa[%i] : !s8, index -> i8
    %db = trikeshed.at %xb[%i] : !s32, index -> i32
    %dc = trikeshed.at %xc[%i] : !s64, index -> i64
    %ea = arith.cmpi ne, %ga, %a : i8
    %eb = arith.cmpi ne, %gb, %b : i32
    %ec = arith.cmpi ne, %gc, %c : i64
    %fa = arith.cmpi ne, %da, %a : i8
    %fb = arith.cmpi ne, %db, %b : i32
    %fc = arith.cmpi ne, %dc, %c : i64
    %o1 = arith.ori %ea, %eb : i1
    %o2 = arith.ori %ec, %fa : i1
    %o3 = arith.ori %fb, %fc : i1
    %o4 = arith.ori %o1, %o2 : i1
    %o5 = arith.ori %o4, %o3 : i1
    %w = arith.extui %o5 : i1 to i64
    %next = arith.addi %bad, %w : i64
    scf.yield %next : i64
  }
  return %size64, %b4 : i64, i64
}

memref.global "private" constant @lane_bcounts : memref<6xi64> = dense<[0, 1, 4095, 4096, 4097, 40963]>
memref.global "private" constant @lane_wcounts : memref<6xi64> = dense<[0, 1, 2047, 2048, 2049, 20483]>
memref.global "private" constant @lane_mcounts : memref<6xi64> = dense<[0, 1, 2047, 2048, 4097, 40963]>
func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

func.func @main() {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c6 = arith.constant 6 : index
  %bc = memref.get_global @lane_bcounts : memref<6xi64>
  %wc = memref.get_global @lane_wcounts : memref<6xi64>
  %mc = memref.get_global @lane_mcounts : memref<6xi64>
  %out = memref.alloc() : memref<12xi64>
  %u = memref.cast %out : memref<12xi64> to memref<*xi64>
  scf.for %k = %c0 to %c6 step %c1 {
    %n64 = memref.load %bc[%k] : memref<6xi64>
    %n = arith.index_cast %n64 : i64 to index
    %size, %bad = func.call @lane_bytes(%n) : (index) -> (i64, i64)
    %k2 = arith.muli %k, %c2 : index
    %k21 = arith.addi %k2, %c1 : index
    memref.store %size, %out[%k2] : memref<12xi64>
    memref.store %bad, %out[%k21] : memref<12xi64>
  }
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  scf.for %k = %c0 to %c6 step %c1 {
    %n64 = memref.load %wc[%k] : memref<6xi64>
    %n = arith.index_cast %n64 : i64 to index
    %size, %bad = func.call @lane_words(%n) : (index) -> (i64, i64)
    %k2 = arith.muli %k, %c2 : index
    %k21 = arith.addi %k2, %c1 : index
    memref.store %size, %out[%k2] : memref<12xi64>
    memref.store %bad, %out[%k21] : memref<12xi64>
  }
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  scf.for %k = %c0 to %c6 step %c1 {
    %n64 = memref.load %wc[%k] : memref<6xi64>
    %n = arith.index_cast %n64 : i64 to index
    %size, %bad = func.call @lane_rows(%n) : (index) -> (i64, i64)
    %k2 = arith.muli %k, %c2 : index
    %k21 = arith.addi %k2, %c1 : index
    memref.store %size, %out[%k2] : memref<12xi64>
    memref.store %bad, %out[%k21] : memref<12xi64>
  }
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  scf.for %k = %c0 to %c6 step %c1 {
    %n64 = memref.load %mc[%k] : memref<6xi64>
    %n = arith.index_cast %n64 : i64 to index
    %size, %bad = func.call @lane_mixed(%n) : (index) -> (i64, i64)
    %k2 = arith.muli %k, %c2 : index
    %k21 = arith.addi %k2, %c1 : index
    memref.store %size, %out[%k2] : memref<12xi64>
    memref.store %bad, %out[%k21] : memref<12xi64>
  }
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  return
}
