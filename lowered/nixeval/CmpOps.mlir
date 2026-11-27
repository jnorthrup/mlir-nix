// EvalState::eqValues and EvalState::lessThan hollowed into the TrikeShed dialect.  lib/Eval/Eval.cpp keeps only thin
// bridges (the methods forward here) and the callbacks: forcing (nixev_cmp_force, the inline forceValue check), the
// outPath attribute lookup (nixev_attr_get) and isDerivation (called by its mangled name, still C++: it forces the type
// attribute).  The type dispatch, the int/float cross-comparison, the scalar comparisons, the list and attribute walks and
// the recursion are here: a list's cells (Value**) are a series<i64> of pointer bits (the descriptor built inline, as
// ListOps.mlir does), a string or path is a series<i8> compared unsigned (trikeshed.compare: the first difference, then
// the shorter one is less — std::string_view's order).  The walks short-circuit (scf.while, as ListOps2.mlir's
// any/all/elem): a later element is never forced once the answer is known.
//
// The result is an Either (Either.kt, trikeshed.either): Right(value) is the answer (eqValues 0 or 1; lessThan 0 or 1,
// and -1 while a chain is undecided, never returned), Left(err) is a comparison that cannot be made: err's code (0 "cannot
// compare X with Y", 1 "...; values of that type are incomparable") and the two values the message names.  A Left is
// carried up by the walks, which stop at it: a Left is not undecided, so every test above it passes it on, and a walk
// tests it before it goes on.  The C entries nixev_ts_eq / nixev_ts_lt return a Left as kCmpLeft (-2) with err written
// to their last argument: the bridge throws Nix's message once, with the two values' types.  The recursion is func.call
// back into the internal entries (ceq_eq, ceq_lt).  Forcing still throws: a C++ exception unwinds through the compiled
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
// the Left: the code, then the two values it names
!err = !llvm.struct<(i64, ptr, ptr)>
// a walk's result: Left(err) or Right(value)
!ev = !trikeshed.either<!err, i64>

