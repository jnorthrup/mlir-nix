// __parseDrvName's dash scan hollowed from lib/Eval/Builtins.cpp into the TrikeShed dialect: the first '-' at index i
// with a following byte (i + 1 < n) that is NOT a letter splits "name-version"; the bridge keeps forceStringNoCtx (Nix's
// error wording) and the mkString/mkAttrs of the two windows.  The scan is here, in trikeshed.at over series<i8>, lowered
// by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Nix semantics, byte for byte the old body: find the FIRST i in [0, n) with s[i] == '-' && i + 1 < n &&
// !isalpha((unsigned char)s[i + 1]); return i, or -1 when there is none (name = the whole string, version empty).
// isalpha is the C locale's (the evaluator never calls setlocale; macOS inlines it to __istype(_c, _CTYPE_A), which in
// the C locale is exactly [A-Za-z]): the letter test is the two unsigned ASCII ranges, NUL and every other byte false.
//
// Nothing throws and nothing allocates: the cut is one i64.  Helper names are module-unique (convert-func-to-llvm).
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the descriptor of n i8 cells at p
func.func private @dn_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixev_ts_drvname_split(%p: !llvm.ptr, %n: i64) -> i64 {
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %cm1 = arith.constant -1 : i64
  %c0 = arith.constant 0 : i64
  %dash = arith.constant 45 : i8
  %cA = arith.constant 65 : i8
  %cZ = arith.constant 90 : i8
  %ca = arith.constant 97 : i8
  %cz = arith.constant 122 : i8
  %true = arith.constant true
  %false = arith.constant false
  %d = func.call @dn_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %i, %found = scf.while (%i = %zi, %f = %cm1) : (index, i64) -> (index, i64) {
    %in = arith.cmpi ult, %i, %ni : index
    %notfound = arith.cmpi slt, %f, %c0 : i64
    %go = arith.andi %in, %notfound : i1
    scf.condition(%go) %i, %f : index, i64
  } do {
  ^bb0(%i: index, %f: i64):
    %ch = trikeshed.at %ss[%i] : !s, index -> i8
    %isdash = arith.cmpi eq, %ch, %dash : i8
    %i1 = arith.addi %i, %oi : index
    %hasnext = arith.cmpi ult, %i1, %ni : index
    %hit = scf.if %hasnext -> (i1) {
      %nch = trikeshed.at %ss[%i1] : !s, index -> i8
      %geA = arith.cmpi uge, %nch, %cA : i8
      %leZ = arith.cmpi ule, %nch, %cZ : i8
      %upper = arith.andi %geA, %leZ : i1
      %gea = arith.cmpi uge, %nch, %ca : i8
      %lez = arith.cmpi ule, %nch, %cz : i8
      %lower = arith.andi %gea, %lez : i1
      %isal = arith.ori %upper, %lower : i1
      %notal = arith.xori %isal, %true : i1
      %h = arith.andi %isdash, %notal : i1
      scf.yield %h : i1
    } else {
      scf.yield %false : i1
    }
    %i64 = arith.index_cast %i : index to i64
    %nf = arith.select %hit, %i64, %f : i64
    %i2 = arith.addi %i, %oi : index
    scf.yield %i2, %nf : index, i64
  }
  return %found : i64
}
