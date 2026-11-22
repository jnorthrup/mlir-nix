// The local store's graph and content algorithms (lib/Store/LocalStore.cpp) hollowed into the TrikeShed dialect.  The C++
// keeps the store's reads and writes (queryPathInfo's file, readDerivation, isValidPath, the deletions) as callbacks and
// marshals its sorted sets into window arrays; the algorithms are here:
//   nixstore_ts_union        drvReferences / writeDerivation's references: two sorted sets merged (sorted + where)
//   nixstore_ts_sortwins     NarFraming.mlir's walk: a directory's names (windows) as their indices in byte order (sorted)
//   nixstore_ts_xxh3         XXH3-64 (seed 0, the default secret), LLVM's llvm::xxh3_64bits bit for bit
//   nixstore_ts_fingerprint  contentFingerprint: a fold of the derivation's tokens through xxh3 and the word mix
//   nixstore_ts_samecontent  sameContent: the two derivations' token streams walked in step
//   nixstore_ts_closure      computeFSClosure: the worklist (a stack of frames) and the visited set (bisect + insert)
//   nixstore_ts_gc           collectGarbage: dead = valid minus live (where + bisect), then the referrer-safe rounds
//   nixstore_ts_infolines    queryPathInfo's lines (parts at '\n', the first ": ", the five keys)
//
// A window is 16 bytes {const char *p, int64 n}.  A token is 24 bytes {int64 tag, int64 a, int64 b}; tags:
//   0 a word (a)                 1 a string (a = ptr bits, b = length)      2 a word the fingerprint skips
//   3 a Hash* the fingerprint skips (Hash::operator==)                      4 an output's kind (a word)
//   5 an env value (a string)    6 an output's path (a string)              7 the outputs' count (a word)
// The fingerprint reads tags 0 4 7 as words and 1 5 6 as strings, in order (contentFingerprint's order); an output is the
// six tokens name(1) kind(4) path(6) method(2) hashAlgo(2) hash(3).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!sp = !trikeshed.series<!trikeshed.twinpacked<i32>>
!tp = !trikeshed.twinpacked<i32>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @sg_secret : memref<192xi8> = dense<"0xb8fe6c3923a44bbe7c01812cf721ad1cded46de9839097db7240a4a4b7b3671fcb79e64eccc0e578825ad07dccff7221b8084674f743248ee03590e6813a264c3c2852bb91c300cb88d0658b1b532ea371644897a20df94e3819ef46a9deacd8a8fa763fe39c343ff9dcbbc7c70b4f1d8a51e04bcdb45931c89f7ec9d9787364eac5ac8334d3ebc3c581a0fffa1363eb170ddd51b7f0da49d316552629d4689e2b16be587d47a1fc8ff8b8d17ad031ce45cb3a8f95160428afd7fbcabb4b407e">
memref.global "private" constant @sg_drv : memref<4xi8> = dense<"0x2e647276">
// queryPathInfo's keys: narHash narSize ref deriver ca, one blob with their offsets and lengths
memref.global "private" constant @sg_keys : memref<26xi8> = dense<"0x6e6172486173686e617253697a65726566646572697665726361">
memref.global "private" constant @sg_koff : memref<5xi8> = dense<[0, 7, 14, 17, 24]>
memref.global "private" constant @sg_klen : memref<5xi8> = dense<[7, 7, 3, 7, 2]>

