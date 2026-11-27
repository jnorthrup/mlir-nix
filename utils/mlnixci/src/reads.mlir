// reads.mlir -- a text's bytes read where they lie, in TrikeShed's forms: what series.mlir's coordinates are searched and
// read with, and the errors of an evaluation kept.
//   rd_find    the first place of a byte: a fold whose accumulator is (the place found or -1, the place reached)
//   rd_search  the first place a text appears (memmem's): fractal fill-drain over the places it could start, in chunks
//              of 256 (a long text) and 16: a chunk's bytes equal to the text's first are counted, only the first chunk that has
//              one is searched at the next scale, and a chunk after the one that found it is not read; at 16, each place
//              whose byte agrees is compared with the text (trikeshed.compare of a slice)
//   rd_number  a decimal as atol reads one (blanks, a minus, digits; the first other byte ends it): two folds find where
//              the blanks and the digits end, a third folds the digits (Kotlin's CharSeries reading a Long)
//   rd_same    two texts with the same bytes: compare
//   rd_kept    the lines of an evaluation's errors that do not begin "evaluation warning:", each with its '\n': its parts
//              at '\n' (Series.div), those kept (where), combined (combineAll), and a NUL after them for the C library
// Compiled like columns.mlir, by mlnix-opt --trikeshed-lower-cursors; series.mlir and eval.mlir call these through their
// C interfaces, with @view's descriptors.  A text here is at most 2^31 bytes (a place is an i32 half of a TwinPacked).

!text = !trikeshed.series<i8>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>

memref.global "private" constant @rd_warning : memref<19xi8> = dense<"0x6576616C756174696F6E207761726E696E673A">  // evaluation warning:
memref.global "private" constant @rd_newline : memref<1xi8> = dense<10>
memref.global "private" constant @rd_nul : memref<1xi8> = dense<0>

// the first place of b in xs, or -1
func.func @rd_find(%xs: !text, %b: i8) -> i64 attributes {llvm.emit_c_interface} {
  %unset = arith.constant -1 : i32
  %zero = arith.constant 0 : i32
  %start = trikeshed.j %unset, %zero : i32, i32 -> !tp
  %end = trikeshed.fold %xs, %start : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %x: i8):
    %found = trikeshed.first %acc : !tp -> i32
    %i = trikeshed.second %acc : !tp -> i32
    %z = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %open = arith.cmpi slt, %found, %z : i32
    %is = arith.cmpi eq, %x, %b : i8
    %hit = arith.andi %open, %is : i1
    %found2 = arith.select %hit, %i, %found : i32
    %i2 = arith.addi %i, %one : i32
    %next = trikeshed.j %found2, %i2 : i32, i32 -> !tp
    trikeshed.yield %next : !tp
  }
  %p = trikeshed.first %end : !tp -> i32
  %r = arith.extsi %p : i32 to i64
  return %r : i64
}

