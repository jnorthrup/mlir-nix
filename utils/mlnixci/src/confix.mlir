// confix.mlir -- the handle mlnixci passes around for a JSON text's index, and the reads it makes of it.  The index is
// src/index.mlir's: confix.index's rows (ConfixIndexK's Spans, Tags and DirectChildren) and kids, read with trikeshed ops
// there.  Here are only the buffers' descriptors behind the handle, and calls of index.mlir's C interfaces with them: no
// read of an element is made in this file.  An element is a row; its coordinates are its span in the text; an object's
// children are its keys and values, alternating.  Nothing is decoded: a key is compared with the bytes it is written as.

llvm.func @malloc(i64) -> !llvm.ptr
llvm.func @free(!llvm.ptr)

// a buffer's descriptor (memref<?xT, strided<[1], offset: ?>>, as the LLVM lowering lays it out)
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
// the handle: ix_scan's results (the rows' span, tag and kids columns, the kid series, the fault), then the text
!h = !llvm.struct<(struct<(struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>, i32)>, struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>)>

llvm.func @_mlir_ciface_ix_scan(!llvm.ptr, !llvm.ptr)
llvm.func @_mlir_ciface_ix_rows(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_ix_tag(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
llvm.func @_mlir_ciface_ix_open(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
llvm.func @_mlir_ciface_ix_close(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
llvm.func @_mlir_ciface_ix_nkids(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
llvm.func @_mlir_ciface_ix_kid(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i64
llvm.func @_mlir_ciface_ix_find(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
llvm.func @_mlir_ciface_ix_member(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64

func.func private @tw(i64, i64) -> i64
func.func private @tw_s(i64) -> i64
func.func private @tw_n(i64) -> i64
func.func private @off(!llvm.ptr, i64) -> !llvm.ptr
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

func.func @cx_rows(%h: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %n = llvm.call @_mlir_ciface_ix_rows(%d0, %d1, %d2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  return %n : i64
}

func.func @cx_tag(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_tag(%d0, %d1, %d2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %v : i64
}

// [open, close] as the text has them: the first and the last byte
func.func @cx_open(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_open(%d0, %d1, %d2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %v : i64
}

func.func @cx_close(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_close(%d0, %d1, %d2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %v : i64
}

// the element as written: [open, close + 1)
func.func @cx_raw(%h: !llvm.ptr, %r: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %o = func.call @cx_open(%h, %r) : (!llvm.ptr, i64) -> i64
  %c = func.call @cx_close(%h, %r) : (!llvm.ptr, i64) -> i64
  %e = arith.addi %c, %c1 : i64
  %t = func.call @tw(%o, %e) : (i64, i64) -> i64
  return %t : i64
}

// a string's inside, between its quotes: [open + 1, close)
func.func @cx_str(%h: !llvm.ptr, %r: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %o = func.call @cx_open(%h, %r) : (!llvm.ptr, i64) -> i64
  %c = func.call @cx_close(%h, %r) : (!llvm.ptr, i64) -> i64
  %s = arith.addi %o, %c1 : i64
  %t = func.call @tw(%s, %c) : (i64, i64) -> i64
  return %t : i64
}

func.func @cx_nkids(%h: !llvm.ptr, %r: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_nkids(%d0, %d1, %d2, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
  return %v : i64
}

func.func @cx_kid(%h: !llvm.ptr, %r: i64, %i: i64) -> i64 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %c3) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_kid(%d0, %d1, %d2, %d3, %r, %i) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i64
  return %v : i64
}

// The place among the object's children of the key written as the n bytes at key, or -1: the key is child i, its value
// child i + 1.  The first of equal keys is the one found (index.mlir's ix_find: KeyToChild).
func.func @cx_find(%text: !llvm.ptr, %h: !llvm.ptr, %obj: i64, %key: !llvm.ptr, %n: i64) -> i64 {
  %one = arith.constant 1 : i32
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %own = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  %pn = llvm.getelementptr %own[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !d
  %tn = llvm.load %pn : !llvm.ptr -> i64
  %td = llvm.alloca %one x !d : (i32) -> !llvm.ptr
  func.call @view(%td, %text, %tn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %kd = llvm.alloca %one x !d : (i32) -> !llvm.ptr
  func.call @view(%kd, %key, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %c3) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_find(%d0, %d1, %d2, %d3, %td, %obj, %kd) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  return %v : i64
}

// the value row of the key, or -1
func.func @cx_member(%text: !llvm.ptr, %h: !llvm.ptr, %obj: i64, %key: !llvm.ptr, %n: i64) -> i64 {
  %one = arith.constant 1 : i32
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %own = func.call @cx_text(%h) : (!llvm.ptr) -> !llvm.ptr
  %pn = llvm.getelementptr %own[0, 3, 0] : (!llvm.ptr) -> !llvm.ptr, !d
  %tn = llvm.load %pn : !llvm.ptr -> i64
  %td = llvm.alloca %one x !d : (i32) -> !llvm.ptr
  func.call @view(%td, %text, %tn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %kd = llvm.alloca %one x !d : (i32) -> !llvm.ptr
  func.call @view(%kd, %key, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %d0 = func.call @cx_d(%h, %c0) : (!llvm.ptr, i32) -> !llvm.ptr
  %d1 = func.call @cx_d(%h, %c1) : (!llvm.ptr, i32) -> !llvm.ptr
  %d2 = func.call @cx_d(%h, %c2) : (!llvm.ptr, i32) -> !llvm.ptr
  %d3 = func.call @cx_d(%h, %c3) : (!llvm.ptr, i32) -> !llvm.ptr
  %v = llvm.call @_mlir_ciface_ix_member(%d0, %d1, %d2, %d3, %td, %obj, %kd) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  return %v : i64
}

// the same, with the key a piece of another text
func.func @cx_member_at(%text: !llvm.ptr, %h: !llvm.ptr, %obj: i64, %kbase: !llvm.ptr, %kt: i64) -> i64 {
  %s = func.call @tw_s(%kt) : (i64) -> i64
  %n = func.call @tw_n(%kt) : (i64) -> i64
  %k = func.call @off(%kbase, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  %v = func.call @cx_member(%text, %h, %obj, %k, %n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  return %v : i64
}

func.func @cx_find_at(%text: !llvm.ptr, %h: !llvm.ptr, %obj: i64, %kbase: !llvm.ptr, %kt: i64) -> i64 {
  %s = func.call @tw_s(%kt) : (i64) -> i64
  %n = func.call @tw_n(%kt) : (i64) -> i64
  %k = func.call @off(%kbase, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  %i = func.call @cx_find(%text, %h, %obj, %k, %n) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  return %i : i64
}
