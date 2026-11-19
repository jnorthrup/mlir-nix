// The pure path string algebra of nixstore::baseNameOf / dirOf (lib/Store/StorePaths.cpp) hollowed into the TrikeShed
// dialect.  StorePaths.cpp keeps only the bridges that size the composite::Text and adopt the drained bytes; the slash
// algebra is here, in trikeshed.at / slice / text / drain over series<i8>, lowered by --trikeshed-lower-cursors and the
// stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Nix semantics, byte for byte the old C++:
//   baseNameOf: strip ONE trailing slash (unless the path is just "/"), then the bytes after the last slash before it.
//   dirOf: up to the last slash; "/" when that slash is the first byte; "." when there is no slash.
//
// Each entry drains into room the caller reserved (the Encoders.mlir way) and returns the byte count.  Nothing throws:
// the path algebra is pure.  A descriptor is built inline as a struct (returning it allocates nothing and clones
// nothing) and cast to the strided memref at the use site.  canonPath lives in lowered/nixfe/CanonPath.mlir (NixFrontend
// owns it; mlnix-parse links NixFrontend alone) and the primops' bounds scans in lowered/nixeval/PathBounds.mlir.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @path_slash_g : memref<1xi8> = dense<47>
memref.global "private" constant @path_dot_g : memref<1xi8> = dense<46>

// the descriptor of n i8 cells at p
func.func private @path_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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
func.func private @path_rfind(%ss: !s, %hi: index) -> i64 {
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

// drain the one-byte constant '/' at out + k
func.func private @path_put_slash(%out: !llvm.ptr, %k: i64) {
  %g = memref.get_global @path_slash_g : memref<1xi8>
  %t = trikeshed.text %g : memref<1xi8> -> !s
  %p = llvm.getelementptr %out[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %c1 = arith.constant 1 : i64
  %d = func.call @path_desc8(%p, %c1) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %e = trikeshed.drain %t, %mm : !s, !m -> index
  return
}

// nixstore::baseNameOf: the last component, one trailing slash stripped (a lone "/" keeps its slash and gives "").
func.func @nixstore_ts_basename(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %empty = arith.cmpi eq, %n, %c0 : i64
  %r = scf.if %empty -> i64 {
    scf.yield %c0 : i64
  } else {
    %d = func.call @path_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
    %mm = builtin.unrealized_conversion_cast %d : !d to !m
    %ss = builtin.unrealized_conversion_cast %mm : !m to !s
    %ni = arith.index_cast %n : i64 to index
    %c1i = arith.constant 1 : index
    %nm1 = arith.subi %ni, %c1i : index
    %lastch = trikeshed.at %ss[%nm1] : !s, index -> i8
    %c47 = arith.constant 47 : i8
    %isslash = arith.cmpi eq, %lastch, %c47 : i8
    %c1 = arith.constant 1 : i64
    %gt1b = arith.cmpi ugt, %n, %c1 : i64
    %strip = arith.andi %isslash, %gt1b : i1
    %lasti = scf.if %strip -> index {
      scf.yield %nm1 : index
    } else {
      scf.yield %ni : index
    }
    %pos = func.call @path_rfind(%ss, %lasti) : (!s, index) -> i64
    %has = arith.cmpi sge, %pos, %c0 : i64
    %pos1 = arith.addi %pos, %c1 : i64
    %from = arith.select %has, %pos1, %c0 : i64
    %last64 = arith.index_cast %lasti : index to i64
    %len = arith.subi %last64, %from : i64
    %fromi = arith.index_cast %from : i64 to index
    %leni = arith.index_cast %len : i64 to index
    %sl = trikeshed.slice %ss[%fromi, %leni] : !s -> !s
    %od = func.call @path_desc8(%out, %len) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m
    %e = trikeshed.drain %sl, %om : !s, !m -> index
    scf.yield %len : i64
  }
  return %r : i64
}

// nixstore::dirOf: the parent — up to the last slash, "/" when it is the first byte, "." when there is none.
func.func @nixstore_ts_dirname(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @path_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %pos = func.call @path_rfind(%ss, %ni) : (!s, index) -> i64
  %c0 = arith.constant 0 : i64
  %zi = arith.constant 0 : index
  %c1 = arith.constant 1 : i64
  %none = arith.cmpi slt, %pos, %c0 : i64
  %r = scf.if %none -> i64 {
    %g = memref.get_global @path_dot_g : memref<1xi8>
    %t = trikeshed.text %g : memref<1xi8> -> !s
    %od = func.call @path_desc8(%out, %c1) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m
    %e = trikeshed.drain %t, %om : !s, !m -> index
    scf.yield %c1 : i64
  } else {
    %root = arith.cmpi eq, %pos, %c0 : i64
    %r2 = scf.if %root -> i64 {
      func.call @path_put_slash(%out, %c0) : (!llvm.ptr, i64) -> ()
      scf.yield %c1 : i64
    } else {
      %posi = arith.index_cast %pos : i64 to index
      %sl = trikeshed.slice %ss[%zi, %posi] : !s -> !s
      %od = func.call @path_desc8(%out, %pos) : (!llvm.ptr, i64) -> !d
      %om = builtin.unrealized_conversion_cast %od : !d to !m
      %e = trikeshed.drain %sl, %om : !s, !m -> index
      scf.yield %pos : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}
