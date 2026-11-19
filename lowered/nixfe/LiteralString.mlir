// The Nix string-literal escaping hollowed out of lib/Frontend/Source.cpp: nixfe::printLiteralString.
// The C++ keeps the interface (a growing Text) and reserves room; the quoting and per-byte escaping are here, in
// trikeshed.combineAll / slice / at / text / combine / drain over a constant escape table, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).  The entry
// drains into room the caller reserved (2 + 2 n: two quotes, at most two bytes a byte) and returns how many it wrote.
// Nix literal escaping: " -> \", \ -> \\, \n \r \t -> \n \r \t, and a '$' immediately before '{' -> \$ (the '{'
// itself stays raw); every other byte passes through.  The '$' case is the one context-dependent rule: the table holds
// "\$" for '$', and when the next byte is not '{' the op slices just that entry's second byte (the raw '$').
!text = !trikeshed.series<i8>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// byte b's escape at 2 b, its length at b
memref.global "private" constant @lesc : memref<512xi8> = dense<"0x0000010002000300040005000600070008005c745c6e0b000c005c720e000f0010001100120013001400150016001700180019001a001b001c001d001e001f00200021005c2223005c24250026002700280029002a002b002c002d002e002f0030003100320033003400350036003700380039003a003b003c003d003e003f0040004100420043004400450046004700480049004a004b004c004d004e004f0050005100520053005400550056005700580059005a005b005c5c5d005e005f0060006100620063006400650066006700680069006a006b006c006d006e006f0070007100720073007400750076007700780079007a007b007c007d007e007f0080008100820083008400850086008700880089008a008b008c008d008e008f0090009100920093009400950096009700980099009a009b009c009d009e009f00a000a100a200a300a400a500a600a700a800a900aa00ab00ac00ad00ae00af00b000b100b200b300b400b500b600b700b800b900ba00bb00bc00bd00be00bf00c000c100c200c300c400c500c600c700c800c900ca00cb00cc00cd00ce00cf00d000d100d200d300d400d500d600d700d800d900da00db00dc00dd00de00df00e000e100e200e300e400e500e600e700e800e900ea00eb00ec00ed00ee00ef00f000f100f200f300f400f500f600f700f800f900fa00fb00fc00fd00fe00ff00">
memref.global "private" constant @lesc_len : memref<256xi8> = dense<"0x01010101010101010102020101020101010101010101010101010101010101010101020102010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @ls_quote : memref<1xi8> = dense<34>

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @ls_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// s (n bytes at p) as a Nix string literal: the opening quote, each byte's escape (a slice of one constant table, its
// length in a second; '$' before '{' escapes, otherwise raw), the closing quote -- one combineAll and two combines,
// drained into `into` (room for 2 + 2 n).
func.func @nixfe_ts_litstr(%p: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c36 = arith.constant 36 : index
  %c123 = arith.constant 123 : i8
  %false = arith.constant 0 : i1
  %ds = func.call @ls_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m8
  %xs = builtin.unrealized_conversion_cast %ms : !m8 to !text
  %ni = arith.index_cast %n : i64 to index
  %eg = memref.get_global @lesc : memref<512xi8>
  %table = trikeshed.text %eg : memref<512xi8> -> !text
  %lg = memref.get_global @lesc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %escaped, %parts = trikeshed.combineAll %ni : !text, !trikeshed.series<!trikeshed.twinpacked<i32>> {
  ^bb0(%k: index):
    %b = trikeshed.at %xs[%k] : !text, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %l = trikeshed.at %lengths[%bi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %at2 = arith.muli %bi, %c2 : index
    // a '$' not immediately before '{' is written raw: the second byte of its "\$" table entry
    %isD = arith.cmpi eq, %bi, %c36 : index
    %kp1 = arith.addi %k, %c1 : index
    %last = arith.subi %ni, %c1 : index
    %idx = arith.minui %kp1, %last : index
    %nb = trikeshed.at %xs[%idx] : !text, index -> i8
    %isB = arith.cmpi eq, %nb, %c123 : i8
    %hasNext = arith.cmpi ult, %kp1, %ni : index
    %followed = arith.andi %hasNext, %isB : i1
    %notF = arith.cmpi eq, %followed, %false : i1
    %rawD = arith.andi %isD, %notF : i1
    %at2p1 = arith.addi %at2, %c1 : index
    %start = arith.select %rawD, %at2p1, %at2 : index
    %len = arith.select %rawD, %c1, %li : index
    %part = trikeshed.slice %table[%start, %len] : !text -> !text
    trikeshed.yield %part : !text
  }
  %qg = memref.get_global @ls_quote : memref<1xi8>
  %quote = trikeshed.text %qg : memref<1xi8> -> !text
  %q = trikeshed.slice %quote[%c0, %c1] : !text -> !text
  %open = trikeshed.combine %q, %escaped : !text, !text -> !text
  %all = trikeshed.combine %open, %q : !text, !text -> !text
  %di = func.call @ls_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}
