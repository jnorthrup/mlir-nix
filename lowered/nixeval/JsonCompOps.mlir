// The JSON composition of a set or a list, hollowed out of lib/Eval/Formats.cpp (printValueAsJSON): one
// trikeshed.combineAll over the rows, each row the separator (',' after the first row), the escaped key (a set), ':' (a
// set) and the value's text, drained ONCE into the caller's JsonOut; the whole is '{' rows '}' or '[' rows ']'.
// The C++ keeps the recursion, the forcing, the contexts, the store copies, the outPath shortcut, CallDepth and the
// error traces: nixev_json_piece (the callback) renders a piece once, in order, into the composition's arena.
// A combineAll's region runs for its size and again for its drain, so the callback must answer the second run from
// the arena (it does: a rendered piece is only looked up).  One entry
//   nixev_ts_json_comp(ctx, kind, n, into, cap) -> the total byte count
// kind 0 a set (2n pieces: 2j the escaped key of row j, 2j+1 its value), kind 1 a list (n pieces: j the element j).
// The caller calls it with cap 0 (the size pass renders every piece, nothing is written), reserves that room, and
// calls again with cap = that count (the drain: every piece is a lookup).  Punctuation is the 6-byte blob below.
!text = !trikeshed.series<i8>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// { } [ ] , :  (set open 0, set close 1, list open 2, list close 3, comma 4, colon 5)
memref.global "private" constant @jc_blob : memref<6xi8> = dense<"0x7b7d5b5d2c3a">

// the callback: piece p's bytes at *pp (*nn long); the bridge renders it on the first call and answers from its cache after
func.func private @nixev_json_piece(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr)

// the descriptor of n bytes at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @jc_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixev_ts_json_comp(%ctx: !llvm.ptr, %kind: i32, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c0_64 = arith.constant 0 : i64
  %c1_64 = arith.constant 1 : i64
  %c2_64 = arith.constant 2 : i64
  %k0 = arith.constant 0 : i32
  %wOpenS = arith.constant 0 : index
  %wCloseS = arith.constant 1 : index
  %wOpenL = arith.constant 2 : index
  %wCloseL = arith.constant 3 : index
  %wComma = arith.constant 4 : index
  %wColon = arith.constant 5 : index
  %isAttrs = arith.cmpi eq, %kind, %k0 : i32
  %ni = arith.index_cast %n : i64 to index
  %openi = arith.select %isAttrs, %wOpenS, %wOpenL : index
  %closei = arith.select %isAttrs, %wCloseS, %wCloseL : index
  %colonn = arith.select %isAttrs, %c1, %c0 : index
  // the callback's two out-slots, hoisted out of the region (an alloca inside a loop grows the stack every row)
  %oe = llvm.alloca %c1_64 x !llvm.ptr : (i64) -> !llvm.ptr
  %on = llvm.alloca %c1_64 x i64 : (i64) -> !llvm.ptr
  %bg = memref.get_global @jc_blob : memref<6xi8>
  %blob = trikeshed.text %bg : memref<6xi8> -> !text
  %all, %co = trikeshed.combineAll %ni : !text, !coords {
  ^bb0(%j: index):
    %j64 = arith.index_cast %j : index to i64
    %j2 = arith.muli %j64, %c2_64 : i64
    // the escaped key of a set row (piece 2j); a list row has none: an empty piece, the callback not called
    %kp, %kn = scf.if %isAttrs -> (!llvm.ptr, i64) {
      func.call @nixev_json_piece(%ctx, %j2, %oe, %on) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
      %kp0 = llvm.load %oe : !llvm.ptr -> !llvm.ptr
      %kn0 = llvm.load %on : !llvm.ptr -> i64
      scf.yield %kp0, %kn0 : !llvm.ptr, i64
    } else {
      scf.yield %oe, %c0_64 : !llvm.ptr, i64
    }
    %kd = func.call @jc_desc8(%kp, %kn) : (!llvm.ptr, i64) -> !d
    %km = builtin.unrealized_conversion_cast %kd : !d to !m8
    %key = builtin.unrealized_conversion_cast %km : !m8 to !text
    // the value's text: piece 2j+1 (set) or j (list)
    %vj = arith.addi %j2, %c1_64 : i64
    %vi = arith.select %isAttrs, %vj, %j64 : i64
    func.call @nixev_json_piece(%ctx, %vi, %oe, %on) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
    %vp = llvm.load %oe : !llvm.ptr -> !llvm.ptr
    %vl = llvm.load %on : !llvm.ptr -> i64
    %vd = func.call @jc_desc8(%vp, %vl) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m8
    %val = builtin.unrealized_conversion_cast %vm : !m8 to !text
    // ',' before every row but the first, ':' after the key (sets only)
    %gt = arith.cmpi ugt, %j, %c0 : index
    %sepn = arith.select %gt, %c1, %c0 : index
    %sep = trikeshed.slice %blob[%wComma, %sepn] : !text -> !text
    %colon = trikeshed.slice %blob[%wColon, %colonn] : !text -> !text
    %row = trikeshed.combine %sep, %key, %colon, %val : !text, !text, !text, !text -> !text
    trikeshed.yield %row : !text
  }
  %open = trikeshed.slice %blob[%openi, %c1] : !text -> !text
  %close = trikeshed.slice %blob[%closei, %c1] : !text -> !text
  %t1 = trikeshed.combine %open, %all : !text, !text -> !text
  %whole = trikeshed.combine %t1, %close : !text, !text -> !text
  %sz = trikeshed.size %whole : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @jc_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m8
    %end = trikeshed.drain %whole, %mi : !text, !m8 -> index
  }
  return %szi : i64
}
