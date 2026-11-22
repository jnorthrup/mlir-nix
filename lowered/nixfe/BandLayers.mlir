// confix::lexBands' band layering (Parser.cpp's token switch and Confix.h's Layers are gone; the bridge lexes the
// tokens and adopts the rows).  The lexer's tokens arrive as one word each (kind | ch << 8 | offset << 16); a token's
// action is a lookup in two constant tables (by kind, and by character for T_CHAR), act | k1 << 8 | k2 << 16:
//   1 open a band of kind k1 at the token; 2 close the innermost band, which must be of kind k1 or k2 (else false);
//   3 a `with` / `assert`: the next semicolon of its band is owed to it; 4 ';' (an end of its band unless owed);
//   5 ',' (an end of its band); 6 end of input (true when nothing is open); 7 '"' (close the string band the
//   quote is inside of, else open one); 8 `let` (opens a band unless a '{' follows: `let { }`); 9 a T_CHAR.
//   nixfe_lb_layers(toks, n, total, ebase, rows, ends, stack, pend, counts) -> 1 balanced, 0 not
// walks the first n of the total tokens (the lookahead reads token i+1); rows are 5 words {open, close, kind,
// first, count} in the order bands open (close 0 and first/count 0 while open), ends the qualified semicolons and
// commas in the order bands close (each close drains its band's pending slice: trikeshed.slice + drain), stack 3
// words {row, owed, from} an open band, pend the ends met and not yet claimed.  counts gets {rows, ends}.  The
// caller's scratch holds n rows, n ends, n stack entries and n pending ends.  n < total, with no end of input
// reached, is a lexer error past token n: false, the rows as they stand.
!s64 = !trikeshed.series<i64>
!s32 = !trikeshed.series<i32>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @lb_tok : memref<64xi32> = dense<[6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9217, 9985, 2565890, 0, 0, 0, 3, 3, 27656, 7105538, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>
memref.global "private" constant @lb_ch : memref<256xi32> = dense<[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2236935, 0, 0, 0, 0, 0, 10241, 2631682, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 23297, 0, 5987074, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 31489, 0, 2390786, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]>

// the descriptor of n words at p
func.func private @lb_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// cell k of a word table
func.func private @lb_ld(%m: memref<?xi64>, %k: i64) -> i64 {
  %ki = arith.index_cast %k : i64 to index
  %v = memref.load %m[%ki] : memref<?xi64>
  return %v : i64
}
func.func private @lb_st(%m: memref<?xi64>, %k: i64, %v: i64) {
  %ki = arith.index_cast %k : i64 to index
  memref.store %v, %m[%ki] : memref<?xi64>
  return
}

// the action entry of a token word (and of the token after it, for `let`): act | k1 << 8 | k2 << 16
func.func private @lb_entry(%w: i64, %next: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c36 = arith.constant 36 : i64
  %c64 = arith.constant 64 : i64
  %c123 = arith.constant 123 : i64
  %c255 = arith.constant 255 : i64
  %kind = arith.andi %w, %c255 : i64
  %chs = arith.shrui %w, %c8 : i64
  %ch = arith.andi %chs, %c255 : i64
  %tg = memref.get_global @lb_tok : memref<64xi32>
  %toks = trikeshed.text %tg : memref<64xi32> -> !s32
  %cg = memref.get_global @lb_ch : memref<256xi32>
  %chars = trikeshed.text %cg : memref<256xi32> -> !s32
  %known = arith.cmpi ult, %kind, %c64 : i64
  %ki = arith.index_cast %kind : i64 to index
  %e0 = scf.if %known -> (i64) {
    %t = trikeshed.at %toks[%ki] : !s32, index -> i32
    %t64 = arith.extui %t : i32 to i64
    scf.yield %t64 : i64
  } else {
    scf.yield %c0 : i64
  }
  %byChar = arith.cmpi eq, %e0, %c9 : i64
  %chi = arith.index_cast %ch : i64 to index
  %ce = trikeshed.at %chars[%chi] : !s32, index -> i32
  %ce64 = arith.extui %ce : i32 to i64
  %e1 = arith.select %byChar, %ce64, %e0 : i64
  // `let` followed by '{' is the old `let { }`: no band
  %act = arith.andi %e1, %c255 : i64
  %isLet = arith.cmpi eq, %act, %c8 : i64
  %nk = arith.andi %next, %c255 : i64
  %nchs = arith.shrui %next, %c8 : i64
  %nch = arith.andi %nchs, %c255 : i64
  %nIsChar = arith.cmpi eq, %nk, %c36 : i64
  %nIsBrace = arith.cmpi eq, %nch, %c123 : i64
  %braced = arith.andi %nIsChar, %nIsBrace : i1
  // opened, it is action 1 with the same kinds
  %c1 = arith.constant 1 : i64
  %kinds = arith.subi %e1, %act : i64
  %letE = arith.ori %kinds, %c1 : i64
  %letR = arith.select %braced, %c0, %letE : i64
  %e2 = arith.select %isLet, %letR, %e1 : i64
  return %e2 : i64
}

func.func @nixfe_lb_layers(%toksp: !llvm.ptr, %n: i64, %total: i64, %ebase: i64, %rowsp: !llvm.ptr, %endsp: !llvm.ptr,
                           %stackp: !llvm.ptr, %pendp: !llvm.ptr, %countsp: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c255 = arith.constant 255 : i64
  %cm1 = arith.constant -1 : i64
  %n5 = arith.muli %n, %c5 : i64
  %n3 = arith.muli %n, %c3 : i64
  %td = func.call @lb_desc(%toksp, %total) : (!llvm.ptr, i64) -> !d
  %toks = builtin.unrealized_conversion_cast %td : !d to memref<?xi64>
  %rd = func.call @lb_desc(%rowsp, %n5) : (!llvm.ptr, i64) -> !d
  %rows = builtin.unrealized_conversion_cast %rd : !d to memref<?xi64>
  %ed = func.call @lb_desc(%endsp, %n) : (!llvm.ptr, i64) -> !d
  %ends = builtin.unrealized_conversion_cast %ed : !d to memref<?xi64>
  %sd = func.call @lb_desc(%stackp, %n3) : (!llvm.ptr, i64) -> !d
  %stack = builtin.unrealized_conversion_cast %sd : !d to memref<?xi64>
  %pd = func.call @lb_desc(%pendp, %n) : (!llvm.ptr, i64) -> !d
  %pend = builtin.unrealized_conversion_cast %pd : !d to memref<?xi64>
  %pendS = trikeshed.text %pend : memref<?xi64> -> !s64
  // state: token, open bands, rows, pending ends, ends, semicolons owed at the root, status (-1 running, 0, 1)
  %fin:7 = scf.while (%i = %c0, %sp = %c0, %nr = %c0, %np = %c0, %ne = %c0, %ow = %c0, %st = %cm1)
      : (i64, i64, i64, i64, i64, i64, i64) -> (i64, i64, i64, i64, i64, i64, i64) {
    %run = arith.cmpi eq, %st, %cm1 : i64
    %more = arith.cmpi ult, %i, %n : i64
    %go = arith.andi %run, %more : i1
    scf.condition(%go) %i, %sp, %nr, %np, %ne, %ow, %st : i64, i64, i64, i64, i64, i64, i64
  } do {
  ^bb0(%i: i64, %sp: i64, %nr: i64, %np: i64, %ne: i64, %ow: i64, %st: i64):
    %w = func.call @lb_ld(%toks, %i) : (memref<?xi64>, i64) -> i64
    %i1 = arith.addi %i, %c1 : i64
    %hasNext = arith.cmpi ult, %i1, %total : i64
    %nx = scf.if %hasNext -> (i64) {
      %v = func.call @lb_ld(%toks, %i1) : (memref<?xi64>, i64) -> i64
      scf.yield %v : i64
    } else {
      scf.yield %w : i64
    }
    %off = arith.shrui %w, %c16 : i64
    %e = func.call @lb_entry(%w, %nx) : (i64, i64) -> i64
    %act0 = arith.andi %e, %c255 : i64
    %k1s = arith.shrui %e, %c8 : i64
    %k1 = arith.andi %k1s, %c255 : i64
    %k2s = arith.shrui %e, %c16 : i64
    %k2 = arith.andi %k2s, %c255 : i64
    // the innermost open band's row and kind (when one is open)
    %open = arith.cmpi ugt, %sp, %c0 : i64
    %spm1 = arith.subi %sp, %c1 : i64
    %top3 = arith.muli %spm1, %c3 : i64
    %topKind = scf.if %open -> (i64) {
      %row = func.call @lb_ld(%stack, %top3) : (memref<?xi64>, i64) -> i64
      %r5 = arith.muli %row, %c5 : i64
      %r52 = arith.addi %r5, %c2 : i64
      %kk = func.call @lb_ld(%rows, %r52) : (memref<?xi64>, i64) -> i64
      scf.yield %kk : i64
    } else {
      scf.yield %c0 : i64
    }
    // '"': close the string band it is inside of, else open one
    %isQuote = arith.cmpi eq, %act0, %c7 : i64
    %inStr0 = arith.cmpi eq, %topKind, %k1 : i64
    %inStr = arith.andi %open, %inStr0 : i1
    %qAct = arith.select %inStr, %c2, %c1 : i64
    %act = arith.select %isQuote, %qAct, %act0 : i64
    %isOpen = arith.cmpi eq, %act, %c1 : i64
    %isClose = arith.cmpi eq, %act, %c2 : i64
    %isOwe = arith.cmpi eq, %act, %c3 : i64
    %isSemi = arith.cmpi eq, %act, %c4 : i64
    %isComma = arith.cmpi eq, %act, %c5 : i64
    %isEof = arith.cmpi eq, %act, %c6 : i64
    %r:6 = scf.if %isOpen -> (i64, i64, i64, i64, i64, i64) {
      // a new row {off, 0, k1, 0, 0}, and the band on the stack {row, 0 owed, its ends from np}
      %r5 = arith.muli %nr, %c5 : i64
      func.call @lb_st(%rows, %r5, %off) : (memref<?xi64>, i64, i64) -> ()
      %r51 = arith.addi %r5, %c1 : i64
      func.call @lb_st(%rows, %r51, %c0) : (memref<?xi64>, i64, i64) -> ()
      %r52 = arith.addi %r5, %c2 : i64
      func.call @lb_st(%rows, %r52, %k1) : (memref<?xi64>, i64, i64) -> ()
      %r53 = arith.addi %r5, %c3 : i64
      func.call @lb_st(%rows, %r53, %c0) : (memref<?xi64>, i64, i64) -> ()
      %r54 = arith.addi %r5, %c4 : i64
      func.call @lb_st(%rows, %r54, %c0) : (memref<?xi64>, i64, i64) -> ()
      %s3 = arith.muli %sp, %c3 : i64
      func.call @lb_st(%stack, %s3, %nr) : (memref<?xi64>, i64, i64) -> ()
      %s31 = arith.addi %s3, %c1 : i64
      func.call @lb_st(%stack, %s31, %c0) : (memref<?xi64>, i64, i64) -> ()
      %s32 = arith.addi %s3, %c2 : i64
      func.call @lb_st(%stack, %s32, %np) : (memref<?xi64>, i64, i64) -> ()
      %sp1 = arith.addi %sp, %c1 : i64
      %nr1 = arith.addi %nr, %c1 : i64
      scf.yield %sp1, %nr1, %np, %ne, %ow, %st : i64, i64, i64, i64, i64, i64
    } else {
      %q:6 = scf.if %isClose -> (i64, i64, i64, i64, i64, i64) {
        %ka = arith.cmpi eq, %topKind, %k1 : i64
        %kb = arith.cmpi eq, %topKind, %k2 : i64
        %kab = arith.ori %ka, %kb : i1
        %fits = arith.andi %open, %kab : i1
        %cl:6 = scf.if %fits -> (i64, i64, i64, i64, i64, i64) {
          // the band closes at off; its statements are the pending ends from its `from`, drained into ends
          %row = func.call @lb_ld(%stack, %top3) : (memref<?xi64>, i64) -> i64
          %top32 = arith.addi %top3, %c2 : i64
          %from = func.call @lb_ld(%stack, %top32) : (memref<?xi64>, i64) -> i64
          %cnt = arith.subi %np, %from : i64
          %r5 = arith.muli %row, %c5 : i64
          %r51 = arith.addi %r5, %c1 : i64
          func.call @lb_st(%rows, %r51, %off) : (memref<?xi64>, i64, i64) -> ()
          %r53 = arith.addi %r5, %c3 : i64
          %first = arith.addi %ebase, %ne : i64
          func.call @lb_st(%rows, %r53, %first) : (memref<?xi64>, i64, i64) -> ()
          %r54 = arith.addi %r5, %c4 : i64
          func.call @lb_st(%rows, %r54, %cnt) : (memref<?xi64>, i64, i64) -> ()
          %fromi = arith.index_cast %from : i64 to index
          %cnti = arith.index_cast %cnt : i64 to index
          %nei = arith.index_cast %ne : i64 to index
          %mine = trikeshed.slice %pendS[%fromi, %cnti] : !s64 -> !s64
          %into = memref.subview %ends[%nei] [%cnti] [1] : memref<?xi64> to !m64
          %end = trikeshed.drain %mine, %into : !s64, !m64 -> index
          %ne1 = arith.addi %ne, %cnt : i64
          scf.yield %spm1, %nr, %from, %ne1, %ow, %st : i64, i64, i64, i64, i64, i64
        } else {
          scf.yield %sp, %nr, %np, %ne, %ow, %c0 : i64, i64, i64, i64, i64, i64
        }
        scf.yield %cl#0, %cl#1, %cl#2, %cl#3, %cl#4, %cl#5 : i64, i64, i64, i64, i64, i64
      } else {
        // the semicolons owed: the innermost band's, or the root's
        %top31 = arith.addi %top3, %c1 : i64
        %owed = scf.if %open -> (i64) {
          %v = func.call @lb_ld(%stack, %top31) : (memref<?xi64>, i64) -> i64
          scf.yield %v : i64
        } else {
          scf.yield %ow : i64
        }
        %owing = arith.cmpi ugt, %owed, %c0 : i64
        %payOwed = arith.andi %isSemi, %owing : i1
        %owed1 = arith.addi %owed, %c1 : i64
        %owedm = arith.subi %owed, %c1 : i64
        %owedA = arith.select %isOwe, %owed1, %owed : i64
        %owedB = arith.select %payOwed, %owedm, %owedA : i64
        // the owed count goes back where it came from
        scf.if %open {
          func.call @lb_st(%stack, %top31, %owedB) : (memref<?xi64>, i64, i64) -> ()
        }
        %ow1 = arith.select %open, %ow, %owedB : i64
        // an end of the innermost band: a comma, or a semicolon not owed
        %semiEnd0 = arith.xori %payOwed, %isSemi : i1
        %endish = arith.ori %semiEnd0, %isComma : i1
        %pushes = arith.andi %endish, %open : i1
        %np1 = scf.if %pushes -> (i64) {
          func.call @lb_st(%pend, %np, %off) : (memref<?xi64>, i64, i64) -> ()
          %v = arith.addi %np, %c1 : i64
          scf.yield %v : i64
        } else {
          scf.yield %np : i64
        }
        %bal = arith.extui %open : i1 to i64
        %balanced = arith.xori %bal, %c1 : i64
        %st1 = arith.select %isEof, %balanced, %st : i64
        scf.yield %sp, %nr, %np1, %ne, %ow1, %st1 : i64, i64, i64, i64, i64, i64
      }
      scf.yield %q#0, %q#1, %q#2, %q#3, %q#4, %q#5 : i64, i64, i64, i64, i64, i64
    }
    scf.yield %i1, %r#0, %r#1, %r#2, %r#3, %r#4, %r#5 : i64, i64, i64, i64, i64, i64, i64
  }
  %cnd = func.call @lb_desc(%countsp, %c2) : (!llvm.ptr, i64) -> !d
  %counts = builtin.unrealized_conversion_cast %cnd : !d to memref<?xi64>
  func.call @lb_st(%counts, %c0, %fin#2) : (memref<?xi64>, i64, i64) -> ()
  func.call @lb_st(%counts, %c1, %fin#4) : (memref<?xi64>, i64, i64) -> ()
  // ran out of tokens with no end of input: a lexer error stopped it
  %ranOut = arith.cmpi eq, %fin#6, %cm1 : i64
  %res = arith.select %ranOut, %c0, %fin#6 : i64
  return %res : i64
}
