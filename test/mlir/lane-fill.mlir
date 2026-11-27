// A lane filled in runs: trikeshed.drain of a series INTO a lane (Mutable.h appendAll: text written in pieces) makes the
// series' rows the lane's next rows, a page's run at a time, and gives the lane's size after them.  The lane is of bytes
// (4096 a page); the pieces are slices of 10000 source bytes, src[i] = the low byte of 7 i + 3, so that the runs begin
// and end at a page's first row, at its last, and inside it, and pass the frame's four pages:
//   nothing (0);  1 byte (1);  4094 (4095: a page less one);  one byte by trikeshed.append (4096: the page full);
//   1 byte (4097: a run that opens a page);  all 10000 (14097: two pages crossed);
//   combine(3 bytes, none, 1000) (15100): a view drains into a lane as into cells, its parts in turn;
//   combineAll of 40 slices of 200 + k bytes (23880: past the frame's directory), its region run once: a lane is not
//   sized ahead, so nothing adds the parts up first and no buffer is made for them;
//   a series of 300 computed bytes (24180).
// The same bytes are written beside it into plain cells; the lane, drained, must be those cells: 0 rows differ.  Then
// a lane of words (2048 a page): three appends, and 5000 rows drained into it from row 3 (5003; 0 rows differ).
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s

// ROUND: trikeshed.drain %{{.*}}, %{{.*}} : !trikeshed.series<i8>, !trikeshed.lane<i8> -> index

// The views drained into the lane: no buffer of bytes is made for a part or for the whole (the only allocations are
// the lane's own, a page and a directory), and nothing of them is left.
// LOWERED-LABEL: func.func private @fill_views(
// LOWERED-NOT: memref<?xi8>
// LOWERED: memref.alloc() {bufferization.manual_deallocation} : memref<4096xi8>
// LOWERED-NOT: memref<?xi8>
// LOWERED-LABEL: func.func private @fill_expect(
// LOWERED-NOT: trikeshed.

// CHECK: [0,  1,  4095,  4096,  4097,  14097,  15100,  23880,  24180,  0,  5003,  0]

!bytes = !trikeshed.lane<i8>
!words = !trikeshed.lane<i64>
!s8 = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>

// the two views, drained into the lane: (after the combine, after the combineAll)
func.func private @fill_views(%out: !bytes, %src: !s8) -> (index, index) {
  %c0 = arith.constant 0 : index
  %c3 = arith.constant 3 : index
  %c5 = arith.constant 5 : index
  %c37 = arith.constant 37 : index
  %c40 = arith.constant 40 : index
  %c200 = arith.constant 200 : index
  %c1000 = arith.constant 1000 : index
  %c9000 = arith.constant 9000 : index
  %a = trikeshed.slice %src[%c5, %c3] : !s8 -> !s8
  %none = trikeshed.slice %src[%c0, %c0] : !s8 -> !s8
  %b = trikeshed.slice %src[%c9000, %c1000] : !s8 -> !s8
  %three = trikeshed.combine %a, %none, %b : !s8, !s8, !s8 -> !s8
  %e1 = trikeshed.drain %three, %out : !s8, !bytes -> index
  %all, %where = trikeshed.combineAll %c40 : !s8, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k: index):
    %from = arith.muli %k, %c37 : index
    %len = arith.addi %k, %c200 : index
    %part = trikeshed.slice %src[%from, %len] : !s8 -> !s8
    trikeshed.yield %part : !s8
  }
  %e2 = trikeshed.drain %all, %out : !s8, !bytes -> index
  return %e1, %e2 : index, index
}

// the same pieces into plain cells: len bytes of src from off, at e; the next e
func.func private @fill_expect(%exp: memref<?xi8>, %e: index, %src: memref<?xi8>, %off: index, %len: index) -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  scf.for %i = %c0 to %len step %c1 {
    %from = arith.addi %off, %i : index
    %to = arith.addi %e, %i : index
    %x = memref.load %src[%from] : memref<?xi8>
    memref.store %x, %exp[%to] : memref<?xi8>
  }
  %r = arith.addi %e, %len : index
  return %r : index
}

// the low byte of 5 i + 1
func.func private @fill_byte(%i: index) -> i8 {
  %x = arith.index_cast %i : index to i64
  %c5 = arith.constant 5 : i64
  %c1 = arith.constant 1 : i64
  %m = arith.muli %x, %c5 : i64
  %a = arith.addi %m, %c1 : i64
  %b = arith.trunci %a : i64 to i8
  return %b : i8
}