// the first place q appears in xs, or -1 (0 for an empty q, as glibc's memmem): rd_first over every place it could start,
// in chunks of 16, or of 256 when there are more than 4096 places (measured: a row's search text, 40 to 400 bytes, is
// searched fastest by chunks of 16; a deeper start costs more than it skips)
func.func @rd_search(%xs: !text, %q: !text) -> i64 attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  %c256 = arith.constant 256 : index
  %c4096 = arith.constant 4096 : index
  %none = arith.constant -1 : i64
  %zero64 = arith.constant 0 : i64
  %n = trikeshed.size %xs : !text
  %m = trikeshed.size %q : !text
  %empty = arith.cmpi eq, %m, %c0 : index
  %short = arith.cmpi ult, %n, %m : index
  %r = scf.if %empty -> (i64) {
    scf.yield %zero64 : i64
  } else {
    %r2 = scf.if %short -> (i64) {
      scf.yield %none : i64
    } else {
      %head = trikeshed.at %q[%c0] : !text, index -> i8
      %nm = arith.subi %n, %m : index
      %places = arith.addi %nm, %c1 : index
      // chunks of 16 (a row's search text), of 256 above 4096 places (a request)
      %long = arith.cmpi ugt, %places, %c4096 : index
      %step = arith.select %long, %c256, %c16 : index
      %p = func.call @rd_first(%xs, %q, %head, %c0, %places, %step) : (!text, !text, i8, index, index, index) -> i32
      %pz = arith.extsi %p : i32 to i64
      scf.yield %pz : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

// The first of the places lo ..< lo + len where q appears in xs, or -1, searched as fractal fill-drain: the places are
// taken in chunks of step (a fold over as many of xs's bytes as there are chunks: only their count is read), a chunk is
// read only while nothing is found, its bytes equal to q's first are counted (a fold with no branch), and only a chunk
// that has one is searched again, in chunks a sixteenth the size, down to 16 places, which rd_search_in compares.
func.func private @rd_first(%xs: !text, %q: !text, %head: i8, %lo: index, %len: index, %step: index) -> i32 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c16 = arith.constant 16 : index
  %unset = arith.constant -1 : i32
  %leaf = arith.cmpi ule, %len, %c16 : index
  %r = scf.if %leaf -> (i32) {
    %window = trikeshed.slice %xs[%lo, %len] : !text -> !text
    %lo32 = arith.index_cast %lo : index to i32
    %at = func.call @rd_search_in(%xs, %q, %head, %lo32, %window) : (!text, !text, i8, i32, !text) -> i32
    scf.yield %at : i32
  } else {
    %s1 = arith.subi %step, %c1 : index
    %ls = arith.addi %len, %s1 : index
    %chunks = arith.divui %ls, %step : index
    %finer = arith.divui %step, %c16 : index
    %counter = trikeshed.slice %xs[%c0, %chunks] : !text -> !text
    %zero = arith.constant 0 : i32
    %start = trikeshed.j %unset, %zero : i32, i32 -> !tp
    %end = trikeshed.fold %counter, %start : !text, !tp -> !tp {
    ^bb0(%acc: !tp, %ignored: i8):
      %found = trikeshed.first %acc : !tp -> i32
      %k = trikeshed.second %acc : !tp -> i32
      %z = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      %open = arith.cmpi slt, %found, %z : i32
      %found2 = scf.if %open -> (i32) {
        %ki = arith.index_cast %k : i32 to index
        %off = arith.muli %ki, %step : index
        %clo = arith.addi %lo, %off : index
        %left = arith.subi %len, %off : index
        %clen = arith.minui %left, %step : index
        %window = trikeshed.slice %xs[%clo, %clen] : !text -> !text
        %heads = trikeshed.fold %window, %z : !text, i32 -> i32 {
        ^bb0(%h: i32, %x: i8):
          %is = arith.cmpi eq, %x, %head : i8
          %isz = arith.extui %is : i1 to i32
          %h2 = arith.addi %h, %isz : i32
          trikeshed.yield %h2 : i32
        }
        %some = arith.cmpi sgt, %heads, %z : i32
        %f = scf.if %some -> (i32) {
          %at = func.call @rd_first(%xs, %q, %head, %clo, %clen, %finer) : (!text, !text, i8, index, index, index) -> i32
          scf.yield %at : i32
        } else {
          scf.yield %unset : i32
        }
        scf.yield %f : i32
      } else {
        scf.yield %found : i32
      }
      %k2 = arith.addi %k, %one : i32
      %next = trikeshed.j %found2, %k2 : i32, i32 -> !tp
      trikeshed.yield %next : !tp
    }
    %p = trikeshed.first %end : !tp -> i32
    scf.yield %p : i32
  }
  return %r : i32
}

// the first of the places in window (xs's bytes from lo) where q appears in xs, or -1: a fold whose accumulator is (the
// place found or -1, the place reached); a place whose byte is q's first is compared with q
func.func private @rd_search_in(%xs: !text, %q: !text, %head: i8, %lo: i32, %window: !text) -> i32 {
  %m = trikeshed.size %q : !text
  %unset = arith.constant -1 : i32
  %start = trikeshed.j %unset, %lo : i32, i32 -> !tp
  %end = trikeshed.fold %window, %start : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %x: i8):
    %found = trikeshed.first %acc : !tp -> i32
    %i = trikeshed.second %acc : !tp -> i32
    %z = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %open = arith.cmpi slt, %found, %z : i32
    %agrees = arith.cmpi eq, %x, %head : i8
    %cand = arith.andi %open, %agrees : i1
    %hit = scf.if %cand -> (i1) {
      %ii = arith.index_cast %i : i32 to index
      %there = trikeshed.slice %xs[%ii, %m] : !text -> !text
      %order = trikeshed.compare %there, %q : !text, !text
      %same = arith.cmpi eq, %order, %z : i32
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
  return %p : i32
}

// how many of xs's first bytes are blanks (' ')
func.func private @rd_blanks(%xs: !text) -> index {
  %unset = arith.constant -1 : i32
  %zero = arith.constant 0 : i32
  %start = trikeshed.j %unset, %zero : i32, i32 -> !tp
  %end = trikeshed.fold %xs, %start : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %x: i8):
    %found = trikeshed.first %acc : !tp -> i32
    %i = trikeshed.second %acc : !tp -> i32
    %z = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %blank = arith.constant 32 : i8
    %open = arith.cmpi slt, %found, %z : i32
    %other = arith.cmpi ne, %x, %blank : i8
    %hit = arith.andi %open, %other : i1
    %found2 = arith.select %hit, %i, %found : i32
    %i2 = arith.addi %i, %one : i32
    %next = trikeshed.j %found2, %i2 : i32, i32 -> !tp
    trikeshed.yield %next : !tp
  }
  %p = trikeshed.first %end : !tp -> i32
  %z = arith.constant 0 : i32
  %all = arith.cmpi slt, %p, %z : i32
  %pi = arith.index_cast %p : i32 to index
  %n = trikeshed.size %xs : !text
  %r = arith.select %all, %n, %pi : index
  return %r : index
}

