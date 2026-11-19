// The pure byte decoders of lib/Store/Hash.cpp hollowed into the TrikeShed dialect: nix32Decode and base64Decode.
// Hash.cpp keeps only the bridges that size the composite::Text and turn the validity flag into the composite::Maybe
// (the parseRest error wording -- "invalid nix32 hash", "invalid SRI hash", the wrong-length message -- stays in C++);
// the decoding algebra is here, in trikeshed.at over the input series<i8>, a constant reverse-alphabet table
// (memref.global) and guarded byte stores, lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).  Each entry returns 1 when valid (bytes written), 0 when invalid.
//
// nix32: the reverse of appendNix32 -- chars read right-to-left, digit d of char k goes to bit b = 5k: byte i = b/8 gets
// d << (b%8), byte i+1 gets d >> (8 - b%8); a char outside the alphabet, i >= size, or high bits past the last byte are
// invalid.  The output buffer is zero-filled by the caller (Text::resize), so the contributions are OR-ed in, as before.
// base64: the reverse of base64Encode -- a 6-bit accumulator, '=' ends the data, '\n' is skipped, any other byte outside
// the alphabet is invalid; a byte is emitted whenever the accumulator holds >= 8 bits.  The count is written to *outlen.
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @dec_nix32 : memref<256xi8> =
  dense<[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 10, 11, 12, 13, -1, 14, 15, 16, 17, 18, 19, 20, 21, 22, -1, 23, 24, 25, 26, -1, -1, 27, 28, 29, 30, 31, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]>
memref.global "private" constant @dec_b64 : memref<256xi8> =
  dense<[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]>

