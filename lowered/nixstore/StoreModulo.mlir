// A derivation's hash modulo its fixed inputs, and its content as tokens (lib/Store/LocalStore.cpp's
// hashDerivationModulo and drvTokens are gone; LocalStore.cpp names these entries and keeps the error one returns with).
//
//   nixsb_tokcount, nixsb_tokens   drvTokens: a derivation as tokens {tag, a, b} in contentFingerprint's order, which
//                  StoreGraph.mlir folds into the fingerprint and walks for sameContent.  The room is sized ahead (the
//                  count), then filled once: each list of the derivation is a fold over its rows' words, a word put
//                  where its token wants it.  Tags: 0 a word, 1 a string, 2 a word not fingerprinted, 3 a hash's place,
//                  4 an output's kind, 5 an env value, 6 an output's path, 7 the outputs' count.
//   nixsb_modulo   hashDerivationModulo.  A fixed-output derivation (one output, "out", fixed): the hash of
//                  "fixed:out:<method and algorithm>:<hash, base 16>:<path>" (one combine drained once) by the output's
//                  name; answers 2.  Any other: an output that is content-addressed or impure is refused; then a fold
//                  over the input derivations, each one's own modulo hashes read from its record (made there when it has
//                  none yet) and its outputs put under that hash in base 16; then the derivation's text hashed with
//                  those inputs: answers 0.  1: the error is said or kept.
//
// A derivation is read where it lies (a Text is a pointer and 32 bits of length; a row of the outputs is 15 words: its
// name, kind in the third, its path, method and algorithm in the sixth, its hash from the seventh; a row of the input
// derivations a path and a set; a row of the environment two Texts); LocalStore.cpp holds each place read here against
// the headers.  A fold over rows takes their words one by one: its state is the words taken (the low half) and what it
// carries (the high half).  The constant texts are one blob (store-lits.py, kept with the module's proofs).
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// lits @sbm_lits
memref.global "private" constant @sbm_lits : memref<60xi8> =
  dense<"0x0a66697865643a6f75743a0002723a0005746578743a000000036d64350004736861310006736861323536000673686135313200013a00036f757400">

