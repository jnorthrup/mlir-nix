// The Attrs/List composition of EvalState::printValue hollowed out of lib/Eval/Eval.cpp: the separator/bracket
// stitching of the per-attr/element pieces, a trikeshed.combineAll of the pieces drained once into the Text.
// The C++ keeps the recursion into child values, the seen-table (firstTime/WordTable, «repeated» identity), the
// depth guard and the attribute-name sorting (lexicographicOrder); each piece is rendered once by the callback
// nixev_pv_piece (a combineAll's region runs for its size and again for its drain, so the callback caches each
// piece in a Text, the concatMap/replaceStrings cache way).  One entry
//   nixev_ts_pv_comp(ctx, kind, n, into, cap) -> the total byte count
// kind 0 attrs: n rows, 2n pieces (piece 2k the quoted name, piece 2k+1 the value), stitched "{ " + name + " = "
//   + value + "; " per row + "}"; kind 1 list: n pieces (the values), stitched "[ " + value + " " per element + "]".
// The caller reserves room: a first call with cap 0 renders the pieces (the size pass) and returns the count
// without draining; the caller resizes the Text and calls again with that room, which drains (cache hits).
// The fixed words are a small constant table (a subset of PrintValueOps.mlir's blob, private to this module).
// Word ids: 0 "{ "  1 " = "  2 "; "  3 "}"  4 "[ "  5 " "  6 "]"
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>

memref.global "private" constant @pc_blob : memref<12xi8> = dense<"0x7b20203d203b207d5b20205d">
memref.global "private" constant @pc_off : memref<7xi32> = dense<[0, 2, 5, 7, 8, 10, 11]>
memref.global "private" constant @pc_len : memref<7xi32> = dense<[2, 3, 2, 1, 2, 1, 1]>

func.func private @nixev_pv_piece(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr)

// the descriptor of n bytes at p (module-unique: PrintValueOps.mlir has its own @pv_desc8)
func.func private @pc_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// the (start, length) of word wid in the blob (two scalar reads; returning indices allocates nothing)
func.func private @pc_bounds(%wid: index) -> (index, index) {
  %og = memref.get_global @pc_off : memref<7xi32>
  %offs = trikeshed.text %og : memref<7xi32> -> !s32
  %lg = memref.get_global @pc_len : memref<7xi32>
  %lens = trikeshed.text %lg : memref<7xi32> -> !s32
  %o = trikeshed.at %offs[%wid] : !s32, index -> i32
  %l = trikeshed.at %lens[%wid] : !s32, index -> i32
  %oi = arith.index_cast %o : i32 to index
  %li = arith.index_cast %l : i32 to index
  return %oi, %li : index, index
}

func.func @nixev_ts_pv_comp(%ctx: !llvm.ptr, %kind: i32, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %one64 = arith.constant 1 : i64
  %c2 = arith.constant 2 : index
  %k0 = arith.constant 0 : i32
  %w1 = arith.constant 1 : index
  %w2 = arith.constant 2 : index
  %w5 = arith.constant 5 : index
  %w0 = arith.constant 0 : index
  %w4 = arith.constant 4 : index
  %w3 = arith.constant 3 : index
  %w6 = arith.constant 6 : index
  %isAttrs = arith.cmpi eq, %kind, %k0 : i32
  %ni = arith.index_cast %n : i64 to index
  %two_n = arith.muli %ni, %c2 : index
  %np = arith.select %isAttrs, %two_n, %ni : index
  %bg = memref.get_global @pc_blob : memref<12xi8>
  %blob = trikeshed.text %bg : memref<12xi8> -> !text
  // the pieces: each rendered once by the callback (cached), stitched with its separator word.
  // attrs piece j: even -> name + " = " (word 1), odd -> value + "; " (word 2); list piece j: value + " " (word 5).
  %all, %co = trikeshed.combineAll %np : !text, !coords {
  ^bb0(%j: index):
    %j64 = arith.index_cast %j : index to i64
    %oe = llvm.alloca %one64 x !llvm.ptr : (i64) -> !llvm.ptr
    %on = llvm.alloca %one64 x i64 : (i64) -> !llvm.ptr
    func.call @nixev_pv_piece(%ctx, %j64, %oe, %on) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
    %p = llvm.load %oe : !llvm.ptr -> !llvm.ptr
    %l = llvm.load %on : !llvm.ptr -> i64
    %pd = func.call @pc_desc8(%p, %l) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m8
    %piece = builtin.unrealized_conversion_cast %pm : !m8 to !text
    %bit = arith.andi %j, %c1 : index
    %odd = arith.cmpi ne, %bit, %c0 : index
    %wa = arith.select %odd, %w2, %w1 : index
    %wid = arith.select %isAttrs, %wa, %w5 : index
    %ws, %wl = func.call @pc_bounds(%wid) : (index) -> (index, index)
    %sep = trikeshed.slice %blob[%ws, %wl] : !text -> !text
    %row = trikeshed.combine %piece, %sep : !text, !text -> !text
    trikeshed.yield %row : !text
  }
  // the brackets: attrs "{ " (0) ... "}" (3), list "[ " (4) ... "]" (6)
  %ow = arith.select %isAttrs, %w0, %w4 : index
  %cw = arith.select %isAttrs, %w3, %w6 : index
  %os, %ol = func.call @pc_bounds(%ow) : (index) -> (index, index)
  %open = trikeshed.slice %blob[%os, %ol] : !text -> !text
  %cs, %cl = func.call @pc_bounds(%cw) : (index) -> (index, index)
  %close = trikeshed.slice %blob[%cs, %cl] : !text -> !text
  %t1 = trikeshed.combine %open, %all : !text, !text -> !text
  %whole = trikeshed.combine %t1, %close : !text, !text -> !text
  %sz = trikeshed.size %whole : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @pc_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m8
    %end = trikeshed.drain %whole, %mi : !text, !m8 -> index
  }
  return %szi : i64
}
