// The XML byte emission of builtins.toXML: the DRAIN of a fill-drain.  XmlWalk.mlir's walk fills rows (one a tag line,
// in document order); nixev_ts_xml_text composes every row's line -- the indent, the '<'/'</' prefix, the name, the
// attributes with their values escaped or an integer's digits, the suffix -- as one trikeshed.combineAll of the rows
// (each a combine of series / slices / a nested combineAll of the eight attribute slots, each slot's value a combineAll
// over a constant escape table) and drains it once.  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// nixev_ts_xml_text(rows, n, into, cap): rows is n rows of 20 i64 (XmlWalk.mlir's header has the layout: kind, depth,
// the name's window, then slots 0 column, 1 drvPath, 2 ellipsis, 3 line, 4 name, 5 outPath, 6 path, 7 value as
// {bits, length: -1 absent, -2 an integer, else a window}).  Returns the text's length; the bytes are drained into
// `into` only when they fit in cap (the bridge calls once with cap 0, sizes its Text, and calls again).
// kind 0 open ('<name attrs>\n'), 1 close ('</name>\n'), 2 empty ('<name attrs />\n'); depth indents 2*depth spaces.
// Each attribute value is escaped as Nix escapes it: " < > & and newline to &quot; &lt; &gt; &amp; &#xA;, every other
// byte raw (the apostrophe, tab and carriage return are NOT escaped).  The escape table is 256 rows of 6 bytes (row b at
// 6b) with a 256-byte length table.  An integer is '-' when negative and the digits of its magnitude (2^63 read unsigned).
!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// byte b's escape at 6b, its length at b
memref.global "private" constant @xesc : memref<1536xi8> = dense<"0x000000000000010000000000020000000000030000000000040000000000050000000000060000000000070000000000080000000000090000000000262378413b000b00000000000c00000000000d00000000000e00000000000f00000000001000000000001100000000001200000000001300000000001400000000001500000000001600000000001700000000001800000000001900000000001a00000000001b00000000001c00000000001d00000000001e00000000001f00000000002000000000002100000000002671756f743b23000000000024000000000025000000000026616d703b002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b0000000000266c743b00003d00000000002667743b00003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c00000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @xesc_len : memref<256xi8> = dense<"0x01010101010101010101050101010101010101010101010101010101010101010101060101010501010101010101010101010101010101010101010104010401010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @xlt : memref<2xi8> = dense<[60, 47]>          // "</"
memref.global "private" constant @xend : memref<4xi8> = dense<[32, 47, 62, 10]>  // " />\n"
memref.global "private" constant @xq : memref<1xi8> = dense<34>                // "\""
memref.global "private" constant @xminus : memref<1xi8> = dense<45>            // "-"
// slot s's ' key="' at its offset: column drvPath ellipsis line name outPath path value
memref.global "private" constant @xkey : memref<69xi8> = dense<"0x20636f6c756d6e3d2220647276506174683d2220656c6c69707369733d22206c696e653d22206e616d653d22206f7574506174683d2220706174683d222076616c75653d22">
memref.global "private" constant @xkey_off : memref<8xi32> = dense<[0, 9, 19, 30, 37, 44, 54, 61]>
memref.global "private" constant @xkey_len : memref<8xi32> = dense<[9, 10, 11, 7, 7, 10, 7, 8]>
memref.global "private" constant @xpow : memref<19xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000]>

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

