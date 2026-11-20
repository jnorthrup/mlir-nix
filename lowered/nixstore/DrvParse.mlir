// The derivation ATerm reader (nixstore::parseDerivation's ATermParser, lib/Store/StorePaths.cpp) hollowed into the
// TrikeShed dialect.  This module walks the fixed Derive(...) structure over the text as a series<i8>:
//   Derive([(id,path,algo,hash),...],[(path,[outs]),...],[srcs],platform,builder,[args],[(key,val),...])
// with the old parser's exact leniencies (the comma after a list element is optional, text after the final "])" is not
// read).  Each string's escapes are decoded into the caller's room (the runs between escapes are slices of the text
// drained there, an escape is one stored byte: \n \r \t, anything else stands for itself), and each decoded string is
// appended to `wins` as a {ptr, len} record, in text order.  `counts` gets [outputs, inputs, srcs, args, env, then
// each input's output count]; the outputs count only says outputs whose ")" was read, so on a failure the bridge can
// first classify the outputs the old parser had already classified (its hash-algorithm errors come first).  The entry
// returns -1, or the offset the old parser's fail() reported ("ATerm parse error at offset N").
//
// Every step takes the position p and returns the next one; a failure is the negative -(offset)-1 and every later
// step passes it through, so the walk is straight-line code with three while loops and no unwinding.  The room holds
// n bytes (a decoded string is never longer than its text), wins n/2 + 2 records (every string takes two quotes),
// counts 5 + n/2 + 2 cells.  The bridge (StorePaths.cpp) builds the Derivation: outputs' kinds, the "r:"/"text:"
// methods, parseHashAlgo/parseHash and their errors, __json, the sorted maps and sets.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// every literal the walk expects, overlapped: Derive([ 0/8, ( 6/1, [ 7/1, ],[ 8/3, ], 8/2, ,[ 9/2, , 9/1, ]) 11/2,
// ] 11/1, ) 12/1, " 13/1
memref.global "private" constant @dp_lits : memref<14xi8> = dense<"0x446572697665285b5d2c5b5d2922">

// the descriptor of n cells at p (a struct, never a memref: nothing is cloned across the return)
func.func private @dp_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the byte at q, or -1 when q is outside [0, n)
func.func private @dp_byte(%src: !llvm.ptr, %n: i64, %q: i64) -> i32 {
  %in = arith.cmpi ult, %q, %n : i64
  %r = scf.if %in -> i32 {
    %d = func.call @dp_desc(%src, %n) : (!llvm.ptr, i64) -> !d
    %m = builtin.unrealized_conversion_cast %d : !d to !m
    %ss = builtin.unrealized_conversion_cast %m : !m to !s
    %qi = arith.index_cast %q : i64 to index
    %b = trikeshed.at %ss[%qi] : !s, index -> i8
    %bu = arith.extui %b : i8 to i32
    scf.yield %bu : i32
  } else {
    %none = arith.constant -1 : i32
    scf.yield %none : i32
  }
  return %r : i32
}

// ATermParser::peek: p is a position (not a failure) and the byte there is c
func.func private @dp_peek(%src: !llvm.ptr, %n: i64, %p: i64, %c: i32) -> i1 {
  %b = func.call @dp_byte(%src, %n, %p) : (!llvm.ptr, i64, i64) -> i32
  %r = arith.cmpi eq, %b, %c : i32
  return %r : i1
}

// `if (peek(c)) p++`
func.func private @dp_skip(%src: !llvm.ptr, %n: i64, %p: i64, %c: i32) -> i64 {
  %hit = func.call @dp_peek(%src, %n, %p, %c) : (!llvm.ptr, i64, i64, i32) -> i1
  %one = arith.constant 1 : i64
  %p1 = arith.addi %p, %one : i64
  %r = arith.select %hit, %p1, %p : i64
  return %r : i64
}

