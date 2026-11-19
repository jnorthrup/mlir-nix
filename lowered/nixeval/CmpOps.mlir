// EvalState::eqValues and EvalState::lessThan hollowed into the TrikeShed dialect.  lib/Eval/Eval.cpp keeps only thin
// bridges (the methods forward here) and the callbacks: forcing (nixev_cmp_force, the inline forceValue check), the
// error wording (the throws), the outPath attribute lookup (nixev_attr_get) and isDerivation (called by its mangled
// name, still C++: it forces the type attribute).  The type dispatch, the int/float cross-comparison, the scalar
// comparisons, the list and attribute walks and the recursion are here: a list's cells (Value**) are a series<i64> of
// pointer bits (the descriptor built inline, as ListOps.mlir does), a string or path is a series<i8> compared unsigned
// (trikeshed.compare: the first difference, then the shorter one is less — std::string_view's order).  The walks
// short-circuit (scf.while, as ListOps2.mlir's any/all/elem): a later element is never forced once the answer is known.
// The recursion is func.call back into these entries; a C++ exception thrown in a callback unwinds through the compiled
// frames, as fold's callFunction does in ListOps.mlir.
//
// Value 24 bytes: VType u8@0 (Int 5, Float 6, Bool 7, Null 8, String 9, Path 10, Attrs 11, List 12, Lambda 13,
// PrimOp 14, PrimOpApp 15), aux u32@4 (string/path length, list size), union@8 (integer i64 / fpoint f64 / boolean u8 /
// str.s ptr / path.s ptr / attrs ptr / list.elems ptr).  Bindings: u32 size_@0, PosPtr pos@8, Attr rows@16, sorted by
// Symbol; Attr 16 bytes: name u32@0, pos u32@4, value ptr@8.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!s8 = !trikeshed.series<i8>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d8 = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// forcing (the inline forceValue: the thunk test and the stats census stay in C++)
func.func private @nixev_cmp_force(!llvm.ptr, !llvm.ptr, !llvm.ptr)
// the throws: "cannot compare X with Y" (eqValues' default, lessThan's type mismatch) and lessThan's incomparable
func.func private @nixev_cmp_eq_throw(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_cmp_lt_inc(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
// the outPath attribute of a set (which 0), or its __toString (which 1): the Attr, or null
func.func private @nixev_attr_get(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(!llvm.ptr, !llvm.ptr) -> i8

// the descriptor of n i64 cells at p (module-unique: ListOps.mlir has its own @desc)
func.func private @ceq_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the descriptor of n bytes at p
func.func private @ceq_desc8(%p: !llvm.ptr, %n: i64) -> !d8 {
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

// two strings' order: the first differing byte (unsigned), else the shorter one is less (-1 / 0 / 1)
func.func private @ceq_bytes_cmp(%p1: !llvm.ptr, %n1: i64, %p2: !llvm.ptr, %n2: i64) -> i32 {
  %d1 = func.call @ceq_desc8(%p1, %n1) : (!llvm.ptr, i64) -> !d8
  %m1 = builtin.unrealized_conversion_cast %d1 : !d8 to !m8
  %s1 = builtin.unrealized_conversion_cast %m1 : !m8 to !s8
  %d2 = func.call @ceq_desc8(%p2, %n2) : (!llvm.ptr, i64) -> !d8
  %m2 = builtin.unrealized_conversion_cast %d2 : !d8 to !m8
  %s2 = builtin.unrealized_conversion_cast %m2 : !m8 to !s8
  %c = trikeshed.compare %s1, %s2 unsigned : !s8, !s8
  return %c : i32
}

// the list walk: the sizes must match, then each pair of cells (one value, equal without a look, when the pointers
// match); the first unequal pair decides, a later element is never forced
func.func private @ceq_list_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %n1p = llvm.getelementptr %v1[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n1_32 = llvm.load %n1p : !llvm.ptr -> i32
  %n1 = llvm.zext %n1_32 : i32 to i64
  %n2p = llvm.getelementptr %v2[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n2_32 = llvm.load %n2p : !llvm.ptr -> i32
  %n2 = llvm.zext %n2_32 : i32 to i64
  %sizediff = arith.cmpi ne, %n1, %n2 : i64
  %r = scf.if %sizediff -> (i64) {
    scf.yield %c0 : i64
  } else {
    %e1p = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %e1 = llvm.load %e1p : !llvm.ptr -> !llvm.ptr
    %e2p = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %e2 = llvm.load %e2p : !llvm.ptr -> !llvm.ptr
    %d1 = func.call @ceq_desc(%e1, %n1) : (!llvm.ptr, i64) -> !d
    %mm1 = builtin.unrealized_conversion_cast %d1 : !d to !m
    %ss1 = builtin.unrealized_conversion_cast %mm1 : !m to !s
    %d2 = func.call @ceq_desc(%e2, %n2) : (!llvm.ptr, i64) -> !d
    %mm2 = builtin.unrealized_conversion_cast %d2 : !d to !m
    %ss2 = builtin.unrealized_conversion_cast %mm2 : !m to !s
    %ni = arith.index_cast %n1 : i64 to index
    %w:2 = scf.while (%i = %zi, %acc = %c1) : (index, i64) -> (index, i64) {
      %inside = arith.cmpi ult, %i, %ni : index
      %still = arith.cmpi ne, %acc, %c0 : i64
      %go = arith.andi %inside, %still : i1
      scf.condition(%go) %i, %acc : index, i64
    } do {
    ^bb0(%i: index, %acc: i64):
      %a = trikeshed.at %ss1[%i] : !s, index -> i64
      %b = trikeshed.at %ss2[%i] : !s, index -> i64
      %same = arith.cmpi eq, %a, %b : i64
      %acc2 = scf.if %same -> (i64) {
        scf.yield %acc : i64
      } else {
        %ap = llvm.inttoptr %a : i64 to !llvm.ptr
        %bp = llvm.inttoptr %b : i64 to !llvm.ptr
        %e = func.call @nixev_ts_eq(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %e : i64
      }
      %i2 = arith.addi %i, %oi : index
      scf.yield %i2, %acc2 : index, i64
    }
    scf.yield %w#1 : i64
  }
  return %r : i64
}

// the attribute walk: one set (the same Bindings) is equal without a look; two derivations compare by their outPath
// cells when both have one (isDerivation forces each type attribute, v1 first, as the C++ && did); else the sizes must
// match and the rows walk in symbol order: a different name decides, a shared value cell is equal without a look
func.func private @ceq_attrs_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %cm1 = arith.constant -1 : i64
  %c0_8 = arith.constant 0 : i8
  %c16 = arith.constant 16 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %b1p = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %b1 = llvm.load %b1p : !llvm.ptr -> !llvm.ptr
  %b2p = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %b2 = llvm.load %b2p : !llvm.ptr -> !llvm.ptr
  %b1i = llvm.ptrtoint %b1 : !llvm.ptr to i64
  %b2i = llvm.ptrtoint %b2 : !llvm.ptr to i64
  %sameb = arith.cmpi eq, %b1i, %b2i : i64
  %r_same = scf.if %sameb -> (i64) {
    scf.yield %c1 : i64
  } else {
    scf.yield %cm1 : i64
  }
  %und1 = arith.cmpi eq, %r_same, %cm1 : i64
  %r_drv = scf.if %und1 -> (i64) {
    %d1 = func.call @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(%st, %v1) : (!llvm.ptr, !llvm.ptr) -> i8
    %d1n = arith.cmpi ne, %d1, %c0_8 : i8
    %r_d1 = scf.if %d1n -> (i64) {
      %d2 = func.call @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(%st, %v2) : (!llvm.ptr, !llvm.ptr) -> i8
      %d2n = arith.cmpi ne, %d2, %c0_8 : i8
      %r_d2 = scf.if %d2n -> (i64) {
        %i = func.call @nixev_attr_get(%st, %v1, %c0) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
        %j = func.call @nixev_attr_get(%st, %v2, %c0) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
        %ii = llvm.ptrtoint %i : !llvm.ptr to i64
        %ji = llvm.ptrtoint %j : !llvm.ptr to i64
        %inz = arith.cmpi ne, %ii, %c0 : i64
        %jnz = arith.cmpi ne, %ji, %c0 : i64
        %both = arith.andi %inz, %jnz : i1
        %r_both = scf.if %both -> (i64) {
          %ivp = llvm.getelementptr %i[8] : (!llvm.ptr) -> !llvm.ptr, i8
          %iv = llvm.load %ivp : !llvm.ptr -> !llvm.ptr
          %jvp = llvm.getelementptr %j[8] : (!llvm.ptr) -> !llvm.ptr, i8
          %jv = llvm.load %jvp : !llvm.ptr -> !llvm.ptr
          %ivi = llvm.ptrtoint %iv : !llvm.ptr to i64
          %jvi = llvm.ptrtoint %jv : !llvm.ptr to i64
          %peq = arith.cmpi eq, %ivi, %jvi : i64
          %r_pe = scf.if %peq -> (i64) {
            scf.yield %c1 : i64
          } else {
            %e = func.call @nixev_ts_eq(%st, %iv, %jv, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
            scf.yield %e : i64
          }
          scf.yield %r_pe : i64
        } else {
          scf.yield %cm1 : i64
        }
        scf.yield %r_both : i64
      } else {
        scf.yield %cm1 : i64
      }
      scf.yield %r_d2 : i64
    } else {
      scf.yield %cm1 : i64
    }
    scf.yield %r_d1 : i64
  } else {
    scf.yield %r_same : i64
  }
  %und2 = arith.cmpi eq, %r_drv, %cm1 : i64
  %r = scf.if %und2 -> (i64) {
    %s1p = llvm.getelementptr %b1[0] : (!llvm.ptr) -> !llvm.ptr, i8
    %s1 = llvm.load %s1p : !llvm.ptr -> i32
    %s2p = llvm.getelementptr %b2[0] : (!llvm.ptr) -> !llvm.ptr, i8
    %s2 = llvm.load %s2p : !llvm.ptr -> i32
    %sizediff = arith.cmpi ne, %s1, %s2 : i32
    %r_sz = scf.if %sizediff -> (i64) {
      scf.yield %c0 : i64
    } else {
      %n = llvm.zext %s1 : i32 to i64
      %ni = arith.index_cast %n : i64 to index
      %w:2 = scf.while (%k = %zi, %acc = %c1) : (index, i64) -> (index, i64) {
        %inside = arith.cmpi ult, %k, %ni : index
        %still = arith.cmpi ne, %acc, %c0 : i64
        %go = arith.andi %inside, %still : i1
        scf.condition(%go) %k, %acc : index, i64
      } do {
      ^bb0(%k: index, %acc: i64):
        %k64 = arith.index_cast %k : index to i64
        %rowoff = arith.muli %k64, %c16 : i64
        %off = arith.addi %rowoff, %c16 : i64
        %ra = llvm.getelementptr %b1[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %rb = llvm.getelementptr %b2[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %na = llvm.load %ra : !llvm.ptr -> i32
        %nb = llvm.load %rb : !llvm.ptr -> i32
        %namesame = arith.cmpi eq, %na, %nb : i32
        %acc2 = scf.if %namesame -> (i64) {
          %avp = llvm.getelementptr %ra[8] : (!llvm.ptr) -> !llvm.ptr, i8
          %av = llvm.load %avp : !llvm.ptr -> !llvm.ptr
          %bvp = llvm.getelementptr %rb[8] : (!llvm.ptr) -> !llvm.ptr, i8
          %bv = llvm.load %bvp : !llvm.ptr -> !llvm.ptr
          %avi = llvm.ptrtoint %av : !llvm.ptr to i64
          %bvi = llvm.ptrtoint %bv : !llvm.ptr to i64
          %peq = arith.cmpi eq, %avi, %bvi : i64
          %acc3 = scf.if %peq -> (i64) {
            scf.yield %acc : i64
          } else {
            %e = func.call @nixev_ts_eq(%st, %av, %bv, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
            scf.yield %e : i64
          }
          scf.yield %acc3 : i64
        } else {
          scf.yield %c0 : i64
        }
        %k2 = arith.addi %k, %oi : index
        scf.yield %k2, %acc2 : index, i64
      }
      scf.yield %w#1 : i64
    }
    scf.yield %r_sz : i64
  } else {
    scf.yield %r_drv : i64
  }
  return %r : i64
}

// eqValues: force both, the int/float cross-comparison, the function types normalized (PrimOp/PrimOpApp as Lambda),
// then the type dispatch; the walks recurse into this entry
func.func @nixev_ts_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %cm1 = arith.constant -1 : i64
  %c0_32 = arith.constant 0 : i32
  %c5 = arith.constant 5 : i8
  %c6 = arith.constant 6 : i8
  %c7 = arith.constant 7 : i8
  %c8 = arith.constant 8 : i8
  %c9 = arith.constant 9 : i8
  %c10 = arith.constant 10 : i8
  %c11 = arith.constant 11 : i8
  %c12 = arith.constant 12 : i8
  %c13 = arith.constant 13 : i8
  %c14 = arith.constant 14 : i8
  %c15 = arith.constant 15 : i8
  %true = arith.constant true
  func.call @nixev_cmp_force(%st, %v1, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @nixev_cmp_force(%st, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %t1p = llvm.getelementptr %v1[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %t1 = llvm.load %t1p : !llvm.ptr -> i8
  %t2p = llvm.getelementptr %v2[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %t2 = llvm.load %t2p : !llvm.ptr -> i8
  // int == float and float == int: the integer as a double
  %isif = arith.cmpi eq, %t1, %c5 : i8
  %isfi = arith.cmpi eq, %t2, %c6 : i8
  %cross1 = arith.andi %isif, %isfi : i1
  %r1 = scf.if %cross1 -> (i64) {
    %ip = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %i = llvm.load %ip : !llvm.ptr -> i64
    %f1 = arith.sitofp %i : i64 to f64
    %fp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %f2 = llvm.load %fp : !llvm.ptr -> f64
    %e = arith.cmpf oeq, %f1, %f2 : f64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %cm1 : i64
  }
  %u1 = arith.cmpi eq, %r1, %cm1 : i64
  %isfi2 = arith.cmpi eq, %t1, %c6 : i8
  %isif2 = arith.cmpi eq, %t2, %c5 : i8
  %cross2 = arith.andi %isfi2, %isif2 : i1
  %g2 = arith.andi %u1, %cross2 : i1
  %r2 = scf.if %g2 -> (i64) {
    %fp = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %f1 = llvm.load %fp : !llvm.ptr -> f64
    %ip = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %i = llvm.load %ip : !llvm.ptr -> i64
    %f2 = arith.sitofp %i : i64 to f64
    %e = arith.cmpf oeq, %f1, %f2 : f64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %r1 : i64
  }
  // the function types normalize to Lambda for the type test
  %u2 = arith.cmpi eq, %r2, %cm1 : i64
  %p14 = arith.cmpi eq, %t1, %c14 : i8
  %p15 = arith.cmpi eq, %t1, %c15 : i8
  %por1 = arith.ori %p14, %p15 : i1
  %n1 = arith.select %por1, %c13, %t1 : i8
  %q14 = arith.cmpi eq, %t2, %c14 : i8
  %q15 = arith.cmpi eq, %t2, %c15 : i8
  %por2 = arith.ori %q14, %q15 : i1
  %n2 = arith.select %por2, %c13, %t2 : i8
  %typesame = arith.cmpi eq, %n1, %n2 : i8
  %g3 = arith.andi %u2, %typesame : i1
  %r3 = scf.if %g3 -> (i64) {
    %is5 = arith.cmpi eq, %t1, %c5 : i8
    %d5 = scf.if %is5 -> (i64) {
      %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %a = llvm.load %ap : !llvm.ptr -> i64
      %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %b = llvm.load %bp : !llvm.ptr -> i64
      %e = arith.cmpi eq, %a, %b : i64
      %x = arith.extui %e : i1 to i64
      scf.yield %x : i64
    } else {
      scf.yield %cm1 : i64
    }
    %ud5 = arith.cmpi eq, %d5, %cm1 : i64
    %is6 = arith.cmpi eq, %t1, %c6 : i8
    %g6 = arith.andi %ud5, %is6 : i1
    %d6 = scf.if %g6 -> (i64) {
      %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %a = llvm.load %ap : !llvm.ptr -> f64
      %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %b = llvm.load %bp : !llvm.ptr -> f64
      %e = arith.cmpf oeq, %a, %b : f64
      %x = arith.extui %e : i1 to i64
      scf.yield %x : i64
    } else {
      scf.yield %d5 : i64
    }
    %ud6 = arith.cmpi eq, %d6, %cm1 : i64
    %is7 = arith.cmpi eq, %t1, %c7 : i8
    %g7 = arith.andi %ud6, %is7 : i1
    %d7 = scf.if %g7 -> (i64) {
      %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %a = llvm.load %ap : !llvm.ptr -> i8
      %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %b = llvm.load %bp : !llvm.ptr -> i8
      %e = arith.cmpi eq, %a, %b : i8
      %x = arith.extui %e : i1 to i64
      scf.yield %x : i64
    } else {
      scf.yield %d6 : i64
    }
    %ud7 = arith.cmpi eq, %d7, %cm1 : i64
    %is8 = arith.cmpi eq, %t1, %c8 : i8
    %g8 = arith.andi %ud7, %is8 : i1
    %d8 = scf.if %g8 -> (i64) {
      scf.yield %c1 : i64
    } else {
      scf.yield %d7 : i64
    }
    %ud8 = arith.cmpi eq, %d8, %cm1 : i64
    %is9 = arith.cmpi eq, %t1, %c9 : i8
    %is10 = arith.cmpi eq, %t1, %c10 : i8
    %sor = arith.ori %is9, %is10 : i1
    %g9 = arith.andi %ud8, %sor : i1
    %d9 = scf.if %g9 -> (i64) {
      %p1 = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %s1 = llvm.load %p1 : !llvm.ptr -> !llvm.ptr
      %l1p = llvm.getelementptr %v1[4] : (!llvm.ptr) -> !llvm.ptr, i8
      %l1_32 = llvm.load %l1p : !llvm.ptr -> i32
      %l1 = llvm.zext %l1_32 : i32 to i64
      %p2 = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %s2 = llvm.load %p2 : !llvm.ptr -> !llvm.ptr
      %l2p = llvm.getelementptr %v2[4] : (!llvm.ptr) -> !llvm.ptr, i8
      %l2_32 = llvm.load %l2p : !llvm.ptr -> i32
      %l2 = llvm.zext %l2_32 : i32 to i64
      %c = func.call @ceq_bytes_cmp(%s1, %l1, %s2, %l2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      %e = arith.cmpi eq, %c, %c0_32 : i32
      %x = arith.extui %e : i1 to i64
      scf.yield %x : i64
    } else {
      scf.yield %d8 : i64
    }
    %ud9 = arith.cmpi eq, %d9, %cm1 : i64
    %is12 = arith.cmpi eq, %t1, %c12 : i8
    %g12 = arith.andi %ud9, %is12 : i1
    %d12 = scf.if %g12 -> (i64) {
      %e = func.call @ceq_list_eq(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %e : i64
    } else {
      scf.yield %d9 : i64
    }
    %ud12 = arith.cmpi eq, %d12, %cm1 : i64
    %is11 = arith.cmpi eq, %t1, %c11 : i8
    %g11 = arith.andi %ud12, %is11 : i1
    %d11 = scf.if %g11 -> (i64) {
      %e = func.call @ceq_attrs_eq(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %e : i64
    } else {
      scf.yield %d12 : i64
    }
    %ud11 = arith.cmpi eq, %d11, %cm1 : i64
    %is13 = arith.cmpi eq, %t1, %c13 : i8
    %is14 = arith.cmpi eq, %t1, %c14 : i8
    %is15 = arith.cmpi eq, %t1, %c15 : i8
    %f1 = arith.ori %is13, %is14 : i1
    %f2 = arith.ori %f1, %is15 : i1
    %g13 = arith.andi %ud11, %f2 : i1
    %d13 = scf.if %g13 -> (i64) {
      scf.yield %c0 : i64
    } else {
      scf.yield %d11 : i64
    }
    %ud13 = arith.cmpi eq, %d13, %cm1 : i64
    %dflt = scf.if %ud13 -> (i64) {
      func.call @nixev_cmp_eq_throw(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
      scf.yield %c0 : i64
    } else {
      scf.yield %d13 : i64
    }
    scf.yield %dflt : i64
  } else {
    // the cross-comparison already decided, or the normalized types differ (unequal)
    %decided = arith.cmpi ne, %r2, %cm1 : i64
    %relse = arith.select %decided, %r2, %c0 : i64
    scf.yield %relse : i64
  }
  %u3 = arith.cmpi eq, %r3, %cm1 : i64
  %rf = arith.select %u3, %c0, %r3 : i64
  return %rf : i64
}

// the list order: walk both while neither is exhausted and the elements are equal; the first unequal pair decides by
// lessThan; a list exhausted first is less (the right one exhausted first: not less)
func.func private @ceq_list_lt(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %n1p = llvm.getelementptr %v1[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n1_32 = llvm.load %n1p : !llvm.ptr -> i32
  %n1 = llvm.zext %n1_32 : i32 to i64
  %n2p = llvm.getelementptr %v2[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n2_32 = llvm.load %n2p : !llvm.ptr -> i32
  %n2 = llvm.zext %n2_32 : i32 to i64
  %e1p = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %e1 = llvm.load %e1p : !llvm.ptr -> !llvm.ptr
  %e2p = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %e2 = llvm.load %e2p : !llvm.ptr -> !llvm.ptr
  %d1 = func.call @ceq_desc(%e1, %n1) : (!llvm.ptr, i64) -> !d
  %mm1 = builtin.unrealized_conversion_cast %d1 : !d to !m
  %ss1 = builtin.unrealized_conversion_cast %mm1 : !m to !s
  %d2 = func.call @ceq_desc(%e2, %n2) : (!llvm.ptr, i64) -> !d
  %mm2 = builtin.unrealized_conversion_cast %d2 : !d to !m
  %ss2 = builtin.unrealized_conversion_cast %mm2 : !m to !s
  %ni1 = arith.index_cast %n1 : i64 to index
  %ni2 = arith.index_cast %n2 : i64 to index
  // state: 2 undecided, 0 false, 1 true
  %w:2 = scf.while (%i = %zi, %state = %c2) : (index, i64) -> (index, i64) {
    %in2 = arith.cmpi ult, %i, %ni2 : index
    %in1 = arith.cmpi ult, %i, %ni1 : index
    %und = arith.cmpi eq, %state, %c2 : i64
    %go1 = arith.andi %in2, %in1 : i1
    %go = arith.andi %go1, %und : i1
    scf.condition(%go) %i, %state : index, i64
  } do {
  ^bb0(%i: index, %state: i64):
    %a = trikeshed.at %ss1[%i] : !s, index -> i64
    %b = trikeshed.at %ss2[%i] : !s, index -> i64
    %ap = llvm.inttoptr %a : i64 to !llvm.ptr
    %bp = llvm.inttoptr %b : i64 to !llvm.ptr
    %e = func.call @nixev_ts_eq(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %neq = arith.cmpi eq, %e, %c0 : i64
    %state2 = scf.if %neq -> (i64) {
      %l = func.call @nixev_ts_lt(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %l : i64
    } else {
      scf.yield %c2 : i64
    }
    %i2 = arith.addi %i, %oi : index
    scf.yield %i2, %state2 : index, i64
  }
  %und = arith.cmpi eq, %w#1, %c2 : i64
  %r = scf.if %und -> (i64) {
    %at2 = arith.cmpi eq, %w#0, %ni2 : index
    %r2 = scf.if %at2 -> (i64) {
      scf.yield %c0 : i64
    } else {
      scf.yield %c1 : i64
    }
    scf.yield %r2 : i64
  } else {
    scf.yield %w#1 : i64
  }
  return %r : i64
}

// lessThan: force both, the float/int cross-comparison, a type mismatch throws, then the type dispatch; lists walk
// element-wise (eqValues then lessThan on the first unequal pair), the other types are incomparable
func.func @nixev_ts_lt(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %cm1 = arith.constant -1 : i64
  %c0_32 = arith.constant 0 : i32
  %c5 = arith.constant 5 : i8
  %c6 = arith.constant 6 : i8
  %c9 = arith.constant 9 : i8
  %c10 = arith.constant 10 : i8
  %c12 = arith.constant 12 : i8
  func.call @nixev_cmp_force(%st, %v1, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @nixev_cmp_force(%st, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %t1p = llvm.getelementptr %v1[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %t1 = llvm.load %t1p : !llvm.ptr -> i8
  %t2p = llvm.getelementptr %v2[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %t2 = llvm.load %t2p : !llvm.ptr -> i8
  %isfi = arith.cmpi eq, %t1, %c6 : i8
  %isif = arith.cmpi eq, %t2, %c5 : i8
  %cross1 = arith.andi %isfi, %isif : i1
  %r1 = scf.if %cross1 -> (i64) {
    %fp = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %f1 = llvm.load %fp : !llvm.ptr -> f64
    %ip = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %i = llvm.load %ip : !llvm.ptr -> i64
    %f2 = arith.sitofp %i : i64 to f64
    %e = arith.cmpf olt, %f1, %f2 : f64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %cm1 : i64
  }
  %u1 = arith.cmpi eq, %r1, %cm1 : i64
  %isif2 = arith.cmpi eq, %t1, %c5 : i8
  %isfi2 = arith.cmpi eq, %t2, %c6 : i8
  %cross2 = arith.andi %isif2, %isfi2 : i1
  %g2 = arith.andi %u1, %cross2 : i1
  %r2 = scf.if %g2 -> (i64) {
    %ip = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %i = llvm.load %ip : !llvm.ptr -> i64
    %f1 = arith.sitofp %i : i64 to f64
    %fp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %f2 = llvm.load %fp : !llvm.ptr -> f64
    %e = arith.cmpf olt, %f1, %f2 : f64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %r1 : i64
  }
  %u2 = arith.cmpi eq, %r2, %cm1 : i64
  %typediff = arith.cmpi ne, %t1, %t2 : i8
  %gm = arith.andi %u2, %typediff : i1
  %rm = scf.if %gm -> (i64) {
    func.call @nixev_cmp_eq_throw(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    scf.yield %c0 : i64
  } else {
    scf.yield %r2 : i64
  }
  %u3 = arith.cmpi eq, %rm, %cm1 : i64
  %is5 = arith.cmpi eq, %t1, %c5 : i8
  %g5 = arith.andi %u3, %is5 : i1
  %d5 = scf.if %g5 -> (i64) {
    %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %ap : !llvm.ptr -> i64
    %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> i64
    %e = arith.cmpi slt, %a, %b : i64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %rm : i64
  }
  %ud5 = arith.cmpi eq, %d5, %cm1 : i64
  %is6 = arith.cmpi eq, %t1, %c6 : i8
  %g6 = arith.andi %ud5, %is6 : i1
  %d6 = scf.if %g6 -> (i64) {
    %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %ap : !llvm.ptr -> f64
    %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> f64
    %e = arith.cmpf olt, %a, %b : f64
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %d5 : i64
  }
  %ud6 = arith.cmpi eq, %d6, %cm1 : i64
  %is9 = arith.cmpi eq, %t1, %c9 : i8
  %is10 = arith.cmpi eq, %t1, %c10 : i8
  %sor = arith.ori %is9, %is10 : i1
  %g9 = arith.andi %ud6, %sor : i1
  %d9 = scf.if %g9 -> (i64) {
    %p1 = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %s1 = llvm.load %p1 : !llvm.ptr -> !llvm.ptr
    %l1p = llvm.getelementptr %v1[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %l1_32 = llvm.load %l1p : !llvm.ptr -> i32
    %l1 = llvm.zext %l1_32 : i32 to i64
    %p2 = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %s2 = llvm.load %p2 : !llvm.ptr -> !llvm.ptr
    %l2p = llvm.getelementptr %v2[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %l2_32 = llvm.load %l2p : !llvm.ptr -> i32
    %l2 = llvm.zext %l2_32 : i32 to i64
    %c = func.call @ceq_bytes_cmp(%s1, %l1, %s2, %l2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    %e = arith.cmpi slt, %c, %c0_32 : i32
    %x = arith.extui %e : i1 to i64
    scf.yield %x : i64
  } else {
    scf.yield %d6 : i64
  }
  %ud9 = arith.cmpi eq, %d9, %cm1 : i64
  %is12 = arith.cmpi eq, %t1, %c12 : i8
  %g12 = arith.andi %ud9, %is12 : i1
  %d12 = scf.if %g12 -> (i64) {
    %e = func.call @ceq_list_lt(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %e : i64
  } else {
    scf.yield %d9 : i64
  }
  %ud12 = arith.cmpi eq, %d12, %cm1 : i64
  %dflt = scf.if %ud12 -> (i64) {
    func.call @nixev_cmp_lt_inc(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    scf.yield %c0 : i64
  } else {
    scf.yield %d12 : i64
  }
  %u4 = arith.cmpi eq, %dflt, %cm1 : i64
  %rf = arith.select %u4, %c0, %dflt : i64
  return %rf : i64
}
