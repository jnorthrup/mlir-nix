// The C++ string primops (__stringLength, __substring, __concatStringsSep, __replaceStrings) and mkStringOf hollowed
// into the TrikeShed dialect.  lib/Eval/Builtins.cpp keeps only the forcing/coercion of operands (Nix's error order and
// wording, the string contexts) and calls these entries; the text algebra is here, in trikeshed.size / slice / compare /
// combineAll / drain, lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt
// mlnix_lower_trikeshed).  Bytes are seen as a series<i8>: the descriptor of n bytes at p is built inline (a struct, not
// a memref: returning it allocates nothing and clones nothing) and cast to the series' strided memref at the use site.
// A composite::Chars piece is 16 bytes: u32 count @0, const char *data @8 (Series.h's Join<uint32_t, Ptr<const char>>).
// Value: VType u8@0 (Int 5, String 9), aux u32@4 (a string's byte count), str.s ptr@8, str.ctx ptr@16.
//
// The callbacks into the evaluator (only it can allocate arena room, throw a Nix error, or force a replacement string
// with its context): nixev_str_room, nixev_str_toobig, nixev_replace_to.  A C++ exception thrown in a callback unwinds
// through the compiled frame (as fold's callFunction does in ListOps.mlir).
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!bnds = !llvm.struct<(i64, i64)>
!chars = !llvm.struct<(i32, ptr)>

