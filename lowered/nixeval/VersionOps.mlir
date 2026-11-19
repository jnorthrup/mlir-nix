// Version comparison (upstream names.cc) hollowed into the TrikeShed dialect: __compareVersions and __splitVersion's
// component scan.  lib/Eval/Builtins.cpp keeps only the forcing of operands (Nix's error order and wording) and the
// stoll reading of a numeric component (nixev_ver_int below: its std::out_of_range throw and libc++/libstdc++ wording
// stay in C++); the component walk, the "pre" rule and the byte order are here, in trikeshed.at / slice / compare /
// text over the strings' bytes, lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).  A string is seen as a series<i8>: the descriptor of n bytes at p is
// built inline and cast to the series' strided memref, as ListOps.mlir does for a list's cells.
//
// Text order is unsigned (Kotlin's Char order, memcmp's): std::string_view's operator< compares unsigned char.
!s8 = !trikeshed.series<i8>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d8 = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// "pre", the component that sorts before every other (componentsLT's rule)
memref.global "private" constant @ver_pre : memref<3xi8> = dense<[112, 114, 101]>

// the stoll reading of a component: 1 and its value when digits all through, 0 otherwise; throws std::out_of_range
// past the range of long long (the C++ side keeps the throw and its platform's wording)
func.func private @nixev_ver_int(!llvm.ptr, i64, !llvm.ptr) -> i64

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @ver_desc(%p: !llvm.ptr, %n: i64) -> !d8 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d8
  %a = llvm.insertvalue %p, %u[0] : !d8
  %b = llvm.insertvalue %p, %a[1] : !d8
  %c = llvm.insertvalue %c0, %b[2] : !d8
  %e = llvm.insertvalue %n, %c[3, 0] : !d8
  %f = llvm.insertvalue %c1, %e[4, 0] : !d8
  return %f : !d8
}

// nextComponent: skip '.' and '-', then the run of digits (or of non-digits that are not '.' or '-') that follows;
// (start, length) of the component, empty at the end.  The next position is start + length.
func.func private @ver_next(%xs: !s8, %n: index, %from: index) -> (index, index) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %dot = arith.constant 46 : i8
  %dash = arith.constant 45 : i8
  %zero = arith.constant 48 : i8
  %ten = arith.constant 10 : i8
  %true = arith.constant true
  %false = arith.constant false
  %skipped = scf.while (%i = %from) : (index) -> index {
    %in = arith.cmpi ult, %i, %n : index
    %sep = scf.if %in -> (i1) {
      %b = trikeshed.at %xs[%i] : !s8, index -> i8
      %isd = arith.cmpi eq, %b, %dot : i8
      %ish = arith.cmpi eq, %b, %dash : i8
      %or = arith.ori %isd, %ish : i1
      scf.yield %or : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%sep) %i : index
  } do {
  ^bb0(%i: index):
    %i2 = arith.addi %i, %c1 : index
    scf.yield %i2 : index
  }
  %ate = arith.cmpi eq, %skipped, %n : index
  %sl_s, %sl_l = scf.if %ate -> (index, index) {
    scf.yield %skipped, %c0 : index, index
  } else {
    %b0 = trikeshed.at %xs[%skipped] : !s8, index -> i8
    %d0 = arith.subi %b0, %zero : i8
    %dig0 = arith.cmpi ult, %d0, %ten : i8
    %end = scf.if %dig0 -> (index) {
      %e = scf.while (%j = %skipped) : (index) -> index {
        %in = arith.cmpi ult, %j, %n : index
        %go = scf.if %in -> (i1) {
          %b = trikeshed.at %xs[%j] : !s8, index -> i8
          %d = arith.subi %b, %zero : i8
          %dig = arith.cmpi ult, %d, %ten : i8
          scf.yield %dig : i1
        } else {
          scf.yield %false : i1
        }
        scf.condition(%go) %j : index
      } do {
      ^bb0(%j: index):
        %j2 = arith.addi %j, %c1 : index
        scf.yield %j2 : index
      }
      scf.yield %e : index
    } else {
      %e = scf.while (%j = %skipped) : (index) -> index {
        %in = arith.cmpi ult, %j, %n : index
        %go = scf.if %in -> (i1) {
          %b = trikeshed.at %xs[%j] : !s8, index -> i8
          %d = arith.subi %b, %zero : i8
          %dig = arith.cmpi ult, %d, %ten : i8
          %ndig = arith.xori %dig, %true : i1
          %isd = arith.cmpi eq, %b, %dot : i8
          %ish = arith.cmpi eq, %b, %dash : i8
          %sep = arith.ori %isd, %ish : i1
          %nsep = arith.xori %sep, %true : i1
          %and = arith.andi %ndig, %nsep : i1
          scf.yield %and : i1
        } else {
          scf.yield %false : i1
        }
        scf.condition(%go) %j : index
      } do {
      ^bb0(%j: index):
        %j2 = arith.addi %j, %c1 : index
        scf.yield %j2 : index
      }
      scf.yield %e : index
    }
    %len = arith.subi %end, %skipped : index
    scf.yield %skipped, %len : index, index
  }
  return %sl_s, %sl_l : index, index
}

