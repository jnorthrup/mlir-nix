// Eval.cpp's error text hollowed into trikeshed fill-drain: formatError and formatParseError are ONE entry,
//   nixev_et_error(recs, n, into, cap) -> size (drained into `into` only when it fits cap)
// a combineAll over records of 14 words {kind, msg, mn, label, ln, hasPos, file, fn, line, col, indent, with, text,
// tn}, each record's text a combine of nested compositions:
//   kind 0, a trace:              "\n       … " msg [pos] "\n"
//   kind 1, the error, no traces: "error: " msg' [pos]
//   kind 2, the error after them: "\n       error: " msg' [pos]
//   kind 3, a parse error:        label ": " msg [pos]
//   kind 4, the start of a trace list: "error:"
// msg' is the message with seven spaces after each newline (a nested combineAll over its newline-ended segments;
// kinds 0 and 3 take them with no indent).  [pos], when hasPos: "\n" + indent spaces + "at " + file + ":" + line +
// ":" + col + ":", then, when `with`, the code lines around `line` of `text` (a nested combineAll of four slots):
// the text's lines are the windows between its newlines (trikeshed.where over the byte indices: one more line than
// newlines), and each of lines line-1, line, line+1 that exists is "\n" + (indent+1) spaces + "%5u" + "| " + the
// line, its trailing ' ' '\t' '\n' '\r' chomped (an all-blank line loses the space after '|' too); under line, when
// col > 0, "\n" + indent spaces + "      |" + col spaces + "^".  The bridge decodes the positions, reads the sources
// (sourceFor) and lays the records out, outermost trace first; the formatting is all here.
// The numbers are unsigned 32-bit in the C++ (line, col); the i64 arithmetic here is the same on that range.
// Every series is made in the entry that drains it: a helper returning one would be cloned (the dealloc pass), so
// helpers return descriptors and scalars only.
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

// "\n       error: " 0..15 ('\n' 0, "\n       " 0..8, "error: " 8..15, "error:" 8..14, ": " 13..15, ' ' 14),
// "… " 15..19, "at " 19..22, ':' 22, '|' 23, "      |" 24..31, '^' 31
memref.global "private" constant @et_blob : memref<32xi8> = dense<[10, 32, 32, 32, 32, 32, 32, 32, 101, 114, 114, 111, 114, 58, 32, 226, 128, 166, 32, 97, 116, 32, 58, 124, 32, 32, 32, 32, 32, 32, 124, 94]>
memref.global "private" constant @et_pow : memref<10xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000]>

// the descriptor of n bytes at p
func.func private @et_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// how many decimal digits x (unsigned, below 10^10) has
func.func private @et_ndigits(%x: i64) -> index {
  %c1 = arith.constant 1 : index
  %c9 = arith.constant 9 : index
  %pg = memref.get_global @et_pow : memref<10xi64>
  %pow = trikeshed.text %pg : memref<10xi64> -> !s64
  %above = trikeshed.slice %pow[%c1, %c9] : !s64 -> !s64
  %nd = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %x, %p : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  return %nd : index
}

// digit k of the nd-digit decimal x, as a character
func.func private @et_digit(%x: i64, %nd: index, %k: index) -> i8 {
  %c1 = arith.constant 1 : index
  %c10 = arith.constant 10 : i64
  %zero = arith.constant 48 : i8
  %pg = memref.get_global @et_pow : memref<10xi64>
  %pow = trikeshed.text %pg : memref<10xi64> -> !s64
  %last = arith.subi %nd, %c1 : index
  %e = arith.subi %last, %k : index
  %p = trikeshed.at %pow[%e] : !s64, index -> i64
  %q = arith.divui %x, %p : i64
  %dd = arith.remui %q, %c10 : i64
  %d8 = arith.trunci %dd : i64 to i8
  %ch = arith.addi %d8, %zero : i8
  return %ch : i8
}

// is c one of the bytes chomp drops: ' ' '\t' '\n' '\r'
func.func private @et_blank(%ch: i8) -> i1 {
  %spc = arith.constant 32 : i8
  %tab = arith.constant 9 : i8
  %nlc = arith.constant 10 : i8
  %crc = arith.constant 13 : i8
  %d1 = arith.cmpi eq, %ch, %spc : i8
  %d2 = arith.cmpi eq, %ch, %tab : i8
  %d3 = arith.cmpi eq, %ch, %nlc : i8
  %d4 = arith.cmpi eq, %ch, %crc : i8
  %d12 = arith.ori %d1, %d2 : i1
  %d34 = arith.ori %d3, %d4 : i1
  %b = arith.ori %d12, %d34 : i1
  return %b : i1
}

