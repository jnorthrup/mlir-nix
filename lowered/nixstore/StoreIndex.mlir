// The store's index (lib/Store/LocalStore.cpp): `<stateDir>/info.trie`, the info directory's entries as a trie CAS in
// TrikeShed's shape (cas/CursorTrie.kt, HashTrie): rows keyed by the hash part, a byte of fan-out a level, an open leaf
// filled by append and sealed, sorted, as one page of 1,024 rows (16 KiB of them), the heap store's page
// (docs/BTRFS-COMPRESSOR.md): sorted rows emitted as deltas, kept as they are when that is not shorter.
// The pages' algebra (this part of the file):
//
//   nixsi_page_seal   a fill (a leaf's rows, in the order they came) drained once, sorted, into its page
//   nixsi_page_rows   a page's rows again
//   nixsi_page_find   the rows of one key: a bisect into the page, then the run
//
// A row is two words, a key and a value, ordered unsigned by key and then by value; equal rows are kept.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the powers of 128 a varint's length counts
memref.global "private" constant @si_pow : memref<9xi64> = dense<[128, 16384, 2097152, 268435456, 34359738368, 4398046511104, 562949953421312, 72057594037927936, -9223372036854775808]>

// the descriptor of n cells at p
func.func private @si_d(%p: !llvm.ptr, %n: i64) -> !d {
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

//===----------------------------------------------------------------------===//
// The sum that checks what is read back
//===----------------------------------------------------------------------===//

// one word taken into a running sum (MurmurHash3's 64-bit step)
func.func private @si_mix(%h: i64, %w: i64) -> i64 {
  %c1 = arith.constant -8663945395140668459 : i64
  %c2 = arith.constant 5545529020109919103 : i64
  %c5 = arith.constant 5 : i64
  %ca = arith.constant 1390208809 : i64
  %s27 = arith.constant 27 : i64
  %s31 = arith.constant 31 : i64
  %s33 = arith.constant 33 : i64
  %s37 = arith.constant 37 : i64
  %k1 = arith.muli %w, %c1 : i64
  %k2a = arith.shli %k1, %s31 : i64
  %k2b = arith.shrui %k1, %s33 : i64
  %k2 = arith.ori %k2a, %k2b : i64
  %k3 = arith.muli %k2, %c2 : i64
  %h1 = arith.xori %h, %k3 : i64
  %h2a = arith.shli %h1, %s27 : i64
  %h2b = arith.shrui %h1, %s37 : i64
  %h2 = arith.ori %h2a, %h2b : i64
  %h3 = arith.muli %h2, %c5 : i64
  %h4 = arith.addi %h3, %ca : i64
  return %h4 : i64
}

// the sum of the n words at p, begun at seed: a fold of the words, then the finishing mix
func.func private @si_sum(%p: !llvm.ptr, %n: i64, %seed: i64) -> i64 {
  %f1 = arith.constant -49064778989728563 : i64
  %f2 = arith.constant -4265267296055464877 : i64
  %s33 = arith.constant 33 : i64
  %wd = func.call @si_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %h = trikeshed.fold %ws, %seed : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %r = func.call @si_mix(%acc, %w) : (i64, i64) -> i64
    trikeshed.yield %r : i64
  }
  %a = arith.xori %h, %n : i64
  %a1 = arith.shrui %a, %s33 : i64
  %a2 = arith.xori %a, %a1 : i64
  %a3 = arith.muli %a2, %f1 : i64
  %a4 = arith.shrui %a3, %s33 : i64
  %a5 = arith.xori %a3, %a4 : i64
  %a6 = arith.muli %a5, %f2 : i64
  %a7 = arith.shrui %a6, %s33 : i64
  %a8 = arith.xori %a6, %a7 : i64
  return %a8 : i64
}

//===----------------------------------------------------------------------===//
// The sealed page
//===----------------------------------------------------------------------===//

// the bytes of v's varint: one, and one more for each power of 128 v reaches
func.func private @si_vn(%v: i64) -> index {
  %c1 = arith.constant 1 : i64
  %pg = memref.get_global @si_pow : memref<9xi64>
  %pows = trikeshed.text %pg : memref<9xi64> -> !s64
  %n = trikeshed.fold %pows, %c1 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %p: i64):
    %ge = arith.cmpi uge, %v, %p : i64
    %a1 = arith.addi %acc, %c1 : i64
    %r = arith.select %ge, %a1, %acc : i64
    trikeshed.yield %r : i64
  }
  %ni = arith.index_cast %n : i64 to index
  return %ni : index
}

