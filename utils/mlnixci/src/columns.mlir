// columns.mlir -- the corpus's columns read, coded, and its rows ordered, in TrikeShed's forms.
//   opt_members ConfixIndexK.Columns (ConfixColumns.kt) over the options' elements: each option's members by name, one
//               pass over its keys (confix.columns)
// A coded column is a series of pieces of one text (!trikeshed.twinpacked<i32> (start, length), series.mlir's
// coordinates); two pieces are in the order of their bytes, compared unsigned as Kotlin compares Chars (a UTF-8 text in
// code point order), then the shorter first.
//   col_order   Cursor.ordered (GroupBy.kt): the rows by their pieces, a stable sort, so equal pieces keep their rows' order
//   col_code    DictColumn (ColumnCursor.kt) with its names in that order: trikeshed.groupBy ordered (GroupBy.kt's
//               groupClusters over the ordered rows), each name its group's first row's piece and each row's code its
//               name's place among them, so a name keeps its place as the counts change
//   mark        trikeshed.keyedJoin (KeyedJoin.kt) of a corpus with its base on their keys, base's col_order the index
//               over base: each row's base row, and whether the option changed
//   etc_join    the same join made full outer, of two objects' members by name (the /etc files of the base and of the
//               what-if): a keyedJoin each way, each side the index over the other (both are in name order), the entries
//               the report shows ranked by their own place plus the other side's names below them (the first of their
//               matches)
//   opt_cells   the cells a facet counts, read off each option's members as pieces of the text: the section (the first
//               segment of the path), the value when it is shown, the state, the kind (the type's name: its first part at
//               ' ', Series.div) and the module (the place of the first declaration: two levels below its last
//               "modules/", found by a fold, the levels by Series.div at '/')
//   opt_text    the two texts a corpus makes: each option's key, its path's segments with a '.' between each two
//               (Combine.kt's combine over a Series<Series<Char>>), and what it is searched by, its key and its
//               description with their escapes read (confix.unescape, KnownSchema.decodeEscaped) and lower-cased (α),
//               a ' ' between them (combine).  Each text is one series with each row's (start, length) in it
//               (trikeshed.combineAll)
//   query_text  what a query is searched for: its bytes read as the search text reads a description
// Compiled like query.mlir and index.mlir, by mlnix-opt --trikeshed-lower-cursors; corpus.mlir calls these through their
// C interfaces.  The buffers returned are malloc'd; corpus.mlir frees them.

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">
!members = !trikeshed.cursor<"Option", [i32, i32, i32, i32, i32, i32, i32]>
!mk = !trikeshed.colkey<"Option">

// For each element of the array at row opts of the index (an option of mlnix's evaluation), the row of the value of its
// member path, valueShown, value, state, kind, declarations and description, or -1 (not an object, or no such member).
func.func @opt_members(%rows: !ix, %kids: !s32, %t: !text, %opts: i64)
    -> (!s32, !s32, !s32, !s32, !s32, !s32, !s32) attributes {llvm.emit_c_interface} {
  %k2 = trikeshed.key 2 : !ik
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %fc = trikeshed.at %kc[%opts] : !trikeshed.series<!tp>, i64 -> !tp
  %f = trikeshed.first %fc : !tp -> i32
  %n = trikeshed.second %fc : !tp -> i32
  %fi = arith.index_cast %f : i32 to index
  %ni = arith.index_cast %n : i32 to index
  %options = trikeshed.slice %kids[%fi, %ni] : !s32 -> !s32
  %table = confix.columns json %rows, %kids, %t, %options ["path", "valueShown", "value", "state", "kind", "declarations", "description"] : !ix, !s32, !text, !s32 -> !members
  %m0 = trikeshed.key 0 : !mk
  %m1 = trikeshed.key 1 : !mk
  %m2 = trikeshed.key 2 : !mk
  %m3 = trikeshed.key 3 : !mk
  %m4 = trikeshed.key 4 : !mk
  %m5 = trikeshed.key 5 : !mk
  %m6 = trikeshed.key 6 : !mk
  %path = trikeshed.column %table[%m0] : !members, !mk -> !s32
  %shown = trikeshed.column %table[%m1] : !members, !mk -> !s32
  %value = trikeshed.column %table[%m2] : !members, !mk -> !s32
  %state = trikeshed.column %table[%m3] : !members, !mk -> !s32
  %kind = trikeshed.column %table[%m4] : !members, !mk -> !s32
  %decl = trikeshed.column %table[%m5] : !members, !mk -> !s32
  %desc = trikeshed.column %table[%m6] : !members, !mk -> !s32
  return %path, %shown, %value, %state, %kind, %decl, %desc : !s32, !s32, !s32, !s32, !s32, !s32, !s32
}

// the order of the pieces of rows a and b (a slice is a view, so it stays in the function that makes it: a function's
// result is a buffer its caller owns, and a view returned would be copied)
func.func private @piece_order(%t: !text, %pieces: !pieces, %a: i32, %b: i32) -> i32 {
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

// rows 0 ..< size(pieces), ordered by their pieces
func.func @col_order(%t: !text, %pieces: !pieces) -> !s32 attributes {llvm.emit_c_interface} {
  %n = trikeshed.size %pieces : !pieces
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %order = trikeshed.sorted %rows : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %c = func.call @piece_order(%t, %pieces, %a, %b) : (!text, !pieces, i32, i32) -> i32
    trikeshed.yield %c : i32
  }
  return %order : !s32
}

