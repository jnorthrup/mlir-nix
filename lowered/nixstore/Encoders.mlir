// The pure byte encoders of lib/Store/Hash.cpp hollowed into the TrikeShed dialect: appendBase16, appendNix32 and
// base64Encode.  Hash.cpp keeps only the bridges that size the composite::Text and call these neutral C-ABI entries;
// the encoding algebra is here, in trikeshed.series / at / alpha / drain over a byte series, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Each entry takes the input bytes (ptr, i64 len) and an output buffer with room for the whole encoding, writes the
// encoded chars and returns the output length.  The input is seen as a series<i8> through its strided memref
// descriptor (built inline, as in lowered/nixeval/ListOps.mlir); the digits are a series<i64> of alphabet indices,
// alpha maps each index to its char through the alphabet's constant table (trikeshed.text over a memref.global),
// and drain writes the chars into the caller's buffer.  Nothing throws: the encoders are pure.
//
// Alphabets, byte for byte the C++ ones: hex "0123456789abcdef"; Nix's base32 "0123456789abcdfghijklmnpqrsvwxyz"
// (no e/o/t/u); base64 "ABC...abc...0123456789+/" with '=' at index 64 for the padding cells.
!b = !trikeshed.series<i8>
!q = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @enc_hex : memref<16xi8> =
  dense<[48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102]>
memref.global "private" constant @enc_nix32 : memref<32xi8> =
  dense<[48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 118, 119, 120, 121, 122]>
