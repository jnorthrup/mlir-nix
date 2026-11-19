// The higher-order C++ list primops (__concatLists, __concatMap, __filter, __any, __all, __elem) hollowed into the
// TrikeShed dialect.  lib/Eval/Builtins.cpp keeps only the forcing of operands (Nix's error order and wording) and calls
// these entries; the list algebra is here, in trikeshed.size / at / where / combineAll / drain, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).  A list's cells
// (Value**, 24-byte Value: VType u8@0, aux u32@4, union@8, list.elems ptr@8) are a series<i64> of pointer bits: the
// descriptor of n cells at p is built inline (a struct, not a memref: returning it allocates nothing and clones nothing)
// and cast to the series' strided memref at the use site, as ListOps.mlir does.  VType: Bool 7, List 12.
//
// The function/comparator operands are Nix functions, so each predicate/comparison calls back into the evaluator
// (callFunction + forceBool, or eqValues) — the forcing that carries a std::string_view error context stays in C++.
// concatLists/concatMap are a combineAll of the parts (the inner lists' cells); concatMap's callback caches each call's
// result so the function runs once per element even though a combineAll's region runs for its size and again for its
// drain (the replaceStrings cache way).  filter is a where (the kept indices, scanned once) drained into the bridge's
// keep buffer.  any/all/elem short-circuit: a scf.while that stops at the first true/false/match, so a later element is
// never forced (no trikeshed op short-circuits; fold and where scan every element).  A C++ exception thrown in a callback
// unwinds through the compiled frame, as fold's callFunction does in ListOps.mlir.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