// each row's code, and each code's name (its first row's piece): groupBy ordered, the rows grouped by their pieces
func.func @col_code(%t: !text, %pieces: !pieces) -> (!s32, !pieces) attributes {llvm.emit_c_interface} {
  %n = trikeshed.size %pieces : !pieces
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %codes, %names = trikeshed.groupBy %rows ordered : !s32 -> !s32, !s32 by {
  ^bb0(%a: i32, %b: i32):
    %c = func.call @piece_order(%t, %pieces, %a, %b) : (!text, !pieces, i32, i32) -> i32
    trikeshed.yield %c : i32
  }
  %dict = trikeshed.project %pieces[%names] : !pieces, !s32 -> !pieces
  return %codes, %dict : !s32, !pieces
}

// the order of a piece of one text and a piece of another: their bytes, unsigned, then the shorter first
func.func private @order_of(%ta: !text, %pa: !tp, %tb: !text, %pb: !tp) -> i32 {
  %sa = trikeshed.first %pa : !tp -> i32
  %na = trikeshed.second %pa : !tp -> i32
  %sb = trikeshed.first %pb : !tp -> i32
  %nb = trikeshed.second %pb : !tp -> i32
  %sai = arith.index_cast %sa : i32 to index
  %nai = arith.index_cast %na : i32 to index
  %sbi = arith.index_cast %sb : i32 to index
  %nbi = arith.index_cast %nb : i32 to index
  %ba = trikeshed.slice %ta[%sai, %nai] : !text -> !text
  %bb = trikeshed.slice %tb[%sbi, %nbi] : !text -> !text
  %c = trikeshed.compare %ba, %bb unsigned : !text, !text
  return %c : i32
}

// Each row of a corpus (its keys: pieces of the text keysC) joined to its base (keysB) on the key: its base row, or -1 --
// the first base row, in base's key order ordB, whose key is not below the row's (a lower bound: an order that is never
// equal, so the search ends there), when that key is the same bytes.  And whether the option changed: it has no base row,
// or its value (a piece of tc, or -1 when it is not shown) or its state is not the same bytes as the base row's (of tb).
// Both are drained into the corpus's arrays.
func.func @mark(%keysC: !text, %keyC: !pieces, %tc: !text, %valC: !pieces, %stC: !pieces,
                %keysB: !text, %keyB: !pieces, %ordB: !s32, %tb: !text, %valB: !pieces, %stB: !pieces,
                %baseOf: memref<?xi32>, %whatif: memref<?xi32>) attributes {llvm.emit_c_interface} {
  %n = trikeshed.size %keyC : !pieces
  %rows = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %matches = trikeshed.keyedJoin %keyC, %ordB : !pieces, !s32 -> !pieces by {
  ^bb0(%b: i32, %k: !tp):
    %kb = trikeshed.at %keyB[%b] : !pieces, i32 -> !tp
    %c = func.call @order_of(%keysB, %kb, %keysC, %k) : (!text, !tp, !text, !tp) -> i32
    trikeshed.yield %c : i32
  }
  %match = trikeshed.alpha %matches : !pieces -> !s32 {
  ^bb0(%m: !tp):
    %zero = arith.constant 0 : i32
    %none = arith.constant -1 : i32
    %first = trikeshed.first %m : !tp -> i32
    %count = trikeshed.second %m : !tp -> i32
    %has = arith.cmpi sgt, %count, %zero : i32
    %found = scf.if %has -> (i32) {
      %b = trikeshed.at %ordB[%first] : !s32, i32 -> i32
      scf.yield %b : i32
    } else {
      scf.yield %none : i32
    }
    trikeshed.yield %found : i32
  }
  %changed = trikeshed.alpha %rows : !s32 -> !s32 {
  ^bb0(%r: i32):
    %zero = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %none = arith.constant -1 : i32
    %b = trikeshed.at %match[%r] : !s32, i32 -> i32
    %has = arith.cmpi sge, %b, %zero : i32
    %ch = scf.if %has -> (i32) {
      %vc = trikeshed.at %valC[%r] : !pieces, i32 -> !tp
      %vb = trikeshed.at %valB[%b] : !pieces, i32 -> !tp
      // a value that is not shown is the piece -1: its length is -1
      %nvc = trikeshed.second %vc : !tp -> i32
      %nvb = trikeshed.second %vb : !tp -> i32
      %noC = arith.cmpi eq, %nvc, %none : i32
      %noB = arith.cmpi eq, %nvb, %none : i32
      %either = arith.ori %noC, %noB : i1
      %sameV = scf.if %either -> (i1) {
        %both = arith.andi %noC, %noB : i1
        scf.yield %both : i1
      } else {
        %cv = func.call @order_of(%tc, %vc, %tb, %vb) : (!text, !tp, !text, !tp) -> i32
        %eqv = arith.cmpi eq, %cv, %zero : i32
        scf.yield %eqv : i1
      }
      %sc = trikeshed.at %stC[%r] : !pieces, i32 -> !tp
      %sb = trikeshed.at %stB[%b] : !pieces, i32 -> !tp
      %cs = func.call @order_of(%tc, %sc, %tb, %sb) : (!text, !tp, !text, !tp) -> i32
      %sameS = arith.cmpi eq, %cs, %zero : i32
      %same = arith.andi %sameV, %sameS : i1
      %v = arith.select %same, %zero, %one : i32
      scf.yield %v : i32
    } else {
      scf.yield %one : i32
    }
    trikeshed.yield %ch : i32
  }
  %e1 = trikeshed.drain %match, %baseOf : !s32, memref<?xi32> -> index
  %e2 = trikeshed.drain %changed, %whatif : !s32, memref<?xi32> -> index
  return
}

