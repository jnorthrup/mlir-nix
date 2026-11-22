// Eval.cpp's error text hollowed into trikeshed fill-drain (appendCodeLines, chomp and the position headers of
// appendPos / formatParseError are gone; the bridge reads the source, decodes positions and keeps the traces' walk):
//   nixev_et_pos(file, fn, line, col, indent, with, text, tn, into, cap) -> size
//     "\n" + indent spaces + "at " + file + ":" + line + ":" + col + ":", then, when `with`, the code lines around
//     `line` of `text`: the text's lines are the windows between its newlines (trikeshed.where over the byte
//     indices: one more line than newlines), and each of lines line-1, line, line+1 that exists is "\n" +
//     (indent+1) spaces + "%5u" + "| " + the line, its trailing ' ' '\t' '\n' '\r' chomped (an all-blank line
//     loses the space after '|' too); under line, when col > 0, "\n" + indent spaces + "      |" + col spaces + "^".
//     ONE combine of the header and ONE combineAll of the four slots, drained once into `into` when the size fits
//     cap (the bridge sizes it: file + text + 5 indent + col + 128 always does).
//   nixev_et_indent(msg, n, into, cap) -> size
//     the message with seven spaces after each newline (formatError's continuation lines): one combineAll of the
//     message's newline-ended segments, each followed by its indent, drained once.
// The numbers are unsigned 32-bit in the C++ (line, col); the i64 arithmetic here is the same on that range.
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

// "\nat :|      |^ " -- '\n' 0, "at " 1..4, ':' 4, '|' 5, "      |" 6..13, '^' 13, ' ' 14
memref.global "private" constant @et_blob : memref<15xi8> = dense<[10, 97, 116, 32, 58, 124, 32, 32, 32, 32, 32, 32, 124, 94, 32]>
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

// n bytes at p as a text
func.func private @et_text(%p: !llvm.ptr, %n: i64) -> !s {
  %dd = func.call @et_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %dd : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  return %ss : !s
}

// n spaces, generated (no cells)
func.func private @et_spaces(%n: index) -> !s {
  %sp = arith.constant 32 : i8
  %r = trikeshed.series %n : !s {
  ^bb0(%k: index):
    trikeshed.yield %sp : i8
  }
  return %r : !s
}

// the decimal digits of x (unsigned, below 10^10), at least `width` wide: leading spaces, as printf's "%<width>u"
func.func private @et_dec(%x: i64, %width: index) -> !s {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c10 = arith.constant 10 : i64
  %zero = arith.constant 48 : i8
  %pg = memref.get_global @et_pow : memref<10xi64>
  %pow = trikeshed.text %pg : memref<10xi64> -> !s64
  %c9 = arith.constant 9 : index
  %above = trikeshed.slice %pow[%c1, %c9] : !s64 -> !s64
  %nd = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %x, %p : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %digits = trikeshed.series %nd : !s {
  ^bb0(%k: index):
    %last = arith.subi %nd, %c1 : index
    %e = arith.subi %last, %k : index
    %p = trikeshed.at %pow[%e] : !s64, index -> i64
    %q = arith.divui %x, %p : i64
    %dd = arith.remui %q, %c10 : i64
    %d8 = arith.trunci %dd : i64 to i8
    %ch = arith.addi %d8, %zero : i8
    trikeshed.yield %ch : i8
  }
  %short = arith.cmpi ult, %nd, %width : index
  %gap = arith.subi %width, %nd : index
  %padn = arith.select %short, %gap, %c0 : index
  %pad = func.call @et_spaces(%padn) : (index) -> !s
  %all = trikeshed.combine %pad, %digits : !s, !s -> !s
  return %all : !s
}

// the newline offsets of a text, in increasing order
func.func private @et_newlines(%tx: !s, %tn: i64) -> !s64 {
  %nl = arith.constant 10 : i8
  %tni = arith.index_cast %tn : i64 to index
  %idx = trikeshed.series %tni : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %nls = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%j: i64):
    %ji = arith.index_cast %j : i64 to index
    %ch = trikeshed.at %tx[%ji] : !s, index -> i8
    %is = arith.cmpi eq, %ch, %nl : i8
    trikeshed.yield %is : i1
  }
  return %nls : !s64
}

