// The JSON byte emission hollowed out of lib/Eval/Formats.cpp: JsonOut::putInt and JsonOut::putString.
// The C++ keeps the JsonOut interface (a growing run of bytes) and the recursion/forcing/throws of printValueAsJSON;
// the digits of an integer and the escaping of a string are here, in trikeshed.fold / series / combine / combineAll /
// slice / text / at / size / drain, lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).  Both entries drain into room the caller reserved (the mlnixci builder's
// way): nixev_ts_int writes at most 20 bytes, nixev_ts_escape at most 2 + 6 n, and each returns how many it wrote.
// The escape table is Nix's, not the web reply's (text.mlir): \b and \f for 0x08 and 0x0c, not \u0008 / \u000c.
!text = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// byte b's escape at 6 b, its length at b
memref.global "private" constant @jesc : memref<1536xi8> = dense<"0x5c75303030305c75303030315c75303030325c75303030335c75303030345c75303030355c75303030365c75303030375c62000000005c74000000005c6e000000005c75303030625c66000000005c72000000005c75303030655c75303030665c75303031305c75303031315c75303031325c75303031335c75303031345c75303031355c75303031365c75303031375c75303031385c75303031395c75303031615c75303031625c75303031635c75303031645c75303031655c75303031662000000000002100000000005c22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b00000000003c00000000003d00000000003e00000000003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c5c000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @jesc_len : memref<256xi8> = dense<"0x06060606060606060202020602020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @jpow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>
memref.global "private" constant @jminus : memref<1xi8> = dense<45>
memref.global "private" constant @jquote : memref<1xi8> = dense<34>

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @p_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// x as JSON writes it: '-' when negative, then the digits of the magnitude (the most negative i64's is 2^63, read
// unsigned), drained into `into` (room for 21).  The digit count is a fold over the powers of ten; each digit an
// element of a series; the sign a 0- or 1-byte slice; one combine, one drain.
func.func @nixev_ts_int(%x: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c18 = arith.constant 18 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %d0 = arith.constant 48 : i8
  %neg = arith.cmpi slt, %x, %z : i64
  %minusv = arith.subi %z, %x : i64
  %mag = arith.select %neg, %minusv, %x : i64
  %pg = memref.get_global @jpow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c18] : !s64 -> !s64
  %count = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %p: i64):
    %reach = arith.cmpi uge, %mag, %p : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %digits = trikeshed.series %count : !text {
  ^bb0(%k: index):
    %last = arith.subi %count, %c1 : index
    %e = arith.subi %last, %k : index
    %p = trikeshed.at %powers[%e] : !s64, index -> i64
    %q = arith.divui %mag, %p : i64
    %d = arith.remui %q, %ten : i64
    %d8 = arith.trunci %d : i64 to i8
    %c = arith.addi %d8, %d0 : i8
    trikeshed.yield %c : i8
  }
  %mg = memref.get_global @jminus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !text
  %signs = arith.select %neg, %c1, %c0 : index
  %sign = trikeshed.slice %minus[%c0, %signs] : !text -> !text
  %all = trikeshed.combine %sign, %digits : !text, !text -> !text
  %di = func.call @p_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// s (n bytes at p) as a JSON string: the opening quote, each byte's escape (a slice of one constant table, its length
// in a second), the closing quote -- one combineAll and two combines, drained into `into` (room for 2 + 6 n).
func.func @nixev_ts_escape(%p: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %six = arith.constant 6 : index
  %ds = func.call @p_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m8
  %xs = builtin.unrealized_conversion_cast %ms : !m8 to !text
  %ni = arith.index_cast %n : i64 to index
  %eg = memref.get_global @jesc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @jesc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %escaped, %where = trikeshed.combineAll %ni : !text, !pieces {
  ^bb0(%k: index):
    %b = trikeshed.at %xs[%k] : !text, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %l = trikeshed.at %lengths[%bi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at = arith.muli %bi, %six : index
    %part = trikeshed.slice %table[%at, %li] : !text -> !text
    trikeshed.yield %part : !text
  }
  %qg = memref.get_global @jquote : memref<1xi8>
  %quote = trikeshed.text %qg : memref<1xi8> -> !text
  %q = trikeshed.slice %quote[%c0, %c1] : !text -> !text
  %open = trikeshed.combine %q, %escaped : !text, !text -> !text
  %all = trikeshed.combine %open, %q : !text, !text -> !text
  %di = func.call @p_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}
