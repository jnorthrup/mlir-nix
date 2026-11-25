// EvalState::coerceToString hollowed into the TrikeShed dialect.  lib/Eval/Eval.cpp keeps a thin bridge (the method
// forwards here, errorCtx as raw bytes — the std::string_view never crosses the ABI) and the callbacks: forcing, the
// error wording (the TypeError with showType/printValueForTrace and the errorCtx trace), the __toString/outPath
// attribute lookup, copyPathToStore (the store glue), cp::str/fixedFloat (the number text), the Text writes, and the
// list element's recursive coercion wrapped in its try/catch addTrace ("while evaluating one element of the list").
// The type dispatch, the string/path/attrs handling, the __toString call and the outPath recursion, the coerceMore
// scalar cases and the list walk with its separator rule are here.  The recursion is func.call back into this entry
// (the __toString result with a null position and canonicalizePath true, as tryAttrsToString gave it; the outPath value
// with the caller's position and canonicalizePath); the list's elements recurse through the C++ callback, which keeps
// the exception trace and the piece Text's lifetime.  A list's cells (Value**) are a series<i64> of pointer bits, the
// descriptor built inline as ListOps.mlir does; the walk is scf.for over trikeshed.at.
//
// Value 24 bytes: VType u8@0 (Int 5, Float 6, Bool 7, Null 8, String 9, Path 10, Attrs 11, List 12), aux u32@4
// (string/path length, list size), union@8 (integer i64 / fpoint f64 / boolean u8 / str.s ptr / path.s ptr / attrs ptr /
// list.elems ptr).  composite::Text 16 bytes: char* p@0, u32 n@8, u32 cap@12 (Growable<char>); the bridge hands an
// empty Text, the entry fills it (a move of the list result's two words at the end; no destructor runs over the MLIR
// stack, so the result's buffer is the caller's).  Attr 16 bytes: name u32@0, pos u32@4, value ptr@8.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!text = !llvm.struct<(ptr, i32, i32)>

// the error contexts of the two recursions (tryAttrsToString's and the outPath attribute's)
llvm.mlir.global private constant @cst_ctx_ts(dense<[119, 104, 105, 108, 101, 32, 101, 118, 97, 108, 117, 97, 116, 105, 110, 103, 32, 116, 104, 101, 32, 114, 101, 115, 117, 108, 116, 32, 111, 102, 32, 116, 104, 101, 32, 96, 95, 95, 116, 111, 83, 116, 114, 105, 110, 103, 96, 32, 97, 116, 116, 114, 105, 98, 117, 116, 101]> : tensor<57xi8>) : !llvm.array<57 x i8>
llvm.mlir.global private constant @cst_ctx_op(dense<[119, 104, 105, 108, 101, 32, 101, 118, 97, 108, 117, 97, 116, 105, 110, 103, 32, 116, 104, 101, 32, 96, 111, 117, 116, 80, 97, 116, 104, 96, 32, 97, 116, 116, 114, 105, 98, 117, 116, 101]> : tensor<40xi8>) : !llvm.array<40 x i8>
llvm.mlir.global private constant @cst_one(dense<49> : tensor<1xi8>) : !llvm.array<1 x i8>
llvm.mlir.global private constant @cst_space(dense<32> : tensor<1xi8>) : !llvm.array<1 x i8>

