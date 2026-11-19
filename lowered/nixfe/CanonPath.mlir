// nixfe::canonPath's segment walk (lib/Frontend/Parser.cpp) hollowed into the TrikeShed dialect.  Parser.cpp keeps only
// the bridge that sizes the composite::Text and adopts the drained size; the walk is here, in trikeshed.at / slice /
// text / drain over series<i8>, lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt
// mlnix_lower_trikeshed).  Built into NixFrontend: mlnix-parse links NixFrontend alone.
//
// Nix semantics, byte for byte the old C++: walk a's segments, then b's (two separate walks — a segment never crosses
// from a into b).  A segment ends at '/' or the end; skip empty and "." segments; ".." removes the last segment written
// (never past `from`, the size the output Text already had); every other segment is written as '/' + its bytes.
// Nothing written: a lone '/'.  Trailing slashes are NOT kept (the parser adds its own).
//
// The entry drains into room the caller reserved (the Encoders.mlir way) and returns the new size.  Nothing throws:
// canonPath is pure.  A descriptor is built inline as a struct (returning it allocates nothing and clones nothing) and
// cast to the strided memref at the use site.  Helper names are module-unique: convert-func-to-llvm makes them global.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @canon_slash_g : memref<1xi8> = dense<47>

// the descriptor of n i8 cells at p
func.func private @canon_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// drain the one-byte constant '/' at out + k
func.func private @canon_put_slash(%out: !llvm.ptr, %k: i64) {
  %g = memref.get_global @canon_slash_g : memref<1xi8>
  %t = trikeshed.text %g : memref<1xi8> -> !s
  %p = llvm.getelementptr %out[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %c1 = arith.constant 1 : i64
  %d = func.call @canon_desc8(%p, %c1) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %e = trikeshed.drain %t, %mm : !s, !m -> index
  return
}

// one walk of canonPath: the segments of ss (up to n bytes), written at out + k.  `from` is the floor the ".." pop
// never goes below (the size the output Text had before canonPath); k0 the size written so far.  Returns the new size.
func.func private @canon_walk(%ss: !s, %n: i64, %out: !llvm.ptr, %from: i64, %k0: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %zi = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %c46 = arith.constant 46 : i8
  %c47 = arith.constant 47 : i8
  %ni = arith.index_cast %n : i64 to index
  %nm1 = arith.subi %ni, %c1i : index
  %walk:2 = scf.while (%p = %zi, %k = %k0) : (index, i64) -> (index, i64) {
    %go = arith.cmpi ult, %p, %ni : index
    scf.condition(%go) %p, %k : index, i64
  } do {
  ^bb0(%p: index, %k: i64):
    // the segment [p, e): e the first '/' at or after p, else n (the read clamps to the last byte)
    %e = scf.while (%q = %p) : (index) -> index {
      %in = arith.cmpi ult, %q, %ni : index
      %qs = arith.minsi %q, %nm1 : index
      %ch = trikeshed.at %ss[%qs] : !s, index -> i8
      %nots = arith.cmpi ne, %ch, %c47 : i8
      %go = arith.andi %in, %nots : i1
      scf.condition(%go) %q : index
    } do {
    ^bb0(%q: index):
      %qp1 = arith.addi %q, %c1i : index
      scf.yield %qp1 : index
    }
    %len = arith.subi %e, %p : index
    %is0 = arith.cmpi eq, %len, %zi : index
    %ch0 = trikeshed.at %ss[%p] : !s, index -> i8
    %dot0 = arith.cmpi eq, %ch0, %c46 : i8
    %is1 = arith.cmpi eq, %len, %c1i : index
    %isdot = arith.andi %is1, %dot0 : i1
    %pp1 = arith.addi %p, %c1i : index
    %p1s = arith.minsi %pp1, %nm1 : index
    %ch1 = trikeshed.at %ss[%p1s] : !s, index -> i8
    %dot1 = arith.cmpi eq, %ch1, %c46 : i8
    %is2b = arith.cmpi eq, %len, %c2i : index
    %dots = arith.andi %dot0, %dot1 : i1
    %isdd = arith.andi %is2b, %dots : i1
    %skip = arith.ori %is0, %isdot : i1
    %k2 = scf.if %isdd -> i64 {
      // "..": the last segment written goes, if there is one — scan back to its '/', never past from
      %above = arith.cmpi sgt, %k, %from : i64
      %kpop = scf.if %above -> i64 {
        %od = func.call @canon_desc8(%out, %k) : (!llvm.ptr, i64) -> !d
        %om = builtin.unrealized_conversion_cast %od : !d to !m
        %os = builtin.unrealized_conversion_cast %om : !m to !s
        %kscan = scf.while (%j = %k) : (i64) -> i64 {
          %gt = arith.cmpi sgt, %j, %from : i64
          %jm1 = arith.subi %j, %c1 : i64
          %ji = arith.index_cast %jm1 : i64 to index
          %ch = trikeshed.at %os[%ji] : !s, index -> i8
          %nots = arith.cmpi ne, %ch, %c47 : i8
          %go = arith.andi %gt, %nots : i1
          scf.condition(%go) %j : i64
        } do {
        ^bb0(%j: i64):
          %jm1 = arith.subi %j, %c1 : i64
          scf.yield %jm1 : i64
        }
        %still = arith.cmpi sgt, %kscan, %from : i64
        %k3 = arith.subi %kscan, %c1 : i64
        %k4 = arith.select %still, %k3, %kscan : i64
        scf.yield %k4 : i64
      } else {
        scf.yield %k : i64
      }
      scf.yield %kpop : i64
    } else {
      %k3 = scf.if %skip -> i64 {
        scf.yield %k : i64
      } else {
        // '/' + the segment's bytes
        %k1 = arith.addi %k, %c1 : i64
        func.call @canon_put_slash(%out, %k) : (!llvm.ptr, i64) -> ()
        %sl = trikeshed.slice %ss[%p, %len] : !s -> !s
        %len64 = arith.index_cast %len : index to i64
        %ptr1 = llvm.getelementptr %out[%k1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %dd = func.call @canon_desc8(%ptr1, %len64) : (!llvm.ptr, i64) -> !d
        %dm = builtin.unrealized_conversion_cast %dd : !d to !m
        %e1 = trikeshed.drain %sl, %dm : !s, !m -> index
        %kn = arith.addi %k1, %len64 : i64
        scf.yield %kn : i64
      }
      scf.yield %k3 : i64
    }
    // past the segment's slash, when there was one
    %hasslash = arith.cmpi ult, %e, %ni : index
    %ep1 = arith.addi %e, %c1i : index
    %p2 = arith.select %hasslash, %ep1, %e : index
    scf.yield %p2, %k2 : index, i64
  }
  return %walk#1 : i64
}

// nixfe::canonPath(out, a, b): the canonical absolute path, appended to out's own bytes.  `from` is the size out
// already had (the ".." pop never goes below it); out has room for from + an + bn + 1.  Returns the new size.
func.func @nixfe_ts_canonpath(%ap: !llvm.ptr, %an: i64, %bp: !llvm.ptr, %bn: i64, %out: !llvm.ptr, %from: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %ad = func.call @canon_desc8(%ap, %an) : (!llvm.ptr, i64) -> !d
  %am = builtin.unrealized_conversion_cast %ad : !d to !m
  %sa = builtin.unrealized_conversion_cast %am : !m to !s
  %bd = func.call @canon_desc8(%bp, %bn) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m
  %sb = builtin.unrealized_conversion_cast %bm : !m to !s
  %k1 = func.call @canon_walk(%sa, %an, %out, %from, %from) : (!s, i64, !llvm.ptr, i64, i64) -> i64
  %k2 = func.call @canon_walk(%sb, %bn, %out, %from, %k1) : (!s, i64, !llvm.ptr, i64, i64) -> i64
  // nothing written: a lone '/'
  %nowhere = arith.cmpi eq, %k2, %from : i64
  %kout = scf.if %nowhere -> i64 {
    func.call @canon_put_slash(%out, %from) : (!llvm.ptr, i64) -> ()
    %kn = arith.addi %from, %c1 : i64
    scf.yield %kn : i64
  } else {
    scf.yield %k2 : i64
  }
  return %kout : i64
}
