// __getContext's context algebra hollowed into the TrikeShed dialect.  lib/Eval/Builtins.cpp forces the string with its
// context (Nix's error wording) and builds the sets; the algebra is here: each context element read as what it is
// ("=PATH" all outputs, "!OUT!PATH" one output, else a plain path: the windows on its bytes, the second '!' found by
// trikeshed.parts), the elements' rows sorted by their path's bytes (trikeshed.sorted, compare unsigned: SortedMap's
// byte order; stable, so a path's outputs keep the context's order), the runs of one path (a where), and per path its
// flags (a fold) and its outputs (a where, their windows drained into the bridge's scratch).  nixev_cx_group makes the
// path's set and its row, in the order the C++ made them, so the symbols are created in the same order.
//
// The context's elements are C strings (NixStringContext: sorted by bytes, each once), handed in as their pointers;
// their lengths are strlen's.  A window handed back is a composite::Chars: u32 count@0 (the word's low half; the high
// half is padding), const char *data@8.
!s = !trikeshed.series<i64>
!t = !trikeshed.series<i8>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi64, strided<[1], offset: ?>>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @strlen(!llvm.ptr) -> i64
func.func private @nixev_cx_group(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64)

// the descriptor of n cells at p (module-unique)
func.func private @cx_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// an element's reading: (kind 0 path / 1 all outputs / 2 an output, the path's start, its length, the output's length;
// the output starts at 1).  For "!OUT!PATH" the output is the first part of the bytes after the leading '!' split at '!'.
func.func private @cx_info(%p: !llvm.ptr, %n: i64) -> (i64, i64, i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %z = arith.constant 0 : index
  %bang = arith.constant 33 : i8
  %eq = arith.constant 61 : i8
  %nul = arith.constant 0 : i8
  %d = func.call @cx_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %d : !d to !m8
  %bytes = builtin.unrealized_conversion_cast %dm : !m8 to !t
  %some = arith.cmpi ugt, %n, %c0 : i64
  %b0 = scf.if %some -> (i8) {
    %b = trikeshed.at %bytes[%z] : !t, index -> i8
    scf.yield %b : i8
  } else {
    scf.yield %nul : i8
  }
  %isall = arith.cmpi eq, %b0, %eq : i8
  %isout = arith.cmpi eq, %b0, %bang : i8
  %r:4 = scf.if %isout -> (i64, i64, i64, i64) {
    %one = arith.constant 1 : index
    %ni = arith.index_cast %n : i64 to index
    %rest = arith.subi %ni, %one : index
    %tail = trikeshed.slice %bytes[%one, %rest] : !t -> !t
    %ps = trikeshed.parts %tail, %bang : !t, i8 -> !sp
    %p0 = trikeshed.at %ps[%z] : !sp, index -> !tp
    %q32 = trikeshed.second %p0 : !tp -> i32
    %q = arith.extui %q32 : i32 to i64
    %start = arith.addi %q, %c2 : i64
    %over = arith.cmpi ugt, %start, %n : i64
    %start2 = arith.select %over, %n, %start : i64
    %plen = arith.subi %n, %start2 : i64
    scf.yield %c2, %start2, %plen, %q : i64, i64, i64, i64
  } else {
    %start = arith.select %isall, %c1, %c0 : i64
    %kind = arith.extui %isall : i1 to i64
    %plen = arith.subi %n, %start : i64
    scf.yield %kind, %start, %plen, %c0 : i64, i64, i64, i64
  }
  return %r#0, %r#1, %r#2, %r#3 : i64, i64, i64, i64
}

