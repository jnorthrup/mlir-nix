// index.mlir -- a JSON text's index in TrikeShed's forms (ConfixIndexK): confix.index scans the text into the rows, a
// cursor of Spans (open, close), Tags and DirectChildren's (first, count), and the kid series those slice; every read
// below is a trikeshed op on them.  Compiled like query.mlir, by mlnix-opt --trikeshed-lower-cursors.  src/confix.mlir
// keeps the index's buffers behind the handle the rest of mlnixci passes around, and calls these through their C
// interfaces.  An element is a row; an object's children are its keys and values, alternating; nothing is decoded.

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">

// the scan: the rows, the kids, and the fault (0 for none; after one the rows are empty)
func.func @ix_scan(%t: !text) -> (!ix, !s32, i32) attributes {llvm.emit_c_interface} {
  %rows, %kids, %fault, %at = confix.index json %t : !text -> !ix, !s32
  return %rows, %kids, %fault : !ix, !s32, i32
}

func.func @ix_rows(%rows: !ix) -> i64 attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %n = trikeshed.size %spans : !trikeshed.series<!tw>
  %r = arith.index_cast %n : index to i64
  return %r : i64
}

// Tags: the TagKind (0 null, 1 boolean, 2 long, 3 double, 4 string, 5 object, 6 array, 7 bytes)
func.func @ix_tag(%rows: !ix, %r: i64) -> i64 attributes {llvm.emit_c_interface} {
  %k1 = trikeshed.key 1 : !ik
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !trikeshed.series<i8>
  %t = trikeshed.at %tags[%r] : !trikeshed.series<i8>, i64 -> i8
  %z = arith.extui %t : i8 to i64
  return %z : i64
}

// Spans: the first and the last byte of the element as written
func.func @ix_open(%rows: !ix, %r: i64) -> i64 attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %s = trikeshed.at %spans[%r] : !trikeshed.series<!tw>, i64 -> !tw
  %o = trikeshed.first %s : !tw -> i32
  %z = arith.extui %o : i32 to i64
  return %z : i64
}

func.func @ix_close(%rows: !ix, %r: i64) -> i64 attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %s = trikeshed.at %spans[%r] : !trikeshed.series<!tw>, i64 -> !tw
  %c = trikeshed.second %s : !tw -> i32
  %z = arith.extui %c : i32 to i64
  return %z : i64
}

// Spans as coordinates (TwinPacked (start, length), series.mlir's): the element as written, [open, close + 1), and a
// string's inside, between its quotes, [open + 1, close)
func.func @ix_raw(%rows: !ix, %r: i64) -> !tp attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %s = trikeshed.at %spans[%r] : !trikeshed.series<!tw>, i64 -> !tw
  %o = trikeshed.first %s : !tw -> i32
  %c = trikeshed.second %s : !tw -> i32
  %one = arith.constant 1 : i32
  %c1 = arith.addi %c, %one : i32
  %n = arith.subi %c1, %o : i32
  %t = trikeshed.j %o, %n : i32, i32 -> !tp
  return %t : !tp
}

func.func @ix_str(%rows: !ix, %r: i64) -> !tp attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %s = trikeshed.at %spans[%r] : !trikeshed.series<!tw>, i64 -> !tw
  %o = trikeshed.first %s : !tw -> i32
  %c = trikeshed.second %s : !tw -> i32
  %one = arith.constant 1 : i32
  %in = arith.addi %o, %one : i32
  %n = arith.subi %c, %in : i32
  %t = trikeshed.j %in, %n : i32, i32 -> !tp
  return %t : !tp
}

// DirectChildren: how many, and the i-th
func.func @ix_nkids(%rows: !ix, %r: i64) -> i64 attributes {llvm.emit_c_interface} {
  %k2 = trikeshed.key 2 : !ik
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %fc = trikeshed.at %kc[%r] : !trikeshed.series<!tp>, i64 -> !tp
  %n = trikeshed.second %fc : !tp -> i32
  %z = arith.extui %n : i32 to i64
  return %z : i64
}

func.func @ix_kid(%rows: !ix, %kids: !s32, %r: i64, %i: i64) -> i64 attributes {llvm.emit_c_interface} {
  %k2 = trikeshed.key 2 : !ik
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %fc = trikeshed.at %kc[%r] : !trikeshed.series<!tp>, i64 -> !tp
  %f = trikeshed.first %fc : !tp -> i32
  %fz = arith.extui %f : i32 to i64
  %at = arith.addi %fz, %i : i64
  %k = trikeshed.at %kids[%at] : !s32, i64 -> i32
  %z = arith.extui %k : i32 to i64
  return %z : i64
}

