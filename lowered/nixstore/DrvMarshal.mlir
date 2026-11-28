// The derivation bridges of lib/Store/StorePaths.cpp: what stood between a Derivation and the ATerm writer, the JSON
// writer (DrvUnparse.mlir, DrvJson.mlir) and the ATerm reader (DrvParse.mlir).  The C++ keeps a forward each, and the
// callbacks that make rows in a Derivation's sorted maps and sets (they allocate).
//
//   nixstore_ts_drvtext(d, mask, inputs, out)    Derivation::unparse: the ATerm text in the Text at out
//   nixstore_ts_drvhash(d, mask, inputs, h)      Derivation::hashUnparsed: the SHA-256 of that text
//   nixstore_ts_drvjsontext(path, pn, d, out)    derivationToJSON
//   nixstore_ts_methodalgo(o, out)               DerivationOutput::methodAlgo: "r:sha256", "sha256", "text:sha256"
//   nixstore_ts_drvfixedpath(o, sd, sdn, drvName, dn, output, on, out)   DerivationOutput::fixedPath
//   nixstore_ts_isfixed(d)                       Derivation::isFixed: one output, "out", content-addressed and fixed
//   nixstore_ts_drvread(text, n, d, err)         parseDerivation: the reader's strings classified and given to d
//
// A Derivation is read where it lies (the C++ holds these layouts with a static_assert): 19 words, name @0, outputs @2,
// inputDrvs @4, inputSrcs @6, platform @8, builder @10, args @12, env @14, structuredAttrs' flag @16 and Text @17.  A
// Text, a set and a map are two words, the cells' address and their count (its low 32 bits; the capacity above them).
// An output's row is 15 words: its name, kind @2 (0 input-addressed, 1 fixed, 2 floating, 3 deferred, 4 impure), path
// @3, method and hashAlgo @5 (32 bits each), hash @6 (its algorithm, then the digest from byte 52).  An input's row is
// its path and its outputs' set; an env row a key and a value.
//
// The writers read the input derivations, the sources and the arguments as the rows they are (they mask the counts).
// What is made here is what has no row: the outputs' windows by kind (one series of words: name, path, method-and-
// algorithm, hash; a path masked when the hash is of the outputs' names), each output's method-and-algorithm text and
// base-16 digest (a second series, written as it is filled), and the environment when __json has to stand at its place
// in key order or an output's value is masked (one combine of the rows around __json's place, which a bisect finds,
// drained once; a masked value is found by a bisect of the rows for each output's name).  Otherwise the environment is
// its rows too.  The reader's windows are walked by folds over their words (dm_outputs, dm_inputs, dm_strings,
// dm_entries), each window given to the callback that makes its row.
//
// Written as DrvMarshal.mlir.t and expanded by gen.py (both kept outside the repository, with the lane's harnesses: the
// literals are spans of one blob).  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @dm_words : memref<178xi8> =
  dense<"0x723a746578743a6f7574696d707572655f5f6a736f6e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000756e6b6e6f776e206861736820616c676f726974686d20272720696e2064657269766174696f6e696e76616c69642064657269766174696f6e2028415465726d207061727365206572726f72206174206f66667365742029">
// the powers of ten a decimal's length counts (10 to 10^19, the last as its bits)
memref.global "private" constant @dm_pow10 : memref<19xi64> = dense<[10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000, 10000000000, 100000000000, 1000000000000, 10000000000000, 100000000000000, 1000000000000000, 10000000000000000, 100000000000000000, 1000000000000000000, -8446744073709551616]>

