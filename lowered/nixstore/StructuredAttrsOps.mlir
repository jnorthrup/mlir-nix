// lib/Store/StructuredAttrs.cpp's structuredAttrsFiles, whole: the (.attrs.json, .attrs.sh) pair a structured-attrs
// derivation's builder reads, as upstream's ParsedDerivation / writeStructuredAttrsShell writes it, from __json.  The C++
// keeps the rooms the bytes land in and the words of the two errors; nothing of the reading or the writing.  In order:
//
//   the reading   confix.checked over __json fills the index's lane (a row is open, close, tag and the row it is in),
//                 checked as builtins.fromJSON's reader checks JSON (the record's `end` set: an integer past 2^63
//                 and a \u0000 are values here, as nlohmann reads them); the rows are read where the fill left them,
//                 and a row's children are trikeshed.adjacency of the rows they are in, drained for it.
//                 No DOM: a node is a row, its text a window -- a number its span of the source, a string its bytes
//                 decoded by JsonRead.mlir's nixev_json_decode into one room of n bytes.
//   the members   each object's members in key order (trikeshed.sorted over row indices, a region comparing two slices
//                 unsigned; stable, so of equal keys the last in the text is the last of its run, and it is the one kept,
//                 as the sorted DOM's member(k) = val() kept it).  The root gets one member more, `outputs`: the object of
//                 the output names and paths (nodes rows .. rows + nout), last, so it wins over an `outputs` of the text.
//   the rewrites  every string value, every placeholder in turn (rewrites' order), each pass replacing the occurrences
//                 left to right without overlap: the occurrences found (a scan of slices compared), then one combineAll of
//                 the gaps and the replacement, drained once into a room of the new length (fill-drain per pass).
//   the numbers   strtod, then the shell's test of ParsedDerivation's handleSimpleType: ceil((float) f) == (float) f, and
//                 then (int) f written as decimal digits (a trikeshed.series of digits behind a '-' slice, drained into
//                 the number's 11-byte cell).
//   .attrs.json   one walk of the tree into events (open, leaf, close; the comma and the key a member carries), then ONE
//                 combineAll over the events -- the comma, the escaped key and ':', the word or the number's span, the
//                 escaped string -- drained once.  The escape is Nix's JSON table (PrintOps.mlir's: \b \f, \u00xx).
//   .attrs.sh     the root's members whose key is a shell name and whose value is simple, an array of simple values or
//                 an object of them (trikeshed.where over the members), then ONE combineAll of their lines: `declare K=V`,
//                 `declare -a K=(V V )`, `declare -A K=(['k']=V ['k']=V )`, every piece a slice of one word blob, a
//                 window or a combineAll of shell-escape table slices (' as '\''), drained once.
// nixstore_ts_escape is nixstore::jsonEscape's (StorePaths.cpp), with the same table.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!text = !trikeshed.series<i8>
!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
// confix.checked's rows while they are filled (open, close, tag, up), and one column of them
!rows = !trikeshed.lane<i32, i32, i8, i32>
!l32 = !trikeshed.lane<i32>
!l8 = !trikeshed.lane<i8>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the bridge's rooms (StructuredAttrs.cpp): room(ctx, n) n bytes that live until the bridge returns; out(ctx, which, n)
// the n bytes of .attrs.json (0) or .attrs.sh (1)
func.func private @nixsa_room(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsa_out(!llvm.ptr, i64, i64) -> !llvm.ptr
// JsonRead.mlir: the bytes of the string whose quotes are at from and to, its escapes read
func.func private @nixev_json_decode(!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
func.func private @strtod(!llvm.ptr, !llvm.ptr) -> f64

memref.global "private" constant @sa_esc : memref<1536xi8> = dense<"0x5c75303030305c75303030315c75303030325c75303030335c75303030345c75303030355c75303030365c75303030375c62000000005c74000000005c6e000000005c75303030625c66000000005c72000000005c75303030655c75303030665c75303031305c75303031315c75303031325c75303031335c75303031345c75303031355c75303031365c75303031375c75303031385c75303031395c75303031615c75303031625c75303031635c75303031645c75303031655c75303031662000000000002100000000005c22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b00000000003c00000000003d00000000003e00000000003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c5c000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @sa_esc_len : memref<256xi8> = dense<"0x06060606060606060202020602020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @sa_comma : memref<1xi8> = dense<44>
memref.global "private" constant @sa_quote : memref<1xi8> = dense<34>
memref.global "private" constant @sa_jw : memref<17xi8> = dense<"0x5b5d7b7d6e756c6c7472756566616c7365">
memref.global "private" constant @sa_qcolon : memref<2xi8> = dense<"0x223a">
memref.global "private" constant @sa_shw : memref<33xi8> = dense<"0x6465636c617265202d61206465636c617265202d41203d28290a5b5d3d27273120">
memref.global "private" constant @sa_shesc : memref<1024xi8> = dense<"0x000000000100000002000000030000000400000005000000060000000700000008000000090000000a0000000b0000000c0000000d0000000e0000000f000000100000001100000012000000130000001400000015000000160000001700000018000000190000001a0000001b0000001c0000001d0000001e0000001f00000020000000210000002200000023000000240000002500000026000000275c272728000000290000002a0000002b0000002c0000002d0000002e0000002f000000300000003100000032000000330000003400000035000000360000003700000038000000390000003a0000003b0000003c0000003d0000003e0000003f000000400000004100000042000000430000004400000045000000460000004700000048000000490000004a0000004b0000004c0000004d0000004e0000004f000000500000005100000052000000530000005400000055000000560000005700000058000000590000005a0000005b0000005c0000005d0000005e0000005f000000600000006100000062000000630000006400000065000000660000006700000068000000690000006a0000006b0000006c0000006d0000006e0000006f000000700000007100000072000000730000007400000075000000760000007700000078000000790000007a0000007b0000007c0000007d0000007e0000007f000000800000008100000082000000830000008400000085000000860000008700000088000000890000008a0000008b0000008c0000008d0000008e0000008f000000900000009100000092000000930000009400000095000000960000009700000098000000990000009a0000009b0000009c0000009d0000009e0000009f000000a0000000a1000000a2000000a3000000a4000000a5000000a6000000a7000000a8000000a9000000aa000000ab000000ac000000ad000000ae000000af000000b0000000b1000000b2000000b3000000b4000000b5000000b6000000b7000000b8000000b9000000ba000000bb000000bc000000bd000000be000000bf000000c0000000c1000000c2000000c3000000c4000000c5000000c6000000c7000000c8000000c9000000ca000000cb000000cc000000cd000000ce000000cf000000d0000000d1000000d2000000d3000000d4000000d5000000d6000000d7000000d8000000d9000000da000000db000000dc000000dd000000de000000df000000e0000000e1000000e2000000e3000000e4000000e5000000e6000000e7000000e8000000e9000000ea000000eb000000ec000000ed000000ee000000ef000000f0000000f1000000f2000000f3000000f4000000f5000000f6000000f7000000f8000000f9000000fa000000fb000000fc000000fd000000fe000000ff000000">
memref.global "private" constant @sa_shesc_len : memref<256xi8> = dense<"0x01010101010101010101010101010101010101010101010101010101010101010101010101010104010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @sa_cls : memref<256xi8> = dense<"0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002020202020202020202000000000000000101010101010101010101010101010101010101010101010101000000000100010101010101010101010101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000">
memref.global "private" constant @sa_minus : memref<1xi8> = dense<"0x2d">
memref.global "private" constant @sa_outputs : memref<7xi8> = dense<"0x6f757470757473">
memref.global "private" constant @sa_pow10 : memref<11xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000]>

// the descriptor of n bytes at p (a struct, not a memref: returning it allocates nothing and clones nothing); any
// element type: the descriptor of n i64 or i32 cells at p is the same struct
func.func private @nx_sa_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

// word k of the i64 words at p (the record, the record's words)
func.func private @nx_sa_w(%p: !llvm.ptr, %k: i64) -> i64 {
  %q = llvm.getelementptr %p[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %v = llvm.load %q : !llvm.ptr -> i64
  return %v : i64
}

// row j of a SortedMap<Text>'s rows (Store.h: Row {Text first, second}, 32 bytes; a Text is {char *p, uint32 n, cap}):
// the outputs (name, path) and the rewrites (placeholder, path) as the bridges hold them, read in place.  A Text that
// never held a byte has p null; its window is empty, so no byte of it is read.
func.func private @nx_sa_row(%rows: !llvm.ptr, %j: i64) -> (i64, i64, i64, i64) {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %off = arith.muli %j, %c32 : i64
  %r = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fp = llvm.load %r : !llvm.ptr -> i64
  %flp = llvm.getelementptr %r[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %fl32 = llvm.load %flp : !llvm.ptr -> i32
  %fl = arith.extui %fl32 : i32 to i64
  %tpp = llvm.getelementptr %r[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tp = llvm.load %tpp : !llvm.ptr -> i64
  %tlp = llvm.getelementptr %r[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tl32 = llvm.load %tlp : !llvm.ptr -> i32
  %tl = arith.extui %tl32 : i32 to i64
  return %fp, %fl, %tp, %tl : i64, i64, i64, i64
}

// s (n bytes at p) as a JSON string: the opening quote, each byte's escape (a slice of one constant table, its
// length in a second), the closing quote -- one combineAll and two combines, drained into `into` (room 2 + 6 n).
func.func @nixstore_ts_escape(%p: !llvm.ptr, %n: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %six = arith.constant 6 : index
  %ds = func.call @nx_sa_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m8
  %xs = builtin.unrealized_conversion_cast %ms : !m8 to !text
  %ni = arith.index_cast %n : i64 to index
  %eg = memref.get_global @sa_esc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @sa_esc_len : memref<256xi8>
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
  %qg = memref.get_global @sa_quote : memref<1xi8>
  %quote = trikeshed.text %qg : memref<1xi8> -> !text
  %open = trikeshed.combine %quote, %escaped : !text, !text -> !text
  %all = trikeshed.combine %open, %quote : !text, !text -> !text
  %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m8
  %end = trikeshed.drain %all, %mi : !text, !m8 -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// ---- the nodes: a kind and a window for every row.  Kinds: 0 null, 1 false, 2 true, 3 number, 4 string, 5 array,
// 6 object.  A string's window is its decoded bytes (one room of n bytes: no string decodes longer than its text), any
// other row's its span of the source.
func.func private @nx_sa_nodes(%rec: !llvm.ptr, %ctx: !llvm.ptr, %opens: !l32, %closes: !l32, %tags: !l8,
                               %nkind: memref<?xi64>, %nptr: memref<?xi64>, %nlen: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %srcw = func.call @nx_sa_w(%rec, %c0) : (!llvm.ptr, i64) -> i64
  %src = llvm.inttoptr %srcw : i64 to !llvm.ptr
  %n = func.call @nx_sa_w(%rec, %c1) : (!llvm.ptr, i64) -> i64
  %dbuf = func.call @nixsa_room(%ctx, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %dbw = llvm.ptrtoint %dbuf : !llvm.ptr to i64
  %ri = trikeshed.size %tags : !l8
  %used = scf.for %r = %z to %ri step %one iter_args(%off = %c0) -> (i64) {
    %from32 = trikeshed.at %opens[%r] : !l32, index -> i32
    %to32 = trikeshed.at %closes[%r] : !l32, index -> i32
    %from = arith.extui %from32 : i32 to i64
    %to = arith.extui %to32 : i32 to i64
    %tg8 = trikeshed.at %tags[%r] : !l8, index -> i8
    %tg = arith.extui %tg8 : i8 to i64
    %isstr = arith.cmpi eq, %tg, %c4 : i64
    %off2 = scf.if %isstr -> (i64) {
      %into = llvm.getelementptr %dbuf[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %w = func.call @nixev_json_decode(%src, %from, %to, %into, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
      %pw = arith.addi %dbw, %off : i64
      memref.store %pw, %nptr[%r] : memref<?xi64>
      memref.store %w, %nlen[%r] : memref<?xi64>
      %o2 = arith.addi %off, %w : i64
      scf.yield %o2 : i64
    } else {
      %pw2 = arith.addi %srcw, %from : i64
      %dd = arith.subi %to, %from : i64
      %ln = arith.addi %dd, %c1 : i64
      memref.store %pw2, %nptr[%r] : memref<?xi64>
      memref.store %ln, %nlen[%r] : memref<?xi64>
      scf.yield %off : i64
    }
    // the tags: 0 Nothing, 1 Boolean, 2 Long, 3 Double, 4 String, 5 Object, 6 Array; `true` spans 4 bytes
    %width = arith.subi %to, %from : i64
    %istrue = arith.cmpi eq, %width, %c3 : i64
    %kb = arith.select %istrue, %c2, %c1 : i64
    %isnull = arith.cmpi eq, %tg, %c0 : i64
    %isbool = arith.cmpi eq, %tg, %c1 : i64
    %isnum = arith.cmpi ule, %tg, %c3 : i64
    %isobj = arith.cmpi eq, %tg, %c5 : i64
    %kc = arith.select %isobj, %c6, %c5 : i64
    %kd = arith.select %isstr, %c4, %kc : i64
    %ke = arith.select %isnum, %c3, %kd : i64
    %kf = arith.select %isbool, %kb, %ke : i64
    %k = arith.select %isnull, %c0, %kf : i64
    memref.store %k, %nkind[%r] : memref<?xi64>
    scf.yield %off2 : i64
  }
  return
}

// ---- the members of every container: (key window, value node) from nfirst[x], ncnt[x] of them.  An array's are its
// elements (key length -1); an object's its keys in byte order, the last of equal keys kept; the root's one more, the
// `outputs` object (node rows), whose members are the outputs (node rows + 1 + i: the path, a string).
func.func private @nx_sa_members(%kids: !pieces, %kid: !s32, %outs: !llvm.ptr, %nout: i64, %nkind: memref<?xi64>,
                                 %nptr: memref<?xi64>, %nlen: memref<?xi64>, %nfirst: memref<?xi64>,
                                 %ncnt: memref<?xi64>, %mkp: memref<?xi64>, %mkl: memref<?xi64>, %mval: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %cm1 = arith.constant -1 : i64
  %zero32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ri = trikeshed.size %kids : !pieces
  %rows = arith.index_cast %ri : index to i64
  // the key `outputs`: the constant's own bytes
  %og = memref.get_global @sa_outputs : memref<7xi8>
  %oa = memref.extract_aligned_pointer_as_index %og : memref<7xi8> -> index
  %ow = arith.index_cast %oa : index to i64
  %mo = scf.for %r = %z to %ri step %one iter_args(%at = %c0) -> (i64) {
    %kind = memref.load %nkind[%r] : memref<?xi64>
    %kd = trikeshed.at %kids[%r] : !pieces, index -> !tp
    %first32 = trikeshed.first %kd : !tp -> i32
    %count32 = trikeshed.second %kd : !tp -> i32
    %first = arith.extui %first32 : i32 to i64
    %count = arith.extui %count32 : i32 to i64
    memref.store %at, %nfirst[%r] : memref<?xi64>
    %isarr = arith.cmpi eq, %kind, %c5 : i64
    %isobj = arith.cmpi eq, %kind, %c6 : i64
    %next = scf.if %isarr -> (i64) {
      %ci = arith.index_cast %count : i64 to index
      scf.for %i = %z to %ci step %one {
        %i64 = arith.index_cast %i : index to i64
        %ka = arith.addi %first, %i64 : i64
        %kai = arith.index_cast %ka : i64 to index
        %erow32 = trikeshed.at %kid[%kai] : !s32, index -> i32
        %erow = arith.extui %erow32 : i32 to i64
        %dst = arith.addi %at, %i64 : i64
        %dsti = arith.index_cast %dst : i64 to index
        memref.store %erow, %mval[%dsti] : memref<?xi64>
        memref.store %c0, %mkp[%dsti] : memref<?xi64>
        memref.store %cm1, %mkl[%dsti] : memref<?xi64>
      }
      memref.store %count, %ncnt[%r] : memref<?xi64>
      %a2 = arith.addi %at, %count : i64
      scf.yield %a2 : i64
    } else {
      %onext = scf.if %isobj -> (i64) {
        %isroot = arith.cmpi eq, %r, %z : index
        %rooti = arith.extui %isroot : i1 to i64
        %m0 = arith.divui %count, %c2 : i64
        %m = arith.addi %m0, %rooti : i64
        %mi = arith.index_cast %m : i64 to index
        %m0i = arith.index_cast %m0 : i64 to index
        %kpa = memref.alloc(%mi) : memref<?xi64>
        %kla = memref.alloc(%mi) : memref<?xi64>
        %kva = memref.alloc(%mi) : memref<?xi64>
        scf.for %j = %z to %m0i step %one {
          %j64 = arith.index_cast %j : index to i64
          %j2 = arith.muli %j64, %c2 : i64
          %kat = arith.addi %first, %j2 : i64
          %kati = arith.index_cast %kat : i64 to index
          %krow32 = trikeshed.at %kid[%kati] : !s32, index -> i32
          %krow = arith.extui %krow32 : i32 to i64
          %krowi = arith.index_cast %krow : i64 to index
          %vat = arith.addi %kat, %c1 : i64
          %vati = arith.index_cast %vat : i64 to index
          %vrow32 = trikeshed.at %kid[%vati] : !s32, index -> i32
          %vrow = arith.extui %vrow32 : i32 to i64
          %kpw = memref.load %nptr[%krowi] : memref<?xi64>
          %klw = memref.load %nlen[%krowi] : memref<?xi64>
          memref.store %kpw, %kpa[%j] : memref<?xi64>
          memref.store %klw, %kla[%j] : memref<?xi64>
          memref.store %vrow, %kva[%j] : memref<?xi64>
        }
        scf.if %isroot {
          memref.store %ow, %kpa[%m0i] : memref<?xi64>
          memref.store %c7, %kla[%m0i] : memref<?xi64>
          memref.store %rows, %kva[%m0i] : memref<?xi64>
        }
        %idx = trikeshed.series %mi : !s64 {
        ^bb0(%q: index):
          %q64 = arith.index_cast %q : index to i64
          trikeshed.yield %q64 : i64
        }
        // in key order; sorted is stable (a tie keeps the order of the text, the `outputs` member last)
        %order = trikeshed.sorted %idx : !s64 -> !s64 by {
        ^bb0(%ea: i64, %eb: i64):
          %eai = arith.index_cast %ea : i64 to index
          %ebi = arith.index_cast %eb : i64 to index
          %pa = memref.load %kpa[%eai] : memref<?xi64>
          %la = memref.load %kla[%eai] : memref<?xi64>
          %pb = memref.load %kpa[%ebi] : memref<?xi64>
          %lb = memref.load %kla[%ebi] : memref<?xi64>
          %ppa = llvm.inttoptr %pa : i64 to !llvm.ptr
          %ppb = llvm.inttoptr %pb : i64 to !llvm.ptr
          %da = func.call @nx_sa_desc8(%ppa, %la) : (!llvm.ptr, i64) -> !d
          %db = func.call @nx_sa_desc8(%ppb, %lb) : (!llvm.ptr, i64) -> !d
          %ma = builtin.unrealized_conversion_cast %da : !d to !m8
          %mb = builtin.unrealized_conversion_cast %db : !d to !m8
          %sa = builtin.unrealized_conversion_cast %ma : !m8 to !s8
          %sb = builtin.unrealized_conversion_cast %mb : !m8 to !s8
          %cab = trikeshed.compare %sa, %sb unsigned : !s8, !s8
          trikeshed.yield %cab : i32
        }
        // the members: each key that the next does not repeat
        %kept = scf.for %k = %z to %mi step %one iter_args(%jn = %c0) -> (i64) {
          %o1 = trikeshed.at %order[%k] : !s64, index -> i64
          %k1 = arith.addi %k, %one : index
          %more = arith.cmpi ult, %k1, %mi : index
          %kn = arith.select %more, %k1, %k : index
          %o2 = trikeshed.at %order[%kn] : !s64, index -> i64
          %o1i = arith.index_cast %o1 : i64 to index
          %o2i = arith.index_cast %o2 : i64 to index
          %p1 = memref.load %kpa[%o1i] : memref<?xi64>
          %l1 = memref.load %kla[%o1i] : memref<?xi64>
          %p2 = memref.load %kpa[%o2i] : memref<?xi64>
          %l2 = memref.load %kla[%o2i] : memref<?xi64>
          %pp1 = llvm.inttoptr %p1 : i64 to !llvm.ptr
          %pp2 = llvm.inttoptr %p2 : i64 to !llvm.ptr
          %d1 = func.call @nx_sa_desc8(%pp1, %l1) : (!llvm.ptr, i64) -> !d
          %d2 = func.call @nx_sa_desc8(%pp2, %l2) : (!llvm.ptr, i64) -> !d
          %m1 = builtin.unrealized_conversion_cast %d1 : !d to !m8
          %m2 = builtin.unrealized_conversion_cast %d2 : !d to !m8
          %s1 = builtin.unrealized_conversion_cast %m1 : !m8 to !s8
          %s2 = builtin.unrealized_conversion_cast %m2 : !m8 to !s8
          %c12 = trikeshed.compare %s1, %s2 unsigned : !s8, !s8
          %same = arith.cmpi eq, %c12, %zero32 : i32
          %dup = arith.andi %more, %same : i1
          %jn2 = scf.if %dup -> (i64) {
            scf.yield %jn : i64
          } else {
            %mdst = arith.addi %at, %jn : i64
            %mdsti = arith.index_cast %mdst : i64 to index
            %v1 = memref.load %kva[%o1i] : memref<?xi64>
            memref.store %p1, %mkp[%mdsti] : memref<?xi64>
            memref.store %l1, %mkl[%mdsti] : memref<?xi64>
            memref.store %v1, %mval[%mdsti] : memref<?xi64>
            %jn3 = arith.addi %jn, %c1 : i64
            scf.yield %jn3 : i64
          }
          scf.yield %jn2 : i64
        }
        memref.store %kept, %ncnt[%r] : memref<?xi64>
        %a3 = arith.addi %at, %kept : i64
        scf.yield %a3 : i64
      } else {
        memref.store %c0, %ncnt[%r] : memref<?xi64>
        scf.yield %at : i64
      }
      scf.yield %onext : i64
    }
    scf.yield %next : i64
  }
  // the outputs: the object (node rows), its members the names, their values the paths (nodes rows + 1 + i)
  memref.store %c6, %nkind[%ri] : memref<?xi64>
  memref.store %c0, %nptr[%ri] : memref<?xi64>
  memref.store %c0, %nlen[%ri] : memref<?xi64>
  memref.store %mo, %nfirst[%ri] : memref<?xi64>
  memref.store %nout, %ncnt[%ri] : memref<?xi64>
  %noi = arith.index_cast %nout : i64 to index
  scf.for %oi = %z to %noi step %one {
    %oi64 = arith.index_cast %oi : index to i64
    %namep, %namel, %pathp, %pathl = func.call @nx_sa_row(%outs, %oi64) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
    %odst = arith.addi %mo, %oi64 : i64
    %odsti = arith.index_cast %odst : i64 to index
    %r1 = arith.addi %rows, %c1 : i64
    %node = arith.addi %r1, %oi64 : i64
    %nodei = arith.index_cast %node : i64 to index
    memref.store %namep, %mkp[%odsti] : memref<?xi64>
    memref.store %namel, %mkl[%odsti] : memref<?xi64>
    memref.store %node, %mval[%odsti] : memref<?xi64>
    memref.store %c4, %nkind[%nodei] : memref<?xi64>
    memref.store %pathp, %nptr[%nodei] : memref<?xi64>
    memref.store %pathl, %nlen[%nodei] : memref<?xi64>
    memref.store %c0, %nfirst[%nodei] : memref<?xi64>
    memref.store %c0, %ncnt[%nodei] : memref<?xi64>
  }
  return
}

// ---- the output placeholders: one string's rewrites (p, l: its window, as ptr bits and a length): each placeholder in turn (rewrites' order), its
// occurrences left to right without overlap, then the gaps and the replacement as one combineAll drained into a room of
// the new length.  An empty placeholder rewrites nothing; a string none occurs in keeps its window.
func.func private @nx_sa_rewrite1(%ctx: !llvm.ptr, %rws: !llvm.ptr, %nrw: i64, %p0: i64, %l0: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %zero32 = arith.constant 0 : i32
  %no = arith.constant 0 : i1
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %nrwi = arith.index_cast %nrw : i64 to index
  %pl:2 = scf.for %j = %z to %nrwi step %one iter_args(%p = %p0, %l = %l0) -> (i64, i64) {
    %j64 = arith.index_cast %j : index to i64
    %fpw, %fl, %tpw, %tl = func.call @nx_sa_row(%rws, %j64) : (!llvm.ptr, i64) -> (i64, i64, i64, i64)
    %fne = arith.cmpi ne, %fl, %c0 : i64
    %fits = arith.cmpi ule, %fl, %l : i64
    %try = arith.andi %fne, %fits : i1
    %res:2 = scf.if %try -> (i64, i64) {
      %cap0 = arith.divui %l, %fl : i64
      %cap = arith.addi %cap0, %c1 : i64
      %capi = arith.index_cast %cap : i64 to index
      %pos = memref.alloc(%capi) : memref<?xi64>
      %pp = llvm.inttoptr %p : i64 to !llvm.ptr
      %sd = func.call @nx_sa_desc8(%pp, %l) : (!llvm.ptr, i64) -> !d
      %sm = builtin.unrealized_conversion_cast %sd : !d to !m8
      %s = builtin.unrealized_conversion_cast %sm : !m8 to !s8
      %fpp = llvm.inttoptr %fpw : i64 to !llvm.ptr
      %fd = func.call @nx_sa_desc8(%fpp, %fl) : (!llvm.ptr, i64) -> !d
      %fm = builtin.unrealized_conversion_cast %fd : !d to !m8
      %fs = builtin.unrealized_conversion_cast %fm : !m8 to !s8
      %f0 = trikeshed.at %fs[%z] : !s8, index -> i8
      %li = arith.index_cast %l : i64 to index
      %fli = arith.index_cast %fl : i64 to index
      // the occurrences, left to right; after one, the search goes on past it
      %found:2 = scf.while (%qa = %z, %ma = %c0) : (index, i64) -> (index, i64) {
        %qe = arith.addi %qa, %fli : index
        %go = arith.cmpi ule, %qe, %li : index
        scf.condition(%go) %qa, %ma : index, i64
      } do {
      ^bb0(%qb: index, %mb: i64):
        %bq = trikeshed.at %s[%qb] : !s8, index -> i8
        %h0 = arith.cmpi eq, %bq, %f0 : i8
        %hit = scf.if %h0 -> (i1) {
          %win = trikeshed.slice %s[%qb, %fli] : !s8 -> !s8
          %cw = trikeshed.compare %win, %fs unsigned : !s8, !s8
          %eq0 = arith.cmpi eq, %cw, %zero32 : i32
          scf.yield %eq0 : i1
        } else {
          scf.yield %no : i1
        }
        %nx:2 = scf.if %hit -> (index, i64) {
          %mbi = arith.index_cast %mb : i64 to index
          %qb64 = arith.index_cast %qb : index to i64
          memref.store %qb64, %pos[%mbi] : memref<?xi64>
          %qn = arith.addi %qb, %fli : index
          %mn = arith.addi %mb, %c1 : i64
          scf.yield %qn, %mn : index, i64
        } else {
          %qn1 = arith.addi %qb, %one : index
          scf.yield %qn1, %mb : index, i64
        }
        scf.yield %nx#0, %nx#1 : index, i64
      }
      %m = arith.addi %found#1, %c0 : i64
      %none = arith.cmpi eq, %m, %c0 : i64
      %w:2 = scf.if %none -> (i64, i64) {
        scf.yield %p, %l : i64, i64
      } else {
        %dl = arith.subi %tl, %fl : i64
        %grow = arith.muli %m, %dl : i64
        %nl = arith.addi %l, %grow : i64
        %out = func.call @nixsa_room(%ctx, %nl) : (!llvm.ptr, i64) -> !llvm.ptr
        %tpp = llvm.inttoptr %tpw : i64 to !llvm.ptr
        %tdd = func.call @nx_sa_desc8(%tpp, %tl) : (!llvm.ptr, i64) -> !d
        %tmm = builtin.unrealized_conversion_cast %tdd : !d to !m8
        %ts = builtin.unrealized_conversion_cast %tmm : !m8 to !s8
        %mi2 = arith.index_cast %m : i64 to index
        %last = arith.subi %mi2, %one : index
        %m2 = arith.muli %mi2, %two : index
        %np2 = arith.addi %m2, %one : index
        // piece 2g: the gap before occurrence g (after the last, the rest); piece 2g + 1: the replacement
        %view, %where = trikeshed.combineAll %np2 : !s8, !pieces {
        ^bb0(%k: index):
          %g = arith.divui %k, %two : index
          %odd0 = arith.remui %k, %two : index
          %isodd = arith.cmpi ne, %odd0, %z : index
          %has = arith.cmpi ugt, %g, %z : index
          %gm1 = arith.subi %g, %one : index
          %gp = arith.select %has, %gm1, %z : index
          %prev = memref.load %pos[%gp] : memref<?xi64>
          %prevend = arith.addi %prev, %fl : i64
          %start = arith.select %has, %prevend, %c0 : i64
          %islast = arith.cmpi eq, %g, %mi2 : index
          %ge = arith.minui %g, %last : index
          %cur = memref.load %pos[%ge] : memref<?xi64>
          %en = arith.select %islast, %l, %cur : i64
          %gap = arith.subi %en, %start : i64
          %gapl = arith.select %isodd, %c0, %gap : i64
          %tol = arith.select %isodd, %tl, %c0 : i64
          %starti = arith.index_cast %start : i64 to index
          %gapli = arith.index_cast %gapl : i64 to index
          %toli = arith.index_cast %tol : i64 to index
          %gs = trikeshed.slice %s[%starti, %gapli] : !s8 -> !s8
          %tsl = trikeshed.slice %ts[%z, %toli] : !s8 -> !s8
          %part = trikeshed.combine %gs, %tsl : !s8, !s8 -> !s8
          trikeshed.yield %part : !s8
        }
        %od = func.call @nx_sa_desc8(%out, %nl) : (!llvm.ptr, i64) -> !d
        %om = builtin.unrealized_conversion_cast %od : !d to !m8
        %e = trikeshed.drain %view, %om : !s8, !m8 -> index
        %outw = llvm.ptrtoint %out : !llvm.ptr to i64
        scf.yield %outw, %nl : i64, i64
      }
      scf.yield %w#0, %w#1 : i64, i64
    } else {
      scf.yield %p, %l : i64, i64
    }
    scf.yield %res#0, %res#1 : i64, i64
  }
  return %pl#0, %pl#1 : i64, i64
}

// every string of the text rewritten (not the keys: a key's window is the member table's, taken before)
func.func private @nx_sa_rewrite(%ctx: !llvm.ptr, %rows: i64, %rws: !llvm.ptr, %nrw: i64, %nkind: memref<?xi64>,
                                 %nptr: memref<?xi64>, %nlen: memref<?xi64>) {
  %c4 = arith.constant 4 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ri = arith.index_cast %rows : i64 to index
  scf.for %r = %z to %ri step %one {
    %kind = memref.load %nkind[%r] : memref<?xi64>
    %isstr = arith.cmpi eq, %kind, %c4 : i64
    scf.if %isstr {
      %p0 = memref.load %nptr[%r] : memref<?xi64>
      %l0 = memref.load %nlen[%r] : memref<?xi64>
      %pl:2 = func.call @nx_sa_rewrite1(%ctx, %rws, %nrw, %p0, %l0) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> (i64, i64)
      memref.store %pl#0, %nptr[%r] : memref<?xi64>
      memref.store %pl#1, %nlen[%r] : memref<?xi64>
    }
  }
  return
}

// nixstore::rewritePlaceholders (StructuredAttrs.cpp): the n bytes at p with the placeholders rewritten (runBuilder's
// environment and arguments, as the structured attributes' strings are).  The result's length goes to *len; its bytes
// are p's when nothing occurs, else the last room.
func.func @nixstore_ts_rewrite(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64, %rws: !llvm.ptr, %nrw: i64,
                               %len: !llvm.ptr) -> !llvm.ptr {
  %pw = llvm.ptrtoint %p : !llvm.ptr to i64
  %r:2 = func.call @nx_sa_rewrite1(%ctx, %rws, %nrw, %pw, %n) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> (i64, i64)
  llvm.store %r#1, %len : i64, !llvm.ptr
  %rp = llvm.inttoptr %r#0 : i64 to !llvm.ptr
  return %rp : !llvm.ptr
}

// ---- the simple values (handleSimpleType): every string, null and boolean; a number when ceil((float) f) == (float) f,
// its (int) f then written into its 11-byte cell (dec at 11 x) as decimal digits, declen[x] of them.
func.func private @nx_sa_numbers(%nodes: i64, %nkind: memref<?xi64>, %nptr: memref<?xi64>, %nsimple: memref<?xi64>,
                                 %dec: memref<?xi8>, %declen: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c48 = arith.constant 48 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c11i = arith.constant 11 : index
  %null = llvm.mlir.zero : !llvm.ptr
  %pg = memref.get_global @sa_pow10 : memref<11xi64>
  %pws = trikeshed.text %pg : memref<11xi64> -> !s64
  %mg = memref.get_global @sa_minus : memref<1xi8>
  %minus = trikeshed.text %mg : memref<1xi8> -> !s8
  %ni = arith.index_cast %nodes : i64 to index
  scf.for %x = %z to %ni step %one {
    %kind = memref.load %nkind[%x] : memref<?xi64>
    memref.store %c0, %declen[%x] : memref<?xi64>
    %isnum = arith.cmpi eq, %kind, %c3 : i64
    %iscont = arith.cmpi uge, %kind, %c5 : i64
    %simple = scf.if %isnum -> (i64) {
      %pw = memref.load %nptr[%x] : memref<?xi64>
      %pp = llvm.inttoptr %pw : i64 to !llvm.ptr
      // the number is followed by `,` `]` `}` or white space (the root is an object): strtod stops at its end
      %f = func.call @strtod(%pp, %null) : (!llvm.ptr, !llvm.ptr) -> f64
      %ff = arith.truncf %f : f64 to f32
      %fc = "llvm.intr.ceil"(%ff) : (f32) -> f32
      %whole = arith.cmpf oeq, %fc, %ff : f32
      %sw = scf.if %whole -> (i64) {
        %iv = arith.fptosi %f : f64 to i32
        %v = arith.extsi %iv : i32 to i64
        %neg = arith.cmpi slt, %v, %c0 : i64
        %nv = arith.subi %c0, %v : i64
        %a = arith.select %neg, %nv, %v : i64
        %cnt = trikeshed.fold %pws, %c0 : !s64, i64 -> i64 {
        ^bb0(%acc: i64, %pv: i64):
          %le = arith.cmpi ule, %pv, %a : i64
          %le64 = arith.extui %le : i1 to i64
          %acc2 = arith.addi %acc, %le64 : i64
          trikeshed.yield %acc2 : i64
        }
        %nd = arith.maxui %cnt, %c1 : i64
        %ndi = arith.index_cast %nd : i64 to index
        %digits = trikeshed.series %ndi : !s8 {
        ^bb0(%dk: index):
          %dk64 = arith.index_cast %dk : index to i64
          %e0 = arith.subi %nd, %c1 : i64
          %e = arith.subi %e0, %dk64 : i64
          %ei = arith.index_cast %e : i64 to index
          %pe = trikeshed.at %pws[%ei] : !s64, index -> i64
          %qv = arith.divui %a, %pe : i64
          %rv = arith.remui %qv, %c10 : i64
          %ch = arith.addi %rv, %c48 : i64
          %ch8 = arith.trunci %ch : i64 to i8
          trikeshed.yield %ch8 : i8
        }
        %negi = arith.index_castui %neg : i1 to index
        %sg = trikeshed.slice %minus[%z, %negi] : !s8 -> !s8
        %all = trikeshed.combine %sg, %digits : !s8, !s8 -> !s8
        %x64 = arith.index_cast %x : index to i64
        %off = arith.muli %x64, %c11 : i64
        %offi = arith.index_cast %off : i64 to index
        %cell = memref.subview %dec[%offi] [%c11i] [1] : memref<?xi8> to memref<?xi8, strided<[1], offset: ?>>
        %end = trikeshed.drain %all, %cell : !s8, !m8 -> index
        %e64 = arith.index_cast %end : index to i64
        memref.store %e64, %declen[%x] : memref<?xi64>
        scf.yield %c1 : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %sw : i64
    } else {
      %sc = arith.select %iscont, %c0, %c1 : i64
      scf.yield %sc : i64
    }
    memref.store %simple, %nsimple[%x] : memref<?xi64>
  }
  return
}

// ---- the tree as events, in the order .attrs.json writes it: (node, member or -1, 0 open or a leaf / 1 close, comma).
// A stack of (container, next member), so no recursion: a document nested as deep as it is long is written.
func.func private @nx_sa_walk(%nodes: i64, %nkind: memref<?xi64>, %nfirst: memref<?xi64>, %ncnt: memref<?xi64>,
                              %mval: memref<?xi64>, %evn: memref<?xi64>, %evm: memref<?xi64>, %evt: memref<?xi64>,
                              %evc: memref<?xi64>) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %cm1 = arith.constant -1 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ni = arith.index_cast %nodes : i64 to index
  %cap = arith.addi %ni, %one : index
  %stn = memref.alloc(%cap) : memref<?xi64>
  %sti = memref.alloc(%cap) : memref<?xi64>
  memref.store %c0, %evn[%z] : memref<?xi64>
  memref.store %cm1, %evm[%z] : memref<?xi64>
  memref.store %c0, %evt[%z] : memref<?xi64>
  memref.store %c0, %evc[%z] : memref<?xi64>
  memref.store %c0, %stn[%z] : memref<?xi64>
  memref.store %c0, %sti[%z] : memref<?xi64>
  %fin:2 = scf.while (%e = %one, %sp = %one) : (index, index) -> (index, index) {
    %live = arith.cmpi ugt, %sp, %z : index
    scf.condition(%live) %e, %sp : index, index
  } do {
  ^bb0(%ea: index, %spa: index):
    %top = arith.subi %spa, %one : index
    %xn = memref.load %stn[%top] : memref<?xi64>
    %xi = arith.index_cast %xn : i64 to index
    %iv = memref.load %sti[%top] : memref<?xi64>
    %cnt = memref.load %ncnt[%xi] : memref<?xi64>
    %more = arith.cmpi ult, %iv, %cnt : i64
    %nx:2 = scf.if %more -> (index, index) {
      %fst = memref.load %nfirst[%xi] : memref<?xi64>
      %mm = arith.addi %fst, %iv : i64
      %mmi = arith.index_cast %mm : i64 to index
      %ch = memref.load %mval[%mmi] : memref<?xi64>
      %chi = arith.index_cast %ch : i64 to index
      memref.store %ch, %evn[%ea] : memref<?xi64>
      memref.store %mm, %evm[%ea] : memref<?xi64>
      memref.store %c0, %evt[%ea] : memref<?xi64>
      %later = arith.cmpi ugt, %iv, %c0 : i64
      %later64 = arith.extui %later : i1 to i64
      memref.store %later64, %evc[%ea] : memref<?xi64>
      %iv1 = arith.addi %iv, %c1 : i64
      memref.store %iv1, %sti[%top] : memref<?xi64>
      %kc = memref.load %nkind[%chi] : memref<?xi64>
      %cont = arith.cmpi uge, %kc, %c5 : i64
      %sp2 = scf.if %cont -> (index) {
        memref.store %ch, %stn[%spa] : memref<?xi64>
        memref.store %c0, %sti[%spa] : memref<?xi64>
        %s1 = arith.addi %spa, %one : index
        scf.yield %s1 : index
      } else {
        scf.yield %spa : index
      }
      %e1 = arith.addi %ea, %one : index
      scf.yield %e1, %sp2 : index, index
    } else {
      memref.store %xn, %evn[%ea] : memref<?xi64>
      memref.store %cm1, %evm[%ea] : memref<?xi64>
      memref.store %c1, %evt[%ea] : memref<?xi64>
      memref.store %c0, %evc[%ea] : memref<?xi64>
      %e2 = arith.addi %ea, %one : index
      scf.yield %e2, %top : index, index
    }
    scf.yield %nx#0, %nx#1 : index, index
  }
  %r = arith.index_cast %fin#0 : index to i64
  return %r : i64
}

// ---- .attrs.json: ONE combineAll over the events, each the comma, the key ("k":), the word ([ ] { } null true false)
// or the number's span, and the string (quotes around its escape), every absent piece a slice of length 0.
func.func private @nx_sa_json(%ctx: !llvm.ptr, %ne: i64, %nkind: memref<?xi64>, %nptr: memref<?xi64>,
                              %nlen: memref<?xi64>, %mkp: memref<?xi64>, %mkl: memref<?xi64>, %evn: memref<?xi64>,
                              %evm: memref<?xi64>, %evt: memref<?xi64>, %evc: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c12 = arith.constant 12 : i64
  %z = arith.constant 0 : index
  %two = arith.constant 2 : index
  %six = arith.constant 6 : index
  %jg = memref.get_global @sa_jw : memref<17xi8>
  %jw = trikeshed.text %jg : memref<17xi8> -> !s8
  %cg = memref.get_global @sa_comma : memref<1xi8>
  %comma = trikeshed.text %cg : memref<1xi8> -> !s8
  %qg = memref.get_global @sa_quote : memref<1xi8>
  %quote = trikeshed.text %qg : memref<1xi8> -> !s8
  %qcg = memref.get_global @sa_qcolon : memref<2xi8>
  %qcolon = trikeshed.text %qcg : memref<2xi8> -> !s8
  %eg = memref.get_global @sa_esc : memref<1536xi8>
  %table = trikeshed.text %eg : memref<1536xi8> -> !s8
  %lg = memref.get_global @sa_esc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !s8
  %nei = arith.index_cast %ne : i64 to index
  %all, %where = trikeshed.combineAll %nei : !s8, !pieces {
  ^bb0(%k: index):
    %xn = memref.load %evn[%k] : memref<?xi64>
    %xi = arith.index_cast %xn : i64 to index
    %mm = memref.load %evm[%k] : memref<?xi64>
    %t = memref.load %evt[%k] : memref<?xi64>
    %cm = memref.load %evc[%k] : memref<?xi64>
    %kind = memref.load %nkind[%xi] : memref<?xi64>
    %open = arith.cmpi eq, %t, %c0 : i64
    %hasm = arith.cmpi sge, %mm, %c0 : i64
    %mm0 = arith.select %hasm, %mm, %c0 : i64
    %mmi = arith.index_cast %mm0 : i64 to index
    %kl = memref.load %mkl[%mmi] : memref<?xi64>
    %kpw = memref.load %mkp[%mmi] : memref<?xi64>
    %klpos = arith.cmpi sge, %kl, %c0 : i64
    %k1 = arith.andi %open, %hasm : i1
    %keyed = arith.andi %k1, %klpos : i1
    %kn = arith.select %keyed, %kl, %c0 : i64
    %kni = arith.index_cast %kn : i64 to index
    %kpp = llvm.inttoptr %kpw : i64 to !llvm.ptr
    %kd = func.call @nx_sa_desc8(%kpp, %kn) : (!llvm.ptr, i64) -> !d
    %km = builtin.unrealized_conversion_cast %kd : !d to !m8
    %ks = builtin.unrealized_conversion_cast %km : !m8 to !s8
    %keyedi = arith.index_castui %keyed : i1 to index
    %keyed2 = arith.muli %keyedi, %two : index
    %cmi = arith.index_cast %cm : i64 to index
    %sep = trikeshed.slice %comma[%z, %cmi] : !s8 -> !s8
    %kq = trikeshed.slice %quote[%z, %keyedi] : !s8 -> !s8
    %kesc, %kwh = trikeshed.combineAll %kni : !s8, !pieces {
    ^bb0(%kb: index):
      %b = trikeshed.at %ks[%kb] : !s8, index -> i8
      %bi = arith.index_castui %b : i8 to index
      %l = trikeshed.at %lengths[%bi] : !s8, index -> i8
      %li = arith.index_castui %l : i8 to index
      %at = arith.muli %bi, %six : index
      %kpart = trikeshed.slice %table[%at, %li] : !s8 -> !s8
      trikeshed.yield %kpart : !s8
    }
    %kc = trikeshed.slice %qcolon[%z, %keyed2] : !s8 -> !s8
    // the word: [ ] { } at 0..3 (an object's 2 on, a close 1 on), null at 4, true at 8, false at 12
    %isobj = arith.cmpi eq, %kind, %c6 : i64
    %closen = arith.cmpi ne, %t, %c0 : i64
    %close64 = arith.extui %closen : i1 to i64
    %bro = arith.select %isobj, %c2, %c0 : i64
    %brs = arith.addi %bro, %close64 : i64
    %isnull = arith.cmpi eq, %kind, %c0 : i64
    %isfalse = arith.cmpi eq, %kind, %c1 : i64
    %istrue = arith.cmpi eq, %kind, %c2 : i64
    %isword = arith.cmpi ule, %kind, %c2 : i64
    %iscont = arith.cmpi uge, %kind, %c5 : i64
    %ws1 = arith.select %istrue, %c8, %brs : i64
    %ws2 = arith.select %isfalse, %c12, %ws1 : i64
    %ws = arith.select %isnull, %c4, %ws2 : i64
    %wlw = arith.select %isfalse, %c5, %c4 : i64
    %wlc = arith.select %iscont, %c1, %c0 : i64
    %wl = arith.select %isword, %wlw, %wlc : i64
    %wsi = arith.index_cast %ws : i64 to index
    %wli = arith.index_cast %wl : i64 to index
    %word = trikeshed.slice %jw[%wsi, %wli] : !s8 -> !s8
    %isnumk = arith.cmpi eq, %kind, %c3 : i64
    %isstrk = arith.cmpi eq, %kind, %c4 : i64
    %isnum = arith.andi %open, %isnumk : i1
    %isstr = arith.andi %open, %isstrk : i1
    %vl = memref.load %nlen[%xi] : memref<?xi64>
    %vpw = memref.load %nptr[%xi] : memref<?xi64>
    %vpp = llvm.inttoptr %vpw : i64 to !llvm.ptr
    %numl = arith.select %isnum, %vl, %c0 : i64
    %strl = arith.select %isstr, %vl, %c0 : i64
    %numli = arith.index_cast %numl : i64 to index
    %strli = arith.index_cast %strl : i64 to index
    %vd = func.call @nx_sa_desc8(%vpp, %vl) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m8
    %vs = builtin.unrealized_conversion_cast %vm : !m8 to !s8
    %num = trikeshed.slice %vs[%z, %numli] : !s8 -> !s8
    %isstri = arith.index_castui %isstr : i1 to index
    %vq = trikeshed.slice %quote[%z, %isstri] : !s8 -> !s8
    %vesc, %vwh = trikeshed.combineAll %strli : !s8, !pieces {
    ^bb0(%vb: index):
      %c = trikeshed.at %vs[%vb] : !s8, index -> i8
      %ci = arith.index_castui %c : i8 to index
      %cl = trikeshed.at %lengths[%ci] : !s8, index -> i8
      %cli = arith.index_castui %cl : i8 to index
      %cat = arith.muli %ci, %six : index
      %vpart = trikeshed.slice %table[%cat, %cli] : !s8 -> !s8
      trikeshed.yield %vpart : !s8
    }
    %part = trikeshed.combine %sep, %kq, %kesc, %kc, %word, %num, %vq, %vesc, %vq : !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8 -> !s8
    trikeshed.yield %part : !s8
  }
  %sz = trikeshed.size %all : !s8
  %szw = arith.index_cast %sz : index to i64
  %out = func.call @nixsa_out(%ctx, %c0, %szw) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %od = func.call @nx_sa_desc8(%out, %szw) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m8
  %end = trikeshed.drain %all, %om : !s8, !m8 -> index
  return
}

// ---- which line each of the root's members writes: 0 none (its key is no shell name [A-Za-z_][A-Za-z0-9_]*, or its
// value is a number with a fraction, or a container holding something not simple), 1 `declare K=V`, 2 an indexed
// array, 3 an associative array
func.func private @nx_sa_shkinds(%nkind: memref<?xi64>, %nfirst: memref<?xi64>, %ncnt: memref<?xi64>,
                                 %mkp: memref<?xi64>, %mkl: memref<?xi64>, %mval: memref<?xi64>,
                                 %nsimple: memref<?xi64>, %shk: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %w1 = arith.constant 1 : i8
  %w0 = arith.constant 0 : i8
  %yes = arith.constant 1 : i1
  %no = arith.constant 0 : i1
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %clg = memref.get_global @sa_cls : memref<256xi8>
  %cls = trikeshed.text %clg : memref<256xi8> -> !s8
  %rf = memref.load %nfirst[%z] : memref<?xi64>
  %rc = memref.load %ncnt[%z] : memref<?xi64>
  %rci = arith.index_cast %rc : i64 to index
  scf.for %j = %z to %rci step %one {
    %j64 = arith.index_cast %j : index to i64
    %mm = arith.addi %rf, %j64 : i64
    %mmi = arith.index_cast %mm : i64 to index
    %kp = memref.load %mkp[%mmi] : memref<?xi64>
    %kl = memref.load %mkl[%mmi] : memref<?xi64>
    %kpp = llvm.inttoptr %kp : i64 to !llvm.ptr
    %kd = func.call @nx_sa_desc8(%kpp, %kl) : (!llvm.ptr, i64) -> !d
    %km = builtin.unrealized_conversion_cast %kd : !d to !m8
    %ks = builtin.unrealized_conversion_cast %km : !m8 to !s8
    %some = arith.cmpi ugt, %kl, %c0 : i64
    %lead = scf.if %some -> (i1) {
      %b0 = trikeshed.at %ks[%z] : !s8, index -> i8
      %b0i = arith.index_castui %b0 : i8 to index
      %k0 = trikeshed.at %cls[%b0i] : !s8, index -> i8
      %isl = arith.cmpi eq, %k0, %w1 : i8
      scf.yield %isl : i1
    } else {
      scf.yield %no : i1
    }
    %bad = trikeshed.fold %ks, %c0 : !s8, i64 -> i64 {
    ^bb0(%acc: i64, %b: i8):
      %bi = arith.index_castui %b : i8 to index
      %kb = trikeshed.at %cls[%bi] : !s8, index -> i8
      %other = arith.cmpi eq, %kb, %w0 : i8
      %o64 = arith.extui %other : i1 to i64
      %acc2 = arith.addi %acc, %o64 : i64
      trikeshed.yield %acc2 : i64
    }
    %clean = arith.cmpi eq, %bad, %c0 : i64
    %name = arith.andi %lead, %clean : i1
    %v = memref.load %mval[%mmi] : memref<?xi64>
    %vi = arith.index_cast %v : i64 to index
    %kv = memref.load %nkind[%vi] : memref<?xi64>
    %sv = memref.load %nsimple[%vi] : memref<?xi64>
    %vf = memref.load %nfirst[%vi] : memref<?xi64>
    %vc = memref.load %ncnt[%vi] : memref<?xi64>
    %vfi = arith.index_cast %vf : i64 to index
    %vci = arith.index_cast %vc : i64 to index
    %vend = arith.addi %vfi, %vci : index
    %allsimple = scf.for %ci = %vfi to %vend step %one iter_args(%ok = %yes) -> (i1) {
      %cv = memref.load %mval[%ci] : memref<?xi64>
      %cvi = arith.index_cast %cv : i64 to index
      %cs = memref.load %nsimple[%cvi] : memref<?xi64>
      %csb = arith.cmpi ne, %cs, %c0 : i64
      %ok2 = arith.andi %ok, %csb : i1
      scf.yield %ok2 : i1
    }
    %issimple = arith.cmpi ne, %sv, %c0 : i64
    %isarr = arith.cmpi eq, %kv, %c5 : i64
    %isobj = arith.cmpi eq, %kv, %c6 : i64
    %ka = arith.select %allsimple, %c2, %c0 : i64
    %ko = arith.select %allsimple, %c3, %c0 : i64
    %s3 = arith.select %isobj, %ko, %c0 : i64
    %s2 = arith.select %isarr, %ka, %s3 : i64
    %s1 = arith.select %issimple, %c1, %s2 : i64
    %s = arith.select %name, %s1, %c0 : i64
    memref.store %s, %shk[%j] : memref<?xi64>
  }
  return
}

// ---- .attrs.sh: the members that write a line (trikeshed.where), then ONE combineAll of their lines.  The words are
// one blob: "declare -a declare -A =()\n[]=''1 " (declare 0..8, -a 0..11, -A 11..22, = 22, =( 22..24, )\n 24..26, \n 25,
// [ 26, ]= 27..29, '' 29..31, ' 29, 1 31, space 32).  A simple value: '' (null), 1 or nothing (a boolean), the
// number's digits, or ' + each byte (' as '\'') + '.
func.func private @nx_sa_sh(%ctx: !llvm.ptr, %nkind: memref<?xi64>, %nptr: memref<?xi64>, %nlen: memref<?xi64>,
                            %nfirst: memref<?xi64>, %ncnt: memref<?xi64>, %mkp: memref<?xi64>, %mkl: memref<?xi64>,
                            %mval: memref<?xi64>, %dec: memref<?xi8>, %declen: memref<?xi64>, %shk: memref<?xi64>) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c11 = arith.constant 11 : i64
  %c22 = arith.constant 22 : i64
  %c24 = arith.constant 24 : i64
  %c25 = arith.constant 25 : i64
  %c29 = arith.constant 29 : i64
  %c31 = arith.constant 31 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %two = arith.constant 2 : index
  %four = arith.constant 4 : index
  %i22 = arith.constant 22 : index
  %i26 = arith.constant 26 : index
  %i27 = arith.constant 27 : index
  %i29 = arith.constant 29 : index
  %i32 = arith.constant 32 : index
  %wg = memref.get_global @sa_shw : memref<33xi8>
  %shw = trikeshed.text %wg : memref<33xi8> -> !s8
  %eg = memref.get_global @sa_shesc : memref<1024xi8>
  %table = trikeshed.text %eg : memref<1024xi8> -> !s8
  %lg = memref.get_global @sa_shesc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !s8
  %decm = builtin.unrealized_conversion_cast %dec : memref<?xi8> to !m8
  %decs = builtin.unrealized_conversion_cast %decm : !m8 to !s8
  %rf = memref.load %nfirst[%z] : memref<?xi64>
  %rc = memref.load %ncnt[%z] : memref<?xi64>
  %rci = arith.index_cast %rc : i64 to index
  %idx = trikeshed.series %rci : !s64 {
  ^bb0(%q: index):
    %q64 = arith.index_cast %q : index to i64
    trikeshed.yield %q64 : i64
  }
  %kept = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%jw: i64):
    %jwi = arith.index_cast %jw : i64 to index
    %sj = memref.load %shk[%jwi] : memref<?xi64>
    %writes = arith.cmpi ne, %sj, %c0 : i64
    trikeshed.yield %writes : i1
  }
  %nk = trikeshed.size %kept : !s64
  %lines, %lwh = trikeshed.combineAll %nk : !s8, !pieces {
  ^bb0(%lq: index):
    %j = trikeshed.at %kept[%lq] : !s64, index -> i64
    %ji = arith.index_cast %j : i64 to index
    %mm = arith.addi %rf, %j : i64
    %mmi = arith.index_cast %mm : i64 to index
    %s = memref.load %shk[%ji] : memref<?xi64>
    %is1 = arith.cmpi eq, %s, %c1 : i64
    %is3 = arith.cmpi eq, %s, %c3 : i64
    %hst = arith.select %is3, %c11, %c0 : i64
    %hl = arith.select %is1, %c8, %c11 : i64
    %hsti = arith.index_cast %hst : i64 to index
    %hli = arith.index_cast %hl : i64 to index
    %head = trikeshed.slice %shw[%hsti, %hli] : !s8 -> !s8
    %kp = memref.load %mkp[%mmi] : memref<?xi64>
    %kl = memref.load %mkl[%mmi] : memref<?xi64>
    %kpp = llvm.inttoptr %kp : i64 to !llvm.ptr
    %kd = func.call @nx_sa_desc8(%kpp, %kl) : (!llvm.ptr, i64) -> !d
    %km = builtin.unrealized_conversion_cast %kd : !d to !m8
    %ks = builtin.unrealized_conversion_cast %km : !m8 to !s8
    %kli = arith.index_cast %kl : i64 to index
    %key = trikeshed.slice %ks[%z, %kli] : !s8 -> !s8
    %eql = arith.select %is1, %one, %two : index
    %eq = trikeshed.slice %shw[%i22, %eql] : !s8 -> !s8
    // the value, when simple: its word, or its quoted bytes, or its digits
    %v = memref.load %mval[%mmi] : memref<?xi64>
    %vi = arith.index_cast %v : i64 to index
    %vk = memref.load %nkind[%vi] : memref<?xi64>
    %vnull = arith.cmpi eq, %vk, %c0 : i64
    %vtrue = arith.cmpi eq, %vk, %c2 : i64
    %vstr = arith.cmpi eq, %vk, %c4 : i64
    %vnum = arith.cmpi eq, %vk, %c3 : i64
    %vws = arith.select %vnull, %c29, %c31 : i64
    %vwl1 = arith.select %vtrue, %c1, %c0 : i64
    %vwl = arith.select %vnull, %c2, %vwl1 : i64
    %vwsi = arith.index_cast %vws : i64 to index
    %vwli = arith.index_cast %vwl : i64 to index
    %vword = trikeshed.slice %shw[%vwsi, %vwli] : !s8 -> !s8
    %vstri = arith.index_castui %vstr : i1 to index
    %vq = trikeshed.slice %shw[%i29, %vstri] : !s8 -> !s8
    %vlen = memref.load %nlen[%vi] : memref<?xi64>
    %vpw = memref.load %nptr[%vi] : memref<?xi64>
    %vsl = arith.select %vstr, %vlen, %c0 : i64
    %vsli = arith.index_cast %vsl : i64 to index
    %vpp = llvm.inttoptr %vpw : i64 to !llvm.ptr
    %vd = func.call @nx_sa_desc8(%vpp, %vsl) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m8
    %vs = builtin.unrealized_conversion_cast %vm : !m8 to !s8
    %vesc, %vewh = trikeshed.combineAll %vsli : !s8, !pieces {
    ^bb0(%vb: index):
      %b = trikeshed.at %vs[%vb] : !s8, index -> i8
      %bi = arith.index_castui %b : i8 to index
      %l = trikeshed.at %lengths[%bi] : !s8, index -> i8
      %li = arith.index_castui %l : i8 to index
      %at = arith.muli %bi, %four : index
      %vpart = trikeshed.slice %table[%at, %li] : !s8 -> !s8
      trikeshed.yield %vpart : !s8
    }
    %vdl0 = memref.load %declen[%vi] : memref<?xi64>
    %vdl = arith.select %vnum, %vdl0, %c0 : i64
    %v11 = arith.muli %v, %c11 : i64
    %vdo = arith.select %vnum, %v11, %c0 : i64
    %vdoi = arith.index_cast %vdo : i64 to index
    %vdli = arith.index_cast %vdl : i64 to index
    %vdec = trikeshed.slice %decs[%vdoi, %vdli] : !s8 -> !s8
    // an array's or an object's members, each `V ` or `['k']=V `
    %many = arith.cmpi uge, %s, %c2 : i64
    %vc = memref.load %ncnt[%vi] : memref<?xi64>
    %vf = memref.load %nfirst[%vi] : memref<?xi64>
    %lc = arith.select %many, %vc, %c0 : i64
    %lci = arith.index_cast %lc : i64 to index
    %is3i = arith.index_castui %is3 : i1 to index
    %is3two = arith.muli %is3i, %two : index
    %list, %liwh = trikeshed.combineAll %lci : !s8, !pieces {
    ^bb0(%li0: index):
      %li64 = arith.index_cast %li0 : index to i64
      %cm = arith.addi %vf, %li64 : i64
      %cmi = arith.index_cast %cm : i64 to index
      %cn = memref.load %mval[%cmi] : memref<?xi64>
      %cni = arith.index_cast %cn : i64 to index
      %lb = trikeshed.slice %shw[%i26, %is3i] : !s8 -> !s8
      %kq = trikeshed.slice %shw[%i29, %is3i] : !s8 -> !s8
      %ckl = memref.load %mkl[%cmi] : memref<?xi64>
      %ckp = memref.load %mkp[%cmi] : memref<?xi64>
      %ckn = arith.select %is3, %ckl, %c0 : i64
      %ckni = arith.index_cast %ckn : i64 to index
      %ckpp = llvm.inttoptr %ckp : i64 to !llvm.ptr
      %ckd = func.call @nx_sa_desc8(%ckpp, %ckn) : (!llvm.ptr, i64) -> !d
      %ckm = builtin.unrealized_conversion_cast %ckd : !d to !m8
      %cks = builtin.unrealized_conversion_cast %ckm : !m8 to !s8
      %kesc, %kewh = trikeshed.combineAll %ckni : !s8, !pieces {
      ^bb0(%kb: index):
        %kbb = trikeshed.at %cks[%kb] : !s8, index -> i8
        %kbi = arith.index_castui %kbb : i8 to index
        %kbl = trikeshed.at %lengths[%kbi] : !s8, index -> i8
        %kbli = arith.index_castui %kbl : i8 to index
        %kat = arith.muli %kbi, %four : index
        %kpart = trikeshed.slice %table[%kat, %kbli] : !s8 -> !s8
        trikeshed.yield %kpart : !s8
      }
      %req = trikeshed.slice %shw[%i27, %is3two] : !s8 -> !s8
      %ck = memref.load %nkind[%cni] : memref<?xi64>
      %cnull = arith.cmpi eq, %ck, %c0 : i64
      %ctrue = arith.cmpi eq, %ck, %c2 : i64
      %cstr = arith.cmpi eq, %ck, %c4 : i64
      %cnum = arith.cmpi eq, %ck, %c3 : i64
      %cws = arith.select %cnull, %c29, %c31 : i64
      %cwl1 = arith.select %ctrue, %c1, %c0 : i64
      %cwl = arith.select %cnull, %c2, %cwl1 : i64
      %cwsi = arith.index_cast %cws : i64 to index
      %cwli = arith.index_cast %cwl : i64 to index
      %cword = trikeshed.slice %shw[%cwsi, %cwli] : !s8 -> !s8
      %cstri = arith.index_castui %cstr : i1 to index
      %cq = trikeshed.slice %shw[%i29, %cstri] : !s8 -> !s8
      %clen = memref.load %nlen[%cni] : memref<?xi64>
      %cpw = memref.load %nptr[%cni] : memref<?xi64>
      %csl = arith.select %cstr, %clen, %c0 : i64
      %csli = arith.index_cast %csl : i64 to index
      %cpp = llvm.inttoptr %cpw : i64 to !llvm.ptr
      %cdd = func.call @nx_sa_desc8(%cpp, %csl) : (!llvm.ptr, i64) -> !d
      %cmm = builtin.unrealized_conversion_cast %cdd : !d to !m8
      %css = builtin.unrealized_conversion_cast %cmm : !m8 to !s8
      %cesc, %cewh = trikeshed.combineAll %csli : !s8, !pieces {
      ^bb0(%cb: index):
        %cbb = trikeshed.at %css[%cb] : !s8, index -> i8
        %cbi = arith.index_castui %cbb : i8 to index
        %cbl = trikeshed.at %lengths[%cbi] : !s8, index -> i8
        %cbli = arith.index_castui %cbl : i8 to index
        %cat = arith.muli %cbi, %four : index
        %cpart = trikeshed.slice %table[%cat, %cbli] : !s8 -> !s8
        trikeshed.yield %cpart : !s8
      }
      %cdl0 = memref.load %declen[%cni] : memref<?xi64>
      %cdl = arith.select %cnum, %cdl0, %c0 : i64
      %c11n = arith.muli %cn, %c11 : i64
      %cdo = arith.select %cnum, %c11n, %c0 : i64
      %cdoi = arith.index_cast %cdo : i64 to index
      %cdli = arith.index_cast %cdl : i64 to index
      %cdec = trikeshed.slice %decs[%cdoi, %cdli] : !s8 -> !s8
      %spc = trikeshed.slice %shw[%i32, %one] : !s8 -> !s8
      %mpart = trikeshed.combine %lb, %kq, %kesc, %kq, %req, %cword, %cq, %cesc, %cq, %cdec, %spc : !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8 -> !s8
      trikeshed.yield %mpart : !s8
    }
    %tst = arith.select %is1, %c25, %c24 : i64
    %tl = arith.select %is1, %c1, %c2 : i64
    %tsti = arith.index_cast %tst : i64 to index
    %tli = arith.index_cast %tl : i64 to index
    %tail = trikeshed.slice %shw[%tsti, %tli] : !s8 -> !s8
    %line = trikeshed.combine %head, %key, %eq, %vword, %vq, %vesc, %vq, %vdec, %list, %tail : !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8, !s8 -> !s8
    trikeshed.yield %line : !s8
  }
  %sz = trikeshed.size %lines : !s8
  %szw = arith.index_cast %sz : index to i64
  %out = func.call @nixsa_out(%ctx, %c1, %szw) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %od = func.call @nx_sa_desc8(%out, %szw) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m8
  %end = trikeshed.drain %lines, %om : !s8, !m8 -> index
  return
}

// ---- the entry: 0 the two files written (through nixsa_out), 1 __json is not JSON, 2 it is not an object.
// rec is confix.checked's record (`end` set: the store's reading); outs the outputs' SortedMap rows (name, path),
// rws the rewrites' (placeholder, path), both read in place (nx_sa_row).  The index is this function's lane: filled by
// confix.checked, read here, gone when it returns.
func.func @nixstore_ts_sattrs(%ctx: !llvm.ptr, %rec: !llvm.ptr, %outs: !llvm.ptr, %nout: i64, %rws: !llvm.ptr,
                              %nrw: i64) -> i32 {
  %index = trikeshed.lane : !rows
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c11 = arith.constant 11 : i64
  %t5 = arith.constant 5 : i8
  %ok = arith.constant 0 : i32
  %notjson = arith.constant 1 : i32
  %notobj = arith.constant 2 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %fault = confix.checked %rec, %index : !llvm.ptr, !rows
  %bad = arith.cmpi ne, %fault, %ok : i32
  %r = scf.if %bad -> (i32) {
    scf.yield %notjson : i32
  } else {
    %ltags = trikeshed.take %index[%i2] : !rows -> !l8
    %t0 = trikeshed.at %ltags[%z] : !l8, index -> i8
    %isobj = arith.cmpi eq, %t0, %t5 : i8
    %r2 = scf.if %isobj -> (i32) {
      // open, close and tag are read where the fill left them; `up` is drained into one series, for each row's
      // children out of the rows they are in
      %opens = trikeshed.take %index[%z] : !rows -> !l32
      %closes = trikeshed.take %index[%i1] : !rows -> !l32
      %lups = trikeshed.take %index[%i3] : !rows -> !l32
      %ups = trikeshed.drain %lups : !l32 -> !s32
      %nrows = trikeshed.size %ups : !s32
      %ids = trikeshed.series %nrows : !s32 {
      ^bb0(%i: index):
        %id = arith.index_cast %i : index to i32
        trikeshed.yield %id : i32
      }
      %kids, %kid = trikeshed.adjacency %ups, %ids over %nrows : !s32, !s32 -> !pieces, !s32
      %nkidi = trikeshed.size %kid : !s32
      %rows = arith.index_cast %nrows : index to i64
      %nkid = arith.index_cast %nkidi : index to i64
      %r1 = arith.addi %rows, %c1 : i64
      %nodes = arith.addi %r1, %nout : i64
      %k1 = arith.addi %nkid, %c1 : i64
      %nmem = arith.addi %k1, %nout : i64
      %ni = arith.index_cast %nodes : i64 to index
      %mi = arith.index_cast %nmem : i64 to index
      %nkind = memref.alloc(%ni) : memref<?xi64>
      %nptr = memref.alloc(%ni) : memref<?xi64>
      %nlen = memref.alloc(%ni) : memref<?xi64>
      %nfirst = memref.alloc(%ni) : memref<?xi64>
      %ncnt = memref.alloc(%ni) : memref<?xi64>
      %nsimple = memref.alloc(%ni) : memref<?xi64>
      %declen = memref.alloc(%ni) : memref<?xi64>
      %mkp = memref.alloc(%mi) : memref<?xi64>
      %mkl = memref.alloc(%mi) : memref<?xi64>
      %mval = memref.alloc(%mi) : memref<?xi64>
      %decn = arith.muli %rows, %c11 : i64
      %deci = arith.index_cast %decn : i64 to index
      %dec = memref.alloc(%deci) : memref<?xi8>
      func.call @nx_sa_nodes(%rec, %ctx, %opens, %closes, %ltags, %nkind, %nptr, %nlen)
        : (!llvm.ptr, !llvm.ptr, !l32, !l32, !l8, memref<?xi64>, memref<?xi64>, memref<?xi64>) -> ()
      func.call @nx_sa_members(%kids, %kid, %outs, %nout, %nkind, %nptr, %nlen, %nfirst, %ncnt, %mkp, %mkl, %mval)
        : (!pieces, !s32, !llvm.ptr, i64, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>,
           memref<?xi64>, memref<?xi64>, memref<?xi64>) -> ()
      func.call @nx_sa_rewrite(%ctx, %rows, %rws, %nrw, %nkind, %nptr, %nlen)
        : (!llvm.ptr, i64, !llvm.ptr, i64, memref<?xi64>, memref<?xi64>, memref<?xi64>) -> ()
      func.call @nx_sa_numbers(%nodes, %nkind, %nptr, %nsimple, %dec, %declen)
        : (i64, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi8>, memref<?xi64>) -> ()
      %ne2 = arith.muli %nodes, %c2 : i64
      %nei = arith.index_cast %ne2 : i64 to index
      %evn = memref.alloc(%nei) : memref<?xi64>
      %evm = memref.alloc(%nei) : memref<?xi64>
      %evt = memref.alloc(%nei) : memref<?xi64>
      %evc = memref.alloc(%nei) : memref<?xi64>
      %ne = func.call @nx_sa_walk(%nodes, %nkind, %nfirst, %ncnt, %mval, %evn, %evm, %evt, %evc)
        : (i64, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>,
           memref<?xi64>, memref<?xi64>) -> i64
      func.call @nx_sa_json(%ctx, %ne, %nkind, %nptr, %nlen, %mkp, %mkl, %evn, %evm, %evt, %evc)
        : (!llvm.ptr, i64, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>,
           memref<?xi64>, memref<?xi64>, memref<?xi64>) -> ()
      %rc = memref.load %ncnt[%z] : memref<?xi64>
      %rci = arith.index_cast %rc : i64 to index
      %shk = memref.alloc(%rci) : memref<?xi64>
      func.call @nx_sa_shkinds(%nkind, %nfirst, %ncnt, %mkp, %mkl, %mval, %nsimple, %shk)
        : (memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>,
           memref<?xi64>) -> ()
      func.call @nx_sa_sh(%ctx, %nkind, %nptr, %nlen, %nfirst, %ncnt, %mkp, %mkl, %mval, %dec, %declen, %shk)
        : (!llvm.ptr, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>, memref<?xi64>,
           memref<?xi64>, memref<?xi64>, memref<?xi8>, memref<?xi64>, memref<?xi64>) -> ()
      scf.yield %ok : i32
    } else {
      scf.yield %notobj : i32
    }
    scf.yield %r2 : i32
  }
  return %r : i32
}