// componentsLT(c1, c2): two numeric components compare by value; an empty component is below a numeric one; "pre" is
// below everything but itself; a numeric component is above a non-numeric one; else the bytes, unsigned.  The stoll
// readings happen first, in order (either may throw, as the C++ toInt did); the rest is pure, so the rules are one
// select chain.  The slices are views: they stay in this function, read by compare.
func.func private @ver_lt(%xs1: !s8, %s1: index, %l1: index, %xs2: !s8, %s2: index, %l2: index, %p1: !llvm.ptr, %p2: !llvm.ptr) -> i1 {
  %c0 = arith.constant 0 : index
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %zero32 = arith.constant 0 : i32
  %true = arith.constant true
  %false = arith.constant false
  %s1_64 = arith.index_cast %s1 : index to i64
  %l1_64 = arith.index_cast %l1 : index to i64
  %s2_64 = arith.index_cast %s2 : index to i64
  %l2_64 = arith.index_cast %l2 : index to i64
  %q1 = llvm.getelementptr %p1[%s1_64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %q2 = llvm.getelementptr %p2[%s2_64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %o1 = llvm.alloca %c1i x i64 : (i64) -> !llvm.ptr
  %o2 = llvm.alloca %c1i x i64 : (i64) -> !llvm.ptr
  %i1 = func.call @nixev_ver_int(%q1, %l1_64, %o1) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %i2 = func.call @nixev_ver_int(%q2, %l2_64, %o2) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %b1 = arith.cmpi ne, %i1, %c0i : i64
  %b2 = arith.cmpi ne, %i2, %c0i : i64
  %both = arith.andi %b1, %b2 : i1
  %v1 = llvm.load %o1 : !llvm.ptr -> i64
  %v2 = llvm.load %o2 : !llvm.ptr -> i64
  %numlt = arith.cmpi slt, %v1, %v2 : i64
  %empty1 = arith.cmpi eq, %l1, %c0 : index
  %ei2 = arith.andi %empty1, %b2 : i1
  %c1s = trikeshed.slice %xs1[%s1, %l1] : !s8 -> !s8
  %c2s = trikeshed.slice %xs2[%s2, %l2] : !s8 -> !s8
  %g = memref.get_global @ver_pre : memref<3xi8>
  %pre = trikeshed.text %g : memref<3xi8> -> !s8
  %pc1 = trikeshed.compare %c1s, %pre unsigned : !s8, !s8
  %pc2 = trikeshed.compare %c2s, %pre unsigned : !s8, !s8
  %ispre1 = arith.cmpi eq, %pc1, %zero32 : i32
  %ispre2 = arith.cmpi eq, %pc2, %zero32 : i32
  %notpre2 = arith.xori %ispre2, %true : i1
  %pre12 = arith.andi %ispre1, %notpre2 : i1
  %lex = trikeshed.compare %c1s, %c2s unsigned : !s8, !s8
  %lexlt = arith.cmpi slt, %lex, %zero32 : i32
  %r5 = arith.select %b2, %true, %lexlt : i1
  %r4 = arith.select %b1, %false, %r5 : i1
  %r3 = arith.select %ispre2, %false, %r4 : i1
  %r2 = arith.select %pre12, %true, %r3 : i1
  %r1 = arith.select %ei2, %true, %r2 : i1
  %r = arith.select %both, %numlt, %r1 : i1
  return %r : i1
}

// __compareVersions: walk the components of both versions while either has bytes left; the first pair that differs
// one way or the other decides (-1 / 1), else 0.  The bridge has forced both strings.
func.func @nixev_ts_compare_versions(%a: !llvm.ptr, %an: i64, %b: !llvm.ptr, %bn: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c0i = arith.constant 0 : i64
  %c1i = arith.constant 1 : i64
  %cm1 = arith.constant -1 : i64
  %true = arith.constant true
  %false = arith.constant false
  %n1 = arith.index_cast %an : i64 to index
  %n2 = arith.index_cast %bn : i64 to index
  %d1 = func.call @ver_desc(%a, %an) : (!llvm.ptr, i64) -> !d8
  %m1 = builtin.unrealized_conversion_cast %d1 : !d8 to !m8
  %xs1 = builtin.unrealized_conversion_cast %m1 : !m8 to !s8
  %d2 = func.call @ver_desc(%b, %bn) : (!llvm.ptr, i64) -> !d8
  %m2 = builtin.unrealized_conversion_cast %d2 : !d8 to !m8
  %xs2 = builtin.unrealized_conversion_cast %m2 : !m8 to !s8
  %p1f, %p2f, %res, %gof = scf.while (%p1 = %c0, %p2 = %c0, %r = %c0i, %go = %true) : (index, index, i64, i1) -> (index, index, i64, i1) {
    %more1 = arith.cmpi ult, %p1, %n1 : index
    %more2 = arith.cmpi ult, %p2, %n2 : index
    %more = arith.ori %more1, %more2 : i1
    %cond = arith.andi %go, %more : i1
    scf.condition(%cond) %p1, %p2, %r, %go : index, index, i64, i1
  } do {
  ^bb0(%p1: index, %p2: index, %r: i64, %go: i1):
    %s1, %l1 = func.call @ver_next(%xs1, %n1, %p1) : (!s8, index, index) -> (index, index)
    %s2, %l2 = func.call @ver_next(%xs2, %n2, %p2) : (!s8, index, index) -> (index, index)
    %np1 = arith.addi %s1, %l1 : index
    %np2 = arith.addi %s2, %l2 : index
    %lt12 = func.call @ver_lt(%xs1, %s1, %l1, %xs2, %s2, %l2, %a, %b) : (!s8, index, index, !s8, index, index, !llvm.ptr, !llvm.ptr) -> i1
    %rg_r, %rg_go = scf.if %lt12 -> (i64, i1) {
      scf.yield %cm1, %false : i64, i1
    } else {
      %lt21 = func.call @ver_lt(%xs2, %s2, %l2, %xs1, %s1, %l1, %b, %a) : (!s8, index, index, !s8, index, index, !llvm.ptr, !llvm.ptr) -> i1
      %rg2_r, %rg2_go = scf.if %lt21 -> (i64, i1) {
        scf.yield %c1i, %false : i64, i1
      } else {
        scf.yield %r, %true : i64, i1
      }
      scf.yield %rg2_r, %rg2_go : i64, i1
    }
    scf.yield %np1, %np2, %rg_r, %rg_go : index, index, i64, i1
  }
  return %res : i64
}

// __splitVersion's scan: the component at or after `from`, its (start, length) written out, the next position returned.
// The bridge keeps the list of string views and the evaluator's newString (a std::string_view interface).
func.func @nixev_ts_next_component(%p: !llvm.ptr, %n: i64, %from: i64, %sout: !llvm.ptr, %lout: !llvm.ptr) -> i64 {
  %ni = arith.index_cast %n : i64 to index
  %fi = arith.index_cast %from : i64 to index
  %d = func.call @ver_desc(%p, %n) : (!llvm.ptr, i64) -> !d8
  %mm = builtin.unrealized_conversion_cast %d : !d8 to !m8
  %xs = builtin.unrealized_conversion_cast %mm : !m8 to !s8
  %s, %l = func.call @ver_next(%xs, %ni, %fi) : (!s8, index, index) -> (index, index)
  %s64 = arith.index_cast %s : index to i64
  %l64 = arith.index_cast %l : index to i64
  llvm.store %s64, %sout : i64, !llvm.ptr
  llvm.store %l64, %lout : i64, !llvm.ptr
  %np = arith.addi %s64, %l64 : i64
  return %np : i64
}