// the C library
func.func private @strerror(i32) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
// a Text sized (StorePaths.cpp), and the rows of a Derivation made (StorePaths.cpp: they allocate)
func.func private @nixstore_text_sized(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixstore_drv_out(!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr, i64)
func.func private @nixstore_drv_in(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixstore_set_insert(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixstore_texts_append(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixstore_drv_env(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64)
// the writers and the reader (DrvUnparse.mlir, DrvJson.mlir, DrvParse.mlir)
func.func private @nixstore_ts_unparse(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixstore_ts_drvjson(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_drvparse(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
// HashOps.mlir, Encoders.mlir, StoreName.mlir, StorePathMake.mlir
func.func private @_ZN8nixstore8hashSizeENS_8HashAlgoE(i32) -> i64
func.func private @nixstore_ts_algoname(i64) -> !llvm.ptr
func.func private @nixstore_ts_algoof(!llvm.ptr, i64) -> i64
func.func private @nixstore_ts_hashparse(!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @mlnix_base16_encode(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_outputname(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_fixedpath(!llvm.ptr, i64, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64

// the descriptor of n cells at p
func.func private @dm_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// A failure's message put in the Text at err: the words at [ao, an), the bytes [p1, n1), the words at [bo, bn), the
// bytes [p2, n2), the words at [co, cn), and what the system says of error e (strerror) unless e is negative.  One
// combine, drained once into the Text sized to it.  Answers 1.
func.func private @dm_fail(%err: !llvm.ptr, %ao: index, %an: index, %p1: !llvm.ptr, %n1: i64, %bo: index, %bn: index, %p2: !llvm.ptr, %n2: i64, %co: index, %cn: index, %e: i32) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %a = trikeshed.slice %words[%ao, %an] : !s -> !s
  %b = trikeshed.slice %words[%bo, %bn] : !s -> !s
  %c = trikeshed.slice %words[%co, %cn] : !s -> !s
  %w1_d = func.call @dm_desc(%p1, %n1) : (!llvm.ptr, i64) -> !d
  %w1_m = builtin.unrealized_conversion_cast %w1_d : !d to !m
  %w1 = builtin.unrealized_conversion_cast %w1_m : !m to !s
  %w2_d = func.call @dm_desc(%p2, %n2) : (!llvm.ptr, i64) -> !d
  %w2_m = builtin.unrealized_conversion_cast %w2_d : !d to !m
  %w2 = builtin.unrealized_conversion_cast %w2_m : !m to !s
  %said = arith.cmpi sge, %e, %z32 : i32
  %wp, %wn = scf.if %said -> (!llvm.ptr, i64) {
    %t = func.call @strerror(%e) : (i32) -> !llvm.ptr
    %tn = func.call @strlen(%t) : (!llvm.ptr) -> i64
    scf.yield %t, %tn : !llvm.ptr, i64
  } else {
    scf.yield %p1, %c0 : !llvm.ptr, i64
  }
  %why_d = func.call @dm_desc(%wp, %wn) : (!llvm.ptr, i64) -> !d
  %why_m = builtin.unrealized_conversion_cast %why_d : !d to !m
  %why = builtin.unrealized_conversion_cast %why_m : !m to !s
  %msg = trikeshed.combine %a, %w1, %b, %w2, %c, %why : !s, !s, !s, !s, !s, !s -> !s
  %sz = trikeshed.size %msg : !s
  %sz64 = arith.index_cast %sz : index to i64
  %room = func.call @nixstore_text_sized(%err, %sz64) : (!llvm.ptr, i64) -> !llvm.ptr
  %into_d = func.call @dm_desc(%room, %sz64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %into_d : !d to !m
  %end = trikeshed.drain %msg, %into : !s, !m -> index
  return %c1 : i64
}

// the address of the blob's byte at `off`
func.func private @dm_word(%off: index) -> !llvm.ptr {
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %base = memref.extract_aligned_pointer_as_index %words_g : memref<178xi8> -> index
  %at = arith.addi %base, %off : index
  %at64 = arith.index_cast %at : index to i64
  %p = llvm.inttoptr %at64 : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

//===----------------------------------------------------------------------===//
// An output: its method and algorithm, its fixed path; a derivation that is fixed
//===----------------------------------------------------------------------===//

// "r:" or "text:" or nothing by the output's method, then the name of its algorithm (a fixed output's is its hash's),
// written at `into` (room for 16 bytes): one combine drained once.  Its bytes.
func.func private @dm_methodalgo(%o: !llvm.ptr, %into: !llvm.ptr) -> i64 {
  %c24 = arith.constant 24 : i64
  %c28 = arith.constant 28 : i64
  %c32 = arith.constant 32 : i64
  %one = arith.constant 1 : i32
  %two = arith.constant 2 : i32
  %z = arith.constant 0 : index
  %i2 = arith.constant 2 : index
  %i5 = arith.constant 5 : index
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %rec_o = arith.constant 0 : index  // "r:"
  %rec_n = arith.constant 2 : index
  %text_o = arith.constant 2 : index  // "text:"
  %text_n = arith.constant 5 : index
  %kind = llvm.load %o : !llvm.ptr -> i32
  %mp = llvm.getelementptr %o[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ap = llvm.getelementptr %o[%c28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %hp = llvm.getelementptr %o[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %method = llvm.load %mp : !llvm.ptr -> i32
  %own = llvm.load %ap : !llvm.ptr -> i32
  %hashs = llvm.load %hp : !llvm.ptr -> i32
  %fixed = arith.cmpi eq, %kind, %one : i32
  %a32 = arith.select %fixed, %hashs, %own : i32
  %a = arith.extsi %a32 : i32 to i64
  %np = func.call @nixstore_ts_algoname(%a) : (i64) -> !llvm.ptr
  %nn = func.call @strlen(%np) : (!llvm.ptr) -> i64
  %name_d = func.call @dm_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
  %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
  %name = builtin.unrealized_conversion_cast %name_m : !m to !s
  %isnar = arith.cmpi eq, %method, %one : i32
  %istext = arith.cmpi eq, %method, %two : i32
  %po0 = arith.select %istext, %text_o, %rec_o : index
  %pn0 = arith.select %istext, %i5, %z : index
  %pn = arith.select %isnar, %i2, %pn0 : index
  %prefix = trikeshed.slice %words[%po0, %pn] : !s -> !s
  %all = trikeshed.combine %prefix, %name : !s, !s -> !s
  %sz = trikeshed.size %all : !s
  %sz64 = arith.index_cast %sz : index to i64
  %room_d = func.call @dm_desc(%into, %sz64) : (!llvm.ptr, i64) -> !d
  %room = builtin.unrealized_conversion_cast %room_d : !d to !m
  %e = trikeshed.drain %all, %room : !s, !m -> index
  return %sz64 : i64
}

func.func @nixstore_ts_methodalgo(%o: !llvm.ptr, %out: !llvm.ptr) {
  %c16 = arith.constant 16 : i64
  %buf = llvm.alloca %c16 x i8 : (i64) -> !llvm.ptr
  %n = func.call @dm_methodalgo(%o, %buf) : (!llvm.ptr, !llvm.ptr) -> i64
  %room = func.call @nixstore_text_sized(%out, %n) : (!llvm.ptr, i64) -> !llvm.ptr
  %text_d = func.call @dm_desc(%buf, %n) : (!llvm.ptr, i64) -> !d
  %text_m = builtin.unrealized_conversion_cast %text_d : !d to !m
  %text = builtin.unrealized_conversion_cast %text_m : !m to !s
  %into_d = func.call @dm_desc(%room, %n) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %into_d : !d to !m
  %e = trikeshed.drain %text, %into : !s, !m -> index
  return
}

// fixedPath: makeFixedOutputPath of the output's method and hash, the name outputPathName's (no reference)
func.func @nixstore_ts_drvfixedpath(%o: !llvm.ptr, %sd: !llvm.ptr, %sdn: i64, %dp: !llvm.ptr, %dn: i64, %op: !llvm.ptr, %on: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %b0 = arith.addi %dn, %c1 : i64
  %bound = arith.addi %b0, %on : i64
  %bi = arith.index_cast %bound : i64 to index
  %name = memref.alloc(%bi) : memref<?xi8>
  %nb = memref.extract_aligned_pointer_as_index %name : memref<?xi8> -> index
  %nb64 = arith.index_cast %nb : index to i64
  %np = llvm.inttoptr %nb64 : i64 to !llvm.ptr
  %nn = func.call @nixstore_ts_outputname(%dp, %dn, %op, %on, %np) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  %mp = llvm.getelementptr %o[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %method32 = llvm.load %mp : !llvm.ptr -> i32
  %method = arith.extsi %method32 : i32 to i64
  %h = llvm.getelementptr %o[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %r = func.call @nixstore_ts_fixedpath(%sd, %sdn, %np, %nn, %method, %h, %null, %c0, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  return %r : i64
}

func.func @nixstore_ts_isfixed(%d: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c19 = arith.constant 19 : i64
  %c15 = arith.constant 15 : i64
  %m32 = arith.constant 4294967295 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %out_o = arith.constant 7 : index  // "out"
  %out_n = arith.constant 3 : index
  %out = trikeshed.slice %words[%out_o, %out_n] : !s -> !s
  %dw_d = func.call @dm_desc(%d, %c19) : (!llvm.ptr, i64) -> !d
  %dw_m = builtin.unrealized_conversion_cast %dw_d : !d to !m64
  %dw = builtin.unrealized_conversion_cast %dw_m : !m64 to !s64
  %rows64 = trikeshed.at %dw[%i2] : !s64, index -> i64
  %nw = trikeshed.at %dw[%i3] : !s64, index -> i64
  %n = arith.andi %nw, %m32 : i64
  %single = arith.cmpi eq, %n, %c1 : i64
  %r = scf.if %single -> (i64) {
    %rows = llvm.inttoptr %rows64 : i64 to !llvm.ptr
    %row_d = func.call @dm_desc(%rows, %c15) : (!llvm.ptr, i64) -> !d
    %row_m = builtin.unrealized_conversion_cast %row_d : !d to !m64
    %row = builtin.unrealized_conversion_cast %row_m : !m64 to !s64
    %np64 = trikeshed.at %row[%z] : !s64, index -> i64
    %nnw = trikeshed.at %row[%i1] : !s64, index -> i64
    %kw = trikeshed.at %row[%i2] : !s64, index -> i64
    %nn = arith.andi %nnw, %m32 : i64
    %kind = arith.andi %kw, %m32 : i64
    %np = llvm.inttoptr %np64 : i64 to !llvm.ptr
    %name_d = func.call @dm_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
    %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
    %name = builtin.unrealized_conversion_cast %name_m : !m to !s
    %c = trikeshed.compare %name, %out unsigned : !s, !s
    %isout = arith.cmpi eq, %c, %z32 : i32
    %isfixed = arith.cmpi eq, %kind, %c1 : i64
    %both = arith.andi %isout, %isfixed : i1
    %b = arith.extui %both : i1 to i64
    scf.yield %b : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// A Derivation given to a writer
//===----------------------------------------------------------------------===//

// The values under the outputs' names given no bytes, in the environment rows made for a writer (4 words a row, sorted
// by key): a fold over the outputs' rows' words (15 a row, the first where its name is), each name looked up among the
// rows' keys by bisect.  The words walked.
func.func private @dm_maskvalues(%outp: !llvm.ptr, %nouts: i64, %rows: !llvm.ptr, %nrows: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %c15 = arith.constant 15 : i64
  %m32 = arith.constant 4294967295 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %owords = arith.muli %nouts, %c15 : i64
  %ow_d = func.call @dm_desc(%outp, %owords) : (!llvm.ptr, i64) -> !d
  %ow_m = builtin.unrealized_conversion_cast %ow_d : !d to !m64
  %ow = builtin.unrealized_conversion_cast %ow_m : !m64 to !s64
  %rcells = arith.muli %nrows, %c4 : i64
  %rw_d = func.call @dm_desc(%rows, %rcells) : (!llvm.ptr, i64) -> !d
  %rw_m = builtin.unrealized_conversion_cast %rw_d : !d to !m64
  %rw = builtin.unrealized_conversion_cast %rw_m : !m64 to !s64
  %rroom_d = func.call @dm_desc(%rows, %rcells) : (!llvm.ptr, i64) -> !d
  %rroom = builtin.unrealized_conversion_cast %rroom_d : !d to !m64
  %nri = arith.index_cast %nrows : i64 to index
  %ridx = trikeshed.series %nri : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %end = trikeshed.fold %ow, %c0 : !s64, i64 -> i64 {
  ^bb0(%at: i64, %word: i64):
    %rem = arith.remui %at, %c15 : i64
    %starts = arith.cmpi eq, %rem, %c0 : i64
    scf.if %starts {
      %ai = arith.index_cast %at : i64 to index
      %ai1 = arith.addi %ai, %i1 : index
      %nnw = trikeshed.at %ow[%ai1] : !s64, index -> i64
      %nn = arith.andi %nnw, %m32 : i64
      %np = llvm.inttoptr %word : i64 to !llvm.ptr
      %name_d = func.call @dm_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
      %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
      %name = builtin.unrealized_conversion_cast %name_m : !m to !s
      %j = trikeshed.bisect %ridx, %c0 : !s64, i64 -> index by {
      ^bb0(%e: i64, %key: i64):
        %ei = arith.index_cast %e : i64 to index
        %rat = arith.muli %ei, %i4 : index
        %rat1 = arith.addi %rat, %i1 : index
        %kp64 = trikeshed.at %rw[%rat] : !s64, index -> i64
        %knw = trikeshed.at %rw[%rat1] : !s64, index -> i64
        %kn = arith.andi %knw, %m32 : i64
        %kp = llvm.inttoptr %kp64 : i64 to !llvm.ptr
        %k_d = func.call @dm_desc(%kp, %kn) : (!llvm.ptr, i64) -> !d
        %k_m = builtin.unrealized_conversion_cast %k_d : !d to !m
        %k = builtin.unrealized_conversion_cast %k_m : !m to !s
        %c = trikeshed.compare %k, %name unsigned : !s, !s
        trikeshed.yield %c : i32
      }
      %found = arith.cmpi sge, %j, %z : index
      scf.if %found {
        %v0 = arith.muli %j, %i4 : index
        %vat = arith.addi %v0, %i3 : index
        memref.store %c0, %rroom[%vat] : !m64
      }
    }
    %next = arith.addi %at, %c1 : i64
    trikeshed.yield %next : i64
  }
  return %end : i64
}

// mode 0: the ATerm text into the Text at `into`; 1: its SHA-256 into the Hash at `into`; 2: the JSON text into the
// Text at `into` (pp, pn the derivation's path).  mask: the outputs' paths, and the environment's values under an
// output's name, are left empty (the hash that names the outputs).  inputs: the input derivations to write instead of
// the Derivation's own (a map's two words), or null.
func.func private @dm_write(%d: !llvm.ptr, %mask: i64, %inputs: !llvm.ptr, %mode: i64, %pp: !llvm.ptr, %pn: i64, %into: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c19 = arith.constant 19 : i64
  %c32 = arith.constant 32 : i64
  %c36 = arith.constant 36 : i64
  %c64 = arith.constant 64 : i64
  %c120 = arith.constant 120 : i64
  %c144 = arith.constant 144 : i64
  %c255 = arith.constant 255 : i64
  %m32 = arith.constant 4294967295 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i7 = arith.constant 7 : index
  %i8 = arith.constant 8 : index
  %i9 = arith.constant 9 : index
  %i10 = arith.constant 10 : index
  %i11 = arith.constant 11 : index
  %i12 = arith.constant 12 : index
  %i13 = arith.constant 13 : index
  %i14 = arith.constant 14 : index
  %i15 = arith.constant 15 : index
  %i16 = arith.constant 16 : index
  %i17 = arith.constant 17 : index
  %i18 = arith.constant 18 : index
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %impure_o = arith.constant 10 : index  // "impure"
  %impure_n = arith.constant 6 : index
  %jsonkey_o = arith.constant 16 : index  // "__json"
  %jsonkey_n = arith.constant 6 : index
  %jsonname_o = arith.constant 16 : index  // "__json"
  %jsonname_n = arith.constant 6 : index
  %jsonname = trikeshed.slice %words[%jsonname_o, %jsonname_n] : !s -> !s
  %impurep = func.call @dm_word(%impure_o) : (index) -> !llvm.ptr
  %impureb = llvm.ptrtoint %impurep : !llvm.ptr to i64
  %jsonp = func.call @dm_word(%jsonkey_o) : (index) -> !llvm.ptr
  %jsonb = llvm.ptrtoint %jsonp : !llvm.ptr to i64
  %masked = arith.cmpi ne, %mask, %c0 : i64
  // the Derivation's words
  %dw_d = func.call @dm_desc(%d, %c19) : (!llvm.ptr, i64) -> !d
  %dw_m = builtin.unrealized_conversion_cast %dw_d : !d to !m64
  %dw = builtin.unrealized_conversion_cast %dw_m : !m64 to !s64
  %namep64 = trikeshed.at %dw[%z] : !s64, index -> i64
  %namenw = trikeshed.at %dw[%i1] : !s64, index -> i64
  %outp64 = trikeshed.at %dw[%i2] : !s64, index -> i64
  %noutsw = trikeshed.at %dw[%i3] : !s64, index -> i64
  %ownin64 = trikeshed.at %dw[%i4] : !s64, index -> i64
  %ownninw = trikeshed.at %dw[%i5] : !s64, index -> i64
  %srcp64 = trikeshed.at %dw[%i6] : !s64, index -> i64
  %nsrcsw = trikeshed.at %dw[%i7] : !s64, index -> i64
  %platp64 = trikeshed.at %dw[%i8] : !s64, index -> i64
  %platnw = trikeshed.at %dw[%i9] : !s64, index -> i64
  %bldp64 = trikeshed.at %dw[%i10] : !s64, index -> i64
  %bldnw = trikeshed.at %dw[%i11] : !s64, index -> i64
  %argp64 = trikeshed.at %dw[%i12] : !s64, index -> i64
  %nargsw = trikeshed.at %dw[%i13] : !s64, index -> i64
  %envp64 = trikeshed.at %dw[%i14] : !s64, index -> i64
  %nenvw = trikeshed.at %dw[%i15] : !s64, index -> i64
  %hasw = trikeshed.at %dw[%i16] : !s64, index -> i64
  %sap64 = trikeshed.at %dw[%i17] : !s64, index -> i64
  %sanw = trikeshed.at %dw[%i18] : !s64, index -> i64
  %namen = arith.andi %namenw, %m32 : i64
  %nouts = arith.andi %noutsw, %m32 : i64
  %ownnin = arith.andi %ownninw, %m32 : i64
  %nsrcs = arith.andi %nsrcsw, %m32 : i64
  %platn = arith.andi %platnw, %m32 : i64
  %bldn = arith.andi %bldnw, %m32 : i64
  %nargs = arith.andi %nargsw, %m32 : i64
  %nenv = arith.andi %nenvw, %m32 : i64
  %hasb = arith.andi %hasw, %c255 : i64
  %json = arith.cmpi ne, %hasb, %c0 : i64
  %san = arith.andi %sanw, %m32 : i64
  %namep = llvm.inttoptr %namep64 : i64 to !llvm.ptr
  %outp = llvm.inttoptr %outp64 : i64 to !llvm.ptr
  %srcp = llvm.inttoptr %srcp64 : i64 to !llvm.ptr
  %platp = llvm.inttoptr %platp64 : i64 to !llvm.ptr
  %bldp = llvm.inttoptr %bldp64 : i64 to !llvm.ptr
  %argp = llvm.inttoptr %argp64 : i64 to !llvm.ptr
  %envp = llvm.inttoptr %envp64 : i64 to !llvm.ptr
  // the input derivations: the ones given, or the Derivation's own
  %inb = llvm.ptrtoint %inputs : !llvm.ptr to i64
  %given = arith.cmpi ne, %inb, %c0 : i64
  %inp64, %nin = scf.if %given -> (i64, i64) {
    %iw_d = func.call @dm_desc(%inputs, %c2) : (!llvm.ptr, i64) -> !d
    %iw_m = builtin.unrealized_conversion_cast %iw_d : !d to !m64
    %iw = builtin.unrealized_conversion_cast %iw_m : !m64 to !s64
    %gp = trikeshed.at %iw[%z] : !s64, index -> i64
    %gnw = trikeshed.at %iw[%i1] : !s64, index -> i64
    %gn = arith.andi %gnw, %m32 : i64
    scf.yield %gp, %gn : i64, i64
  } else {
    scf.yield %ownin64, %ownnin : i64, i64
  }
  %inp = llvm.inttoptr %inp64 : i64 to !llvm.ptr

  // The outputs.  Each one's method-and-algorithm text and its hash's base 16 are written in a room of 144 bytes an
  // output (16 and 128) as the series of their lengths is filled (the text's << 32 | the digits').
  %owords = arith.muli %nouts, %c15 : i64
  %ow_d = func.call @dm_desc(%outp, %owords) : (!llvm.ptr, i64) -> !d
  %ow_m = builtin.unrealized_conversion_cast %ow_d : !d to !m64
  %ow = builtin.unrealized_conversion_cast %ow_m : !m64 to !s64
  %nouti = arith.index_cast %nouts : i64 to index
  %tbytes = arith.muli %nouts, %c144 : i64
  %tbi = arith.index_cast %tbytes : i64 to index
  %texts = memref.alloc(%tbi) : memref<?xi8>
  %tb = memref.extract_aligned_pointer_as_index %texts : memref<?xi8> -> index
  %tb64 = arith.index_cast %tb : index to i64
  %lens = trikeshed.series %nouti : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %kat0 = arith.muli %i, %i15 : index
    %kat = arith.addi %kat0, %i2 : index
    %kw = trikeshed.at %ow[%kat] : !s64, index -> i64
    %kind = arith.andi %kw, %m32 : i64
    %ro = arith.muli %i64, %c120 : i64
    %ro16 = arith.addi %ro, %c16 : i64
    %o = llvm.getelementptr %outp[%ro16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %to = arith.muli %i64, %c144 : i64
    %tat64 = arith.addi %tb64, %to : i64
    %tat = llvm.inttoptr %tat64 : i64 to !llvm.ptr
    %k1 = arith.cmpi eq, %kind, %c1 : i64
    %k2 = arith.cmpi eq, %kind, %c2 : i64
    %k4 = arith.cmpi eq, %kind, %c4 : i64
    %k12 = arith.ori %k1, %k2 : i1
    %named = arith.ori %k12, %k4 : i1
    %an = scf.if %named -> (i64) {
      %w = func.call @dm_methodalgo(%o, %tat) : (!llvm.ptr, !llvm.ptr) -> i64
      scf.yield %w : i64
    } else {
      scf.yield %c0 : i64
    }
    %hn = scf.if %k1 -> (i64) {
      %hp = llvm.getelementptr %o[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %ha = llvm.load %hp : !llvm.ptr -> i32
      %size = func.call @_ZN8nixstore8hashSizeENS_8HashAlgoE(%ha) : (i32) -> i64
      %bytes = llvm.getelementptr %o[%c36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %hat = llvm.getelementptr %tat[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %some = arith.cmpi ne, %size, %c0 : i64
      %w2 = scf.if %some -> (i64) {
        %w3 = func.call @mlnix_base16_encode(%bytes, %size, %hat) : (!llvm.ptr, i64, !llvm.ptr) -> i64
        scf.yield %w3 : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %w2 : i64
    } else {
      scf.yield %c0 : i64
    }
    %hi = arith.shli %an, %c32 : i64
    %both = arith.ori %hi, %hn : i64
    trikeshed.yield %both : i64
  }
  // the writers' rows of an output: four windows, the name, the path, the method and algorithm, the hash
  %no8 = arith.muli %nouti, %i8 : index
  %outs = trikeshed.series %no8 : !s64 {
  ^bb0(%j: index):
    %row = arith.divui %j, %i8 : index
    %col = arith.remui %j, %i8 : index
    %row64 = arith.index_cast %row : index to i64
    %at = arith.muli %row, %i15 : index
    %at1 = arith.addi %at, %i1 : index
    %at2 = arith.addi %at, %i2 : index
    %at3 = arith.addi %at, %i3 : index
    %at4 = arith.addi %at, %i4 : index
    %np64 = trikeshed.at %ow[%at] : !s64, index -> i64
    %nnw = trikeshed.at %ow[%at1] : !s64, index -> i64
    %kw = trikeshed.at %ow[%at2] : !s64, index -> i64
    %pp64 = trikeshed.at %ow[%at3] : !s64, index -> i64
    %pnw = trikeshed.at %ow[%at4] : !s64, index -> i64
    %ln = trikeshed.at %lens[%row] : !s64, index -> i64
    %nn = arith.andi %nnw, %m32 : i64
    %kind = arith.andi %kw, %m32 : i64
    %pn0 = arith.andi %pnw, %m32 : i64
    %an = arith.shrui %ln, %c32 : i64
    %hn = arith.andi %ln, %m32 : i64
    %to = arith.muli %row64, %c144 : i64
    %tat = arith.addi %tb64, %to : i64
    %hat = arith.addi %tat, %c16 : i64
    // a path: an input-addressed or a fixed output's, unless masked; the hash of an impure output is the word
    %k0 = arith.cmpi eq, %kind, %c0 : i64
    %k1 = arith.cmpi eq, %kind, %c1 : i64
    %k4 = arith.cmpi eq, %kind, %c4 : i64
    %k01 = arith.ori %k0, %k1 : i1
    %open = arith.cmpi eq, %mask, %c0 : i64
    %haspath = arith.andi %k01, %open : i1
    %pn1 = arith.select %haspath, %pn0, %c0 : i64
    %hp0 = arith.select %k4, %impureb, %hat : i64
    %hn0 = arith.select %k4, %c6, %hn : i64
    %is0 = arith.cmpi eq, %col, %z : index
    %is1 = arith.cmpi eq, %col, %i1 : index
    %is2 = arith.cmpi eq, %col, %i2 : index
    %is3 = arith.cmpi eq, %col, %i3 : index
    %is4 = arith.cmpi eq, %col, %i4 : index
    %is5 = arith.cmpi eq, %col, %i5 : index
    %is6 = arith.cmpi eq, %col, %i6 : index
    %w7 = arith.select %is6, %hp0, %hn0 : i64
    %w6 = arith.select %is5, %an, %w7 : i64
    %w5 = arith.select %is4, %tat, %w6 : i64
    %w4 = arith.select %is3, %pn1, %w5 : i64
    %w3 = arith.select %is2, %pp64, %w4 : i64
    %w2 = arith.select %is1, %nn, %w3 : i64
    %w1 = arith.select %is0, %np64, %w2 : i64
    trikeshed.yield %w1 : i64
  }
  // each output's kind, for the JSON writer
  %isjsonmode = arith.cmpi eq, %mode, %c2 : i64
  %nkinds = arith.select %isjsonmode, %nouti, %z : index
  %kinds = trikeshed.series %nkinds : !s64 {
  ^bb0(%i: index):
    %kat0 = arith.muli %i, %i15 : index
    %kat = arith.addi %kat0, %i2 : index
    %kw = trikeshed.at %ow[%kat] : !s64, index -> i64
    %kind = arith.andi %kw, %m32 : i64
    trikeshed.yield %kind : i64
  }

  // The environment: its rows as they are, unless __json (the structured attributes, which win over an entry of that
  // name) has to stand at its place in key order, or an output's value is masked.  Then the writers' rows are one
  // combine drained once into a room: the rows before __json's place (found by bisect), __json's row, the rows after
  // (an entry named __json left out); and the value under each output's name is given no bytes.
  %ewords = arith.muli %nenv, %c4 : i64
  %ew_d = func.call @dm_desc(%envp, %ewords) : (!llvm.ptr, i64) -> !d
  %ew_m = builtin.unrealized_conversion_cast %ew_d : !d to !m64
  %ew = builtin.unrealized_conversion_cast %ew_m : !m64 to !s64
  %nenvi = arith.index_cast %nenv : i64 to index
  %nidx = arith.select %json, %nenvi, %z : index
  %idx = trikeshed.series %nidx : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %found = trikeshed.bisect %idx, %c0 : !s64, i64 -> index by {
  ^bb0(%e: i64, %key: i64):
    %ei = arith.index_cast %e : i64 to index
    %at = arith.muli %ei, %i4 : index
    %at1 = arith.addi %at, %i1 : index
    %kp64 = trikeshed.at %ew[%at] : !s64, index -> i64
    %knw = trikeshed.at %ew[%at1] : !s64, index -> i64
    %kn = arith.andi %knw, %m32 : i64
    %kp = llvm.inttoptr %kp64 : i64 to !llvm.ptr
    %k_d = func.call @dm_desc(%kp, %kn) : (!llvm.ptr, i64) -> !d
    %k_m = builtin.unrealized_conversion_cast %k_d : !d to !m
    %k = builtin.unrealized_conversion_cast %k_m : !m to !s
    %c = trikeshed.compare %k, %jsonname unsigned : !s, !s
    trikeshed.yield %c : i32
  }
  %there = arith.cmpi sge, %found, %z : index
  %ins0 = arith.subi %z, %found : index
  %ins = arith.subi %ins0, %i1 : index
  %pos0 = arith.select %there, %found, %ins : index
  %dup0 = arith.select %there, %i1, %z : index
  %pos = arith.select %json, %pos0, %nenvi : index
  %dup = arith.select %json, %dup0, %z : index
  %made = arith.ori %json, %masked : i1
  %nbefore0 = arith.muli %pos, %i4 : index
  %nbefore = arith.select %made, %nbefore0, %z : index
  %from0 = arith.addi %pos, %dup : index
  %from = arith.muli %from0, %i4 : index
  %rest0 = arith.subi %nenvi, %from0 : index
  %rest1 = arith.muli %rest0, %i4 : index
  %nafter = arith.select %made, %rest1, %z : index
  %njrow = arith.select %json, %i4, %z : index
  %before = trikeshed.slice %ew[%z, %nbefore] : !s64 -> !s64
  %after = trikeshed.slice %ew[%from, %nafter] : !s64 -> !s64
  %jrow = trikeshed.series %njrow : !s64 {
  ^bb0(%j: index):
    %is0 = arith.cmpi eq, %j, %z : index
    %is1 = arith.cmpi eq, %j, %i1 : index
    %is2 = arith.cmpi eq, %j, %i2 : index
    %w2 = arith.select %is2, %sap64, %san : i64
    %w1 = arith.select %is1, %c6, %w2 : i64
    %w0 = arith.select %is0, %jsonb, %w1 : i64
    trikeshed.yield %w0 : i64
  }
  %envc = trikeshed.combine %before, %jrow, %after : !s64, !s64, !s64 -> !s64
  %ncells = trikeshed.size %envc : !s64
  %envm = memref.alloc(%ncells) : memref<?xi64>
  %envroom = memref.cast %envm : memref<?xi64> to !m64
  %ee = trikeshed.drain %envc, %envroom : !s64, !m64 -> index
  %nrows = arith.divui %ncells, %i4 : index
  %nrows64 = arith.index_cast %nrows : index to i64
  %env_i = memref.extract_aligned_pointer_as_index %envm : memref<?xi64> -> index
  %env_64 = arith.index_cast %env_i : index to i64
  %madep = llvm.inttoptr %env_64 : i64 to !llvm.ptr
  scf.if %masked {
    %nmasked = func.call @dm_maskvalues(%outp, %nouts, %madep, %nrows64) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
  }
  %envrows64 = arith.select %made, %env_64, %envp64 : i64
  %envrows = llvm.inttoptr %envrows64 : i64 to !llvm.ptr
  %envn = arith.select %made, %nrows64, %nenv : i64

  // the outputs' rows and then their kinds: one combine drained once into one room (each cell stored where it goes),
  // which the writers are given the addresses in
  %rows = trikeshed.combine %outs, %kinds : !s64, !s64 -> !s64
  %nrowcells = trikeshed.size %rows : !s64
  %rowsm = memref.alloc(%nrowcells) : memref<?xi64>
  %rowsroom = memref.cast %rowsm : memref<?xi64> to !m64
  %re = trikeshed.drain %rows, %rowsroom : !s64, !m64 -> index
  %rows_i = memref.extract_aligned_pointer_as_index %rowsm : memref<?xi64> -> index
  %rows_64 = arith.index_cast %rows_i : index to i64
  %outsp = llvm.inttoptr %rows_64 : i64 to !llvm.ptr
  %kindsat = arith.muli %nouts, %c64 : i64
  %kinds_64 = arith.addi %rows_64, %kindsat : i64
  %kindsp = llvm.inttoptr %kinds_64 : i64 to !llvm.ptr

  %r = scf.if %isjsonmode -> (i64) {
    %w = func.call @nixstore_ts_drvjson(%pp, %pn, %outsp, %nouts, %kindsp, %inp, %nin, %srcp, %nsrcs, %namep, %namen, %platp, %platn, %bldp, %bldn, %argp, %nargs, %envrows, %envn, %into) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %w : i64
  } else {
    %w = func.call @nixstore_ts_unparse(%outsp, %nouts, %inp, %nin, %srcp, %nsrcs, %platp, %platn, %bldp, %bldn, %argp, %nargs, %envrows, %envn, %into, %mode) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %w : i64
  }
  return %r : i64
}

func.func @nixstore_ts_drvtext(%d: !llvm.ptr, %mask: i64, %inputs: !llvm.ptr, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %w = func.call @dm_write(%d, %mask, %inputs, %c0, %null, %c0, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  return
}
func.func @nixstore_ts_drvhash(%d: !llvm.ptr, %mask: i64, %inputs: !llvm.ptr, %h: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %w = func.call @dm_write(%d, %mask, %inputs, %c1, %null, %c0, %h) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  return
}
func.func @nixstore_ts_drvjsontext(%pp: !llvm.ptr, %pn: i64, %d: !llvm.ptr, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %w = func.call @dm_write(%d, %c0, %null, %c2, %pp, %pn, %out) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  return
}

//===----------------------------------------------------------------------===//
// parseDerivation
//===----------------------------------------------------------------------===//

// v in decimal written at `into` (room for 20 bytes): its digits.  The count is a fold over the powers of ten, the
// digits one series.
func.func private @dm_decimal(%v: i64, %into: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : i64
  %c10 = arith.constant 10 : i64
  %c48 = arith.constant 48 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %pg = memref.get_global @dm_pow10 : memref<19xi64>
  %pows = trikeshed.text %pg : memref<19xi64> -> !s64
  %n = trikeshed.fold %pows, %c1 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %p: i64):
    %ge = arith.cmpi uge, %v, %p : i64
    %a1 = arith.addi %acc, %c1 : i64
    %r = arith.select %ge, %a1, %acc : i64
    trikeshed.yield %r : i64
  }
  %ni = arith.index_cast %n : i64 to index
  %digits = trikeshed.series %ni : !s {
  ^bb0(%k: index):
    // digit k from the left: v / 10^(n - 1 - k) mod 10 (the last digit's power is 1)
    %last = arith.subi %ni, %i1 : index
    %left = arith.subi %last, %k : index
    %isunit = arith.cmpi eq, %left, %z : index
    %pi0 = arith.subi %left, %i1 : index
    %pi = arith.select %isunit, %z, %pi0 : index
    %p0 = trikeshed.at %pows[%pi] : !s64, index -> i64
    %p = arith.select %isunit, %c1, %p0 : i64
    %q = arith.divui %v, %p : i64
    %dg = arith.remui %q, %c10 : i64
    %ch = arith.addi %dg, %c48 : i64
    %ch8 = arith.trunci %ch : i64 to i8
    trikeshed.yield %ch8 : i8
  }
  %room_d = func.call @dm_desc(%into, %n) : (!llvm.ptr, i64) -> !d
  %room = builtin.unrealized_conversion_cast %room_d : !d to !m
  %e = trikeshed.drain %digits, %room : !s, !m -> index
  return %n : i64
}

// window k of the reader's strings: its bytes and their count
func.func private @dm_win(%wins: !llvm.ptr, %k: i64) -> (!llvm.ptr, i64) {
  %c2 = arith.constant 2 : i64
  %i1 = arith.constant 1 : index
  %k2 = arith.muli %k, %c2 : i64
  %bound = arith.addi %k2, %c2 : i64
  %ws_d = func.call @dm_desc(%wins, %bound) : (!llvm.ptr, i64) -> !d
  %ws_m = builtin.unrealized_conversion_cast %ws_d : !d to !m64
  %ws = builtin.unrealized_conversion_cast %ws_m : !m64 to !s64
  %at = arith.index_cast %k2 : i64 to index
  %at1 = arith.addi %at, %i1 : index
  %p64 = trikeshed.at %ws[%at] : !s64, index -> i64
  %n = trikeshed.at %ws[%at1] : !s64, index -> i64
  %p = llvm.inttoptr %p64 : i64 to !llvm.ptr
  return %p, %n : !llvm.ptr, i64
}

// the Text at t becomes the n bytes at p (an empty one is left as it is made: nothing)
func.func private @dm_settext(%t: !llvm.ptr, %p: !llvm.ptr, %n: i64) {
  %c0 = arith.constant 0 : i64
  %some = arith.cmpi ne, %n, %c0 : i64
  scf.if %some {
    %room = func.call @nixstore_text_sized(%t, %n) : (!llvm.ptr, i64) -> !llvm.ptr
    %bytes_d = func.call @dm_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %bytes_m = builtin.unrealized_conversion_cast %bytes_d : !d to !m
    %bytes = builtin.unrealized_conversion_cast %bytes_m : !m to !s
    %into_d = func.call @dm_desc(%room, %n) : (!llvm.ptr, i64) -> !d
    %into = builtin.unrealized_conversion_cast %into_d : !d to !m
    %e = trikeshed.drain %bytes, %into : !s, !m -> index
  }
  return
}

// One output of the reader's (its name, path, method-and-algorithm and hash windows from window `at`), classified and
// given to the Derivation: 0, or 1 with the message at err (an unknown algorithm; a hash parseHash refuses).
func.func private @dm_output(%d: !llvm.ptr, %wins: !llvm.ptr, %at: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c9 = arith.constant 9 : i64
  %c68 = arith.constant 68 : i64
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %z = arith.constant 0 : index
  %i2 = arith.constant 2 : index
  %i5 = arith.constant 5 : index
  %null = llvm.mlir.zero : !llvm.ptr
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %rec_o = arith.constant 0 : index  // "r:"
  %rec_n = arith.constant 2 : index
  %rec = trikeshed.slice %words[%rec_o, %rec_n] : !s -> !s
  %textp_o = arith.constant 2 : index  // "text:"
  %textp_n = arith.constant 5 : index
  %textp = trikeshed.slice %words[%textp_o, %textp_n] : !s -> !s
  %impure_o = arith.constant 10 : index  // "impure"
  %impure_n = arith.constant 6 : index
  %impure = trikeshed.slice %words[%impure_o, %impure_n] : !s -> !s
  %zeros_o = arith.constant 22 : index  // "\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000"
  %zeros_n = arith.constant 68 : index
  %zeros = trikeshed.slice %words[%zeros_o, %zeros_n] : !s -> !s
  %unknown_o = arith.constant 90 : index  // "unknown hash algorithm '"
  %unknown_n = arith.constant 24 : index
  %inderivation_o = arith.constant 114 : index  // "' in derivation"
  %inderivation_n = arith.constant 15 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %hash = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %at1 = arith.addi %at, %c1 : i64
  %at2 = arith.addi %at, %c2 : i64
  %at3 = arith.addi %at, %c3 : i64
  %idp, %idn = func.call @dm_win(%wins, %at) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %pp, %pn = func.call @dm_win(%wins, %at1) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %ap, %an = func.call @dm_win(%wins, %at2) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %hp, %hn = func.call @dm_win(%wins, %at3) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %typed = arith.cmpi ne, %an, %c0 : i64
  %r = scf.if %typed -> (i64) {
    // content-addressed: `[r:|text:]algo`, then by the hash impure, fixed or floating
    %a_d = func.call @dm_desc(%ap, %an) : (!llvm.ptr, i64) -> !d
    %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
    %a = builtin.unrealized_conversion_cast %a_m : !m to !s
    %ani = arith.index_cast %an : i64 to index
    %n2 = arith.minui %ani, %i2 : index
    %n5 = arith.minui %ani, %i5 : index
    %head2 = trikeshed.slice %a[%z, %n2] : !s -> !s
    %head5 = trikeshed.slice %a[%z, %n5] : !s -> !s
    %cr = trikeshed.compare %head2, %rec unsigned : !s, !s
    %ct = trikeshed.compare %head5, %textp unsigned : !s, !s
    %isr = arith.cmpi eq, %cr, %z32 : i32
    %ist0 = arith.cmpi eq, %ct, %z32 : i32
    %true = arith.constant true
    %notr = arith.xori %isr, %true : i1
    %ist = arith.andi %ist0, %notr : i1
    %m0 = arith.select %ist, %c2, %c0 : i64
    %method = arith.select %isr, %c1, %m0 : i64
    %s0 = arith.select %ist, %c5, %c0 : i64
    %skip = arith.select %isr, %c2, %s0 : i64
    %np = llvm.getelementptr %ap[%skip] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nn = arith.subi %an, %skip : i64
    %algo = func.call @nixstore_ts_algoof(%np, %nn) : (!llvm.ptr, i64) -> i64
    %noalgo = arith.cmpi slt, %algo, %c0 : i64
    %r1 = scf.if %noalgo -> (i64) {
      %f = func.call @dm_fail(%err, %unknown_o, %unknown_n, %np, %nn, %inderivation_o, %inderivation_n, %np, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      %h_d = func.call @dm_desc(%hp, %hn) : (!llvm.ptr, i64) -> !d
      %h_m = builtin.unrealized_conversion_cast %h_d : !d to !m
      %h = builtin.unrealized_conversion_cast %h_m : !m to !s
      %ci = trikeshed.compare %h, %impure unsigned : !s, !s
      %isimpure = arith.cmpi eq, %ci, %z32 : i32
      %r2 = scf.if %isimpure -> (i64) {
        func.call @nixstore_drv_out(%d, %idp, %idn, %c4, %method, %algo, %null, %pp, %c0) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr, i64) -> ()
        scf.yield %c0 : i64
      } else {
        %hashed = arith.cmpi ne, %hn, %c0 : i64
        %r3 = scf.if %hashed -> (i64) {
          // fixed: the hash parsed as its algorithm's (a Hash of zeros first, as the C++ made one)
          %hroom_d = func.call @dm_desc(%hash, %c68) : (!llvm.ptr, i64) -> !d
          %hroom = builtin.unrealized_conversion_cast %hroom_d : !d to !m
          %e0 = trikeshed.drain %zeros, %hroom : !s, !m -> index
          %bad = func.call @nixstore_ts_hashparse(%hp, %hn, %algo, %hash, %err) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr) -> i64
          %ok = arith.cmpi eq, %bad, %c0 : i64
          scf.if %ok {
            func.call @nixstore_drv_out(%d, %idp, %idn, %c1, %method, %algo, %hash, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr, i64) -> ()
          }
          scf.yield %bad : i64
        } else {
          func.call @nixstore_drv_out(%d, %idp, %idn, %c2, %method, %algo, %null, %pp, %c0) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr, i64) -> ()
          scf.yield %c0 : i64
        }
        scf.yield %r3 : i64
      }
      scf.yield %r2 : i64
    }
    scf.yield %r1 : i64
  } else {
    // no algorithm: deferred when there is no path either, else input-addressed (the method and the algorithm are
    // what a new output has: NAR, SHA-256)
    %nopath = arith.cmpi eq, %pn, %c0 : i64
    %kind = arith.select %nopath, %c3, %c0 : i64
    func.call @nixstore_drv_out(%d, %idp, %idn, %kind, %c1, %c2, %null, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, i64, !llvm.ptr, !llvm.ptr, i64) -> ()
    scf.yield %c0 : i64
  }
  return %r : i64
}

// The outputs the reader got through, each classified as it was read (dm_output): a fold over their windows' words (8
// an output), which a refusal ends: the place after them, or -1 with the message at err.
func.func private @dm_outputs(%wins: !llvm.ptr, %nwords: i64, %nouts: i64, %d: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %z = arith.constant 0 : index
  %ws_d = func.call @dm_desc(%wins, %nwords) : (!llvm.ptr, i64) -> !d
  %ws_m = builtin.unrealized_conversion_cast %ws_d : !d to !m64
  %ws = builtin.unrealized_conversion_cast %ws_m : !m64 to !s64
  %cells = arith.muli %nouts, %c8 : i64
  %ci = arith.index_cast %cells : i64 to index
  %words = trikeshed.slice %ws[%z, %ci] : !s64 -> !s64
  %end = trikeshed.fold %words, %c0 : !s64, i64 -> i64 {
  ^bb0(%at: i64, %word: i64):
    %fine = arith.cmpi sge, %at, %c0 : i64
    %rem = arith.remui %at, %c8 : i64
    %first = arith.cmpi eq, %rem, %c0 : i64
    %starts = arith.andi %fine, %first : i1
    %step = arith.addi %at, %c1 : i64
    %next = scf.if %starts -> (i64) {
      %w = arith.divui %at, %c2 : i64
      %x = func.call @dm_output(%d, %wins, %w, %err) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
      %ok = arith.cmpi eq, %x, %c0 : i64
      %n1 = arith.select %ok, %step, %m1 : i64
      scf.yield %n1 : i64
    } else {
      %n2 = arith.select %fine, %step, %at : i64
      scf.yield %n2 : i64
    }
    trikeshed.yield %next : i64
  }
  return %end : i64
}

// The n windows from window `from` on, each given to a set (kind 0) or appended to the arguments (kind 1): a fold over
// their words (an even word is where a window's bytes are, the word after it how many).  The window after them.
func.func private @dm_strings(%wins: !llvm.ptr, %nwords: i64, %from: i64, %n: i64, %into: !llvm.ptr, %kind: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %i1 = arith.constant 1 : index
  %ws_d = func.call @dm_desc(%wins, %nwords) : (!llvm.ptr, i64) -> !d
  %ws_m = builtin.unrealized_conversion_cast %ws_d : !d to !m64
  %ws = builtin.unrealized_conversion_cast %ws_m : !m64 to !s64
  %first = arith.muli %from, %c2 : i64
  %cells = arith.muli %n, %c2 : i64
  %fi = arith.index_cast %first : i64 to index
  %ci = arith.index_cast %cells : i64 to index
  %words = trikeshed.slice %ws[%fi, %ci] : !s64 -> !s64
  %toset = arith.cmpi eq, %kind, %c0 : i64
  %end = trikeshed.fold %words, %first : !s64, i64 -> i64 {
  ^bb0(%at: i64, %word: i64):
    %odd = arith.andi %at, %c1 : i64
    %starts = arith.cmpi eq, %odd, %c0 : i64
    scf.if %starts {
      %ai = arith.index_cast %at : i64 to index
      %ai1 = arith.addi %ai, %i1 : index
      %len = trikeshed.at %ws[%ai1] : !s64, index -> i64
      %p = llvm.inttoptr %word : i64 to !llvm.ptr
      scf.if %toset {
        func.call @nixstore_set_insert(%into, %p, %len) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      } else {
        func.call @nixstore_texts_append(%into, %p, %len) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      }
    }
    %next = arith.addi %at, %c1 : i64
    trikeshed.yield %next : i64
  }
  %after = arith.divui %end, %c2 : i64
  return %after : i64
}

// The input derivations from window `from` on: a fold over their outputs' counts (the reader's sixth count on), the
// window reached its state: a path, which begins its set in the Derivation (a path met again begins a new one), then
// that many names into the set.  The window after them.
func.func private @dm_inputs(%wins: !llvm.ptr, %nwords: i64, %from: i64, %counts: !llvm.ptr, %nins: i64, %d: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %i5 = arith.constant 5 : index
  %bound = arith.addi %nins, %c5 : i64
  %cs_d = func.call @dm_desc(%counts, %bound) : (!llvm.ptr, i64) -> !d
  %cs_m = builtin.unrealized_conversion_cast %cs_d : !d to !m64
  %cs = builtin.unrealized_conversion_cast %cs_m : !m64 to !s64
  %ni = arith.index_cast %nins : i64 to index
  %each = trikeshed.slice %cs[%i5, %ni] : !s64 -> !s64
  %end = trikeshed.fold %each, %from : !s64, i64 -> i64 {
  ^bb0(%w: i64, %k: i64):
    %pp, %pn = func.call @dm_win(%wins, %w) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %set = func.call @nixstore_drv_in(%d, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %first = arith.addi %w, %c1 : i64
    %next = func.call @dm_strings(%wins, %nwords, %first, %k, %set, %c0) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> i64
    trikeshed.yield %next : i64
  }
  return %end : i64
}

// The environment's n entries from window `from` on (a key's window, then a value's: 4 words an entry): a fold over
// their words.  __json is the structured attributes, any other key an entry of the Derivation's.  The window after them.
func.func private @dm_entries(%wins: !llvm.ptr, %nwords: i64, %from: i64, %n: i64, %d: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c128 = arith.constant 128 : i64
  %c136 = arith.constant 136 : i64
  %z32 = arith.constant 0 : i32
  %one8 = arith.constant 1 : i8
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %jsonname_o = arith.constant 16 : index  // "__json"
  %jsonname_n = arith.constant 6 : index
  %jsonname = trikeshed.slice %words[%jsonname_o, %jsonname_n] : !s -> !s
  %ws_d = func.call @dm_desc(%wins, %nwords) : (!llvm.ptr, i64) -> !d
  %ws_m = builtin.unrealized_conversion_cast %ws_d : !d to !m64
  %ws = builtin.unrealized_conversion_cast %ws_m : !m64 to !s64
  %first = arith.muli %from, %c2 : i64
  %cells = arith.muli %n, %c4 : i64
  %fi = arith.index_cast %first : i64 to index
  %ci = arith.index_cast %cells : i64 to index
  %run = trikeshed.slice %ws[%fi, %ci] : !s64 -> !s64
  %hasp = llvm.getelementptr %d[%c128] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sattrs = llvm.getelementptr %d[%c136] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %end = trikeshed.fold %run, %first : !s64, i64 -> i64 {
  ^bb0(%at: i64, %word: i64):
    %rel = arith.subi %at, %first : i64
    %rem = arith.remui %rel, %c4 : i64
    %starts = arith.cmpi eq, %rem, %c0 : i64
    scf.if %starts {
      %ai = arith.index_cast %at : i64 to index
      %ai1 = arith.addi %ai, %i1 : index
      %ai2 = arith.addi %ai, %i2 : index
      %ai3 = arith.addi %ai, %i3 : index
      %kn = trikeshed.at %ws[%ai1] : !s64, index -> i64
      %vp64 = trikeshed.at %ws[%ai2] : !s64, index -> i64
      %vn = trikeshed.at %ws[%ai3] : !s64, index -> i64
      %kp = llvm.inttoptr %word : i64 to !llvm.ptr
      %vp = llvm.inttoptr %vp64 : i64 to !llvm.ptr
      %key_d = func.call @dm_desc(%kp, %kn) : (!llvm.ptr, i64) -> !d
      %key_m = builtin.unrealized_conversion_cast %key_d : !d to !m
      %key = builtin.unrealized_conversion_cast %key_m : !m to !s
      %c = trikeshed.compare %key, %jsonname unsigned : !s, !s
      %isjson = arith.cmpi eq, %c, %z32 : i32
      scf.if %isjson {
        llvm.store %one8, %hasp : i8, !llvm.ptr
        %room2 = func.call @nixstore_text_sized(%sattrs, %vn) : (!llvm.ptr, i64) -> !llvm.ptr
        %bytes_d = func.call @dm_desc(%vp, %vn) : (!llvm.ptr, i64) -> !d
        %bytes_m = builtin.unrealized_conversion_cast %bytes_d : !d to !m
        %bytes = builtin.unrealized_conversion_cast %bytes_m : !m to !s
        %into_d = func.call @dm_desc(%room2, %vn) : (!llvm.ptr, i64) -> !d
        %into = builtin.unrealized_conversion_cast %into_d : !d to !m
        %e = trikeshed.drain %bytes, %into : !s, !m -> index
      } else {
        func.call @nixstore_drv_env(%d, %kp, %kn, %vp, %vn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
      }
    }
    %next = arith.addi %at, %c1 : i64
    trikeshed.yield %next : i64
  }
  %after = arith.divui %end, %c2 : i64
  return %after : i64
}

func.func @nixstore_ts_drvread(%tp: !llvm.ptr, %tn: i64, %d: !llvm.ptr, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c20 = arith.constant 20 : i64
  %c40 = arith.constant 40 : i64
  %c48 = arith.constant 48 : i64
  %c64 = arith.constant 64 : i64
  %c80 = arith.constant 80 : i64
  %c96 = arith.constant 96 : i64
  %m1 = arith.constant -1 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %words_g = memref.get_global @dm_words : memref<178xi8>
  %words = trikeshed.text %words_g : memref<178xi8> -> !s
  %zeros_o = arith.constant 22 : index  // "\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000"
  %zeros_n = arith.constant 40 : index
  %zeros = trikeshed.slice %words[%zeros_o, %zeros_n] : !s -> !s
  %invalid_o = arith.constant 129 : index  // "invalid derivation (ATerm parse error at offset "
  %invalid_n = arith.constant 48 : index
  %close_o = arith.constant 177 : index  // ")"
  %close_n = arith.constant 1 : index
  %none_o = arith.constant 0 : index  // ""
  %none_n = arith.constant 0 : index
  %digits = llvm.alloca %c20 x i8 : (i64) -> !llvm.ptr
  // the reader's rooms: the decoded strings (as long as the text), their windows (every string has two quotes) and
  // the lists' counts
  %half0 = arith.divui %tn, %c2 : i64
  %half = arith.addi %half0, %c2 : i64
  %nwords = arith.muli %half, %c2 : i64
  %ncounts = arith.addi %half, %c5 : i64
  %tni = arith.index_cast %tn : i64 to index
  %nwi = arith.index_cast %nwords : i64 to index
  %nci = arith.index_cast %ncounts : i64 to index
  %room = memref.alloc(%tni) : memref<?xi8>
  %winsm = memref.alloc(%nwi) : memref<?xi64>
  %countsm = memref.alloc(%nci) : memref<?xi64>
  %rb = memref.extract_aligned_pointer_as_index %room : memref<?xi8> -> index
  %rb64 = arith.index_cast %rb : index to i64
  %roomp = llvm.inttoptr %rb64 : i64 to !llvm.ptr
  %wb = memref.extract_aligned_pointer_as_index %winsm : memref<?xi64> -> index
  %wb64 = arith.index_cast %wb : index to i64
  %wins = llvm.inttoptr %wb64 : i64 to !llvm.ptr
  %cb = memref.extract_aligned_pointer_as_index %countsm : memref<?xi64> -> index
  %cb64 = arith.index_cast %cb : index to i64
  %counts = llvm.inttoptr %cb64 : i64 to !llvm.ptr
  // the five lists' counts start at none (the reader adds to them; it may stop before it has met them all)
  %croom_d = func.call @dm_desc(%counts, %c40) : (!llvm.ptr, i64) -> !d
  %croom = builtin.unrealized_conversion_cast %croom_d : !d to !m
  %ce = trikeshed.drain %zeros, %croom : !s, !m -> index
  %fail = func.call @nixstore_ts_drvparse(%tp, %tn, %roomp, %wins, %counts) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  %cs_d = func.call @dm_desc(%counts, %ncounts) : (!llvm.ptr, i64) -> !d
  %cs_m = builtin.unrealized_conversion_cast %cs_d : !d to !m64
  %cs = builtin.unrealized_conversion_cast %cs_m : !m64 to !s64
  %nouts = trikeshed.at %cs[%z] : !s64, index -> i64
  %nins = trikeshed.at %cs[%i1] : !s64, index -> i64
  %nsrcs = trikeshed.at %cs[%i2] : !s64, index -> i64
  %nargs = trikeshed.at %cs[%i3] : !s64, index -> i64
  %nenv = trikeshed.at %cs[%i4] : !s64, index -> i64
  // the outputs the reader got through are classified first, as they were when they were read: what one of them
  // refuses is said before what the text's shape refuses
  %ost = func.call @dm_outputs(%wins, %nwords, %nouts, %d, %err) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr) -> i64
  %fine = arith.cmpi sge, %ost, %c0 : i64
  %r = scf.if %fine -> (i64) {
    %parsed = arith.cmpi slt, %fail, %c0 : i64
    %r1 = scf.if %parsed -> (i64) {
      // the windows after the outputs', in the text's order: the input derivations, the sources, the platform, the
      // builder, the arguments, the environment
      %w0 = arith.muli %nouts, %c4 : i64
      %w1 = func.call @dm_inputs(%wins, %nwords, %w0, %counts, %nins, %d) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
      %srcs = llvm.getelementptr %d[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %w2 = func.call @dm_strings(%wins, %nwords, %w1, %nsrcs, %srcs, %c0) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> i64
      %w2b = arith.addi %w2, %c1 : i64
      %platform = llvm.getelementptr %d[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %builder = llvm.getelementptr %d[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %plp, %pln = func.call @dm_win(%wins, %w2) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @dm_settext(%platform, %plp, %pln) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %bp, %bn = func.call @dm_win(%wins, %w2b) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @dm_settext(%builder, %bp, %bn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %w3 = arith.addi %w2, %c2 : i64
      %args = llvm.getelementptr %d[%c96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %w4 = func.call @dm_strings(%wins, %nwords, %w3, %nargs, %args, %c1) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> i64
      %w5 = func.call @dm_entries(%wins, %nwords, %w4, %nenv, %d) : (!llvm.ptr, i64, i64, i64, !llvm.ptr) -> i64
      scf.yield %c0 : i64
    } else {
      %dn = func.call @dm_decimal(%fail, %digits) : (i64, !llvm.ptr) -> i64
      %f = func.call @dm_fail(%err, %invalid_o, %invalid_n, %digits, %dn, %close_o, %close_n, %digits, %c0, %none_o, %none_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    }
    scf.yield %r1 : i64
  } else {
    scf.yield %c1 : i64
  }
  return %r : i64
}