// ---- the /etc files of two corpora, joined by name

// An object's members: the first of its kids and the number of its members (pairs of kids), or (0, 0) for row -1.
func.func private @members_of(%kc: !pieces, %e: i64) -> (i32, i32) {
  %c0 = arith.constant 0 : i64
  %none = arith.cmpi slt, %e, %c0 : i64
  %r:2 = scf.if %none -> (i32, i32) {
    %z = arith.constant 0 : i32
    scf.yield %z, %z : i32, i32
  } else {
    %fc = trikeshed.at %kc[%e] : !pieces, i64 -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %n = trikeshed.second %fc : !tp -> i32
    %two = arith.constant 2 : i32
    %half = arith.divui %n, %two : i32
    scf.yield %f, %half : i32, i32
  }
  return %r#0, %r#1 : i32, i32
}

// Member m's name (the inside of its key's quotes) or value (its text as written): pieces of the object's text, from the
// spans (Twin (open, close), close inclusive) of the kids at first + 2m and first + 2m + 1.
func.func private @member_pieces(%spans: !trikeshed.series<!tw>, %kids: !s32, %first: i32, %n: i32) -> (!pieces, !pieces) {
  %ni = arith.index_cast %n : i32 to index
  %names = trikeshed.series %ni : !pieces {
  ^bb0(%m: index):
    %m32 = arith.index_cast %m : index to i32
    %two = arith.constant 2 : i32
    %one = arith.constant 1 : i32
    %m2 = arith.muli %m32, %two : i32
    %at = arith.addi %first, %m2 : i32
    %key = trikeshed.at %kids[%at] : !s32, i32 -> i32
    %sp = trikeshed.at %spans[%key] : !trikeshed.series<!tw>, i32 -> !tw
    %o = trikeshed.first %sp : !tw -> i32
    %c = trikeshed.second %sp : !tw -> i32
    %s = arith.addi %o, %one : i32
    %l = arith.subi %c, %o : i32
    %l1 = arith.subi %l, %one : i32
    %piece = trikeshed.j %s, %l1 : i32, i32 -> !tp
    trikeshed.yield %piece : !tp
  }
  %values = trikeshed.series %ni : !pieces {
  ^bb0(%m: index):
    %m32 = arith.index_cast %m : index to i32
    %two = arith.constant 2 : i32
    %one = arith.constant 1 : i32
    %m2 = arith.muli %m32, %two : i32
    %at0 = arith.addi %first, %m2 : i32
    %at = arith.addi %at0, %one : i32
    %value = trikeshed.at %kids[%at] : !s32, i32 -> i32
    %sp = trikeshed.at %spans[%value] : !trikeshed.series<!tw>, i32 -> !tw
    %o = trikeshed.first %sp : !tw -> i32
    %c = trikeshed.second %sp : !tw -> i32
    %l = arith.subi %c, %o : i32
    %l1 = arith.addi %l, %one : i32
    %piece = trikeshed.j %o, %l1 : i32, i32 -> !tp
    trikeshed.yield %piece : !tp
  }
  return %names, %values : !pieces, !pieces
}

