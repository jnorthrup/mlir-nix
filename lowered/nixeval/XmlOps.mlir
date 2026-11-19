// The XML byte emission hollowed out of lib/Eval/Formats.cpp's XMLWriter (the indent, the '<'/'</' prefix, the name,
// the attributes and the suffix of every tag line).  The C++ keeps the XMLWriter interface (the attribute rows and the
// element stack) and the recursion/forcing/CallDepth/addTrace/drvsSeen of toXML; one tag line's bytes are here, in
// trikeshed.series / slice / text / combine / combineAll / at / drain over a constant escape table, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).  The entry drains
// into room the caller reserved (the mlnixci builder's way) and returns how many bytes it wrote.
//
// nixev_ts_xml_tag(kind, depth, name, nn, keys, vals, nrows, into, cap): kind 0 open ('<name attrs>\n'), 1 close
// ('</name>\n'), 2 empty ('<name attrs />\n'); depth indents 2*depth spaces.  keys/vals are composite::Chars windows
// (16 bytes: u32 count @0, const char *data @8) of the rows' names and values, already sorted by name in the bridge.
// Each attribute value is escaped as Nix escapes it: " < > & and newline to &quot; &lt; &gt; &amp; &#xA;, every other
// byte raw (the apostrophe, tab and carriage return are NOT escaped).  The escape table is 256 rows of 6 bytes (row b at
// 6b) with a 256-byte length table; a value is one combineAll of slices of it, nested in the per-row combineAll.
!text = !trikeshed.series<i8>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// byte b's escape at 6b, its length at b
memref.global "private" constant @xesc : memref<1536xi8> = dense<"0x000000000000010000000000020000000000030000000000040000000000050000000000060000000000070000000000080000000000090000000000262378413b000b00000000000c00000000000d00000000000e00000000000f00000000001000000000001100000000001200000000001300000000001400000000001500000000001600000000001700000000001800000000001900000000001a00000000001b00000000001c00000000001d00000000001e00000000001f00000000002000000000002100000000002671756f743b23000000000024000000000025000000000026616d703b002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b0000000000266c743b00003d00000000002667743b00003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c00000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @xesc_len : memref<256xi8> = dense<"0x01010101010101010101050101010101010101010101010101010101010101010101060101010501010101010101010101010101010101010101010104010401010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @xlt : memref<2xi8> = dense<[60, 47]>          // "</"
memref.global "private" constant @xend : memref<4xi8> = dense<[32, 47, 62, 10]>  // " />\n"
memref.global "private" constant @xeq : memref<2xi8> = dense<[61, 34]>          // "=\""
memref.global "private" constant @xsp : memref<1xi8> = dense<32>               // " "
memref.global "private" constant @xq : memref<1xi8> = dense<34>                // "\""

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @xml_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixev_ts_xml_tag(%kind: i64, %depth: i64, %name: !llvm.ptr, %nn: i64,
                            %keys: !llvm.ptr, %vals: !llvm.ptr, %nrows: i64,
                            %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %c4i = arith.constant 4 : index
  %six = arith.constant 6 : index
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  // the indent: 2*depth spaces, a series
  %d2 = arith.muli %depth, %c2 : i64
  %d2i = arith.index_cast %d2 : i64 to index
  %indent = trikeshed.series %d2i : !text {
  ^bb0(%ik: index):
    %sp = arith.constant 32 : i8
    trikeshed.yield %sp : i8
  }
  // the prefix: "</" when closing (2 bytes), else "<" (1)
  %isClose = arith.cmpi eq, %kind, %c1 : i64
  %plen = arith.select %isClose, %c2i, %c1i : index
  %ltg = memref.get_global @xlt : memref<2xi8>
  %lt = trikeshed.text %ltg : memref<2xi8> -> !text
  %prefix = trikeshed.slice %lt[%c0i, %plen] : !text -> !text
  // the name: a window of the bytes the bridge passed
  %nd = func.call @xml_desc8(%name, %nn) : (!llvm.ptr, i64) -> !d
  %nm = builtin.unrealized_conversion_cast %nd : !d to !m8
  %ns = builtin.unrealized_conversion_cast %nm : !m8 to !text
  %nmi = arith.index_cast %nn : i64 to index
  %namev = trikeshed.slice %ns[%c0i, %nmi] : !text -> !text
  // the constant pieces of an attribute row
  %eg = memref.get_global @xesc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @xesc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %spg = memref.get_global @xsp : memref<1xi8>
  %spt = trikeshed.text %spg : memref<1xi8> -> !text
  %space = trikeshed.slice %spt[%c0i, %c1i] : !text -> !text
  %eqg = memref.get_global @xeq : memref<2xi8>
  %eqt = trikeshed.text %eqg : memref<2xi8> -> !text
  %eq = trikeshed.slice %eqt[%c0i, %c2i] : !text -> !text
  %qg = memref.get_global @xq : memref<1xi8>
  %qt = trikeshed.text %qg : memref<1xi8> -> !text
  %quote = trikeshed.slice %qt[%c0i, %c1i] : !text -> !text
  // the attributes: one part a row, ' ' + name + '="' + escaped value + '"'
  %nri = arith.index_cast %nrows : i64 to index
  %attrs, %aw = trikeshed.combineAll %nri : !text, !pieces {
  ^bb0(%rk: index):
    %rk64 = arith.index_cast %rk : index to i64
    %roff = arith.muli %rk64, %c16 : i64
    // the key window (Chars at keys + 16k)
    %kp = llvm.getelementptr %keys[%roff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kn32 = llvm.load %kp : !llvm.ptr -> i32
    %kn = llvm.zext %kn32 : i32 to i64
    %kni = arith.index_cast %kn : i64 to index
    %kdp = llvm.getelementptr %kp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kdata = llvm.load %kdp : !llvm.ptr -> !llvm.ptr
    %kd = func.call @xml_desc8(%kdata, %kn) : (!llvm.ptr, i64) -> !d
    %km = builtin.unrealized_conversion_cast %kd : !d to !m8
    %ks = builtin.unrealized_conversion_cast %km : !m8 to !text
    %key = trikeshed.slice %ks[%c0i, %kni] : !text -> !text
    // the value window (Chars at vals + 16k)
    %vp = llvm.getelementptr %vals[%roff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vn32 = llvm.load %vp : !llvm.ptr -> i32
    %vn = llvm.zext %vn32 : i32 to i64
    %vni = arith.index_cast %vn : i64 to index
    %vdp = llvm.getelementptr %vp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vdata = llvm.load %vdp : !llvm.ptr -> !llvm.ptr
    %vd = func.call @xml_desc8(%vdata, %vn) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m8
    %vs = builtin.unrealized_conversion_cast %vm : !m8 to !text
    // the escaped value: a slice of the table a byte, its length in the second table
    %escaped, %ew = trikeshed.combineAll %vni : !text, !pieces {
    ^bb0(%ej: index):
      %b = trikeshed.at %vs[%ej] : !text, index -> i8
      %bi = arith.index_castui %b : i8 to index
      %l = trikeshed.at %lengths[%bi] : !text, index -> i8
      %li = arith.index_castui %l : i8 to index
      %at = arith.muli %bi, %six : index
      %part = trikeshed.slice %table[%at, %li] : !text -> !text
      trikeshed.yield %part : !text
    }
    %r1 = trikeshed.combine %space, %key : !text, !text -> !text
    %r2 = trikeshed.combine %r1, %eq : !text, !text -> !text
    %r3 = trikeshed.combine %r2, %escaped : !text, !text -> !text
    %row = trikeshed.combine %r3, %quote : !text, !text -> !text
    trikeshed.yield %row : !text
  }
  // the suffix: " />\n" when empty (4 bytes from 0), else ">\n" (2 bytes from 2)
  %isEmpty = arith.cmpi eq, %kind, %c2 : i64
  %soff = arith.select %isEmpty, %c0i, %c2i : index
  %slen = arith.select %isEmpty, %c4i, %c2i : index
  %endg = memref.get_global @xend : memref<4xi8>
  %endt = trikeshed.text %endg : memref<4xi8> -> !text
  %suffix = trikeshed.slice %endt[%soff, %slen] : !text -> !text
  // one combine of the whole line, one drain into the reserved room
  %a1 = trikeshed.combine %indent, %prefix : !text, !text -> !text
  %a2 = trikeshed.combine %a1, %namev : !text, !text -> !text
  %a3 = trikeshed.combine %a2, %attrs : !text, !text -> !text
  %all = trikeshed.combine %a3, %suffix : !text, !text -> !text
  %di = func.call @xml_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}