// forcing (the inline forceValue: the thunk test and the stats census stay in C++; a forced thunk's error throws through)
func.func private @nixev_cmp_force(!llvm.ptr, !llvm.ptr, !llvm.ptr)
// the outPath attribute of a set (which 0), or its __toString (which 1): the Attr, or null
func.func private @nixev_attr_get(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(!llvm.ptr, !llvm.ptr) -> i8

// Right(x)
func.func private @ceq_right(%x: i64) -> !ev {
  %f = arith.constant false
  %u = llvm.mlir.undef : !err
  %e = builtin.unrealized_conversion_cast %f, %u, %x : i1, !err, i64 to !ev
  return %e : !ev
}

// Left(code, a, b)
func.func private @ceq_left(%code: i64, %a: !llvm.ptr, %b: !llvm.ptr) -> !ev {
  %t = arith.constant true
  %z = arith.constant 0 : i64
  %u = llvm.mlir.undef : !err
  %s1 = llvm.insertvalue %code, %u[0] : !err
  %s2 = llvm.insertvalue %a, %s1[1] : !err
  %s3 = llvm.insertvalue %b, %s2[2] : !err
  %e = builtin.unrealized_conversion_cast %t, %s3, %z : i1, !err, i64 to !ev
  return %e : !ev
}

// e is Right(v)
func.func private @ceq_is(%e: !ev, %v: i64) -> i1 {
  %r = trikeshed.eitherFold %e : !ev -> i1 {
  ^bb0(%lerr: !err):
    %no = arith.constant false
    trikeshed.yield %no : i1
  }, {
  ^bb0(%rval: i64):
    %same = arith.cmpi eq, %rval, %v : i64
    trikeshed.yield %same : i1
  }
  return %r : i1
}

// e is Left
func.func private @ceq_is_left(%e: !ev) -> i1 {
  %r = trikeshed.eitherFold %e : !ev -> i1 {
  ^bb0(%lerr: !err):
    %yes = arith.constant true
    trikeshed.yield %yes : i1
  }, {
  ^bb0(%rval: i64):
    %no = arith.constant false
    trikeshed.yield %no : i1
  }
  return %r : i1
}

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

// the list walk (eqValues): the sizes must match, then each pair of cells (one value, equal without a look, when the
// pointers match); the first unequal pair decides, a later element is never forced.  The walk goes on while it is
// Right(1), so a Left ends it.
func.func private @ceq_list_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> !ev {
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
  %r = scf.if %sizediff -> (!ev) {
    %z = func.call @ceq_right(%c0) : (i64) -> !ev
    scf.yield %z : !ev
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
    %start = func.call @ceq_right(%c1) : (i64) -> !ev
    %w:2 = scf.while (%i = %zi, %acc = %start) : (index, !ev) -> (index, !ev) {
      %inside = arith.cmpi ult, %i, %ni : index
      %still = func.call @ceq_is(%acc, %c1) : (!ev, i64) -> i1
      %go = arith.andi %inside, %still : i1
      scf.condition(%go) %i, %acc : index, !ev
    } do {
    ^bb0(%wi: index, %wacc: !ev):
      %a = trikeshed.at %ss1[%wi] : !s, index -> i64
      %b = trikeshed.at %ss2[%wi] : !s, index -> i64
      %same = arith.cmpi eq, %a, %b : i64
      %acc2 = scf.if %same -> (!ev) {
        scf.yield %wacc : !ev
      } else {
        %ap = llvm.inttoptr %a : i64 to !llvm.ptr
        %bp = llvm.inttoptr %b : i64 to !llvm.ptr
        %e = func.call @ceq_eq(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
        scf.yield %e : !ev
      }
      %wi2 = arith.addi %wi, %oi : index
      scf.yield %wi2, %acc2 : index, !ev
    }
    scf.yield %w#1 : !ev
  }
  return %r : !ev
}

// the attribute walk (eqValues): one set (the same Bindings) is equal without a look; two derivations compare by their
// outPath cells when both have one (isDerivation forces each type attribute, v1 first, as the C++ && did); else the sizes
// must match and the rows walk in symbol order: a different name decides, a shared value cell is equal without a look.
// The record reads are trikeshed.at over word views: a Value is 3 words (word 1 is its union: the Bindings pointer), a
// Bindings is 2 header words then 2 words per row (word 2+2k: the name in the low 32 bits; word 3+2k: the value), an
// Attr is 2 words (its name and position, then its value pointer).  The walk itself stays an scf.while: a later
// element is never forced once the answer is known.
func.func private @ceq_attr_value(%p: !llvm.ptr) -> i64 {
  %c2 = arith.constant 2 : i64
  %oi = arith.constant 1 : index
  %d = func.call @ceq_desc(%p, %c2) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m
  %s = builtin.unrealized_conversion_cast %m : !m to !s
  %x = trikeshed.at %s[%oi] : !s, index -> i64
  return %x : i64
}

func.func private @ceq_attrs_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> !ev {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %cm1 = arith.constant -1 : i64
  %c0_8 = arith.constant 0 : i8
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %vd1 = func.call @ceq_desc(%v1, %c3) : (!llvm.ptr, i64) -> !d
  %vm1 = builtin.unrealized_conversion_cast %vd1 : !d to !m
  %vs1 = builtin.unrealized_conversion_cast %vm1 : !m to !s
  %vd2 = func.call @ceq_desc(%v2, %c3) : (!llvm.ptr, i64) -> !d
  %vm2 = builtin.unrealized_conversion_cast %vd2 : !d to !m
  %vs2 = builtin.unrealized_conversion_cast %vm2 : !m to !s
  %b1 = trikeshed.at %vs1[%oi] : !s, index -> i64
  %b2 = trikeshed.at %vs2[%oi] : !s, index -> i64
  %sameb = arith.cmpi eq, %b1, %b2 : i64
  %r_same = scf.if %sameb -> (i64) {
    scf.yield %c1 : i64
  } else {
    scf.yield %cm1 : i64
  }
  %und1 = arith.cmpi eq, %r_same, %cm1 : i64
  %r_drv = scf.if %und1 -> (!ev) {
    %d1 = func.call @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(%st, %v1) : (!llvm.ptr, !llvm.ptr) -> i8
    %d1n = arith.cmpi ne, %d1, %c0_8 : i8
    %r_d1 = scf.if %d1n -> (!ev) {
      %d2 = func.call @_ZN5nixev9EvalState12isDerivationERNS_5ValueE(%st, %v2) : (!llvm.ptr, !llvm.ptr) -> i8
      %d2n = arith.cmpi ne, %d2, %c0_8 : i8
      %r_d2 = scf.if %d2n -> (!ev) {
        %i = func.call @nixev_attr_get(%st, %v1, %c0) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
        %j = func.call @nixev_attr_get(%st, %v2, %c0) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
        %ii = llvm.ptrtoint %i : !llvm.ptr to i64
        %ji = llvm.ptrtoint %j : !llvm.ptr to i64
        %inz = arith.cmpi ne, %ii, %c0 : i64
        %jnz = arith.cmpi ne, %ji, %c0 : i64
        %both = arith.andi %inz, %jnz : i1
        %r_both = scf.if %both -> (!ev) {
          %iv = func.call @ceq_attr_value(%i) : (!llvm.ptr) -> i64
          %jv = func.call @ceq_attr_value(%j) : (!llvm.ptr) -> i64
          %peq = arith.cmpi eq, %iv, %jv : i64
          %r_pe = scf.if %peq -> (!ev) {
            %one = func.call @ceq_right(%c1) : (i64) -> !ev
            scf.yield %one : !ev
          } else {
            %ivp = llvm.inttoptr %iv : i64 to !llvm.ptr
            %jvp = llvm.inttoptr %jv : i64 to !llvm.ptr
            %e = func.call @ceq_eq(%st, %ivp, %jvp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
            scf.yield %e : !ev
          }
          scf.yield %r_pe : !ev
        } else {
          %m1 = func.call @ceq_right(%cm1) : (i64) -> !ev
          scf.yield %m1 : !ev
        }
        scf.yield %r_both : !ev
      } else {
        %m1 = func.call @ceq_right(%cm1) : (i64) -> !ev
        scf.yield %m1 : !ev
      }
      scf.yield %r_d2 : !ev
    } else {
      %m1 = func.call @ceq_right(%cm1) : (i64) -> !ev
      scf.yield %m1 : !ev
    }
    scf.yield %r_d1 : !ev
  } else {
    %same = func.call @ceq_right(%r_same) : (i64) -> !ev
    scf.yield %same : !ev
  }
  %und2 = func.call @ceq_is(%r_drv, %cm1) : (!ev, i64) -> i1
  %r = scf.if %und2 -> (!ev) {
    %bp1 = llvm.inttoptr %b1 : i64 to !llvm.ptr
    %bp2 = llvm.inttoptr %b2 : i64 to !llvm.ptr
    // the header: the size is the low 32 bits of word 0
    %hd1 = func.call @ceq_desc(%bp1, %c2) : (!llvm.ptr, i64) -> !d
    %hm1 = builtin.unrealized_conversion_cast %hd1 : !d to !m
    %hs1 = builtin.unrealized_conversion_cast %hm1 : !m to !s
    %hd2 = func.call @ceq_desc(%bp2, %c2) : (!llvm.ptr, i64) -> !d
    %hm2 = builtin.unrealized_conversion_cast %hd2 : !d to !m
    %hs2 = builtin.unrealized_conversion_cast %hm2 : !m to !s
    %h1 = trikeshed.at %hs1[%zi] : !s, index -> i64
    %h2 = trikeshed.at %hs2[%zi] : !s, index -> i64
    %s1 = arith.trunci %h1 : i64 to i32
    %s2 = arith.trunci %h2 : i64 to i32
    %sizediff = arith.cmpi ne, %s1, %s2 : i32
    %r_sz = scf.if %sizediff -> (!ev) {
      %z = func.call @ceq_right(%c0) : (i64) -> !ev
      scf.yield %z : !ev
    } else {
      %n = arith.extui %s1 : i32 to i64
      %ni = arith.index_cast %n : i64 to index
      // the words: 2 header words, then 2 per row
      %n2 = arith.muli %n, %c2 : i64
      %nw = arith.addi %n2, %c2 : i64
      %rd1 = func.call @ceq_desc(%bp1, %nw) : (!llvm.ptr, i64) -> !d
      %rm1 = builtin.unrealized_conversion_cast %rd1 : !d to !m
      %rs1 = builtin.unrealized_conversion_cast %rm1 : !m to !s
      %rd2 = func.call @ceq_desc(%bp2, %nw) : (!llvm.ptr, i64) -> !d
      %rm2 = builtin.unrealized_conversion_cast %rd2 : !d to !m
      %rs2 = builtin.unrealized_conversion_cast %rm2 : !m to !s
      %start = func.call @ceq_right(%c1) : (i64) -> !ev
      %w:2 = scf.while (%k = %zi, %acc = %start) : (index, !ev) -> (index, !ev) {
        %inside = arith.cmpi ult, %k, %ni : index
        %still = func.call @ceq_is(%acc, %c1) : (!ev, i64) -> i1
        %go = arith.andi %inside, %still : i1
        scf.condition(%go) %k, %acc : index, !ev
      } do {
      ^bb0(%wk: index, %wacc: !ev):
        %two = arith.constant 2 : index
        %rk = arith.muli %wk, %two : index
        %nidx = arith.addi %rk, %two : index
        %vidx = arith.addi %nidx, %oi : index
        %na64 = trikeshed.at %rs1[%nidx] : !s, index -> i64
        %nb64 = trikeshed.at %rs2[%nidx] : !s, index -> i64
        %na = arith.trunci %na64 : i64 to i32
        %nb = arith.trunci %nb64 : i64 to i32
        %namesame = arith.cmpi eq, %na, %nb : i32
        %acc2 = scf.if %namesame -> (!ev) {
          %av = trikeshed.at %rs1[%vidx] : !s, index -> i64
          %bv = trikeshed.at %rs2[%vidx] : !s, index -> i64
          %peq = arith.cmpi eq, %av, %bv : i64
          %acc3 = scf.if %peq -> (!ev) {
            scf.yield %wacc : !ev
          } else {
            %avp = llvm.inttoptr %av : i64 to !llvm.ptr
            %bvp = llvm.inttoptr %bv : i64 to !llvm.ptr
            %e = func.call @ceq_eq(%st, %avp, %bvp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
            scf.yield %e : !ev
          }
          scf.yield %acc3 : !ev
        } else {
          %zero = func.call @ceq_right(%c0) : (i64) -> !ev
          scf.yield %zero : !ev
        }
        %k2 = arith.addi %wk, %oi : index
        scf.yield %k2, %acc2 : index, !ev
      }
      scf.yield %w#1 : !ev
    }
    scf.yield %r_sz : !ev
  } else {
    scf.yield %r_drv : !ev
  }
  return %r : !ev
}

// eqValues: force both, the int/float cross-comparison, the function types normalized (PrimOp/PrimOpApp as Lambda),
// then the type dispatch; the walks recurse into this entry.  The scalar chain is Right(-1) while undecided.
func.func private @ceq_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> !ev {
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
  %r3 = scf.if %g3 -> (!ev) {
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
    // from here the walks can fail: the chain is Either, and a Left is passed on (no test below takes it as undecided)
    %e9 = func.call @ceq_right(%d9) : (i64) -> !ev
    %is12 = arith.cmpi eq, %t1, %c12 : i8
    %ud9 = arith.cmpi eq, %d9, %cm1 : i64
    %g12 = arith.andi %ud9, %is12 : i1
    %d12 = scf.if %g12 -> (!ev) {
      %e = func.call @ceq_list_eq(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
      scf.yield %e : !ev
    } else {
      scf.yield %e9 : !ev
    }
    %ud12 = func.call @ceq_is(%d12, %cm1) : (!ev, i64) -> i1
    %is11 = arith.cmpi eq, %t1, %c11 : i8
    %g11 = arith.andi %ud12, %is11 : i1
    %d11 = scf.if %g11 -> (!ev) {
      %e = func.call @ceq_attrs_eq(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
      scf.yield %e : !ev
    } else {
      scf.yield %d12 : !ev
    }
    %ud11 = func.call @ceq_is(%d11, %cm1) : (!ev, i64) -> i1
    %is13 = arith.cmpi eq, %t1, %c13 : i8
    %is14 = arith.cmpi eq, %t1, %c14 : i8
    %is15 = arith.cmpi eq, %t1, %c15 : i8
    %f1 = arith.ori %is13, %is14 : i1
    %f2 = arith.ori %f1, %is15 : i1
    %g13 = arith.andi %ud11, %f2 : i1
    %d13 = scf.if %g13 -> (!ev) {
      %z = func.call @ceq_right(%c0) : (i64) -> !ev
      scf.yield %z : !ev
    } else {
      scf.yield %d11 : !ev
    }
    %ud13 = func.call @ceq_is(%d13, %cm1) : (!ev, i64) -> i1
    %dflt = scf.if %ud13 -> (!ev) {
      %lft = func.call @ceq_left(%c0, %v1, %v2) : (i64, !llvm.ptr, !llvm.ptr) -> !ev
      scf.yield %lft : !ev
    } else {
      scf.yield %d13 : !ev
    }
    scf.yield %dflt : !ev
  } else {
    // the cross-comparison already decided, or the normalized types differ (unequal)
    %decided = arith.cmpi ne, %r2, %cm1 : i64
    %relse = arith.select %decided, %r2, %c0 : i64
    %rr = func.call @ceq_right(%relse) : (i64) -> !ev
    scf.yield %rr : !ev
  }
  %u3 = func.call @ceq_is(%r3, %cm1) : (!ev, i64) -> i1
  %rf = scf.if %u3 -> (!ev) {
    %z = func.call @ceq_right(%c0) : (i64) -> !ev
    scf.yield %z : !ev
  } else {
    scf.yield %r3 : !ev
  }
  return %rf : !ev
}

// the list order: walk both while neither is exhausted and the elements are equal; the first unequal pair decides by
// lessThan; a list exhausted first is less (the right one exhausted first: not less).  A Left ends the walk.
func.func private @ceq_list_lt(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> !ev {
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
  // state: Right(2) undecided, Right(0) false, Right(1) true, or a Left
  %start = func.call @ceq_right(%c2) : (i64) -> !ev
  %w:2 = scf.while (%i = %zi, %state = %start) : (index, !ev) -> (index, !ev) {
    %in2 = arith.cmpi ult, %i, %ni2 : index
    %in1 = arith.cmpi ult, %i, %ni1 : index
    %und = func.call @ceq_is(%state, %c2) : (!ev, i64) -> i1
    %go1 = arith.andi %in2, %in1 : i1
    %go = arith.andi %go1, %und : i1
    scf.condition(%go) %i, %state : index, !ev
  } do {
  ^bb0(%wi: index, %wstate: !ev):
    %a = trikeshed.at %ss1[%wi] : !s, index -> i64
    %b = trikeshed.at %ss2[%wi] : !s, index -> i64
    %ap = llvm.inttoptr %a : i64 to !llvm.ptr
    %bp = llvm.inttoptr %b : i64 to !llvm.ptr
    %e = func.call @ceq_eq(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
    %yes = func.call @ceq_is(%e, %c1) : (!ev, i64) -> i1
    %state2 = scf.if %yes -> (!ev) {
      %still = func.call @ceq_right(%c2) : (i64) -> !ev
      scf.yield %still : !ev
    } else {
      %isl = func.call @ceq_is_left(%e) : (!ev) -> i1
      %s = scf.if %isl -> (!ev) {
        scf.yield %e : !ev
      } else {
        %l = func.call @ceq_lt(%st, %ap, %bp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
        scf.yield %l : !ev
      }
      scf.yield %s : !ev
    }
    %wi2 = arith.addi %wi, %oi : index
    scf.yield %wi2, %state2 : index, !ev
  }
  %und = func.call @ceq_is(%w#1, %c2) : (!ev, i64) -> i1
  %r = scf.if %und -> (!ev) {
    %at2 = arith.cmpi eq, %w#0, %ni2 : index
    %r2 = scf.if %at2 -> (!ev) {
      %zero = func.call @ceq_right(%c0) : (i64) -> !ev
      scf.yield %zero : !ev
    } else {
      %one = func.call @ceq_right(%c1) : (i64) -> !ev
      scf.yield %one : !ev
    }
    scf.yield %r2 : !ev
  } else {
    scf.yield %w#1 : !ev
  }
  return %r : !ev
}

// lessThan: force both, the float/int cross-comparison, a type mismatch is Left 0, then the type dispatch; lists walk
// element-wise (eqValues then lessThan on the first unequal pair), the other types are incomparable (Left 1)
func.func private @ceq_lt(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr) -> !ev {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
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
  %rm = scf.if %gm -> (!ev) {
    %lft = func.call @ceq_left(%c0, %v1, %v2) : (i64, !llvm.ptr, !llvm.ptr) -> !ev
    scf.yield %lft : !ev
  } else {
    %rr = func.call @ceq_right(%r2) : (i64) -> !ev
    scf.yield %rr : !ev
  }
  // from here the chain is Either: an undecided Right(-1) goes on, a Left is passed on
  %u3 = func.call @ceq_is(%rm, %cm1) : (!ev, i64) -> i1
  %is5 = arith.cmpi eq, %t1, %c5 : i8
  %g5 = arith.andi %u3, %is5 : i1
  %d5 = scf.if %g5 -> (!ev) {
    %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %ap : !llvm.ptr -> i64
    %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> i64
    %e = arith.cmpi slt, %a, %b : i64
    %x = arith.extui %e : i1 to i64
    %rr = func.call @ceq_right(%x) : (i64) -> !ev
    scf.yield %rr : !ev
  } else {
    scf.yield %rm : !ev
  }
  %ud5 = func.call @ceq_is(%d5, %cm1) : (!ev, i64) -> i1
  %is6 = arith.cmpi eq, %t1, %c6 : i8
  %g6 = arith.andi %ud5, %is6 : i1
  %d6 = scf.if %g6 -> (!ev) {
    %ap = llvm.getelementptr %v1[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %a = llvm.load %ap : !llvm.ptr -> f64
    %bp = llvm.getelementptr %v2[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> f64
    %e = arith.cmpf olt, %a, %b : f64
    %x = arith.extui %e : i1 to i64
    %rr = func.call @ceq_right(%x) : (i64) -> !ev
    scf.yield %rr : !ev
  } else {
    scf.yield %d5 : !ev
  }
  %ud6 = func.call @ceq_is(%d6, %cm1) : (!ev, i64) -> i1
  %is9 = arith.cmpi eq, %t1, %c9 : i8
  %is10 = arith.cmpi eq, %t1, %c10 : i8
  %sor = arith.ori %is9, %is10 : i1
  %g9 = arith.andi %ud6, %sor : i1
  %d9 = scf.if %g9 -> (!ev) {
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
    %rr = func.call @ceq_right(%x) : (i64) -> !ev
    scf.yield %rr : !ev
  } else {
    scf.yield %d6 : !ev
  }
  %ud9 = func.call @ceq_is(%d9, %cm1) : (!ev, i64) -> i1
  %is12 = arith.cmpi eq, %t1, %c12 : i8
  %g12 = arith.andi %ud9, %is12 : i1
  %d12 = scf.if %g12 -> (!ev) {
    %e = func.call @ceq_list_lt(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
    scf.yield %e : !ev
  } else {
    scf.yield %d9 : !ev
  }
  %ud12 = func.call @ceq_is(%d12, %cm1) : (!ev, i64) -> i1
  %dflt = scf.if %ud12 -> (!ev) {
    %inc = func.call @ceq_left(%c1, %v1, %v2) : (i64, !llvm.ptr, !llvm.ptr) -> !ev
    scf.yield %inc : !ev
  } else {
    scf.yield %d12 : !ev
  }
  %u4 = func.call @ceq_is(%dflt, %cm1) : (!ev, i64) -> i1
  %rf = scf.if %u4 -> (!ev) {
    %z = func.call @ceq_right(%c0) : (i64) -> !ev
    scf.yield %z : !ev
  } else {
    scf.yield %dflt : !ev
  }
  return %rf : !ev
}

// The C entries (lib/Eval/Eval.cpp's bridges call these): a Left is returned as -2 (kCmpLeft) with its code and values
// written to `err`, and the bridge throws Nix's message once; a Right is the answer.
func.func @nixev_ts_eq(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %r = func.call @ceq_eq(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
  %x = trikeshed.eitherFold %r : !ev -> i64 {
  ^bb0(%lerr: !err):
    llvm.store %lerr, %err : !err, !llvm.ptr
    %left = arith.constant -2 : i64
    trikeshed.yield %left : i64
  }, {
  ^bb0(%rval: i64):
    trikeshed.yield %rval : i64
  }
  return %x : i64
}

func.func @nixev_ts_lt(%st: !llvm.ptr, %v1: !llvm.ptr, %v2: !llvm.ptr, %pos: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %r = func.call @ceq_lt(%st, %v1, %v2, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !ev
  %x = trikeshed.eitherFold %r : !ev -> i64 {
  ^bb0(%lerr: !err):
    llvm.store %lerr, %err : !err, !llvm.ptr
    %left = arith.constant -2 : i64
    trikeshed.yield %left : i64
  }, {
  ^bb0(%rval: i64):
    trikeshed.yield %rval : i64
  }
  return %x : i64
}