// forcing (the inline forceValue check stays in C++)
func.func private @nixev_cmp_force(!llvm.ptr, !llvm.ptr, !llvm.ptr)
// the __toString attribute (which 1) or the outPath attribute (which 0): the Attr, or null
func.func private @nixev_attr_get(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
// a fresh arena cell (allocValue is inline in the header)
func.func private @nixev_cell(!llvm.ptr) -> !llvm.ptr
func.func private @_ZN5nixev9EvalState12callFunctionERNS_5ValueEmPPS1_S2_PKv(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @_ZN5nixev9EvalState11copyContextERKNS_5ValueERNS_16NixStringContextE(!llvm.ptr, !llvm.ptr, !llvm.ptr)
// the TypeError: "cannot coerce X to a string: ..." with the errorCtx trace when there is one
func.func private @nixev_coerce_throw(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
// the Text writes: a copy of bytes into the empty result, and an append
func.func private @nixev_text_set(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixev_text_put(!llvm.ptr, !llvm.ptr, i64)
// the number text (cp::str / nixfe::fixedFloat stay C++)
func.func private @nixev_int_text(!llvm.ptr, i64)
func.func private @nixev_float_text(!llvm.ptr, f64)
// copyPathToStore (the store glue stays C++)
func.func private @nixev_copy_path(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr)
// one list element: the recursive coercion (canonicalizePath true, as the C++ default argument gave it) appended to
// the result, its EvalError traced "while evaluating one element of the list" and rethrown
func.func private @nixev_coerce_elem(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr)

// the descriptor of n i64 cells at p (module-unique)
func.func private @cst_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the list coercion: each element coerced in order (the callback keeps the trace and the piece's lifetime), a space
// between two pieces unless the element just coerced is an empty list; the result Text moved into the caller's
func.func private @cst_list(%st: !llvm.ptr, %v: !llvm.ptr, %ctx: !llvm.ptr, %cm: i64, %cts: i64, %pos: !llvm.ptr, %ectx: !llvm.ptr, %ectxn: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c0_32 = arith.constant 0 : i32
  %c12 = arith.constant 12 : i8
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %true = arith.constant true
  %n32 = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n_32 = llvm.load %n32 : !llvm.ptr -> i32
  %n = llvm.zext %n_32 : i32 to i64
  %ni = arith.index_cast %n : i64 to index
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %d = func.call @cst_desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  // the result Text, empty (p null, n and cap 0)
  %txt = llvm.alloca %c1 x !text : (i64) -> !llvm.ptr
  %t0 = llvm.getelementptr %txt[0] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %c0, %t0 : i64, !llvm.ptr
  %t8 = llvm.getelementptr %txt[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %c0, %t8 : i64, !llvm.ptr
  scf.for %i = %zi to %ni step %oi {
    %eb = trikeshed.at %ss[%i] : !s, index -> i64
    %e = llvm.inttoptr %eb : i64 to !llvm.ptr
    func.call @nixev_coerce_elem(%st, %e, %ctx, %cm, %cts, %pos, %ectx, %ectxn, %txt) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    // the separator: not the last piece, and the element (now forced) not an empty list
    %nb = llvm.load %n32 : !llvm.ptr -> i32
    %nib = arith.index_cast %nb : i32 to index
    %last = arith.subi %nib, %oi : index
    %notlast = arith.cmpi ult, %i, %last : index
    %etp = llvm.getelementptr %e[0] : (!llvm.ptr) -> !llvm.ptr, i8
    %et = llvm.load %etp : !llvm.ptr -> i8
    %eap = llvm.getelementptr %e[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %ea = llvm.load %eap : !llvm.ptr -> i32
    %islist = arith.cmpi eq, %et, %c12 : i8
    %empty = arith.cmpi eq, %ea, %c0_32 : i32
    %iel = arith.andi %islist, %empty : i1
    %notiel = arith.xori %iel, %true : i1
    %sep = arith.andi %notlast, %notiel : i1
    scf.if %sep {
      %sp = llvm.mlir.addressof @cst_space : !llvm.ptr
      func.call @nixev_text_put(%txt, %sp, %c1) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  // move the result into the caller's Text (the two words; the stack Text runs no destructor)
  %w0 = llvm.load %t0 : !llvm.ptr -> i64
  %w1 = llvm.load %t8 : !llvm.ptr -> i64
  %o0 = llvm.getelementptr %out[0] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %w0, %o0 : i64, !llvm.ptr
  %o8 = llvm.getelementptr %out[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %w1, %o8 : i64, !llvm.ptr
  return
}

// coerceToString: force, then the type dispatch.  A string copies its bytes (its context merged into ctx); a path is
// copied to the store when asked, else its bytes; a set is its __toString result (called with the set as the argument)
// or its outPath value coerced, else the TypeError.  With coerceMore: true is "1", false/null "", an int its digits, a
// float its fixed text, a list its elements' coercions joined by spaces (the empty-list rule).  Anything else throws.
func.func @nixev_ts_coerce(%st: !llvm.ptr, %v: !llvm.ptr, %ctx: !llvm.ptr, %cm: i64, %cts: i64, %pos: !llvm.ptr, %canon: i64, %ectx: !llvm.ptr, %ectxn: i64, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c0_8 = arith.constant 0 : i8
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i8
  %c6 = arith.constant 6 : i8
  %c7 = arith.constant 7 : i8
  %c8 = arith.constant 8 : i8
  %c9 = arith.constant 9 : i8
  %c10 = arith.constant 10 : i8
  %c11 = arith.constant 11 : i8
  %c12 = arith.constant 12 : i8
  %c57 = arith.constant 57 : i64
  %c40 = arith.constant 40 : i64
  func.call @nixev_cmp_force(%st, %v, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %t = llvm.load %tp : !llvm.ptr -> i8
  // String: the context merged, the bytes copied
  %isstr = arith.cmpi eq, %t, %c9 : i8
  %h1 = scf.if %isstr -> (i64) {
    func.call @_ZN5nixev9EvalState11copyContextERKNS_5ValueERNS_16NixStringContextE(%st, %v, %ctx) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %sp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %s = llvm.load %sp : !llvm.ptr -> !llvm.ptr
    %lp = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %l32 = llvm.load %lp : !llvm.ptr -> i32
    %l = llvm.zext %l32 : i32 to i64
    func.call @nixev_text_set(%out, %s, %l) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    scf.yield %c1 : i64
  } else {
    scf.yield %c0 : i64
  }
  // Path: to the store when asked, else the bytes
  %u1 = arith.cmpi eq, %h1, %c0 : i64
  %ispath = arith.cmpi eq, %t, %c10 : i8
  %g2 = arith.andi %u1, %ispath : i1
  %h2 = scf.if %g2 -> (i64) {
    %sp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %s = llvm.load %sp : !llvm.ptr -> !llvm.ptr
    %lp = llvm.getelementptr %v[4] : (!llvm.ptr) -> !llvm.ptr, i8
    %l32 = llvm.load %lp : !llvm.ptr -> i32
    %l = llvm.zext %l32 : i32 to i64
    %cts_nz = arith.cmpi ne, %cts, %c0 : i64
    scf.if %cts_nz {
      func.call @nixev_copy_path(%st, %ctx, %s, %l, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    } else {
      func.call @nixev_text_set(%out, %s, %l) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
    scf.yield %c1 : i64
  } else {
    scf.yield %h1 : i64
  }
  // Attrs: __toString called with the set, its result coerced (null position, canonicalizePath true); else outPath
  // coerced (the caller's position and canonicalizePath); else the TypeError
  %u2 = arith.cmpi eq, %h2, %c0 : i64
  %isattrs = arith.cmpi eq, %t, %c11 : i8
  %g3 = arith.andi %u2, %isattrs : i1
  %h3 = scf.if %g3 -> (i64) {
    %f = func.call @nixev_attr_get(%st, %v, %c1) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %fi = llvm.ptrtoint %f : !llvm.ptr to i64
    %hasf = arith.cmpi ne, %fi, %c0 : i64
    scf.if %hasf {
      %r = func.call @nixev_cell(%st) : (!llvm.ptr) -> !llvm.ptr
      %args = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
      llvm.store %v, %args : !llvm.ptr, !llvm.ptr
      %fvp = llvm.getelementptr %f[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %fv = llvm.load %fvp : !llvm.ptr -> !llvm.ptr
      %nullpos = llvm.inttoptr %c0 : i64 to !llvm.ptr
      func.call @_ZN5nixev9EvalState12callFunctionERNS_5ValueEmPPS1_S2_PKv(%st, %fv, %c1, %args, %r, %nullpos) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
      %gp = llvm.mlir.addressof @cst_ctx_ts : !llvm.ptr
      func.call @nixev_ts_coerce(%st, %r, %ctx, %cm, %cts, %nullpos, %c1, %gp, %c57, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> ()
    } else {
      %o = func.call @nixev_attr_get(%st, %v, %c0) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
      %oi = llvm.ptrtoint %o : !llvm.ptr to i64
      %haso = arith.cmpi ne, %oi, %c0 : i64
      scf.if %haso {
        %ovp = llvm.getelementptr %o[8] : (!llvm.ptr) -> !llvm.ptr, i8
        %ov = llvm.load %ovp : !llvm.ptr -> !llvm.ptr
        %gp = llvm.mlir.addressof @cst_ctx_op : !llvm.ptr
        func.call @nixev_ts_coerce(%st, %ov, %ctx, %cm, %cts, %pos, %canon, %gp, %c40, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> ()
      } else {
        func.call @nixev_coerce_throw(%st, %v, %pos, %ectx, %ectxn) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
      }
    }
    scf.yield %c1 : i64
  } else {
    scf.yield %h2 : i64
  }
  // the coerceMore cases
  %u3 = arith.cmpi eq, %h3, %c0 : i64
  %more = arith.cmpi ne, %cm, %c0 : i64
  %gm = arith.andi %u3, %more : i1
  %isbool = arith.cmpi eq, %t, %c7 : i8
  %gb = arith.andi %gm, %isbool : i1
  %h4 = scf.if %gb -> (i64) {
    %bp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %b = llvm.load %bp : !llvm.ptr -> i8
    %bnz = arith.cmpi ne, %b, %c0_8 : i8
    scf.if %bnz {
      %gp = llvm.mlir.addressof @cst_one : !llvm.ptr
      func.call @nixev_text_set(%out, %gp, %c1) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
    scf.yield %c1 : i64
  } else {
    scf.yield %h3 : i64
  }
  %isint = arith.cmpi eq, %t, %c5 : i8
  %gi = arith.andi %gm, %isint : i1
  %h5 = scf.if %gi -> (i64) {
    %ip = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %x = llvm.load %ip : !llvm.ptr -> i64
    func.call @nixev_int_text(%out, %x) : (!llvm.ptr, i64) -> ()
    scf.yield %c1 : i64
  } else {
    scf.yield %h4 : i64
  }
  %isfloat = arith.cmpi eq, %t, %c6 : i8
  %gf = arith.andi %gm, %isfloat : i1
  %h6 = scf.if %gf -> (i64) {
    %fp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %d = llvm.load %fp : !llvm.ptr -> f64
    func.call @nixev_float_text(%out, %d) : (!llvm.ptr, f64) -> ()
    scf.yield %c1 : i64
  } else {
    scf.yield %h5 : i64
  }
  %isnull = arith.cmpi eq, %t, %c8 : i8
  %gn = arith.andi %gm, %isnull : i1
  %h7 = scf.if %gn -> (i64) {
    scf.yield %c1 : i64
  } else {
    scf.yield %h6 : i64
  }
  %islist = arith.cmpi eq, %t, %c12 : i8
  %gl = arith.andi %gm, %islist : i1
  %h8 = scf.if %gl -> (i64) {
    func.call @cst_list(%st, %v, %ctx, %cm, %cts, %pos, %ectx, %ectxn, %out) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    scf.yield %c1 : i64
  } else {
    scf.yield %h7 : i64
  }
  // nothing handled it: the TypeError
  %u8 = arith.cmpi eq, %h8, %c0 : i64
  scf.if %u8 {
    func.call @nixev_coerce_throw(%st, %v, %pos, %ectx, %ectxn) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
  }
  return
}