// drain `all` into n bytes at `into` when it fits; its size either way
func.func private @et_out(%all: !s, %into: !llvm.ptr, %cap: i64) -> i64 {
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

func.func @nixev_et_pos(%file: !llvm.ptr, %fn: i64, %line: i64, %col: i64, %indent: i64, %with: i64,
                        %text: !llvm.ptr, %tn: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %three = arith.constant 3 : index
  %four = arith.constant 4 : index
  %five = arith.constant 5 : index
  %six = arith.constant 6 : index
  %seven = arith.constant 7 : index
  %i13 = arith.constant 13 : index
  %i14 = arith.constant 14 : index
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %spc = arith.constant 32 : i8
  %tab = arith.constant 9 : i8
  %nlc = arith.constant 10 : i8
  %crc = arith.constant 13 : i8
  %bg = memref.get_global @et_blob : memref<15xi8>
  %blob = trikeshed.text %bg : memref<15xi8> -> !s
  %ind = arith.index_cast %indent : i64 to index
  // the header: "\n" indent "at " file ":" line ":" col ":"
  %nlw = trikeshed.slice %blob[%z, %one] : !s -> !s
  %indw = func.call @et_spaces(%ind) : (index) -> !s
  %atw = trikeshed.slice %blob[%one, %three] : !s -> !s
  %fw = func.call @et_text(%file, %fn) : (!llvm.ptr, i64) -> !s
  %colon = trikeshed.slice %blob[%four, %one] : !s -> !s
  %ld = func.call @et_dec(%line, %one) : (i64, index) -> !s
  %cd = func.call @et_dec(%col, %one) : (i64, index) -> !s
  %head = trikeshed.combine %nlw, %indw, %atw, %fw, %colon, %ld, %colon, %cd, %colon : !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
  // the code lines: four slots (line-1, line, the caret, line+1), each empty when it does not print
  %tx = func.call @et_text(%text, %tn) : (!llvm.ptr, i64) -> !s
  %nls = func.call @et_newlines(%tx, %tn) : (!s, i64) -> !s64
  %nnl = trikeshed.size %nls : !s64
  %nnl64 = arith.index_cast %nnl : index to i64
  %nlines = arith.addi %nnl64, %c1 : i64
  %w = arith.cmpi ne, %with, %c0 : i64
  %slots = arith.select %w, %four, %z : index
  %ind1 = arith.addi %ind, %one : index
  %lineHas = arith.cmpi uge, %line, %c1 : i64
  %lineIn = arith.cmpi ule, %line, %nlines : i64
  %lineOk = arith.andi %lineHas, %lineIn : i1
  %colPos = arith.cmpi ugt, %col, %c0 : i64
  %caretOk = arith.andi %lineOk, %colPos : i1
  %coli = arith.index_cast %col : i64 to index
  %lines, %where = trikeshed.combineAll %slots : !s, !coords {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %isCaret = arith.cmpi eq, %k, %two : index
    // the line of this slot: line-1, line, -, line+1
    %isLast = arith.cmpi eq, %k, %three : index
    %kk = arith.select %isLast, %c2, %k64 : i64
    %lnp = arith.addi %line, %kk : i64
    %ln = arith.subi %lnp, %c1 : i64
    %lnHas = arith.cmpi uge, %ln, %c1 : i64
    %lnIn = arith.cmpi ule, %ln, %nlines : i64
    %lnOk0 = arith.andi %lnHas, %lnIn : i1
    %notCaret = arith.cmpi ne, %k, %two : index
    %lnOk = arith.andi %lnOk0, %notCaret : i1
    // its window: after newline ln-2 (or 0) up to newline ln-1 (or the end); 0..0 when it does not print
    %lnS = arith.select %lnOk, %ln, %c1 : i64
    %first = arith.cmpi eq, %lnS, %c1 : i64
    %pi64 = arith.subi %lnS, %c2 : i64
    %pv = arith.select %first, %c0, %pi64 : i64
    %pvi = arith.index_cast %pv : i64 to index
    %nnlz = arith.cmpi eq, %nnl, %z : index
    %pvc = arith.select %nnlz, %z, %pvi : index
    %hasPrev = arith.cmpi ne, %nnl, %z : index
    %prevNl = scf.if %hasPrev -> (i64) {
      %pn = trikeshed.at %nls[%pvc] : !s64, index -> i64
      scf.yield %pn : i64
    } else {
      scf.yield %c0 : i64
    }
    %prevNl1 = arith.addi %prevNl, %c1 : i64
    %start = arith.select %first, %c0, %prevNl1 : i64
    %hasEnd = arith.cmpi ule, %lnS, %nnl64 : i64
    %ei64 = arith.subi %lnS, %c1 : i64
    %ei = arith.index_cast %ei64 : i64 to index
    %eic = arith.select %hasEnd, %ei, %z : index
    %nextNl = scf.if %hasEnd -> (i64) {
      %nn = trikeshed.at %nls[%eic] : !s64, index -> i64
      scf.yield %nn : i64
    } else {
      scf.yield %tn : i64
    }
    %stop = arith.select %hasEnd, %nextNl, %tn : i64
    %len0 = arith.subi %stop, %start : i64
    %len = arith.select %lnOk, %len0, %c0 : i64
    %starti = arith.index_cast %start : i64 to index
    %leni = arith.index_cast %len : i64 to index
    %body = trikeshed.slice %tx[%starti, %leni] : !s -> !s
    // chomped: the length up to its last byte that is not ' ' '\t' '\n' '\r'
    %idx = trikeshed.series %leni : !s64 {
    ^bb0(%q: index):
      %q64 = arith.index_cast %q : index to i64
      trikeshed.yield %q64 : i64
    }
    %keep = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc2: i64, %j: i64):
      %ji = arith.index_cast %j : i64 to index
      %ch2 = trikeshed.at %body[%ji] : !s, index -> i8
      %d1 = arith.cmpi eq, %ch2, %spc : i8
      %d2 = arith.cmpi eq, %ch2, %tab : i8
      %d3 = arith.cmpi eq, %ch2, %nlc : i8
      %d4 = arith.cmpi eq, %ch2, %crc : i8
      %d12 = arith.ori %d1, %d2 : i1
      %d34 = arith.ori %d3, %d4 : i1
      %blank2 = arith.ori %d12, %d34 : i1
      %j1 = arith.addi %j, %c1 : i64
      %nacc = arith.select %blank2, %acc2, %j1 : i64
      trikeshed.yield %nacc : i64
    }
    %keepi = arith.index_cast %keep : i64 to index
    %shown = trikeshed.slice %body[%z, %keepi] : !s -> !s
    %some = arith.cmpi ugt, %keep, %c0 : i64
    %sepn = arith.select %some, %one, %z : index
    %sep = trikeshed.slice %blob[%i14, %sepn] : !s -> !s
    %lnum = arith.select %lnOk, %ln, %c0 : i64
    %num = func.call @et_dec(%lnum, %five) : (i64, index) -> !s
    %bar = trikeshed.slice %blob[%five, %one] : !s -> !s
    %lead = func.call @et_spaces(%ind1) : (index) -> !s
    %lineText = trikeshed.combine %nlw, %lead, %num, %bar, %sep, %shown : !s, !s, !s, !s, !s, !s -> !s
    // the caret: "\n" indent "      |" col spaces "^"
    %cind = func.call @et_spaces(%ind) : (index) -> !s
    %cbar = trikeshed.slice %blob[%six, %seven] : !s -> !s
    %ccol = func.call @et_spaces(%coli) : (index) -> !s
    %hat = trikeshed.slice %blob[%i13, %one] : !s -> !s
    %caret = trikeshed.combine %nlw, %cind, %cbar, %ccol, %hat : !s, !s, !s, !s, !s -> !s
    %empty = trikeshed.slice %blob[%z, %z] : !s -> !s
    %lineOr = arith.select %lnOk, %lineText, %empty : !s
    %caretOr = arith.select %caretOk, %caret, %empty : !s
    %part = arith.select %isCaret, %caretOr, %lineOr : !s
    trikeshed.yield %part : !s
  }
  %all = trikeshed.combine %head, %lines : !s, !s -> !s
  %r = func.call @et_out(%all, %into, %cap) : (!s, !llvm.ptr, i64) -> i64
  return %r : i64
}