// the descriptor of n i8 cells at p
func.func private @dec_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @mlnix_nix32_decode(%p: !llvm.ptr, %n: i64, %size: i64, %out: !llvm.ptr) -> i32 {
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %true = arith.constant true
  %c5 = arith.constant 5 : index
  %c8i = arith.constant 8 : index
  %c8 = arith.constant 8 : i32
  %c0_32 = arith.constant 0 : i32
  %d = func.call @dec_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %tab = memref.get_global @dec_nix32 : memref<256xi8>
  %ni = arith.index_cast %n : i64 to index
  %sizei = arith.index_cast %size : i64 to index
  %k, %ok = scf.while (%k = %zi, %ok = %true) : (index, i1) -> (index, i1) {
    %in = arith.cmpi ult, %k, %ni : index
    %go = arith.andi %in, %ok : i1
    scf.condition(%go) %k, %ok : index, i1
  } do {
  ^bb0(%k: index, %ok: i1):
    %ci = arith.subi %ni, %k : index
    %ci1 = arith.subi %ci, %oi : index
    %c = trikeshed.at %ss[%ci1] : !s, index -> i8
    %cu = arith.extui %c : i8 to i32
    %cui = arith.index_cast %cu : i32 to index
    %d8 = memref.load %tab[%cui] : memref<256xi8>
    %digit = arith.extsi %d8 : i8 to i32
    %vchar = arith.cmpi sge, %digit, %c0_32 : i32
    %b = arith.muli %k, %c5 : index
    %i = arith.divui %b, %c8i : index
    %j = arith.remui %b, %c8i : index
    %i_ok = arith.cmpi ult, %i, %sizei : index
    %active = arith.andi %vchar, %i_ok : i1
    scf.if %active {
      %j32 = arith.index_cast %j : index to i32
      %shl = arith.shli %digit, %j32 : i32
      %shl8 = arith.trunci %shl : i32 to i8
      %i64 = arith.index_cast %i : index to i64
      %ptr = llvm.getelementptr %out[%i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %old = llvm.load %ptr : !llvm.ptr -> i8
      %new = arith.ori %old, %shl8 : i8
      llvm.store %new, %ptr : i8, !llvm.ptr
    }
    %j32b = arith.index_cast %j : index to i32
    %sh = arith.subi %c8, %j32b : i32
    %hi = arith.shrui %digit, %sh : i32
    %i1 = arith.addi %i, %oi : index
    %hasnext = arith.cmpi ult, %i1, %sizei : index
    %writehi = arith.andi %active, %hasnext : i1
    scf.if %writehi {
      %hi8 = arith.trunci %hi : i32 to i8
      %i164 = arith.index_cast %i1 : index to i64
      %ptr1 = llvm.getelementptr %out[%i164] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %old1 = llvm.load %ptr1 : !llvm.ptr -> i8
      %new1 = arith.ori %old1, %hi8 : i8
      llvm.store %new1, %ptr1 : i8, !llvm.ptr
    }
    %hinz = arith.cmpi ne, %hi, %c0_32 : i32
    %nohas = arith.xori %hasnext, %true : i1
    %ov1 = arith.andi %active, %nohas : i1
    %overflow = arith.andi %ov1, %hinz : i1
    %nvchar = arith.xori %vchar, %true : i1
    %ni_ok = arith.xori %i_ok, %true : i1
    %inv3 = arith.ori %nvchar, %ni_ok : i1
    %invalid = arith.ori %inv3, %overflow : i1
    %ninv = arith.xori %invalid, %true : i1
    %ok2 = arith.andi %ok, %ninv : i1
    %k2 = arith.addi %k, %oi : index
    scf.yield %k2, %ok2 : index, i1
  }
  %r = arith.extui %ok : i1 to i32
  return %r : i32
}

func.func @mlnix_base64_decode(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr, %outlen: !llvm.ptr) -> i32 {
  %zi = arith.constant 0 : index
  %oi = arith.constant 1 : index
  %true = arith.constant true
  %false = arith.constant false
  %c0_64 = arith.constant 0 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %cff = arith.constant 255 : i64
  %c0_32 = arith.constant 0 : i32
  %eq = arith.constant 61 : i8
  %nl = arith.constant 10 : i8
  %d = func.call @dec_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %ss = builtin.unrealized_conversion_cast %mm : !m to !s
  %tab = memref.get_global @dec_b64 : memref<256xi8>
  %ni = arith.index_cast %n : i64 to index
  %k, %acc, %bits, %w, %ok, %stop = scf.while (%k = %zi, %acc = %c0_64, %bits = %c0_64, %w = %zi, %ok = %true, %stop = %false) : (index, i64, i64, index, i1, i1) -> (index, i64, i64, index, i1, i1) {
    %in = arith.cmpi ult, %k, %ni : index
    %nst = arith.xori %stop, %true : i1
    %go1 = arith.andi %in, %ok : i1
    %go = arith.andi %go1, %nst : i1
    scf.condition(%go) %k, %acc, %bits, %w, %ok, %stop : index, i64, i64, index, i1, i1
  } do {
  ^bb0(%k: index, %acc: i64, %bits: i64, %w: index, %ok: i1, %stop: i1):
    %c = trikeshed.at %ss[%k] : !s, index -> i8
    %is_eq = arith.cmpi eq, %c, %eq : i8
    %is_nl = arith.cmpi eq, %c, %nl : i8
    %cu = arith.extui %c : i8 to i32
    %cui = arith.index_cast %cu : i32 to index
    %d8 = memref.load %tab[%cui] : memref<256xi8>
    %digit = arith.extsi %d8 : i8 to i32
    %vchar = arith.cmpi sge, %digit, %c0_32 : i32
    %not_eq = arith.xori %is_eq, %true : i1
    %not_nl = arith.xori %is_nl, %true : i1
    %proc1 = arith.andi %not_eq, %not_nl : i1
    %process = arith.andi %proc1, %vchar : i1
    %nvchar = arith.xori %vchar, %true : i1
    %invalid = arith.andi %proc1, %nvchar : i1
    %digit64 = arith.extsi %digit : i32 to i64
    %bits6 = arith.addi %bits, %c6 : i64
    %dsh = arith.shli %acc, %c6 : i64
    %dnew = arith.ori %dsh, %digit64 : i64
    %ge8 = arith.cmpi sge, %bits6, %c8 : i64
    %emit = arith.andi %process, %ge8 : i1
    scf.if %emit {
      %shift = arith.subi %bits6, %c8 : i64
      %sh = arith.shrui %dnew, %shift : i64
      %b = arith.andi %sh, %cff : i64
      %b8 = arith.trunci %b : i64 to i8
      %w64 = arith.index_cast %w : index to i64
      %ptr = llvm.getelementptr %out[%w64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store %b8, %ptr : i8, !llvm.ptr
    }
    %bitsub = arith.subi %bits6, %c8 : i64
    %bits_after = arith.select %ge8, %bitsub, %bits6 : i64
    %acc2 = arith.select %process, %dnew, %acc : i64
    %bits2 = arith.select %process, %bits_after, %bits : i64
    %w1 = arith.addi %w, %oi : index
    %w2 = arith.select %emit, %w1, %w : index
    %ninv = arith.xori %invalid, %true : i1
    %ok2 = arith.andi %ok, %ninv : i1
    %stop2 = arith.ori %stop, %is_eq : i1
    %k2 = arith.addi %k, %oi : index
    scf.yield %k2, %acc2, %bits2, %w2, %ok2, %stop2 : index, i64, i64, index, i1, i1
  }
  %w64 = arith.index_cast %w : index to i64
  llvm.store %w64, %outlen : i64, !llvm.ptr
  %r = arith.extui %ok : i1 to i32
  return %r : i32
}
