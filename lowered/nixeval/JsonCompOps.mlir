// The JSON composition of a set, a list or a single value, hollowed out of lib/Eval/Formats.cpp (printValueAsJSON):
// ONE trikeshed.combineAll over the rows, each row's pieces chosen and emitted here from the row's record, the whole
// drained once into the caller's room.  A set row is  sep, "key", ':', value;  a list row  sep, value;  the root (kind
// 2) is one row with no separator, key or brackets.  Brackets: set '{' '}', list '[' ']'.
//
// The record (six i64 words per row, the C++ JsonRec):  0 kind (0 not described yet, 1 int, 2 bool, 3 null, 4 float,
// 5 a string's bytes, to escape, 6 a composite's rendered bytes, raw), 1 payload (int / bool / float bits), 2 offset of the
// bytes in the arena (the base passed in), 3 bytes length, 4 key ptr, 5 key length.  A row is described by the callback nixev_json_row ONCE, on its first use (the
// combineAll's size pass): the callback does the forcing, coercions, CallDepth and error traces in the old order, and the
// later passes only read the record.  The pieces are chosen by zero lengths (no view is selected): each candidate is
// built from the record with its length selected to 0 when it is not the row's kind.
//
// Entry  nixev_ts_json_comp(ctx, kind, n, recs, base, into, cap) -> the total byte count.  kind 0 set (n rows), 1 list (n
// rows), 2 root (n = 1).  A call with cap 0 runs the size pass (describing every row); the caller reserves that room
// and calls again to drain.  Digits go through nixev_ts_int (PrintOps.mlir) and a float through nixstore_ts_jsonfloat
// (JsonFloat.mlir), both into scratch allocas hoisted to the function top.
!text = !trikeshed.series<i8>
!coords = !trikeshed.series<!trikeshed.twinpacked<i32>>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// { } [ ] , :  (0..5)   true false null (6, 10, 15)   the quote (19)
memref.global "private" constant @jc_blob : memref<20xi8> = dense<"0x7b7d5b5d2c3a7472756566616c73656e756c6c22">
memref.global "private" constant @jc_esc : memref<1536xi8> = dense<"0x5c75303030305c75303030315c75303030325c75303030335c75303030345c75303030355c75303030365c75303030375c62000000005c74000000005c6e000000005c75303030625c66000000005c72000000005c75303030655c75303030665c75303031305c75303031315c75303031325c75303031335c75303031345c75303031355c75303031365c75303031375c75303031385c75303031395c75303031615c75303031625c75303031635c75303031645c75303031655c75303031662000000000002100000000005c22000000002300000000002400000000002500000000002600000000002700000000002800000000002900000000002a00000000002b00000000002c00000000002d00000000002e00000000002f00000000003000000000003100000000003200000000003300000000003400000000003500000000003600000000003700000000003800000000003900000000003a00000000003b00000000003c00000000003d00000000003e00000000003f00000000004000000000004100000000004200000000004300000000004400000000004500000000004600000000004700000000004800000000004900000000004a00000000004b00000000004c00000000004d00000000004e00000000004f00000000005000000000005100000000005200000000005300000000005400000000005500000000005600000000005700000000005800000000005900000000005a00000000005b00000000005c5c000000005d00000000005e00000000005f00000000006000000000006100000000006200000000006300000000006400000000006500000000006600000000006700000000006800000000006900000000006a00000000006b00000000006c00000000006d00000000006e00000000006f00000000007000000000007100000000007200000000007300000000007400000000007500000000007600000000007700000000007800000000007900000000007a00000000007b00000000007c00000000007d00000000007e00000000007f00000000008000000000008100000000008200000000008300000000008400000000008500000000008600000000008700000000008800000000008900000000008a00000000008b00000000008c00000000008d00000000008e00000000008f00000000009000000000009100000000009200000000009300000000009400000000009500000000009600000000009700000000009800000000009900000000009a00000000009b00000000009c00000000009d00000000009e00000000009f0000000000a00000000000a10000000000a20000000000a30000000000a40000000000a50000000000a60000000000a70000000000a80000000000a90000000000aa0000000000ab0000000000ac0000000000ad0000000000ae0000000000af0000000000b00000000000b10000000000b20000000000b30000000000b40000000000b50000000000b60000000000b70000000000b80000000000b90000000000ba0000000000bb0000000000bc0000000000bd0000000000be0000000000bf0000000000c00000000000c10000000000c20000000000c30000000000c40000000000c50000000000c60000000000c70000000000c80000000000c90000000000ca0000000000cb0000000000cc0000000000cd0000000000ce0000000000cf0000000000d00000000000d10000000000d20000000000d30000000000d40000000000d50000000000d60000000000d70000000000d80000000000d90000000000da0000000000db0000000000dc0000000000dd0000000000de0000000000df0000000000e00000000000e10000000000e20000000000e30000000000e40000000000e50000000000e60000000000e70000000000e80000000000e90000000000ea0000000000eb0000000000ec0000000000ed0000000000ee0000000000ef0000000000f00000000000f10000000000f20000000000f30000000000f40000000000f50000000000f60000000000f70000000000f80000000000f90000000000fa0000000000fb0000000000fc0000000000fd0000000000fe0000000000ff0000000000">
memref.global "private" constant @jc_esc_len : memref<256xi8> = dense<"0x06060606060606060202020602020606060606060606060606060606060606060101020101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010201010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101">