// the varint at p of the n bytes at b (seven bits a byte, the high ones first, the top bit set on all but the last):
// its value and where the next one begins, -1 when the bytes end inside it
func.func private @si_vread(%b: !llvm.ptr, %n: i64, %p: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c7 = arith.constant 7 : i64
  %c127 = arith.constant 127 : i64
  %c128 = arith.constant 128 : i64
  %m1 = arith.constant -1 : i64
  %bd = func.call @si_d(%b, %n) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m
  %bs = builtin.unrealized_conversion_cast %bm : !m to !s
  %qe, %ve, %ge = scf.while (%q = %p, %acc = %c0, %go = %c1) : (i64, i64, i64) -> (i64, i64, i64) {
    %run = arith.cmpi eq, %go, %c1 : i64
    scf.condition(%run) %q, %acc, %go : i64, i64, i64
  } do {
  ^bb0(%qa: i64, %aa: i64, %ga: i64):
    %in = arith.cmpi ult, %qa, %n : i64
    %qn, %vn, %gn = scf.if %in -> (i64, i64, i64) {
      %qi = arith.index_cast %qa : i64 to index
      %byte = trikeshed.at %bs[%qi] : !s, index -> i8
      %b64 = arith.extui %byte : i8 to i64
      %g = arith.andi %b64, %c127 : i64
      %sh = arith.shli %aa, %c7 : i64
      %v = arith.ori %sh, %g : i64
      %more = arith.cmpi uge, %b64, %c128 : i64
      %g2 = arith.select %more, %c1, %c0 : i64
      %q1 = arith.addi %qa, %c1 : i64
      scf.yield %q1, %v, %g2 : i64, i64, i64
    } else {
      scf.yield %qa, %aa, %m1 : i64, i64, i64
    }
    scf.yield %qn, %vn, %gn : i64, i64, i64
  }
  %bad = arith.cmpi eq, %ge, %m1 : i64
  %next = arith.select %bad, %m1, %qe : i64
  return %ve, %next : i64, i64
}

