// The C++ set primops (__attrNames, __attrValues, __getAttr, __hasAttr, __intersectAttrs) hollowed into the TrikeShed
// dialect.  lib/Eval/Builtins.cpp keeps only the forcing of operands (Nix's error order and wording) and calls these
// entries; the set algebra itself is here, in trikeshed.size / at / series / sorted / bisect / where / alpha / compare /
// drain, lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// A set is a Bindings: u32 size_@0, PosPtr pos@8, Attr attrs[0]@16, the rows sorted by Symbol (a u32).  An Attr is 16
// bytes: Symbol name@0, PosIdx pos@4, Value* value@8.  A Value is 24 bytes: VType u8@0 (Int 5, Bool 7, Attrs 11, List 12),
// aux u32@4, union@8 (list.elems ptr@8, attrs ptr@8, boolean@8).  A series is stride-1, so the rows' symbols (one u32
// every 16 bytes) are gathered once into a contiguous series<i64> to bisect; symbols are non-negative, so the signed
// order is their order.  A list's cells (Value**) are a series<i64> of pointer bits, drained into the arena cells mkList
// made.
//
// attrNames / attrValues order the rows by their names' BYTES (Bindings::lexicographicOrder), not by symbol: a sorted
// index series whose order reads each name's first-eight-bytes prefix word (SymbolTable.prefix, unsigned), and on a tie
// compares the names' bytes (trikeshed.compare unsigned over the SymbolTable.names windows).  The bridge hands these two
// arrays' data pointers in, so the symbol table's layout never crosses the ABI.
//
// The C++ methods called by their mangled name (this is the first ptr): mkList(Value&, size_t), forceCell(Value&, PosPtr),
// allocBindings(size_t).  None takes a std::string_view, so the ABI is the same on libstdc++ and libc++; the forcing that
// carries an error context stays in the C++ bridge.  nixev_name_cell is the callback for a name's string cell only the
// evaluator can make (newStringWindow over the symbol table's own bytes).
!s64 = !trikeshed.series<i64>
!text = !trikeshed.series<i8>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)
func.func private @_ZN5nixev9EvalState9forceCellERNS_5ValueEPKv(!llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @_ZN5nixev9EvalState13allocBindingsEm(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_name_cell(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr

// the descriptor of n cells at p with the given element stride (a struct, not a memref: returning it allocates nothing)
func.func private @set_desc(%p: !llvm.ptr, %n: i64, %stride: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %stride, %e[4, 0] : !d
  return %f : !d
}

// a name's bytes as a window: SymbolTable.names[sym] is a StringRef {const char* @0, size_t @8}
func.func private @set_namedesc(%names: !llvm.ptr, %sym: i64) -> !d {
  %c16 = arith.constant 16 : i64
  %off = llvm.mul %sym, %c16 : i64
  %slot = llvm.getelementptr %names[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %slot : !llvm.ptr -> !llvm.ptr
  %c8 = arith.constant 8 : i64
  %lp = llvm.getelementptr %slot[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n = llvm.load %lp : !llvm.ptr -> i64
  %c1 = arith.constant 1 : i64
  %d = func.call @set_desc(%p, %n, %c1) : (!llvm.ptr, i64, i64) -> !d
  return %d : !d
}

// copy the 24 bytes of a Value from %src to %dst
func.func private @set_copyval(%src: !llvm.ptr, %dst: !llvm.ptr) {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %p0 = llvm.getelementptr %src[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %w0 = llvm.load %p0 : !llvm.ptr -> i64
  %q0 = llvm.getelementptr %dst[0] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %w0, %q0 : i64, !llvm.ptr
  %p1 = llvm.getelementptr %src[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %w1 = llvm.load %p1 : !llvm.ptr -> i64
  %q1 = llvm.getelementptr %dst[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %w1, %q1 : i64, !llvm.ptr
  %p2 = llvm.getelementptr %src[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %w2 = llvm.load %p2 : !llvm.ptr -> i64
  %q2 = llvm.getelementptr %dst[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %w2, %q2 : i64, !llvm.ptr
  return
}

// the order of two rows by their names' bytes: the prefix words first (unsigned), the bytes only on a tie
// (SymbolTable::less / Bindings::lexicographicOrder).  The name windows are slices made and compared here, never returned.
func.func private @set_name_order(%attrs: !llvm.ptr, %prefixes: !llvm.ptr, %names: !llvm.ptr, %a: i64, %b: i64) -> i32 {
  %c16 = arith.constant 16 : i64
  %oa = llvm.mul %a, %c16 : i64
  %ra = llvm.getelementptr %attrs[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sa = llvm.load %ra : !llvm.ptr -> i32
  %ob = llvm.mul %b, %c16 : i64
  %rb = llvm.getelementptr %attrs[%ob] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sb = llvm.load %rb : !llvm.ptr -> i32
  %sa64 = arith.extui %sa : i32 to i64
  %sb64 = arith.extui %sb : i32 to i64
  %c8 = arith.constant 8 : i64
  %paoff = llvm.mul %sa64, %c8 : i64
  %pap = llvm.getelementptr %prefixes[%paoff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %pa = llvm.load %pap : !llvm.ptr -> i64
  %pboff = llvm.mul %sb64, %c8 : i64
  %pbp = llvm.getelementptr %prefixes[%pboff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %pb = llvm.load %pbp : !llvm.ptr -> i64
  %tie = arith.cmpi eq, %pa, %pb : i64
  %r = scf.if %tie -> (i32) {
    %da = func.call @set_namedesc(%names, %sa64) : (!llvm.ptr, i64) -> !d
    %ma = builtin.unrealized_conversion_cast %da : !d to !m8
    %ta = builtin.unrealized_conversion_cast %ma : !m8 to !text
    %db = func.call @set_namedesc(%names, %sb64) : (!llvm.ptr, i64) -> !d
    %mb = builtin.unrealized_conversion_cast %db : !d to !m8
    %tb = builtin.unrealized_conversion_cast %mb : !m8 to !text
    %c = trikeshed.compare %ta, %tb unsigned : !text, !text
    scf.yield %c : i32
  } else {
    %lt = arith.cmpi ult, %pa, %pb : i64
    %m1 = arith.constant -1 : i32
    %o1 = arith.constant 1 : i32
    %c = arith.select %lt, %m1, %o1 : i32
    scf.yield %c : i32
  }
  return %r : i32
}

// the row of a symbol among the rows sorted by symbol, or a negative insertion code.  The rows' symbols are gathered into
// a contiguous series<i64> (a series is stride-1, so the 16-byte rows' names are collected once), then bisected signed:
// symbols are u32, non-negative as i64, so the signed order is their order.
func.func private @set_find(%set: !llvm.ptr, %sym: i64) -> index {
  %np = llvm.getelementptr %set[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = arith.extui %n32 : i32 to i64
  %ni = arith.index_cast %n : i64 to index
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %syms = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %i64, %c16 : i64
    %rp = llvm.getelementptr %attrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %s32 = llvm.load %rp : !llvm.ptr -> i32
    %s64 = arith.extui %s32 : i32 to i64
    trikeshed.yield %s64 : i64
  }
  %idx = trikeshed.bisect %syms, %sym : !s64, i64 -> index
  return %idx : index
}

// __attrNames: mkList, then the name string cell of each row in byte order, drained into the arena cells.  The rows'
// indices 0..n-1 are sorted by their names' bytes (the shared core of attrNames / attrValues), the order kept in this
// function so the sorted buffer is never returned across a call.
func.func @nixev_ts_attrNames(%st: !llvm.ptr, %set: !llvm.ptr, %v: !llvm.ptr, %prefixes: !llvm.ptr, %names: !llvm.ptr) {
  %np = llvm.getelementptr %set[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = arith.extui %n32 : i32 to i64
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %order = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @set_name_order(%attrs, %prefixes, %names, %a, %b) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %c1 = arith.constant 1 : i64
  %d = func.call @set_desc(%elems, %n, %c1) : (!llvm.ptr, i64, i64) -> !d
  %into = builtin.unrealized_conversion_cast %d : !d to !m64
  %ni2 = arith.index_cast %n : i64 to index
  %cells = trikeshed.series %ni2 : !s64 {
  ^bb0(%i: index):
    %r = trikeshed.at %order[%i] : !s64, index -> i64
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %r, %c16 : i64
    %rp = llvm.getelementptr %attrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %sym = llvm.load %rp : !llvm.ptr -> i32
    %sym64 = arith.extui %sym : i32 to i64
    %nd = func.call @set_namedesc(%names, %sym64) : (!llvm.ptr, i64) -> !d
    %nptr = llvm.extractvalue %nd[0] : !d
    %nlen = llvm.extractvalue %nd[3, 0] : !d
    %cell = func.call @nixev_name_cell(%st, %nptr, %nlen) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %cb = llvm.ptrtoint %cell : !llvm.ptr to i64
    trikeshed.yield %cb : i64
  }
  %end = trikeshed.drain %cells, %into : !s64, !m64 -> index
  return
}

// __attrValues: mkList, then each row's value cell (already made) in byte order, drained into the arena cells.
func.func @nixev_ts_attrValues(%st: !llvm.ptr, %set: !llvm.ptr, %v: !llvm.ptr, %prefixes: !llvm.ptr, %names: !llvm.ptr) {
  %np = llvm.getelementptr %set[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = arith.extui %n32 : i32 to i64
  %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %order = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%a: i64, %b: i64):
    %c = func.call @set_name_order(%attrs, %prefixes, %names, %a, %b) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %c1 = arith.constant 1 : i64
  %d = func.call @set_desc(%elems, %n, %c1) : (!llvm.ptr, i64, i64) -> !d
  %into = builtin.unrealized_conversion_cast %d : !d to !m64
  %ni2 = arith.index_cast %n : i64 to index
  %cells = trikeshed.series %ni2 : !s64 {
  ^bb0(%i: index):
    %r = trikeshed.at %order[%i] : !s64, index -> i64
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %r, %c16 : i64
    %rp = llvm.getelementptr %attrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %c8 = arith.constant 8 : i64
    %vp = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %val = llvm.load %vp : !llvm.ptr -> !llvm.ptr
    %vb = llvm.ptrtoint %val : !llvm.ptr to i64
    trikeshed.yield %vb : i64
  }
  %end = trikeshed.drain %cells, %into : !s64, !m64 -> index
  return
}

// __getAttr: bisect the symbol, force the found row's value and copy it out; 1 when found, 0 when the bridge must throw.
func.func @nixev_ts_getAttr(%st: !llvm.ptr, %set: !llvm.ptr, %sym: i64, %v: !llvm.ptr, %pos: !llvm.ptr) -> i32 {
  %idx = func.call @set_find(%set, %sym) : (!llvm.ptr, i64) -> index
  %zero = arith.constant 0 : index
  %found = arith.cmpi sge, %idx, %zero : index
  %r = scf.if %found -> (i32) {
    %ri = arith.index_cast %idx : index to i64
    %attrs = llvm.getelementptr %set[16] : (!llvm.ptr) -> !llvm.ptr, i8
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %ri, %c16 : i64
    %rp = llvm.getelementptr %attrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %c8 = arith.constant 8 : i64
    %vp = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %val = llvm.load %vp : !llvm.ptr -> !llvm.ptr
    func.call @_ZN5nixev9EvalState9forceCellERNS_5ValueEPKv(%st, %val, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    func.call @set_copyval(%val, %v) : (!llvm.ptr, !llvm.ptr) -> ()
    %one = arith.constant 1 : i32
    scf.yield %one : i32
  } else {
    %z = arith.constant 0 : i32
    scf.yield %z : i32
  }
  return %r : i32
}

// __hasAttr: bisect the symbol; 1 when the set holds it, 0 otherwise.
func.func @nixev_ts_hasAttr(%set: !llvm.ptr, %sym: i64) -> i32 {
  %idx = func.call @set_find(%set, %sym) : (!llvm.ptr, i64) -> index
  %zero = arith.constant 0 : index
  %found = arith.cmpi sge, %idx, %zero : index
  %r = arith.extui %found : i1 to i32
  return %r : i32
}

// __intersectAttrs's walk: keep the walk rows whose symbol bisects into the probe, then drain the second set's matching
// rows (the result always carries the second set's entries) into out.  emitProbe: the walk is the first set, so a kept
// row's place in the second set is its bisect; otherwise the walk IS the second set and the row index is already its place.
func.func private @set_intersect(%out: !llvm.ptr, %walk: !llvm.ptr, %probe: !llvm.ptr, %emitProbe: i1) {
  %np = llvm.getelementptr %walk[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %nw32 = llvm.load %np : !llvm.ptr -> i32
  %nw = arith.extui %nw32 : i32 to i64
  %nwi = arith.index_cast %nw : i64 to index
  %walkAttrs = llvm.getelementptr %walk[16] : (!llvm.ptr) -> !llvm.ptr, i8
  // the probe's symbols, gathered once into a contiguous series<i64> to bisect (signed: symbols are non-negative)
  %ppn = llvm.getelementptr %probe[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %pn32 = llvm.load %ppn : !llvm.ptr -> i32
  %pn = arith.extui %pn32 : i32 to i64
  %pni = arith.index_cast %pn : i64 to index
  %probeAttrs0 = llvm.getelementptr %probe[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %ps = trikeshed.series %pni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %i64, %c16 : i64
    %rp = llvm.getelementptr %probeAttrs0[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %s32 = llvm.load %rp : !llvm.ptr -> i32
    %s64 = arith.extui %s32 : i32 to i64
    trikeshed.yield %s64 : i64
  }
  %widx = trikeshed.series %nwi : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %kept = trikeshed.where %widx : !s64 -> !s64 {
  ^bb0(%i: i64):
    %c16 = arith.constant 16 : i64
    %off = llvm.mul %i, %c16 : i64
    %rp = llvm.getelementptr %walkAttrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %sym = llvm.load %rp : !llvm.ptr -> i32
    %sym64 = arith.extui %sym : i32 to i64
    %j = trikeshed.bisect %ps, %sym64 : !s64, i64 -> index
    %zero = arith.constant 0 : index
    %found = arith.cmpi sge, %j, %zero : index
    trikeshed.yield %found : i1
  }
  %cnt = trikeshed.size %kept : !s64
  %cnt64 = arith.index_cast %cnt : index to i64
  %cnt32 = arith.trunci %cnt64 : i64 to i32
  %sp = llvm.getelementptr %out[0] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %cnt32, %sp : i32, !llvm.ptr
  // the kept rows' places in the second set
  %b1rows = trikeshed.alpha %kept : !s64 -> !s64 {
  ^bb0(%ri: i64):
    %src = scf.if %emitProbe -> (i64) {
      %c16 = arith.constant 16 : i64
      %off = llvm.mul %ri, %c16 : i64
      %rp = llvm.getelementptr %walkAttrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %sym = llvm.load %rp : !llvm.ptr -> i32
      %sym64 = arith.extui %sym : i32 to i64
      %j = trikeshed.bisect %ps, %sym64 : !s64, i64 -> index
      %ji = arith.index_cast %j : index to i64
      scf.yield %ji : i64
    } else {
      scf.yield %ri : i64
    }
    trikeshed.yield %src : i64
  }
  // drain the second set's rows, two i64 words an Attr, into out's arena cells.  The second set is the probe when the
  // walk is the first set (emitProbe), and the walk itself otherwise; its rows are the result's either way.
  %outAttrs = llvm.getelementptr %out[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %probeAttrs = llvm.getelementptr %probe[16] : (!llvm.ptr) -> !llvm.ptr, i8
  %srcAttrs = scf.if %emitProbe -> (!llvm.ptr) {
    scf.yield %probeAttrs : !llvm.ptr
  } else {
    scf.yield %walkAttrs : !llvm.ptr
  }
  %two = arith.constant 2 : index
  %words = arith.muli %cnt, %two : index
  %c1 = arith.constant 1 : i64
  %w64 = arith.index_cast %words : index to i64
  %d = func.call @set_desc(%outAttrs, %w64, %c1) : (!llvm.ptr, i64, i64) -> !d
  %into = builtin.unrealized_conversion_cast %d : !d to !m64
  %cells = trikeshed.series %words : !s64 {
  ^bb0(%k: index):
    %row = arith.divui %k, %two : index
    %w = arith.remui %k, %two : index
    %r = trikeshed.at %b1rows[%row] : !s64, index -> i64
    %c16 = arith.constant 16 : i64
    %roff = llvm.mul %r, %c16 : i64
    %wi = arith.index_cast %w : index to i64
    %c8 = arith.constant 8 : i64
    %woff = llvm.mul %wi, %c8 : i64
    %off = llvm.add %roff, %woff : i64
    %wp = llvm.getelementptr %srcAttrs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %word = llvm.load %wp : !llvm.ptr -> i64
    trikeshed.yield %word : i64
  }
  %end = trikeshed.drain %cells, %into : !s64, !m64 -> index
  return
}

// __intersectAttrs: allocBindings(min), walk the smaller set probing the larger, mkAttrs.  The result is sorted (the walk
// is sorted and the kept rows keep its order) and carries the second set's entries.
func.func @nixev_ts_intersectAttrs(%st: !llvm.ptr, %v: !llvm.ptr, %b0: !llvm.ptr, %b1: !llvm.ptr) {
  %p0 = llvm.getelementptr %b0[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %n032 = llvm.load %p0 : !llvm.ptr -> i32
  %n0 = arith.extui %n032 : i32 to i64
  %p1 = llvm.getelementptr %b1[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %n132 = llvm.load %p1 : !llvm.ptr -> i32
  %n1 = arith.extui %n132 : i32 to i64
  %min = arith.minui %n0, %n1 : i64
  %out = func.call @_ZN5nixev9EvalState13allocBindingsEm(%st, %min) : (!llvm.ptr, i64) -> !llvm.ptr
  %less = arith.cmpi ult, %n0, %n1 : i64
  scf.if %less {
    %yes = arith.constant true
    func.call @set_intersect(%out, %b0, %b1, %yes) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i1) -> ()
    scf.yield
  } else {
    %no = arith.constant false
    func.call @set_intersect(%out, %b1, %b0, %no) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i1) -> ()
    scf.yield
  }
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %attrs = arith.constant 11 : i8
  llvm.store %attrs, %tp : i8, !llvm.ptr
  %ap = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %out, %ap : !llvm.ptr, !llvm.ptr
  return
}