// The members of the objects at row ea of index A (text ta: the base's /etc) and row eb of index B (text tb: the what-if's),
// -1 for none, joined by name -- KeyedJoin with each side the index over the other, made full outer.  The entries the report
// shows, in name order: A's members whose name B lacks or whose value's bytes differ from B's member of that name, and B's
// members whose name A lacks.  Entry e is A's member e when e < size(A), else B's member e - size(A); other[e] is the
// other side's member of the same name, or -1.  Both are drained into entries and other (room for size(A) + size(B));
// the result is how many.  Each side's members' names (the inside of their keys' quotes) and values (their text as
// written), pieces of its text, are drained into namesA/valuesA and namesB/valuesB: what the report writes (text.mlir's
// report_reply).  An entry's place is its name's rank among both sides' names (A's member i: i plus the names
// of B below it; B's member j: j plus the names of A below it), the order the merge of the two would give.
func.func @etc_join(%rowsA: !ix, %kidsA: !s32, %ta: !text, %ea: i64, %rowsB: !ix, %kidsB: !s32, %tb: !text, %eb: i64,
                    %entries: memref<?xi32>, %other: memref<?xi32>, %namesAOut: memref<?xi64>, %valuesAOut: memref<?xi64>,
                    %namesBOut: memref<?xi64>, %valuesBOut: memref<?xi64>) -> i64 attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spansA = trikeshed.column %rowsA[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %kcA = trikeshed.column %rowsA[%k2] : !ix, !ik -> !pieces
  %spansB = trikeshed.column %rowsB[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %kcB = trikeshed.column %rowsB[%k2] : !ix, !ik -> !pieces
  %fA, %nA = func.call @members_of(%kcA, %ea) : (!pieces, i64) -> (i32, i32)
  %fB, %nB = func.call @members_of(%kcB, %eb) : (!pieces, i64) -> (i32, i32)
  %namesA, %valuesA = func.call @member_pieces(%spansA, %kidsA, %fA, %nA) : (!trikeshed.series<!tw>, !s32, i32, i32) -> (!pieces, !pieces)
  %namesB, %valuesB = func.call @member_pieces(%spansB, %kidsB, %fB, %nB) : (!trikeshed.series<!tw>, !s32, i32, i32) -> (!pieces, !pieces)
  // each side's names joined to the other's: the matches of A's member i, (how many of B's names sort below its name, 1
  // when B has that name else 0), and B's likewise
  %nAi = arith.index_cast %nA : i32 to index
  %nBi = arith.index_cast %nB : i32 to index
  %placesA = trikeshed.series %nAi : !s32 {
  ^bb0(%i: index):
    %p = arith.index_cast %i : index to i32
    trikeshed.yield %p : i32
  }
  %placesB = trikeshed.series %nBi : !s32 {
  ^bb0(%i: index):
    %p = arith.index_cast %i : index to i32
    trikeshed.yield %p : i32
  }
  %byA = trikeshed.keyedJoin %namesA, %placesB : !pieces, !s32 -> !pieces by {
  ^bb0(%p: i32, %k: !tp):
    %pk = trikeshed.at %namesB[%p] : !pieces, i32 -> !tp
    %c = func.call @order_of(%tb, %pk, %ta, %k) : (!text, !tp, !text, !tp) -> i32
    trikeshed.yield %c : i32
  }
  %byB = trikeshed.keyedJoin %namesB, %placesA : !pieces, !s32 -> !pieces by {
  ^bb0(%p: i32, %k: !tp):
    %pk = trikeshed.at %namesA[%p] : !pieces, i32 -> !tp
    %c = func.call @order_of(%ta, %pk, %tb, %k) : (!text, !tp, !text, !tp) -> i32
    trikeshed.yield %c : i32
  }
  %all32 = arith.addi %nA, %nB : i32
  %all = arith.index_cast %all32 : i32 to index
  %es = trikeshed.series %all : !s32 {
  ^bb0(%i: index):
    %e = arith.index_cast %i : index to i32
    trikeshed.yield %e : i32
  }
  %shown = trikeshed.where %es : !s32 -> !s32 {
  ^bb0(%e: i32):
    %zero = arith.constant 0 : i32
    %inA = arith.cmpi slt, %e, %nA : i32
    %keep = scf.if %inA -> (i1) {
      %m = trikeshed.at %byA[%e] : !pieces, i32 -> !tp
      %count = trikeshed.second %m : !tp -> i32
      %lacks = arith.cmpi eq, %count, %zero : i32
      %k = scf.if %lacks -> (i1) {
        %yes = arith.constant true
        scf.yield %yes : i1
      } else {
        %b = trikeshed.first %m : !tp -> i32
        %va = trikeshed.at %valuesA[%e] : !pieces, i32 -> !tp
        %vb = trikeshed.at %valuesB[%b] : !pieces, i32 -> !tp
        %c = func.call @order_of(%ta, %va, %tb, %vb) : (!text, !tp, !text, !tp) -> i32
        %differ = arith.cmpi ne, %c, %zero : i32
        scf.yield %differ : i1
      }
      scf.yield %k : i1
    } else {
      %j = arith.subi %e, %nA : i32
      %m = trikeshed.at %byB[%j] : !pieces, i32 -> !tp
      %count = trikeshed.second %m : !tp -> i32
      %lacks = arith.cmpi eq, %count, %zero : i32
      scf.yield %lacks : i1
    }
    trikeshed.yield %keep : i1
  }
  %ordered = trikeshed.sorted %shown : !s32 -> !s32 by {
  ^bb0(%x: i32, %y: i32):
    %rx = func.call @join_rank(%x, %nA, %byA, %byB) : (i32, i32, !pieces, !pieces) -> i32
    %ry = func.call @join_rank(%y, %nA, %byA, %byB) : (i32, i32, !pieces, !pieces) -> i32
    %lt = arith.cmpi slt, %rx, %ry : i32
    %gt = arith.cmpi sgt, %rx, %ry : i32
    %m1 = arith.constant -1 : i32
    %p1 = arith.constant 1 : i32
    %z = arith.constant 0 : i32
    %g = arith.select %gt, %p1, %z : i32
    %o = arith.select %lt, %m1, %g : i32
    trikeshed.yield %o : i32
  }
  %others = trikeshed.alpha %ordered : !s32 -> !s32 {
  ^bb0(%e: i32):
    %none = arith.constant -1 : i32
    %zero = arith.constant 0 : i32
    %inA = arith.cmpi slt, %e, %nA : i32
    %o = scf.if %inA -> (i32) {
      %m = trikeshed.at %byA[%e] : !pieces, i32 -> !tp
      %b = trikeshed.first %m : !tp -> i32
      %count = trikeshed.second %m : !tp -> i32
      %has = arith.cmpi sgt, %count, %zero : i32
      %v = arith.select %has, %b, %none : i32
      scf.yield %v : i32
    } else {
      scf.yield %none : i32
    }
    trikeshed.yield %o : i32
  }
  %n1 = trikeshed.drain %ordered, %entries : !s32, memref<?xi32> -> index
  %n2 = trikeshed.drain %others, %other : !s32, memref<?xi32> -> index
  %n3 = trikeshed.drain %namesA, %namesAOut : !pieces, memref<?xi64> -> index
  %n4 = trikeshed.drain %valuesA, %valuesAOut : !pieces, memref<?xi64> -> index
  %n5 = trikeshed.drain %namesB, %namesBOut : !pieces, memref<?xi64> -> index
  %n6 = trikeshed.drain %valuesB, %valuesBOut : !pieces, memref<?xi64> -> index
  %count = arith.index_cast %n1 : index to i64
  return %count : i64
}

// an entry's place in the merge of the two sides' names (etc_join): its own place plus the other side's names below it,
// the first of its matches
func.func private @join_rank(%e: i32, %nA: i32, %byA: !pieces, %byB: !pieces) -> i32 {
  %inA = arith.cmpi slt, %e, %nA : i32
  %r = scf.if %inA -> (i32) {
    %m = trikeshed.at %byA[%e] : !pieces, i32 -> !tp
    %b = trikeshed.first %m : !tp -> i32
    %v = arith.addi %e, %b : i32
    scf.yield %v : i32
  } else {
    %j = arith.subi %e, %nA : i32
    %m = trikeshed.at %byB[%j] : !pieces, i32 -> !tp
    %a = trikeshed.first %m : !tp -> i32
    %v = arith.addi %j, %a : i32
    scf.yield %v : i32
  }
  return %r : i32
}

// ---- the cells of the options

memref.global "private" constant @k_true : memref<4xi8> = dense<[116, 114, 117, 101]>
memref.global "private" constant @k_modules : memref<8xi8> = dense<[109, 111, 100, 117, 108, 101, 115, 47]>

// a string's inside (between its quotes), or the fallback when row is -1 or not a string
func.func private @string_or(%tags: !text, %spans: !trikeshed.series<!tw>, %row: i32, %fallback: !tp) -> !tp {
  %zero = arith.constant 0 : i32
  %present = arith.cmpi sge, %row, %zero : i32
  %r = scf.if %present -> (!tp) {
    %string = arith.constant 4 : i8
    %tag = trikeshed.at %tags[%row] : !text, i32 -> i8
    %isString = arith.cmpi eq, %tag, %string : i8
    %r2 = scf.if %isString -> (!tp) {
      %one = arith.constant 1 : i32
      %sp = trikeshed.at %spans[%row] : !trikeshed.series<!tw>, i32 -> !tw
      %o = trikeshed.first %sp : !tw -> i32
      %c = trikeshed.second %sp : !tw -> i32
      %s = arith.addi %o, %one : i32
      %l = arith.subi %c, %s : i32
      %in = trikeshed.j %s, %l : i32, i32 -> !tp
      scf.yield %in : !tp
    } else {
      scf.yield %fallback : !tp
    }
    scf.yield %r2 : !tp
  } else {
    scf.yield %fallback : !tp
  }
  return %r : !tp
}

// a value's text as written: its span, both ends in
func.func private @raw_of(%spans: !trikeshed.series<!tw>, %row: i32) -> !tp {
  %one = arith.constant 1 : i32
  %sp = trikeshed.at %spans[%row] : !trikeshed.series<!tw>, i32 -> !tw
  %o = trikeshed.first %sp : !tw -> i32
  %c = trikeshed.second %sp : !tw -> i32
  %l0 = arith.subi %c, %o : i32
  %l = arith.addi %l0, %one : i32
  %raw = trikeshed.j %o, %l : i32, i32 -> !tp
  return %raw : !tp
}

// the first kid of a row (DirectChildren), or -1 when the row is -1 or has none
func.func private @first_kid(%kc: !pieces, %kids: !s32, %row: i32) -> i32 {
  %zero = arith.constant 0 : i32
  %none = arith.constant -1 : i32
  %present = arith.cmpi sge, %row, %zero : i32
  %r = scf.if %present -> (i32) {
    %fc = trikeshed.at %kc[%row] : !pieces, i32 -> !tp
    %f = trikeshed.first %fc : !tp -> i32
    %n = trikeshed.second %fc : !tp -> i32
    %some = arith.cmpi sgt, %n, %zero : i32
    %k = scf.if %some -> (i32) {
      %kid = trikeshed.at %kids[%f] : !s32, i32 -> i32
      scf.yield %kid : i32
    } else {
      scf.yield %none : i32
    }
    scf.yield %k : i32
  } else {
    scf.yield %none : i32
  }
  return %r : i32
}

// a type's name without its arguments: the first part of the piece at ' ' (Series.div)
func.func private @kind_of(%t: !text, %kin: !tp) -> !tp {
  %s = trikeshed.first %kin : !tp -> i32
  %n = trikeshed.second %kin : !tp -> i32
  %si = arith.index_cast %s : i32 to index
  %ni = arith.index_cast %n : i32 to index
  %bytes = trikeshed.slice %t[%si, %ni] : !text -> !text
  %space = arith.constant 32 : i8
  %ps = trikeshed.parts %bytes, %space : !text, i8 -> !pieces
  %c0 = arith.constant 0 : index
  %p0 = trikeshed.at %ps[%c0] : !pieces, index -> !tp
  %l = trikeshed.second %p0 : !tp -> i32
  %name = trikeshed.j %s, %l : i32, i32 -> !tp
  return %name : !tp
}

// "nixos/modules/services/networking/ssh/sshd.nix" -> "services/networking": the declaring module's place, two levels
// below the last "modules/" (a fold over the bytes keeps where the last one ends); the levels are the parts at '/'
// (Series.div) but the last, the file: one part is a file at the top, its own place; two, a directory; more, the first two
func.func private @module_of(%t: !text, %d: !tp, %mods: !text) -> !tp {
  %s = trikeshed.first %d : !tp -> i32
  %n = trikeshed.second %d : !tp -> i32
  %si = arith.index_cast %s : i32 to index
  %ni = arith.index_cast %n : i32 to index
  %bytes = trikeshed.slice %t[%si, %ni] : !text -> !text
  %z = arith.constant 0 : i32
  %start = trikeshed.j %z, %z : i32, i32 -> !tp
  // (bytes read, the end of the last "modules/" in them)
  %found = trikeshed.fold %bytes, %start : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %b: i8):
    %i = trikeshed.first %acc : !tp -> i32
    %last = trikeshed.second %acc : !tp -> i32
    %one = arith.constant 1 : i32
    %seven = arith.constant 7 : i32
    %slashc = arith.constant 47 : i8
    %isSlash = arith.cmpi eq, %b, %slashc : i8
    %room = arith.cmpi sge, %i, %seven : i32
    %maybe = arith.andi %isSlash, %room : i1
    %next = arith.addi %i, %one : i32
    %l2 = scf.if %maybe -> (i32) {
      %zero = arith.constant 0 : i32
      %at0 = arith.addi %s, %i : i32
      %at = arith.subi %at0, %seven : i32
      %ati = arith.index_cast %at : i32 to index
      %c8 = arith.constant 8 : index
      %word = trikeshed.slice %t[%ati, %c8] : !text -> !text
      %c = trikeshed.compare %word, %mods unsigned : !text, !text
      %is = arith.cmpi eq, %c, %zero : i32
      %l3 = arith.select %is, %next, %last : i32
      scf.yield %l3 : i32
    } else {
      scf.yield %last : i32
    }
    %acc2 = trikeshed.j %next, %l2 : i32, i32 -> !tp
    trikeshed.yield %acc2 : !tp
  }
  %r = trikeshed.second %found : !tp -> i32
  %rs = arith.addi %s, %r : i32
  %rn = arith.subi %n, %r : i32
  %rsi = arith.index_cast %rs : i32 to index
  %rni = arith.index_cast %rn : i32 to index
  %rest = trikeshed.slice %t[%rsi, %rni] : !text -> !text
  %slash = arith.constant 47 : i8
  %ps = trikeshed.parts %rest, %slash : !text, i8 -> !pieces
  %k = trikeshed.size %ps : !pieces
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %isFile = arith.cmpi eq, %k, %c1 : index
  %isDir = arith.cmpi eq, %k, %c2 : index
  %len = scf.if %isFile -> (i32) {
    scf.yield %rn : i32
  } else {
    %l = scf.if %isDir -> (i32) {
      %c0 = arith.constant 0 : index
      %p0 = trikeshed.at %ps[%c0] : !pieces, index -> !tp
      %l0 = trikeshed.second %p0 : !tp -> i32
      scf.yield %l0 : i32
    } else {
      %p1 = trikeshed.at %ps[%c1] : !pieces, index -> !tp
      %f1 = trikeshed.first %p1 : !tp -> i32
      %l1 = trikeshed.second %p1 : !tp -> i32
      %e1 = arith.addi %f1, %l1 : i32
      scf.yield %e1 : i32
    }
    scf.yield %l : i32
  }
  %place = trikeshed.j %rs, %len : i32, i32 -> !tp
  return %place : !tp
}