func.func private @abort()
// the system's words (StoreBuildDarwin.mlir.in, StoreBuildLinux.mlir.in)
func.func private @nixsb_os_grow(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_os_free(!llvm.ptr)
// the store's words (StoreWords.mlir): 25 content-addressed and impure derivations, 26 no hash for an output
func.func private @nixsb_say(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
// the store's (lib/Store/LocalStore.cpp), none of which throws: a hash made (how 3: these bytes'); the path a hash
// names (no bytes and -1: the error is kept); an input derivation's record with its modulo hashes made (none: the
// error is kept); a set of outputs (none: the one output "out") put under a hash's text in the inputs; a hash put under
// a name; the derivation's text hashed with the inputs and put under "" (1: the error is kept)
func.func private @nixsb_hash(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_fixedpath(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_modrec(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_merge(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr)
func.func private @nixsb_sethash(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr)
func.func private @nixsb_hashdrv(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
// base 16 (Encoders.mlir), outputPathName (StoreName.mlir), a sorted row by its key (SortedRows.mlir)
func.func private @mlnix_base16_encode(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_outputname(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_rowfind(!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64

//===----------------------------------------------------------------------===//
// Words, texts
//===----------------------------------------------------------------------===//

// the descriptor of n cells at p
func.func private @sbm_d(%p: !llvm.ptr, %n: i64) -> !d {
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

// word i of the words at p
func.func private @sbm_w(%p: !llvm.ptr, %i: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %n = arith.addi %i, %c1 : i64
  %pd = func.call @sbm_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m64
  %ps = builtin.unrealized_conversion_cast %pm : !m64 to !s64
  %ii = arith.index_cast %i : i64 to index
  %v = trikeshed.at %ps[%ii] : !s64, index -> i64
  return %v : i64
}

// the Text at t: its bytes (as a word) and its length; a set's or a map's rows and their count
func.func private @sbm_text(%t: !llvm.ptr) -> (i64, i64) {
  %c2 = arith.constant 2 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %low32 = arith.constant 4294967295 : i64
  %td = func.call @sbm_d(%t, %c2) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m64
  %ts = builtin.unrealized_conversion_cast %tm : !m64 to !s64
  %pb = trikeshed.at %ts[%z] : !s64, index -> i64
  %nw = trikeshed.at %ts[%i1] : !s64, index -> i64
  %n = arith.andi %nw, %low32 : i64
  return %pb, %n : i64, i64
}

// the constant text at `off` of the blob (a length byte, then its bytes and a NUL): its bytes and its length
func.func private @sbm_lit(%off: i64) -> (!llvm.ptr, i64) {
  %c1 = arith.constant 1 : i64
  %g = memref.get_global @sbm_lits : memref<60xi8> // lits
  %lits = trikeshed.text %g : memref<60xi8> -> !s // lits
  %oi = arith.index_cast %off : i64 to index
  %n8 = trikeshed.at %lits[%oi] : !s, index -> i8
  %n = arith.extui %n8 : i8 to i64
  %bi = memref.extract_aligned_pointer_as_index %g : memref<60xi8> -> index // lits
  %b64 = arith.index_cast %bi : index to i64
  %base = llvm.inttoptr %b64 : i64 to !llvm.ptr
  %o1 = arith.addi %off, %c1 : i64
  %p = llvm.getelementptr %base[%o1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p, %n : !llvm.ptr, i64
}

// the n bytes at p as a series
// (a descriptor and two casts each time: a view is not returned from a function)

//===----------------------------------------------------------------------===//
// drvTokens
//===----------------------------------------------------------------------===//

// The outputs the input derivations give, counted: a fold over the rows' words (four a row), a row's fourth the count
// of its set.
func.func private @sbm_given(%rows: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %n4 = arith.muli %n, %c4 : i64
  %wd = func.call @sbm_d(%rows, %n4) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %end = trikeshed.fold %words, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %count = arith.andi %acc, %low32 : i64
    %sum = arith.shrui %acc, %c32 : i64
    %phase = arith.andi %count, %c3 : i64
    %last = arith.cmpi eq, %phase, %c3 : i64
    %k = arith.andi %w, %low32 : i64
    %add = arith.select %last, %k, %c0 : i64
    %sum1 = arith.addi %sum, %add : i64
    %count1 = arith.addi %count, %c1 : i64
    %hi = arith.shli %sum1, %c32 : i64
    %acc1 = arith.ori %hi, %count1 : i64
    trikeshed.yield %acc1 : i64
  }
  %res = arith.shrui %end, %c32 : i64
  return %res : i64
}

// How many tokens the derivation is: three strings; the arguments and the sources, a count and a string each; the input
// derivations' count, then a path, a count and its outputs each; the outputs' count and six tokens each; the
// environment's count and two strings each; whether there are structured attributes, and them.
func.func @nixsb_tokcount(%drv: !llvm.ptr) -> i64 {
  %c2 = arith.constant 2 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c96 = arith.constant 96 : i64
  %c112 = arith.constant 112 : i64
  %c128 = arith.constant 128 : i64
  %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ins = llvm.getelementptr %drv[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %srcs = llvm.getelementptr %drv[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %args = llvm.getelementptr %drv[%c96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %env = llvm.getelementptr %drv[%c112] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %hasp = llvm.getelementptr %drv[%c128] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ob, %on = func.call @sbm_text(%outs) : (!llvm.ptr) -> (i64, i64)
  %ib, %in = func.call @sbm_text(%ins) : (!llvm.ptr) -> (i64, i64)
  %sb, %sn = func.call @sbm_text(%srcs) : (!llvm.ptr) -> (i64, i64)
  %ab, %an = func.call @sbm_text(%args) : (!llvm.ptr) -> (i64, i64)
  %eb, %en = func.call @sbm_text(%env) : (!llvm.ptr) -> (i64, i64)
  %has8 = llvm.load %hasp : !llvm.ptr -> i8
  %has = arith.extui %has8 : i8 to i64
  %irows = llvm.inttoptr %ib : i64 to !llvm.ptr
  %given = func.call @sbm_given(%irows, %in) : (!llvm.ptr, i64) -> i64
  %in2 = arith.muli %in, %c2 : i64
  %on6 = arith.muli %on, %c6 : i64
  %en2 = arith.muli %en, %c2 : i64
  %n0 = arith.addi %c9, %an : i64
  %n1 = arith.addi %n0, %sn : i64
  %n2 = arith.addi %n1, %in2 : i64
  %n3 = arith.addi %n2, %given : i64
  %n4 = arith.addi %n3, %on6 : i64
  %n5 = arith.addi %n4, %en2 : i64
  %n6 = arith.addi %n5, %has : i64
  return %n6 : i64
}

// Strings as tokens from token k on: the Texts are the nw words at rows, two each; a fold over the words, a Text's
// pointer its token's second word, its length the third.  The Texts are tagged 1, every second of them `tag2` (a row of
// the environment is a name and a value: 5).  The next token's number.
func.func private @sbm_strings(%room: !llvm.ptr, %words3: i64, %k: i64, %rows: !llvm.ptr, %nw: i64, %tag2: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %rd = func.call @sbm_d(%room, %words3) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %wd = func.call @sbm_d(%rows, %nw) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %zero = arith.shli %k, %c32 : i64
  %end = trikeshed.fold %words, %zero : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %count = arith.andi %acc, %low32 : i64
    %tok = arith.shrui %acc, %c32 : i64
    %odd = arith.andi %count, %c1 : i64
    %islen = arith.cmpi ne, %odd, %c0 : i64
    %t3 = arith.muli %tok, %c3 : i64
    %ti = arith.index_cast %t3 : i64 to index
    %next = scf.if %islen -> (i64) {
      %len = arith.andi %w, %low32 : i64
      %at = arith.addi %ti, %i2 : index
      memref.store %len, %rm[%at] : !m64
      %tok1 = arith.addi %tok, %c1 : i64
      scf.yield %tok1 : i64
    } else {
      %second = arith.andi %count, %c2 : i64
      %is2 = arith.cmpi ne, %second, %c0 : i64
      %tag = arith.select %is2, %tag2, %c1 : i64
      %at = arith.addi %ti, %i1 : index
      memref.store %tag, %rm[%ti] : !m64
      memref.store %w, %rm[%at] : !m64
      scf.yield %tok : i64
    }
    %count1 = arith.addi %count, %c1 : i64
    %hi = arith.shli %next, %c32 : i64
    %acc1 = arith.ori %hi, %count1 : i64
    trikeshed.yield %acc1 : i64
  }
  %res = arith.shrui %end, %c32 : i64
  return %res : i64
}

// token k set whole; the next token's number
func.func private @sbm_tok(%room: !llvm.ptr, %words3: i64, %k: i64, %tag: i64, %a: i64, %b: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %rd = func.call @sbm_d(%room, %words3) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %t3 = arith.muli %k, %c3 : i64
  %ti = arith.index_cast %t3 : i64 to index
  %at1 = arith.addi %ti, %i1 : index
  %at2 = arith.addi %ti, %i2 : index
  memref.store %tag, %rm[%ti] : !m64
  memref.store %a, %rm[%at1] : !m64
  memref.store %b, %rm[%at2] : !m64
  %next = arith.addi %k, %c1 : i64
  return %next : i64
}

// The input derivations as tokens from token k on: a fold over the rows' words (four a row): the path's pointer and
// length a string; at the set's count (the row's fourth word), the count and the strings of the set's rows (the word
// before).
func.func private @sbm_inputs(%room: !llvm.ptr, %words3: i64, %k: i64, %rows: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %rd = func.call @sbm_d(%room, %words3) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %n4 = arith.muli %n, %c4 : i64
  %wd = func.call @sbm_d(%rows, %n4) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %zero = arith.shli %k, %c32 : i64
  %end = trikeshed.fold %words, %zero : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %count = arith.andi %acc, %low32 : i64
    %tok = arith.shrui %acc, %c32 : i64
    %phase = arith.andi %count, %c3 : i64
    %t3 = arith.muli %tok, %c3 : i64
    %ti = arith.index_cast %t3 : i64 to index
    %p0 = arith.cmpi eq, %phase, %c0 : i64
    %p1 = arith.cmpi eq, %phase, %c1 : i64
    %p2 = arith.cmpi eq, %phase, %c2 : i64
    %next = scf.if %p0 -> (i64) {
      %at = arith.addi %ti, %i1 : index
      memref.store %c1, %rm[%ti] : !m64
      memref.store %w, %rm[%at] : !m64
      scf.yield %tok : i64
    } else {
      %r1 = scf.if %p1 -> (i64) {
        %len = arith.andi %w, %low32 : i64
        %at = arith.addi %ti, %i2 : index
        memref.store %len, %rm[%at] : !m64
        %tok1 = arith.addi %tok, %c1 : i64
        scf.yield %tok1 : i64
      } else {
        %r2 = scf.if %p2 -> (i64) {
          scf.yield %tok : i64
        } else {
          %no = arith.andi %w, %low32 : i64
          %tok1 = func.call @sbm_tok(%room, %words3, %tok, %c0, %no, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
          %before = arith.subi %count, %c1 : i64
          %bi = arith.index_cast %before : i64 to index
          %ob = trikeshed.at %words[%bi] : !s64, index -> i64
          %orows = llvm.inttoptr %ob : i64 to !llvm.ptr
          %no2 = arith.muli %no, %c2 : i64
          %tok2 = func.call @sbm_strings(%room, %words3, %tok1, %orows, %no2, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
          scf.yield %tok2 : i64
        }
        scf.yield %r2 : i64
      }
      scf.yield %r1 : i64
    }
    %count1 = arith.addi %count, %c1 : i64
    %hi = arith.shli %next, %c32 : i64
    %acc1 = arith.ori %hi, %count1 : i64
    trikeshed.yield %acc1 : i64
  }
  %res = arith.shrui %end, %c32 : i64
  return %res : i64
}

// The outputs as tokens from token k on: a fold over the rows' words (15 a row): the name a string; the kind (tag 4); the
// path (tag 6); the method and the algorithm, the two halves of one word (tag 2 each); the hash's place, which is where
// the seventh word lies (tag 3).
func.func private @sbm_outputs(%room: !llvm.ptr, %words3: i64, %k: i64, %rows: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %rd = func.call @sbm_d(%room, %words3) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rowsb = llvm.ptrtoint %rows : !llvm.ptr to i64
  %n15 = arith.muli %n, %c15 : i64
  %wd = func.call @sbm_d(%rows, %n15) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %zero = arith.shli %k, %c32 : i64
  %end = trikeshed.fold %words, %zero : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %count = arith.andi %acc, %low32 : i64
    %tok = arith.shrui %acc, %c32 : i64
    %phase = arith.remui %count, %c15 : i64
    %t3 = arith.muli %tok, %c3 : i64
    %ti = arith.index_cast %t3 : i64 to index
    %lo = arith.andi %w, %low32 : i64
    %isptr0 = arith.cmpi eq, %phase, %c0 : i64
    %isptr3 = arith.cmpi eq, %phase, %c3 : i64
    %isptr = arith.ori %isptr0, %isptr3 : i1
    %islen1 = arith.cmpi eq, %phase, %c1 : i64
    %islen4 = arith.cmpi eq, %phase, %c4 : i64
    %islen = arith.ori %islen1, %islen4 : i1
    %next = scf.if %isptr -> (i64) {
      // a string begins: the name's tag is 1, the path's 6
      %tag = arith.select %isptr0, %c1, %c6 : i64
      %at = arith.addi %ti, %i1 : index
      memref.store %tag, %rm[%ti] : !m64
      memref.store %w, %rm[%at] : !m64
      scf.yield %tok : i64
    } else {
      %r1 = scf.if %islen -> (i64) {
        %at = arith.addi %ti, %i2 : index
        memref.store %lo, %rm[%at] : !m64
        %tok1 = arith.addi %tok, %c1 : i64
        scf.yield %tok1 : i64
      } else {
        %iskind = arith.cmpi eq, %phase, %c2 : i64
        %r2 = scf.if %iskind -> (i64) {
          %tok1 = func.call @sbm_tok(%room, %words3, %tok, %c4, %lo, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
          scf.yield %tok1 : i64
        } else {
          %ismethod = arith.cmpi eq, %phase, %c5 : i64
          %r3 = scf.if %ismethod -> (i64) {
            %algo = arith.shrui %w, %c32 : i64
            %tok1 = func.call @sbm_tok(%room, %words3, %tok, %c2, %lo, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
            %tok2 = func.call @sbm_tok(%room, %words3, %tok1, %c2, %algo, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
            scf.yield %tok2 : i64
          } else {
            %ishash = arith.cmpi eq, %phase, %c6 : i64
            %r4 = scf.if %ishash -> (i64) {
              %off = arith.muli %count, %c8 : i64
              %place = arith.addi %rowsb, %off : i64
              %tok1 = func.call @sbm_tok(%room, %words3, %tok, %c3, %place, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
              scf.yield %tok1 : i64
            } else {
              scf.yield %tok : i64
            }
            scf.yield %r4 : i64
          }
          scf.yield %r3 : i64
        }
        scf.yield %r2 : i64
      }
      scf.yield %r1 : i64
    }
    %count1 = arith.addi %count, %c1 : i64
    %hi = arith.shli %next, %c32 : i64
    %acc1 = arith.ori %hi, %count1 : i64
    trikeshed.yield %acc1 : i64
  }
  %res = arith.shrui %end, %c32 : i64
  return %res : i64
}

// The derivation's tokens put in the room (nixsb_tokcount's tokens of three words): how many.
func.func @nixsb_tokens(%drv: !llvm.ptr, %room: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c7 = arith.constant 7 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c64 = arith.constant 64 : i64
  %c80 = arith.constant 80 : i64
  %c96 = arith.constant 96 : i64
  %c112 = arith.constant 112 : i64
  %c128 = arith.constant 128 : i64
  %c136 = arith.constant 136 : i64
  %w3 = arith.muli %n, %c3 : i64
  %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ins = llvm.getelementptr %drv[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %srcs = llvm.getelementptr %drv[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %platform = llvm.getelementptr %drv[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %builder = llvm.getelementptr %drv[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %args = llvm.getelementptr %drv[%c96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %env = llvm.getelementptr %drv[%c112] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %hasp = llvm.getelementptr %drv[%c128] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %json = llvm.getelementptr %drv[%c136] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // the name, the platform, the builder
  %k1 = func.call @sbm_strings(%room, %w3, %c0, %drv, %c2, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  %k3 = func.call @sbm_strings(%room, %w3, %k1, %platform, %c4, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  // the arguments, the sources: a count and the strings
  %ab, %an = func.call @sbm_text(%args) : (!llvm.ptr) -> (i64, i64)
  %arows = llvm.inttoptr %ab : i64 to !llvm.ptr
  %an2 = arith.muli %an, %c2 : i64
  %k4 = func.call @sbm_tok(%room, %w3, %k3, %c0, %an, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %k5 = func.call @sbm_strings(%room, %w3, %k4, %arows, %an2, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  %sb, %sn = func.call @sbm_text(%srcs) : (!llvm.ptr) -> (i64, i64)
  %srows = llvm.inttoptr %sb : i64 to !llvm.ptr
  %sn2 = arith.muli %sn, %c2 : i64
  %k6 = func.call @sbm_tok(%room, %w3, %k5, %c0, %sn, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %k7 = func.call @sbm_strings(%room, %w3, %k6, %srows, %sn2, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  // the input derivations
  %ib, %in = func.call @sbm_text(%ins) : (!llvm.ptr) -> (i64, i64)
  %irows = llvm.inttoptr %ib : i64 to !llvm.ptr
  %k8 = func.call @sbm_tok(%room, %w3, %k7, %c0, %in, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %k9 = func.call @sbm_inputs(%room, %w3, %k8, %irows, %in) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  // the outputs
  %ob, %on = func.call @sbm_text(%outs) : (!llvm.ptr) -> (i64, i64)
  %orows = llvm.inttoptr %ob : i64 to !llvm.ptr
  %k10 = func.call @sbm_tok(%room, %w3, %k9, %c7, %on, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %k11 = func.call @sbm_outputs(%room, %w3, %k10, %orows, %on) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  // the environment: a name and a value (tag 5) a row
  %eb, %en = func.call @sbm_text(%env) : (!llvm.ptr) -> (i64, i64)
  %erows = llvm.inttoptr %eb : i64 to !llvm.ptr
  %en4 = arith.muli %en, %c4 : i64
  %k12 = func.call @sbm_tok(%room, %w3, %k11, %c0, %en, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %k13 = func.call @sbm_strings(%room, %w3, %k12, %erows, %en4, %c5) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  // the structured attributes
  %has8 = llvm.load %hasp : !llvm.ptr -> i8
  %has = arith.extui %has8 : i8 to i64
  %k14 = func.call @sbm_tok(%room, %w3, %k13, %c0, %has, %c0) : (!llvm.ptr, i64, i64, i64, i64, i64) -> i64
  %hasn = arith.muli %has, %c2 : i64
  %k15 = func.call @sbm_strings(%room, %w3, %k14, %json, %hasn, %c1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, i64) -> i64
  return %k15 : i64
}

//===----------------------------------------------------------------------===//
// hashDerivationModulo
//===----------------------------------------------------------------------===//

// a room of n bytes, the caller's to give back
func.func private @sbm_room(%n: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %want = arith.maxsi %n, %c8 : i64
  %p = func.call @nixsb_os_grow(%null, %want) : (!llvm.ptr, i64) -> !llvm.ptr
  %pb = llvm.ptrtoint %p : !llvm.ptr to i64
  %none = arith.cmpi eq, %pb, %c0 : i64
  scf.if %none {
    func.call @abort() : () -> ()
  }
  return %p : !llvm.ptr
}

// A hash in base 16, written at `into` (128 bytes of room): how many digits.  Its bytes follow its algorithm (a word of
// 32 bits: 0 MD5, 16 bytes; 1 SHA-1, 20; 2 SHA-256, 32; 3 SHA-512, 64).
func.func private @sbm_hex(%hash: !llvm.ptr, %into: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c16 = arith.constant 16 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %c64 = arith.constant 64 : i64
  %low32 = arith.constant 4294967295 : i64
  %aw = func.call @sbm_w(%hash, %c0) : (!llvm.ptr, i64) -> i64
  %algo = arith.andi %aw, %low32 : i64
  %is0 = arith.cmpi eq, %algo, %c0 : i64
  %is1 = arith.cmpi eq, %algo, %c1 : i64
  %is2 = arith.cmpi eq, %algo, %c2 : i64
  %s2 = arith.select %is2, %c32, %c64 : i64
  %s1 = arith.select %is1, %c20, %s2 : i64
  %size = arith.select %is0, %c16, %s1 : i64
  %bytes = llvm.getelementptr %hash[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n = func.call @mlnix_base16_encode(%bytes, %size, %into) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  return %n : i64
}

// A fixed-output derivation's hash: of "fixed:out:", the output's method ("r:" a tree, "text:" a text, none a file) and
// its hash's algorithm, ":", the hash in base 16, ":", and the output's path (the one its hash names): one combine
// drained once, hashed, and put under the output's name.  orow: the output's row.
func.func private @sbm_fixed(%c: !llvm.ptr, %drv: !llvm.ptr, %orow: !llvm.ptr, %res: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c48 = arith.constant 48 : i64
  %low32 = arith.constant 4294967295 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %o_head = arith.constant 0 : i64 // lit "fixed:out:"
  %o_r = arith.constant 12 : i64 // lit "r:"
  %o_text = arith.constant 16 : i64 // lit "text:"
  %o_none = arith.constant 23 : i64 // lit ""
  %o_md5 = arith.constant 25 : i64 // lit "md5"
  %o_sha1 = arith.constant 30 : i64 // lit "sha1"
  %o_sha256 = arith.constant 36 : i64 // lit "sha256"
  %o_sha512 = arith.constant 44 : i64 // lit "sha512"
  %o_colon = arith.constant 52 : i64 // lit ":"
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %h = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %hex = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  %hash = llvm.getelementptr %orow[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %mw = func.call @sbm_w(%orow, %c5) : (!llvm.ptr, i64) -> i64
  %aw = func.call @sbm_w(%orow, %c6) : (!llvm.ptr, i64) -> i64
  %method = arith.andi %mw, %low32 : i64
  %algo = arith.andi %aw, %low32 : i64
  // the path the hash names: the output's name of the derivation's name
  %db, %dn = func.call @sbm_text(%drv) : (!llvm.ptr) -> (i64, i64)
  %kb, %kn = func.call @sbm_text(%orow) : (!llvm.ptr) -> (i64, i64)
  %dp = llvm.inttoptr %db : i64 to !llvm.ptr
  %kp = llvm.inttoptr %kb : i64 to !llvm.ptr
  %nn0 = arith.addi %dn, %kn : i64
  %ncap = arith.addi %nn0, %c2 : i64
  %name = func.call @sbm_room(%ncap) : (i64) -> !llvm.ptr
  %nlen = func.call @nixstore_ts_outputname(%dp, %dn, %kp, %kn, %name) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
  %pp = func.call @nixsb_fixedpath(%c, %name, %nlen, %method, %hash, %null, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
  %pn = func.call @sbm_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
  func.call @nixsb_os_free(%name) : (!llvm.ptr) -> ()
  %named = arith.cmpi sge, %pn, %c0 : i64
  %res1 = scf.if %named -> (i64) {
    %tree = arith.cmpi eq, %method, %c1 : i64
    %astext = arith.cmpi eq, %method, %c2 : i64
    %m0 = arith.select %astext, %o_text, %o_none : i64
    %moff = arith.select %tree, %o_r, %m0 : i64
    %is0 = arith.cmpi eq, %algo, %c0 : i64
    %is1 = arith.cmpi eq, %algo, %c1 : i64
    %is2 = arith.cmpi eq, %algo, %c2 : i64
    %a2 = arith.select %is2, %o_sha256, %o_sha512 : i64
    %a1 = arith.select %is1, %o_sha1, %a2 : i64
    %aoff = arith.select %is0, %o_md5, %a1 : i64
    %hp, %hn = func.call @sbm_lit(%o_head) : (i64) -> (!llvm.ptr, i64)
    %mp, %mn = func.call @sbm_lit(%moff) : (i64) -> (!llvm.ptr, i64)
    %ap, %an = func.call @sbm_lit(%aoff) : (i64) -> (!llvm.ptr, i64)
    %cp, %cn = func.call @sbm_lit(%o_colon) : (i64) -> (!llvm.ptr, i64)
    %xn = func.call @sbm_hex(%hash, %hex) : (!llvm.ptr, !llvm.ptr) -> i64
    %t0 = arith.addi %hn, %mn : i64
    %t1 = arith.addi %t0, %an : i64
    %t2 = arith.addi %t1, %cn : i64
    %t3 = arith.addi %t2, %xn : i64
    %t4 = arith.addi %t3, %cn : i64
    %size = arith.addi %t4, %pn : i64
    %room = func.call @sbm_room(%size) : (i64) -> !llvm.ptr
    %h_d = func.call @sbm_d(%hp, %hn) : (!llvm.ptr, i64) -> !d
    %h_m = builtin.unrealized_conversion_cast %h_d : !d to !m
    %hs = builtin.unrealized_conversion_cast %h_m : !m to !s
    %m_d = func.call @sbm_d(%mp, %mn) : (!llvm.ptr, i64) -> !d
    %m_m = builtin.unrealized_conversion_cast %m_d : !d to !m
    %ms = builtin.unrealized_conversion_cast %m_m : !m to !s
    %a_d = func.call @sbm_d(%ap, %an) : (!llvm.ptr, i64) -> !d
    %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
    %as = builtin.unrealized_conversion_cast %a_m : !m to !s
    %c_d = func.call @sbm_d(%cp, %cn) : (!llvm.ptr, i64) -> !d
    %c_m = builtin.unrealized_conversion_cast %c_d : !d to !m
    %cs = builtin.unrealized_conversion_cast %c_m : !m to !s
    %x_d = func.call @sbm_d(%hex, %xn) : (!llvm.ptr, i64) -> !d
    %x_m = builtin.unrealized_conversion_cast %x_d : !d to !m
    %xs = builtin.unrealized_conversion_cast %x_m : !m to !s
    %p_d = func.call @sbm_d(%pp, %pn) : (!llvm.ptr, i64) -> !d
    %p_m = builtin.unrealized_conversion_cast %p_d : !d to !m
    %ps = builtin.unrealized_conversion_cast %p_m : !m to !s
    %all = trikeshed.combine %hs, %ms, %as, %cs, %xs, %cs, %ps : !s, !s, !s, !s, !s, !s, !s -> !s
    %r_d = func.call @sbm_d(%room, %size) : (!llvm.ptr, i64) -> !d
    %r_m = builtin.unrealized_conversion_cast %r_d : !d to !m
    %end = trikeshed.drain %all, %r_m : !s, !m -> index
    %hs1 = func.call @nixsb_hash(%c, %c3, %c2, %room, %size, %h, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
    func.call @nixsb_os_free(%room) : (!llvm.ptr) -> ()
    func.call @nixsb_sethash(%res, %kp, %kn, %h) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
    scf.yield %hs1 : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res1 : i64
}

// One input derivation put into the inputs: its record's modulo hashes (made by the store when the record has none);
// where it has one hash for the whole derivation, that hash's text (the record's) names the outputs the derivation takes
// of it; else each of those outputs' own hash, in base 16, names the output "out".  row: the input's row (its path, then
// the set of outputs taken); dname: the derivation's name, for the error.  A record: its modulo hashes' rows at 176 (88
// bytes a row: a name, then the hash at 16), the one hash's text at 192.
func.func private @sbm_input(%c: !llvm.ptr, %row: !llvm.ptr, %inputs: !llvm.ptr, %dp: !llvm.ptr, %dn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c16 = arith.constant 16 : i64
  %c26 = arith.constant 26 : i64
  %c32 = arith.constant 32 : i64
  %c88 = arith.constant 88 : i64
  %c176 = arith.constant 176 : i64
  %c192 = arith.constant 192 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %hex = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  %pb, %pn = func.call @sbm_text(%row) : (!llvm.ptr) -> (i64, i64)
  %pp = llvm.inttoptr %pb : i64 to !llvm.ptr
  %rec = func.call @nixsb_modrec(%c, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %rb = llvm.ptrtoint %rec : !llvm.ptr to i64
  %made = arith.cmpi ne, %rb, %c0 : i64
  %res = scf.if %made -> (i64) {
    %set = llvm.getelementptr %row[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %hext = llvm.getelementptr %rec[%c192] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %xb, %xn = func.call @sbm_text(%hext) : (!llvm.ptr) -> (i64, i64)
    %one = arith.cmpi ne, %xn, %c0 : i64
    %r = scf.if %one -> (i64) {
      %xp = llvm.inttoptr %xb : i64 to !llvm.ptr
      func.call @nixsb_merge(%inputs, %xp, %xn, %set) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
      scf.yield %c0 : i64
    } else {
      // each output taken: its hash among the record's, by its name
      %hashes = llvm.getelementptr %rec[%c176] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %hb, %hn = func.call @sbm_text(%hashes) : (!llvm.ptr) -> (i64, i64)
      %hrows = llvm.inttoptr %hb : i64 to !llvm.ptr
      %ob, %on = func.call @sbm_text(%set) : (!llvm.ptr) -> (i64, i64)
      %orows = llvm.inttoptr %ob : i64 to !llvm.ptr
      %on2 = arith.muli %on, %c2 : i64
      %wd = func.call @sbm_d(%orows, %on2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %end = trikeshed.fold %words, %c0 : !s64, i64 -> i64 {
      ^bb0(%acc: i64, %w: i64):
        %count = arith.andi %acc, %low32 : i64
        %st = arith.shrui %acc, %c32 : i64
        %odd = arith.andi %count, %c1 : i64
        %first = arith.cmpi eq, %odd, %c0 : i64
        %fine = arith.cmpi eq, %st, %c0 : i64
        %go = arith.andi %first, %fine : i1
        %st1 = scf.if %go -> (i64) {
          // the output's name: this word and the length after it
          %c8 = arith.constant 8 : i64
          %off = arith.muli %count, %c8 : i64
          %t = llvm.getelementptr %orows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %nb, %nn = func.call @sbm_text(%t) : (!llvm.ptr) -> (i64, i64)
          %np = llvm.inttoptr %nb : i64 to !llvm.ptr
          %at = func.call @nixstore_ts_rowfind(%hrows, %hn, %c88, %np, %nn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
          %has = arith.cmpi sge, %at, %c0 : i64
          %s = scf.if %has -> (i64) {
            %ho0 = arith.muli %at, %c88 : i64
            %ho = arith.addi %ho0, %c16 : i64
            %hash = llvm.getelementptr %hrows[%ho] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %k = func.call @sbm_hex(%hash, %hex) : (!llvm.ptr, !llvm.ptr) -> i64
            func.call @nixsb_merge(%inputs, %hex, %k, %null) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> ()
            scf.yield %c0 : i64
          } else {
            %said = func.call @nixsb_say(%c, %c0, %c26, %np, %nn, %dp, %dn, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
            scf.yield %c1 : i64
          }
          scf.yield %s : i64
        } else {
          scf.yield %st : i64
        }
        %count1 = arith.addi %count, %c1 : i64
        %hi = arith.shli %st1, %c32 : i64
        %acc1 = arith.ori %hi, %count1 : i64
        trikeshed.yield %acc1 : i64
      }
      %s2 = arith.shrui %end, %c32 : i64
      scf.yield %s2 : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

// Whether an output of the n rows is content-addressed (kind 2) or impure (4): a fold over the rows' words, a row's
// third its kind.
func.func private @sbm_refused(%rows: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c15 = arith.constant 15 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %n15 = arith.muli %n, %c15 : i64
  %wd = func.call @sbm_d(%rows, %n15) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %end = trikeshed.fold %words, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %count = arith.andi %acc, %low32 : i64
    %bad = arith.shrui %acc, %c32 : i64
    %phase = arith.remui %count, %c15 : i64
    %iskind = arith.cmpi eq, %phase, %c2 : i64
    %kind = arith.andi %w, %low32 : i64
    %k2 = arith.cmpi eq, %kind, %c2 : i64
    %k4 = arith.cmpi eq, %kind, %c4 : i64
    %k = arith.ori %k2, %k4 : i1
    %is = arith.andi %iskind, %k : i1
    %one = arith.extui %is : i1 to i64
    %bad1 = arith.ori %bad, %one : i64
    %count1 = arith.addi %count, %c1 : i64
    %hi = arith.shli %bad1, %c32 : i64
    %acc1 = arith.ori %hi, %count1 : i64
    trikeshed.yield %acc1 : i64
  }
  %res = arith.shrui %end, %c32 : i64
  return %res : i64
}

// whether the n bytes at p are the constant text at off
func.func private @sbm_is(%p: !llvm.ptr, %n: i64, %off: i64) -> i1 {
  %z32 = arith.constant 0 : i32
  %lp, %ln = func.call @sbm_lit(%off) : (i64) -> (!llvm.ptr, i64)
  %a_d = func.call @sbm_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sbm_d(%lp, %ln) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c = trikeshed.compare %a, %b unsigned : !s, !s
  %same = arith.cmpi eq, %c, %z32 : i32
  return %same : i1
}

// c: the store's context; drv: the derivation; mask: whether its own output paths are left out of its text; inputs: a
// map that gets the input derivations as the hash saw them (each one's modulo hash in base 16, and the outputs taken);
// res: a map the hashes are put in by name.  0; 2 for a fixed-output derivation (inputs is not touched); 1 an error.
func.func @nixsb_modulo(%c: !llvm.ptr, %drv: !llvm.ptr, %mask: i64, %inputs: !llvm.ptr, %res: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c25 = arith.constant 25 : i64
  %c32 = arith.constant 32 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %o_out = arith.constant 55 : i64 // lit "out"
  %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ob, %on = func.call @sbm_text(%outs) : (!llvm.ptr) -> (i64, i64)
  %orows = llvm.inttoptr %ob : i64 to !llvm.ptr
  %db, %dn = func.call @sbm_text(%drv) : (!llvm.ptr) -> (i64, i64)
  %dp = llvm.inttoptr %db : i64 to !llvm.ptr
  // fixed: one output, "out", of kind 1
  %single = arith.cmpi eq, %on, %c1 : i64
  %fixed = scf.if %single -> (i1) {
    %kb, %kn = func.call @sbm_text(%orows) : (!llvm.ptr) -> (i64, i64)
    %kp = llvm.inttoptr %kb : i64 to !llvm.ptr
    %isout = func.call @sbm_is(%kp, %kn, %o_out) : (!llvm.ptr, i64, i64) -> i1
    %kw = func.call @sbm_w(%orows, %c2) : (!llvm.ptr, i64) -> i64
    %kind = arith.andi %kw, %low32 : i64
    %k1 = arith.cmpi eq, %kind, %c1 : i64
    %f = arith.andi %isout, %k1 : i1
    scf.yield %f : i1
  } else {
    %no = arith.constant 0 : i1
    scf.yield %no : i1
  }
  %r = scf.if %fixed -> (i64) {
    %fs = func.call @sbm_fixed(%c, %drv, %orows, %res) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %ok = arith.cmpi eq, %fs, %c0 : i64
    %r1 = arith.select %ok, %c2, %c1 : i64
    scf.yield %r1 : i64
  } else {
    %bad = func.call @sbm_refused(%orows, %on) : (!llvm.ptr, i64) -> i64
    %refused = arith.cmpi ne, %bad, %c0 : i64
    %r2 = scf.if %refused -> (i64) {
      %said = func.call @nixsb_say(%c, %c0, %c25, %dp, %dn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %c1 : i64
    } else {
      // the input derivations: a fold over their rows' words, a row taken at its first
      %ins = llvm.getelementptr %drv[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %ib, %in = func.call @sbm_text(%ins) : (!llvm.ptr) -> (i64, i64)
      %irows = llvm.inttoptr %ib : i64 to !llvm.ptr
      %in4 = arith.muli %in, %c4 : i64
      %wd = func.call @sbm_d(%irows, %in4) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %words = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %end = trikeshed.fold %words, %c0 : !s64, i64 -> i64 {
      ^bb0(%acc: i64, %w: i64):
        %count = arith.andi %acc, %low32 : i64
        %st = arith.shrui %acc, %c32 : i64
        %phase = arith.andi %count, %c3 : i64
        %first = arith.cmpi eq, %phase, %c0 : i64
        %fine = arith.cmpi eq, %st, %c0 : i64
        %go = arith.andi %first, %fine : i1
        %st1 = scf.if %go -> (i64) {
          %off = arith.muli %count, %c8 : i64
          %row = llvm.getelementptr %irows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %s = func.call @sbm_input(%c, %row, %inputs, %dp, %dn) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
          scf.yield %s : i64
        } else {
          scf.yield %st : i64
        }
        %count1 = arith.addi %count, %c1 : i64
        %hi = arith.shli %st1, %c32 : i64
        %acc1 = arith.ori %hi, %count1 : i64
        trikeshed.yield %acc1 : i64
      }
      %s1 = arith.shrui %end, %c32 : i64
      %go1 = arith.cmpi eq, %s1, %c0 : i64
      %r3 = scf.if %go1 -> (i64) {
        %hs = func.call @nixsb_hashdrv(%c, %drv, %mask, %inputs, %res) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %hs : i64
      } else {
        scf.yield %c1 : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}
