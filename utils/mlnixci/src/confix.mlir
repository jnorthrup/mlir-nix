// confix.mlir -- the handle mlnixci passes around for a JSON text's index, and the reads it makes of it.  The index is
// src/index.mlir's: its cursor (ConfixIndexK's Spans, Tags and DirectChildren) and its kid series, read with trikeshed
// ops there.  Here are only the handle's buffers, seen as the cursor's columns, and the calls of index.mlir's readers on
// them: a reader makes the cursor from the handle's descriptors (each cast to its column's buffer, the three cast to the
// cursor) and calls index.mlir's function with it.  No read of an element is made in this file.  An element is a row; its
// coordinates are its span in the text; an object's children are its keys and values, alternating.  Nothing is decoded:
// a key is compared with the bytes it is written as.  ix_scan (the scan, which writes the handle's buffers) stays a C
// interface: the buffers are the scanner's allocations.

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)

// a buffer's descriptor (memref<?xT, strided<[1], offset: ?>>, as the LLVM lowering lays it out)
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
// the handle: ix_scan's results (the rows' span, tag and kids columns, the kid series, the fault), then the text
!h = !llvm.struct<(struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i32)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)>

// index.mlir's cursor and series, as its functions name them
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>

llvm.func @_mlir_ciface_ix_scan(!llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_ix_raw(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
llvm.func @_mlir_ciface_ix_str(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64

// index.mlir's readers (trikeshed ops over the cursor's columns)
func.func private @ix_rows(!ix) -> i64
func.func private @ix_tag(!ix, i64) -> i64
func.func private @ix_close(!ix, i64) -> i64
func.func private @ix_nkids(!ix, i64) -> i64
func.func private @ix_member(!ix, !s32, !text, i64, !text) -> i64
func.func private @ix_unterminated(!ix, !text) -> i64

func.func private @view(!llvm.ptr, !llvm.ptr, i64)

// the tags (Confix.td TagKind)
//   0 nothing (null)  1 boolean  2 long  3 double  4 string  5 object  6 array  7 bytes

// the handle's descriptors: 0 span, 1 tag, 2 kids (first, count), 3 the kid series (ix_scan's results come first in the
// handle, four descriptors in a row)
func.func @cx_d(%h: !llvm.ptr, %k: i32) -> !llvm.ptr {
  %ki = arith.extui %k : i32 to i64
  %p = llvm.getelementptr %h[%ki] : (!llvm.ptr, i64) -> !llvm.ptr, !d
  return %p : !llvm.ptr
}

func.func @cx_text(%h: !llvm.ptr) -> !llvm.ptr {
  %p = llvm.getelementptr %h[0, 1] : (!llvm.ptr) -> !llvm.ptr, !h
  return %p : !llvm.ptr
}

// the four descriptors of the handle's buffers (values: a function returns them; each is cast where a cursor is made)
func.func private @cx_descs(%h: !llvm.ptr) -> (!d, !d, !d, !d) {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %p0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %p1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %p2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %p3 = func.call @cx_d(%h, %c3) : (!llvm.ptr, i32) -> !llvm.ptr
  %d0 = llvm.load %p0 : !llvm.ptr -> !d
  %d1 = llvm.load %p1 : !llvm.ptr -> !d
  %d2 = llvm.load %p2 : !llvm.ptr -> !d
  %d3 = llvm.load %p3 : !llvm.ptr -> !d
  return %d0, %d1, %d2, %d3 : !d, !d, !d, !d
}

// a view of the n bytes at p, as a descriptor (a struct value; the caller casts it to memref<?xi8> and makes the text)
func.func private @cx_mview(%p: !llvm.ptr, %n: i64) -> !d {
  %one = arith.constant 1 : i32
  %d = llvm.alloca %one x !d : (i32) -> !llvm.ptr
  func.call @view(%d, %p, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %s = llvm.load %d : !llvm.ptr -> !d
  return %s : !d
}

// The index of the n bytes at text, or null when they are not JSON (or hold no element).
func.func @cx_scan(%text: !llvm.ptr, %n: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %z32 = arith.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %end = llvm.getelementptr %null[1] : (!llvm.ptr) -> !llvm.ptr, !h
  %size = llvm.ptrtoint %end : !llvm.ptr to i64
  %h = llvm.call @malloc(%size) : (i64) -> !llvm.ptr
  %td = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  func.call @view(%td, %text, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %res = llvm.getelementptr %h[0, 0] : (!llvm.ptr) -> !llvm.ptr, !h
  llvm.call @_mlir_ciface_ix_scan(%res, %td) : (!llvm.ptr, !llvm.ptr) -> ()
  %pf = llvm.getelementptr %h[0, 0, 4] : (!llvm.ptr) -> !llvm.ptr, !h
  %fault = llvm.load %pf : !llvm.ptr -> i32
  %total = func.call @cx_rows(%h) : (!llvm.ptr) -> i64
  %ok0 = arith.cmpi eq, %fault, %z32 : i32
  %some = arith.cmpi sgt, %total, %c0 : i64
  %ok = arith.andi %ok0, %some : i1
  %r = scf.if %ok -> (!llvm.ptr) {
    scf.yield %h : !llvm.ptr
  } else {
    func.call @cx_free(%h) : (!llvm.ptr) -> ()
    scf.yield %null : !llvm.ptr
  }
  return %r : !llvm.ptr
}

// the index's buffers (ix_scan made them; their first word is the allocation), then the handle
func.func @cx_free(%h: !llvm.ptr) {
  %null = llvm.mlir.zero : !llvm.ptr
  %isnull = llvm.icmp "eq" %h, %null : !llvm.ptr
  scf.if %isnull {
  } else {
    %c0 = arith.constant 0 : i32
    %c4 = arith.constant 4 : i32
    %c1 = arith.constant 1 : i32
    scf.for %k = %c0 to %c4 step %c1 : i32 {
      %d = func.call @cx_d(%h, %k) : (!llvm.ptr, i32) -> !llvm.ptr
      %a = llvm.load %d : !llvm.ptr -> !llvm.ptr
      llvm.call @free(%a) : (!llvm.ptr) -> ()
    }
    llvm.call @free(%h) : (!llvm.ptr) -> ()
  }
  return
}

// Each reader below makes the cursor from the handle's buffers (the span, tag and kids columns, cast to memrefs and the
// three to the cursor), and makes the kid series of the kid buffer where the reader takes one; then one call of
// index.mlir's function on them.

func.func @cx_rows(%h: !llvm.ptr) -> i64 {
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %n = func.call @ix_rows(%rows) : (!ix) -> i64
  return %n : i64
}

func.func @cx_tag(%h: !llvm.ptr, %r: i64) -> i64 {
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %v = func.call @ix_tag(%rows, %r) : (!ix, i64) -> i64
  return %v : i64
}

func.func @cx_close(%h: !llvm.ptr, %r: i64) -> i64 {
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %v = func.call @ix_close(%rows, %r) : (!ix, i64) -> i64
  return %v : i64
}

// the element as written, [open, close + 1), and a string's inside, between its quotes, [open + 1, close): index.mlir's
// Spans read as coordinates.  Their result is a TwinPacked word, which a func.call cannot carry through the cursor
// lowering (a !trikeshed.twinpacked result has no conversion at a call): these two cross as index.mlir's C interfaces,
// the word's ABI, over the handle's three descriptors.
func.func @cx_raw(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %p0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %p1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %p2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %t = llvm.call @_mlir_ciface_ix_raw(%p0, %p1, %p2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %t : i64
}

func.func @cx_str(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %p0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %p1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %p2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %t = llvm.call @_mlir_ciface_ix_str(%p0, %p1, %p2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %t : i64
}

func.func @cx_nkids(%h: !llvm.ptr, %r: i64) -> i64 {
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %v = func.call @ix_nkids(%rows, %r) : (!ix, i64) -> i64
  return %v : i64
}

// the value row of the key, or -1 (index.mlir's ix_member: KeyToChild, then the value after the key)
func.func @cx_member(%text: !llvm.ptr, %h: !llvm.ptr, %obj: i64, %key: !llvm.ptr, %n: i64) -> i64 {
  %own = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  %pn = llvm.getelementptr %own[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !d
  %tn = llvm.load %pn : !llvm.ptr -> i64
  %td = func.call @cx_mview(%text, %tn) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to memref<?xi8>
  %t = trikeshed.text %tm : memref<?xi8> -> !text
  %kd = func.call @cx_mview(%key, %n) : (!llvm.ptr, i64) -> !d
  %km = builtin.unrealized_conversion_cast %kd : !d to memref<?xi8>
  %k = trikeshed.text %km : memref<?xi8> -> !text
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %m3 = builtin.unrealized_conversion_cast %d3 : !d to memref<?xi32>
  %kids = trikeshed.text %m3 : memref<?xi32> -> !s32
  %v = func.call @ix_member(%rows, %kids, %t, %obj, %k) : (!ix, !s32, !text, i64, !text) -> i64
  return %v : i64
}

// the number of unterminated strings in the text (index.mlir's ix_unterminated: a text that ends in an open quote)
func.func @cx_unterminated(%text: !llvm.ptr, %h: !llvm.ptr) -> i64 {
  %own = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  %pn = llvm.getelementptr %own[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !d
  %tn = llvm.load %pn : !llvm.ptr -> i64
  %td = func.call @cx_mview(%text, %tn) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to memref<?xi8>
  %t = trikeshed.text %tm : memref<?xi8> -> !text
  %d0, %d1, %d2, %d3 = func.call @cx_descs(%h) : (!llvm.ptr) -> (!d, !d, !d, !d)
  %m0 = builtin.unrealized_conversion_cast %d0 : !d to memref<?xi64>
  %m1 = builtin.unrealized_conversion_cast %d1 : !d to memref<?xi8>
  %m2 = builtin.unrealized_conversion_cast %d2 : !d to memref<?xi64>
  %rows = builtin.unrealized_conversion_cast %m0, %m1, %m2 : memref<?xi64>, memref<?xi8>, memref<?xi64> to !ix
  %v = func.call @ix_unterminated(%rows, %t) : (!ix, !text) -> i64
  return %v : i64
}
