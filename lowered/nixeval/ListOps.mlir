// The C++ list primops (__length, __elemAt, __genList, __foldl') hollowed into the TrikeShed dialect.
// lib/Eval/Builtins.cpp keeps only the forcing of operands (Nix's error order and wording) and calls these entries;
// the list algebra itself is here, in trikeshed.size / at / series / fold, lowered by --trikeshed-lower-cursors and the
// stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).  A list's cells (Value**, 24-byte Value: VType u8@0,
// aux u32@4, union@8, list.elems ptr@8) are seen as a series<i64> of pointer bits: the descriptor of n cells at p is built
// inline and cast to the series' strided memref.  An element is a Value* thunk, made by the C++ callbacks below; the
// evaluator forces it later, so laziness is kept.  VType: Int 5, List 12.
//
// The C++ methods called by their mangled name (this is the first ptr): mkList(Value&, size_t),
// callFunction(Value&, size_t, Value**, Value&, PosPtr), forceCell(Value&, PosPtr).  None takes a std::string_view, so the
// ABI is the same on libstdc++ and libc++; the forcing that carries an error context stays in the C++ bridge.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @nixev_gen_elem(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixev_cell(!llvm.ptr) -> !llvm.ptr
func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)
func.func private @_ZN5nixev9EvalState12callFunctionERNS_5ValueEmPPS1_S2_PKv(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @_ZN5nixev9EvalState9forceCellERNS_5ValueEPKv(!llvm.ptr, !llvm.ptr, !llvm.ptr)

// the descriptor of n i64 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// copy the 24 bytes of a Value from %src to %dst
func.func private @copyval(%src: !llvm.ptr, %dst: !llvm.ptr) {
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

// __length: the size of the list's series, an Int.  The bridge has forced the list.
func.func @nixev_ts_length(%list: !llvm.ptr, %v: !llvm.ptr) {
  %ep = llvm.getelementptr %list[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %list[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = llvm.zext %n32 : i32 to i64
  %d = func.call @desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %k = trikeshed.size %ss : !s
  %r = arith.index_cast %k : index to i64
  %tp = llvm.getelementptr %v[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %five = arith.constant 5 : i8
  llvm.store %five, %tp : i8, !llvm.ptr
  %ip = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  llvm.store %r, %ip : i64, !llvm.ptr
  return
}

// __elemAt: element n of the list's series, forced.  The bridge has forced the list and index and checked the bounds.
func.func @nixev_ts_elemAt(%st: !llvm.ptr, %list: !llvm.ptr, %n: i64, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %ep = llvm.getelementptr %list[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %list[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %sz = llvm.zext %n32 : i32 to i64
  %d = func.call @desc(%elems, %sz) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %e64 = trikeshed.at %ss[%ni] : !s, index -> i64
  %e = llvm.inttoptr %e64 : i64 to !llvm.ptr
  func.call @_ZN5nixev9EvalState9forceCellERNS_5ValueEPKv(%st, %e, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @copyval(%e, %v) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}

// __genList: mkList, then the series whose element i is the thunk `f i`, drained into the arena cells.  The bridge has
// forced the length (and refused a negative one) and the function.
func.func @nixev_ts_genList(%st: !llvm.ptr, %f: !llvm.ptr, %n: i64, %v: !llvm.ptr) {
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %d = func.call @desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %d : !d to !m
  %ni = arith.index_cast %n : i64 to index
  %ss = trikeshed.series %ni : !s {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %el = func.call @nixev_gen_elem(%st, %f, %i64) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %eb = llvm.ptrtoint %el : !llvm.ptr to i64
    trikeshed.yield %eb : i64
  }
  %end = trikeshed.drain %ss, %into : !s, !m -> index
  return
}

// __foldl': fold the list's series from the (unforced) accumulator nul, the step `f acc x` applied by callFunction; the
// last result is forced and copied out.  The bridge has forced the function and the list.
func.func @nixev_ts_fold(%st: !llvm.ptr, %f: !llvm.ptr, %list: !llvm.ptr, %nul: !llvm.ptr, %v: !llvm.ptr, %pos: !llvm.ptr) {
  %ep = llvm.getelementptr %list[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %list[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %sz = llvm.zext %n32 : i32 to i64
  %d = func.call @desc(%elems, %sz) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %z = llvm.ptrtoint %nul : !llvm.ptr to i64
  %two = arith.constant 2 : i64
  %one = arith.constant 1 : i64
  %r = trikeshed.fold %ss, %z : !s, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %ap = llvm.inttoptr %acc : i64 to !llvm.ptr
    %xp = llvm.inttoptr %x : i64 to !llvm.ptr
    %next = func.call @nixev_cell(%st) : (!llvm.ptr) -> !llvm.ptr
    %fa = llvm.alloca %two x !llvm.ptr : (i64) -> !llvm.ptr
    llvm.store %ap, %fa : !llvm.ptr, !llvm.ptr
    %fb = llvm.getelementptr %fa[%one] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.ptr
    llvm.store %xp, %fb : !llvm.ptr, !llvm.ptr
    func.call @_ZN5nixev9EvalState12callFunctionERNS_5ValueEmPPS1_S2_PKv(%st, %f, %two, %fa, %next, %pos) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
    %nb = llvm.ptrtoint %next : !llvm.ptr to i64
    trikeshed.yield %nb : i64
  }
  %rp = llvm.inttoptr %r : i64 to !llvm.ptr
  func.call @_ZN5nixev9EvalState9forceCellERNS_5ValueEPKv(%st, %rp, %pos) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  func.call @copyval(%rp, %v) : (!llvm.ptr, !llvm.ptr) -> ()
  return
}