// The cells of each option of the members' table (opt_members), as pieces of t: its section, its value when valueShown is
// true (else -1), its state (or "?"), its kind (or "?"), its module (or "(none)").  qmark, none and empty are the pieces
// "?", "(none)" and "" (after the JSON in t).
func.func @opt_cells(%rows: !ix, %kids: !s32, %t: !text, %path: !s32, %shown: !s32, %value: !s32, %state: !s32,
                     %kind: !s32, %decl: !s32, %qmark: !tp, %none: !tp, %empty: !tp)
    -> (!pieces, !pieces, !pieces, !pieces, !pieces) attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !text
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !pieces
  %gt = memref.get_global @k_true : memref<4xi8>
  %true = trikeshed.text %gt : memref<4xi8> -> !text
  %gm = memref.get_global @k_modules : memref<8xi8>
  %mods = trikeshed.text %gm : memref<8xi8> -> !text
  %section = trikeshed.alpha %path : !s32 -> !pieces {
  ^bb0(%p: i32):
    %seg = func.call @first_kid(%kc, %kids, %p) : (!pieces, !s32, i32) -> i32
    %piece = func.call @string_or(%tags, %spans, %seg, %empty) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
    trikeshed.yield %piece : !tp
  }
  %n = trikeshed.size %shown : !s32
  %shownValue = trikeshed.series %n : !pieces {
  ^bb0(%i: index):
    %zero = arith.constant 0 : i32
    %m1 = arith.constant -1 : i32
    %hidden = trikeshed.j %m1, %m1 : i32, i32 -> !tp
    %sh = trikeshed.at %shown[%i] : !s32, index -> i32
    %v = trikeshed.at %value[%i] : !s32, index -> i32
    %hasSh = arith.cmpi sge, %sh, %zero : i32
    %hasV = arith.cmpi sge, %v, %zero : i32
    %both = arith.andi %hasSh, %hasV : i1
    %piece = scf.if %both -> (!tp) {
      %shr = func.call @raw_of(%spans, %sh) : (!trikeshed.series<!tw>, i32) -> !tp
      %ss = trikeshed.first %shr : !tp -> i32
      %sn = trikeshed.second %shr : !tp -> i32
      %ssi = arith.index_cast %ss : i32 to index
      %sni = arith.index_cast %sn : i32 to index
      %word = trikeshed.slice %t[%ssi, %sni] : !text -> !text
      %c = trikeshed.compare %word, %true unsigned : !text, !text
      %yes = arith.cmpi eq, %c, %zero : i32
      %vr = func.call @raw_of(%spans, %v) : (!trikeshed.series<!tw>, i32) -> !tp
      %r = arith.select %yes, %vr, %hidden : !tp
      scf.yield %r : !tp
    } else {
      scf.yield %hidden : !tp
    }
    trikeshed.yield %piece : !tp
  }
  %states = trikeshed.alpha %state : !s32 -> !pieces {
  ^bb0(%r: i32):
    %piece = func.call @string_or(%tags, %spans, %r, %qmark) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
    trikeshed.yield %piece : !tp
  }
  %kinds = trikeshed.alpha %kind : !s32 -> !pieces {
  ^bb0(%r: i32):
    %kin = func.call @string_or(%tags, %spans, %r, %qmark) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
    %name = func.call @kind_of(%t, %kin) : (!text, !tp) -> !tp
    trikeshed.yield %name : !tp
  }
  %modules = trikeshed.alpha %decl : !s32 -> !pieces {
  ^bb0(%d: i32):
    %zero = arith.constant 0 : i32
    %array = arith.constant 6 : i8
    %present = arith.cmpi sge, %d, %zero : i32
    %m = scf.if %present -> (!tp) {
      %tag = trikeshed.at %tags[%d] : !text, i32 -> i8
      %isArray = arith.cmpi eq, %tag, %array : i8
      %first = func.call @first_kid(%kc, %kids, %d) : (!pieces, !s32, i32) -> i32
      %some = arith.cmpi sge, %first, %zero : i32
      %ok = arith.andi %isArray, %some : i1
      %m2 = scf.if %ok -> (!tp) {
        %din = func.call @string_or(%tags, %spans, %first, %empty) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
        %dn = trikeshed.second %din : !tp -> i32
        %blank = arith.cmpi eq, %dn, %zero : i32
        %m3 = scf.if %blank -> (!tp) {
          scf.yield %none : !tp
        } else {
          %place = func.call @module_of(%t, %din, %mods) : (!text, !tp, !text) -> !tp
          scf.yield %place : !tp
        }
        scf.yield %m3 : !tp
      } else {
        scf.yield %none : !tp
      }
      scf.yield %m2 : !tp
    } else {
      scf.yield %none : !tp
    }
    trikeshed.yield %m : !tp
  }
  return %section, %shownValue, %states, %kinds, %modules : !pieces, !pieces, !pieces, !pieces, !pieces
}