memref.global "private" constant @enc_b64 : memref<65xi8> =
  dense<[65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 43, 47, 61]>

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @enc_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// appendBase16: two lower-case hex chars per byte, the high nibble first.  Digit j is nibble j%2 of byte j/2.
func.func @mlnix_base16_encode(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @enc_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %bytes = builtin.unrealized_conversion_cast %mm : !m to !b
  %g = memref.get_global @enc_hex : memref<16xi8>
  %tab = trikeshed.text %g : memref<16xi8> -> !b
  %ni = arith.index_cast %n : i64 to index
  %c2 = arith.constant 2 : index
  %L = arith.muli %ni, %c2 : index
  %digits = trikeshed.series %L : !q {
  ^bb0(%j: index):
    %bi = arith.divui %j, %c2 : index
    %byte = trikeshed.at %bytes[%bi] : !b, index -> i8
    %v = arith.extui %byte : i8 to i64
    %odd = arith.remui %j, %c2 : index
    %odd64 = arith.index_cast %odd : index to i64
    %c4 = arith.constant 4 : i64
    %sh = arith.muli %odd64, %c4 : i64
    %shift = arith.subi %c4, %sh : i64
    %nib = arith.shrui %v, %shift : i64
    %c15 = arith.constant 15 : i64
    %dig = arith.andi %nib, %c15 : i64
    trikeshed.yield %dig : i64
  }
  %chars = trikeshed.alpha %digits : !q -> !b {
  ^bb0(%dig: i64):
    %di = arith.index_cast %dig : i64 to index
    %ch = trikeshed.at %tab[%di] : !b, index -> i8
    trikeshed.yield %ch : i8
  }
  %c2i = arith.constant 2 : i64
  %L64 = arith.muli %n, %c2i : i64
  %od = func.call @enc_desc(%out, %L64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %chars, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// appendNix32: ceil(8n/5) chars, most significant 5-bit group first.  Char p (from the left) is group i = len-1-p:
// b = 5i, bi = b/8, bj = b%8, digit = (d[bi] >> bj | d[bi+1] << (8-bj)) & 31, the next byte read only when bi+1 < n
// (the index is clamped so the read stays in bounds and the contribution is selected to 0 at the last byte).
func.func @mlnix_nix32_encode(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @enc_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %bytes = builtin.unrealized_conversion_cast %mm : !m to !b
  %g = memref.get_global @enc_nix32 : memref<32xi8>
  %tab = trikeshed.text %g : memref<32xi8> -> !b
  %ni = arith.index_cast %n : i64 to index
  %c1 = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c8 = arith.constant 8 : index
  %n8 = arith.muli %ni, %c8 : index
  %n8p4 = arith.addi %n8, %c4 : index
  %len = arith.divui %n8p4, %c5 : index
  %digits = trikeshed.series %len : !q {
  ^bb0(%pos: index):
    %lm1 = arith.subi %len, %c1 : index
    %i = arith.subi %lm1, %pos : index
    %b = arith.muli %i, %c5 : index
    %bi = arith.divui %b, %c8 : index
    %bj = arith.remui %b, %c8 : index
    %byte = trikeshed.at %bytes[%bi] : !b, index -> i8
    %v = arith.extui %byte : i8 to i64
    %bj64 = arith.index_cast %bj : index to i64
    %c8i = arith.constant 8 : i64
    %lo = arith.shrui %v, %bj64 : i64
    %bip1 = arith.addi %bi, %c1 : index
    %nm1 = arith.subi %ni, %c1 : index
    %valid = arith.cmpi ult, %bip1, %ni : index
    %safe = arith.minsi %bip1, %nm1 : index
    %nb = trikeshed.at %bytes[%safe] : !b, index -> i8
    %nv = arith.extui %nb : i8 to i64
    %sh = arith.subi %c8i, %bj64 : i64
    %hi = arith.shli %nv, %sh : i64
    %zero = arith.constant 0 : i64
    %hic = arith.select %valid, %hi, %zero : i64
    %c = arith.ori %lo, %hic : i64
    %c31 = arith.constant 31 : i64
    %dig = arith.andi %c, %c31 : i64
    trikeshed.yield %dig : i64
  }
  %chars = trikeshed.alpha %digits : !q -> !b {
  ^bb0(%dig: i64):
    %di = arith.index_cast %dig : i64 to index
    %ch = trikeshed.at %tab[%di] : !b, index -> i8
    trikeshed.yield %ch : i8
  }
  %len64 = arith.index_cast %len : index to i64
  %od = func.call @enc_desc(%out, %len64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %chars, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// base64Encode: 4 chars per 3-byte group, '=' padding to a multiple of 4.  Char j is sextet k = j%4 of group g = j/4:
// the group's three bytes (0 past the input) form a 24-bit word, sextet = (word >> (18-6k)) & 63.  The chars from
// ceil(4n/3) on carry no data and take alphabet index 64, '='.  This matches the C++ bit-stream encoder exactly,
// including the last partial group's shifted tail.
func.func @mlnix_base64_encode(%p: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %d = func.call @enc_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %bytes = builtin.unrealized_conversion_cast %mm : !m to !b
  %g = memref.get_global @enc_b64 : memref<65xi8>
  %tab = trikeshed.text %g : memref<65xi8> -> !b
  %ni = arith.index_cast %n : i64 to index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %np2 = arith.addi %ni, %c2 : index
  %groups = arith.divui %np2, %c3 : index
  %L = arith.muli %groups, %c4 : index
  %n4 = arith.muli %ni, %c4 : index
  %n4p2 = arith.addi %n4, %c2 : index
  %real = arith.divui %n4p2, %c3 : index
  %digits = trikeshed.series %L : !q {
  ^bb0(%j: index):
    %gr = arith.divui %j, %c4 : index
    %k = arith.remui %j, %c4 : index
    %base = arith.muli %gr, %c3 : index
    %nm1 = arith.subi %ni, %c1 : index
    %zero = arith.constant 0 : i64
    // byte 0 of the group, 0 when past the input (the clamped index keeps the read in bounds)
    %v0 = arith.cmpi ult, %base, %ni : index
    %s0 = arith.minsi %base, %nm1 : index
    %b0 = trikeshed.at %bytes[%s0] : !b, index -> i8
    %b0v = arith.extui %b0 : i8 to i64
    %x0 = arith.select %v0, %b0v, %zero : i64
    // byte 1
    %i1 = arith.addi %base, %c1 : index
    %v1 = arith.cmpi ult, %i1, %ni : index
    %s1 = arith.minsi %i1, %nm1 : index
    %b1 = trikeshed.at %bytes[%s1] : !b, index -> i8
    %b1v = arith.extui %b1 : i8 to i64
    %x1 = arith.select %v1, %b1v, %zero : i64
    // byte 2
    %i2 = arith.addi %base, %c2 : index
    %v2 = arith.cmpi ult, %i2, %ni : index
    %s2 = arith.minsi %i2, %nm1 : index
    %b2 = trikeshed.at %bytes[%s2] : !b, index -> i8
    %b2v = arith.extui %b2 : i8 to i64
    %x2 = arith.select %v2, %b2v, %zero : i64
    %c16 = arith.constant 16 : i64
    %c8i = arith.constant 8 : i64
    %t0 = arith.shli %x0, %c16 : i64
    %t1 = arith.shli %x1, %c8i : i64
    %w0 = arith.ori %t0, %t1 : i64
    %word = arith.ori %w0, %x2 : i64
    %k64 = arith.index_cast %k : index to i64
    %c6 = arith.constant 6 : i64
    %c18 = arith.constant 18 : i64
    %ks = arith.muli %k64, %c6 : i64
    %sh = arith.subi %c18, %ks : i64
    %sext = arith.shrui %word, %sh : i64
    %c63 = arith.constant 63 : i64
    %dig = arith.andi %sext, %c63 : i64
    %pad = arith.cmpi uge, %j, %real : index
    %c64 = arith.constant 64 : i64
    %r = arith.select %pad, %c64, %dig : i64
    trikeshed.yield %r : i64
  }
  %chars = trikeshed.alpha %digits : !q -> !b {
  ^bb0(%dig: i64):
    %di = arith.index_cast %dig : i64 to index
    %ch = trikeshed.at %tab[%di] : !b, index -> i8
    trikeshed.yield %ch : i8
  }
  %L64 = arith.index_cast %L : index to i64
  %od = func.call @enc_desc(%out, %L64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %chars, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}