func.func private @printMemrefI64(memref<*xi64>) attributes {llvm.emit_c_interface}

func.func @main() {
  %out = trikeshed.lane : !bytes
  %wide = trikeshed.lane : !words
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %c7 = arith.constant 7 : index
  %c8 = arith.constant 8 : index
  %c9 = arith.constant 9 : index
  %c10 = arith.constant 10 : index
  %c11 = arith.constant 11 : index
  %c37 = arith.constant 37 : index
  %c40 = arith.constant 40 : index
  %c100 = arith.constant 100 : index
  %c200 = arith.constant 200 : index
  %c300 = arith.constant 300 : index
  %c1000 = arith.constant 1000 : index
  %c4094 = arith.constant 4094 : index
  %c5000 = arith.constant 5000 : index
  %c9000 = arith.constant 9000 : index
  %n = arith.constant 10000 : index
  %total = arith.constant 24180 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %k7 = arith.constant 7 : i64
  %k3 = arith.constant 3 : i64
  // the source, and the cells the same pieces go to
  %buf = memref.alloc(%n) : memref<?xi8>
  scf.for %i = %c0 to %n step %c1 {
    %x = arith.index_cast %i : index to i64
    %m = arith.muli %x, %k7 : i64
    %a = arith.addi %m, %k3 : i64
    %b = arith.trunci %a : i64 to i8
    memref.store %b, %buf[%i] : memref<?xi8>
  }
  %src = trikeshed.text %buf : memref<?xi8> -> !s8
  %exp = memref.alloc(%total) : memref<?xi8>
  %sizes = memref.alloc() : memref<12xi64>
  // nothing; one byte; a page less one
  %p0 = trikeshed.slice %src[%c0, %c0] : !s8 -> !s8
  %s0 = trikeshed.drain %p0, %out : !s8, !bytes -> index
  %p1 = trikeshed.slice %src[%c0, %c1] : !s8 -> !s8
  %s1 = trikeshed.drain %p1, %out : !s8, !bytes -> index
  %p2 = trikeshed.slice %src[%c1, %c4094] : !s8 -> !s8
  %s2 = trikeshed.drain %p2, %out : !s8, !bytes -> index
  %x0 = func.call @fill_expect(%exp, %c0, %buf, %c0, %c1) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  %x1 = func.call @fill_expect(%exp, %x0, %buf, %c1, %c4094) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  // one row by append fills the page; the next run opens one
  %k85 = arith.constant 85 : i8
  %row = trikeshed.append %out, %k85 : !bytes, i8 -> index
  %s3 = trikeshed.size %out : !bytes
  memref.store %k85, %exp[%x1] : memref<?xi8>
  %x2 = arith.addi %x1, %c1 : index
  %p4 = trikeshed.slice %src[%c100, %c1] : !s8 -> !s8
  %s4 = trikeshed.drain %p4, %out : !s8, !bytes -> index
  %x3 = func.call @fill_expect(%exp, %x2, %buf, %c100, %c1) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  // the whole source: two pages crossed, ending inside the fourth
  %s5 = trikeshed.drain %src, %out : !s8, !bytes -> index
  %x4 = func.call @fill_expect(%exp, %x3, %buf, %c0, %n) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  // the views
  %s6, %s7 = func.call @fill_views(%out, %src) : (!bytes, !s8) -> (index, index)
  %x5 = func.call @fill_expect(%exp, %x4, %buf, %c5, %c3) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  %x6 = func.call @fill_expect(%exp, %x5, %buf, %c9000, %c1000) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
  %x7 = scf.for %k = %c0 to %c40 step %c1 iter_args(%e = %x6) -> (index) {
    %from = arith.muli %k, %c37 : index
    %len = arith.addi %k, %c200 : index
    %e2 = func.call @fill_expect(%exp, %e, %buf, %from, %len) : (memref<?xi8>, index, memref<?xi8>, index, index) -> index
    scf.yield %e2 : index
  }
  // a series of computed bytes
  %gen = trikeshed.series %c300 : !s8 {
  ^bb0(%i: index):
    %g = func.call @fill_byte(%i) : (index) -> i8
    trikeshed.yield %g : i8
  }
  %s8 = trikeshed.drain %gen, %out : !s8, !bytes -> index
  scf.for %i = %c0 to %c300 step %c1 {
    %g = func.call @fill_byte(%i) : (index) -> i8
    %to = arith.addi %x7, %i : index
    memref.store %g, %exp[%to] : memref<?xi8>
  }
  // the lane, drained, is those cells
  %got = trikeshed.drain %out : !bytes -> !s8
  %ngot = trikeshed.size %got : !s8
  %differ = scf.for %i = %c0 to %total step %c1 iter_args(%acc = %z) -> (i64) {
    %inside = arith.cmpi ult, %i, %ngot : index
    %d = scf.if %inside -> (i64) {
      %a = trikeshed.at %got[%i] : !s8, index -> i8
      %b = memref.load %exp[%i] : memref<?xi8>
      %ne = arith.cmpi ne, %a, %b : i8
      %w = arith.extui %ne : i1 to i64
      scf.yield %w : i64
    } else {
      scf.yield %one : i64
    }
    %next = arith.addi %acc, %d : i64
    scf.yield %next : i64
  }
  // words: three appends, then 5000 rows (i * i + 1) drained in from row 3
  %w11 = arith.constant 11 : i64
  %w22 = arith.constant 22 : i64
  %w33 = arith.constant 33 : i64
  %r0 = trikeshed.append %wide, %w11 : !words, i64 -> index
  %r1 = trikeshed.append %wide, %w22 : !words, i64 -> index
  %r2 = trikeshed.append %wide, %w33 : !words, i64 -> index
  %squares = trikeshed.series %c5000 : !s64 {
  ^bb0(%i: index):
    %x = arith.index_cast %i : index to i64
    %sq = arith.muli %x, %x : i64
    %v = arith.addi %sq, %one : i64
    trikeshed.yield %v : i64
  }
  %ws = trikeshed.drain %squares, %wide : !s64, !words -> index
  %wn = trikeshed.size %wide : !words
  %wdiffer = scf.for %i = %c0 to %wn step %c1 iter_args(%acc = %z) -> (i64) {
    %a = trikeshed.at %wide[%i] : !words, index -> i64
    %head = arith.cmpi ult, %i, %c3 : index
    %want = scf.if %head -> (i64) {
      %i1 = arith.addi %i, %c1 : index
      %h = arith.index_cast %i1 : index to i64
      %hv = arith.muli %h, %w11 : i64
      scf.yield %hv : i64
    } else {
      %j = arith.subi %i, %c3 : index
      %x = arith.index_cast %j : index to i64
      %sq = arith.muli %x, %x : i64
      %v = arith.addi %sq, %one : i64
      scf.yield %v : i64
    }
    %ne = arith.cmpi ne, %a, %want : i64
    %w = arith.extui %ne : i1 to i64
    %next = arith.addi %acc, %w : i64
    scf.yield %next : i64
  }
  %ends = arith.cmpi ne, %ws, %wn : index
  %endsw = arith.extui %ends : i1 to i64
  %wbad = arith.addi %wdiffer, %endsw : i64
  %v0 = arith.index_cast %s0 : index to i64
  %v1 = arith.index_cast %s1 : index to i64
  %v2 = arith.index_cast %s2 : index to i64
  %v3 = arith.index_cast %s3 : index to i64
  %v4 = arith.index_cast %s4 : index to i64
  %v5 = arith.index_cast %s5 : index to i64
  %v6 = arith.index_cast %s6 : index to i64
  %v7 = arith.index_cast %s7 : index to i64
  %v8 = arith.index_cast %s8 : index to i64
  %v10 = arith.index_cast %wn : index to i64
  memref.store %v0, %sizes[%c0] : memref<12xi64>
  memref.store %v1, %sizes[%c1] : memref<12xi64>
  memref.store %v2, %sizes[%c2] : memref<12xi64>
  memref.store %v3, %sizes[%c3] : memref<12xi64>
  memref.store %v4, %sizes[%c4] : memref<12xi64>
  memref.store %v5, %sizes[%c5] : memref<12xi64>
  memref.store %v6, %sizes[%c6] : memref<12xi64>
  memref.store %v7, %sizes[%c7] : memref<12xi64>
  memref.store %v8, %sizes[%c8] : memref<12xi64>
  memref.store %differ, %sizes[%c9] : memref<12xi64>
  memref.store %v10, %sizes[%c10] : memref<12xi64>
  memref.store %wbad, %sizes[%c11] : memref<12xi64>
  %u = memref.cast %sizes : memref<12xi64> to memref<*xi64>
  func.call @printMemrefI64(%u) : (memref<*xi64>) -> ()
  return
}