func.func private @nixev_json_row(!llvm.ptr, i64, !llvm.ptr)
func.func private @nixev_json_base(!llvm.ptr) -> !llvm.ptr
func.func private @nixev_ts_int(i64, !llvm.ptr, i64) -> i64
func.func private @nixstore_ts_jsonfloat(f64, !llvm.ptr, !llvm.ptr) -> i64

// the descriptor of n bytes at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @jc_desc8(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @nixev_ts_json_comp(%ctx: !llvm.ptr, %kind: i32, %n: i64, %recs: !llvm.ptr, %base: !llvm.ptr, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c3 = arith.constant 3 : index
  %c4 = arith.constant 4 : index
  %c5 = arith.constant 5 : index
  %c6 = arith.constant 6 : index
  %c10 = arith.constant 10 : index
  %c15 = arith.constant 15 : index
  %c19 = arith.constant 19 : index
  %c0_64 = arith.constant 0 : i64
  %c1_64 = arith.constant 1 : i64
  %c2_64 = arith.constant 2 : i64
  %c3_64 = arith.constant 3 : i64
  %c4_64 = arith.constant 4 : i64
  %c5_64 = arith.constant 5 : i64
  %c6_64 = arith.constant 6 : i64
  %c21_64 = arith.constant 21 : i64
  %c32_64 = arith.constant 32 : i64
  %c64_64 = arith.constant 64 : i64
  %k0 = arith.constant 0 : i32
  %k2 = arith.constant 2 : i32
  %isSetK = arith.cmpi eq, %kind, %k0 : i32
  %isRoot = arith.cmpi eq, %kind, %k2 : i32
  %ni = arith.index_cast %n : i64 to index
  %openi = arith.select %isSetK, %c0, %c2 : index
  %closei = arith.select %isSetK, %c1, %c3 : index
  %ol = arith.select %isRoot, %c0, %c1 : index
  %kql = arith.select %isSetK, %c1, %c0 : index
  %bg = memref.get_global @jc_blob : memref<20xi8>
  %blob = trikeshed.text %bg : memref<20xi8> -> !text
  %eg = memref.get_global @jc_esc : memref<1536xi8>
  %etab = trikeshed.text %eg : memref<1536xi8> -> !text
  %lg = memref.get_global @jc_esc_len : memref<256xi8>
  %elens = trikeshed.text %lg : memref<256xi8> -> !text
  // the scratch of an int's digits or a float's text (32) and of snprintf (64), hoisted: an alloca in a loop grows the stack
  %sout = llvm.alloca %c32_64 x i8 : (i64) -> !llvm.ptr
  %sbuf = llvm.alloca %c64_64 x i8 : (i64) -> !llvm.ptr
  %all, %co = trikeshed.combineAll %ni : !text, !coords {
  ^bb0(%j: index):
    %j64 = arith.index_cast %j : index to i64
    %jm = arith.muli %j64, %c6_64 : i64
    %rp = llvm.getelementptr %recs[%jm] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %k0v = llvm.load %rp : !llvm.ptr -> i64
    %miss = arith.cmpi eq, %k0v, %c0_64 : i64
    // a described row may have grown the arena: the bytes are read from its base as it is now
    %bcur = scf.if %miss -> (!llvm.ptr) {
      func.call @nixev_json_row(%ctx, %j64, %rp) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %bn = func.call @nixev_json_base(%ctx) : (!llvm.ptr) -> !llvm.ptr
      scf.yield %bn : !llvm.ptr
    } else {
      scf.yield %base : !llvm.ptr
    }
    %kd = llvm.load %rp : !llvm.ptr -> i64
    %pa = llvm.getelementptr %rp[%c1_64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %payload = llvm.load %pa : !llvm.ptr -> i64
    %pb = llvm.getelementptr %rp[%c2_64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %poff = llvm.load %pb : !llvm.ptr -> i64
    %p = llvm.getelementptr %bcur[%poff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pc = llvm.getelementptr %rp[%c3_64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %nl = llvm.load %pc : !llvm.ptr -> i64
    %pd = llvm.getelementptr %rp[%c4_64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %kpbits = llvm.load %pd : !llvm.ptr -> i64
    %kp = llvm.inttoptr %kpbits : i64 to !llvm.ptr
    %pe = llvm.getelementptr %rp[%c5_64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    %knl = llvm.load %pe : !llvm.ptr -> i64
    %isInt = arith.cmpi eq, %kd, %c1_64 : i64
    %isBool = arith.cmpi eq, %kd, %c2_64 : i64
    %isNull = arith.cmpi eq, %kd, %c3_64 : i64
    %isFloat = arith.cmpi eq, %kd, %c4_64 : i64
    %isStr = arith.cmpi eq, %kd, %c5_64 : i64
    %isRaw = arith.cmpi eq, %kd, %c6_64 : i64
    // an int's digits or a float's text: the length from the emitter the kind selects, 0 for the others
    %dl = scf.if %isInt -> (i64) {
      %dI = func.call @nixev_ts_int(%payload, %sout, %c21_64) : (i64, !llvm.ptr, i64) -> i64
      scf.yield %dI : i64
    } else {
      %dF = scf.if %isFloat -> (i64) {
        %fx = arith.bitcast %payload : i64 to f64
        %fl = func.call @nixstore_ts_jsonfloat(%fx, %sout, %sbuf) : (f64, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %fl : i64
      } else {
        scf.yield %c0_64 : i64
      }
      scf.yield %dF : i64
    }
    %dd = func.call @jc_desc8(%sout, %dl) : (!llvm.ptr, i64) -> !d
    %dm = builtin.unrealized_conversion_cast %dd : !d to !m8
    %digits = builtin.unrealized_conversion_cast %dm : !m8 to !text
    // true / false / null: a word of the blob, its offset and length selected
    %bnz = arith.cmpi ne, %payload, %c0_64 : i64
    %bo1 = arith.select %bnz, %c6, %c10 : index
    %boff = arith.select %isNull, %c15, %bo1 : index
    %bl1 = arith.select %bnz, %c4, %c5 : index
    %bl2 = arith.select %isNull, %c4, %c0 : index
    %blen = arith.select %isBool, %bl1, %bl2 : index
    %word = trikeshed.slice %blob[%boff, %blen] : !text -> !text
    // a set row's key: its bytes (the name, for a set; none for a list or the root), quoted and escaped
    %knc = arith.index_cast %knl : i64 to index
    %kdsrcd = func.call @jc_desc8(%kp, %knl) : (!llvm.ptr, i64) -> !d
    %kdsrcm = builtin.unrealized_conversion_cast %kdsrcd : !d to !m8
    %kdsrc = builtin.unrealized_conversion_cast %kdsrcm : !m8 to !text
    %kesc, %kco = trikeshed.combineAll %knc : !text, !coords {
    ^bb0(%ki: index):
      %kc = trikeshed.at %kdsrc[%ki] : !text, index -> i8
      %kci = arith.index_castui %kc : i8 to index
      %kl = trikeshed.at %elens[%kci] : !text, index -> i8
      %kli = arith.index_castui %kl : i8 to index
      %kat = arith.muli %kci, %c6 : index
      %kpart = trikeshed.slice %etab[%kat, %kli] : !text -> !text
      trikeshed.yield %kpart : !text
    }
    %kq = trikeshed.slice %blob[%c19, %kql] : !text -> !text
    %colon = trikeshed.slice %blob[%c5, %kql] : !text -> !text
    // a string's bytes, quoted and escaped (the raw bytes of a composite, unescaped, are the last piece)
    %nc = arith.index_cast %nl : i64 to index
    %vcnt = arith.select %isStr, %nc, %c0 : index
    %vsrcd = func.call @jc_desc8(%p, %nl) : (!llvm.ptr, i64) -> !d
    %vsrcm = builtin.unrealized_conversion_cast %vsrcd : !d to !m8
    %vsrc = builtin.unrealized_conversion_cast %vsrcm : !m8 to !text
    %vesc, %vco = trikeshed.combineAll %vcnt : !text, !coords {
    ^bb0(%vi: index):
      %vc = trikeshed.at %vsrc[%vi] : !text, index -> i8
      %vci = arith.index_castui %vc : i8 to index
      %vl = trikeshed.at %elens[%vci] : !text, index -> i8
      %vli = arith.index_castui %vl : i8 to index
      %vat = arith.muli %vci, %c6 : index
      %vpart = trikeshed.slice %etab[%vat, %vli] : !text -> !text
      trikeshed.yield %vpart : !text
    }
    %vqlen = arith.select %isStr, %c1, %c0 : index
    %vq = trikeshed.slice %blob[%c19, %vqlen] : !text -> !text
    %rl = arith.select %isRaw, %nl, %c0_64 : i64
    %rawd = func.call @jc_desc8(%p, %rl) : (!llvm.ptr, i64) -> !d
    %rawm = builtin.unrealized_conversion_cast %rawd : !d to !m8
    %raw = builtin.unrealized_conversion_cast %rawm : !m8 to !text
    %gt = arith.cmpi ugt, %j, %c0 : index
    %sepn = arith.select %gt, %c1, %c0 : index
    %sep = trikeshed.slice %blob[%c4, %sepn] : !text -> !text
    %row = trikeshed.combine %sep, %kq, %kesc, %kq, %colon, %digits, %word, %vq, %vesc, %vq, %raw : !text, !text, !text, !text, !text, !text, !text, !text, !text, !text, !text -> !text
    trikeshed.yield %row : !text
  }
  %open = trikeshed.slice %blob[%openi, %ol] : !text -> !text
  %close = trikeshed.slice %blob[%closei, %ol] : !text -> !text
  %t1 = trikeshed.combine %open, %all : !text, !text -> !text
  %whole = trikeshed.combine %t1, %close : !text, !text -> !text
  %sz = trikeshed.size %whole : !text
  %szi = arith.index_cast %sz : index to i64
  %capi = arith.index_cast %cap : i64 to index
  %fits = arith.cmpi ule, %sz, %capi : index
  scf.if %fits {
    %di = func.call @jc_desc8(%into, %cap) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m8
    %end = trikeshed.drain %whole, %mi : !text, !m8 -> index
  }
  return %szi : i64
}
