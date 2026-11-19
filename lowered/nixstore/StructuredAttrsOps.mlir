// The .attrs.json serialization hollowed out of lib/Store/StructuredAttrs.cpp: the DOM -> text composition of
// dump() (the object/array bracket + comma + colon stitching, the string escaping, the number text) and
// nixstore::jsonEscape (lib/Store/StorePaths.cpp).  The C++ keeps the DOM (JV/Member), its parsing/building, the
// .attrs.sh shell quoting, and three pure-read callbacks into the DOM (nixsa_info/nixsa_kid/nixsa_key).  The
// composition is here: each node's children are drained once into cells (fresh buffers sized by nixstore_ts_size),
// then ONE lazy trikeshed.combineAll over the cells + the punctuation slices stitches the node, drained once into
// the caller's room (the mlnixci builder's way).  The escape is PrintOps.mlir's Nix JSON table (\b \f for 0x08
// 0x0c, \u00xx below 0x20): a combineAll of table slices.  nixstore_ts_size is the same recursion without writes.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!text = !trikeshed.series<i8>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the DOM reads (StructuredAttrs.cpp): info = [kind, b, raw ptr, raw len, arr count, obj count]; kid = arr[i] or
// obj[i].value (isobj 1); key = [ptr, len] of obj[i].key.  Pure reads: combineAll's region may run twice.
func.func private @nixsa_info(!llvm.ptr, !llvm.ptr)
func.func private @nixsa_kid(!llvm.ptr, i64, i64) -> !llvm.ptr
func.func private @nixsa_key(!llvm.ptr, i64, !llvm.ptr)

memref.global "private" constant @sa_esc : memref<1536xi8> = dense<"0x5c75303030305c75303030315c75303030325c75303030335c75303030345c75303030355c75303030365c75303030375c62000000005c74000000005c6e000000005c75303030625c66000000005c72000000005c75303030655c75303030665c75303031305c75303031315c75303031325c75303031335c75303031345c75303031355c75303031365c75303031375c75303031385c75303031395c75303031615c75303031625c75303031635c75303031645c75303031655c75303031662000000000002100000000005c22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b00000000003c00000000003d00000000003e00000000003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c5c000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @sa_esc_len : memref<256xi8> = dense<"0x06060606060606060202020602020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">
memref.global "private" constant @sa_null : memref<4xi8> = dense<"0x6e756c6c">
memref.global "private" constant @sa_bools : memref<9xi8> = dense<"0x7472756566616c7365">
memref.global "private" constant @sa_lbrack : memref<1xi8> = dense<91>
memref.global "private" constant @sa_rbrack : memref<1xi8> = dense<93>
memref.global "private" constant @sa_lbrace : memref<1xi8> = dense<123>
memref.global "private" constant @sa_rbrace : memref<1xi8> = dense<125>
memref.global "private" constant @sa_comma : memref<1xi8> = dense<44>
memref.global "private" constant @sa_colon : memref<1xi8> = dense<58>
memref.global "private" constant @sa_quote : memref<1xi8> = dense<34>

// the descriptor of n bytes at p (a struct, not a memref: returning it allocates nothing and clones nothing)
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