func.func private @nixev_str_room(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_str_toobig()
func.func private @nixev_replace_to(!llvm.ptr, i64, !llvm.ptr)

// the one empty string literal mkStringOf shares when no piece has a byte (its NUL is the string's)
llvm.mlir.global private constant @ts_empty(dense<0> : tensor<1xi8>) : !llvm.array<1 x i8>

// the descriptor of n i8 cells at p
func.func private @ts_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// __stringLength: the size of the string's byte series, an Int.  The bridge has coerced the argument to a window.
func.func @nixev_ts_stringLength(%p: !llvm.ptr, %n: i64, %v: !llvm.ptr) {
  %d = func.call @ts_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %k = trikeshed.size %ss : !s
  %r = arith.index_cast %k : index to i64
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %five = arith.constant 5 : i8
  llvm.store %five, %tp : i8, !llvm.ptr
  %ip = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %r, %ip : i64, !llvm.ptr
  return
}

// __substring: the clamped [from, to) of the byte series.  start >= 0 (the bridge refused a negative one); a negative
// len takes the rest.  The bridge shares the string's own bytes at from (nothing copied) or copies the coerced window.
func.func @nixev_ts_substring(%p: !llvm.ptr, %n: i64, %start: i64, %len: i64) -> !bnds {
  %d = func.call @ts_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %k = trikeshed.size %ss : !s
  %sz = arith.index_cast %k : index to i64
  %from = arith.minsi %start, %sz : i64
  %rest = arith.subi %sz, %from : i64
  %c0 = arith.constant 0 : i64
  %neg = arith.cmpi slt, %len, %c0 : i64
  %big = arith.cmpi uge, %len, %rest : i64
  %whole = arith.ori %neg, %big : i1
  %cnt = arith.select %whole, %rest, %len : i64
  %to = arith.addi %from, %cnt : i64
  %u = llvm.mlir.undef : !bnds
  %a = llvm.insertvalue %from, %u[0] : !bnds
  %b = llvm.insertvalue %to, %a[1] : !bnds
  return %b : !bnds
}

// mkStringOf / __concatStringsSep: the pieces one after another.  At most one non-empty piece is the string itself (its
// bytes shared, as a string is never written); else one arena buffer of the total, the combineAll of the pieces drained
// into it once, a NUL after the last.  The bridge has forced every piece and settled the contexts.
func.func @nixev_ts_concat(%st: !llvm.ptr, %pieces: !llvm.ptr, %np: i64, %v: !llvm.ptr, %ctx: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %onep = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
  %onel = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %ep = llvm.mlir.addressof @ts_empty : !llvm.ptr
  llvm.store %ep, %onep : !llvm.ptr, !llvm.ptr
  llvm.store %c0, %onel : i64, !llvm.ptr
  %npi = arith.index_cast %np : i64 to index
  %sum:2 = scf.for %i = %zi to %npi step %oi iter_args(%total = %c0, %full = %c0) -> (i64, i64) {
    %i64 = arith.index_cast %i : index to i64
    %off = arith.muli %i64, %c16 : i64
    %ap = llvm.getelementptr %pieces[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %l32 = llvm.load %ap : !llvm.ptr -> i32
    %l = llvm.zext %l32 : i32 to i64
    %dp = llvm.getelementptr %ap[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p = llvm.load %dp : !llvm.ptr -> !llvm.ptr
    %total2 = arith.addi %total, %l : i64
    %nz = arith.cmpi ne, %l, %c0 : i64
    %full1 = arith.addi %full, %c1 : i64
    %full2 = arith.select %nz, %full1, %full : i64
    scf.if %nz {
      llvm.store %p, %onep : !llvm.ptr, !llvm.ptr
      llvm.store %l, %onel : i64, !llvm.ptr
    }
    scf.yield %total2, %full2 : i64, i64
  }
  %max = arith.constant 4294967295 : i64
  %big = arith.cmpi ugt, %sum#0, %max : i64
  scf.if %big {
    func.call @nixev_str_toobig() : () -> ()
  }
  %le1 = arith.cmpi ule, %sum#1, %c1 : i64
  scf.if %le1 {
    %p = llvm.load %onep : !llvm.ptr -> !llvm.ptr
    %l = llvm.load %onel : !llvm.ptr -> i64
    %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
    %nine = arith.constant 9 : i8
    llvm.store %nine, %tp : i8, !llvm.ptr
    %l32 = arith.trunci %l : i64 to i32
    %ap = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %l32, %ap : i32, !llvm.ptr
    %sp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %p, %sp : !llvm.ptr, !llvm.ptr
    %cp = llvm.getelementptr %v[16] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %ctx, %cp : !llvm.ptr, !llvm.ptr
  } else {
    %buf = func.call @nixev_str_room(%st, %sum#0) : (!llvm.ptr, i64) -> !llvm.ptr
    %d = func.call @ts_desc8(%buf, %sum#0) : (!llvm.ptr, i64) -> !d
    %into = builtin.unrealized_conversion_cast %d : !d to !m
    %all, %coords = trikeshed.combineAll %npi : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
    ^bb0(%k: index):
      %k64 = arith.index_cast %k : index to i64
      %off = arith.muli %k64, %c16 : i64
      %ap = llvm.getelementptr %pieces[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %l32 = llvm.load %ap : !llvm.ptr -> i32
      %l = llvm.zext %l32 : i32 to i64
      %dp = llvm.getelementptr %ap[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %p = llvm.load %dp : !llvm.ptr -> !llvm.ptr
      %pd = func.call @ts_desc8(%p, %l) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m
  %part = builtin.unrealized_conversion_cast %pm : !m to !s
      trikeshed.yield %part : !s
    }
    %end = trikeshed.drain %all, %into : !s, !m -> index
    %nul = llvm.getelementptr %buf[%sum#0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %zero = arith.constant 0 : i8
    llvm.store %zero, %nul : i8, !llvm.ptr
    %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
    %nine = arith.constant 9 : i8
    llvm.store %nine, %tp : i8, !llvm.ptr
    %l32 = arith.trunci %sum#0 : i64 to i32
    %ap = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %l32, %ap : i32, !llvm.ptr
    %sp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %buf, %sp : !llvm.ptr, !llvm.ptr
    %cp = llvm.getelementptr %v[16] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %ctx, %cp : !llvm.ptr, !llvm.ptr
  }
  return
}

// the first j whose from[j] (a Chars at from + 16*j) equals the bytes at p, else -1: a slice of the string compared
// unsigned (Kotlin's Char order) with the piece.  A piece longer than what is left cannot match; an empty one matches
// anywhere (p <= size).  The first match wins, as std::string_view::compare's scan does.
func.func private @ts_match_at(%ss: !s, %sz: index, %p: index, %from: !llvm.ptr, %m: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c032 = arith.constant 0 : i32
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %cm1 = arith.constant -1 : i64
  %rest = arith.subi %sz, %p : index
  %mi = arith.index_cast %m : i64 to index
  %r = scf.for %j = %zi to %mi step %oi iter_args(%found = %cm1) -> i64 {
    %go = arith.cmpi slt, %found, %c0 : i64
    %next = scf.if %go -> i64 {
      %j64 = arith.index_cast %j : index to i64
      %off = arith.muli %j64, %c16 : i64
      %ap = llvm.getelementptr %from[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %l32 = llvm.load %ap : !llvm.ptr -> i32
      %l = llvm.zext %l32 : i32 to i64
      %li = arith.index_cast %l : i64 to index
      %dp = llvm.getelementptr %ap[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %fp = llvm.load %dp : !llvm.ptr -> !llvm.ptr
      %ok = arith.cmpi ule, %li, %rest : index
      %hit = scf.if %ok -> i64 {
        %sl = trikeshed.slice %ss[%p, %li] : !s -> !s
        %fd = func.call @ts_desc8(%fp, %l) : (!llvm.ptr, i64) -> !d
  %fm = builtin.unrealized_conversion_cast %fd : !d to !m
  %fs = builtin.unrealized_conversion_cast %fm : !m to !s
        %c = trikeshed.compare %sl, %fs unsigned : !s, !s
        %eq = arith.cmpi eq, %c, %c032 : i32
        %sel = arith.select %eq, %j64, %cm1 : i64
        scf.yield %sel : i64
      } else {
        scf.yield %cm1 : i64
      }
      scf.yield %hit : i64
    } else {
      scf.yield %found : i64
    }
    scf.yield %next : i64
  }
  return %r : i64
}

// __replaceStrings: scan the string's positions; at each, the first matching from[j] is replaced by to[j] (forced once,
// cached, its context merged -- the callback keeps Nix's order), an empty from inserting to[j] before the byte at p; a
// position with no match keeps its byte.  Pass one counts the result (forcing the replacements in match order), pass two
// drains the pieces into one arena buffer.  The bridge has forced the two lists (checked equal), every from[j], and the
// string, and settles the result's context.
func.func @nixev_ts_replace(%st: !llvm.ptr, %r: !llvm.ptr, %p: !llvm.ptr, %sn: i64, %from: !llvm.ptr, %m: i64, %v: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c1i = arith.constant 1 : index
  %c8i = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %sd = func.call @ts_desc8(%p, %sn) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m
  %ss = builtin.unrealized_conversion_cast %sm : !m to !s
  %k = trikeshed.size %ss : !s
  %sz = arith.index_cast %k : index to i64
  %szi = arith.index_cast %sz : i64 to index
  %zero = arith.constant 0 : index
  // pass one: the total, the replacements forced in match order
  %tot:2 = scf.while (%pos = %zero, %total = %c0) : (index, i64) -> (index, i64) {
    %cond = arith.cmpi ule, %pos, %szi : index
    scf.condition(%cond) %pos, %total : index, i64
  } do {
  ^bb0(%pos: index, %total: i64):
    %j = func.call @ts_match_at(%ss, %szi, %pos, %from, %m) : (!s, index, index, !llvm.ptr, i64) -> i64
    %hit = arith.cmpi sge, %j, %c0 : i64
    %tlfl:2 = scf.if %hit -> (i64, i64) {
      %out = llvm.alloca %c1 x !chars : (i64) -> !llvm.ptr
      func.call @nixev_replace_to(%r, %j, %out) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %tl32 = llvm.load %out : !llvm.ptr -> i32
      %tl = llvm.zext %tl32 : i32 to i64
      %off = arith.muli %j, %c16 : i64
      %ap = llvm.getelementptr %from[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %fl32 = llvm.load %ap : !llvm.ptr -> i32
      %fl = llvm.zext %fl32 : i32 to i64
      scf.yield %tl, %fl : i64, i64
    } else {
      scf.yield %c0, %c0 : i64, i64
    }
    %inside = arith.cmpi ult, %pos, %szi : index
    %empty = arith.cmpi eq, %tlfl#1, %c0 : i64
    %mins = arith.andi %inside, %empty : i1
    %extra = arith.select %hit, %mins, %inside : i1
    %e64 = arith.extui %extra : i1 to i64
    %t1 = arith.addi %total, %tlfl#0 : i64
    %total2 = arith.addi %t1, %e64 : i64
    %adv0 = arith.select %empty, %c1, %tlfl#1 : i64
    %adv = arith.select %hit, %adv0, %c1 : i64
    %advi = arith.index_cast %adv : i64 to index
    %pos2 = arith.addi %pos, %advi : index
    scf.yield %pos2, %total2 : index, i64
  }
  %max = arith.constant 4294967295 : i64
  %big = arith.cmpi ugt, %tot#1, %max : i64
  scf.if %big {
    func.call @nixev_str_toobig() : () -> ()
  }
  %buf = func.call @nixev_str_room(%st, %tot#1) : (!llvm.ptr, i64) -> !llvm.ptr
  %d = func.call @ts_desc8(%buf, %tot#1) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %d : !d to !m
  // pass two: the pieces drained where each lands (the replacements now cached)
  %fill:2 = scf.while (%pos = %zero, %at = %c0) : (index, i64) -> (index, i64) {
    %cond = arith.cmpi ule, %pos, %szi : index
    scf.condition(%cond) %pos, %at : index, i64
  } do {
  ^bb0(%pos: index, %at: i64):
    %j = func.call @ts_match_at(%ss, %szi, %pos, %from, %m) : (!s, index, index, !llvm.ptr, i64) -> i64
    %hit = arith.cmpi sge, %j, %c0 : i64
    %step:2 = scf.if %hit -> (index, i64) {
      %out = llvm.alloca %c1 x !chars : (i64) -> !llvm.ptr
      func.call @nixev_replace_to(%r, %j, %out) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %tl32 = llvm.load %out : !llvm.ptr -> i32
      %tl = llvm.zext %tl32 : i32 to i64
      %dp = llvm.getelementptr %out[%c8i] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %tp = llvm.load %dp : !llvm.ptr -> !llvm.ptr
      %td = func.call @ts_desc8(%tp, %tl) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m
  %ts = builtin.unrealized_conversion_cast %tm : !m to !s
      %ati = arith.index_cast %at : i64 to index
      %tli = arith.index_cast %tl : i64 to index
      %cells = memref.subview %into[%ati] [%tli] [1] : !m to !m
      %e1 = trikeshed.drain %ts, %cells : !s, !m -> index
      %at1 = arith.addi %at, %tl : i64
      %off = arith.muli %j, %c16 : i64
      %ap = llvm.getelementptr %from[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %fl32 = llvm.load %ap : !llvm.ptr -> i32
      %fl = llvm.zext %fl32 : i32 to i64
      %empty = arith.cmpi eq, %fl, %c0 : i64
      %inside = arith.cmpi ult, %pos, %szi : index
      %need = arith.andi %empty, %inside : i1
      %at2 = scf.if %need -> i64 {
        %one = trikeshed.slice %ss[%pos, %c1i] : !s -> !s
        %at1i = arith.index_cast %at1 : i64 to index
        %cell1 = memref.subview %into[%at1i] [%c1i] [1] : !m to !m
        %e2 = trikeshed.drain %one, %cell1 : !s, !m -> index
        %next = arith.addi %at1, %c1 : i64
        scf.yield %next : i64
      } else {
        scf.yield %at1 : i64
      }
      %adv0 = arith.select %empty, %c1, %fl : i64
      %advi = arith.index_cast %adv0 : i64 to index
      %pos2 = arith.addi %pos, %advi : index
      scf.yield %pos2, %at2 : index, i64
    } else {
      %inside = arith.cmpi ult, %pos, %szi : index
      %atn = scf.if %inside -> i64 {
        %one = trikeshed.slice %ss[%pos, %c1i] : !s -> !s
        %ati = arith.index_cast %at : i64 to index
        %cell1 = memref.subview %into[%ati] [%c1i] [1] : !m to !m
        %e2 = trikeshed.drain %one, %cell1 : !s, !m -> index
        %next = arith.addi %at, %c1 : i64
        scf.yield %next : i64
      } else {
        scf.yield %at : i64
      }
      %pos2 = arith.addi %pos, %c1i : index
      scf.yield %pos2, %atn : index, i64
    }
    scf.yield %step#0, %step#1 : index, i64
  }
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %nine = arith.constant 9 : i8
  llvm.store %nine, %tp : i8, !llvm.ptr
  %l32 = arith.trunci %tot#1 : i64 to i32
  %ap = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %l32, %ap : i32, !llvm.ptr
  %sp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %buf, %sp : !llvm.ptr, !llvm.ptr
  return
}