func.func private @nixev_concat_part(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_concatmap_part(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_pred(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixev_elem_eq(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)

// the descriptor of n i64 cells at p (module-unique: ListOps.mlir has its own @desc)
func.func private @l2_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the descriptor of a forced list's cells (a struct: safe to return; the caller casts it to the series at the use site)
func.func private @l2_list_desc(%list: !llvm.ptr) -> !d {
  %ep = llvm.getelementptr %list[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %list[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = llvm.zext %n32 : i32 to i64
  %d = func.call @l2_desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

// write a Bool result: VType 7 at 0, the byte at 8 (mkBool sets only those)
func.func private @l2_mkbool(%v: !llvm.ptr, %b: i64) {
  %c0 = arith.constant 0 : i64
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %seven = arith.constant 7 : i8
  llvm.store %seven, %tp : i8, !llvm.ptr
  %nz = arith.cmpi ne, %b, %c0 : i64
  %b8 = arith.extui %nz : i1 to i8
  %bp = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %b8, %bp : i8, !llvm.ptr
  return
}

// __concatLists: the combineAll of the inner lists' cells, drained into the result list.  The size pass forces every
// inner list in list order (the callback), as cp::Combine's size did; the drain copies their cells.  The bridge forced
// the outer list.
func.func @nixev_ts_concatLists(%st: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %ss : !s
  %c1 = arith.constant 1 : i64
  %all, %co = trikeshed.combineAll %n : !s, !coords {
  ^bb0(%k: index):
    %x = trikeshed.at %ss[%k] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %oe = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
    %on = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    func.call @nixev_concat_part(%st, %xp, %pos, %oe, %on) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %p = llvm.load %oe : !llvm.ptr -> !llvm.ptr
    %l = llvm.load %on : !llvm.ptr -> i64
    %pd = func.call @l2_desc(%p, %l) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m
    %part = builtin.unrealized_conversion_cast %pm : !m to !s
    trikeshed.yield %part : !s
  }
  %total = trikeshed.size %all : !s
  %t64 = arith.index_cast %total : index to i64
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %t64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %id = func.call @l2_desc(%elems, %t64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %id : !d to !m
  %end = trikeshed.drain %all, %into : !s, !m -> index
  return
}

// __concatMap: f x for each element (once, cached by the callback), each result a list; the combineAll of their cells.
// The size pass runs the calls in list order (filling the cache); the drain reuses it.  The bridge forced the list.
func.func @nixev_ts_concatMap(%st: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %cm: !llvm.ptr) {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %ss : !s
  %c1 = arith.constant 1 : i64
  %all, %co = trikeshed.combineAll %n : !s, !coords {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %x = trikeshed.at %ss[%k] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %oe = llvm.alloca %c1 x !llvm.ptr : (i64) -> !llvm.ptr
    %on = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
    func.call @nixev_concatmap_part(%cm, %k64, %xp, %oe, %on) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %p = llvm.load %oe : !llvm.ptr -> !llvm.ptr
    %l = llvm.load %on : !llvm.ptr -> i64
    %pd = func.call @l2_desc(%p, %l) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m
    %part = builtin.unrealized_conversion_cast %pm : !m to !s
    trikeshed.yield %part : !s
  }
  %total = trikeshed.size %all : !s
  %t64 = arith.index_cast %total : index to i64
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %t64) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %id = func.call @l2_desc(%elems, %t64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %id : !d to !m
  %end = trikeshed.drain %all, %into : !s, !m -> index
  return
}

// __filter: the where of the list (the predicate calls f and forces its Bool, once per element in order), drained into
// the bridge's keep buffer; returns the kept count.  The bridge forced the list and chose the keep buffer (stack when
// short, arena when long), and returns the original list when nothing was filtered.
func.func @nixev_ts_filter(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %keep: !llvm.ptr, %pos: !llvm.ptr) -> i64 {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %kept = trikeshed.where %ss : !s -> !s {
  ^bb0(%x: i64):
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %w = arith.constant 0 : i64
    %b = func.call @nixev_pred(%st, %f, %xp, %pos, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
    %b1 = arith.trunci %b : i64 to i1
    trikeshed.yield %b1 : i1
  }
  %k = trikeshed.size %kept : !s
  %k64 = arith.index_cast %k : index to i64
  %kd = func.call @l2_desc(%keep, %k64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %kd : !d to !m
  %end = trikeshed.drain %kept, %into : !s, !m -> index
  return %k64 : i64
}

// __any: true at the first element whose f forces true; the scf.while stops there, never forcing a later element.
func.func @nixev_ts_any(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %ss : !s
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c0 = arith.constant 0 : i64
  %r:2 = scf.while (%i = %zi, %acc = %c0) : (index, i64) -> (index, i64) {
    %inside = arith.cmpi ult, %i, %n : index
    %notyet = arith.cmpi eq, %acc, %c0 : i64
    %go = arith.andi %inside, %notyet : i1
    scf.condition(%go) %i, %acc : index, i64
  } do {
  ^bb0(%i: index, %acc: i64):
    %x = trikeshed.at %ss[%i] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %w = arith.constant 1 : i64
    %b = func.call @nixev_pred(%st, %f, %xp, %pos, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
    %acc2 = arith.ori %acc, %b : i64
    %i2 = arith.addi %i, %oi : index
    scf.yield %i2, %acc2 : index, i64
  }
  func.call @l2_mkbool(%v, %r#1) : (!llvm.ptr, i64) -> ()
  return
}

// __all: false at the first element whose f forces false; the scf.while stops there.
func.func @nixev_ts_all(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %ss : !s
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %r:2 = scf.while (%i = %zi, %acc = %c1) : (index, i64) -> (index, i64) {
    %inside = arith.cmpi ult, %i, %n : index
    %still = arith.cmpi ne, %acc, %c0 : i64
    %go = arith.andi %inside, %still : i1
    scf.condition(%go) %i, %acc : index, i64
  } do {
  ^bb0(%i: index, %acc: i64):
    %x = trikeshed.at %ss[%i] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %w = arith.constant 2 : i64
    %b = func.call @nixev_pred(%st, %f, %xp, %pos, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
    %acc2 = arith.andi %acc, %b : i64
    %i2 = arith.addi %i, %oi : index
    scf.yield %i2, %acc2 : index, i64
  }
  func.call @l2_mkbool(%v, %r#1) : (!llvm.ptr, i64) -> ()
  return
}

// __elem: true at the first element equal to the needle (pointer equality, else eqValues); the scf.while stops there.
func.func @nixev_ts_elem(%st: !llvm.ptr, %a: !llvm.ptr, %list: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %d = func.call @l2_list_desc(%list) : (!llvm.ptr) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %n = trikeshed.size %ss : !s
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %c0 = arith.constant 0 : i64
  %r:2 = scf.while (%i = %zi, %acc = %c0) : (index, i64) -> (index, i64) {
    %inside = arith.cmpi ult, %i, %n : index
    %notyet = arith.cmpi eq, %acc, %c0 : i64
    %go = arith.andi %inside, %notyet : i1
    scf.condition(%go) %i, %acc : index, i64
  } do {
  ^bb0(%i: index, %acc: i64):
    %x = trikeshed.at %ss[%i] : !s, index -> i64
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %b = func.call @nixev_elem_eq(%st, %a, %xp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %acc2 = arith.ori %acc, %b : i64
    %i2 = arith.addi %i, %oi : index
    scf.yield %i2, %acc2 : index, i64
  }
  func.call @l2_mkbool(%v, %r#1) : (!llvm.ptr, i64) -> ()
  return
}