// the escaped length of n bytes at p: the two quotes plus each byte's escape length (the table's second row)
func.func private @nx_sa_esize(%p: !llvm.ptr, %n: i64) -> i64 {
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %two = arith.constant 2 : i64
  %ds = func.call @nx_sa_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m8
  %xs = builtin.unrealized_conversion_cast %ms : !m8 to !text
  %lg = memref.get_global @sa_esc_len : memref<256xi8>
  %lengths = trikeshed.text %lg : memref<256xi8> -> !text
  %ni = arith.index_cast %n : i64 to index
  %sum = scf.for %k = %c0i to %ni step %c1i iter_args(%acc = %c0i) -> index {
    %b = trikeshed.at %xs[%k] : !text, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %l = trikeshed.at %lengths[%bi] : !text, index -> i8
    %li = arith.index_castui %l : i8 to index
    %acc2 = arith.addi %acc, %li : index
    scf.yield %acc2 : index
  }
  %si = arith.index_cast %sum : index to i64
  %r = arith.addi %si, %two : i64
  return %r : i64
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

// the size of v's serialization: the same recursion as nixstore_ts_dump without the writes.  Null 4, Bool 4/5,
// Num the raw text's length, Str the escaped length, Arr/Obj the brackets + the children + the commas between.
func.func @nixstore_ts_size(%v: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %ip = llvm.alloca %c6 x i64 : (i64) -> !llvm.ptr
  func.call @nixsa_info(%v, %ip) : (!llvm.ptr, !llvm.ptr) -> ()
  %kp0 = llvm.getelementptr %ip[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %kind = llvm.load %kp0 : !llvm.ptr -> i64
  %isnull = arith.cmpi eq, %kind, %c0 : i64
  %r = scf.if %isnull -> i64 {
    scf.yield %c4 : i64
  } else {
    %isbool = arith.cmpi eq, %kind, %c1 : i64
    %rb = scf.if %isbool -> i64 {
      %bp = llvm.getelementptr %ip[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %b = llvm.load %bp : !llvm.ptr -> i64
      %bt = arith.cmpi ne, %b, %c0 : i64
      %rr = arith.select %bt, %c4, %c5 : i64
      scf.yield %rr : i64
    } else {
      %isnum = arith.cmpi eq, %kind, %c2 : i64
      %rn = scf.if %isnum -> i64 {
        %np = llvm.getelementptr %ip[24] : (!llvm.ptr) -> !llvm.ptr, i8
        %nl = llvm.load %np : !llvm.ptr -> i64
        scf.yield %nl : i64
      } else {
        %isstr = arith.cmpi eq, %kind, %c3 : i64
        %rs = scf.if %isstr -> i64 {
          %pp = llvm.getelementptr %ip[16] : (!llvm.ptr) -> !llvm.ptr, i8
          %pb = llvm.load %pp : !llvm.ptr -> i64
          %p = llvm.inttoptr %pb : i64 to !llvm.ptr
          %np2 = llvm.getelementptr %ip[24] : (!llvm.ptr) -> !llvm.ptr, i8
          %n = llvm.load %np2 : !llvm.ptr -> i64
          %e = func.call @nx_sa_esize(%p, %n) : (!llvm.ptr, i64) -> i64
          scf.yield %e : i64
        } else {
          %isarr = arith.cmpi eq, %kind, %c4 : i64
          %ra = scf.if %isarr -> i64 {
            %nap = llvm.getelementptr %ip[32] : (!llvm.ptr) -> !llvm.ptr, i8
            %na = llvm.load %nap : !llvm.ptr -> i64
            %nai = arith.index_cast %na : i64 to index
            %sum = scf.for %k = %c0i to %nai step %c1i iter_args(%acc = %c0i) -> index {
              %ki = arith.index_cast %k : index to i64
              %kid = func.call @nixsa_kid(%v, %ki, %c0) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %sz = func.call @nixstore_ts_size(%kid) : (!llvm.ptr) -> i64
              %szi = arith.index_cast %sz : i64 to index
              %acc2 = arith.addi %acc, %szi : index
              scf.yield %acc2 : index
            }
            %sum64 = arith.index_cast %sum : index to i64
            %base = arith.addi %sum64, %c2 : i64
            %has = arith.cmpi ugt, %na, %c0 : i64
            %nm1 = arith.subi %na, %c1 : i64
            %commas = arith.select %has, %nm1, %c0 : i64
            %rra = arith.addi %base, %commas : i64
            scf.yield %rra : i64
          } else {
            %nop = llvm.getelementptr %ip[40] : (!llvm.ptr) -> !llvm.ptr, i8
            %no = llvm.load %nop : !llvm.ptr -> i64
            %noi = arith.index_cast %no : i64 to index
            %kpo = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
            %sumo = scf.for %k2 = %c0i to %noi step %c1i iter_args(%acco = %c0i) -> index {
              %k2i = arith.index_cast %k2 : index to i64
              func.call @nixsa_key(%v, %k2i, %kpo) : (!llvm.ptr, i64, !llvm.ptr) -> ()
              %kpp = llvm.getelementptr %kpo[0] : (!llvm.ptr) -> !llvm.ptr, i8
              %kpb = llvm.load %kpp : !llvm.ptr -> i64
              %kptr = llvm.inttoptr %kpb : i64 to !llvm.ptr
              %knp = llvm.getelementptr %kpo[8] : (!llvm.ptr) -> !llvm.ptr, i8
              %klen = llvm.load %knp : !llvm.ptr -> i64
              %ksz = func.call @nx_sa_esize(%kptr, %klen) : (!llvm.ptr, i64) -> i64
              %kid2 = func.call @nixsa_kid(%v, %k2i, %c1) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %vsz = func.call @nixstore_ts_size(%kid2) : (!llvm.ptr) -> i64
              %kszi = arith.index_cast %ksz : i64 to index
              %vszi = arith.index_cast %vsz : i64 to index
              %t1 = arith.addi %acco, %kszi : index
              %t2 = arith.addi %t1, %c1i : index
              %t3 = arith.addi %t2, %vszi : index
              scf.yield %t3 : index
            }
            %sumo64 = arith.index_cast %sumo : index to i64
            %baseo = arith.addi %sumo64, %c2 : i64
            %haso = arith.cmpi ugt, %no, %c0 : i64
            %nom1 = arith.subi %no, %c1 : i64
            %commaso = arith.select %haso, %nom1, %c0 : i64
            %rro = arith.addi %baseo, %commaso : i64
            scf.yield %rro : i64
          }
          scf.yield %ra : i64
        }
        scf.yield %rs : i64
      }
      scf.yield %rn : i64
    }
    scf.yield %rb : i64
  }
  return %r : i64
}

// v's serialization drained into `into` (room cap, at least nixstore_ts_size(v)).  A leaf is one view drained;
// an Arr/Obj drains each child once into a cell (a fresh buffer of the child's size), then ONE combineAll over
// the cells and the punctuation slices, drained once.  The recursion is func.call back into these entries.
func.func @nixstore_ts_dump(%v: !llvm.ptr, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c0i = arith.constant 0 : index
  %c1i = arith.constant 1 : index
  %c4i = arith.constant 4 : index
  %c5i = arith.constant 5 : index
  %ip = llvm.alloca %c6 x i64 : (i64) -> !llvm.ptr
  func.call @nixsa_info(%v, %ip) : (!llvm.ptr, !llvm.ptr) -> ()
  %kp0 = llvm.getelementptr %ip[0] : (!llvm.ptr) -> !llvm.ptr, i8
  %kind = llvm.load %kp0 : !llvm.ptr -> i64
  %isnull = arith.cmpi eq, %kind, %c0 : i64
  %r = scf.if %isnull -> i64 {
    %ng = memref.get_global @sa_null : memref<4xi8>
    %nt = trikeshed.text %ng : memref<4xi8> -> !text
    %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m8
    %end = trikeshed.drain %nt, %mi : !text, !m8 -> index
    %endi = arith.index_cast %end : index to i64
    scf.yield %endi : i64
  } else {
    %isbool = arith.cmpi eq, %kind, %c1 : i64
    %rb = scf.if %isbool -> i64 {
      %bp = llvm.getelementptr %ip[8] : (!llvm.ptr) -> !llvm.ptr, i8
      %b = llvm.load %bp : !llvm.ptr -> i64
      %bnz = arith.cmpi ne, %b, %c0 : i64
      %start = arith.select %bnz, %c0i, %c4i : index
      %len = arith.select %bnz, %c4i, %c5i : index
      %bg = memref.get_global @sa_bools : memref<9xi8>
      %bt = trikeshed.text %bg : memref<9xi8> -> !text
      %bs = trikeshed.slice %bt[%start, %len] : !text -> !text
      %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
      %mi = builtin.unrealized_conversion_cast %di : !d to !m8
      %end = trikeshed.drain %bs, %mi : !text, !m8 -> index
      %endi = arith.index_cast %end : index to i64
      scf.yield %endi : i64
    } else {
      %isnum = arith.cmpi eq, %kind, %c2 : i64
      %rn = scf.if %isnum -> i64 {
        %pp = llvm.getelementptr %ip[16] : (!llvm.ptr) -> !llvm.ptr, i8
        %pb = llvm.load %pp : !llvm.ptr -> i64
        %p = llvm.inttoptr %pb : i64 to !llvm.ptr
        %np = llvm.getelementptr %ip[24] : (!llvm.ptr) -> !llvm.ptr, i8
        %n = llvm.load %np : !llvm.ptr -> i64
        %ds = func.call @nx_sa_desc8(%p, %n) : (!llvm.ptr, i64) -> !d
        %ms = builtin.unrealized_conversion_cast %ds : !d to !m8
        %xs = builtin.unrealized_conversion_cast %ms : !m8 to !text
        %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
        %mi = builtin.unrealized_conversion_cast %di : !d to !m8
        %end = trikeshed.drain %xs, %mi : !text, !m8 -> index
        %endi = arith.index_cast %end : index to i64
        scf.yield %endi : i64
      } else {
        %isstr = arith.cmpi eq, %kind, %c3 : i64
        %rs = scf.if %isstr -> i64 {
          %pp = llvm.getelementptr %ip[16] : (!llvm.ptr) -> !llvm.ptr, i8
          %pb = llvm.load %pp : !llvm.ptr -> i64
          %p = llvm.inttoptr %pb : i64 to !llvm.ptr
          %np = llvm.getelementptr %ip[24] : (!llvm.ptr) -> !llvm.ptr, i8
          %n = llvm.load %np : !llvm.ptr -> i64
          %w = func.call @nixstore_ts_escape(%p, %n, %into, %cap) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
          scf.yield %w : i64
        } else {
          %isarr = arith.cmpi eq, %kind, %c4 : i64
          %ra = scf.if %isarr -> i64 {
            %nap = llvm.getelementptr %ip[32] : (!llvm.ptr) -> !llvm.ptr, i8
            %na = llvm.load %nap : !llvm.ptr -> i64
            %nai = arith.index_cast %na : i64 to index
            %lens = memref.alloc(%nai) : memref<?xi64>
            %offs = memref.alloc(%nai) : memref<?xi64>
            %total = scf.for %k = %c0i to %nai step %c1i iter_args(%acc = %c0i) -> index {
              %ki = arith.index_cast %k : index to i64
              %kid = func.call @nixsa_kid(%v, %ki, %c0) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %sz = func.call @nixstore_ts_size(%kid) : (!llvm.ptr) -> i64
              %szi = arith.index_cast %sz : i64 to index
              memref.store %sz, %lens[%k] : memref<?xi64>
              %acc2 = arith.addi %acc, %szi : index
              scf.yield %acc2 : index
            }
            %scratch = memref.alloc(%total) : memref<?xi8>
            %si = memref.extract_aligned_pointer_as_index %scratch : memref<?xi8> -> index
            %sb = arith.index_cast %si : index to i64
            scf.for %k2 = %c0i to %nai step %c1i iter_args(%o = %c0i) -> index {
              %k2i = arith.index_cast %k2 : index to i64
              %oi = arith.index_cast %o : index to i64
              memref.store %oi, %offs[%k2] : memref<?xi64>
              %ln = memref.load %lens[%k2] : memref<?xi64>
              %pb = arith.addi %sb, %oi : i64
              %pp = llvm.inttoptr %pb : i64 to !llvm.ptr
              %kid2 = func.call @nixsa_kid(%v, %k2i, %c0) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %w = func.call @nixstore_ts_dump(%kid2, %pp, %ln) : (!llvm.ptr, !llvm.ptr, i64) -> i64
              %lni = arith.index_cast %ln : i64 to index
              %o2 = arith.addi %o, %lni : index
              scf.yield %o2 : index
            }
            %inner, %wh = trikeshed.combineAll %nai : !text, !pieces {
            ^bb0(%k3: index):
              %hasprev = arith.cmpi ugt, %k3, %c0i : index
              %seplen = arith.select %hasprev, %c1i, %c0i : index
              %cg = memref.get_global @sa_comma : memref<1xi8>
              %ct = trikeshed.text %cg : memref<1xi8> -> !text
              %sep = trikeshed.slice %ct[%c0i, %seplen] : !text -> !text
              %of = memref.load %offs[%k3] : memref<?xi64>
              %ofi = arith.index_cast %of : i64 to index
              %ln2 = memref.load %lens[%k3] : memref<?xi64>
              %ln2i = arith.index_cast %ln2 : i64 to index
              %sm = builtin.unrealized_conversion_cast %scratch : memref<?xi8> to !m8
              %sx = builtin.unrealized_conversion_cast %sm : !m8 to !text
              %child = trikeshed.slice %sx[%ofi, %ln2i] : !text -> !text
              %part = trikeshed.combine %sep, %child : !text, !text -> !text
              trikeshed.yield %part : !text
            }
            %lg = memref.get_global @sa_lbrack : memref<1xi8>
            %lt = trikeshed.text %lg : memref<1xi8> -> !text
            %rg = memref.get_global @sa_rbrack : memref<1xi8>
            %rt = trikeshed.text %rg : memref<1xi8> -> !text
            %o1 = trikeshed.combine %lt, %inner : !text, !text -> !text
            %all = trikeshed.combine %o1, %rt : !text, !text -> !text
            %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
            %mi = builtin.unrealized_conversion_cast %di : !d to !m8
            %end = trikeshed.drain %all, %mi : !text, !m8 -> index
            %endi = arith.index_cast %end : index to i64
            scf.yield %endi : i64
          } else {
            %nop = llvm.getelementptr %ip[40] : (!llvm.ptr) -> !llvm.ptr, i8
            %no = llvm.load %nop : !llvm.ptr -> i64
            %noi = arith.index_cast %no : i64 to index
            %klens = memref.alloc(%noi) : memref<?xi64>
            %koffs = memref.alloc(%noi) : memref<?xi64>
            %vlens = memref.alloc(%noi) : memref<?xi64>
            %voffs = memref.alloc(%noi) : memref<?xi64>
            %kpo = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
            %ktot, %vtot = scf.for %k4 = %c0i to %noi step %c1i iter_args(%ka = %c0i, %va = %c0i) -> (index, index) {
              %k4i = arith.index_cast %k4 : index to i64
              func.call @nixsa_key(%v, %k4i, %kpo) : (!llvm.ptr, i64, !llvm.ptr) -> ()
              %kpp = llvm.getelementptr %kpo[0] : (!llvm.ptr) -> !llvm.ptr, i8
              %kpb = llvm.load %kpp : !llvm.ptr -> i64
              %kptr = llvm.inttoptr %kpb : i64 to !llvm.ptr
              %knp = llvm.getelementptr %kpo[8] : (!llvm.ptr) -> !llvm.ptr, i8
              %klen = llvm.load %knp : !llvm.ptr -> i64
              %ksz = func.call @nx_sa_esize(%kptr, %klen) : (!llvm.ptr, i64) -> i64
              %kszi = arith.index_cast %ksz : i64 to index
              memref.store %ksz, %klens[%k4] : memref<?xi64>
              %kid4 = func.call @nixsa_kid(%v, %k4i, %c1) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %vsz = func.call @nixstore_ts_size(%kid4) : (!llvm.ptr) -> i64
              %vszi = arith.index_cast %vsz : i64 to index
              memref.store %vsz, %vlens[%k4] : memref<?xi64>
              %ka2 = arith.addi %ka, %kszi : index
              %va2 = arith.addi %va, %vszi : index
              scf.yield %ka2, %va2 : index, index
            }
            %kscratch = memref.alloc(%ktot) : memref<?xi8>
            %vscratch = memref.alloc(%vtot) : memref<?xi8>
            %ksi = memref.extract_aligned_pointer_as_index %kscratch : memref<?xi8> -> index
            %ksb = arith.index_cast %ksi : index to i64
            %vsi = memref.extract_aligned_pointer_as_index %vscratch : memref<?xi8> -> index
            %vsb = arith.index_cast %vsi : index to i64
            scf.for %k5 = %c0i to %noi step %c1i iter_args(%ko = %c0i, %vo = %c0i) -> (index, index) {
              %k5i = arith.index_cast %k5 : index to i64
              %koi = arith.index_cast %ko : index to i64
              %voi = arith.index_cast %vo : index to i64
              memref.store %koi, %koffs[%k5] : memref<?xi64>
              memref.store %voi, %voffs[%k5] : memref<?xi64>
              func.call @nixsa_key(%v, %k5i, %kpo) : (!llvm.ptr, i64, !llvm.ptr) -> ()
              %kpp2 = llvm.getelementptr %kpo[0] : (!llvm.ptr) -> !llvm.ptr, i8
              %kpb2 = llvm.load %kpp2 : !llvm.ptr -> i64
              %kptr2 = llvm.inttoptr %kpb2 : i64 to !llvm.ptr
              %knp2 = llvm.getelementptr %kpo[8] : (!llvm.ptr) -> !llvm.ptr, i8
              %klen2 = llvm.load %knp2 : !llvm.ptr -> i64
              %kl2 = memref.load %klens[%k5] : memref<?xi64>
              %kpb3 = arith.addi %ksb, %koi : i64
              %kbp = llvm.inttoptr %kpb3 : i64 to !llvm.ptr
              %kw = func.call @nixstore_ts_escape(%kptr2, %klen2, %kbp, %kl2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
              %kid5 = func.call @nixsa_kid(%v, %k5i, %c1) : (!llvm.ptr, i64, i64) -> !llvm.ptr
              %vl2 = memref.load %vlens[%k5] : memref<?xi64>
              %vpb = arith.addi %vsb, %voi : i64
              %vbp = llvm.inttoptr %vpb : i64 to !llvm.ptr
              %vw = func.call @nixstore_ts_dump(%kid5, %vbp, %vl2) : (!llvm.ptr, !llvm.ptr, i64) -> i64
              %kl2i = arith.index_cast %kl2 : i64 to index
              %vl2i = arith.index_cast %vl2 : i64 to index
              %ko2 = arith.addi %ko, %kl2i : index
              %vo2 = arith.addi %vo, %vl2i : index
              scf.yield %ko2, %vo2 : index, index
            }
            %innero, %who = trikeshed.combineAll %noi : !text, !pieces {
            ^bb0(%k6: index):
              %hp = arith.cmpi ugt, %k6, %c0i : index
              %sl = arith.select %hp, %c1i, %c0i : index
              %cg = memref.get_global @sa_comma : memref<1xi8>
              %ct = trikeshed.text %cg : memref<1xi8> -> !text
              %sep = trikeshed.slice %ct[%c0i, %sl] : !text -> !text
              %kof = memref.load %koffs[%k6] : memref<?xi64>
              %kofi = arith.index_cast %kof : i64 to index
              %kl3 = memref.load %klens[%k6] : memref<?xi64>
              %kl3i = arith.index_cast %kl3 : i64 to index
              %ksm = builtin.unrealized_conversion_cast %kscratch : memref<?xi8> to !m8
              %ksx = builtin.unrealized_conversion_cast %ksm : !m8 to !text
              %key = trikeshed.slice %ksx[%kofi, %kl3i] : !text -> !text
              %cog = memref.get_global @sa_colon : memref<1xi8>
              %cot = trikeshed.text %cog : memref<1xi8> -> !text
              %vof = memref.load %voffs[%k6] : memref<?xi64>
              %vofi = arith.index_cast %vof : i64 to index
              %vl3 = memref.load %vlens[%k6] : memref<?xi64>
              %vl3i = arith.index_cast %vl3 : i64 to index
              %vsm = builtin.unrealized_conversion_cast %vscratch : memref<?xi8> to !m8
              %vsx = builtin.unrealized_conversion_cast %vsm : !m8 to !text
              %val = trikeshed.slice %vsx[%vofi, %vl3i] : !text -> !text
              %p1 = trikeshed.combine %sep, %key : !text, !text -> !text
              %p2 = trikeshed.combine %p1, %cot : !text, !text -> !text
              %part = trikeshed.combine %p2, %val : !text, !text -> !text
              trikeshed.yield %part : !text
            }
            %lbg = memref.get_global @sa_lbrace : memref<1xi8>
            %lbt = trikeshed.text %lbg : memref<1xi8> -> !text
            %rbg = memref.get_global @sa_rbrace : memref<1xi8>
            %rbt = trikeshed.text %rbg : memref<1xi8> -> !text
            %o1o = trikeshed.combine %lbt, %innero : !text, !text -> !text
            %allo = trikeshed.combine %o1o, %rbt : !text, !text -> !text
            %di = func.call @nx_sa_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
            %mi = builtin.unrealized_conversion_cast %di : !d to !m8
            %end = trikeshed.drain %allo, %mi : !text, !m8 -> index
            %endi = arith.index_cast %end : index to i64
            scf.yield %endi : i64
          }
          scf.yield %ra : i64
        }
        scf.yield %rs : i64
      }
      scf.yield %rn : i64
    }
    scf.yield %rb : i64
  }
  return %r : i64
}