// KeyToChild: the place among the object's children of the key written as the bytes of `key` (the key is child i, its
// value child i + 1), or -1.  The first of equal keys is the one found, and a key with no value after it (a text cut
// short) is not.  One fold over the object's children (a slice of the kids); its accumulator is (the place found or -1,
// the place reached).
func.func @ix_find(%rows: !ix, %kids: !s32, %t: !text, %obj: i64, %key: !text) -> i64 attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !trikeshed.series<i8>
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %none = arith.constant -1 : i64
  %object = arith.constant 5 : i8
  %tag = trikeshed.at %tags[%obj] : !trikeshed.series<i8>, i64 -> i8
  %isObj = arith.cmpi eq, %tag, %object : i8
  %place = scf.if %isObj -> (i64) {
    %fc = trikeshed.at %kc[%obj] : !trikeshed.series<!tp>, i64 -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %n = trikeshed.second %fc : !tp -> i32
    %fi = arith.index_cast %f : i32 to index
    %ni = arith.index_cast %n : i32 to index
    %children = trikeshed.slice %kids[%fi, %ni] : !s32 -> !s32
    %unset = arith.constant -1 : i32
    %c0 = arith.constant 0 : i32
    %start = trikeshed.j %unset, %c0 : i32, i32 -> !tp
    %end = trikeshed.fold %children, %start : !s32, !tp -> !tp {
    ^bb0(%acc: !tp, %kid: i32):
      %found = trikeshed.first %acc : !tp -> i32
      %i = trikeshed.second %acc : !tp -> i32
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      %string = arith.constant 4 : i8
      %open = arith.cmpi slt, %found, %zero : i32
      %odd = arith.andi %i, %one : i32
      %even = arith.cmpi eq, %odd, %zero : i32
      %kt = trikeshed.at %tags[%kid] : !trikeshed.series<i8>, i32 -> i8
      %isStr = arith.cmpi eq, %kt, %string : i8
      %i1 = arith.addi %i, %one : i32
      %valued = arith.cmpi slt, %i1, %n : i32
      %a = arith.andi %open, %even : i1
      %b = arith.andi %isStr, %valued : i1
      %cand = arith.andi %a, %b : i1
      %hit = scf.if %cand -> (i1) {
        %sp = trikeshed.at %spans[%kid] : !trikeshed.series<!tw>, i32 -> !tw
        %o = trikeshed.first %sp : !tw -> i32
        %c = trikeshed.second %sp : !tw -> i32
        %in = arith.addi %o, %one : i32
        %len = arith.subi %c, %in : i32
        %ini = arith.index_cast %in : i32 to index
        %leni = arith.index_cast %len : i32 to index
        %inside = trikeshed.slice %t[%ini, %leni] : !text -> !text
        %order = trikeshed.compare %inside, %key : !text, !text
        %same = arith.cmpi eq, %order, %zero : i32
        scf.yield %same : i1
      } else {
        %no = arith.constant false
        scf.yield %no : i1
      }
      %found2 = arith.select %hit, %i, %found : i32
      %i2 = arith.addi %i, %one : i32
      %next = trikeshed.j %found2, %i2 : i32, i32 -> !tp
      trikeshed.yield %next : !tp
    }
    %p = trikeshed.first %end : !tp -> i32
    %pz = arith.extsi %p : i32 to i64
    scf.yield %pz : i64
  } else {
    scf.yield %none : i64
  }
  return %place : i64
}

// the value row of the key, or -1
func.func @ix_member(%rows: !ix, %kids: !s32, %t: !text, %obj: i64, %key: !text) -> i64 attributes {llvm.emit_c_interface} {
  %none = arith.constant -1 : i64
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %i = func.call @ix_find(%rows, %kids, %t, %obj, %key) : (!ix, !s32, !text, i64, !text) -> i64
  %absent = arith.cmpi slt, %i, %c0 : i64
  %v = scf.if %absent -> (i64) {
    scf.yield %none : i64
  } else {
    %i1 = arith.addi %i, %c1 : i64
    %r = func.call @ix_kid(%rows, %kids, %obj, %i1) : (!ix, !s32, i64, i64) -> i64
    scf.yield %r : i64
  }
  return %v : i64
}