// ATermParser::expect: the len bytes at p are the literal at off in @dp_lits (trikeshed.compare of the two slices),
// then p + len; else the failure at p.  A failure passes through.
func.func private @dp_lit(%src: !llvm.ptr, %n: i64, %p: i64, %off: index, %len: index) -> i64 {
  %c0 = arith.constant 0 : i64
  %m1 = arith.constant -1 : i64
  %bad = arith.cmpi slt, %p, %c0 : i64
  %r = scf.if %bad -> i64 {
    scf.yield %p : i64
  } else {
    %fail = arith.subi %m1, %p : i64
    %pi = arith.index_cast %p : i64 to index
    %ni = arith.index_cast %n : i64 to index
    %rest = arith.subi %ni, %pi : index
    %short = arith.cmpi ult, %rest, %len : index
    %r2 = scf.if %short -> i64 {
      scf.yield %fail : i64
    } else {
      %d = func.call @dp_desc(%src, %n) : (!llvm.ptr, i64) -> !d
      %m = builtin.unrealized_conversion_cast %d : !d to !m
      %ss = builtin.unrealized_conversion_cast %m : !m to !s
      %w = trikeshed.slice %ss[%pi, %len] : !s -> !s
      %g = memref.get_global @dp_lits : memref<14xi8>
      %lits = trikeshed.text %g : memref<14xi8> -> !s
      %l = trikeshed.slice %lits[%off, %len] : !s -> !s
      %cmp = trikeshed.compare %w, %l unsigned : !s, !s
      %z = arith.constant 0 : i32
      %eq = arith.cmpi eq, %cmp, %z : i32
      %lenI = arith.index_cast %len : index to i64
      %next = arith.addi %p, %lenI : i64
      %r3 = arith.select %eq, %next, %fail : i64
      scf.yield %r3 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

// ATermParser::str: '"', then runs of plain bytes (each a slice of the text drained into the room) and escapes (one
// decoded byte stored), then '"'.  The decoded string is appended to wins as {ptr, len}.  ctx is
// [room ptr, room used, wins ptr, wins used, room size].
func.func private @dp_str(%src: !llvm.ptr, %n: i64, %p: i64, %ctx: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %m1 = arith.constant -1 : i64
  %q13 = arith.constant 13 : index
  %one = arith.constant 1 : index
  %quote = arith.constant 34 : i32
  %bslash = arith.constant 92 : i32
  %true = arith.constant true
  %false = arith.constant false
  %p1 = func.call @dp_lit(%src, %n, %p, %q13, %one) : (!llvm.ptr, i64, i64, index, index) -> i64
  %bad = arith.cmpi slt, %p1, %c0 : i64
  %r = scf.if %bad -> i64 {
    scf.yield %p1 : i64
  } else {
    %a0 = llvm.getelementptr %ctx[0] : (!llvm.ptr) -> !llvm.ptr, i64
    %room = llvm.load %a0 : !llvm.ptr -> !llvm.ptr
    %a1 = llvm.getelementptr %ctx[1] : (!llvm.ptr) -> !llvm.ptr, i64
    %w0 = llvm.load %a1 : !llvm.ptr -> i64
    %a4 = llvm.getelementptr %ctx[4] : (!llvm.ptr) -> !llvm.ptr, i64
    %rn = llvm.load %a4 : !llvm.ptr -> i64
    %sd = func.call @dp_desc(%src, %n) : (!llvm.ptr, i64) -> !d
    %sm = builtin.unrealized_conversion_cast %sd : !d to !m
    %ss = builtin.unrealized_conversion_cast %sm : !m to !s
    %rd = func.call @dp_desc(%room, %rn) : (!llvm.ptr, i64) -> !d
    %rm = builtin.unrealized_conversion_cast %rd : !d to !m
    %qf, %wf, %gof = scf.while (%q = %p1, %w = %w0, %go = %true) : (i64, i64, i1) -> (i64, i64, i1) {
      scf.condition(%go) %q, %w, %go : i64, i64, i1
    } do {
    ^bb0(%qa: i64, %wa: i64, %goa: i1):
      // the run of plain bytes from qa
      %re = scf.while (%t = %qa) : (i64) -> i64 {
        %bt = func.call @dp_byte(%src, %n, %t) : (!llvm.ptr, i64, i64) -> i32
        %nn = arith.constant 0 : i32
        %isb = arith.cmpi sge, %bt, %nn : i32
        %nq = arith.cmpi ne, %bt, %quote : i32
        %nb = arith.cmpi ne, %bt, %bslash : i32
        %k1 = arith.andi %isb, %nq : i1
        %k2 = arith.andi %k1, %nb : i1
        scf.condition(%k2) %t : i64
      } do {
      ^bb0(%ta: i64):
        %t1 = arith.addi %ta, %c1 : i64
        scf.yield %t1 : i64
      }
      %len = arith.subi %re, %qa : i64
      %qai = arith.index_cast %qa : i64 to index
      %leni = arith.index_cast %len : i64 to index
      %run = trikeshed.slice %ss[%qai, %leni] : !s -> !s
      %at = llvm.getelementptr %room[%wa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %od = func.call @dp_desc(%at, %len) : (!llvm.ptr, i64) -> !d
      %om = builtin.unrealized_conversion_cast %od : !d to !m
      %dr = trikeshed.drain %run, %om : !s, !m -> index
      %wl = arith.addi %wa, %len : i64
      %be = func.call @dp_byte(%src, %n, %re) : (!llvm.ptr, i64, i64) -> i32
      %isEsc = arith.cmpi eq, %be, %bslash : i32
      %nx:3 = scf.if %isEsc -> (i64, i64, i1) {
        %r1 = arith.addi %re, %c1 : i64
        %ce = func.call @dp_byte(%src, %n, %r1) : (!llvm.ptr, i64, i64) -> i32
        %z32 = arith.constant 0 : i32
        %eof = arith.cmpi slt, %ce, %z32 : i32
        %e3:3 = scf.if %eof -> (i64, i64, i1) {
          %fe = arith.subi %m1, %r1 : i64
          scf.yield %fe, %wl, %false : i64, i64, i1
        } else {
          %cn = arith.constant 110 : i32
          %cr = arith.constant 114 : i32
          %ct = arith.constant 116 : i32
          %v10 = arith.constant 10 : i32
          %v13 = arith.constant 13 : i32
          %v9 = arith.constant 9 : i32
          %isn = arith.cmpi eq, %ce, %cn : i32
          %isr = arith.cmpi eq, %ce, %cr : i32
          %ist = arith.cmpi eq, %ce, %ct : i32
          %s1 = arith.select %ist, %v9, %ce : i32
          %s2 = arith.select %isr, %v13, %s1 : i32
          %s3 = arith.select %isn, %v10, %s2 : i32
          %b8 = arith.trunci %s3 : i32 to i8
          %wli = arith.index_cast %wl : i64 to index
          memref.store %b8, %rm[%wli] : !m
          %r2 = arith.addi %re, %c2 : i64
          %wl1 = arith.addi %wl, %c1 : i64
          scf.yield %r2, %wl1, %true : i64, i64, i1
        }
        scf.yield %e3#0, %e3#1, %e3#2 : i64, i64, i1
      } else {
        scf.yield %re, %wl, %false : i64, i64, i1
      }
      scf.yield %nx#0, %nx#1, %nx#2 : i64, i64, i1
    }
    %p2 = func.call @dp_lit(%src, %n, %qf, %q13, %one) : (!llvm.ptr, i64, i64, index, index) -> i64
    %ok = arith.cmpi sge, %p2, %c0 : i64
    scf.if %ok {
      %a2 = llvm.getelementptr %ctx[2] : (!llvm.ptr) -> !llvm.ptr, i64
      %wins = llvm.load %a2 : !llvm.ptr -> !llvm.ptr
      %a3 = llvm.getelementptr %ctx[3] : (!llvm.ptr) -> !llvm.ptr, i64
      %k = llvm.load %a3 : !llvm.ptr -> i64
      %start = llvm.getelementptr %room[%w0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %sp = llvm.ptrtoint %start : !llvm.ptr to i64
      %slen = arith.subi %wf, %w0 : i64
      %cap2 = arith.muli %k, %c2 : i64
      %cap3 = arith.addi %cap2, %c2 : i64
      %wd = func.call @dp_desc(%wins, %cap3) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %i0 = arith.index_cast %cap2 : i64 to index
      %i1 = arith.addi %i0, %one : index
      memref.store %sp, %wm[%i0] : !m64
      memref.store %slen, %wm[%i1] : !m64
      %k1 = arith.addi %k, %c1 : i64
      llvm.store %k1, %a3 : i64, !llvm.ptr
      llvm.store %wf, %a1 : i64, !llvm.ptr
    }
    scf.yield %p2 : i64
  }
  return %r : i64
}

// ATermParser::strs: '[', strings each optionally followed by ',', ']'.  Returns the position and the count.
func.func private @dp_strs(%src: !llvm.ptr, %n: i64, %p: i64, %ctx: !llvm.ptr) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %o7 = arith.constant 7 : index
  %o11 = arith.constant 11 : index
  %one = arith.constant 1 : index
  %close = arith.constant 93 : i32
  %comma = arith.constant 44 : i32
  %true = arith.constant true
  %p1 = func.call @dp_lit(%src, %n, %p, %o7, %one) : (!llvm.ptr, i64, i64, index, index) -> i64
  %qe, %ke = scf.while (%q = %p1, %k = %c0) : (i64, i64) -> (i64, i64) {
    %live = arith.cmpi sge, %q, %c0 : i64
    %end = func.call @dp_peek(%src, %n, %q, %close) : (!llvm.ptr, i64, i64, i32) -> i1
    %more = arith.xori %end, %true : i1
    %go = arith.andi %live, %more : i1
    scf.condition(%go) %q, %k : i64, i64
  } do {
  ^bb0(%qa: i64, %ka: i64):
    %q2 = func.call @dp_str(%src, %n, %qa, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %q3 = func.call @dp_skip(%src, %n, %q2, %comma) : (!llvm.ptr, i64, i64, i32) -> i64
    %k1 = arith.addi %ka, %c1 : i64
    scf.yield %q3, %k1 : i64, i64
  }
  %p2 = func.call @dp_lit(%src, %n, %qe, %o11, %one) : (!llvm.ptr, i64, i64, index, index) -> i64
  return %p2, %ke : i64, i64
}

// parseDerivation's walk.  src/n the text; room n bytes; wins n/2 + 2 {ptr, len} records; counts 5 + n/2 + 2 cells
// (the first five zeroed by the caller).  Returns -1, or the failure offset.
func.func @nixstore_ts_drvparse(%src: !llvm.ptr, %n: i64, %room: !llvm.ptr, %wins: !llvm.ptr, %counts: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i8 = arith.constant 8 : index
  %i9 = arith.constant 9 : index
  %i11 = arith.constant 11 : index
  %i12 = arith.constant 12 : index
  %close = arith.constant 93 : i32
  %comma = arith.constant 44 : i32
  %true = arith.constant true
  %ctx = llvm.alloca %c5 x i64 : (i64) -> !llvm.ptr
  %x0 = llvm.getelementptr %ctx[0] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %room, %x0 : !llvm.ptr, !llvm.ptr
  %x1 = llvm.getelementptr %ctx[1] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %c0, %x1 : i64, !llvm.ptr
  %x2 = llvm.getelementptr %ctx[2] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %wins, %x2 : !llvm.ptr, !llvm.ptr
  %x3 = llvm.getelementptr %ctx[3] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %c0, %x3 : i64, !llvm.ptr
  %x4 = llvm.getelementptr %ctx[4] : (!llvm.ptr) -> !llvm.ptr, i64
  llvm.store %n, %x4 : i64, !llvm.ptr
  %half = arith.divui %n, %c2 : i64
  %ccap0 = arith.addi %half, %c5 : i64
  %ccap = arith.addi %ccap0, %c2 : i64
  %cd = func.call @dp_desc(%counts, %ccap) : (!llvm.ptr, i64) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m64

  %p0 = func.call @dp_lit(%src, %n, %c0, %i0, %i8) : (!llvm.ptr, i64, i64, index, index) -> i64
  // outputs: (id,path,algo,hash)
  %po = scf.while (%q = %p0) : (i64) -> i64 {
    %live = arith.cmpi sge, %q, %c0 : i64
    %end = func.call @dp_peek(%src, %n, %q, %close) : (!llvm.ptr, i64, i64, i32) -> i1
    %more = arith.xori %end, %true : i1
    %go = arith.andi %live, %more : i1
    scf.condition(%go) %q : i64
  } do {
  ^bb0(%qa: i64):
    %o1 = func.call @dp_lit(%src, %n, %qa, %i6, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %o2 = func.call @dp_str(%src, %n, %o1, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %o3 = func.call @dp_lit(%src, %n, %o2, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %o4 = func.call @dp_str(%src, %n, %o3, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %o5 = func.call @dp_lit(%src, %n, %o4, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %o6 = func.call @dp_str(%src, %n, %o5, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %o7 = func.call @dp_lit(%src, %n, %o6, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %o8 = func.call @dp_str(%src, %n, %o7, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %o9 = func.call @dp_lit(%src, %n, %o8, %i12, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %ok = arith.cmpi sge, %o9, %c0 : i64
    scf.if %ok {
      %no = memref.load %cm[%i0] : !m64
      %no1 = arith.addi %no, %c1 : i64
      memref.store %no1, %cm[%i0] : !m64
    }
    %o10 = func.call @dp_skip(%src, %n, %o9, %comma) : (!llvm.ptr, i64, i64, i32) -> i64
    scf.yield %o10 : i64
  }
  %pi0 = func.call @dp_lit(%src, %n, %po, %i8, %i3) : (!llvm.ptr, i64, i64, index, index) -> i64
  // inputDrvs: (path,[outs])
  %pi = scf.while (%q = %pi0) : (i64) -> i64 {
    %live = arith.cmpi sge, %q, %c0 : i64
    %end = func.call @dp_peek(%src, %n, %q, %close) : (!llvm.ptr, i64, i64, i32) -> i1
    %more = arith.xori %end, %true : i1
    %go = arith.andi %live, %more : i1
    scf.condition(%go) %q : i64
  } do {
  ^bb0(%qb: i64):
    %u1 = func.call @dp_lit(%src, %n, %qb, %i6, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %u2 = func.call @dp_str(%src, %n, %u1, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %u3 = func.call @dp_lit(%src, %n, %u2, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %u4, %uk = func.call @dp_strs(%src, %n, %u3, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> (i64, i64)
    %u5 = func.call @dp_lit(%src, %n, %u4, %i12, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %ok = arith.cmpi sge, %u5, %c0 : i64
    scf.if %ok {
      %ni = memref.load %cm[%i1] : !m64
      %nii = arith.index_cast %ni : i64 to index
      %slot = arith.addi %nii, %i5 : index
      memref.store %uk, %cm[%slot] : !m64
      %ni1 = arith.addi %ni, %c1 : i64
      memref.store %ni1, %cm[%i1] : !m64
    }
    %u6 = func.call @dp_skip(%src, %n, %u5, %comma) : (!llvm.ptr, i64, i64, i32) -> i64
    scf.yield %u6 : i64
  }
  %ps0 = func.call @dp_lit(%src, %n, %pi, %i8, %i2) : (!llvm.ptr, i64, i64, index, index) -> i64
  %ps, %ns = func.call @dp_strs(%src, %n, %ps0, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> (i64, i64)
  memref.store %ns, %cm[%i2] : !m64
  %pp0 = func.call @dp_lit(%src, %n, %ps, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
  %pp = func.call @dp_str(%src, %n, %pp0, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %pb0 = func.call @dp_lit(%src, %n, %pp, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
  %pb = func.call @dp_str(%src, %n, %pb0, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
  %pa0 = func.call @dp_lit(%src, %n, %pb, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
  %pa, %na = func.call @dp_strs(%src, %n, %pa0, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> (i64, i64)
  memref.store %na, %cm[%i3] : !m64
  %pe0 = func.call @dp_lit(%src, %n, %pa, %i9, %i2) : (!llvm.ptr, i64, i64, index, index) -> i64
  // env: (key,val)
  %pe = scf.while (%q = %pe0) : (i64) -> i64 {
    %live = arith.cmpi sge, %q, %c0 : i64
    %end = func.call @dp_peek(%src, %n, %q, %close) : (!llvm.ptr, i64, i64, i32) -> i1
    %more = arith.xori %end, %true : i1
    %go = arith.andi %live, %more : i1
    scf.condition(%go) %q : i64
  } do {
  ^bb0(%qc: i64):
    %v1 = func.call @dp_lit(%src, %n, %qc, %i6, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %v2 = func.call @dp_str(%src, %n, %v1, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %v3 = func.call @dp_lit(%src, %n, %v2, %i9, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %v4 = func.call @dp_str(%src, %n, %v3, %ctx) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
    %v5 = func.call @dp_lit(%src, %n, %v4, %i12, %i1) : (!llvm.ptr, i64, i64, index, index) -> i64
    %ok = arith.cmpi sge, %v5, %c0 : i64
    scf.if %ok {
      %nv = memref.load %cm[%i4] : !m64
      %nv1 = arith.addi %nv, %c1 : i64
      memref.store %nv1, %cm[%i4] : !m64
    }
    %v6 = func.call @dp_skip(%src, %n, %v5, %comma) : (!llvm.ptr, i64, i64, i32) -> i64
    scf.yield %v6 : i64
  }
  %pz = func.call @dp_lit(%src, %n, %pe, %i11, %i2) : (!llvm.ptr, i64, i64, index, index) -> i64
  %failed = arith.cmpi slt, %pz, %c0 : i64
  %off = arith.subi %m1, %pz : i64
  %r = arith.select %failed, %off, %m1 : i64
  return %r : i64
}