func.func private @_ZNK8nixstore4HasheqERKS0_(!llvm.ptr, !llvm.ptr) -> i1
func.func private @nixstore_walk_room(!llvm.ptr, i64, i64) -> !llvm.ptr
func.func private @nixstore_walk_next(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixstore_walk_gone(!llvm.ptr, !llvm.ptr, i64)

//===----------------------------------------------------------------------===//
// Windows and tokens
//===----------------------------------------------------------------------===//

func.func private @sg_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// window i of an array of windows
func.func private @sg_win(%w: !llvm.ptr, %i: i64) -> (!llvm.ptr, i64) {
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %off = arith.muli %i, %c16 : i64
  %wp = llvm.getelementptr %w[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %wp : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %wp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n = llvm.load %np : !llvm.ptr -> i64
  return %p, %n : !llvm.ptr, i64
}

func.func private @sg_put(%w: !llvm.ptr, %i: i64, %p: !llvm.ptr, %n: i64) {
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %off = arith.muli %i, %c16 : i64
  %wp = llvm.getelementptr %w[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %p, %wp : !llvm.ptr, !llvm.ptr
  %np = llvm.getelementptr %wp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %n, %np : i64, !llvm.ptr
  return
}

// token i: (tag, a, b)
func.func private @sg_tok(%t: !llvm.ptr, %i: i64) -> (i64, i64, i64) {
  %c24 = arith.constant 24 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %off = arith.muli %i, %c24 : i64
  %tp = llvm.getelementptr %t[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tag = llvm.load %tp : !llvm.ptr -> i64
  %ap = llvm.getelementptr %tp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %a = llvm.load %ap : !llvm.ptr -> i64
  %bp = llvm.getelementptr %tp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %b = llvm.load %bp : !llvm.ptr -> i64
  return %tag, %a, %b : i64, i64, i64
}

// the byte order of two windows (Text's operator<: memcmp's sign, then the shorter first)
func.func private @sg_cmp(%ap: !llvm.ptr, %an: i64, %bp: !llvm.ptr, %bn: i64) -> i32 {
  %da = func.call @sg_desc(%ap, %an) : (!llvm.ptr, i64) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m
  %ta = builtin.unrealized_conversion_cast %ma : !m to !s
  %db = func.call @sg_desc(%bp, %bn) : (!llvm.ptr, i64) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m
  %tb = builtin.unrealized_conversion_cast %mb : !m to !s
  %c = trikeshed.compare %ta, %tb unsigned : !s, !s
  return %c : i32
}

// element e of a's windows then b's
func.func private @sg_pick(%a: !llvm.ptr, %na: i64, %b: !llvm.ptr, %e: i64) -> (!llvm.ptr, i64) {
  %ina = arith.cmpi slt, %e, %na : i64
  %eb = arith.subi %e, %na : i64
  %base = llvm.select %ina, %a, %b : i1, !llvm.ptr
  %i = arith.select %ina, %e, %eb : i64
  %p, %n = func.call @sg_win(%base, %i) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  return %p, %n : !llvm.ptr, i64
}

//===----------------------------------------------------------------------===//
// Set algebra
//===----------------------------------------------------------------------===//

// The sorted union of two sorted sets of distinct windows, a's window kept where both have one (writeDerivation's
// merge, drvReferences' set): the rows of both sorted (stable), then each row unlike the one before it.  The windows are
// written to out; the count is returned.
func.func @nixstore_ts_union(%a: !llvm.ptr, %na: i64, %b: !llvm.ptr, %nb: i64, %out: !llvm.ptr) -> i64 {
  %n = arith.addi %na, %nb : i64
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %xp, %xn = func.call @sg_pick(%a, %na, %b, %x) : (!llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %yp, %yn = func.call @sg_pick(%a, %na, %b, %y) : (!llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %c = func.call @sg_cmp(%xp, %xn, %yp, %yn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    trikeshed.yield %c : i32
  }
  %kept = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%k: i64):
    %z = arith.constant 0 : i64
    %first = arith.cmpi eq, %k, %z : i64
    %r = scf.if %first -> (i1) {
      %t = arith.constant 1 : i1
      scf.yield %t : i1
    } else {
      %one = arith.constant 1 : i64
      %km = arith.subi %k, %one : i64
      %kmi = arith.index_cast %km : i64 to index
      %ki = arith.index_cast %k : i64 to index
      %e1 = trikeshed.at %srt[%kmi] : !s64, index -> i64
      %e2 = trikeshed.at %srt[%ki] : !s64, index -> i64
      %p1, %n1 = func.call @sg_pick(%a, %na, %b, %e1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      %p2, %n2 = func.call @sg_pick(%a, %na, %b, %e2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      %c = func.call @sg_cmp(%p1, %n1, %p2, %n2) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      %c0 = arith.constant 0 : i32
      %ne = arith.cmpi ne, %c, %c0 : i32
      scf.yield %ne : i1
    }
    trikeshed.yield %r : i1
  }
  %m = trikeshed.size %kept : !s64
  %z0 = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  scf.for %j = %z0 to %m step %s1 {
    %k = trikeshed.at %kept[%j] : !s64, index -> i64
    %ki = arith.index_cast %k : i64 to index
    %e = trikeshed.at %srt[%ki] : !s64, index -> i64
    %p, %l = func.call @sg_pick(%a, %na, %b, %e) : (!llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %j64 = arith.index_cast %j : index to i64
    func.call @sg_put(%out, %j64, %p, %l) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  %m64 = arith.index_cast %m : index to i64
  return %m64 : i64
}

// A directory's names in byte order (NarWriter::dump's walk): order[j], a word, is the index of the j-th of the n windows at
// wins when the windows are put in the byte order of their text (trikeshed.sorted over the indices).  order has room for n words.
func.func @nixstore_ts_sortwins(%wins: !llvm.ptr, %n: i64, %order: !llvm.ptr) {
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %xp, %xn = func.call @sg_win(%wins, %x) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %yp, %yn = func.call @sg_win(%wins, %y) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %c = func.call @sg_cmp(%xp, %xn, %yp, %yn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    trikeshed.yield %c : i32
  }
  %z0 = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  %c8 = arith.constant 8 : i64
  scf.for %j = %z0 to %ni step %s1 {
    %e = trikeshed.at %srt[%j] : !s64, index -> i64
    %j64 = arith.index_cast %j : index to i64
    %off = arith.muli %j64, %c8 : i64
    %op = llvm.getelementptr %order[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %e, %op : i64, !llvm.ptr
  }
  return
}

//===----------------------------------------------------------------------===//
// XXH3-64 (llvm/lib/Support/xxhash.cpp, seed 0, the 192-byte default secret)
//===----------------------------------------------------------------------===//

// read64le / read32le: the bytes, each shifted to its place, or-ed (a fold over a series of the shifted bytes)
func.func private @sg_r64(%xs: !s, %k: index) -> i64 {
  %c8 = arith.constant 8 : index
  %w = trikeshed.series %c8 : !s64 {
  ^bb0(%i: index):
    %j = arith.addi %k, %i : index
    %b = trikeshed.at %xs[%j] : !s, index -> i8
    %b64 = arith.extui %b : i8 to i64
    %i64 = arith.index_cast %i : index to i64
    %e8 = arith.constant 8 : i64
    %sh = arith.muli %i64, %e8 : i64
    %v = arith.shli %b64, %sh : i64
    trikeshed.yield %v : i64
  }
  %z = arith.constant 0 : i64
  %r = trikeshed.fold %w, %z : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %o = arith.ori %acc, %x : i64
    trikeshed.yield %o : i64
  }
  return %r : i64
}

func.func private @sg_r32(%xs: !s, %k: index) -> i64 {
  %c4 = arith.constant 4 : index
  %w = trikeshed.series %c4 : !s64 {
  ^bb0(%i: index):
    %j = arith.addi %k, %i : index
    %b = trikeshed.at %xs[%j] : !s, index -> i8
    %b64 = arith.extui %b : i8 to i64
    %i64 = arith.index_cast %i : index to i64
    %e8 = arith.constant 8 : i64
    %sh = arith.muli %i64, %e8 : i64
    %v = arith.shli %b64, %sh : i64
    trikeshed.yield %v : i64
  }
  %z = arith.constant 0 : i64
  %r = trikeshed.fold %w, %z : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %o = arith.ori %acc, %x : i64
    trikeshed.yield %o : i64
  }
  return %r : i64
}

// the 128-bit product of two words, its halves xor-folded
func.func private @sg_fold64(%a: i64, %b: i64) -> i64 {
  %lo, %hi = arith.mului_extended %a, %b : i64
  %r = arith.xori %lo, %hi : i64
  return %r : i64
}

func.func private @sg_avl(%h: i64) -> i64 {
  %s37 = arith.constant 37 : i64
  %s32 = arith.constant 32 : i64
  %mx1 = arith.constant 1609587791953885689 : i64
  %a = arith.shrui %h, %s37 : i64
  %b = arith.xori %h, %a : i64
  %c = arith.muli %b, %mx1 : i64
  %d = arith.shrui %c, %s32 : i64
  %e = arith.xori %c, %d : i64
  return %e : i64
}

func.func private @sg_avl64(%h: i64) -> i64 {
  %s33 = arith.constant 33 : i64
  %s29 = arith.constant 29 : i64
  %s32 = arith.constant 32 : i64
  %p2 = arith.constant -4417276706812531889 : i64
  %p3 = arith.constant 1609587929392839161 : i64
  %a = arith.shrui %h, %s33 : i64
  %b = arith.xori %h, %a : i64
  %c = arith.muli %b, %p2 : i64
  %d = arith.shrui %c, %s29 : i64
  %e = arith.xori %c, %d : i64
  %f = arith.muli %e, %p3 : i64
  %g = arith.shrui %f, %s32 : i64
  %r = arith.xori %f, %g : i64
  return %r : i64
}

func.func private @sg_rotl(%x: i64, %r: i64) -> i64 {
  %c64 = arith.constant 64 : i64
  %a = arith.shli %x, %r : i64
  %rr = arith.subi %c64, %r : i64
  %b = arith.shrui %x, %rr : i64
  %c = arith.ori %a, %b : i64
  return %c : i64
}

// XXH3_mix16B with seed 0: input[k..k+16) against secret[sk..sk+16)
func.func private @sg_mix16(%xs: !s, %k: index, %sec: !s, %sk: index) -> i64 {
  %c8 = arith.constant 8 : index
  %k8 = arith.addi %k, %c8 : index
  %sk8 = arith.addi %sk, %c8 : index
  %s0 = func.call @sg_r64(%sec, %sk) : (!s, index) -> i64
  %s1 = func.call @sg_r64(%sec, %sk8) : (!s, index) -> i64
  %i0 = func.call @sg_r64(%xs, %k) : (!s, index) -> i64
  %i1 = func.call @sg_r64(%xs, %k8) : (!s, index) -> i64
  %lhs = arith.xori %s0, %i0 : i64
  %rhs = arith.xori %s1, %i1 : i64
  %r = func.call @sg_fold64(%lhs, %rhs) : (i64, i64) -> i64
  return %r : i64
}

// XXH3_accumulate_512 of the stripe at input[off..off+64) with secret[soff..)
func.func private @sg_acc512(%acc: memref<8xi64>, %xs: !s, %off: index, %sec: !s, %soff: index) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  scf.for %i = %z to %c8 step %one {
    %i8 = arith.muli %i, %c8 : index
    %xo = arith.addi %off, %i8 : index
    %so = arith.addi %soff, %i8 : index
    %dv = func.call @sg_r64(%xs, %xo) : (!s, index) -> i64
    %sv = func.call @sg_r64(%sec, %so) : (!s, index) -> i64
    %dk = arith.xori %dv, %sv : i64
    %ix = arith.xori %i, %one : index
    %a1 = memref.load %acc[%ix] : memref<8xi64>
    %a1n = arith.addi %a1, %dv : i64
    memref.store %a1n, %acc[%ix] : memref<8xi64>
    %mask = arith.constant 4294967295 : i64
    %s32 = arith.constant 32 : i64
    %lo = arith.andi %dk, %mask : i64
    %hi = arith.shrui %dk, %s32 : i64
    %pr = arith.muli %lo, %hi : i64
    %a0 = memref.load %acc[%i] : memref<8xi64>
    %a0n = arith.addi %a0, %pr : i64
    memref.store %a0n, %acc[%i] : memref<8xi64>
  }
  return
}

func.func private @sg_scramble(%acc: memref<8xi64>, %sec: !s, %soff: index) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c8 = arith.constant 8 : index
  %s47 = arith.constant 47 : i64
  %p1 = arith.constant 2654435761 : i64
  scf.for %i = %z to %c8 step %one {
    %a = memref.load %acc[%i] : memref<8xi64>
    %sh = arith.shrui %a, %s47 : i64
    %b = arith.xori %a, %sh : i64
    %i8 = arith.muli %i, %c8 : index
    %so = arith.addi %soff, %i8 : index
    %sv = func.call @sg_r64(%sec, %so) : (!s, index) -> i64
    %c = arith.xori %b, %sv : i64
    %e = arith.muli %c, %p1 : i64
    memref.store %e, %acc[%i] : memref<8xi64>
  }
  return
}

func.func private @sg_long(%xs: !s, %len: index, %sec: !s) -> i64 {
  %acc = memref.alloca() : memref<8xi64>
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i7 = arith.constant 7 : index
  %p32_1 = arith.constant 2654435761 : i64
  %p32_2 = arith.constant 2246822519 : i64
  %p32_3 = arith.constant 3266489917 : i64
  %p64_1 = arith.constant -7046029288634856825 : i64
  %p64_2 = arith.constant -4417276706812531889 : i64
  %p64_3 = arith.constant 1609587929392839161 : i64
  %p64_4 = arith.constant -8796714831421723037 : i64
  %p64_5 = arith.constant 2870177450012600261 : i64
  memref.store %p32_3, %acc[%z] : memref<8xi64>
  memref.store %p64_1, %acc[%one] : memref<8xi64>
  memref.store %p64_2, %acc[%i2] : memref<8xi64>
  memref.store %p64_3, %acc[%i3] : memref<8xi64>
  memref.store %p64_4, %acc[%i4] : memref<8xi64>
  memref.store %p32_2, %acc[%i5] : memref<8xi64>
  memref.store %p64_5, %acc[%i6] : memref<8xi64>
  memref.store %p32_1, %acc[%i7] : memref<8xi64>
  // 16 stripes a block of 1024 bytes (secret 192: (192 - 64) / 8)
  %blk = arith.constant 1024 : index
  %c64 = arith.constant 64 : index
  %c8 = arith.constant 8 : index
  %c16 = arith.constant 16 : index
  %c128 = arith.constant 128 : index
  %lm1 = arith.subi %len, %one : index
  %nb = arith.divui %lm1, %blk : index
  scf.for %bn = %z to %nb step %one {
    %base = arith.muli %bn, %blk : index
    scf.for %st = %z to %c16 step %one {
      %so = arith.muli %st, %c8 : index
      %xo0 = arith.muli %st, %c64 : index
      %xo = arith.addi %base, %xo0 : index
      func.call @sg_acc512(%acc, %xs, %xo, %sec, %so) : (memref<8xi64>, !s, index, !s, index) -> ()
    }
    func.call @sg_scramble(%acc, %sec, %c128) : (memref<8xi64>, !s, index) -> ()
  }
  %done = arith.muli %nb, %blk : index
  %rest = arith.subi %lm1, %done : index
  %nst = arith.divui %rest, %c64 : index
  scf.for %st = %z to %nst step %one {
    %so = arith.muli %st, %c8 : index
    %xo0 = arith.muli %st, %c64 : index
    %xo = arith.addi %done, %xo0 : index
    func.call @sg_acc512(%acc, %xs, %xo, %sec, %so) : (memref<8xi64>, !s, index, !s, index) -> ()
  }
  %last = arith.subi %len, %c64 : index
  %c121 = arith.constant 121 : index
  func.call @sg_acc512(%acc, %xs, %last, %sec, %c121) : (memref<8xi64>, !s, index, !s, index) -> ()
  // mergeAccs(acc, secret + 11, len * PRIME64_1)
  %len64 = arith.index_cast %len : index to i64
  %start = arith.muli %len64, %p64_1 : i64
  %c11 = arith.constant 11 : index
  %c4 = arith.constant 4 : index
  %sum = scf.for %i = %z to %c4 step %one iter_args(%r = %start) -> (i64) {
    %i2x = arith.muli %i, %i2 : index
    %i2y = arith.addi %i2x, %one : index
    %a0 = memref.load %acc[%i2x] : memref<8xi64>
    %a1 = memref.load %acc[%i2y] : memref<8xi64>
    %i16 = arith.muli %i, %c16 : index
    %ko = arith.addi %c11, %i16 : index
    %ko8 = arith.addi %ko, %c8 : index
    %k0 = func.call @sg_r64(%sec, %ko) : (!s, index) -> i64
    %k1 = func.call @sg_r64(%sec, %ko8) : (!s, index) -> i64
    %x0 = arith.xori %a0, %k0 : i64
    %x1 = arith.xori %a1, %k1 : i64
    %f = func.call @sg_fold64(%x0, %x1) : (i64, i64) -> i64
    %rn = arith.addi %r, %f : i64
    scf.yield %rn : i64
  }
  %h = func.call @sg_avl(%sum) : (i64) -> i64
  return %h : i64
}

func.func private @sg_xxh3(%xs: !s) -> i64 {
  %sg = memref.get_global @sg_secret : memref<192xi8>
  %sec = trikeshed.text %sg : memref<192xi8> -> !s
  %len = trikeshed.size %xs : !s
  %len64 = arith.index_cast %len : index to i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c4 = arith.constant 4 : index
  %c8 = arith.constant 8 : index
  %c16 = arith.constant 16 : index
  %c32 = arith.constant 32 : index
  %c128 = arith.constant 128 : index
  %c240 = arith.constant 240 : index
  %p64_1 = arith.constant -7046029288634856825 : i64
  %mx2 = arith.constant -6939452855193903323 : i64
  %le16 = arith.cmpi ule, %len, %c16 : index
  %h = scf.if %le16 -> (i64) {
    %gt8 = arith.cmpi ugt, %len, %c8 : index
    %h0 = scf.if %gt8 -> (i64) {
      // 9 to 16
      %c24 = arith.constant 24 : index
      %c40 = arith.constant 40 : index
      %c48 = arith.constant 48 : index
      %s24 = func.call @sg_r64(%sec, %c24) : (!s, index) -> i64
      %s32 = func.call @sg_r64(%sec, %c32) : (!s, index) -> i64
      %s40 = func.call @sg_r64(%sec, %c40) : (!s, index) -> i64
      %s48 = func.call @sg_r64(%sec, %c48) : (!s, index) -> i64
      %lo0 = arith.xori %s24, %s32 : i64
      %hi0 = arith.xori %s40, %s48 : i64
      %in0 = func.call @sg_r64(%xs, %z) : (!s, index) -> i64
      %lm8 = arith.subi %len, %c8 : index
      %in1 = func.call @sg_r64(%xs, %lm8) : (!s, index) -> i64
      %lo = arith.xori %lo0, %in0 : i64
      %hi = arith.xori %hi0, %in1 : i64
      %sw = "llvm.intr.bswap"(%lo) : (i64) -> i64
      %f = func.call @sg_fold64(%lo, %hi) : (i64, i64) -> i64
      %a1 = arith.addi %len64, %sw : i64
      %a2 = arith.addi %a1, %hi : i64
      %a3 = arith.addi %a2, %f : i64
      %r = func.call @sg_avl(%a3) : (i64) -> i64
      scf.yield %r : i64
    } else {
      %ge4 = arith.cmpi uge, %len, %c4 : index
      %h1 = scf.if %ge4 -> (i64) {
        // 4 to 8
        %in1 = func.call @sg_r32(%xs, %z) : (!s, index) -> i64
        %lm4 = arith.subi %len, %c4 : index
        %in2 = func.call @sg_r32(%xs, %lm4) : (!s, index) -> i64
        %c16b = arith.constant 16 : index
        %s8 = func.call @sg_r64(%sec, %c8) : (!s, index) -> i64
        %s16 = func.call @sg_r64(%sec, %c16b) : (!s, index) -> i64
        %acc0 = arith.xori %s8, %s16 : i64
        %w32 = arith.constant 32 : i64
        %i1s = arith.shli %in1, %w32 : i64
        %in64 = arith.ori %in2, %i1s : i64
        %acc1 = arith.xori %acc0, %in64 : i64
        %w49 = arith.constant 49 : i64
        %w24 = arith.constant 24 : i64
        %r49 = func.call @sg_rotl(%acc1, %w49) : (i64, i64) -> i64
        %r24 = func.call @sg_rotl(%acc1, %w24) : (i64, i64) -> i64
        %rx = arith.xori %r49, %r24 : i64
        %acc2 = arith.xori %acc1, %rx : i64
        %acc3 = arith.muli %acc2, %mx2 : i64
        %w35 = arith.constant 35 : i64
        %sh35 = arith.shrui %acc3, %w35 : i64
        %pl = arith.addi %sh35, %len64 : i64
        %acc4 = arith.xori %acc3, %pl : i64
        %acc5 = arith.muli %acc4, %mx2 : i64
        %w28 = arith.constant 28 : i64
        %sh28 = arith.shrui %acc5, %w28 : i64
        %r = arith.xori %acc5, %sh28 : i64
        scf.yield %r : i64
      } else {
        %ne0 = arith.cmpi ne, %len, %z : index
        %h2 = scf.if %ne0 -> (i64) {
          // 1 to 3
          %b1 = trikeshed.at %xs[%z] : !s, index -> i8
          %half = arith.shrui %len, %one : index
          %b2 = trikeshed.at %xs[%half] : !s, index -> i8
          %lm1 = arith.subi %len, %one : index
          %b3 = trikeshed.at %xs[%lm1] : !s, index -> i8
          %c1 = arith.extui %b1 : i8 to i64
          %c2 = arith.extui %b2 : i8 to i64
          %c3 = arith.extui %b3 : i8 to i64
          %w16 = arith.constant 16 : i64
          %w24 = arith.constant 24 : i64
          %w8 = arith.constant 8 : i64
          %x1 = arith.shli %c1, %w16 : i64
          %x2 = arith.shli %c2, %w24 : i64
          %x4 = arith.shli %len64, %w8 : i64
          %o1 = arith.ori %x1, %x2 : i64
          %o2 = arith.ori %o1, %c3 : i64
          %comb = arith.ori %o2, %x4 : i64
          %s0 = func.call @sg_r32(%sec, %z) : (!s, index) -> i64
          %s4 = func.call @sg_r32(%sec, %c4) : (!s, index) -> i64
          %flip = arith.xori %s0, %s4 : i64
          %v = arith.xori %comb, %flip : i64
          %r = func.call @sg_avl64(%v) : (i64) -> i64
          scf.yield %r : i64
        } else {
          %c56 = arith.constant 56 : index
          %c64 = arith.constant 64 : index
          %s56 = func.call @sg_r64(%sec, %c56) : (!s, index) -> i64
          %s64 = func.call @sg_r64(%sec, %c64) : (!s, index) -> i64
          %v = arith.xori %s56, %s64 : i64
          %r = func.call @sg_avl64(%v) : (i64) -> i64
          scf.yield %r : i64
        }
        scf.yield %h2 : i64
      }
      scf.yield %h1 : i64
    }
    scf.yield %h0 : i64
  } else {
    %le128 = arith.cmpi ule, %len, %c128 : index
    %h3 = scf.if %le128 -> (i64) {
      // 17 to 128: rounds r of (16r, 32r) and (len - 16(r+1), 32r + 16), one more past each of 32, 64, 96
      %c64 = arith.constant 64 : index
      %c96 = arith.constant 96 : index
      %g32 = arith.cmpi ugt, %len, %c32 : index
      %g64 = arith.cmpi ugt, %len, %c64 : index
      %g96 = arith.cmpi ugt, %len, %c96 : index
      %n1 = arith.select %g32, %one, %z : index
      %n2 = arith.select %g64, %one, %z : index
      %n3 = arith.select %g96, %one, %z : index
      %na = arith.addi %one, %n1 : index
      %nb = arith.addi %na, %n2 : index
      %nr = arith.addi %nb, %n3 : index
      %acc0 = arith.muli %len64, %p64_1 : i64
      %zero64 = arith.constant 0 : i64
      %ae:2 = scf.for %rr = %z to %nr step %one iter_args(%acc = %acc0, %end = %zero64) -> (i64, i64) {
        %x0 = arith.muli %rr, %c16 : index
        %s0 = arith.muli %rr, %c32 : index
        %r1 = arith.addi %rr, %one : index
        %x1b = arith.muli %r1, %c16 : index
        %x1 = arith.subi %len, %x1b : index
        %s1 = arith.addi %s0, %c16 : index
        %m0 = func.call @sg_mix16(%xs, %x0, %sec, %s0) : (!s, index, !s, index) -> i64
        %m1 = func.call @sg_mix16(%xs, %x1, %sec, %s1) : (!s, index, !s, index) -> i64
        %accn = arith.addi %acc, %m0 : i64
        %endn = arith.addi %end, %m1 : i64
        scf.yield %accn, %endn : i64, i64
      }
      %t = arith.addi %ae#0, %ae#1 : i64
      %r = func.call @sg_avl(%t) : (i64) -> i64
      scf.yield %r : i64
    } else {
      %le240 = arith.cmpi ule, %len, %c240 : index
      %h4 = scf.if %le240 -> (i64) {
        // 129 to 240
        %acc0 = arith.muli %len64, %p64_1 : i64
        %acc1 = scf.for %i = %z to %c8 step %one iter_args(%acc = %acc0) -> (i64) {
          %o = arith.muli %i, %c16 : index
          %m = func.call @sg_mix16(%xs, %o, %sec, %o) : (!s, index, !s, index) -> i64
          %an = arith.addi %acc, %m : i64
          scf.yield %an : i64
        }
        %acc2 = func.call @sg_avl(%acc1) : (i64) -> i64
        %nbr = arith.divui %len, %c16 : index
        %c3 = arith.constant 3 : index
        %acc3 = scf.for %i = %c8 to %nbr step %one iter_args(%acc = %acc2) -> (i64) {
          %o = arith.muli %i, %c16 : index
          %im8 = arith.subi %i, %c8 : index
          %so0 = arith.muli %im8, %c16 : index
          %so = arith.addi %so0, %c3 : index
          %m = func.call @sg_mix16(%xs, %o, %sec, %so) : (!s, index, !s, index) -> i64
          %an = arith.addi %acc, %m : i64
          scf.yield %an : i64
        }
        %lm16 = arith.subi %len, %c16 : index
        %c119 = arith.constant 119 : index
        %ml = func.call @sg_mix16(%xs, %lm16, %sec, %c119) : (!s, index, !s, index) -> i64
        %acc4 = arith.addi %acc3, %ml : i64
        %r = func.call @sg_avl(%acc4) : (i64) -> i64
        scf.yield %r : i64
      } else {
        %r = func.call @sg_long(%xs, %len, %sec) : (!s, index, !s) -> i64
        scf.yield %r : i64
      }
      scf.yield %h4 : i64
    }
    scf.yield %h3 : i64
  }
  return %h : i64
}

func.func @nixstore_ts_xxh3(%p: !llvm.ptr, %n: i64) -> i64 {
  %d = func.call @sg_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %t = builtin.unrealized_conversion_cast %mm : !m to !s
  %h = func.call @sg_xxh3(%t) : (!s) -> i64
  return %h : i64
}

//===----------------------------------------------------------------------===//
// Derivation content: the fingerprint and the compare
//===----------------------------------------------------------------------===//

// contentFingerprint: h = 0; each word w (a string's xxh3) mixed in as h = (h ^ w) * 0x9e3779b97f4a7c15, h ^= h >> 29
func.func @nixstore_ts_fingerprint(%t: !llvm.ptr, %n: i64) -> i64 {
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %zero = arith.constant 0 : i64
  %h = trikeshed.fold %idx, %zero : !s64, i64 -> i64 {
  ^bb0(%h0: i64, %i: i64):
    %tag, %a, %b = func.call @sg_tok(%t, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %k0 = arith.constant 0 : i64
    %k1 = arith.constant 1 : i64
    %k4 = arith.constant 4 : i64
    %k5 = arith.constant 5 : i64
    %k6 = arith.constant 6 : i64
    %k7 = arith.constant 7 : i64
    %w0 = arith.cmpi eq, %tag, %k0 : i64
    %w4 = arith.cmpi eq, %tag, %k4 : i64
    %w7 = arith.cmpi eq, %tag, %k7 : i64
    %s1 = arith.cmpi eq, %tag, %k1 : i64
    %s5 = arith.cmpi eq, %tag, %k5 : i64
    %s6 = arith.cmpi eq, %tag, %k6 : i64
    %wa = arith.ori %w0, %w4 : i1
    %isw = arith.ori %wa, %w7 : i1
    %sa = arith.ori %s1, %s5 : i1
    %iss = arith.ori %sa, %s6 : i1
    %w = scf.if %iss -> (i64) {
      %p = llvm.inttoptr %a : i64 to !llvm.ptr
      %x = func.call @nixstore_ts_xxh3(%p, %b) : (!llvm.ptr, i64) -> i64
      scf.yield %x : i64
    } else {
      scf.yield %a : i64
    }
    %gold = arith.constant -7046029254386353131 : i64
    %s29 = arith.constant 29 : i64
    %x1 = arith.xori %h0, %w : i64
    %x2 = arith.muli %x1, %gold : i64
    %x3 = arith.shrui %x2, %s29 : i64
    %x4 = arith.xori %x2, %x3 : i64
    %fp = arith.ori %isw, %iss : i1
    %r = arith.select %fp, %x4, %h0 : i64
    trikeshed.yield %r : i64
  }
  return %h : i64
}

// whether x's outputs (of: the first output's token, om of them, six tokens each, sorted by name) hold the key as a
// Deferred output (kind 3): the outputs bisected by name
func.func private @sg_deferred(%x: !llvm.ptr, %of: i64, %om: i64, %kp: !llvm.ptr, %kn: i64) -> i1 {
  %omi = arith.index_cast %om : i64 to index
  %idx = trikeshed.series %omi : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %c6 = arith.constant 6 : i64
  %zero = arith.constant 0 : i64
  %j = trikeshed.bisect %idx, %zero : !s64, i64 -> index by {
  ^bb0(%e: i64, %key: i64):
    %e6 = arith.muli %e, %c6 : i64
    %ti = arith.addi %of, %e6 : i64
    %tg, %ta, %tb = func.call @sg_tok(%x, %ti) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %tptr = llvm.inttoptr %ta : i64 to !llvm.ptr
    %c = func.call @sg_cmp(%tptr, %tb, %kp, %kn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
    trikeshed.yield %c : i32
  }
  %z = arith.constant 0 : index
  %found = arith.cmpi sge, %j, %z : index
  %r = scf.if %found -> (i1) {
    %j64 = arith.index_cast %j : index to i64
    %j6 = arith.muli %j64, %c6 : i64
    %t0 = arith.addi %of, %j6 : i64
    %one = arith.constant 1 : i64
    %kt = arith.addi %t0, %one : i64
    %g, %ka, %kb = func.call @sg_tok(%x, %kt) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %three = arith.constant 3 : i64
    %d = arith.cmpi eq, %ka, %three : i64
    scf.yield %d : i1
  } else {
    %f = arith.constant 0 : i1
    scf.yield %f : i1
  }
  return %r : i1
}

func.func private @sg_streq(%ap: i64, %an: i64, %bp: i64, %bn: i64) -> i1 {
  %pa = llvm.inttoptr %ap : i64 to !llvm.ptr
  %pb = llvm.inttoptr %bp : i64 to !llvm.ptr
  %c = func.call @sg_cmp(%pa, %an, %pb, %bn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
  %z = arith.constant 0 : i32
  %e = arith.cmpi eq, %c, %z : i32
  return %e : i1
}

// sameContent(n = x, c = y): the two token streams in step.  Until a word differs they have one structure, so token i of
// each plays the same part.  A Deferred output of x (kind 3) matches an InputAddressed one (kind 0) of y, and its path,
// method, algorithm and hash are not compared (the next four tokens); an env value of x may differ from y's only when it
// is empty and its key names a Deferred output of x.  Everything else is compared exactly: 1 when equal, else 0.
func.func @nixstore_ts_samecontent(%x: !llvm.ptr, %nx: i64, %y: !llvm.ptr, %ny: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %t1 = arith.constant 1 : i1
  %w:5 = scf.while (%i = %c0, %skip = %c0, %of = %c0, %om = %c0, %ok = %t1) : (i64, i64, i64, i64, i1) -> (i64, i64, i64, i64, i1) {
    %inx = arith.cmpi slt, %i, %nx : i64
    %iny = arith.cmpi slt, %i, %ny : i64
    %in = arith.andi %inx, %iny : i1
    %go = arith.andi %in, %ok : i1
    scf.condition(%go) %i, %skip, %of, %om, %ok : i64, i64, i64, i64, i1
  } do {
  ^bb0(%i: i64, %skip: i64, %of: i64, %om: i64, %ok: i1):
    %xt, %xa, %xb = func.call @sg_tok(%x, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %yt, %ya, %yb = func.call @sg_tok(%y, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %three = arith.constant 3 : i64
    %four = arith.constant 4 : i64
    %six = arith.constant 6 : i64
    %seven = arith.constant 7 : i64
    %inskip = arith.cmpi sgt, %skip, %zero : i64
    %st:4 = scf.if %inskip -> (i64, i64, i64, i1) {
      %sk1 = arith.subi %skip, %one : i64
      %tt = arith.constant 1 : i1
      scf.yield %sk1, %of, %om, %tt : i64, i64, i64, i1
    } else {
      %tageq = arith.cmpi eq, %xt, %yt : i64
      %weq = arith.cmpi eq, %xa, %ya : i64
      %is0 = arith.cmpi eq, %xt, %zero : i64
      %is1 = arith.cmpi eq, %xt, %one : i64
      %is2 = arith.cmpi eq, %xt, %two : i64
      %is3 = arith.cmpi eq, %xt, %three : i64
      %is4 = arith.cmpi eq, %xt, %four : i64
      %is6 = arith.cmpi eq, %xt, %six : i64
      %is7 = arith.cmpi eq, %xt, %seven : i64
      %w02 = arith.ori %is0, %is2 : i1
      %isword = arith.ori %w02, %is7 : i1
      %isstr = arith.ori %is1, %is6 : i1
      %eq = scf.if %isword -> (i1) {
        scf.yield %weq : i1
      } else {
        %e1 = scf.if %isstr -> (i1) {
          %se = func.call @sg_streq(%xa, %xb, %ya, %yb) : (i64, i64, i64, i64) -> i1
          scf.yield %se : i1
        } else {
          %e2 = scf.if %is3 -> (i1) {
            %hx = llvm.inttoptr %xa : i64 to !llvm.ptr
            %hy = llvm.inttoptr %ya : i64 to !llvm.ptr
            %he = func.call @_ZNK8nixstore4HasheqERKS0_(%hx, %hy) : (!llvm.ptr, !llvm.ptr) -> i1
            scf.yield %he : i1
          } else {
            %e3 = scf.if %is4 -> (i1) {
              %xdef = arith.cmpi eq, %xa, %three : i64
              %yia = arith.cmpi eq, %ya, %zero : i64
              %ke = arith.select %xdef, %yia, %weq : i1
              scf.yield %ke : i1
            } else {
              // an env value
              %ve = func.call @sg_streq(%xa, %xb, %ya, %yb) : (i64, i64, i64, i64) -> i1
              %e4 = scf.if %ve -> (i1) {
                scf.yield %ve : i1
              } else {
                %empty = arith.cmpi eq, %xb, %zero : i64
                %e5 = scf.if %empty -> (i1) {
                  %ki = arith.subi %i, %one : i64
                  %kg, %kpa, %kn = func.call @sg_tok(%x, %ki) : (!llvm.ptr, i64) -> (i64, i64, i64)
                  %kp = llvm.inttoptr %kpa : i64 to !llvm.ptr
                  %df = func.call @sg_deferred(%x, %of, %om, %kp, %kn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i1
                  scf.yield %df : i1
                } else {
                  %ff = arith.constant 0 : i1
                  scf.yield %ff : i1
                }
                scf.yield %e5 : i1
              }
              scf.yield %e4 : i1
            }
            scf.yield %e3 : i1
          }
          scf.yield %e2 : i1
        }
        scf.yield %e1 : i1
      }
      %xdef2 = arith.cmpi eq, %xa, %three : i64
      %lenient = arith.andi %is4, %xdef2 : i1
      %sk2 = arith.select %lenient, %four, %zero : i64
      %i1 = arith.addi %i, %one : i64
      %of2 = arith.select %is7, %i1, %of : i64
      %om2 = arith.select %is7, %xa, %om : i64
      %ok2 = arith.andi %tageq, %eq : i1
      scf.yield %sk2, %of2, %om2, %ok2 : i64, i64, i64, i1
    }
    %inext = arith.addi %i, %one : i64
    scf.yield %inext, %st#0, %st#1, %st#2, %st#3 : i64, i64, i64, i64, i1
  }
  %same = arith.cmpi eq, %nx, %ny : i64
  %r = arith.andi %w#4, %same : i1
  %r64 = arith.extui %r : i1 to i64
  return %r64 : i64
}

//===----------------------------------------------------------------------===//
// The store's graph
//===----------------------------------------------------------------------===//

// a frame pushed when it has windows: room 1 holds the frames, each a window (base of a window array, count left)
func.func private @sg_push(%ctx: !llvm.ptr, %fr: !llvm.ptr, %nf: i64, %rp: !llvm.ptr, %rc: i64) -> (i64, !llvm.ptr) {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %has = arith.cmpi sgt, %rc, %zero : i64
  %r:2 = scf.if %has -> (i64, !llvm.ptr) {
    %nf1 = arith.addi %nf, %one : i64
    %fr2 = func.call @nixstore_walk_room(%ctx, %one, %nf1) : (!llvm.ptr, i64, i64) -> !llvm.ptr
    func.call @sg_put(%fr2, %nf, %rp, %rc) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
    scf.yield %nf1, %fr2 : i64, !llvm.ptr
  } else {
    scf.yield %nf, %fr : i64, !llvm.ptr
  }
  return %r#0, %r#1 : i64, !llvm.ptr
}

// whether the window ends in ".drv" past a first byte (p.size() > 4)
func.func private @sg_isdrv(%p: !llvm.ptr, %n: i64) -> i1 {
  %four = arith.constant 4 : i64
  %long = arith.cmpi sgt, %n, %four : i64
  %r = scf.if %long -> (i1) {
    %d = func.call @sg_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %mm = builtin.unrealized_conversion_cast %d : !d to !m
    %t = builtin.unrealized_conversion_cast %mm : !m to !s
    %ni = arith.index_cast %n : i64 to index
    %c4 = arith.constant 4 : index
    %at = arith.subi %ni, %c4 : index
    %tail = trikeshed.slice %t[%at, %c4] : !s -> !s
    %g = memref.get_global @sg_drv : memref<4xi8>
    %drv = trikeshed.text %g : memref<4xi8> -> !s
    %c = trikeshed.compare %tail, %drv unsigned : !s, !s
    %z = arith.constant 0 : i32
    %e = arith.cmpi eq, %c, %z : i32
    scf.yield %e : i1
  } else {
    %f = arith.constant 0 : i1
    scf.yield %f : i1
  }
  return %r : i1
}

// computeFSClosure: the paths still to visit are a stack of frames (a window array and how many of it are left, the last
// taken first: the old worklist's pops), the visited set is room 0's windows kept sorted (bisect, then the rows after
// the place move up one: SortedSet::insert).  A path seen for the first time is inserted, then its references
// (nixstore_walk_next 0: its info's references, else a cached derivation's) are pushed, then, with includeOutputs and a
// path ending in ".drv", its valid outputs (nixstore_walk_next 1).  Answers the visited count; room 0 holds them sorted.
func.func @nixstore_ts_closure(%ctx: !llvm.ptr, %seeds: !llvm.ptr, %ns: i64, %outs: i64) -> i64 {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %cnt = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
  %fr0 = func.call @nixstore_walk_room(%ctx, %one, %one) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  func.call @sg_put(%fr0, %zero, %seeds, %ns) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  %some = arith.cmpi sgt, %ns, %zero : i64
  %nf0 = arith.select %some, %one, %zero : i64
  %vis0 = func.call @nixstore_walk_room(%ctx, %zero, %one) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %wantOuts = arith.cmpi ne, %outs, %zero : i64
  %r:4 = scf.while (%nv = %zero, %nf = %nf0, %vis = %vis0, %fr = %fr0) : (i64, i64, !llvm.ptr, !llvm.ptr) -> (i64, i64, !llvm.ptr, !llvm.ptr) {
    %more = arith.cmpi sgt, %nf, %zero : i64
    scf.condition(%more) %nv, %nf, %vis, %fr : i64, i64, !llvm.ptr, !llvm.ptr
  } do {
  ^bb0(%nv: i64, %nf: i64, %vis: !llvm.ptr, %fr: !llvm.ptr):
    %top = arith.subi %nf, %one : i64
    %base, %rem = func.call @sg_win(%fr, %top) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %rem1 = arith.subi %rem, %one : i64
    func.call @sg_put(%fr, %top, %base, %rem1) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
    %out = arith.cmpi eq, %rem1, %zero : i64
    %nf1 = arith.select %out, %top, %nf : i64
    %p, %n = func.call @sg_win(%base, %rem1) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %nvi = arith.index_cast %nv : i64 to index
    %vs = trikeshed.series %nvi : !s64 {
    ^bb0(%i: index):
      %i64 = arith.index_cast %i : index to i64
      trikeshed.yield %i64 : i64
    }
    %pos = trikeshed.bisect %vs, %zero : !s64, i64 -> index by {
    ^bb0(%e: i64, %key: i64):
      %vp, %vn = func.call @sg_win(%vis, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %c = func.call @sg_cmp(%vp, %vn, %p, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      trikeshed.yield %c : i32
    }
    %iz = arith.constant 0 : index
    %found = arith.cmpi sge, %pos, %iz : index
    %res:4 = scf.if %found -> (i64, i64, !llvm.ptr, !llvm.ptr) {
      scf.yield %nv, %nf1, %vis, %fr : i64, i64, !llvm.ptr, !llvm.ptr
    } else {
      %pos64 = arith.index_cast %pos : index to i64
      %m1 = arith.constant -1 : i64
      %ins = arith.subi %m1, %pos64 : i64
      %nv1 = arith.addi %nv, %one : i64
      %vis2 = func.call @nixstore_walk_room(%ctx, %zero, %nv1) : (!llvm.ptr, i64, i64) -> !llvm.ptr
      %moves = arith.subi %nv, %ins : i64
      %mvi = arith.index_cast %moves : i64 to index
      %s1 = arith.constant 1 : index
      scf.for %j = %iz to %mvi step %s1 {
        %j64 = arith.index_cast %j : index to i64
        %k = arith.subi %nv, %j64 : i64
        %km = arith.subi %k, %one : i64
        %qp, %ql = func.call @sg_win(%vis2, %km) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        func.call @sg_put(%vis2, %k, %qp, %ql) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
      }
      func.call @sg_put(%vis2, %ins, %p, %n) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
      %rp = func.call @nixstore_walk_next(%ctx, %p, %n, %zero, %cnt) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
      %rc = llvm.load %cnt : !llvm.ptr -> i64
      %pa:2 = func.call @sg_push(%ctx, %fr, %nf1, %rp, %rc) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> (i64, !llvm.ptr)
      %isdrv = func.call @sg_isdrv(%p, %n) : (!llvm.ptr, i64) -> i1
      %drvOuts = arith.andi %wantOuts, %isdrv : i1
      %pb:2 = scf.if %drvOuts -> (i64, !llvm.ptr) {
        %op = func.call @nixstore_walk_next(%ctx, %p, %n, %one, %cnt) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
        %oc = llvm.load %cnt : !llvm.ptr -> i64
        %pc:2 = func.call @sg_push(%ctx, %pa#1, %pa#0, %op, %oc) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> (i64, !llvm.ptr)
        scf.yield %pc#0, %pc#1 : i64, !llvm.ptr
      } else {
        scf.yield %pa#0, %pa#1 : i64, !llvm.ptr
      }
      scf.yield %nv1, %pb#0, %vis2, %pb#1 : i64, i64, !llvm.ptr, !llvm.ptr
    }
    scf.yield %res#0, %res#1, %res#2, %res#3 : i64, i64, !llvm.ptr, !llvm.ptr
  }
  return %r#0 : i64
}

// collectGarbage after the roots: the dead paths are the valid ones the live set lacks (where, each bisected into live),
// both sorted.  Then rounds until one deletes nothing or none is left: each dead path not yet deleted, in order, is
// deleted (nixstore_walk_gone) unless another one not deleted holds it among its references (nixstore_walk_next 2: q's info's
// sorted references, read once and kept in %refs, bisected), the search stopping at the first that does.  A path deleted this round no longer counts as a
// referrer, nor one deleted before (it is not among the remaining), so one mark a path serves every round.
func.func @nixstore_ts_gc(%ctx: !llvm.ptr, %valid: !llvm.ptr, %nvalid: i64, %live: !llvm.ptr, %nlive: i64) -> i64 {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %nvi = arith.index_cast %nvalid : i64 to index
  %nli = arith.index_cast %nlive : i64 to index
  %idx = trikeshed.series %nvi : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %lidx = trikeshed.series %nli : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %dead = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%v: i64):
    %vp, %vn = func.call @sg_win(%valid, %v) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %j = trikeshed.bisect %lidx, %zero : !s64, i64 -> index by {
    ^bb0(%e: i64, %key: i64):
      %lp, %ln = func.call @sg_win(%live, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      %c = func.call @sg_cmp(%lp, %ln, %vp, %vn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
      trikeshed.yield %c : i32
    }
    %iz = arith.constant 0 : index
    %absent = arith.cmpi slt, %j, %iz : index
    trikeshed.yield %absent : i1
  }
  %nd = trikeshed.size %dead : !s64
  %z = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  %mark = memref.alloc(%nd) : memref<?xi8>
  %i2 = arith.constant 2 : index
  %two = arith.constant 2 : i64
  %m1 = arith.constant -1 : i64
  %nd2 = arith.muli %nd, %i2 : index
  %refs = memref.alloc(%nd2) : memref<?xi64>
  %b0 = arith.constant 0 : i8
  %b1 = arith.constant 1 : i8
  scf.for %i = %z to %nd step %s1 {
    memref.store %b0, %mark[%i] : memref<?xi8>
    %i2i = arith.muli %i, %i2 : index
    memref.store %m1, %refs[%i2i] : memref<?xi64>
  }
  %cnt = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
  %t1 = arith.constant 1 : i1
  %f0 = arith.constant 0 : i1
  %w:2 = scf.while (%prog = %t1, %left = %nd) : (i1, index) -> (i1, index) {
    %some = arith.cmpi sgt, %left, %z : index
    %go = arith.andi %prog, %some : i1
    scf.condition(%go) %prog, %left : i1, index
  } do {
  ^bb0(%prog: i1, %left: index):
    %rd:2 = scf.for %pj = %z to %nd step %s1 iter_args(%pg = %f0, %lf = %left) -> (i1, index) {
      %mp = memref.load %mark[%pj] : memref<?xi8>
      %alive = arith.cmpi eq, %mp, %b0 : i8
      %o:2 = scf.if %alive -> (i1, index) {
        %pi = trikeshed.at %dead[%pj] : !s64, index -> i64
        %pp, %pn = func.call @sg_win(%valid, %pi) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        %sr:2 = scf.while (%qj = %z, %refd = %f0) : (index, i1) -> (index, i1) {
          %inq = arith.cmpi slt, %qj, %nd : index
          %notyet = arith.xori %refd, %t1 : i1
          %more = arith.andi %inq, %notyet : i1
          scf.condition(%more) %qj, %refd : index, i1
        } do {
        ^bb0(%qj: index, %refd: i1):
          %mq = memref.load %mark[%qj] : memref<?xi8>
          %qalive = arith.cmpi eq, %mq, %b0 : i8
          %other = arith.cmpi ne, %qj, %pj : index
          %cand = arith.andi %qalive, %other : i1
          %hit = scf.if %cand -> (i1) {
            // q's references, read the first time a round asks (they do not change while q stays)
            %c2q = arith.muli %qj, %i2 : index
            %c2q1 = arith.addi %c2q, %s1 : index
            %seen = memref.load %refs[%c2q] : memref<?xi64>
            %unread = arith.cmpi slt, %seen, %zero : i64
            scf.if %unread {
              %qi = trikeshed.at %dead[%qj] : !s64, index -> i64
              %qp, %qn = func.call @sg_win(%valid, %qi) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
              %got = func.call @nixstore_walk_next(%ctx, %qp, %qn, %two, %cnt) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
              %gc = llvm.load %cnt : !llvm.ptr -> i64
              %gb = llvm.ptrtoint %got : !llvm.ptr to i64
              memref.store %gc, %refs[%c2q] : memref<?xi64>
              memref.store %gb, %refs[%c2q1] : memref<?xi64>
            }
            %rc = memref.load %refs[%c2q] : memref<?xi64>
            %rpb = memref.load %refs[%c2q1] : memref<?xi64>
            %rp = llvm.inttoptr %rpb : i64 to !llvm.ptr
            %rci = arith.index_cast %rc : i64 to index
            %rs = trikeshed.series %rci : !s64 {
            ^bb0(%i: index):
              %i64 = arith.index_cast %i : index to i64
              trikeshed.yield %i64 : i64
            }
            %rj = trikeshed.bisect %rs, %zero : !s64, i64 -> index by {
            ^bb0(%e: i64, %key: i64):
              %ep, %en = func.call @sg_win(%rp, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
              %c = func.call @sg_cmp(%ep, %en, %pp, %pn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i32
              trikeshed.yield %c : i32
            }
            %has = arith.cmpi sge, %rj, %z : index
            scf.yield %has : i1
          } else {
            scf.yield %f0 : i1
          }
          %qn = arith.addi %qj, %s1 : index
          scf.yield %qn, %hit : index, i1
        }
        %o2:2 = scf.if %sr#1 -> (i1, index) {
          scf.yield %pg, %lf : i1, index
        } else {
          func.call @nixstore_walk_gone(%ctx, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
          memref.store %b1, %mark[%pj] : memref<?xi8>
          %lf1 = arith.subi %lf, %s1 : index
          scf.yield %t1, %lf1 : i1, index
        }
        scf.yield %o2#0, %o2#1 : i1, index
      } else {
        scf.yield %pg, %lf : i1, index
      }
      scf.yield %o#0, %o#1 : i1, index
    }
    scf.yield %rd#0, %rd#1 : i1, index
  }
  %gone = arith.subi %nd, %w#1 : index
  %g64 = arith.index_cast %gone : index to i64
  return %g64 : i64
}

//===----------------------------------------------------------------------===//
// queryPathInfo's lines
//===----------------------------------------------------------------------===//

// the key's place among the five keys, or -1
func.func private @sg_keycode(%key: !s) -> i64 {
  %kg = memref.get_global @sg_keys : memref<26xi8>
  %keys = trikeshed.text %kg : memref<26xi8> -> !s
  %og = memref.get_global @sg_koff : memref<5xi8>
  %offs = trikeshed.text %og : memref<5xi8> -> !s
  %lg = memref.get_global @sg_klen : memref<5xi8>
  %lens = trikeshed.text %lg : memref<5xi8> -> !s
  %c5 = arith.constant 5 : index
  %ws = trikeshed.series %c5 : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %m1 = arith.constant -1 : i64
  %r = trikeshed.fold %ws, %m1 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %wi = arith.index_cast %w : i64 to index
    %o8 = trikeshed.at %offs[%wi] : !s, index -> i8
    %l8 = trikeshed.at %lens[%wi] : !s, index -> i8
    %o64 = arith.extui %o8 : i8 to i64
    %l64 = arith.extui %l8 : i8 to i64
    %oi = arith.index_cast %o64 : i64 to index
    %li = arith.index_cast %l64 : i64 to index
    %word = trikeshed.slice %keys[%oi, %li] : !s -> !s
    %c = trikeshed.compare %key, %word unsigned : !s, !s
    %z = arith.constant 0 : i32
    %eq = arith.cmpi eq, %c, %z : i32
    %r = arith.select %eq, %w, %acc : i64
    trikeshed.yield %r : i64
  }
  return %r : i64
}

// The info file's lines (eachLine: the parts between '\n'); in each the first ": " splits the key from the value.  A line
// whose key is one of the five gives a record {key, value offset, value length} (3 x i64), in line order; their count is
// returned.  The value's reading (parseHash, the number, the sets) stays with the caller.
func.func @nixstore_ts_infolines(%tp: !llvm.ptr, %tn: i64, %recs: !llvm.ptr) -> i64 {
  %d = func.call @sg_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %d : !d to !m
  %text = builtin.unrealized_conversion_cast %mm : !m to !s
  %nl = arith.constant 10 : i8
  %colon = arith.constant 58 : i8
  %space = arith.constant 32 : i8
  %ls = trikeshed.parts %text, %nl : !s, i8 -> !sp
  %nls = trikeshed.size %ls : !sp
  %z = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %m1 = arith.constant -1 : i64
  %k = scf.for %j = %z to %nls step %s1 iter_args(%k0 = %zero) -> (i64) {
    %lc = trikeshed.at %ls[%j] : !sp, index -> !tp
    %ls32 = trikeshed.first %lc : !tp -> i32
    %ll32 = trikeshed.second %lc : !tp -> i32
    %lst = arith.index_cast %ls32 : i32 to index
    %lln = arith.index_cast %ll32 : i32 to index
    %line = trikeshed.slice %text[%lst, %lln] : !s -> !s
    %cs = trikeshed.parts %line, %colon : !s, i8 -> !sp
    %ncs = trikeshed.size %cs : !sp
    // the first ':' that a ' ' follows: the end of the first such part (parts before the last end at a ':')
    %f:2 = scf.while (%q = %z, %c = %m1) : (index, i64) -> (index, i64) {
      %q1 = arith.addi %q, %s1 : index
      %inq = arith.cmpi ult, %q1, %ncs : index
      %none = arith.cmpi slt, %c, %zero : i64
      %more = arith.andi %inq, %none : i1
      scf.condition(%more) %q, %c : index, i64
    } do {
    ^bb0(%q: index, %c: i64):
      %pc = trikeshed.at %cs[%q] : !sp, index -> !tp
      %ps32 = trikeshed.first %pc : !tp -> i32
      %pl32 = trikeshed.second %pc : !tp -> i32
      %ps = arith.index_cast %ps32 : i32 to index
      %pl = arith.index_cast %pl32 : i32 to index
      %e = arith.addi %ps, %pl : index
      %e1 = arith.addi %e, %s1 : index
      %inl = arith.cmpi ult, %e1, %lln : index
      %c2 = scf.if %inl -> (i64) {
        %b = trikeshed.at %line[%e1] : !s, index -> i8
        %sp = arith.cmpi eq, %b, %space : i8
        %e64 = arith.index_cast %e : index to i64
        %cv = arith.select %sp, %e64, %m1 : i64
        scf.yield %cv : i64
      } else {
        scf.yield %m1 : i64
      }
      %qn = arith.addi %q, %s1 : index
      scf.yield %qn, %c2 : index, i64
    }
    %has = arith.cmpi sge, %f#1, %zero : i64
    %kn = scf.if %has -> (i64) {
      %ci = arith.index_cast %f#1 : i64 to index
      %key = trikeshed.slice %line[%z, %ci] : !s -> !s
      %code = func.call @sg_keycode(%key) : (!s) -> i64
      %known = arith.cmpi sge, %code, %zero : i64
      %k1 = scf.if %known -> (i64) {
        %two = arith.constant 2 : i64
        %lst64 = arith.index_cast %lst : index to i64
        %lln64 = arith.index_cast %lln : index to i64
        %vo0 = arith.addi %lst64, %f#1 : i64
        %vo = arith.addi %vo0, %two : i64
        %vl0 = arith.subi %lln64, %f#1 : i64
        %vl = arith.subi %vl0, %two : i64
        %c24 = arith.constant 24 : i64
        %c8 = arith.constant 8 : i64
        %c16 = arith.constant 16 : i64
        %off = arith.muli %k0, %c24 : i64
        %rp = llvm.getelementptr %recs[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store %code, %rp : i64, !llvm.ptr
        %op = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store %vo, %op : i64, !llvm.ptr
        %lp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store %vl, %lp : i64, !llvm.ptr
        %kk = arith.addi %k0, %one : i64
        scf.yield %kk : i64
      } else {
        scf.yield %k0 : i64
      }
      scf.yield %k1 : i64
    } else {
      scf.yield %k0 : i64
    }
    scf.yield %kn : i64
  }
  return %k : i64
}