func.func @nixev_ts_xml_text(%rows: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c2i = arith.constant 2 : index
  %c4i = arith.constant 4 : index
  %c8i = arith.constant 8 : index
  %c18i = arith.constant 18 : index
  %six = arith.constant 6 : index
  %z = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c160 = arith.constant 160 : i64
  %ten = arith.constant 10 : i64
  %absent = arith.constant -1 : i64
  %int = arith.constant -2 : i64
  %d0 = arith.constant 48 : i8
  // the constant texts
  %ltg = memref.get_global @xlt : memref<2xi8>
  %lt = trikeshed.text %ltg : memref<2xi8> -> !text
  %eg = memref.get_global @xesc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @xesc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %qg = memref.get_global @xq : memref<1xi8>
  %qt = trikeshed.text %qg : memref<1xi8> -> !text
  %mg = memref.get_global @xminus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !text
  %kg = memref.get_global @xkey : memref<69xi8>
  %keys = trikeshed.text %kg : memref<69xi8> -> !text
  %kog = memref.get_global @xkey_off : memref<8xi32>
  %koffs = trikeshed.text %kog : memref<8xi32> -> !s32
  %klg = memref.get_global @xkey_len : memref<8xi32>
  %klens = trikeshed.text %klg : memref<8xi32> -> !s32
  %pg = memref.get_global @xpow : memref<19xi64>
  %powers = trikeshed.text %pg : memref<19xi64> -> !s64
  %above = trikeshed.slice %powers[%c1i, %c18i] : !s64 -> !s64
  %endg = memref.get_global @xend : memref<4xi8>
  %endt = trikeshed.text %endg : memref<4xi8> -> !text
  // the document: one line a row
  %ni = arith.index_cast %n : i64 to index
  %doc, %dw = trikeshed.combineAll %ni : !text, !pieces {
  ^bb0(%rk: index):
    %rk64 = arith.index_cast %rk : index to i64
    %roff = arith.muli %rk64, %c160 : i64
    %rp = llvm.getelementptr %rows[%roff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kind = llvm.load %rp : !llvm.ptr -> i64
    %dpp = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %depth = llvm.load %dpp : !llvm.ptr -> i64
    %npp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %name = llvm.load %npp : !llvm.ptr -> !llvm.ptr
    %nlp = llvm.getelementptr %rp[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nn = llvm.load %nlp : !llvm.ptr -> i64
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
    %prefix = trikeshed.slice %lt[%c0i, %plen] : !text -> !text
    // the name: a window of the row's word
    %nd = func.call @xml_desc8(%name, %nn) : (!llvm.ptr, i64) -> !d
    %nm = builtin.unrealized_conversion_cast %nd : !d to !m8
    %ns = builtin.unrealized_conversion_cast %nm : !m8 to !text
    %nmi = arith.index_cast %nn : i64 to index
    %namev = trikeshed.slice %ns[%c0i, %nmi] : !text -> !text
    // the attributes: one part a slot, ' key="' + the escaped window or the integer's digits + '"', empty when absent
    %attrs, %aw = trikeshed.combineAll %c8i : !text, !pieces {
    ^bb0(%s: index):
      %s64 = arith.index_cast %s : index to i64
      %so = arith.muli %s64, %c16 : i64
      %bo = arith.addi %so, %c32 : i64
      %bp = llvm.getelementptr %rp[%bo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %bits = llvm.load %bp : !llvm.ptr -> i64
      %lp = llvm.getelementptr %bp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %len = llvm.load %lp : !llvm.ptr -> i64
      %present = arith.cmpi ne, %len, %absent : i64
      %isInt = arith.cmpi eq, %len, %int : i64
      %isWin = arith.cmpi sge, %len, %z : i64
      %ko = trikeshed.at %koffs[%s] : !s32, index -> i32
      %kl = trikeshed.at %klens[%s] : !s32, index -> i32
      %koi = arith.index_castui %ko : i32 to index
      %kli = arith.index_castui %kl : i32 to index
      %klen = arith.select %present, %kli, %c0i : index
      %key = trikeshed.slice %keys[%koi, %klen] : !text -> !text
      // a window's bytes escaped: a slice of the table a byte, its length in the second table
      %wlen = arith.select %isWin, %len, %z : i64
      %wli = arith.index_cast %wlen : i64 to index
      %wp = llvm.inttoptr %bits : i64 to !llvm.ptr
      %wd = func.call @xml_desc8(%wp, %wlen) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m8
      %vs = builtin.unrealized_conversion_cast %wm : !m8 to !text
      %escaped, %ew = trikeshed.combineAll %wli : !text, !pieces {
      ^bb0(%ej: index):
        %b = trikeshed.at %vs[%ej] : !text, index -> i8
        %bi = arith.index_castui %b : i8 to index
        %l = trikeshed.at %lengths[%bi] : !text, index -> i8
        %li = arith.index_castui %l : i8 to index
        %at = arith.muli %bi, %six : index
        %part = trikeshed.slice %table[%at, %li] : !text -> !text
        trikeshed.yield %part : !text
      }
      // an integer's sign and digits: the count a fold over the powers of ten, each digit an element of a series
      %neg = arith.cmpi slt, %bits, %z : i64
      %minusv = arith.subi %z, %bits : i64
      %mag = arith.select %neg, %minusv, %bits : i64
      %count = trikeshed.fold %above, %c1i : !s64, index -> index {
      ^bb0(%acc: index, %p: i64):
        %reach = arith.cmpi uge, %mag, %p : i64
        %more = arith.addi %acc, %c1i : index
        %rr = arith.select %reach, %more, %acc : index
        trikeshed.yield %rr : index
      }
      %dcount = arith.select %isInt, %count, %c0i : index
      %digits = trikeshed.series %dcount : !text {
      ^bb0(%k: index):
        %last = arith.subi %dcount, %c1i : index
        %e = arith.subi %last, %k : index
        %pw = trikeshed.at %powers[%e] : !s64, index -> i64
        %q = arith.divui %mag, %pw : i64
        %dg = arith.remui %q, %ten : i64
        %d8 = arith.trunci %dg : i64 to i8
        %c = arith.addi %d8, %d0 : i8
        trikeshed.yield %c : i8
      }
      %sneg = arith.andi %isInt, %neg : i1
      %signs = arith.select %sneg, %c1i, %c0i : index
      %sign = trikeshed.slice %minus[%c0i, %signs] : !text -> !text
      %ql = arith.select %present, %c1i, %c0i : index
      %quote = trikeshed.slice %qt[%c0i, %ql] : !text -> !text
      %slot = trikeshed.combine %key, %escaped, %sign, %digits, %quote : !text, !text, !text, !text, !text -> !text
      trikeshed.yield %slot : !text
    }
    // the suffix: " />\n" when empty (4 bytes from 0), else ">\n" (2 bytes from 2)
    %isEmpty = arith.cmpi eq, %kind, %c2 : i64
    %soff = arith.select %isEmpty, %c0i, %c2i : index
    %slen = arith.select %isEmpty, %c4i, %c2i : index
    %suffix = trikeshed.slice %endt[%soff, %slen] : !text -> !text
    %line = trikeshed.combine %indent, %prefix, %namev, %attrs, %suffix : !text, !text, !text, !text, !text -> !text
    trikeshed.yield %line : !text
  }
  // one drain into the reserved room, when it fits
  %sz = trikeshed.size %doc : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @xml_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m8
    %end = trikeshed.drain %doc, %mi : !text, !m8 -> index
  }
  return %szi : i64
}