// how many of xs's first bytes are digits
func.func private @rd_digits(%xs: !text) -> index {
  %unset = arith.constant -1 : i32
  %zero = arith.constant 0 : i32
  %start = trikeshed.j %unset, %zero : i32, i32 -> !tp
  %end = trikeshed.fold %xs, %start : !text, !tp -> !tp {
  ^bb0(%acc: !tp, %x: i8):
    %found = trikeshed.first %acc : !tp -> i32
    %i = trikeshed.second %acc : !tp -> i32
    %z = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %d0 = arith.constant 48 : i8
    %nine = arith.constant 9 : i8
    %open = arith.cmpi slt, %found, %z : i32
    %d = arith.subi %x, %d0 : i8
    %other = arith.cmpi ugt, %d, %nine : i8
    %hit = arith.andi %open, %other : i1
    %found2 = arith.select %hit, %i, %found : i32
    %i2 = arith.addi %i, %one : i32
    %next = trikeshed.j %found2, %i2 : i32, i32 -> !tp
    trikeshed.yield %next : !tp
  }
  %p = trikeshed.first %end : !tp -> i32
  %z = arith.constant 0 : i32
  %all = arith.cmpi slt, %p, %z : i32
  %pi = arith.index_cast %p : i32 to index
  %n = trikeshed.size %xs : !text
  %r = arith.select %all, %n, %pi : index
  return %r : index
}