// word w of record r
func.func private @et_word(%recs: !llvm.ptr, %r: index, %w: i64) -> i64 {
  %c14 = arith.constant 14 : i64
  %r64 = arith.index_cast %r : index to i64
  %base = arith.muli %r64, %c14 : i64
  %at = arith.addi %base, %w : i64
  %p = llvm.getelementptr %recs[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %p : !llvm.ptr -> i64
  return %v : i64
}

func.func @nixev_et_error(%recs: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %four = arith.constant 4 : index
  %five = arith.constant 5 : index
  %six = arith.constant 6 : index
  %seven = arith.constant 7 : index
  %eight = arith.constant 8 : index
  %i13 = arith.constant 13 : index
  %i15 = arith.constant 15 : index
  %i14 = arith.constant 14 : index
  %i19 = arith.constant 19 : index
  %i22 = arith.constant 22 : index
  %i23 = arith.constant 23 : index
  %i24 = arith.constant 24 : index
  %i31 = arith.constant 31 : index
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c13 = arith.constant 13 : i64
  %spc = arith.constant 32 : i8
  %nlc = arith.constant 10 : i8
  %bg = memref.get_global @et_blob : memref<32xi8>
  %blob = trikeshed.text %bg : memref<32xi8> -> !s
  %nlw = trikeshed.slice %blob[%z, %one] : !s -> !s
  %empty = trikeshed.slice %blob[%z, %z] : !s -> !s
  %ni = arith.index_cast %n : i64 to index
  %all, %where = trikeshed.combineAll %ni : !s, !coords {
  ^bb0(%r: index):
    %kind = func.call @et_word(%recs, %r, %c0) : (!llvm.ptr, index, i64) -> i64
    %mp = func.call @et_word(%recs, %r, %c1) : (!llvm.ptr, index, i64) -> i64
    %mn = func.call @et_word(%recs, %r, %c2) : (!llvm.ptr, index, i64) -> i64
    %lp = func.call @et_word(%recs, %r, %c3) : (!llvm.ptr, index, i64) -> i64
    %lnn = func.call @et_word(%recs, %r, %c4) : (!llvm.ptr, index, i64) -> i64
    %hasPos = func.call @et_word(%recs, %r, %c5) : (!llvm.ptr, index, i64) -> i64
    %fp = func.call @et_word(%recs, %r, %c6) : (!llvm.ptr, index, i64) -> i64
    %fn = func.call @et_word(%recs, %r, %c7) : (!llvm.ptr, index, i64) -> i64
    %line = func.call @et_word(%recs, %r, %c8) : (!llvm.ptr, index, i64) -> i64
    %col = func.call @et_word(%recs, %r, %c9) : (!llvm.ptr, index, i64) -> i64
    %indent = func.call @et_word(%recs, %r, %c10) : (!llvm.ptr, index, i64) -> i64
    %with = func.call @et_word(%recs, %r, %c11) : (!llvm.ptr, index, i64) -> i64
    %tp = func.call @et_word(%recs, %r, %c12) : (!llvm.ptr, index, i64) -> i64
    %tn = func.call @et_word(%recs, %r, %c13) : (!llvm.ptr, index, i64) -> i64
    %k0 = arith.cmpi eq, %kind, %c0 : i64
    %k1 = arith.cmpi eq, %kind, %c1 : i64
    %k2 = arith.cmpi eq, %kind, %c2 : i64
    %k3 = arith.cmpi eq, %kind, %c3 : i64
    // the lead: "\n       " "… " (0), "error: " (1), "\n       error: " (2), label ": " (3), "error:" (4)
    %as01 = arith.select %k0, %z, %eight : index
    %as = arith.select %k2, %z, %as01 : index
    %al0 = arith.select %k0, %eight, %six : index
    %al1 = arith.select %k1, %seven, %al0 : index
    %al = arith.select %k2, %i15, %al1 : index
    %leadBlob = trikeshed.slice %blob[%as, %al] : !s -> !s
    %lpp = llvm.inttoptr %lp : i64 to !llvm.ptr
    %labd = func.call @et_desc(%lpp, %lnn) : (!llvm.ptr, i64) -> !d
    %labm = builtin.unrealized_conversion_cast %labd : !d to !m
    %label = builtin.unrealized_conversion_cast %labm : !m to !s
    %leadA = arith.select %k3, %label, %leadBlob : !s
    %bs = arith.select %k0, %i15, %i13 : index
    %bl0 = arith.select %k0, %four, %z : index
    %bl = arith.select %k3, %two, %bl0 : index
    %leadB = trikeshed.slice %blob[%bs, %bl] : !s -> !s
    // the message, seven spaces after each newline for the error itself (kinds 1, 2)
    %mpp = llvm.inttoptr %mp : i64 to !llvm.ptr
    %msgd = func.call @et_desc(%mpp, %mn) : (!llvm.ptr, i64) -> !d
    %msgm = builtin.unrealized_conversion_cast %msgd : !d to !m
    %msg = builtin.unrealized_conversion_cast %msgm : !m to !s
    %k12 = arith.ori %k1, %k2 : i1
    %step = arith.select %k12, %seven, %z : index
    %mni = arith.index_cast %mn : i64 to index
    %midx = trikeshed.series %mni : !s64 {
    ^bb0(%q: index):
      %q64 = arith.index_cast %q : index to i64
      trikeshed.yield %q64 : i64
    }
    %mnls = trikeshed.where %midx : !s64 -> !s64 {
    ^bb0(%j: i64):
      %ji = arith.index_cast %j : i64 to index
      %ch = trikeshed.at %msg[%ji] : !s, index -> i8
      %is = arith.cmpi eq, %ch, %nlc : i8
      trikeshed.yield %is : i1
    }
    %mnnl = trikeshed.size %mnls : !s64
    %msegs = arith.addi %mnnl, %one : index
    %body, %bwhere = trikeshed.combineAll %msegs : !s, !coords {
    ^bb0(%k: index):
      %first = arith.cmpi eq, %k, %z : index
      %km1 = arith.subi %k, %one : index
      %start = scf.if %first -> (i64) {
        scf.yield %c0 : i64
      } else {
        %pp = trikeshed.at %mnls[%km1] : !s64, index -> i64
        %pp1 = arith.addi %pp, %c1 : i64
        scf.yield %pp1 : i64
      }
      %ended = arith.cmpi ult, %k, %mnnl : index
      %stop = scf.if %ended -> (i64) {
        %nx = trikeshed.at %mnls[%k] : !s64, index -> i64
        %nx1 = arith.addi %nx, %c1 : i64
        scf.yield %nx1 : i64
      } else {
        scf.yield %mn : i64
      }
      %len = arith.subi %stop, %start : i64
      %starti = arith.index_cast %start : i64 to index
      %leni = arith.index_cast %len : i64 to index
      %seg = trikeshed.slice %msg[%starti, %leni] : !s -> !s
      %indn = arith.select %ended, %step, %z : index
      %tail = trikeshed.series %indn : !s {
      ^bb0(%q: index):
        trikeshed.yield %spc : i8
      }
      %part = trikeshed.combine %seg, %tail : !s, !s -> !s
      trikeshed.yield %part : !s
    }
    // [pos]: "\n" indent "at " file ":" line ":" col ":", then the code lines
    %has = arith.cmpi ne, %hasPos, %c0 : i64
    %ind = arith.index_cast %indent : i64 to index
    %spaces = trikeshed.series %ind : !s {
    ^bb0(%k: index):
      trikeshed.yield %spc : i8
    }
    %atw = trikeshed.slice %blob[%i19, %three] : !s -> !s
    %fpp = llvm.inttoptr %fp : i64 to !llvm.ptr
    %fd = func.call @et_desc(%fpp, %fn) : (!llvm.ptr, i64) -> !d
    %fm = builtin.unrealized_conversion_cast %fd : !d to !m
    %fw = builtin.unrealized_conversion_cast %fm : !m to !s
    %colon = trikeshed.slice %blob[%i22, %one] : !s -> !s
    %lnd = func.call @et_ndigits(%line) : (i64) -> index
    %ldig = trikeshed.series %lnd : !s {
    ^bb0(%k: index):
      %ch = func.call @et_digit(%line, %lnd, %k) : (i64, index, index) -> i8
      trikeshed.yield %ch : i8
    }
    %cnd = func.call @et_ndigits(%col) : (i64) -> index
    %cdig = trikeshed.series %cnd : !s {
    ^bb0(%k: index):
      %ch = func.call @et_digit(%col, %cnd, %k) : (i64, index, index) -> i8
      trikeshed.yield %ch : i8
    }
    %head0 = trikeshed.combine %nlw, %spaces, %atw, %fw, %colon, %ldig, %colon, %cdig, %colon : !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
    %head = arith.select %has, %head0, %empty : !s
    // the code lines: four slots (line-1, line, the caret, line+1), each empty when it does not print
    %tpp = llvm.inttoptr %tp : i64 to !llvm.ptr
    %td = func.call @et_desc(%tpp, %tn) : (!llvm.ptr, i64) -> !d
    %tm = builtin.unrealized_conversion_cast %td : !d to !m
    %tx = builtin.unrealized_conversion_cast %tm : !m to !s
    %w0 = arith.cmpi ne, %with, %c0 : i64
    %w = arith.andi %w0, %has : i1
    %tnv = arith.select %w, %tn, %c0 : i64
    %tni = arith.index_cast %tnv : i64 to index
    %idx = trikeshed.series %tni : !s64 {
    ^bb0(%q: index):
      %q64 = arith.index_cast %q : index to i64
      trikeshed.yield %q64 : i64
    }
    %nls = trikeshed.where %idx : !s64 -> !s64 {
    ^bb0(%j: i64):
      %ji = arith.index_cast %j : i64 to index
      %ch = trikeshed.at %tx[%ji] : !s, index -> i8
      %is = arith.cmpi eq, %ch, %nlc : i8
      trikeshed.yield %is : i1
    }
    %nnl = trikeshed.size %nls : !s64
    %nnl64 = arith.index_cast %nnl : index to i64
    %nlines = arith.addi %nnl64, %c1 : i64
    %slots = arith.select %w, %four, %z : index
    %ind1 = arith.addi %ind, %one : index
    %lineHas = arith.cmpi uge, %line, %c1 : i64
    %lineIn = arith.cmpi ule, %line, %nlines : i64
    %lineOk = arith.andi %lineHas, %lineIn : i1
    %colPos = arith.cmpi ugt, %col, %c0 : i64
    %caretOk = arith.andi %lineOk, %colPos : i1
    %coli = arith.index_cast %col : i64 to index
    %lines, %lwhere = trikeshed.combineAll %slots : !s, !coords {
    ^bb0(%k: index):
      %k64 = arith.index_cast %k : index to i64
      %isCaret = arith.cmpi eq, %k, %two : index
      %isLast = arith.cmpi eq, %k, %three : index
      // the line of this slot: line-1, line, -, line+1
      %kk = arith.select %isLast, %c2, %k64 : i64
      %lnp = arith.addi %line, %kk : i64
      %ln = arith.subi %lnp, %c1 : i64
      %lnHas = arith.cmpi uge, %ln, %c1 : i64
      %lnIn = arith.cmpi ule, %ln, %nlines : i64
      %lnOk0 = arith.andi %lnHas, %lnIn : i1
      %notCaret = arith.cmpi ne, %k, %two : index
      %lnOk = arith.andi %lnOk0, %notCaret : i1
      // its window: after newline ln-2 (or from 0) up to newline ln-1 (or the end); empty when it does not print
      %lnS = arith.select %lnOk, %ln, %c1 : i64
      %first = arith.cmpi eq, %lnS, %c1 : i64
      %pv = arith.subi %lnS, %c2 : i64
      %pvi = arith.index_cast %pv : i64 to index
      %start = scf.if %first -> (i64) {
        scf.yield %c0 : i64
      } else {
        %pn = trikeshed.at %nls[%pvi] : !s64, index -> i64
        %pn1 = arith.addi %pn, %c1 : i64
        scf.yield %pn1 : i64
      }
      %hasEnd = arith.cmpi ule, %lnS, %nnl64 : i64
      %ei64 = arith.subi %lnS, %c1 : i64
      %ei = arith.index_cast %ei64 : i64 to index
      %stop = scf.if %hasEnd -> (i64) {
        %nn = trikeshed.at %nls[%ei] : !s64, index -> i64
        scf.yield %nn : i64
      } else {
        scf.yield %tnv : i64
      }
      %len0 = arith.subi %stop, %start : i64
      %len = arith.select %lnOk, %len0, %c0 : i64
      %starti = arith.index_cast %start : i64 to index
      %leni = arith.index_cast %len : i64 to index
      %lbody = trikeshed.slice %tx[%starti, %leni] : !s -> !s
      // chomped: up to its last byte that is not ' ' '\t' '\n' '\r'
      %bidx = trikeshed.series %leni : !s64 {
      ^bb0(%q: index):
        %q64 = arith.index_cast %q : index to i64
        trikeshed.yield %q64 : i64
      }
      %keep = trikeshed.fold %bidx, %c0 : !s64, i64 -> i64 {
      ^bb0(%acc: i64, %j: i64):
        %ji = arith.index_cast %j : i64 to index
        %ch = trikeshed.at %lbody[%ji] : !s, index -> i8
        %blank = func.call @et_blank(%ch) : (i8) -> i1
        %j1 = arith.addi %j, %c1 : i64
        %nacc = arith.select %blank, %acc, %j1 : i64
        trikeshed.yield %nacc : i64
      }
      %keepi = arith.index_cast %keep : i64 to index
      %shown = trikeshed.slice %lbody[%z, %keepi] : !s -> !s
      %some = arith.cmpi ugt, %keep, %c0 : i64
      %sepn = arith.select %some, %one, %z : index
      %sep = trikeshed.slice %blob[%i14, %sepn] : !s -> !s
      // "%5u": the number right-aligned in five columns, wider when it has more digits
      %lnum = arith.select %lnOk, %ln, %c0 : i64
      %nd = func.call @et_ndigits(%lnum) : (i64) -> index
      %short = arith.cmpi ult, %nd, %five : index
      %gap = arith.subi %five, %nd : index
      %padn = arith.select %short, %gap, %z : index
      %padw = arith.addi %ind1, %padn : index
      %lead = trikeshed.series %padw : !s {
      ^bb0(%q: index):
        trikeshed.yield %spc : i8
      }
      %num = trikeshed.series %nd : !s {
      ^bb0(%q: index):
        %ch = func.call @et_digit(%lnum, %nd, %q) : (i64, index, index) -> i8
        trikeshed.yield %ch : i8
      }
      %bar = trikeshed.slice %blob[%i23, %one] : !s -> !s
      %lineText = trikeshed.combine %nlw, %lead, %num, %bar, %sep, %shown : !s, !s, !s, !s, !s, !s -> !s
      // the caret: "\n" indent "      |" col spaces "^"
      %cbar = trikeshed.slice %blob[%i24, %seven] : !s -> !s
      %ccol = trikeshed.series %coli : !s {
      ^bb0(%q: index):
        trikeshed.yield %spc : i8
      }
      %hat = trikeshed.slice %blob[%i31, %one] : !s -> !s
      %caret = trikeshed.combine %nlw, %spaces, %cbar, %ccol, %hat : !s, !s, !s, !s, !s -> !s
      %lineOr = arith.select %lnOk, %lineText, %empty : !s
      %caretOr = arith.select %caretOk, %caret, %empty : !s
      %part = arith.select %isCaret, %caretOr, %lineOr : !s
      trikeshed.yield %part : !s
    }
    // a trace ends its line
    %trl = arith.select %k0, %one, %z : index
    %trailer = trikeshed.slice %blob[%z, %trl] : !s -> !s
    %rec = trikeshed.combine %leadA, %leadB, %body, %head, %lines, %trailer : !s, !s, !s, !s, !s, !s -> !s
    trikeshed.yield %rec : !s
  }
  %sz = trikeshed.size %all : !s
  %sz64 = arith.index_cast %sz : index to i64
  %fits = arith.cmpi ule, %sz64, %cap : i64
  scf.if %fits {
    %om = func.call @et_desc(%into, %sz64) : (!llvm.ptr, i64) -> !d
    %omm = builtin.unrealized_conversion_cast %om : !d to !m
    %end = trikeshed.drain %all, %omm : !s, !m -> index
  }
  return %sz64 : i64
}
