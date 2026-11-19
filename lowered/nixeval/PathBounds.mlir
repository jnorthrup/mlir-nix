// The baseNameOf / dirOf primops' slash scans (lib/Eval/Builtins.cpp) hollowed into the TrikeShed dialect.  Builtins.cpp
// keeps only the forcing/coercion of the operand (Nix's error order and wording, the string contexts) and shares the
// coerced window at the bounds these entries return; the scans are here, in trikeshed.at / slice over series<i8>,
// lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Nix semantics, byte for byte the old primop bodies:
//   baseNameOf's bounds: last is the last INDEX; strip a trailing slash at last > 0, then the last slash at or before
//   last; the component is [slash + 1, last + 1), or [0, last + 1) with no slash.  Empty: [0, 0).
//   dirOf's scan: the last slash's index, -1 when there is none (the bridge shares [0, slash), or [0, 1) at 0, or ".").
//
// Nothing throws and nothing allocates: the bounds are a struct of two i64 (the TsBounds of StringOps.mlir's substring).
// Helper names are module-unique: convert-func-to-llvm makes them global.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!bnds = !llvm.struct<(i64, i64)>

// the descriptor of n i8 cells at p
func.func private @pb_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// the last index below hi whose byte is '/', else -1 (std::string_view::rfind('/', hi - 1))
func.func private @pb_rfind(%ss: !s, %hi: index) -> i64 {
  %cm1 = arith.constant -1 : i64
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c47 = arith.constant 47 : i8
  %r = scf.for %i = %zi to %hi step %oi iter_args(%found = %cm1) -> i64 {
    %ch = trikeshed.at %ss[%i] : !s, index -> i8
    %hit = arith.cmpi eq, %ch, %c47 : i8
    %i64 = arith.index_cast %i : index to i64
    %next = arith.select %hit, %i64, %found : i64
    scf.yield %next : i64
  }
  return %r : i64
}

// the baseNameOf primop's zero-copy bounds: {from, to} of the coerced window.
func.func @nixev_ts_basename_bounds(%p: !llvm.ptr, %n: i64) -> !bnds {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %zi = arith.constant 0 : index
  %empty = arith.cmpi eq, %n, %c0 : i64
  %r = scf.if %empty -> !bnds {
    %u = llvm.mlir.undef : !bnds
    %a = llvm.insertvalue %c0, %u[0] : !bnds
    %b = llvm.insertvalue %c0, %a[1] : !bnds
    scf.yield %b : !bnds
  } else {
    %d = func.call @pb_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
    %mm = builtin.unrealized_conversion_cast %d : !d to !m
    %ss = builtin.unrealized_conversion_cast %mm : !m to !s
    %ni = arith.index_cast %n : i64 to index
    %c1i = arith.constant 1 : index
    %last0 = arith.subi %ni, %c1i : index
    %lastch = trikeshed.at %ss[%last0] : !s, index -> i8
    %c47 = arith.constant 47 : i8
    %isslash = arith.cmpi eq, %lastch, %c47 : i8
    %gt0b = arith.cmpi ugt, %last0, %zi : index
    %strip = arith.andi %isslash, %gt0b : i1
    %lasti = scf.if %strip -> index {
      %lm1 = arith.subi %last0, %c1i : index
      scf.yield %lm1 : index
    } else {
      scf.yield %last0 : index
    }
    %hi = arith.addi %lasti, %c1i : index
    %slash = func.call @pb_rfind(%ss, %hi) : (!s, index) -> i64
    %has = arith.cmpi sge, %slash, %c0 : i64
    %slash1 = arith.addi %slash, %c1 : i64
    %from = arith.select %has, %slash1, %c0 : i64
    %last64 = arith.index_cast %lasti : index to i64
    %to = arith.addi %last64, %c1 : i64
    %u = llvm.mlir.undef : !bnds
    %a = llvm.insertvalue %from, %u[0] : !bnds
    %b = llvm.insertvalue %to, %a[1] : !bnds
    scf.yield %b : !bnds
  }
  return %r : !bnds
}

// the dirOf primop's scan: the last slash's index, -1 when there is none.
func.func @nixev_ts_dirname_slash(%p: !llvm.ptr, %n: i64) -> i64 {
  %d = func.call @pb_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %pos = func.call @pb_rfind(%ss, %ni) : (!s, index) -> i64
  return %pos : i64
}
