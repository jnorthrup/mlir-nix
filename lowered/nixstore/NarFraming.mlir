// The NAR framing byte emission of lib/Store/StorePaths.cpp's NarWriter hollowed into the TrikeShed dialect: the
// 8-byte little-endian length prefix (u64), the zero padding to a multiple of 8 (pad), the length-prefix + bytes + pad
// composition (str), and the constant NAR tokens ("(", "type", "regular", ...).  StorePaths.cpp keeps the filesystem
// walk (lstat/open/read recursion, the PathFilter, the sink I/O, the throw wording); its u64/pad/str bodies are gone,
// replaced by bridges that reserve a stack buffer, call these neutral C-ABI entries and flush the bytes to the Sink.
// The framing algebra is here, in trikeshed.series / slice / text / at / combine / drain over byte series, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Each entry drains into the caller's buffer and returns how many bytes it wrote.  Nothing throws: the framing is pure.
// The NAR byte stream must stay byte-identical (it is hashed for store paths): u64 is little-endian, pad is 8 - n%8
// zero bytes when n%8 != 0 and nothing otherwise, str is u64(n) then the n bytes then the pad.
!b = !trikeshed.series<i8>
!i32s = !trikeshed.series<i32>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @nar_zeros : memref<8xi8> = dense<0>
// the constant NAR tokens, one blob; nar_toff/nar_tlen give each id's slice (id 4 is the empty string)
memref.global "private" constant @nar_tokens : memref<79xi8> =
  dense<"0x2874797065726567756c617265786563757461626c65636f6e74656e74736469726563746f7279656e7472796e616d656e6f646573796d6c696e6b746172676574296e69782d617263686976652d31">
memref.global "private" constant @nar_toff : memref<14xi32> = dense<[0, 1, 5, 12, 22, 22, 30, 39, 44, 48, 52, 59, 65, 66]>
memref.global "private" constant @nar_tlen : memref<14xi32> = dense<[1, 4, 7, 10, 0, 8, 9, 5, 4, 4, 7, 6, 1, 13]>

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @nar_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %bb = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %bb[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// u64: n as 8 little-endian bytes (byte i is bits [8i, 8i+8) of n), drained into `into` (room for 8).
func.func @mlnix_nar_u64(%n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : index
  %bytes = trikeshed.series %c8 : !b {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c8i = arith.constant 8 : i64
    %sh = arith.muli %i64, %c8i : i64
    %v = arith.shrui %n, %sh : i64
    %byte = arith.trunci %v : i64 to i8
    trikeshed.yield %byte : i8
  }
  %c864 = arith.constant 8 : i64
  %od = func.call @nar_desc(%into, %c864) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %bytes, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// pad: the 8 - n%8 zero bytes when n%8 != 0, nothing otherwise, drained into `into` (room for 8); returns the count.
func.func @mlnix_nar_pad(%n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : i64
  %c0 = arith.constant 0 : i64
  %rem = arith.remui %n, %c8 : i64
  %need = arith.subi %c8, %rem : i64
  %nz = arith.cmpi ne, %rem, %c0 : i64
  %k = arith.select %nz, %need, %c0 : i64
  %ki = arith.index_cast %k : i64 to index
  %c0i = arith.constant 0 : index
  %zg = memref.get_global @nar_zeros : memref<8xi8>
  %zeros = trikeshed.text %zg : memref<8xi8> -> !b
  %part = trikeshed.slice %zeros[%c0i, %ki] : !b -> !b
  %od = func.call @nar_desc(%into, %k) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %part, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// str: the length prefix u64(n), the n bytes at p, then the pad -- one combine of the three lazy parts, one drain into
// `into` (room for 8 + n + pad).  Returns 8 + n + pad.
func.func @mlnix_nar_str(%p: !llvm.ptr, %n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : index
  %len8 = trikeshed.series %c8 : !b {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c8i = arith.constant 8 : i64
    %sh = arith.muli %i64, %c8i : i64
    %v = arith.shrui %n, %sh : i64
    %byte = arith.trunci %v : i64 to i8
    trikeshed.yield %byte : i8
  }
  %ds = func.call @nar_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m
  %xs = builtin.unrealized_conversion_cast %ms : !m to !b
  %ni = arith.index_cast %n : i64 to index
  %c0 = arith.constant 0 : index
  %body = trikeshed.slice %xs[%c0, %ni] : !b -> !b
  %c864 = arith.constant 8 : i64
  %c064 = arith.constant 0 : i64
  %rem = arith.remui %n, %c864 : i64
  %need = arith.subi %c864, %rem : i64
  %nz = arith.cmpi ne, %rem, %c064 : i64
  %k = arith.select %nz, %need, %c064 : i64
  %ki = arith.index_cast %k : i64 to index
  %zg = memref.get_global @nar_zeros : memref<8xi8>
  %zeros = trikeshed.text %zg : memref<8xi8> -> !b
  %pad = trikeshed.slice %zeros[%c0, %ki] : !b -> !b
  %head = trikeshed.combine %len8, %body : !b, !b -> !b
  %all = trikeshed.combine %head, %pad : !b, !b -> !b
  %total = arith.addi %ni, %c8 : index
  %totalp = arith.addi %total, %ki : index
  %total64 = arith.index_cast %totalp : index to i64
  %od = func.call @nar_desc(%into, %total64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %all, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// tok: the constant token `id` framed as str would frame it.  The token's bytes are a slice of the constant blob; its
// address goes to the str entry beside it, so the framing composition is written once.
func.func @mlnix_nar_tok(%id: i64, %into: !llvm.ptr) -> i64 {
  %idi = arith.index_cast %id : i64 to index
  %og = memref.get_global @nar_toff : memref<14xi32>
  %offs = trikeshed.text %og : memref<14xi32> -> !i32s
  %off32 = trikeshed.at %offs[%idi] : !i32s, index -> i32
  %off = arith.index_cast %off32 : i32 to index
  %lg = memref.get_global @nar_tlen : memref<14xi32>
  %lens = trikeshed.text %lg : memref<14xi32> -> !i32s
  %len32 = trikeshed.at %lens[%idi] : !i32s, index -> i32
  %len64 = arith.extui %len32 : i32 to i64
  %tg = memref.get_global @nar_tokens : memref<79xi8>
  %base = memref.extract_aligned_pointer_as_index %tg : memref<79xi8> -> index
  %at = arith.addi %base, %off : index
  %at64 = arith.index_cast %at : index to i64
  %p = llvm.inttoptr %at64 : i64 to !llvm.ptr
  %r = func.call @mlnix_nar_str(%p, %len64, %into) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  return %r : i64
}