// the order of two elements' paths: their bytes, unsigned (memcmp's sign, then the shorter first)
func.func private @cx_order(%pa: !llvm.ptr, %na: i64, %pb: !llvm.ptr, %nb: i64) -> i32 {
  %ia:4 = func.call @cx_info(%pa, %na) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
  %ib:4 = func.call @cx_info(%pb, %nb) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
  %qa = llvm.getelementptr %pa[%ia#1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %qb = llvm.getelementptr %pb[%ib#1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %da = func.call @cx_desc(%qa, %ia#2) : (!llvm.ptr, i64) -> !d
  %db = func.call @cx_desc(%qb, %ib#2) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m8
  %mb = builtin.unrealized_conversion_cast %db : !d to !m8
  %ta = builtin.unrealized_conversion_cast %ma : !m8 to !t
  %tb = builtin.unrealized_conversion_cast %mb : !m8 to !t
  %c = trikeshed.compare %ta, %tb unsigned : !t, !t
  return %c : i32
}

func.func @nixev_ts_getContext(%st: !llvm.ptr, %bb: !llvm.ptr, %elems: !llvm.ptr, %n: i64, %outs: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %ed = func.call @cx_desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  %em = builtin.unrealized_conversion_cast %ed : !d to !m
  %ptrs = builtin.unrealized_conversion_cast %em : !m to !s
  %lens = trikeshed.alpha %ptrs : !s -> !s {
  ^bb0(%pw: i64):
    %p = llvm.inttoptr %pw : i64 to !llvm.ptr
    %l = func.call @strlen(%p) : (!llvm.ptr) -> i64
    trikeshed.yield %l : i64
  }
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %order = trikeshed.sorted %idx : !s -> !s by {
  ^bb0(%a: i64, %b: i64):
    %ai = arith.index_cast %a : i64 to index
    %bi = arith.index_cast %b : i64 to index
    %pa = trikeshed.at %ptrs[%ai] : !s, index -> i64
    %pb = trikeshed.at %ptrs[%bi] : !s, index -> i64
    %na = trikeshed.at %lens[%ai] : !s, index -> i64
    %nb = trikeshed.at %lens[%bi] : !s, index -> i64
    %qa = llvm.inttoptr %pa : i64 to !llvm.ptr
    %qb = llvm.inttoptr %pb : i64 to !llvm.ptr
    %c = func.call @cx_order(%qa, %na, %qb, %nb) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    trikeshed.yield %c : i32
  }
  // the first row of each path's run
  %starts = trikeshed.where %idx : !s -> !s {
  ^bb0(%r: i64):
    %first = arith.cmpi eq, %r, %c0 : i64
    %rm1 = arith.subi %r, %c1 : i64
    %prev = arith.select %first, %r, %rm1 : i64
    %ri = arith.index_cast %r : i64 to index
    %pi = arith.index_cast %prev : i64 to index
    %a = trikeshed.at %order[%ri] : !s, index -> i64
    %b = trikeshed.at %order[%pi] : !s, index -> i64
    %ai = arith.index_cast %a : i64 to index
    %bi = arith.index_cast %b : i64 to index
    %pa = trikeshed.at %ptrs[%ai] : !s, index -> i64
    %pb = trikeshed.at %ptrs[%bi] : !s, index -> i64
    %na = trikeshed.at %lens[%ai] : !s, index -> i64
    %nb = trikeshed.at %lens[%bi] : !s, index -> i64
    %qa = llvm.inttoptr %pa : i64 to !llvm.ptr
    %qb = llvm.inttoptr %pb : i64 to !llvm.ptr
    %c = func.call @cx_order(%qa, %na, %qb, %nb) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    %z32 = arith.constant 0 : i32
    %new = arith.cmpi ne, %c, %z32 : i32
    %start = arith.ori %first, %new : i1
    trikeshed.yield %start : i1
  }
  %m = trikeshed.size %starts : !s
  scf.for %g = %c0i to %m step %c1i {
    %s0 = trikeshed.at %starts[%g] : !s, index -> i64
    %g1 = arith.addi %g, %c1i : index
    %last = arith.cmpi uge, %g1, %m : index
    %g1c = arith.select %last, %g, %g1 : index
    %nx = trikeshed.at %starts[%g1c] : !s, index -> i64
    %e = arith.select %last, %n, %nx : i64
    %cnt = arith.subi %e, %s0 : i64
    %si = arith.index_cast %s0 : i64 to index
    %cnti = arith.index_cast %cnt : i64 to index
    %run = trikeshed.slice %order[%si, %cnti] : !s -> !s
    // path 1, allOutputs 2
    %flags = trikeshed.fold %run, %c0 : !s, i64 -> i64 {
    ^bb0(%acc: i64, %i: i64):
      %ii = arith.index_cast %i : i64 to index
      %pw = trikeshed.at %ptrs[%ii] : !s, index -> i64
      %l = trikeshed.at %lens[%ii] : !s, index -> i64
      %p = llvm.inttoptr %pw : i64 to !llvm.ptr
      %inf:4 = func.call @cx_info(%p, %l) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
      %isp = arith.cmpi eq, %inf#0, %c0 : i64
      %isa = arith.cmpi eq, %inf#0, %c1 : i64
      %bp = arith.ori %acc, %c1 : i64
      %ba = arith.ori %acc, %c2 : i64
      %t = arith.select %isa, %ba, %acc : i64
      %r = arith.select %isp, %bp, %t : i64
      trikeshed.yield %r : i64
    }
    %outrows = trikeshed.where %run : !s -> !s {
    ^bb0(%i: i64):
      %ii = arith.index_cast %i : i64 to index
      %pw = trikeshed.at %ptrs[%ii] : !s, index -> i64
      %l = trikeshed.at %lens[%ii] : !s, index -> i64
      %p = llvm.inttoptr %pw : i64 to !llvm.ptr
      %inf:4 = func.call @cx_info(%p, %l) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
      %iso = arith.cmpi eq, %inf#0, %c2 : i64
      trikeshed.yield %iso : i1
    }
    %no = trikeshed.size %outrows : !s
    %words = arith.muli %no, %c2i : index
    %wins = trikeshed.series %words : !s {
    ^bb0(%q: index):
      %r = arith.divui %q, %c2i : index
      %h = arith.remui %q, %c2i : index
      %i = trikeshed.at %outrows[%r] : !s, index -> i64
      %ii = arith.index_cast %i : i64 to index
      %pw = trikeshed.at %ptrs[%ii] : !s, index -> i64
      %l = trikeshed.at %lens[%ii] : !s, index -> i64
      %p = llvm.inttoptr %pw : i64 to !llvm.ptr
      %inf:4 = func.call @cx_info(%p, %l) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
      %odd = arith.cmpi ne, %h, %c0i : index
      %at1 = arith.addi %pw, %c1 : i64
      %w = arith.select %odd, %at1, %inf#3 : i64
      trikeshed.yield %w : i64
    }
    %w64 = arith.index_cast %words : index to i64
    %od = func.call @cx_desc(%outs, %w64) : (!llvm.ptr, i64) -> !d
    %into = builtin.unrealized_conversion_cast %od : !d to !m
    %end = trikeshed.drain %wins, %into : !s, !m -> index
    %h0 = trikeshed.at %order[%si] : !s, index -> i64
    %hi = arith.index_cast %h0 : i64 to index
    %hpw = trikeshed.at %ptrs[%hi] : !s, index -> i64
    %hl = trikeshed.at %lens[%hi] : !s, index -> i64
    %hp = llvm.inttoptr %hpw : i64 to !llvm.ptr
    %hinf:4 = func.call @cx_info(%hp, %hl) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
    %path = llvm.getelementptr %hp[%hinf#1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %no64 = arith.index_cast %no : index to i64
    func.call @nixev_cx_group(%st, %bb, %path, %hinf#2, %flags, %outs, %no64) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
  }
  return
}