// ---- the texts a corpus makes: the keys, and what each row is searched by

memref.global "private" constant @k_dot : memref<1xi8> = dense<[46]>
memref.global "private" constant @k_space : memref<1xi8> = dense<[32]>

// the children of a row (DirectChildren): its (first, count) into kids, or (0, 0) when the row is -1
func.func private @children_of(%kc: !pieces, %row: i32) -> !tp {
  %zero = arith.constant 0 : i32
  %present = arith.cmpi sge, %row, %zero : i32
  %r = scf.if %present -> (!tp) {
    %fc = trikeshed.at %kc[%row] : !pieces, i32 -> !tp
    scf.yield %fc : !tp
  } else {
    %nothing = trikeshed.j %zero, %zero : i32, i32 -> !tp
    scf.yield %nothing : !tp
  }
  return %r : !tp
}

// a byte lower-cased as an ASCII letter (Kotlin's lowercaseChar on the letters A to Z; any other byte is itself)
func.func private @ascii_lower(%x: i8) -> i8 {
  %cA = arith.constant 65 : i8
  %cZ = arith.constant 90 : i8
  %c32 = arith.constant 32 : i8
  %ge = arith.cmpi uge, %x, %cA : i8
  %le = arith.cmpi ule, %x, %cZ : i8
  %up = arith.andi %ge, %le : i1
  %l = arith.addi %x, %c32 : i8
  %r = arith.select %up, %l, %x : i8
  return %r : i8
}