// xs's decimal, as atol reads one: blanks, a minus, digits (the value wraps as an i64 does)
func.func @rd_number(%xs: !text) -> i64 attributes {llvm.emit_c_interface} {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z64 = arith.constant 0 : i64
  %minus = arith.constant 45 : i8
  %n = trikeshed.size %xs : !text
  %lead = func.call @rd_blanks(%xs) : (!text) -> index
  %some = arith.cmpi ult, %lead, %n : index
  %neg = scf.if %some -> (i1) {
    %x = trikeshed.at %xs[%lead] : !text, index -> i8
    %m = arith.cmpi eq, %x, %minus : i8
    scf.yield %m : i1
  } else {
    %no = arith.constant false
    scf.yield %no : i1
  }
  %sign = arith.select %neg, %c1, %c0 : index
  %from = arith.addi %lead, %sign : index
  %left = arith.subi %n, %from : index
  %rest = trikeshed.slice %xs[%from, %left] : !text -> !text
  %run = func.call @rd_digits(%rest) : (!text) -> index
  %digits = trikeshed.slice %rest[%c0, %run] : !text -> !text
  %v = trikeshed.fold %digits, %z64 : !text, i64 -> i64 {
  ^bb0(%acc: i64, %x: i8):
    %ten = arith.constant 10 : i64
    %d0 = arith.constant 48 : i64
    %xz = arith.extui %x : i8 to i64
    %d = arith.subi %xz, %d0 : i64
    %a10 = arith.muli %acc, %ten : i64
    %next = arith.addi %a10, %d : i64
    trikeshed.yield %next : i64
  }
  %negv = arith.subi %z64, %v : i64
  %r = arith.select %neg, %negv, %v : i64
  return %r : i64
}

// the lines of e that do not begin "evaluation warning:", each followed by a '\n', then a NUL: a line is a part of e at
// '\n' that starts before e's end (so the empty part after a last '\n' is not one)
func.func @rd_kept(%e: !text) -> !text attributes {llvm.emit_c_interface} {
  %nl = arith.constant 10 : i8
  %gw = memref.get_global @rd_warning : memref<19xi8>
  %warning = trikeshed.text %gw : memref<19xi8> -> !text
  %gn = memref.get_global @rd_newline : memref<1xi8>
  %newline = trikeshed.text %gn : memref<1xi8> -> !text
  %gz = memref.get_global @rd_nul : memref<1xi8>
  %nul = trikeshed.text %gz : memref<1xi8> -> !text
  %n = trikeshed.size %e : !text
  %lines = trikeshed.parts %e, %nl : !text, i8 -> !pieces
  %kept = trikeshed.where %lines : !pieces -> !pieces {
  ^bb0(%p: !tp):
    %s = trikeshed.first %p : !tp -> i32
    %len = trikeshed.second %p : !tp -> i32
    %si = arith.index_cast %s : i32 to index
    %c19 = arith.constant 19 : i32
    %c19i = arith.constant 19 : index
    %z = arith.constant 0 : i32
    %inside = arith.cmpi ult, %si, %n : index
    %long = arith.cmpi sge, %len, %c19 : i32
    %warn = scf.if %long -> (i1) {
      %head = trikeshed.slice %e[%si, %c19i] : !text -> !text
      %order = trikeshed.compare %head, %warning : !text, !text
      %is = arith.cmpi eq, %order, %z : i32
      scf.yield %is : i1
    } else {
      %no = arith.constant false
      scf.yield %no : i1
    }
    %t = arith.constant true
    %other = arith.xori %warn, %t : i1
    %keep = arith.andi %inside, %other : i1
    trikeshed.yield %keep : i1
  }
  %k = trikeshed.size %kept : !pieces
  %all, %where = trikeshed.combineAll %k : !text, !pieces {
  ^bb0(%i: index):
    %p = trikeshed.at %kept[%i] : !pieces, index -> !tp
    %s = trikeshed.first %p : !tp -> i32
    %len = trikeshed.second %p : !tp -> i32
    %si = arith.index_cast %s : i32 to index
    %li = arith.index_cast %len : i32 to index
    %line = trikeshed.slice %e[%si, %li] : !text -> !text
    %part = trikeshed.combine %line, %newline : !text, !text -> !text
    trikeshed.yield %part : !text
  }
  %r = trikeshed.combine %all, %nul : !text, !text -> !text
  return %r : !text
}