func.func @nixev_et_indent(%msg: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %seven = arith.constant 7 : index
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %tx = func.call @et_text(%msg, %n) : (!llvm.ptr, i64) -> !s
  %nls = func.call @et_newlines(%tx, %n) : (!s, i64) -> !s64
  %nnl = trikeshed.size %nls : !s64
  %segs = arith.addi %nnl, %one : index
  %ind = func.call @et_spaces(%seven) : (index) -> !s
  %all, %where = trikeshed.combineAll %segs : !s, !coords {
  ^bb0(%k: index):
    // segment k: after newline k-1 (or 0) through newline k (or the end), then the indent when a newline ends it
    %first = arith.cmpi eq, %k, %z : index
    %km1 = arith.subi %k, %one : index
    %pk = arith.select %first, %z, %km1 : index
    %prev = scf.if %first -> (i64) {
      scf.yield %c0 : i64
    } else {
      %pp = trikeshed.at %nls[%pk] : !s64, index -> i64
      scf.yield %pp : i64
    }
    %prev1 = arith.addi %prev, %c1 : i64
    %start = arith.select %first, %c0, %prev1 : i64
    %ended = arith.cmpi ult, %k, %nnl : index
    %kc = arith.select %ended, %k, %z : index
    %next = scf.if %ended -> (i64) {
      %nx = trikeshed.at %nls[%kc] : !s64, index -> i64
      scf.yield %nx : i64
    } else {
      scf.yield %n : i64
    }
    %next1 = arith.addi %next, %c1 : i64
    %stop = arith.select %ended, %next1, %n : i64
    %len = arith.subi %stop, %start : i64
    %starti = arith.index_cast %start : i64 to index
    %leni = arith.index_cast %len : i64 to index
    %seg = trikeshed.slice %tx[%starti, %leni] : !s -> !s
    %indn = arith.select %ended, %seven, %z : index
    %tail = trikeshed.slice %ind[%z, %indn] : !s -> !s
    %part = trikeshed.combine %seg, %tail : !s, !s -> !s
    trikeshed.yield %part : !s
  }
  %r = func.call @et_out(%all, %into, %cap) : (!s, !llvm.ptr, i64) -> i64
  return %r : i64
}