// The page of n rows (2n words at rows, in any order), written at `into`: three words (3 | tag | codec << 24 | n << 32;
// the payload's bytes; the payload's sum), then the payload, to a word.  The rows are put in order (sorted, by key and
// then value, unsigned) and each is two varints: its key's step from the row before and its value's, zigzag.  Every 16th
// row is a restart, with nothing before it (its key and value are whole), and after the rows comes a table of where each
// restart begins (16 bits, the low byte first): the coordinates of the rows' combineAll.  That is codec 1, one combine
// drained once.  When it is not shorter than the rows themselves, or the table's 16 bits cannot hold it, the payload is
// the sorted rows (codec 0).  Returns the page's bytes, or minus them when cap is too few.
func.func @nixsi_page_seal(%rows: !llvm.ptr, %n: i64, %tag: i64, %into: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c63 = arith.constant 63 : i64
  %c127 = arith.constant 127 : i64
  %c128 = arith.constant 128 : i64
  %c65536 = arith.constant 65536 : i64
  %cm8 = arith.constant -8 : i64
  %m1 = arith.constant -1 : i32
  %p1 = arith.constant 1 : i32
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i7 = arith.constant 7 : index
  %n2 = arith.muli %n, %c2 : i64
  %rd = func.call @si_d(%rows, %n2) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rw = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %ord = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %x2 = arith.muli %x, %c2 : i64
    %y2 = arith.muli %y, %c2 : i64
    %xi = arith.index_cast %x2 : i64 to index
    %yi = arith.index_cast %y2 : i64 to index
    %xi1 = arith.addi %xi, %i1 : index
    %yi1 = arith.addi %yi, %i1 : index
    %kx = trikeshed.at %rw[%xi] : !s64, index -> i64
    %ky = trikeshed.at %rw[%yi] : !s64, index -> i64
    %vx = trikeshed.at %rw[%xi1] : !s64, index -> i64
    %vy = trikeshed.at %rw[%yi1] : !s64, index -> i64
    %klt = arith.cmpi ult, %kx, %ky : i64
    %kgt = arith.cmpi ugt, %kx, %ky : i64
    %vlt = arith.cmpi ult, %vx, %vy : i64
    %vgt = arith.cmpi ugt, %vx, %vy : i64
    %cv1 = arith.select %vgt, %p1, %z32 : i32
    %cv = arith.select %vlt, %m1, %cv1 : i32
    %ck1 = arith.select %kgt, %p1, %cv : i32
    %cmp = arith.select %klt, %m1, %ck1 : i32
    trikeshed.yield %cmp : i32
  }
  // row k in order: the steps from row k - 1 (from nothing at a restart), each a series of its varint's bytes
  %stream, %where = trikeshed.combineAll %ni : !s, !sp {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %r16 = arith.andi %k64, %c15 : i64
    %restart = arith.cmpi eq, %r16, %c0 : i64
    %km1 = arith.subi %k, %i1 : index
    %kp = arith.select %restart, %k, %km1 : index
    %e = trikeshed.at %ord[%k] : !s64, index -> i64
    %ep = trikeshed.at %ord[%kp] : !s64, index -> i64
    %e2 = arith.muli %e, %c2 : i64
    %ep2 = arith.muli %ep, %c2 : i64
    %ei = arith.index_cast %e2 : i64 to index
    %epi = arith.index_cast %ep2 : i64 to index
    %ei1 = arith.addi %ei, %i1 : index
    %epi1 = arith.addi %epi, %i1 : index
    %key = trikeshed.at %rw[%ei] : !s64, index -> i64
    %val = trikeshed.at %rw[%ei1] : !s64, index -> i64
    %pk0 = trikeshed.at %rw[%epi] : !s64, index -> i64
    %pv0 = trikeshed.at %rw[%epi1] : !s64, index -> i64
    %pk = arith.select %restart, %c0, %pk0 : i64
    %pv = arith.select %restart, %c0, %pv0 : i64
    %dk = arith.subi %key, %pk : i64
    %dv = arith.subi %val, %pv : i64
    %dv1 = arith.shli %dv, %c1 : i64
    %dv2 = arith.shrsi %dv, %c63 : i64
    %zz = arith.xori %dv1, %dv2 : i64
    %nk = func.call @si_vn(%dk) : (i64) -> index
    %nv = func.call @si_vn(%zz) : (i64) -> index
    %kb = trikeshed.series %nk : !s {
    ^bb0(%jk: index):
      %lastk = arith.subi %nk, %i1 : index
      %leftk = arith.subi %lastk, %jk : index
      %shk = arith.muli %leftk, %i7 : index
      %shk64 = arith.index_cast %shk : index to i64
      %gk = arith.shrui %dk, %shk64 : i64
      %gk7 = arith.andi %gk, %c127 : i64
      %morek = arith.cmpi ult, %jk, %lastk : index
      %contk = arith.select %morek, %c128, %c0 : i64
      %bk = arith.ori %gk7, %contk : i64
      %bk8 = arith.trunci %bk : i64 to i8
      trikeshed.yield %bk8 : i8
    }
    %vb = trikeshed.series %nv : !s {
    ^bb0(%jv: index):
      %lastv = arith.subi %nv, %i1 : index
      %leftv = arith.subi %lastv, %jv : index
      %shv = arith.muli %leftv, %i7 : index
      %shv64 = arith.index_cast %shv : index to i64
      %gv = arith.shrui %zz, %shv64 : i64
      %gv7 = arith.andi %gv, %c127 : i64
      %morev = arith.cmpi ult, %jv, %lastv : index
      %contv = arith.select %morev, %c128, %c0 : i64
      %bv = arith.ori %gv7, %contv : i64
      %bv8 = arith.trunci %bv : i64 to i8
      trikeshed.yield %bv8 : i8
    }
    %piece = trikeshed.combine %kb, %vb : !s, !s -> !s
    trikeshed.yield %piece : !s
  }
  // where each restart begins: the start of every 16th row's piece, two bytes each
  %n15 = arith.addi %n, %c15 : i64
  %nr = arith.divui %n15, %c16 : i64
  %nr2 = arith.muli %nr, %c2 : i64
  %nr2i = arith.index_cast %nr2 : i64 to index
  %rtab = trikeshed.series %nr2i : !s {
  ^bb0(%t: index):
    %t64 = arith.index_cast %t : index to i64
    %half = arith.shrui %t64, %c1 : i64
    %row = arith.muli %half, %c16 : i64
    %rowi = arith.index_cast %row : i64 to index
    %co = trikeshed.at %where[%rowi] : !sp, index -> !tp
    %st32 = trikeshed.first %co : !tp -> i32
    %st = arith.extui %st32 : i32 to i64
    %odd = arith.andi %t64, %c1 : i64
    %shb = arith.muli %odd, %c8 : i64
    %by = arith.shrui %st, %shb : i64
    %by8 = arith.trunci %by : i64 to i8
    trikeshed.yield %by8 : i8
  }
  %both = trikeshed.combine %stream, %rtab : !s, !s -> !s
  %psz = trikeshed.size %both : !s
  %psz64 = arith.index_cast %psz : index to i64
  %raw = arith.muli %n, %c16 : i64
  %shorter = arith.cmpi ult, %psz64, %raw : i64
  %fits16 = arith.cmpi ult, %psz64, %c65536 : i64
  %delta = arith.andi %shorter, %fits16 : i1
  %pay = arith.select %delta, %psz64, %raw : i64
  %pad0 = arith.addi %pay, %c7 : i64
  %padded = arith.andi %pad0, %cm8 : i64
  %total = arith.addi %padded, %c24 : i64
  %room = arith.cmpi sle, %total, %cap : i64
  %res = scf.if %room -> (i64) {
    %codec = arith.extui %delta : i1 to i64
    %cs = arith.shli %codec, %c24 : i64
    %ns = arith.shli %n, %c32 : i64
    %w0a = arith.ori %tag, %c3 : i64
    %w0b = arith.ori %w0a, %cs : i64
    %w0 = arith.ori %w0b, %ns : i64
    %hd = func.call @si_d(%into, %c3) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    memref.store %w0, %hm[%z] : !m64
    memref.store %pay, %hm[%i1] : !m64
    %pp = llvm.getelementptr %into[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    scf.if %delta {
      %padn = arith.subi %padded, %psz64 : i64
      %padi = arith.index_cast %padn : i64 to index
      %zeros = trikeshed.series %padi : !s {
      ^bb0(%q: index):
        %zb = arith.constant 0 : i8
        trikeshed.yield %zb : i8
      }
      %full = trikeshed.combine %stream, %rtab, %zeros : !s, !s, !s -> !s
      %bd = func.call @si_d(%pp, %padded) : (!llvm.ptr, i64) -> !d
      %bm = builtin.unrealized_conversion_cast %bd : !d to !m
      %e1 = trikeshed.drain %full, %bm : !s, !m -> index
    } else {
      %n2i = arith.index_cast %n2 : i64 to index
      %srt = trikeshed.series %n2i : !s64 {
      ^bb0(%q: index):
        %q64 = arith.index_cast %q : index to i64
        %rowq = arith.shrui %q64, %c1 : i64
        %colq = arith.andi %q64, %c1 : i64
        %rqi = arith.index_cast %rowq : i64 to index
        %eq = trikeshed.at %ord[%rqi] : !s64, index -> i64
        %eq2 = arith.muli %eq, %c2 : i64
        %wq = arith.addi %eq2, %colq : i64
        %wqi = arith.index_cast %wq : i64 to index
        %word = trikeshed.at %rw[%wqi] : !s64, index -> i64
        trikeshed.yield %word : i64
      }
      %wd = func.call @si_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %e2 = trikeshed.drain %srt, %wm : !s64, !m64 -> index
    }
    %pw = arith.shrui %padded, %c3 : i64
    %seed = arith.xori %w0, %pay : i64
    %sum = func.call @si_sum(%pp, %pw, %seed) : (!llvm.ptr, i64, i64) -> i64
    memref.store %sum, %hm[%i2] : !m64
    scf.yield %total : i64
  } else {
    %neg = arith.subi %c0, %total : i64
    scf.yield %neg : i64
  }
  return %res : i64
}