// Each option's key, the segments of its path (pieces of t, as written between their quotes) with a '.' between each
// two, and what it is searched by, its key and its description (or the empty piece) with their escapes read and
// lower-cased, a ' ' between them: each as one text and each row's (start, length) in it.
func.func @opt_text(%rows: !ix, %kids: !s32, %t: !text, %path: !s32, %desc: !s32, %empty: !tp)
    -> (!text, !pieces, !text, !pieces) attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !trikeshed.series<!tw>
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !text
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !pieces
  %gd = memref.get_global @k_dot : memref<1xi8>
  %dot = trikeshed.text %gd : memref<1xi8> -> !text
  %gs = memref.get_global @k_space : memref<1xi8>
  %space = trikeshed.text %gs : memref<1xi8> -> !text
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %n = trikeshed.size %path : !s32
  %keys, %keyAt = trikeshed.combineAll %n : !text, !pieces {
  ^bb0(%i: index):
    %p = trikeshed.at %path[%i] : !s32, index -> i32
    %segs = func.call @children_of(%kc, %p) : (!pieces, i32) -> !tp
    %first = trikeshed.first %segs : !tp -> i32
    %count = trikeshed.second %segs : !tp -> i32
    %firsti = arith.index_cast %first : i32 to index
    %counti = arith.index_cast %count : i32 to index
    // the segments, and a '.' between each two: 2 count - 1 parts, or none
    %twice = arith.muli %counti, %two : index
    %between = arith.subi %twice, %one : index
    %m = arith.maxsi %between, %counti : index
    %key, %keyParts = trikeshed.combineAll %m : !text, !pieces {
    ^bb0(%k: index):
      %half = arith.divui %k, %two : index
      %rem = arith.remui %k, %two : index
      %isDot = arith.cmpi eq, %rem, %one : index
      %part = scf.if %isDot -> (!text) {
        scf.yield %dot : !text
      } else {
        %at = arith.addi %firsti, %half : index
        %seg = trikeshed.at %kids[%at] : !s32, index -> i32
        %in = func.call @string_or(%tags, %spans, %seg, %empty) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
        %s = trikeshed.first %in : !tp -> i32
        %l = trikeshed.second %in : !tp -> i32
        %si = arith.index_cast %s : i32 to index
        %li = arith.index_cast %l : i32 to index
        %bytes = trikeshed.slice %t[%si, %li] : !text -> !text
        scf.yield %bytes : !text
      }
      trikeshed.yield %part : !text
    }
    trikeshed.yield %key : !text
  }
  %hay, %hayAt = trikeshed.combineAll %n : !text, !pieces {
  ^bb0(%r: index):
    %kp = trikeshed.at %keyAt[%r] : !pieces, index -> !tp
    %ks = trikeshed.first %kp : !tp -> i32
    %kl = trikeshed.second %kp : !tp -> i32
    %ksi = arith.index_cast %ks : i32 to index
    %kli = arith.index_cast %kl : i32 to index
    %keyBytes = trikeshed.slice %keys[%ksi, %kli] : !text -> !text
    %d = trikeshed.at %desc[%r] : !s32, index -> i32
    %dp = func.call @string_or(%tags, %spans, %d, %empty) : (!text, !trikeshed.series<!tw>, i32, !tp) -> !tp
    %ds = trikeshed.first %dp : !tp -> i32
    %dl = trikeshed.second %dp : !tp -> i32
    %dsi = arith.index_cast %ds : i32 to index
    %dli = arith.index_cast %dl : i32 to index
    %descBytes = trikeshed.slice %t[%dsi, %dli] : !text -> !text
    %keyValue = confix.unescape json %keyBytes : !text -> !text
    %descValue = confix.unescape json %descBytes : !text -> !text
    %keyLower = trikeshed.alpha %keyValue : !text -> !text {
    ^bb0(%x: i8):
      %y = func.call @ascii_lower(%x) : (i8) -> i8
      trikeshed.yield %y : i8
    }
    %descLower = trikeshed.alpha %descValue : !text -> !text {
    ^bb0(%u: i8):
      %v = func.call @ascii_lower(%u) : (i8) -> i8
      trikeshed.yield %v : i8
    }
    %row = trikeshed.combine %keyLower, %space, %descLower : !text, !text, !text -> !text
    trikeshed.yield %row : !text
  }
  return %keys, %keyAt, %hay, %hayAt : !text, !pieces, !text, !pieces
}

// What a query is searched for: its bytes (a string's inside, as written in the request) read as the search text reads
// a key and a description, their escapes read and lower-cased.
func.func @query_text(%q: !text) -> !text attributes {llvm.emit_c_interface} {
  %value = confix.unescape json %q : !text -> !text
  %lower = trikeshed.alpha %value : !text -> !text {
  ^bb0(%x: i8):
    %y = func.call @ascii_lower(%x) : (i8) -> i8
    trikeshed.yield %y : i8
  }
  return %lower : !text
}