// The row count of the page in the avail bytes at page, or -1 when they are not one: its kind, its payload within avail,
// the lengths its codec gives, and with `check` its payload's sum.
func.func private @si_page_n(%page: !llvm.ptr, %avail: i64, %check: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c255 = arith.constant 255 : i64
  %c65536 = arith.constant 65536 : i64
  %cm8 = arith.constant -8 : i64
  %m1 = arith.constant -1 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %has = arith.cmpi sge, %avail, %c24 : i64
  %r = scf.if %has -> (i64) {
    %hd = func.call @si_d(%page, %c3) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
    %w0 = trikeshed.at %hs[%z] : !s64, index -> i64
    %pay = trikeshed.at %hs[%i1] : !s64, index -> i64
    %sum = trikeshed.at %hs[%i2] : !s64, index -> i64
    %kind = arith.andi %w0, %c255 : i64
    %cd0 = arith.shrui %w0, %c24 : i64
    %codec = arith.andi %cd0, %c255 : i64
    %n = arith.shrui %w0, %c32 : i64
    %isp = arith.cmpi eq, %kind, %c3 : i64
    %left = arith.subi %avail, %c24 : i64
    %payin = arith.cmpi ule, %pay, %left : i64
    %pad0 = arith.addi %pay, %c7 : i64
    %padded = arith.andi %pad0, %cm8 : i64
    %padin = arith.cmpi ule, %padded, %left : i64
    %n15 = arith.addi %n, %c15 : i64
    %nr = arith.divui %n15, %c16 : i64
    %nr2 = arith.muli %nr, %c2 : i64
    %raw = arith.muli %n, %c16 : i64
    %is0 = arith.cmpi eq, %codec, %c0 : i64
    %len0 = arith.cmpi eq, %pay, %raw : i64
    %ok0 = arith.andi %is0, %len0 : i1
    // codec 1: the table, and two bytes a row at least before it, in fewer than 2^16 bytes
    %c1 = arith.constant 1 : i64
    %is1 = arith.cmpi eq, %codec, %c1 : i64
    %n2 = arith.muli %n, %c2 : i64
    %least = arith.addi %nr2, %n2 : i64
    %len1a = arith.cmpi uge, %pay, %least : i64
    %len1b = arith.cmpi ult, %pay, %c65536 : i64
    %ok1a = arith.andi %is1, %len1a : i1
    %ok1 = arith.andi %ok1a, %len1b : i1
    %okc = arith.ori %ok0, %ok1 : i1
    %s1 = arith.andi %isp, %payin : i1
    %s2 = arith.andi %s1, %padin : i1
    %shape = arith.andi %s2, %okc : i1
    %want = arith.cmpi ne, %check, %c0 : i64
    %sums = arith.andi %shape, %want : i1
    %ok = scf.if %sums -> (i1) {
      %pp = llvm.getelementptr %page[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %pw = arith.shrui %padded, %c3 : i64
      %seed = arith.xori %w0, %pay : i64
      %got = func.call @si_sum(%pp, %pw, %seed) : (!llvm.ptr, i64, i64) -> i64
      %same = arith.cmpi eq, %got, %sum : i64
      scf.yield %same : i1
    } else {
      scf.yield %shape : i1
    }
    %rn = arith.select %ok, %n, %m1 : i64
    scf.yield %rn : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// A page's rows, in order, as 2n words at out (cap rows of room): n, or -1 when the avail bytes at page are not a page
// that reads back whole.  Codec 1 is one fold of the payload's bytes: a varint ends at a byte below 128, and the fold
// keeps the row it is at and the key and value before it.
func.func @nixsi_page_rows(%page: !llvm.ptr, %avail: i64, %out: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c127 = arith.constant 127 : i64
  %c128 = arith.constant 128 : i64
  %c255 = arith.constant 255 : i64
  %m1 = arith.constant -1 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %st = memref.alloca() : memref<3xi64>
  memref.store %c0, %st[%z] : memref<3xi64>
  memref.store %c0, %st[%i1] : memref<3xi64>
  memref.store %c0, %st[%i2] : memref<3xi64>
  %n = func.call @si_page_n(%page, %avail, %c1) : (!llvm.ptr, i64, i64) -> i64
  %isn = arith.cmpi sge, %n, %c0 : i64
  %fit = arith.cmpi sle, %n, %cap : i64
  %go = arith.andi %isn, %fit : i1
  %r = scf.if %go -> (i64) {
    %hd = func.call @si_d(%page, %c2) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
    %w0 = trikeshed.at %hs[%z] : !s64, index -> i64
    %pay = trikeshed.at %hs[%i1] : !s64, index -> i64
    %cd0 = arith.shrui %w0, %c24 : i64
    %codec = arith.andi %cd0, %c255 : i64
    %pp = llvm.getelementptr %page[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n2 = arith.muli %n, %c2 : i64
    %od = func.call @si_d(%out, %n2) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %asis = arith.cmpi eq, %codec, %c0 : i64
    %rr = scf.if %asis -> (i64) {
      %wd = func.call @si_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %e0 = trikeshed.drain %ws, %om : !s64, !m64 -> index
      scf.yield %n : i64
    } else {
      %n15 = arith.addi %n, %c15 : i64
      %nr = arith.divui %n15, %c16 : i64
      %nr2 = arith.muli %nr, %c2 : i64
      %slen = arith.subi %pay, %nr2 : i64
      %bd = func.call @si_d(%pp, %slen) : (!llvm.ptr, i64) -> !d
      %bm = builtin.unrealized_conversion_cast %bd : !d to !m
      %stream = builtin.unrealized_conversion_cast %bm : !m to !s
      %fin = trikeshed.fold %stream, %c0 : !s, i64 -> i64 {
      ^bb0(%acc: i64, %b: i8):
        %b64 = arith.extui %b : i8 to i64
        %g = arith.andi %b64, %c127 : i64
        %sh = arith.shli %acc, %c7 : i64
        %v = arith.ori %sh, %g : i64
        %more = arith.cmpi uge, %b64, %c128 : i64
        %next = scf.if %more -> (i64) {
          scf.yield %v : i64
        } else {
          %j = memref.load %st[%z] : memref<3xi64>
          %inb = arith.cmpi ult, %j, %n2 : i64
          scf.if %inb {
            %rowj = arith.shrui %j, %c1 : i64
            %r16 = arith.andi %rowj, %c15 : i64
            %restart = arith.cmpi eq, %r16, %c0 : i64
            %col = arith.andi %j, %c1 : i64
            %iskey = arith.cmpi eq, %col, %c0 : i64
            %ji = arith.index_cast %j : i64 to index
            scf.if %iskey {
              %pk = memref.load %st[%i1] : memref<3xi64>
              %basek = arith.select %restart, %c0, %pk : i64
              %key = arith.addi %basek, %v : i64
              memref.store %key, %om[%ji] : !m64
              memref.store %key, %st[%i1] : memref<3xi64>
            } else {
              %pv = memref.load %st[%i2] : memref<3xi64>
              %basev = arith.select %restart, %c0, %pv : i64
              %hv = arith.shrui %v, %c1 : i64
              %low = arith.andi %v, %c1 : i64
              %neg = arith.subi %c0, %low : i64
              %un = arith.xori %hv, %neg : i64
              %val = arith.addi %basev, %un : i64
              memref.store %val, %om[%ji] : !m64
              memref.store %val, %st[%i2] : memref<3xi64>
            }
          }
          %j1 = arith.addi %j, %c1 : i64
          memref.store %j1, %st[%z] : memref<3xi64>
          scf.yield %c0 : i64
        }
        trikeshed.yield %next : i64
      }
      %jn = memref.load %st[%z] : memref<3xi64>
      %all = arith.cmpi eq, %jn, %n2 : i64
      %done = arith.cmpi eq, %fin, %c0 : i64
      %whole = arith.andi %all, %done : i1
      %rn = arith.select %whole, %n, %m1 : i64
      scf.yield %rn : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The values of a page's rows whose key is `key`, the first cap of them stored at out: their count, or -1 when the avail
// bytes at page are not a page (the payload's sum is not checked here: the trie checks a page once).  Codec 1: the
// restarts searched for the first whose key is not below `key` (bisect; a restart's key is the varint it begins with),
// then the rows read from the restart before it, to the first key above.  Codec 0: the keys searched, then the run.
func.func @nixsi_page_find(%page: !llvm.ptr, %avail: i64, %key: i64, %out: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c255 = arith.constant 255 : i64
  %m1 = arith.constant -1 : i64
  %lt32 = arith.constant -1 : i32
  %ge32 = arith.constant 1 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %n = func.call @si_page_n(%page, %avail, %c0) : (!llvm.ptr, i64, i64) -> i64
  %some = arith.cmpi sgt, %n, %c0 : i64
  %r = scf.if %some -> (i64) {
    %hd = func.call @si_d(%page, %c2) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
    %w0 = trikeshed.at %hs[%z] : !s64, index -> i64
    %pay = trikeshed.at %hs[%i1] : !s64, index -> i64
    %cd0 = arith.shrui %w0, %c24 : i64
    %codec = arith.andi %cd0, %c255 : i64
    %pp = llvm.getelementptr %page[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %od = func.call @si_d(%out, %cap) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %ni = arith.index_cast %n : i64 to index
    %asis = arith.cmpi eq, %codec, %c0 : i64
    %rr = scf.if %asis -> (i64) {
      %n2 = arith.muli %n, %c2 : i64
      %wd = func.call @si_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %keys = trikeshed.series %ni : !s64 {
      ^bb0(%i: index):
        %i2x = arith.muli %i, %i2 : index
        %kv = trikeshed.at %ws[%i2x] : !s64, index -> i64
        trikeshed.yield %kv : i64
      }
      %lb = trikeshed.bisect %keys, %key : !s64, i64 -> index by {
      ^bb0(%e: i64, %kk: i64):
        %below = arith.cmpi ult, %e, %kk : i64
        %c = arith.select %below, %lt32, %ge32 : i32
        trikeshed.yield %c : i32
      }
      %lb64 = arith.index_cast %lb : index to i64
      %ins0 = arith.subi %m1, %lb64 : i64
      %ie, %ce = scf.while (%i = %ins0, %cnt = %c0) : (i64, i64) -> (i64, i64) {
        %in = arith.cmpi slt, %i, %n : i64
        %same = scf.if %in -> (i1) {
          %ix = arith.muli %i, %c2 : i64
          %ixi = arith.index_cast %ix : i64 to index
          %k = trikeshed.at %ws[%ixi] : !s64, index -> i64
          %eq = arith.cmpi eq, %k, %key : i64
          scf.yield %eq : i1
        } else {
          scf.yield %in : i1
        }
        scf.condition(%same) %i, %cnt : i64, i64
      } do {
      ^bb0(%ia: i64, %ca: i64):
        %room = arith.cmpi slt, %ca, %cap : i64
        scf.if %room {
          %vx = arith.muli %ia, %c2 : i64
          %vx1 = arith.addi %vx, %c1 : i64
          %vxi = arith.index_cast %vx1 : i64 to index
          %v = trikeshed.at %ws[%vxi] : !s64, index -> i64
          %cai = arith.index_cast %ca : i64 to index
          memref.store %v, %om[%cai] : !m64
        }
        %i1n = arith.addi %ia, %c1 : i64
        %c1n = arith.addi %ca, %c1 : i64
        scf.yield %i1n, %c1n : i64, i64
      }
      scf.yield %ce : i64
    } else {
      %n15 = arith.addi %n, %c15 : i64
      %nr = arith.divui %n15, %c16 : i64
      %nr2 = arith.muli %nr, %c2 : i64
      %slen = arith.subi %pay, %nr2 : i64
      %bd = func.call @si_d(%pp, %pay) : (!llvm.ptr, i64) -> !d
      %bm = builtin.unrealized_conversion_cast %bd : !d to !m
      %bs = builtin.unrealized_conversion_cast %bm : !m to !s
      %nri = arith.index_cast %nr : i64 to index
      %ridx = trikeshed.series %nri : !s64 {
      ^bb0(%i: index):
        %i64 = arith.index_cast %i : index to i64
        trikeshed.yield %i64 : i64
      }
      %lb = trikeshed.bisect %ridx, %key : !s64, i64 -> index by {
      ^bb0(%j: i64, %kk: i64):
        %t = arith.muli %j, %c2 : i64
        %lo_at = arith.addi %slen, %t : i64
        %hi_at = arith.addi %lo_at, %c1 : i64
        %lo_i = arith.index_cast %lo_at : i64 to index
        %hi_i = arith.index_cast %hi_at : i64 to index
        %lo8 = trikeshed.at %bs[%lo_i] : !s, index -> i8
        %hi8 = trikeshed.at %bs[%hi_i] : !s, index -> i8
        %lo = arith.extui %lo8 : i8 to i64
        %hi = arith.extui %hi8 : i8 to i64
        %his = arith.shli %hi, %c8 : i64
        %off = arith.ori %lo, %his : i64
        %rk, %rn = func.call @si_vread(%pp, %slen, %off) : (!llvm.ptr, i64, i64) -> (i64, i64)
        %read = arith.cmpi sge, %rn, %c0 : i64
        %lower = arith.cmpi ult, %rk, %kk : i64
        %below = arith.andi %read, %lower : i1
        %c = arith.select %below, %lt32, %ge32 : i32
        trikeshed.yield %c : i32
      }
      %lb64 = arith.index_cast %lb : index to i64
      %ins = arith.subi %m1, %lb64 : i64
      %ins1 = arith.subi %ins, %c1 : i64
      %j0 = arith.maxsi %ins1, %c0 : i64
      %t0 = arith.muli %j0, %c2 : i64
      %lo0_at = arith.addi %slen, %t0 : i64
      %hi0_at = arith.addi %lo0_at, %c1 : i64
      %lo0_i = arith.index_cast %lo0_at : i64 to index
      %hi0_i = arith.index_cast %hi0_at : i64 to index
      %lo08 = trikeshed.at %bs[%lo0_i] : !s, index -> i8
      %hi08 = trikeshed.at %bs[%hi0_i] : !s, index -> i8
      %lo0 = arith.extui %lo08 : i8 to i64
      %hi0 = arith.extui %hi08 : i8 to i64
      %hi0s = arith.shli %hi0, %c8 : i64
      %off0 = arith.ori %lo0, %hi0s : i64
      %k0 = arith.muli %j0, %c16 : i64
      %pe, %ke, %pke, %pve, %ce, %ge = scf.while (%p = %off0, %k = %k0, %pk = %c0, %pv = %c0, %cnt = %c0, %go = %c1)
          : (i64, i64, i64, i64, i64, i64) -> (i64, i64, i64, i64, i64, i64) {
        %on = arith.cmpi eq, %go, %c1 : i64
        %in = arith.cmpi slt, %k, %n : i64
        %run = arith.andi %on, %in : i1
        scf.condition(%run) %p, %k, %pk, %pv, %cnt, %go : i64, i64, i64, i64, i64, i64
      } do {
      ^bb0(%pa: i64, %ka: i64, %pka: i64, %pva: i64, %ca: i64, %ga: i64):
        %r16 = arith.andi %ka, %c15 : i64
        %restart = arith.cmpi eq, %r16, %c0 : i64
        %dk, %p1 = func.call @si_vread(%pp, %slen, %pa) : (!llvm.ptr, i64, i64) -> (i64, i64)
        %ok1 = arith.cmpi sge, %p1, %c0 : i64
        %zz, %p2 = scf.if %ok1 -> (i64, i64) {
          %zv, %zn = func.call @si_vread(%pp, %slen, %p1) : (!llvm.ptr, i64, i64) -> (i64, i64)
          scf.yield %zv, %zn : i64, i64
        } else {
          scf.yield %c0, %m1 : i64, i64
        }
        %ok2 = arith.cmpi sge, %p2, %c0 : i64
        %basek = arith.select %restart, %c0, %pka : i64
        %basev = arith.select %restart, %c0, %pva : i64
        %rowk = arith.addi %basek, %dk : i64
        %hv = arith.shrui %zz, %c1 : i64
        %low = arith.andi %zz, %c1 : i64
        %neg = arith.subi %c0, %low : i64
        %un = arith.xori %hv, %neg : i64
        %rowv = arith.addi %basev, %un : i64
        %eq0 = arith.cmpi eq, %rowk, %key : i64
        %eq = arith.andi %ok2, %eq0 : i1
        %room = arith.cmpi slt, %ca, %cap : i64
        %put = arith.andi %eq, %room : i1
        scf.if %put {
          %cai = arith.index_cast %ca : i64 to index
          memref.store %rowv, %om[%cai] : !m64
        }
        %one = arith.extui %eq : i1 to i64
        %cn = arith.addi %ca, %one : i64
        %notpast = arith.cmpi ule, %rowk, %key : i64
        %g1 = arith.select %notpast, %c1, %c0 : i64
        %gn = arith.select %ok2, %g1, %m1 : i64
        %kn = arith.addi %ka, %c1 : i64
        scf.yield %p2, %kn, %rowk, %rowv, %cn, %gn : i64, i64, i64, i64, i64, i64
      }
      %bad = arith.cmpi eq, %ge, %m1 : i64
      %rc = arith.select %bad, %m1, %ce : i64
      scf.yield %rc : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %n : i64
  }
  return %r : i64
}
