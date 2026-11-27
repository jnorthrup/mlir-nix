// The local store's index (lib/Store/LocalStore.cpp calls it): `<stateDir>/info.trie`, the entries of the info
// directory as a trie CAS in TrikeShed's shape (cas/CursorTrie.kt: HashTrie's rows by a digest's leading bytes, LaneTrie's
// relation) with the heap store's page (docs/BTRFS-COMPRESSOR.md).  The info files stay what they are, the store's
// truth and what an older mlnix reads and writes; the index is derived from them, says which state of the directory it
// speaks for, and answers only for that state.
//
//   the calls       nixsi_info      a path's info text when the index holds the directory as it is: no lock, no file
//                                   opened (else the store reads the file, as it always did)
//                   nixsi_names     every entry's name in byte order (allValidPaths), or the names whose info may refer
//                                   to a path (queryReferrers reads those and no other)
//                   nixsi_register  an info file written (through `.tmp`, renamed), the index told
//                   nixsi_unlink    an info file removed, the index told
//   two relations   the paths: a row is (the key of an entry's name, its record), struck out by a later row; the
//                   references: a row is (the key of a reference's name, the referring record).  HashTrie's put and
//                   get: down by the key's bytes, open leaves filled by append, a full leaf sealed under a node
//   a key           the first 64 bits of the name's hash part (13 nix32 digits, each its place in the alphabet)
//   a record        an entry's name, its identity (the file's number, with its time where a number is given again)
//                   and its info text as the file has it
//   a page          a full leaf (1,024 rows, 16 KiB) sealed: sorted, each row its step from the one before (two
//                   varints), a restart every 16 rows and the table of the restarts; the rows as they are when that
//                   is not shorter
//   the token       the directory's state as one word (what fstat says of it); written after a pass over the
//                   directory that it did not change under.  The index is read for a directory with that token only
//   sums            a record, a leaf, a page, a node and the first words each carry the sum of what they hold and are
//                   summed before they are believed
// The system's words (where a directory entry's name is, how a file is opened, which file systems are trusted, this
// boot's name) are StoreIndexDarwin.mlir.in and StoreIndexLinux.mlir.  scripts/store-index-check.sh proves the pages,
// the index against the directory under damage and killed writers, and the system's words.
//
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
memref.global "private" constant @nxsi_pow : memref<9xi64> = dense<[128, 16384, 2097152, 268435456, 34359738368, 4398046511104, 562949953421312, 72057594037927936, -9223372036854775808]>

// the descriptor of n cells at p
func.func private @nxsi_d(%p: !llvm.ptr, %n: i64) -> !d {
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
func.func private @nxsi_mix(%h: i64, %w: i64) -> i64 {
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
func.func private @nxsi_sum(%p: !llvm.ptr, %n: i64, %seed: i64) -> i64 {
  %f1 = arith.constant -49064778989728563 : i64
  %f2 = arith.constant -4265267296055464877 : i64
  %s33 = arith.constant 33 : i64
  %wd = func.call @nxsi_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
  %h = trikeshed.fold %ws, %seed : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %r = func.call @nxsi_mix(%acc, %w) : (i64, i64) -> i64
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
func.func private @nxsi_vn(%v: i64) -> index {
  %c1 = arith.constant 1 : i64
  %pg = memref.get_global @nxsi_pow : memref<9xi64>
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
func.func private @nxsi_vread(%b: !llvm.ptr, %n: i64, %p: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c7 = arith.constant 7 : i64
  %c127 = arith.constant 127 : i64
  %c128 = arith.constant 128 : i64
  %m1 = arith.constant -1 : i64
  %bd = func.call @nxsi_d(%b, %n) : (!llvm.ptr, i64) -> !d
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
  %rd = func.call @nxsi_d(%rows, %n2) : (!llvm.ptr, i64) -> !d
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
    %nk = func.call @nxsi_vn(%dk) : (i64) -> index
    %nv = func.call @nxsi_vn(%zz) : (i64) -> index
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
    %hd = func.call @nxsi_d(%into, %c3) : (!llvm.ptr, i64) -> !d
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
      %bd = func.call @nxsi_d(%pp, %padded) : (!llvm.ptr, i64) -> !d
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
      %wd = func.call @nxsi_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %e2 = trikeshed.drain %srt, %wm : !s64, !m64 -> index
    }
    %pw = arith.shrui %padded, %c3 : i64
    %seed = arith.xori %w0, %pay : i64
    %sum = func.call @nxsi_sum(%pp, %pw, %seed) : (!llvm.ptr, i64, i64) -> i64
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
func.func private @nxsi_page_n(%page: !llvm.ptr, %avail: i64, %check: i64) -> i64 {
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
    %hd = func.call @nxsi_d(%page, %c3) : (!llvm.ptr, i64) -> !d
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
      %got = func.call @nxsi_sum(%pp, %pw, %seed) : (!llvm.ptr, i64, i64) -> i64
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
  %n = func.call @nxsi_page_n(%page, %avail, %c1) : (!llvm.ptr, i64, i64) -> i64
  %isn = arith.cmpi sge, %n, %c0 : i64
  %fit = arith.cmpi sle, %n, %cap : i64
  %go = arith.andi %isn, %fit : i1
  %r = scf.if %go -> (i64) {
    %hd = func.call @nxsi_d(%page, %c2) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
    %w0 = trikeshed.at %hs[%z] : !s64, index -> i64
    %pay = trikeshed.at %hs[%i1] : !s64, index -> i64
    %cd0 = arith.shrui %w0, %c24 : i64
    %codec = arith.andi %cd0, %c255 : i64
    %pp = llvm.getelementptr %page[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n2 = arith.muli %n, %c2 : i64
    %od = func.call @nxsi_d(%out, %n2) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %asis = arith.cmpi eq, %codec, %c0 : i64
    %rr = scf.if %asis -> (i64) {
      %wd = func.call @nxsi_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %e0 = trikeshed.drain %ws, %om : !s64, !m64 -> index
      scf.yield %n : i64
    } else {
      %n15 = arith.addi %n, %c15 : i64
      %nr = arith.divui %n15, %c16 : i64
      %nr2 = arith.muli %nr, %c2 : i64
      %slen = arith.subi %pay, %nr2 : i64
      %bd = func.call @nxsi_d(%pp, %slen) : (!llvm.ptr, i64) -> !d
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
  %n = func.call @nxsi_page_n(%page, %avail, %c0) : (!llvm.ptr, i64, i64) -> i64
  %some = arith.cmpi sgt, %n, %c0 : i64
  %r = scf.if %some -> (i64) {
    %hd = func.call @nxsi_d(%page, %c2) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
    %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
    %w0 = trikeshed.at %hs[%z] : !s64, index -> i64
    %pay = trikeshed.at %hs[%i1] : !s64, index -> i64
    %cd0 = arith.shrui %w0, %c24 : i64
    %codec = arith.andi %cd0, %c255 : i64
    %pp = llvm.getelementptr %page[%c24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %od = func.call @nxsi_d(%out, %cap) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %ni = arith.index_cast %n : i64 to index
    %asis = arith.cmpi eq, %codec, %c0 : i64
    %rr = scf.if %asis -> (i64) {
      %n2 = arith.muli %n, %c2 : i64
      %wd = func.call @nxsi_d(%pp, %n2) : (!llvm.ptr, i64) -> !d
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
      %bd = func.call @nxsi_d(%pp, %pay) : (!llvm.ptr, i64) -> !d
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
        %rk, %rn = func.call @nxsi_vread(%pp, %slen, %off) : (!llvm.ptr, i64, i64) -> (i64, i64)
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
        %dk, %p1 = func.call @nxsi_vread(%pp, %slen, %pa) : (!llvm.ptr, i64, i64) -> (i64, i64)
        %ok1 = arith.cmpi sge, %p1, %c0 : i64
        %zz, %p2 = scf.if %ok1 -> (i64, i64) {
          %zv, %zn = func.call @nxsi_vread(%pp, %slen, %p1) : (!llvm.ptr, i64, i64) -> (i64, i64)
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

//===----------------------------------------------------------------------===//
// The image and the handle
//===----------------------------------------------------------------------===//
//
// The index is one file, `<stateDir>/info.trie` (beside the info directory it is derived from), mapped whole and shared:
// 32 words, then a heap that only grows.  The words: 0 the magic, 1 the heap's end, 2 the token (the info directory's
// state the index holds, 0 when no pass has read the directory since it changed), 3 and 4 the roots (the paths, the
// references), 5 the paths in the directory, 6 and 7 the rows put (paths, references), 8 the rows struck out, 9 this
// boot's name, 15 the sum of words 0 to 14.
// A blob of the heap begins with a word whose low byte is its kind:
//   1 a record   1 | flags << 8 | name bytes << 16 | text bytes << 32; the entry's identity; the sum; the name, the
//                text (an info file as it is), zeros to a word.  flags: 1 listed (a valid path's: 34 bytes of name at
//                least and no ".tmp"), 2 not held (the text is read from the file: it is not as registerValidPath
//                writes one, or there is none to read)
//   2 a leaf     2 | relation << 8 | room in rows << 32; rows | their running sum << 32; the rows as they came
//   3 a page     a sealed leaf (above)
//   4 a node     4 | relation << 8 | the sum of its other words << 16; its page; 256 children (a leaf or a node each,
//                0 while none; a child lies after its node in the heap, so every way down ends)
// A relation is HashTrie's: a row goes down from the root by the bytes of its key, to a leaf, which it is appended to; a
// leaf of 1,024 rows is sealed as a page under a node that takes its place, and later rows of its prefix go to the node's
// children (past the key's eight bytes, to the one child a chain goes on by).  A leaf begins with room for 16 rows and
// is copied fourfold when full, so a small index is small.  A key's rows are in every page on its way down (a bisect
// each) and in the leaf the way ends at (a scan).
// The paths: a row (key of the entry's name, its record), struck out by a row (the key, the record | 1).  The references:
// a row (key of the reference's name, the referring record), one row under the key of all (-1) for a record not held:
// every query of referrers gets it, and the store reads its file and fails or answers as it did before the index.
// A record no row of the paths names any more is passed over wherever it is met.
//
// What the index is trusted with, and why:
//   a writer that dies    what is written is linked last and the token after everything, so the index it leaves either
//                         reads back whole or fails a sum; a blob is checked (its place, its lengths, its sum) before
//                         it is believed, and an index that is not sound is begun again from the files
//   the system stopping   the file is written through the mapping and never forced to the disk, so what was written
//                         before the system last started may be there in part: word 9 is the boot's name, and an index
//                         of another boot is begun again (one reading of the info files a boot)
//   two processes         whoever lists or changes takes the file's lock (flock; a list of referrers too: it may have
//                         to mend the index).  nixsi_info takes none: it copies what it gives and sums the copy
//   an older mlnix        takes no lock and knows no index: its changes change the directory's token.  A change this
//                         process makes (a register, an unlink) clears the token even though the index is told of it,
//                         because an older mlnix may have changed the directory in the same moment and a directory's
//                         time does not count changes; the next list makes a pass (the directory read, every entry
//                         matched with its row by name and identity, no file opened that was read before)
//   the file system       the file is kept only where the system says the directory's file system is a local one that
//                         tells its changes (nixsi_os_local).  Anywhere else a process answers from an index of its
//                         own that it begins again for every query, reading the files as the old code did; where the
//                         file system is trusted but the file cannot be made, written or locked, the process's own
//                         index lasts as long as the process and follows the directory's token as the file would
//   the directory's time  set one nanosecond back before a pass (a time no later change gives it); where it cannot
//                         be set the token is held only once the directory is three seconds old

// the handle of this process: 0 the image, 1 its kind (0 none, 1 the file, 2 the file read-only, 3 this process's own),
// 2 the file, 3 the info directory, 4 the file's bytes, 5 the directory path's bytes, 6 a directory is in hand, 7 the
// lock held (1 shared, 2 alone), 8 the entries a pass has seen, 9 the file as it was when last locked (its length and
// time), 10 this boot (0 not asked yet, 1 not known), 11 what the directory's file system is trusted with (0 nothing:
// no index is kept beside it; 1 an entry's number and time; 2 its number alone), 12 the last stamp held, 13 the
// directory was looked for; from 16 the rooms' pointers and bytes (two words a room).  The handle is the store's
// thread's alone, as the store is.
memref.global "private" @nxsi_h : memref<40xi64> = dense<0>
memref.global "private" constant @nxsi_zero : memref<32xi64> = dense<0>
// the code of a byte in a key: its place in nix32's alphabet, the low 5 bits of any other byte
memref.global "private" constant @nxsi_code : memref<256xi8> = dense<"0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f000102030405060708091a1b1c1d1e1f000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000a0b0c0d050e0f101112131415160f1718191a14151b1c1d1e1f1b1c1d1e1f000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f">
// ".tmp" NUL, ".trie" NUL, three bytes not used, "/"
memref.global "private" constant @nxsi_words : memref<16xi8> = dense<"0x2e746d70002e7472696500616200002f">

// the C library: what is the same wherever mlnix is built
func.func private @close(i32) -> i32
func.func private @read(i32, !llvm.ptr, i64) -> i64
func.func private @write(i32, !llvm.ptr, i64) -> i64
func.func private @rename(!llvm.ptr, !llvm.ptr) -> i32
func.func private @unlink(!llvm.ptr) -> i32
func.func private @ftruncate(i32, i64) -> i32
func.func private @lseek(i32, i64, i32) -> i64
func.func private @mmap(!llvm.ptr, i64, i32, i32, i32, i64) -> !llvm.ptr
func.func private @munmap(!llvm.ptr, i64) -> i32
func.func private @flock(i32, i32) -> i32
func.func private @futimens(i32, !llvm.ptr) -> i32
func.func private @closedir(!llvm.ptr) -> i32
func.func private @realloc(!llvm.ptr, i64) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @time(!llvm.ptr) -> i64
func.func private @abort()
// The system's words (StoreIndexDarwin.mlir, StoreIndexLinux.mlir), what is not the same everywhere: where a directory
// entry's name is and where a file's times begin in what stat fills; mmap's flags for memory of the process's own; a
// file opened (how: 0 to read, 1 to read and write, 2 the same and made when it is not there, 3 written anew; never
// kept across an exec); stat and the directory's reading under the names the system gives them; what the file system
// of an open directory is trusted with (the handle's word 11); this boot's name (its bytes, 0 when it has none).
func.func private @nixsi_os_name() -> i64
func.func private @nixsi_os_atime() -> i64
func.func private @nixsi_os_anon() -> i64
func.func private @nixsi_os_open(!llvm.ptr, i64) -> i32
func.func private @nixsi_os_fstat(i32, !llvm.ptr) -> i32
func.func private @nixsi_os_lstat(!llvm.ptr, !llvm.ptr) -> i32
func.func private @nixsi_os_opendir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsi_os_readdir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsi_os_local(i32) -> i64
func.func private @nixsi_os_boot(!llvm.ptr, i64) -> i64
// the store's (lib/Store/LocalStore.cpp): a name of the answer
func.func private @nixsi_name(!llvm.ptr, !llvm.ptr, !llvm.ptr, i64)
// an info file's lines (StoreGraph.mlir), parseHash (HashParse.mlir), baseNameOf (PathOps.mlir)
func.func private @nixstore_ts_infolines(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_parsehash(!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixstore_ts_basename(!llvm.ptr, i64, !llvm.ptr) -> i64

// word i of the handle, read and written
func.func private @nxsi_hg(%i: i64) -> i64 {
  %g = memref.get_global @nxsi_h : memref<40xi64>
  %hs = trikeshed.text %g : memref<40xi64> -> !s64
  %ii = arith.index_cast %i : i64 to index
  %v = trikeshed.at %hs[%ii] : !s64, index -> i64
  return %v : i64
}
func.func private @nxsi_hs(%i: i64, %v: i64) {
  %g = memref.get_global @nxsi_h : memref<40xi64>
  %ii = arith.index_cast %i : i64 to index
  memref.store %v, %g[%ii] : memref<40xi64>
  return
}

// Room b of the handle, n bytes at least (what it held is kept): the results of a search (0 the paths', 1 the
// references'), 2 a file read, 3 the lines of one, 4 a text given out, 5 the entries seen, 6 a path, 7 a relation's rows,
// 8 the records of an answer, 9 its names, 10 the directory's path, 11 the blobs found whole.
func.func private @nxsi_buf(%b: i64, %n: i64) -> !llvm.ptr {
  %c2 = arith.constant 2 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c4096 = arith.constant 4096 : i64
  %b2 = arith.muli %b, %c2 : i64
  %pi = arith.addi %b2, %c16 : i64
  %ci = arith.addi %b2, %c17 : i64
  %p0 = func.call @nxsi_hg(%pi) : (i64) -> i64
  %cap = func.call @nxsi_hg(%ci) : (i64) -> i64
  %enough = arith.cmpi sge, %cap, %n : i64
  %bits = scf.if %enough -> (i64) {
    scf.yield %p0 : i64
  } else {
    %twice = arith.muli %cap, %c2 : i64
    %w0 = arith.maxsi %n, %twice : i64
    %want = arith.maxsi %w0, %c4096 : i64
    %old = llvm.inttoptr %p0 : i64 to !llvm.ptr
    %new = func.call @realloc(%old, %want) : (!llvm.ptr, i64) -> !llvm.ptr
    %nb = llvm.ptrtoint %new : !llvm.ptr to i64
    %c0 = arith.constant 0 : i64
    %none = arith.cmpi eq, %nb, %c0 : i64
    scf.if %none {
      func.call @abort() : () -> ()
    }
    func.call @nxsi_hs(%pi, %nb) : (i64, i64) -> ()
    func.call @nxsi_hs(%ci, %want) : (i64, i64) -> ()
    scf.yield %nb : i64
  }
  %p = llvm.inttoptr %bits : i64 to !llvm.ptr
  return %p : !llvm.ptr
}
// the bytes room b has
func.func private @nxsi_cap(%b: i64) -> i64 {
  %c2 = arith.constant 2 : i64
  %c17 = arith.constant 17 : i64
  %b2 = arith.muli %b, %c2 : i64
  %ci = arith.addi %b2, %c17 : i64
  %cap = func.call @nxsi_hg(%ci) : (i64) -> i64
  return %cap : i64
}

// the image at byte off; its word there, read and written
func.func private @nxsi_p(%off: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %b = func.call @nxsi_hg(%c0) : (i64) -> i64
  %bp = llvm.inttoptr %b : i64 to !llvm.ptr
  %p = llvm.getelementptr %bp[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p : !llvm.ptr
}
func.func private @nxsi_w(%off: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %z = arith.constant 0 : index
  %p = func.call @nxsi_p(%off) : (i64) -> !llvm.ptr
  %d = func.call @nxsi_d(%p, %c1) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %s = builtin.unrealized_conversion_cast %m : !m64 to !s64
  %v = trikeshed.at %s[%z] : !s64, index -> i64
  return %v : i64
}
func.func private @nxsi_ws(%off: i64, %v: i64) {
  %c1 = arith.constant 1 : i64
  %z = arith.constant 0 : index
  %p = func.call @nxsi_p(%off) : (i64) -> !llvm.ptr
  %d = func.call @nxsi_d(%p, %c1) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  memref.store %v, %m[%z] : !m64
  return
}
// The image's first words are summed as they are written: a word's part is its place and its value mixed, and word 15
// is the sum of the parts of words 0 to 14.  nxsi_hw writes one of them; nxsi_inc adds to one.
func.func private @nxsi_hw(%off: i64, %v: i64) {
  %c120 = arith.constant 120 : i64
  %old = func.call @nxsi_w(%off) : (i64) -> i64
  %a = func.call @nxsi_mix(%off, %old) : (i64, i64) -> i64
  %b = func.call @nxsi_mix(%off, %v) : (i64, i64) -> i64
  %s = func.call @nxsi_w(%c120) : (i64) -> i64
  %s1 = arith.subi %s, %a : i64
  %s2 = arith.addi %s1, %b : i64
  func.call @nxsi_ws(%off, %v) : (i64, i64) -> ()
  func.call @nxsi_ws(%c120, %s2) : (i64, i64) -> ()
  return
}
func.func private @nxsi_inc(%off: i64, %by: i64) {
  %v = func.call @nxsi_w(%off) : (i64) -> i64
  %v1 = arith.addi %v, %by : i64
  func.call @nxsi_hw(%off, %v1) : (i64, i64) -> ()
  return
}
// the sum of the n words from off on, each mixed with its place from `base` (a fold of the places)
func.func private @nxsi_parts(%base: i64, %off: i64, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %x = arith.index_cast %i : index to i64
    trikeshed.yield %x : i64
  }
  %s = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %i: i64):
    %i8 = arith.muli %i, %c8 : i64
    %at = arith.addi %off, %i8 : i64
    %rel = arith.subi %at, %base : i64
    %w = func.call @nxsi_w(%at) : (i64) -> i64
    %p = func.call @nxsi_mix(%rel, %w) : (i64, i64) -> i64
    %a = arith.addi %acc, %p : i64
    trikeshed.yield %a : i64
  }
  return %s : i64
}

// This boot's name as a word (never 0; 1 when the system gives none): asked of the system once.
func.func private @nxsi_boot() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c64 = arith.constant 64 : i64
  %z = arith.constant 0 : index
  %i8 = arith.constant 8 : index
  %had = func.call @nxsi_hg(%c10) : (i64) -> i64
  %asked = arith.cmpi ne, %had, %c0 : i64
  %r = scf.if %asked -> (i64) {
    scf.yield %had : i64
  } else {
    %buf = llvm.alloca %c8 x i64 : (i64) -> !llvm.ptr
    %bd = func.call @nxsi_d(%buf, %c8) : (!llvm.ptr, i64) -> !d
    %bm = builtin.unrealized_conversion_cast %bd : !d to !m64
    %zg = memref.get_global @nxsi_zero : memref<32xi64>
    %zs = trikeshed.text %zg : memref<32xi64> -> !s64
    %z8 = trikeshed.slice %zs[%z, %i8] : !s64 -> !s64
    %e = trikeshed.drain %z8, %bm : !s64, !m64 -> index
    %n = func.call @nixsi_os_boot(%buf, %c64) : (!llvm.ptr, i64) -> i64
    %has = arith.cmpi sgt, %n, %c0 : i64
    %s = func.call @nxsi_sum(%buf, %c8, %n) : (!llvm.ptr, i64, i64) -> i64
    %s2 = arith.ori %s, %c2 : i64
    %v = arith.select %has, %s2, %c1 : i64
    func.call @nxsi_hs(%c10, %v) : (i64, i64) -> ()
    scf.yield %v : i64
  }
  return %r : i64
}

// The image holds an index: enough of it to read, the magic, a heap's end inside the file at a word, this boot's name
// (what was written before the system last started may not all have reached the disk: it is not read), and the first
// words' sum.
func.func private @nxsi_ok() -> i1 {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c15 = arith.constant 15 : i64
  %c72 = arith.constant 72 : i64
  %c120 = arith.constant 120 : i64
  %c256 = arith.constant 256 : i64
  %magic = arith.constant 5569912916071893297 : i64
  %size = func.call @nxsi_hg(%c4) : (i64) -> i64
  %big = arith.cmpi sge, %size, %c256 : i64
  %r = scf.if %big -> (i1) {
    %w0 = func.call @nxsi_w(%c0) : (i64) -> i64
    %end = func.call @nxsi_w(%c8) : (i64) -> i64
    %boot = func.call @nxsi_w(%c72) : (i64) -> i64
    %sum = func.call @nxsi_w(%c120) : (i64) -> i64
    %mine = func.call @nxsi_boot() : () -> i64
    %parts = func.call @nxsi_parts(%c0, %c0, %c15) : (i64, i64, i64) -> i64
    %m = arith.cmpi eq, %w0, %magic : i64
    %e1 = arith.cmpi sge, %end, %c256 : i64
    %e2 = arith.cmpi sle, %end, %size : i64
    %low = arith.andi %end, %c7 : i64
    %e3 = arith.cmpi eq, %low, %c0 : i64
    %e4 = arith.cmpi eq, %boot, %mine : i64
    %e5 = arith.cmpi eq, %sum, %parts : i64
    %a = arith.andi %m, %e1 : i1
    %b = arith.andi %a, %e2 : i1
    %c = arith.andi %b, %e3 : i1
    %d = arith.andi %c, %e4 : i1
    %e = arith.andi %d, %e5 : i1
    scf.yield %e : i1
  } else {
    scf.yield %big : i1
  }
  return %r : i1
}

// An empty index in the image (the file 64 KiB at least, never cut): no row, no root, no token, this boot's name; the
// words' sum, and the magic last.  False when the file cannot be made that long.
func.func private @nxsi_init() -> i1 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c15 = arith.constant 15 : i64
  %c32 = arith.constant 32 : i64
  %c120 = arith.constant 120 : i64
  %c256 = arith.constant 256 : i64
  %c65536 = arith.constant 65536 : i64
  %magic = arith.constant 5569912916071893297 : i64
  %z32 = arith.constant 0 : i32
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %size = func.call @nxsi_hg(%c4) : (i64) -> i64
  %isfile = arith.cmpi eq, %kind, %c1 : i64
  %short = arith.cmpi slt, %size, %c65536 : i64
  %grow = arith.andi %isfile, %short : i1
  scf.if %grow {
    %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
    %fd = arith.trunci %fd64 : i64 to i32
    %rc = func.call @ftruncate(%fd, %c65536) : (i32, i64) -> i32
    %done = arith.cmpi eq, %rc, %z32 : i32
    scf.if %done {
      func.call @nxsi_hs(%c4, %c65536) : (i64, i64) -> ()
    }
  }
  %size1 = func.call @nxsi_hg(%c4) : (i64) -> i64
  %room = arith.cmpi sge, %size1, %c65536 : i64
  scf.if %room {
    %boot = func.call @nxsi_boot() : () -> i64
    %p = func.call @nxsi_p(%c0) : (i64) -> !llvm.ptr
    %d = func.call @nxsi_d(%p, %c32) : (!llvm.ptr, i64) -> !d
    %m = builtin.unrealized_conversion_cast %d : !d to !m64
    %i32x = arith.constant 32 : index
    %i1x = arith.constant 1 : index
    %i9x = arith.constant 9 : index
    %first = trikeshed.series %i32x : !s64 {
    ^bb0(%i: index):
      %isend = arith.cmpi eq, %i, %i1x : index
      %isboot = arith.cmpi eq, %i, %i9x : index
      %w1 = arith.select %isend, %c256, %c0 : i64
      %w = arith.select %isboot, %boot, %w1 : i64
      trikeshed.yield %w : i64
    }
    %e = trikeshed.drain %first, %m : !s64, !m64 -> index
    %parts = func.call @nxsi_parts(%c0, %c0, %c15) : (i64, i64, i64) -> i64
    func.call @nxsi_ws(%c120, %parts) : (i64, i64) -> ()
    func.call @nxsi_hw(%c0, %magic) : (i64, i64) -> ()
    func.call @nxsi_forget() : () -> ()
  }
  return %room : i1
}

// The heap's next n bytes (n a multiple of 8): where they begin, or 0 when the file cannot grow to hold them (a quarter
// more each time, 64 KiB at least; the mapping is 64 GiB, more than a store's index).  The end moves before they are
// used: what is written and never linked is room lost, nothing else.
func.func private @nxsi_room(%n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c65535 = arith.constant 65535 : i64
  %cm65536 = arith.constant -65536 : i64
  %limit = arith.constant 68719476736 : i64
  %z32 = arith.constant 0 : i32
  %off = func.call @nxsi_w(%c8) : (i64) -> i64
  %need = arith.addi %off, %n : i64
  %size = func.call @nxsi_hg(%c4) : (i64) -> i64
  %short = arith.cmpi sgt, %need, %size : i64
  %ok = scf.if %short -> (i1) {
    %q = arith.shrui %size, %c2 : i64
    %more = arith.addi %size, %q : i64
    %want = arith.maxsi %need, %more : i64
    %up0 = arith.addi %want, %c65535 : i64
    %up = arith.andi %up0, %cm65536 : i64
    %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
    %isfile = arith.cmpi eq, %kind, %c1 : i64
    %within = arith.cmpi sle, %up, %limit : i64
    %can = arith.andi %isfile, %within : i1
    %grown = scf.if %can -> (i1) {
      %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
      %fd = arith.trunci %fd64 : i64 to i32
      %rc = func.call @ftruncate(%fd, %up) : (i32, i64) -> i32
      %done = arith.cmpi eq, %rc, %z32 : i32
      scf.if %done {
        func.call @nxsi_hs(%c4, %up) : (i64, i64) -> ()
      }
      scf.yield %done : i1
    } else {
      scf.yield %can : i1
    }
    scf.yield %grown : i1
  } else {
    %yes = arith.constant 1 : i1
    scf.yield %yes : i1
  }
  %r = scf.if %ok -> (i64) {
    func.call @nxsi_hw(%c8, %need) : (i64, i64) -> ()
    scf.yield %off : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

// the first word of the blob at off, or 0 when off is not a blob's place (below the heap, at its end, not at a word)
func.func private @nxsi_tag(%off: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c24 = arith.constant 24 : i64
  %c256 = arith.constant 256 : i64
  %end = func.call @nxsi_w(%c8) : (i64) -> i64
  %a = arith.cmpi sge, %off, %c256 : i64
  %past = arith.addi %off, %c24 : i64
  %b = arith.cmpi sle, %past, %end : i64
  %low = arith.andi %off, %c7 : i64
  %c = arith.cmpi eq, %low, %c0 : i64
  %ab = arith.andi %a, %b : i1
  %abc = arith.andi %ab, %c : i1
  %t = scf.if %abc -> (i64) {
    %w = func.call @nxsi_w(%off) : (i64) -> i64
    scf.yield %w : i64
  } else {
    scf.yield %c0 : i64
  }
  return %t : i64
}

// A blob found whole is not summed again while its stamp (the word of it that changes whenever it does) stays: 4,096
// places, by the blob's own.
func.func private @nxsi_known(%off: i64, %stamp: i64) -> i1 {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c11 = arith.constant 11 : i64
  %c4095 = arith.constant 4095 : i64
  %c8192 = arith.constant 8192 : i64
  %c65536 = arith.constant 65536 : i64
  %had = func.call @nxsi_cap(%c11) : (i64) -> i64
  %p = func.call @nxsi_buf(%c11, %c65536) : (i64, i64) -> !llvm.ptr
  %d = func.call @nxsi_d(%p, %c8192) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %fresh = arith.cmpi slt, %had, %c65536 : i64
  scf.if %fresh {
    %i8192 = arith.constant 8192 : index
    %zeros = trikeshed.series %i8192 : !s64 {
    ^bb0(%i: index):
      %zw = arith.constant 0 : i64
      trikeshed.yield %zw : i64
    }
    %e = trikeshed.drain %zeros, %m : !s64, !m64 -> index
  }
  %s = builtin.unrealized_conversion_cast %m : !m64 to !s64
  %sl0 = arith.shrui %off, %c3 : i64
  %sl = arith.andi %sl0, %c4095 : i64
  %a0 = arith.muli %sl, %c2 : i64
  %a1 = arith.addi %a0, %c1 : i64
  %a0i = arith.index_cast %a0 : i64 to index
  %a1i = arith.index_cast %a1 : i64 to index
  %o = trikeshed.at %s[%a0i] : !s64, index -> i64
  %st = trikeshed.at %s[%a1i] : !s64, index -> i64
  %so = arith.cmpi eq, %o, %off : i64
  %ss = arith.cmpi eq, %st, %stamp : i64
  %hit = arith.andi %so, %ss : i1
  return %hit : i1
}
func.func private @nxsi_note(%off: i64, %stamp: i64) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c11 = arith.constant 11 : i64
  %c4095 = arith.constant 4095 : i64
  %c8192 = arith.constant 8192 : i64
  %c65536 = arith.constant 65536 : i64
  %known = func.call @nxsi_known(%off, %stamp) : (i64, i64) -> i1
  %p = func.call @nxsi_buf(%c11, %c65536) : (i64, i64) -> !llvm.ptr
  %d = func.call @nxsi_d(%p, %c8192) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %sl0 = arith.shrui %off, %c3 : i64
  %sl = arith.andi %sl0, %c4095 : i64
  %a0 = arith.muli %sl, %c2 : i64
  %a1 = arith.addi %a0, %c1 : i64
  %a0i = arith.index_cast %a0 : i64 to index
  %a1i = arith.index_cast %a1 : i64 to index
  memref.store %off, %m[%a0i] : !m64
  memref.store %stamp, %m[%a1i] : !m64
  return
}
// what this process found whole, forgotten: the file is not as the process last saw it
func.func private @nxsi_forget() {
  %c11 = arith.constant 11 : i64
  %c8192 = arith.constant 8192 : i64
  %c65536 = arith.constant 65536 : i64
  %had = func.call @nxsi_cap(%c11) : (i64) -> i64
  %has = arith.cmpi sge, %had, %c65536 : i64
  scf.if %has {
    %p = func.call @nxsi_buf(%c11, %c65536) : (i64, i64) -> !llvm.ptr
    %d = func.call @nxsi_d(%p, %c8192) : (!llvm.ptr, i64) -> !d
    %m = builtin.unrealized_conversion_cast %d : !d to !m64
    %i8192 = arith.constant 8192 : index
    %zeros = trikeshed.series %i8192 : !s64 {
    ^bb0(%i: index):
      %zw = arith.constant 0 : i64
      trikeshed.yield %zw : i64
    }
    %e = trikeshed.drain %zeros, %m : !s64, !m64 -> index
  }
  return
}

//===----------------------------------------------------------------------===//
// Keys and records
//===----------------------------------------------------------------------===//

// The key of a name: its first 13 bytes, 5 bits each (a nix32 digit's place in the alphabet), the top 64 of the 65: the
// hash part's leading bits in the order of its text.  A shorter name counts as zeros after it.
func.func private @nxsi_key(%p: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c12 = arith.constant 12 : i64
  %z = arith.constant 0 : index
  %i12 = arith.constant 12 : index
  %d = func.call @nxsi_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m
  %bs = builtin.unrealized_conversion_cast %m : !m to !s
  %cg = memref.get_global @nxsi_code : memref<256xi8>
  %code = trikeshed.text %cg : memref<256xi8> -> !s
  %lead = arith.minsi %n, %c12 : i64
  %leadi = arith.index_cast %lead : i64 to index
  %head = trikeshed.slice %bs[%z, %leadi] : !s -> !s
  %acc = trikeshed.fold %head, %c0 : !s, i64 -> i64 {
  ^bb0(%a: i64, %b: i8):
    %bi = arith.index_castui %b : i8 to index
    %c8 = trikeshed.at %code[%bi] : !s, index -> i8
    %c = arith.extui %c8 : i8 to i64
    %sh = arith.shli %a, %c5 : i64
    %r = arith.ori %sh, %c : i64
    trikeshed.yield %r : i64
  }
  %missing = arith.subi %c12, %lead : i64
  %padbits = arith.muli %missing, %c5 : i64
  %a12 = arith.shli %acc, %padbits : i64
  %has13 = arith.cmpi sgt, %n, %c12 : i64
  %last = scf.if %has13 -> (i64) {
    %b12 = trikeshed.at %bs[%i12] : !s, index -> i8
    %b12i = arith.index_castui %b12 : i8 to index
    %c13 = trikeshed.at %code[%b12i] : !s, index -> i8
    %c13w = arith.extui %c13 : i8 to i64
    %top4 = arith.shrui %c13w, %c1 : i64
    scf.yield %top4 : i64
  } else {
    scf.yield %c0 : i64
  }
  %k0 = arith.shli %a12, %c4 : i64
  %key = arith.ori %k0, %last : i64
  return %key : i64
}

// Whether a name is a valid path's as allValidPaths took them from the directory: 34 bytes at least and no ".tmp" in
// it (one fold of its bytes: how much of ".tmp" the bytes before end with).
func.func private @nxsi_listed(%p: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %c34 = arith.constant 34 : i64
  %dot = arith.constant 46 : i8
  %d = func.call @nxsi_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m
  %bs = builtin.unrealized_conversion_cast %m : !m to !s
  %wg = memref.get_global @nxsi_words : memref<16xi8>
  %words = trikeshed.text %wg : memref<16xi8> -> !s
  %st = trikeshed.fold %bs, %c0 : !s, i64 -> i64 {
  ^bb0(%a: i64, %b: i8):
    %found = arith.cmpi eq, %a, %c4 : i64
    %ai0 = arith.minsi %a, %c1 : i64
    %ai1 = arith.select %found, %ai0, %a : i64
    %ai = arith.index_cast %ai1 : i64 to index
    %want = trikeshed.at %words[%ai] : !s, index -> i8
    %hit = arith.cmpi eq, %b, %want : i8
    %isdot = arith.cmpi eq, %b, %dot : i8
    %next = arith.addi %a, %c1 : i64
    %again = arith.select %isdot, %c1, %c0 : i64
    %step = arith.select %hit, %next, %again : i64
    %r = arith.select %found, %c4, %step : i64
    trikeshed.yield %r : i64
  }
  %tmp = arith.cmpi eq, %st, %c4 : i64
  %long = arith.cmpi sge, %n, %c34 : i64
  %no = arith.xori %tmp, %long : i1
  %both = arith.andi %no, %long : i1
  %r = arith.extui %both : i1 to i64
  return %r : i64
}

// The record at x: its first word when it reads back whole (a record, its name and text inside the heap, its sum),
// else 0.
func.func private @nxsi_rec(%x: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c255 = arith.constant 255 : i64
  %c65535 = arith.constant 65535 : i64
  %cm8 = arith.constant -8 : i64
  %t = func.call @nxsi_tag(%x) : (i64) -> i64
  %kind = arith.andi %t, %c255 : i64
  %isrec = arith.cmpi eq, %kind, %c1 : i64
  %r = scf.if %isrec -> (i64) {
    %nl0 = arith.shrui %t, %c16 : i64
    %nl = arith.andi %nl0, %c65535 : i64
    %tl = arith.shrui %t, %c32 : i64
    %by0 = arith.addi %nl, %tl : i64
    %by1 = arith.addi %by0, %c7 : i64
    %body = arith.andi %by1, %cm8 : i64
    %end = func.call @nxsi_w(%c8) : (i64) -> i64
    %x24 = arith.addi %x, %c24 : i64
    %past = arith.addi %x24, %body : i64
    %fits = arith.cmpi sle, %past, %end : i64
    %rr = scf.if %fits -> (i64) {
      %x16 = arith.addi %x, %c16 : i64
      %stamp = func.call @nxsi_w(%x16) : (i64) -> i64
      %known = func.call @nxsi_known(%x, %stamp) : (i64, i64) -> i1
      %ok = scf.if %known -> (i1) {
        scf.yield %known : i1
      } else {
        %x8 = arith.addi %x, %c8 : i64
        %id = func.call @nxsi_w(%x8) : (i64) -> i64
        %seed = arith.xori %t, %id : i64
        %bp = func.call @nxsi_p(%x24) : (i64) -> !llvm.ptr
        %bw = arith.shrui %body, %c3 : i64
        %got = func.call @nxsi_sum(%bp, %bw, %seed) : (!llvm.ptr, i64, i64) -> i64
        %same = arith.cmpi eq, %got, %stamp : i64
        scf.if %same {
          func.call @nxsi_note(%x, %stamp) : (i64, i64) -> ()
        }
        scf.yield %same : i1
      }
      %tt = arith.select %ok, %t, %c0 : i64
      scf.yield %tt : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// The trie
//===----------------------------------------------------------------------===//

// the running sum of n words, begun at s: each word mixed into the 32 bits before it (so one more row is two steps)
func.func private @nxsi_rowsum(%p: !llvm.ptr, %n: i64, %s: i64) -> i64 {
  %mask = arith.constant 4294967295 : i64
  %d = func.call @nxsi_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %ws = builtin.unrealized_conversion_cast %m : !m64 to !s64
  %r = trikeshed.fold %ws, %s : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %w: i64):
    %x = func.call @nxsi_mix(%acc, %w) : (i64, i64) -> i64
    %x32 = arith.andi %x, %mask : i64
    trikeshed.yield %x32 : i64
  }
  return %r : i64
}

// The rows of the leaf at ref (tag: its first word) when it reads back whole (its room no more than a page's rows, its
// rows no more than its room, inside the heap, their running sum the one it carries), else -1.
func.func private @nxsi_leaf_n(%ref: i64, %tag: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c1024 = arith.constant 1024 : i64
  %mask = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %cap = arith.shrui %tag, %c32 : i64
  %r8 = arith.addi %ref, %c8 : i64
  %r16 = arith.addi %ref, %c16 : i64
  %w1 = func.call @nxsi_w(%r8) : (i64) -> i64
  %cnt = arith.andi %w1, %mask : i64
  %s = arith.shrui %w1, %c32 : i64
  %end = func.call @nxsi_w(%c8) : (i64) -> i64
  %bytes = arith.muli %cap, %c16 : i64
  %past = arith.addi %r16, %bytes : i64
  %a = arith.cmpi ule, %cap, %c1024 : i64
  %b = arith.cmpi ule, %cnt, %cap : i64
  %c = arith.cmpi sle, %past, %end : i64
  %ab = arith.andi %a, %b : i1
  %shape = arith.andi %ab, %c : i1
  %r = scf.if %shape -> (i64) {
    %known = func.call @nxsi_known(%ref, %w1) : (i64, i64) -> i1
    %ok = scf.if %known -> (i1) {
      scf.yield %known : i1
    } else {
      %rp = func.call @nxsi_p(%r16) : (i64) -> !llvm.ptr
      %nw = arith.muli %cnt, %c2 : i64
      %got = func.call @nxsi_rowsum(%rp, %nw, %c0) : (!llvm.ptr, i64, i64) -> i64
      %same = arith.cmpi eq, %got, %s : i64
      scf.if %same {
        func.call @nxsi_note(%ref, %w1) : (i64, i64) -> ()
      }
      scf.yield %same : i1
    }
    %n = arith.select %ok, %cnt, %m1 : i64
    scf.yield %n : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// a leaf of relation rel with room for cap rows, none yet: its place, 0 when the heap has no room
func.func private @nxsi_leaf(%rel: i64, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %rows = arith.muli %cap, %c16 : i64
  %bytes = arith.addi %rows, %c16 : i64
  %off = func.call @nxsi_room(%bytes) : (i64) -> i64
  %has = arith.cmpi ne, %off, %c0 : i64
  scf.if %has {
    %rs = arith.shli %rel, %c8 : i64
    %cs = arith.shli %cap, %c32 : i64
    %t0 = arith.ori %rs, %c2 : i64
    %t = arith.ori %t0, %cs : i64
    %o8 = arith.addi %off, %c8 : i64
    func.call @nxsi_ws(%off, %t) : (i64, i64) -> ()
    func.call @nxsi_ws(%o8, %c0) : (i64, i64) -> ()
  }
  return %off : i64
}

// The full leaf at ref sealed: its rows as a page (nixsi_page_seal: room for them as they are, what the page leaves
// given back), and a node over the page with no child yet.  The node's place; 0 when the heap has no room.
func.func private @nxsi_seal(%ref: i64, %rel: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c256 = arith.constant 256 : i64
  %c1024 = arith.constant 1024 : i64
  %c2064 = arith.constant 2064 : i64
  %c16408 = arith.constant 16408 : i64
  %page = func.call @nxsi_room(%c16408) : (i64) -> i64
  %has = arith.cmpi ne, %page, %c0 : i64
  %r = scf.if %has -> (i64) {
    %r16 = arith.addi %ref, %c16 : i64
    %rp = func.call @nxsi_p(%r16) : (i64) -> !llvm.ptr
    %pp = func.call @nxsi_p(%page) : (i64) -> !llvm.ptr
    %rs = arith.shli %rel, %c8 : i64
    %total = func.call @nixsi_page_seal(%rp, %c1024, %rs, %pp, %c16408) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
    %pend = arith.addi %page, %total : i64
    func.call @nxsi_hw(%c8, %pend) : (i64, i64) -> ()
    %node = func.call @nxsi_room(%c2064) : (i64) -> i64
    %hasn = arith.cmpi ne, %node, %c0 : i64
    scf.if %hasn {
      %n16 = arith.addi %node, %c16 : i64
      %n8 = arith.addi %node, %c8 : i64
      %kp = func.call @nxsi_p(%n16) : (i64) -> !llvm.ptr
      %kd = func.call @nxsi_d(%kp, %c256) : (!llvm.ptr, i64) -> !d
      %km = builtin.unrealized_conversion_cast %kd : !d to !m64
      %i256 = arith.constant 256 : index
      %none = trikeshed.series %i256 : !s64 {
      ^bb0(%i: index):
        %zw = arith.constant 0 : i64
        trikeshed.yield %zw : i64
      }
      %e = trikeshed.drain %none, %km : !s64, !m64 -> index
      func.call @nxsi_ws(%n8, %page) : (i64, i64) -> ()
      %sum = func.call @nxsi_node_sum(%node) : (i64) -> i64
      %ss = arith.shli %sum, %c16 : i64
      %t0 = arith.ori %rs, %c4 : i64
      %t = arith.ori %t0, %ss : i64
      func.call @nxsi_ws(%node, %t) : (i64, i64) -> ()
    }
    scf.yield %node : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

// A node's sum, the 48 bits its first word carries above its kind and relation: its page's and its children's places,
// each mixed with where it stands in the node.
func.func private @nxsi_node_sum(%node: i64) -> i64 {
  %c8 = arith.constant 8 : i64
  %c257 = arith.constant 257 : i64
  %mask = arith.constant 281474976710655 : i64
  %n8 = arith.addi %node, %c8 : i64
  %s = func.call @nxsi_parts(%node, %n8, %c257) : (i64, i64, i64) -> i64
  %s48 = arith.andi %s, %mask : i64
  return %s48 : i64
}
// The node at ref (tag: its first word) reads back whole: it is inside the heap and its sum is the one it carries
// (summed once while its first word stays).
func.func private @nxsi_node_ok(%ref: i64, %tag: i64) -> i1 {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c2064 = arith.constant 2064 : i64
  %end = func.call @nxsi_w(%c8) : (i64) -> i64
  %past = arith.addi %ref, %c2064 : i64
  %fits = arith.cmpi sle, %past, %end : i64
  %r = scf.if %fits -> (i1) {
    %known = func.call @nxsi_known(%ref, %tag) : (i64, i64) -> i1
    %ok = scf.if %known -> (i1) {
      scf.yield %known : i1
    } else {
      %got = func.call @nxsi_node_sum(%ref) : (i64) -> i64
      %has = arith.shrui %tag, %c16 : i64
      %same = arith.cmpi eq, %got, %has : i64
      scf.if %same {
        func.call @nxsi_note(%ref, %tag) : (i64, i64) -> ()
      }
      scf.yield %same : i1
    }
    scf.yield %ok : i1
  } else {
    scf.yield %fits : i1
  }
  return %r : i1
}
// The word at slot made v: a root (par 0: one of the image's first words) or a child of the node at par, whose sum
// follows.
func.func private @nxsi_link(%par: i64, %slot: i64, %v: i64) {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %c65535 = arith.constant 65535 : i64
  %mask = arith.constant 281474976710655 : i64
  %root = arith.cmpi eq, %par, %c0 : i64
  scf.if %root {
    func.call @nxsi_hw(%slot, %v) : (i64, i64) -> ()
  } else {
    %rel = arith.subi %slot, %par : i64
    %old = func.call @nxsi_w(%slot) : (i64) -> i64
    %a = func.call @nxsi_mix(%rel, %old) : (i64, i64) -> i64
    %b = func.call @nxsi_mix(%rel, %v) : (i64, i64) -> i64
    %tag = func.call @nxsi_w(%par) : (i64) -> i64
    %s = arith.shrui %tag, %c16 : i64
    %s1 = arith.subi %s, %a : i64
    %s2 = arith.addi %s1, %b : i64
    %s3 = arith.andi %s2, %mask : i64
    %low = arith.andi %tag, %c65535 : i64
    %ss = arith.shli %s3, %c16 : i64
    %t = arith.ori %low, %ss : i64
    func.call @nxsi_ws(%slot, %v) : (i64, i64) -> ()
    func.call @nxsi_ws(%par, %t) : (i64, i64) -> ()
    func.call @nxsi_note(%par, %t) : (i64, i64) -> ()
  }
  return
}

// A row for the leaf at ref, which the word at sl names (a root, or a child of the node at par): appended when the leaf
// has room (the row, then its count and sum in one word); a leaf of fewer than 1,024 rows' room is first copied into one
// of four times as much (one drain), a full one sealed under a node, and the row then goes down again.  1 done, 2
// again, 0 no room, -1 not a leaf.
func.func private @nxsi_leaf_add(%par: i64, %sl: i64, %ref: i64, %tag: i64, %rel: i64, %key: i64, %val: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c1024 = arith.constant 1024 : i64
  %mask = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %n = func.call @nxsi_leaf_n(%ref, %tag) : (i64, i64) -> i64
  %whole = arith.cmpi sge, %n, %c0 : i64
  %r = scf.if %whole -> (i64) {
    %cap = arith.shrui %tag, %c32 : i64
    %r8 = arith.addi %ref, %c8 : i64
    %r16 = arith.addi %ref, %c16 : i64
    %w1 = func.call @nxsi_w(%r8) : (i64) -> i64
    %room = arith.cmpi ult, %n, %cap : i64
    %rr = scf.if %room -> (i64) {
      %at0 = arith.muli %n, %c16 : i64
      %at = arith.addi %r16, %at0 : i64
      %at8 = arith.addi %at, %c8 : i64
      func.call @nxsi_ws(%at, %key) : (i64, i64) -> ()
      func.call @nxsi_ws(%at8, %val) : (i64, i64) -> ()
      %s = arith.shrui %w1, %c32 : i64
      %s1a = func.call @nxsi_mix(%s, %key) : (i64, i64) -> i64
      %s1 = arith.andi %s1a, %mask : i64
      %s2a = func.call @nxsi_mix(%s1, %val) : (i64, i64) -> i64
      %s2 = arith.andi %s2a, %mask : i64
      %n1 = arith.addi %n, %c1 : i64
      %ss = arith.shli %s2, %c32 : i64
      %nw1 = arith.ori %n1, %ss : i64
      func.call @nxsi_ws(%r8, %nw1) : (i64, i64) -> ()
      func.call @nxsi_note(%ref, %nw1) : (i64, i64) -> ()
      %rel8 = arith.muli %rel, %c8 : i64
      %cw = arith.addi %rel8, %c48 : i64
      func.call @nxsi_inc(%cw, %c1) : (i64, i64) -> ()
      scf.yield %c1 : i64
    } else {
      %small = arith.cmpi ult, %cap, %c1024 : i64
      %rg = scf.if %small -> (i64) {
        %cap4 = arith.muli %cap, %c4 : i64
        %l2 = arith.minsi %cap4, %c1024 : i64
        %big = func.call @nxsi_leaf(%rel, %l2) : (i64, i64) -> i64
        %hasb = arith.cmpi ne, %big, %c0 : i64
        scf.if %hasb {
          %nw = arith.muli %n, %c2 : i64
          %sp = func.call @nxsi_p(%r16) : (i64) -> !llvm.ptr
          %sd = func.call @nxsi_d(%sp, %nw) : (!llvm.ptr, i64) -> !d
          %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
          %src = builtin.unrealized_conversion_cast %sm : !m64 to !s64
          %b16 = arith.addi %big, %c16 : i64
          %b8 = arith.addi %big, %c8 : i64
          %dp = func.call @nxsi_p(%b16) : (i64) -> !llvm.ptr
          %dd = func.call @nxsi_d(%dp, %nw) : (!llvm.ptr, i64) -> !d
          %dm = builtin.unrealized_conversion_cast %dd : !d to !m64
          %e = trikeshed.drain %src, %dm : !s64, !m64 -> index
          func.call @nxsi_ws(%b8, %w1) : (i64, i64) -> ()
          func.call @nxsi_link(%par, %sl, %big) : (i64, i64, i64) -> ()
        }
        %st = arith.select %hasb, %c2, %c0 : i64
        scf.yield %st : i64
      } else {
        %node = func.call @nxsi_seal(%ref, %rel) : (i64, i64) -> i64
        %hasn = arith.cmpi ne, %node, %c0 : i64
        scf.if %hasn {
          func.call @nxsi_link(%par, %sl, %node) : (i64, i64, i64) -> ()
        }
        %st = arith.select %hasn, %c2, %c0 : i64
        scf.yield %st : i64
      }
      scf.yield %rg : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// the child of a node a key goes by at depth d: the key's byte there, the first child past its eight bytes
func.func private @nxsi_child(%key: i64, %d: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c255 = arith.constant 255 : i64
  %deep = arith.cmpi sge, %d, %c8 : i64
  %dd = arith.minsi %d, %c7 : i64
  %left = arith.subi %c7, %dd : i64
  %sh = arith.muli %left, %c8 : i64
  %b0 = arith.shrui %key, %sh : i64
  %b = arith.andi %b0, %c255 : i64
  %i = arith.select %deep, %c0, %b : i64
  return %i : i64
}

// A row put in relation rel (0 the paths, 1 the references): 1; 0 when the heap has no room; -1 when a blob on the way
// is not what its place says.  HashTrie's insert: down by the key's bytes to a leaf, a leaf opened where there is none.
// A child lies after its node in the heap (it was made later), so the way down ends.
func.func private @nxsi_put(%rel: i64, %key: i64, %val: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c255 = arith.constant 255 : i64
  %m1 = arith.constant -1 : i64
  %rel8 = arith.muli %rel, %c8 : i64
  %root = arith.addi %rel8, %c24 : i64
  %pe, %se, %de, %ste = scf.while (%par = %c0, %sl = %root, %d = %c0, %st = %c2) : (i64, i64, i64, i64) -> (i64, i64, i64, i64) {
    %going = arith.cmpi eq, %st, %c2 : i64
    scf.condition(%going) %par, %sl, %d, %st : i64, i64, i64, i64
  } do {
  ^bb0(%pa: i64, %sa: i64, %da: i64, %sta: i64):
    %ref0 = func.call @nxsi_w(%sa) : (i64) -> i64
    %empty = arith.cmpi eq, %ref0, %c0 : i64
    %ref = scf.if %empty -> (i64) {
      %leaf = func.call @nxsi_leaf(%rel, %c16) : (i64, i64) -> i64
      %hasl = arith.cmpi ne, %leaf, %c0 : i64
      scf.if %hasl {
        func.call @nxsi_link(%pa, %sa, %leaf) : (i64, i64, i64) -> ()
      }
      scf.yield %leaf : i64
    } else {
      scf.yield %ref0 : i64
    }
    %tag = func.call @nxsi_tag(%ref) : (i64) -> i64
    %kind = arith.andi %tag, %c255 : i64
    %noroom = arith.cmpi eq, %ref, %c0 : i64
    %after = arith.cmpi sgt, %ref, %pa : i64
    %isnode = arith.cmpi eq, %kind, %c4 : i64
    %np, %ns, %nd, %nst = scf.if %isnode -> (i64, i64, i64, i64) {
      %whole = func.call @nxsi_node_ok(%ref, %tag) : (i64, i64) -> i1
      %fits = arith.andi %whole, %after : i1
      %i = func.call @nxsi_child(%key, %da) : (i64, i64) -> i64
      %i8 = arith.muli %i, %c8 : i64
      %k0 = arith.addi %ref, %c16 : i64
      %ks = arith.addi %k0, %i8 : i64
      %d1 = arith.addi %da, %c1 : i64
      %st1 = arith.select %fits, %c2, %m1 : i64
      scf.yield %ref, %ks, %d1, %st1 : i64, i64, i64, i64
    } else {
      %isleaf0 = arith.cmpi eq, %kind, %c2 : i64
      %isleaf = arith.andi %isleaf0, %after : i1
      %st2 = scf.if %isleaf -> (i64) {
        %a = func.call @nxsi_leaf_add(%pa, %sa, %ref, %tag, %rel, %key, %val) : (i64, i64, i64, i64, i64, i64, i64) -> i64
        scf.yield %a : i64
      } else {
        %b = arith.select %noroom, %c0, %m1 : i64
        scf.yield %b : i64
      }
      scf.yield %pa, %sa, %da, %st2 : i64, i64, i64, i64
    }
    scf.yield %np, %ns, %nd, %nst : i64, i64, i64, i64
  }
  return %ste : i64
}

// The page at `page` when it is one and reads back whole (checked once while it stays): its bytes to the heap's end,
// else -1.
func.func private @nxsi_page_ok(%page: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c255 = arith.constant 255 : i64
  %m1 = arith.constant -1 : i64
  %z = arith.constant 0 : i64
  %t = func.call @nxsi_tag(%page) : (i64) -> i64
  %kind = arith.andi %t, %c255 : i64
  %isp = arith.cmpi eq, %kind, %c3 : i64
  %r = scf.if %isp -> (i64) {
    %end = func.call @nxsi_w(%c8) : (i64) -> i64
    %avail = arith.subi %end, %page : i64
    %p16 = arith.addi %page, %c16 : i64
    %stamp = func.call @nxsi_w(%p16) : (i64) -> i64
    %known = func.call @nxsi_known(%page, %stamp) : (i64, i64) -> i1
    %ok = scf.if %known -> (i1) {
      scf.yield %known : i1
    } else {
      %pp = func.call @nxsi_p(%page) : (i64) -> !llvm.ptr
      %n = func.call @nxsi_page_n(%pp, %avail, %c1) : (!llvm.ptr, i64, i64) -> i64
      %whole = arith.cmpi sge, %n, %z : i64
      scf.if %whole {
        func.call @nxsi_note(%page, %stamp) : (i64, i64) -> ()
      }
      scf.yield %whole : i1
    }
    %a = arith.select %ok, %avail, %m1 : i64
    scf.yield %a : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The values of rel's rows with this key, the first cap of them stored at out: how many there are, or -1 when a blob on
// the way is not sound.  HashTrie's get: down by the key's bytes, a bisect into the page of every node passed, and a
// scan of the leaf the way ends at (one fold of its words: a key, then its value).
func.func private @nxsi_find1(%rel: i64, %key: i64, %out: !llvm.ptr, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c255 = arith.constant 255 : i64
  %c2064 = arith.constant 2064 : i64
  %m1 = arith.constant -1 : i64
  %cm4 = arith.constant -4 : i64
  %rel8 = arith.muli %rel, %c8 : i64
  %rootw = arith.addi %rel8, %c24 : i64
  %root = func.call @nxsi_w(%rootw) : (i64) -> i64
  %od = func.call @nxsi_d(%out, %cap) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m64
  %re, %de, %ne = scf.while (%ref = %root, %d = %c0, %n = %c0) : (i64, i64, i64) -> (i64, i64, i64) {
    %more = arith.cmpi ne, %ref, %c0 : i64
    %fine = arith.cmpi sge, %n, %c0 : i64
    %run = arith.andi %more, %fine : i1
    scf.condition(%run) %ref, %d, %n : i64, i64, i64
  } do {
  ^bb0(%ra: i64, %da: i64, %na: i64):
    %tag = func.call @nxsi_tag(%ra) : (i64) -> i64
    %kind = arith.andi %tag, %c255 : i64
    %isnode = arith.cmpi eq, %kind, %c4 : i64
    %nr, %nd, %nn = scf.if %isnode -> (i64, i64, i64) {
      %fits = func.call @nxsi_node_ok(%ra, %tag) : (i64, i64) -> i1
      %cr, %cn = scf.if %fits -> (i64, i64) {
        %ra8 = arith.addi %ra, %c8 : i64
        %page = func.call @nxsi_w(%ra8) : (i64) -> i64
        %hasp = arith.cmpi ne, %page, %c0 : i64
        %got = scf.if %hasp -> (i64) {
          %avail = func.call @nxsi_page_ok(%page) : (i64) -> i64
          %whole = arith.cmpi sge, %avail, %c0 : i64
          %g = scf.if %whole -> (i64) {
            %left0 = arith.subi %cap, %na : i64
            %left = arith.maxsi %left0, %c0 : i64
            %na8 = arith.muli %na, %c8 : i64
            %op = llvm.getelementptr %out[%na8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %pp = func.call @nxsi_p(%page) : (i64) -> !llvm.ptr
            %k = func.call @nixsi_page_find(%pp, %avail, %key, %op, %left) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
            scf.yield %k : i64
          } else {
            scf.yield %m1 : i64
          }
          scf.yield %g : i64
        } else {
          scf.yield %c0 : i64
        }
        %i = func.call @nxsi_child(%key, %da) : (i64, i64) -> i64
        %i8 = arith.muli %i, %c8 : i64
        %k0 = arith.addi %ra, %c16 : i64
        %ks = arith.addi %k0, %i8 : i64
        %child = func.call @nxsi_w(%ks) : (i64) -> i64
        // a child lies after its node, or there is none
        %nochild = arith.cmpi eq, %child, %c0 : i64
        %later = arith.cmpi sgt, %child, %ra : i64
        %okc = arith.ori %nochild, %later : i1
        %badp = arith.cmpi slt, %got, %c0 : i64
        %yes = arith.constant 1 : i1
        %badc = arith.xori %okc, %yes : i1
        %bad = arith.ori %badp, %badc : i1
        %sum = arith.addi %na, %got : i64
        %n2 = arith.select %bad, %m1, %sum : i64
        scf.yield %child, %n2 : i64, i64
      } else {
        scf.yield %c0, %m1 : i64, i64
      }
      %d1 = arith.addi %da, %c1 : i64
      scf.yield %cr, %d1, %cn : i64, i64, i64
    } else {
      %isleaf = arith.cmpi eq, %kind, %c2 : i64
      %m = scf.if %isleaf -> (i64) {
        %cnt = func.call @nxsi_leaf_n(%ra, %tag) : (i64, i64) -> i64
        %whole = arith.cmpi sge, %cnt, %c0 : i64
        %f = scf.if %whole -> (i64) {
          %ra16 = arith.addi %ra, %c16 : i64
          %lp = func.call @nxsi_p(%ra16) : (i64) -> !llvm.ptr
          %nw = arith.muli %cnt, %c2 : i64
          %ld = func.call @nxsi_d(%lp, %nw) : (!llvm.ptr, i64) -> !d
          %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
          %lw = builtin.unrealized_conversion_cast %lm : !m64 to !s64
          // the fold's word: rows found << 2 | the key just read was this one << 1 | the next word is a value
          %st = trikeshed.fold %lw, %c0 : !s64, i64 -> i64 {
          ^bb0(%acc: i64, %w: i64):
            %phase = arith.andi %acc, %c1 : i64
            %isval = arith.cmpi eq, %phase, %c1 : i64
            %next = scf.if %isval -> (i64) {
              %mt0 = arith.shrui %acc, %c1 : i64
              %mt = arith.andi %mt0, %c1 : i64
              %found = arith.shrui %acc, %c2 : i64
              %hit = arith.cmpi eq, %mt, %c1 : i64
              %tot = arith.addi %na, %found : i64
              %room = arith.cmpi slt, %tot, %cap : i64
              %put = arith.andi %hit, %room : i1
              scf.if %put {
                %ti = arith.index_cast %tot : i64 to index
                memref.store %w, %om[%ti] : !m64
              }
              %f1 = arith.addi %found, %mt : i64
              %a1 = arith.shli %f1, %c2 : i64
              scf.yield %a1 : i64
            } else {
              %eq = arith.cmpi eq, %w, %key : i64
              %e = arith.extui %eq : i1 to i64
              %e1 = arith.shli %e, %c1 : i64
              %keep = arith.andi %acc, %cm4 : i64
              %a2 = arith.ori %keep, %e1 : i64
              %a3 = arith.ori %a2, %c1 : i64
              scf.yield %a3 : i64
            }
            trikeshed.yield %next : i64
          }
          %fnd = arith.shrui %st, %c2 : i64
          scf.yield %fnd : i64
        } else {
          scf.yield %m1 : i64
        }
        scf.yield %f : i64
      } else {
        scf.yield %m1 : i64
      }
      %badl = arith.cmpi slt, %m, %c0 : i64
      %suml = arith.addi %na, %m : i64
      %n3 = arith.select %badl, %m1, %suml : i64
      scf.yield %c0, %da, %n3 : i64, i64, i64
    }
    scf.yield %nr, %nd, %nn : i64, i64, i64
  }
  return %ne : i64
}

// The same into room b from its word `at` on, the room grown to hold them all: the words filled (at and the rows
// found), or -1.
func.func private @nxsi_find(%rel: i64, %key: i64, %b: i64, %at: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %c64 = arith.constant 64 : i64
  %m1 = arith.constant -1 : i64
  %w0 = arith.addi %at, %c64 : i64
  %b0 = arith.muli %w0, %c8 : i64
  %p0 = func.call @nxsi_buf(%b, %b0) : (i64, i64) -> !llvm.ptr
  %capb = func.call @nxsi_cap(%b) : (i64) -> i64
  %capw = arith.shrui %capb, %c3 : i64
  %left = arith.subi %capw, %at : i64
  %at8 = arith.muli %at, %c8 : i64
  %o0 = llvm.getelementptr %p0[%at8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n0 = func.call @nxsi_find1(%rel, %key, %o0, %left) : (i64, i64, !llvm.ptr, i64) -> i64
  %over = arith.cmpi sgt, %n0, %left : i64
  %n = scf.if %over -> (i64) {
    %w1 = arith.addi %at, %n0 : i64
    %b1 = arith.muli %w1, %c8 : i64
    %p1 = func.call @nxsi_buf(%b, %b1) : (i64, i64) -> !llvm.ptr
    %o1 = llvm.getelementptr %p1[%at8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n1 = func.call @nxsi_find1(%rel, %key, %o1, %n0) : (i64, i64, !llvm.ptr, i64) -> i64
    scf.yield %n1 : i64
  } else {
    scf.yield %n0 : i64
  }
  %bad = arith.cmpi slt, %n, %c0 : i64
  %tot = arith.addi %at, %n : i64
  %r = arith.select %bad, %m1, %tot : i64
  return %r : i64
}

// Every row at ref and below it, stored at out from row `at` on (cap rows of room): the next free row, -1 when a blob is
// not sound, -2 when the room is too little.  A leaf's rows are one drain, a page's its reading, a node's children a walk
// each; ref lies after `above`, the node it is a child of (0 for a root).
func.func private @nxsi_walk(%above: i64, %ref: i64, %out: !llvm.ptr, %at: i64, %cap: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c255 = arith.constant 255 : i64
  %m1 = arith.constant -1 : i64
  %m2 = arith.constant -2 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %i256 = arith.constant 256 : index
  %none = arith.cmpi eq, %ref, %c0 : i64
  %r = scf.if %none -> (i64) {
    scf.yield %at : i64
  } else {
    %tag0 = func.call @nxsi_tag(%ref) : (i64) -> i64
    %after = arith.cmpi sgt, %ref, %above : i64
    %tag = arith.select %after, %tag0, %c0 : i64
    %kind = arith.andi %tag, %c255 : i64
    %at16 = arith.muli %at, %c16 : i64
    %op = llvm.getelementptr %out[%at16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %left = arith.subi %cap, %at : i64
    %isleaf = arith.cmpi eq, %kind, %c2 : i64
    %rl = scf.if %isleaf -> (i64) {
      %n = func.call @nxsi_leaf_n(%ref, %tag) : (i64, i64) -> i64
      %whole = arith.cmpi sge, %n, %c0 : i64
      %fits = arith.cmpi sle, %n, %left : i64
      %go = arith.andi %whole, %fits : i1
      scf.if %go {
        %r16 = arith.addi %ref, %c16 : i64
        %lp = func.call @nxsi_p(%r16) : (i64) -> !llvm.ptr
        %nw = arith.muli %n, %c2 : i64
        %ld = func.call @nxsi_d(%lp, %nw) : (!llvm.ptr, i64) -> !d
        %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
        %lw = builtin.unrealized_conversion_cast %lm : !m64 to !s64
        %od = func.call @nxsi_d(%op, %nw) : (!llvm.ptr, i64) -> !d
        %om = builtin.unrealized_conversion_cast %od : !d to !m64
        %e = trikeshed.drain %lw, %om : !s64, !m64 -> index
      }
      %next = arith.addi %at, %n : i64
      %r1 = arith.select %fits, %next, %m2 : i64
      %r2 = arith.select %whole, %r1, %m1 : i64
      scf.yield %r2 : i64
    } else {
      %isnode = arith.cmpi eq, %kind, %c4 : i64
      %sound = scf.if %isnode -> (i1) {
        %nk = func.call @nxsi_node_ok(%ref, %tag) : (i64, i64) -> i1
        scf.yield %nk : i1
      } else {
        scf.yield %isnode : i1
      }
      %rn = scf.if %sound -> (i64) {
        %r8 = arith.addi %ref, %c8 : i64
        %page = func.call @nxsi_w(%r8) : (i64) -> i64
        %hasp = arith.cmpi ne, %page, %c0 : i64
        %a1 = scf.if %hasp -> (i64) {
          %avail = func.call @nxsi_page_ok(%page) : (i64) -> i64
          %whole = arith.cmpi sge, %avail, %c0 : i64
          %a = scf.if %whole -> (i64) {
            %pp = func.call @nxsi_p(%page) : (i64) -> !llvm.ptr
            %pn = func.call @nxsi_page_n(%pp, %avail, %c0) : (!llvm.ptr, i64, i64) -> i64
            %fits = arith.cmpi sle, %pn, %left : i64
            %b = scf.if %fits -> (i64) {
              %k = func.call @nixsi_page_rows(%pp, %avail, %op, %left) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
              %read = arith.cmpi sge, %k, %c0 : i64
              %nx = arith.addi %at, %k : i64
              %b1 = arith.select %read, %nx, %m1 : i64
              scf.yield %b1 : i64
            } else {
              scf.yield %m2 : i64
            }
            scf.yield %b : i64
          } else {
            scf.yield %m1 : i64
          }
          scf.yield %a : i64
        } else {
          scf.yield %at : i64
        }
        %an = scf.for %i = %z to %i256 step %one iter_args(%a = %a1) -> (i64) {
          %fine = arith.cmpi sge, %a, %c0 : i64
          %a2 = scf.if %fine -> (i64) {
            %i64x = arith.index_cast %i : index to i64
            %i8 = arith.muli %i64x, %c8 : i64
            %k0 = arith.addi %ref, %c16 : i64
            %ks = arith.addi %k0, %i8 : i64
            %child = func.call @nxsi_w(%ks) : (i64) -> i64
            %w = func.call @nxsi_walk(%ref, %child, %out, %a, %cap) : (i64, i64, !llvm.ptr, i64, i64) -> i64
            scf.yield %w : i64
          } else {
            scf.yield %a : i64
          }
          scf.yield %a2 : i64
        }
        scf.yield %an : i64
      } else {
        scf.yield %m1 : i64
      }
      scf.yield %rn : i64
    }
    scf.yield %rl : i64
  }
  return %r : i64
}

// Every row of relation rel, in room 7 (2 words a row): how many, or -1.  The count the index keeps sizes the room (no
// more than the heap could hold as leaves: a count is believed no further); when it is behind (a writer died between a
// row and its count, or the rows are in pages, which are shorter) the room is doubled and the walk made again, and
// rows that would be more than the heap's bytes are not rows.
func.func private @nxsi_rows(%rel: i64) -> i64 {
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c48 = arith.constant 48 : i64
  %c0 = arith.constant 0 : i64
  %c1024 = arith.constant 1024 : i64
  %m1 = arith.constant -1 : i64
  %m2 = arith.constant -2 : i64
  %rel8 = arith.muli %rel, %c8 : i64
  %cw = arith.addi %rel8, %c48 : i64
  %rw = arith.addi %rel8, %c24 : i64
  %cnt0 = func.call @nxsi_w(%cw) : (i64) -> i64
  %end = func.call @nxsi_w(%c8) : (i64) -> i64
  %lim = arith.shrui %end, %c4 : i64
  %cnt = arith.minui %cnt0, %lim : i64
  %cap0 = arith.addi %cnt, %c1024 : i64
  %ce, %ne = scf.while (%cap = %cap0, %n = %m2) : (i64, i64) -> (i64, i64) {
    %again = arith.cmpi eq, %n, %m2 : i64
    scf.condition(%again) %cap, %n : i64, i64
  } do {
  ^bb0(%ca: i64, %na: i64):
    %over0 = arith.addi %end, %c1024 : i64
    %over = arith.cmpi sgt, %ca, %over0 : i64
    %k = scf.if %over -> (i64) {
      scf.yield %m1 : i64
    } else {
      %bytes = arith.muli %ca, %c16 : i64
      %gp = func.call @nxsi_buf(%c7, %bytes) : (i64, i64) -> !llvm.ptr
      %root = func.call @nxsi_w(%rw) : (i64) -> i64
      %kk = func.call @nxsi_walk(%c0, %root, %gp, %c0, %ca) : (i64, i64, !llvm.ptr, i64, i64) -> i64
      scf.yield %kk : i64
    }
    %c2x = arith.muli %ca, %c2 : i64
    scf.yield %c2x, %k : i64, i64
  }
  return %ne : i64
}

// The paths' live rows: every row gathered (the fill), put in order by key and value, so that a row struck out is
// followed by its strike (the same key, its record | 1), and the records of the rows that are not, drained into room 8.
// Their count, or -1.
func.func private @nxsi_live_rows() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %lt32 = arith.constant -1 : i32
  %gt32 = arith.constant 1 : i32
  %z32 = arith.constant 0 : i32
  %i1 = arith.constant 1 : index
  %n = func.call @nxsi_rows(%c0) : (i64) -> i64
  %have = arith.cmpi sge, %n, %c0 : i64
  %r = scf.if %have -> (i64) {
    %gp = func.call @nxsi_buf(%c7, %c0) : (i64, i64) -> !llvm.ptr
    %n2 = arith.muli %n, %c2 : i64
    %gd = func.call @nxsi_d(%gp, %n2) : (!llvm.ptr, i64) -> !d
    %gm = builtin.unrealized_conversion_cast %gd : !d to !m64
    %gw = builtin.unrealized_conversion_cast %gm : !m64 to !s64
    %ni = arith.index_cast %n : i64 to index
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%i: index):
      %i64x = arith.index_cast %i : index to i64
      trikeshed.yield %i64x : i64
    }
    %ord = trikeshed.sorted %idx : !s64 -> !s64 by {
    ^bb0(%x: i64, %y: i64):
      %x2 = arith.muli %x, %c2 : i64
      %y2 = arith.muli %y, %c2 : i64
      %xi = arith.index_cast %x2 : i64 to index
      %yi = arith.index_cast %y2 : i64 to index
      %xi1 = arith.addi %xi, %i1 : index
      %yi1 = arith.addi %yi, %i1 : index
      %kx = trikeshed.at %gw[%xi] : !s64, index -> i64
      %ky = trikeshed.at %gw[%yi] : !s64, index -> i64
      %vx = trikeshed.at %gw[%xi1] : !s64, index -> i64
      %vy = trikeshed.at %gw[%yi1] : !s64, index -> i64
      %klt = arith.cmpi ult, %kx, %ky : i64
      %kgt = arith.cmpi ugt, %kx, %ky : i64
      %vlt = arith.cmpi ult, %vx, %vy : i64
      %vgt = arith.cmpi ugt, %vx, %vy : i64
      %cv1 = arith.select %vgt, %gt32, %z32 : i32
      %cv = arith.select %vlt, %lt32, %cv1 : i32
      %ck1 = arith.select %kgt, %gt32, %cv : i32
      %cmp = arith.select %klt, %lt32, %ck1 : i32
      trikeshed.yield %cmp : i32
    }
    %last = arith.subi %n, %c1 : i64
    %keep = trikeshed.where %idx : !s64 -> !s64 {
    ^bb0(%k: i64):
      %ki = arith.index_cast %k : i64 to index
      %e = trikeshed.at %ord[%ki] : !s64, index -> i64
      %e2 = arith.muli %e, %c2 : i64
      %ei = arith.index_cast %e2 : i64 to index
      %ei1 = arith.addi %ei, %i1 : index
      %key = trikeshed.at %gw[%ei] : !s64, index -> i64
      %val = trikeshed.at %gw[%ei1] : !s64, index -> i64
      %odd = arith.andi %val, %c1 : i64
      %row = arith.cmpi eq, %odd, %c0 : i64
      %more = arith.cmpi slt, %k, %last : i64
      %look = arith.andi %row, %more : i1
      %live = scf.if %look -> (i1) {
        %kn = arith.addi %ki, %i1 : index
        %f = trikeshed.at %ord[%kn] : !s64, index -> i64
        %f2 = arith.muli %f, %c2 : i64
        %fi = arith.index_cast %f2 : i64 to index
        %fi1 = arith.addi %fi, %i1 : index
        %nkey = trikeshed.at %gw[%fi] : !s64, index -> i64
        %nval = trikeshed.at %gw[%fi1] : !s64, index -> i64
        %strike = arith.ori %val, %c1 : i64
        %sk = arith.cmpi eq, %nkey, %key : i64
        %sv = arith.cmpi eq, %nval, %strike : i64
        %struck = arith.andi %sk, %sv : i1
        %not = arith.xori %struck, %row : i1
        scf.yield %not : i1
      } else {
        scf.yield %row : i1
      }
      trikeshed.yield %live : i1
    }
    %m = trikeshed.size %keep : !s64
    %m64x = arith.index_cast %m : index to i64
    %mb0 = arith.addi %m64x, %c1 : i64
    %mb = arith.muli %mb0, %c8 : i64
    %lp = func.call @nxsi_buf(%c8, %mb) : (i64, i64) -> !llvm.ptr
    %ld = func.call @nxsi_d(%lp, %m64x) : (!llvm.ptr, i64) -> !d
    %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
    %recs = trikeshed.series %m : !s64 {
    ^bb0(%j: index):
      %k = trikeshed.at %keep[%j] : !s64, index -> i64
      %ki = arith.index_cast %k : i64 to index
      %e = trikeshed.at %ord[%ki] : !s64, index -> i64
      %e2 = arith.muli %e, %c2 : i64
      %ei = arith.index_cast %e2 : i64 to index
      %ei1 = arith.addi %ei, %i1 : index
      %val = trikeshed.at %gw[%ei1] : !s64, index -> i64
      trikeshed.yield %val : i64
    }
    %en = trikeshed.drain %recs, %lm : !s64, !m64 -> index
    // a live row's record is one that reads back whole, or the index is not sound
    %lv = builtin.unrealized_conversion_cast %lm : !m64 to !s64
    %unsound = trikeshed.fold %lv, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %rx: i64):
      %t = func.call @nxsi_rec(%rx) : (i64) -> i64
      %isnt = arith.cmpi eq, %t, %c0 : i64
      %a = arith.select %isnt, %c1, %acc : i64
      trikeshed.yield %a : i64
    }
    %bad = arith.cmpi ne, %unsound, %c0 : i64
    %res = arith.select %bad, %m1, %m64x : i64
    scf.yield %res : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The record that the paths hold for a name, or 0 when they hold none; -1 when the index is not sound.  The rows of the
// name's key: one that is not struck out and whose record's name is this one (a fold of them, a compare of the names).
func.func private @nxsi_live(%np: !llvm.ptr, %nn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c65535 = arith.constant 65535 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %key = func.call @nxsi_key(%np, %nn) : (!llvm.ptr, i64) -> i64
  %n = func.call @nxsi_find(%c0, %key, %c0, %c0) : (i64, i64, i64, i64) -> i64
  %have = arith.cmpi sge, %n, %c0 : i64
  %r = scf.if %have -> (i64) {
    %vp = func.call @nxsi_buf(%c0, %c0) : (i64, i64) -> !llvm.ptr
    %vd = func.call @nxsi_d(%vp, %n) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
    %vs = builtin.unrealized_conversion_cast %vm : !m64 to !s64
    %nd = func.call @nxsi_d(%np, %nn) : (!llvm.ptr, i64) -> !d
    %nm = builtin.unrealized_conversion_cast %nd : !d to !m
    %name = builtin.unrealized_conversion_cast %nm : !m to !s
    %x = trikeshed.fold %vs, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %v: i64):
      %settled = arith.cmpi ne, %acc, %c0 : i64
      %odd0 = arith.andi %v, %c1 : i64
      %odd = arith.cmpi eq, %odd0, %c1 : i64
      %skip = arith.ori %settled, %odd : i1
      %next = scf.if %skip -> (i64) {
        scf.yield %acc : i64
      } else {
        %strike = arith.ori %v, %c1 : i64
        %dead = trikeshed.fold %vs, %c0 : !s64, i64 -> i64 {
        ^bb0(%a2: i64, %u: i64):
          %is = arith.cmpi eq, %u, %strike : i64
          %a3 = arith.select %is, %c1, %a2 : i64
          trikeshed.yield %a3 : i64
        }
        %struck = arith.cmpi ne, %dead, %c0 : i64
        %n1 = scf.if %struck -> (i64) {
          scf.yield %acc : i64
        } else {
          %t = func.call @nxsi_rec(%v) : (i64) -> i64
          %isrec = arith.cmpi ne, %t, %c0 : i64
          %n2 = scf.if %isrec -> (i64) {
            %nl0 = arith.shrui %t, %c16 : i64
            %nl = arith.andi %nl0, %c65535 : i64
            %v24 = arith.addi %v, %c24 : i64
            %rp = func.call @nxsi_p(%v24) : (i64) -> !llvm.ptr
            %rd = func.call @nxsi_d(%rp, %nl) : (!llvm.ptr, i64) -> !d
            %rm = builtin.unrealized_conversion_cast %rd : !d to !m
            %rname = builtin.unrealized_conversion_cast %rm : !m to !s
            %c = trikeshed.compare %rname, %name unsigned : !s, !s
            %eq = arith.cmpi eq, %c, %z32 : i32
            %n3 = arith.select %eq, %v, %acc : i64
            scf.yield %n3 : i64
          } else {
            scf.yield %m1 : i64
          }
          scf.yield %n2 : i64
        }
        scf.yield %n1 : i64
      }
      trikeshed.yield %next : i64
    }
    scf.yield %x : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// Whether the record at x is the one the paths hold for its name: 1, 0, or -1 when the index is not sound.
func.func private @nxsi_is_live(%x: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c65535 = arith.constant 65535 : i64
  %m1 = arith.constant -1 : i64
  %t = func.call @nxsi_rec(%x) : (i64) -> i64
  %isrec = arith.cmpi ne, %t, %c0 : i64
  %r = scf.if %isrec -> (i64) {
    %nl0 = arith.shrui %t, %c16 : i64
    %nl = arith.andi %nl0, %c65535 : i64
    %x24 = arith.addi %x, %c24 : i64
    %np = func.call @nxsi_p(%x24) : (i64) -> !llvm.ptr
    %key = func.call @nxsi_key(%np, %nl) : (!llvm.ptr, i64) -> i64
    %n = func.call @nxsi_find(%c0, %key, %c0, %c0) : (i64, i64, i64, i64) -> i64
    %have = arith.cmpi sge, %n, %c0 : i64
    %rr = scf.if %have -> (i64) {
      %vp = func.call @nxsi_buf(%c0, %c0) : (i64, i64) -> !llvm.ptr
      %vd = func.call @nxsi_d(%vp, %n) : (!llvm.ptr, i64) -> !d
      %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
      %vs = builtin.unrealized_conversion_cast %vm : !m64 to !s64
      %strike = arith.ori %x, %c1 : i64
      %seen = trikeshed.fold %vs, %c0 : !s64, i64 -> i64 {
      ^bb0(%acc: i64, %u: i64):
        %isrow = arith.cmpi eq, %u, %x : i64
        %isstrike = arith.cmpi eq, %u, %strike : i64
        %a1 = arith.ori %acc, %c1 : i64
        %a2 = arith.select %isrow, %a1, %acc : i64
        %a3 = arith.ori %a2, %c2 : i64
        %a4 = arith.select %isstrike, %a3, %a2 : i64
        trikeshed.yield %a4 : i64
      }
      %live = arith.cmpi eq, %seen, %c1 : i64
      %l = arith.extui %live : i1 to i64
      scf.yield %l : i64
    } else {
      scf.yield %m1 : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The row of the record at x struck out: a row of its name's key whose value is x | 1.  1, 0 or -1 as si_put.
func.func private @nxsi_strike(%x: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c40 = arith.constant 40 : i64
  %c64 = arith.constant 64 : i64
  %c65535 = arith.constant 65535 : i64
  %m1 = arith.constant -1 : i64
  %t = func.call @nxsi_rec(%x) : (i64) -> i64
  %isrec = arith.cmpi ne, %t, %c0 : i64
  %r = scf.if %isrec -> (i64) {
    %nl0 = arith.shrui %t, %c16 : i64
    %nl = arith.andi %nl0, %c65535 : i64
    %x24 = arith.addi %x, %c24 : i64
    %np = func.call @nxsi_p(%x24) : (i64) -> !llvm.ptr
    %key = func.call @nxsi_key(%np, %nl) : (!llvm.ptr, i64) -> i64
    %strike = arith.ori %x, %c1 : i64
    %st = func.call @nxsi_put(%c0, %key, %strike) : (i64, i64, i64) -> i64
    %done = arith.cmpi eq, %st, %c1 : i64
    scf.if %done {
      func.call @nxsi_inc(%c40, %m1) : (i64, i64) -> ()
      func.call @nxsi_inc(%c64, %c1) : (i64, i64) -> ()
    }
    scf.yield %st : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// The directory's state, the lock, the handle's files
//===----------------------------------------------------------------------===//

// The info directory's state as a word: what fstat says of it but for the two times that tell nothing of its entries
// (when it was last read, when its own node last changed), summed.  Adding, removing or replacing an entry changes it.
// 0 when there is no directory to ask.
func.func private @nxsi_token() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c32 = arith.constant 32 : i64
  %z32 = arith.constant 0 : i32
  %buf = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
  %bd = func.call @nxsi_d(%buf, %c32) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m64
  %zg = memref.get_global @nxsi_zero : memref<32xi64>
  %zs = trikeshed.text %zg : memref<32xi64> -> !s64
  %e = trikeshed.drain %zs, %bm : !s64, !m64 -> index
  %dfd64 = func.call @nxsi_hg(%c3) : (i64) -> i64
  %has = arith.cmpi sge, %dfd64, %c0 : i64
  %r = scf.if %has -> (i64) {
    %dfd = arith.trunci %dfd64 : i64 to i32
    %rc = func.call @nixsi_os_fstat(%dfd, %buf) : (i32, !llvm.ptr) -> i32
    %ok = arith.cmpi eq, %rc, %z32 : i32
    %t = scf.if %ok -> (i64) {
      %ab = func.call @nixsi_os_atime() : () -> i64
      %aw = arith.shrui %ab, %c3 : i64
      %aw1 = arith.addi %aw, %c1 : i64
      %cw = arith.addi %aw, %c4 : i64
      %cw1 = arith.addi %aw, %c5 : i64
      %awi = arith.index_cast %aw : i64 to index
      %aw1i = arith.index_cast %aw1 : i64 to index
      %cwi = arith.index_cast %cw : i64 to index
      %cw1i = arith.index_cast %cw1 : i64 to index
      memref.store %c0, %bm[%awi] : !m64
      memref.store %c0, %bm[%aw1i] : !m64
      memref.store %c0, %bm[%cwi] : !m64
      memref.store %c0, %bm[%cw1i] : !m64
      %s = func.call @nxsi_sum(%buf, %c32, %c0) : (!llvm.ptr, i64, i64) -> i64
      %nil = arith.cmpi eq, %s, %c0 : i64
      %s1 = arith.select %nil, %c1, %s : i64
      scf.yield %s1 : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %t : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

// The directory stamped: its modification time set one nanosecond back (a time no later change gives it, whatever the
// file system rounds its times to), the time it was last read kept.  Its token then.  What is in the directory before the
// stamp is read after it; what changes after it changes the token.  Where the time cannot be set (the directory is
// another's), the token is one to hold only when the directory's time is three seconds old or more: a change in the
// same tick of the file system's clock would not show.  The handle's word 12 says whether the token is one to hold.
func.func private @nxsi_stamp() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c12 = arith.constant 12 : i64
  %c32 = arith.constant 32 : i64
  %top = arith.constant 999999999 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %buf = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
  %ts = llvm.alloca %c4 x i64 : (i64) -> !llvm.ptr
  %dfd64 = func.call @nxsi_hg(%c3) : (i64) -> i64
  %has = arith.cmpi sge, %dfd64, %c0 : i64
  %held = scf.if %has -> (i64) {
    %dfd = arith.trunci %dfd64 : i64 to i32
    %rc = func.call @nixsi_os_fstat(%dfd, %buf) : (i32, !llvm.ptr) -> i32
    %ok = arith.cmpi eq, %rc, %z32 : i32
    %h = scf.if %ok -> (i64) {
      %bd = func.call @nxsi_d(%buf, %c32) : (!llvm.ptr, i64) -> !d
      %bm = builtin.unrealized_conversion_cast %bd : !d to !m64
      %bs = builtin.unrealized_conversion_cast %bm : !m64 to !s64
      %ab = func.call @nixsi_os_atime() : () -> i64
      %aw = arith.shrui %ab, %c3 : i64
      %awi = arith.index_cast %aw : i64 to index
      %aw1i = arith.addi %awi, %i1 : index
      %aw2i = arith.addi %awi, %i2 : index
      %aw3i = arith.addi %awi, %i3 : index
      %asec = trikeshed.at %bs[%awi] : !s64, index -> i64
      %ansec = trikeshed.at %bs[%aw1i] : !s64, index -> i64
      %msec = trikeshed.at %bs[%aw2i] : !s64, index -> i64
      %mnsec = trikeshed.at %bs[%aw3i] : !s64, index -> i64
      %whole = arith.cmpi eq, %mnsec, %c0 : i64
      %ns1 = arith.subi %mnsec, %c1 : i64
      %ns = arith.select %whole, %top, %ns1 : i64
      %sec1 = arith.subi %msec, %c1 : i64
      %sec = arith.select %whole, %sec1, %msec : i64
      %td = func.call @nxsi_d(%ts, %c4) : (!llvm.ptr, i64) -> !d
      %tm = builtin.unrealized_conversion_cast %td : !d to !m64
      memref.store %asec, %tm[%z] : !m64
      memref.store %ansec, %tm[%i1] : !m64
      memref.store %sec, %tm[%i2] : !m64
      memref.store %ns, %tm[%i3] : !m64
      %rs = func.call @futimens(%dfd, %ts) : (i32, !llvm.ptr) -> i32
      %set0 = arith.cmpi eq, %rs, %z32 : i32
      // the time the directory then has is an earlier one, or the stamp did not take
      %buf2 = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
      %rc2 = func.call @nixsi_os_fstat(%dfd, %buf2) : (i32, !llvm.ptr) -> i32
      %ok2 = arith.cmpi eq, %rc2, %z32 : i32
      %b2d = func.call @nxsi_d(%buf2, %c32) : (!llvm.ptr, i64) -> !d
      %b2m = builtin.unrealized_conversion_cast %b2d : !d to !m64
      %b2s = builtin.unrealized_conversion_cast %b2m : !m64 to !s64
      %msec2 = trikeshed.at %b2s[%aw2i] : !s64, index -> i64
      %mnsec2 = trikeshed.at %b2s[%aw3i] : !s64, index -> i64
      %slt = arith.cmpi slt, %msec2, %msec : i64
      %seq = arith.cmpi eq, %msec2, %msec : i64
      %nlt = arith.cmpi slt, %mnsec2, %mnsec : i64
      %e1 = arith.andi %seq, %nlt : i1
      %earlier = arith.ori %slt, %e1 : i1
      %set1 = arith.andi %set0, %ok2 : i1
      %set = arith.andi %set1, %earlier : i1
      %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
      %now = func.call @time(%null) : (!llvm.ptr) -> i64
      %age = arith.subi %now, %msec : i64
      %old = arith.cmpi sge, %age, %c3 : i64
      %hold = arith.ori %set, %old : i1
      %h1 = arith.extui %hold : i1 to i64
      scf.yield %h1 : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %h : i64
  } else {
    scf.yield %c0 : i64
  }
  func.call @nxsi_hs(%c12, %held) : (i64, i64) -> ()
  %t = func.call @nxsi_token() : () -> i64
  return %t : i64
}

// An entry's identity from what stat filled: the file's number, and with it the file's modification time where the file
// system gives a new file an old one's number (the handle's word 11).  A file written again under its name is another
// entry.
func.func private @nxsi_ident(%buf: !llvm.ptr) -> i64 {
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c11 = arith.constant 11 : i64
  %c32 = arith.constant 32 : i64
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %bd = func.call @nxsi_d(%buf, %c32) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m64
  %bs = builtin.unrealized_conversion_cast %bm : !m64 to !s64
  %ino = trikeshed.at %bs[%i1] : !s64, index -> i64
  %pol = func.call @nxsi_hg(%c11) : (i64) -> i64
  %timed = arith.cmpi ne, %pol, %c2 : i64
  %r = scf.if %timed -> (i64) {
    %ab = func.call @nixsi_os_atime() : () -> i64
    %aw = arith.shrui %ab, %c3 : i64
    %awi = arith.index_cast %aw : i64 to index
    %aw2i = arith.addi %awi, %i2 : index
    %aw3i = arith.addi %awi, %i3 : index
    %msec = trikeshed.at %bs[%aw2i] : !s64, index -> i64
    %mnsec = trikeshed.at %bs[%aw3i] : !s64, index -> i64
    %a = func.call @nxsi_mix(%ino, %msec) : (i64, i64) -> i64
    %b = func.call @nxsi_mix(%a, %mnsec) : (i64, i64) -> i64
    scf.yield %b : i64
  } else {
    scf.yield %ino : i64
  }
  return %r : i64
}

// The file's lock taken (1 shared: readers; 2 alone: a writer) and the file's length read again; nothing for an index
// of the process's own.  Released by nxsi_unlock, and by the system when the process ends.  When the file's length or
// modification time is not what this process saw at its last lock, what it found whole is forgotten: every blob is
// checked again before it is believed.  False when the lock cannot be had (four tries): the file is then not used.
func.func private @nxsi_lock(%mode: i64) -> i1 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c9 = arith.constant 9 : i64
  %c32 = arith.constant 32 : i64
  %end32 = arith.constant 2 : i32
  %z32 = arith.constant 0 : i32
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %yes = arith.constant 1 : i1
  %sbuf = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %k1 = arith.cmpi eq, %kind, %c1 : i64
  %k2 = arith.cmpi eq, %kind, %c2 : i64
  %file = arith.ori %k1, %k2 : i1
  %r = scf.if %file -> (i1) {
    %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
    %fd = arith.trunci %fd64 : i64 to i32
    %m32 = arith.trunci %mode : i64 to i32
    %te, %ge = scf.while (%try = %c0, %got = %c0) : (i64, i64) -> (i64, i64) {
      %open = arith.cmpi eq, %got, %c0 : i64
      %left = arith.cmpi slt, %try, %c4 : i64
      %run = arith.andi %open, %left : i1
      scf.condition(%run) %try, %got : i64, i64
    } do {
    ^bb0(%ta: i64, %ga: i64):
      %rc = func.call @flock(%fd, %m32) : (i32, i32) -> i32
      %ok = arith.cmpi eq, %rc, %z32 : i32
      %g = arith.extui %ok : i1 to i64
      %tn = arith.addi %ta, %c1 : i64
      scf.yield %tn, %g : i64, i64
    }
    %locked = arith.cmpi eq, %ge, %c1 : i64
    scf.if %locked {
      func.call @nxsi_hs(%c7, %mode) : (i64, i64) -> ()
      %size = func.call @lseek(%fd, %c0, %end32) : (i32, i64, i32) -> i64
      func.call @nxsi_hs(%c4, %size) : (i64, i64) -> ()
      %rs = func.call @nixsi_os_fstat(%fd, %sbuf) : (i32, !llvm.ptr) -> i32
      %sd = func.call @nxsi_d(%sbuf, %c32) : (!llvm.ptr, i64) -> !d
      %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
      %ss = builtin.unrealized_conversion_cast %sm : !m64 to !s64
      %ab = func.call @nixsi_os_atime() : () -> i64
      %aw = arith.shrui %ab, %c3 : i64
      %awi = arith.index_cast %aw : i64 to index
      %aw2i = arith.addi %awi, %i2 : index
      %aw3i = arith.addi %awi, %i3 : index
      %msec = trikeshed.at %ss[%aw2i] : !s64, index -> i64
      %mnsec = trikeshed.at %ss[%aw3i] : !s64, index -> i64
      %g1 = func.call @nxsi_mix(%size, %msec) : (i64, i64) -> i64
      %sig = func.call @nxsi_mix(%g1, %mnsec) : (i64, i64) -> i64
      %was = func.call @nxsi_hg(%c9) : (i64) -> i64
      %moved = arith.cmpi ne, %sig, %was : i64
      scf.if %moved {
        func.call @nxsi_hs(%c9, %sig) : (i64, i64) -> ()
        func.call @nxsi_forget() : () -> ()
      }
    }
    scf.yield %locked : i1
  } else {
    scf.yield %yes : i1
  }
  return %r : i1
}
func.func private @nxsi_unlock() {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %un32 = arith.constant 8 : i32
  %mode = func.call @nxsi_hg(%c7) : (i64) -> i64
  %held = arith.cmpi ne, %mode, %c0 : i64
  scf.if %held {
    %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
    %fd = arith.trunci %fd64 : i64 to i32
    %rc = func.call @flock(%fd, %un32) : (i32, i32) -> i32
    func.call @nxsi_hs(%c7, %c0) : (i64, i64) -> ()
  }
  return
}

// The index is sound and holds the directory as it is now.
func.func private @nxsi_fresh() -> i1 {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %ok = func.call @nxsi_ok() : () -> i1
  %r = scf.if %ok -> (i1) {
    %tok = func.call @nxsi_w(%c16) : (i64) -> i64
    %set = arith.cmpi ne, %tok, %c0 : i64
    %rr = scf.if %set -> (i1) {
      %now = func.call @nxsi_token() : () -> i64
      %same = arith.cmpi eq, %now, %tok : i64
      scf.yield %same : i1
    } else {
      scf.yield %set : i1
    }
    scf.yield %rr : i1
  } else {
    scf.yield %ok : i1
  }
  return %r : i1
}

// The index file of the directory in hand opened and mapped: `<dir>.trie`, to read and write, made when `create` asks
// and there is none, to read when it cannot be written; no index (kind 0) when there is none to open or to map, when
// the directory's file system is not one trusted to tell its changes, or when this boot has no name.
func.func private @nxsi_openfile(%create: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %m1 = arith.constant -1 : i64
  %reserve = arith.constant 68719476736 : i64
  %end32 = arith.constant 2 : i32
  %z32 = arith.constant 0 : i32
  %shared = arith.constant 1 : i32
  %pr = arith.constant 1 : i32
  %prw = arith.constant 3 : i32
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %pol = func.call @nxsi_hg(%c11) : (i64) -> i64
  %boot = func.call @nxsi_boot() : () -> i64
  %trusted = arith.cmpi ne, %pol, %c0 : i64
  %named = arith.cmpi ne, %boot, %c1 : i64
  %may = arith.andi %trusted, %named : i1
  scf.if %may {
    %dl = func.call @nxsi_hg(%c5) : (i64) -> i64
    %dp = func.call @nxsi_buf(%c10, %c0) : (i64, i64) -> !llvm.ptr
    %pb = arith.addi %dl, %c8 : i64
    %pp = func.call @nxsi_buf(%c6, %pb) : (i64, i64) -> !llvm.ptr
    %dd = func.call @nxsi_d(%dp, %dl) : (!llvm.ptr, i64) -> !d
    %dm = builtin.unrealized_conversion_cast %dd : !d to !m
    %dir = builtin.unrealized_conversion_cast %dm : !m to !s
    %wg = memref.get_global @nxsi_words : memref<16xi8>
    %words = trikeshed.text %wg : memref<16xi8> -> !s
    %ext = trikeshed.slice %words[%i5, %i6] : !s -> !s
    %path = trikeshed.combine %dir, %ext : !s, !s -> !s
    %pl = arith.addi %dl, %c6 : i64
    %pd = func.call @nxsi_d(%pp, %pl) : (!llvm.ptr, i64) -> !d
    %pm = builtin.unrealized_conversion_cast %pd : !d to !m
    %e = trikeshed.drain %path, %pm : !s, !m -> index
    %asked = arith.cmpi ne, %create, %c0 : i64
    %how = arith.select %asked, %c2, %c1 : i64
    %fd1 = func.call @nixsi_os_open(%pp, %how) : (!llvm.ptr, i64) -> i32
    %rw = arith.cmpi sge, %fd1, %z32 : i32
    %fd = scf.if %rw -> (i32) {
      scf.yield %fd1 : i32
    } else {
      %f3 = func.call @nixsi_os_open(%pp, %c0) : (!llvm.ptr, i64) -> i32
      scf.yield %f3 : i32
    }
    %has = arith.cmpi sge, %fd, %z32 : i32
    scf.if %has {
      %prot = arith.select %rw, %prw, %pr : i32
      %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
      %p = func.call @mmap(%null, %reserve, %prot, %shared, %fd, %c0) : (!llvm.ptr, i64, i32, i32, i32, i64) -> !llvm.ptr
      %bits = llvm.ptrtoint %p : !llvm.ptr to i64
      %ok = arith.cmpi ne, %bits, %m1 : i64
      scf.if %ok {
        %kind = arith.select %rw, %c1, %c2 : i64
        %fd64 = arith.extsi %fd : i32 to i64
        %size = func.call @lseek(%fd, %c0, %end32) : (i32, i64, i32) -> i64
        func.call @nxsi_hs(%c0, %bits) : (i64, i64) -> ()
        func.call @nxsi_hs(%c1, %kind) : (i64, i64) -> ()
        func.call @nxsi_hs(%c2, %fd64) : (i64, i64) -> ()
        func.call @nxsi_hs(%c4, %size) : (i64, i64) -> ()
      } else {
        %rc2 = func.call @close(%fd) : (i32) -> i32
      }
    }
  }
  return
}

// An index of this process's own, empty: where the file cannot be written (or made, or read as it is), a query still
// answers from the directory's files, as it did before there was an index.  Kind 0 when the memory cannot be had.
// The file, when one was in hand, is closed and its image given back.
func.func private @nxsi_anon() {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %m1 = arith.constant -1 : i64
  %reserve = arith.constant 68719476736 : i64
  %prw = arith.constant 3 : i32
  %nofd = arith.constant -1 : i32
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %not = arith.cmpi ne, %kind, %c3 : i64
  scf.if %not {
    func.call @nxsi_drop() : () -> ()
    %fl64 = func.call @nixsi_os_anon() : () -> i64
    %fl = arith.trunci %fl64 : i64 to i32
    %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
    %p = func.call @mmap(%null, %reserve, %prw, %fl, %nofd, %c0) : (!llvm.ptr, i64, i32, i32, i32, i64) -> !llvm.ptr
    %bits = llvm.ptrtoint %p : !llvm.ptr to i64
    %ok = arith.cmpi ne, %bits, %m1 : i64
    scf.if %ok {
      func.call @nxsi_hs(%c0, %bits) : (i64, i64) -> ()
      func.call @nxsi_hs(%c1, %c3) : (i64, i64) -> ()
      func.call @nxsi_hs(%c4, %reserve) : (i64, i64) -> ()
      %made = func.call @nxsi_init() : () -> i1
    }
  }
  return
}

// The image and the file in hand let go (the lock with the file): no index (kind 0).
func.func private @nxsi_drop() {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c9 = arith.constant 9 : i64
  %m1 = arith.constant -1 : i64
  %reserve = arith.constant 68719476736 : i64
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %img = func.call @nxsi_hg(%c0) : (i64) -> i64
  %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
  %k1 = arith.cmpi eq, %kind, %c1 : i64
  %k2 = arith.cmpi eq, %kind, %c2 : i64
  %file = arith.ori %k1, %k2 : i1
  %mapped0 = arith.cmpi ne, %kind, %c0 : i64
  %mapped1 = arith.cmpi ne, %img, %c0 : i64
  %mapped = arith.andi %mapped0, %mapped1 : i1
  scf.if %mapped {
    %ip = llvm.inttoptr %img : i64 to !llvm.ptr
    %ru = func.call @munmap(%ip, %reserve) : (!llvm.ptr, i64) -> i32
  }
  scf.if %file {
    %fd = arith.trunci %fd64 : i64 to i32
    %rc = func.call @close(%fd) : (i32) -> i32
  }
  func.call @nxsi_hs(%c0, %c0) : (i64, i64) -> ()
  func.call @nxsi_hs(%c1, %c0) : (i64, i64) -> ()
  func.call @nxsi_hs(%c2, %m1) : (i64, i64) -> ()
  func.call @nxsi_hs(%c4, %c0) : (i64, i64) -> ()
  func.call @nxsi_hs(%c7, %c0) : (i64, i64) -> ()
  func.call @nxsi_hs(%c9, %c0) : (i64, i64) -> ()
  func.call @nxsi_forget() : () -> ()
  return
}

// The handle made the one of f's directory (f: an info file's path, `<stateDir>/info/<name>`): the directory and the
// index beside it opened when they are not the ones in hand.  mode 0: for one path's info; 1: for a list, the index made
// when there is none; 2: for a change of the directory.  Where f's name begins (the last of its parts at '/').
func.func private @nxsi_use(%f: !llvm.ptr, %mode: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %m1 = arith.constant -1 : i64
  %slash = arith.constant 47 : i8
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i4 = arith.constant 4 : index
  %n = func.call @strlen(%f) : (!llvm.ptr) -> i64
  %fd = func.call @nxsi_d(%f, %n) : (!llvm.ptr, i64) -> !d
  %fm = builtin.unrealized_conversion_cast %fd : !d to !m
  %fs = builtin.unrealized_conversion_cast %fm : !m to !s
  %ps = trikeshed.parts %fs, %slash : !s, i8 -> !sp
  %np = trikeshed.size %ps : !sp
  %lasti = arith.subi %np, %i1 : index
  %lc = trikeshed.at %ps[%lasti] : !sp, index -> !tp
  %st32 = trikeshed.first %lc : !tp -> i32
  %start = arith.extui %st32 : i32 to i64
  %hasdir = arith.cmpi sgt, %start, %c0 : i64
  %dl0 = arith.subi %start, %c1 : i64
  %dl = arith.maxsi %dl0, %c0 : i64
  %dli = arith.index_cast %dl : i64 to index
  %mine = trikeshed.slice %fs[%z, %dli] : !s -> !s
  %inhand = func.call @nxsi_hg(%c6) : (i64) -> i64
  %hl = func.call @nxsi_hg(%c5) : (i64) -> i64
  %hp = func.call @nxsi_buf(%c10, %c0) : (i64, i64) -> !llvm.ptr
  %hd = func.call @nxsi_d(%hp, %hl) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m
  %had = builtin.unrealized_conversion_cast %hm : !m to !s
  %cmp = trikeshed.compare %mine, %had unsigned : !s, !s
  %eq = arith.cmpi eq, %cmp, %z32 : i32
  %open = arith.cmpi ne, %inhand, %c0 : i64
  %same = arith.andi %eq, %open : i1
  %yes = arith.constant 1 : i1
  %change = arith.xori %same, %yes : i1
  scf.if %change {
    scf.if %open {
      func.call @nxsi_drop() : () -> ()
      %odfd64 = func.call @nxsi_hg(%c3) : (i64) -> i64
      %hasd = arith.cmpi sge, %odfd64, %c0 : i64
      scf.if %hasd {
        %odfd = arith.trunci %odfd64 : i64 to i32
        %rc2 = func.call @close(%odfd) : (i32) -> i32
      }
    }
    %db = arith.addi %dl, %c8 : i64
    %dp = func.call @nxsi_buf(%c10, %db) : (i64, i64) -> !llvm.ptr
    %dl1 = arith.addi %dl, %c1 : i64
    %dd = func.call @nxsi_d(%dp, %dl1) : (!llvm.ptr, i64) -> !d
    %dm = builtin.unrealized_conversion_cast %dd : !d to !m
    %wg = memref.get_global @nxsi_words : memref<16xi8>
    %words = trikeshed.text %wg : memref<16xi8> -> !s
    %nul = trikeshed.slice %words[%i4, %i1] : !s -> !s
    %dz = trikeshed.combine %mine, %nul : !s, !s -> !s
    %e = trikeshed.drain %dz, %dm : !s, !m -> index
    func.call @nxsi_hs(%c5, %dl) : (i64, i64) -> ()
    func.call @nxsi_hs(%c6, %c1) : (i64, i64) -> ()
    func.call @nxsi_hs(%c0, %c0) : (i64, i64) -> ()
    func.call @nxsi_hs(%c1, %c0) : (i64, i64) -> ()
    func.call @nxsi_hs(%c2, %m1) : (i64, i64) -> ()
    func.call @nxsi_hs(%c3, %m1) : (i64, i64) -> ()
    func.call @nxsi_hs(%c4, %c0) : (i64, i64) -> ()
    func.call @nxsi_hs(%c7, %c0) : (i64, i64) -> ()
    func.call @nxsi_hs(%c11, %c0) : (i64, i64) -> ()
    %c13x = arith.constant 13 : i64
    func.call @nxsi_hs(%c13x, %c0) : (i64, i64) -> ()
  }
  // the directory, once it is there, and what its file system is trusted with; then the index beside it, if it is there
  // (a query of one path's info looks for the directory once; what changes or lists the directory looks again)
  %dfd64 = func.call @nxsi_hg(%c3) : (i64) -> i64
  %nodir = arith.cmpi slt, %dfd64, %c0 : i64
  %c13 = arith.constant 13 : i64
  %looked = func.call @nxsi_hg(%c13) : (i64) -> i64
  %fresh0 = arith.cmpi eq, %looked, %c0 : i64
  %keen = arith.cmpi ne, %mode, %c0 : i64
  %again = arith.ori %fresh0, %keen : i1
  %try0 = arith.andi %nodir, %hasdir : i1
  %try = arith.andi %try0, %again : i1
  scf.if %try {
    %dp2 = func.call @nxsi_buf(%c10, %c0) : (i64, i64) -> !llvm.ptr
    %d = func.call @nixsi_os_open(%dp2, %c0) : (!llvm.ptr, i64) -> i32
    %d64 = arith.extsi %d : i32 to i64
    func.call @nxsi_hs(%c3, %d64) : (i64, i64) -> ()
    func.call @nxsi_hs(%c13, %c1) : (i64, i64) -> ()
    %got = arith.cmpi sge, %d, %z32 : i32
    scf.if %got {
      %pol = func.call @nixsi_os_local(%d) : (i32) -> i64
      func.call @nxsi_hs(%c11, %pol) : (i64, i64) -> ()
      func.call @nxsi_openfile(%c0) : (i64) -> ()
    }
  }
  // the index made, when it is asked for and there is none
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %none = arith.cmpi eq, %kind, %c0 : i64
  %asked = arith.cmpi eq, %mode, %c1 : i64
  %mk0 = arith.andi %none, %asked : i1
  %hasd2 = func.call @nxsi_hg(%c3) : (i64) -> i64
  %dirin = arith.cmpi sge, %hasd2, %c0 : i64
  %mk = arith.andi %mk0, %dirin : i1
  scf.if %mk {
    func.call @nxsi_openfile(%c1) : (i64) -> ()
  }
  return %start : i64
}

//===----------------------------------------------------------------------===//
// The directory read into the index
//===----------------------------------------------------------------------===//

// The file at path read whole into room 2: its bytes, or -1 when it cannot be opened or read, or is more than a
// megabyte (no info file is: such an entry's text is left in its file).
func.func private @nxsi_slurp(%path: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c65536 = arith.constant 65536 : i64
  %cmax = arith.constant 1048576 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %fd = func.call @nixsi_os_open(%path, %c0) : (!llvm.ptr, i64) -> i32
  %has = arith.cmpi sge, %fd, %z32 : i32
  %r = scf.if %has -> (i64) {
    %ge, %se = scf.while (%got = %c0, %st = %c1) : (i64, i64) -> (i64, i64) {
      %run = arith.cmpi eq, %st, %c1 : i64
      scf.condition(%run) %got, %st : i64, i64
    } do {
    ^bb0(%ga: i64, %sa: i64):
      %want = arith.addi %ga, %c65536 : i64
      %buf = func.call @nxsi_buf(%c2, %want) : (i64, i64) -> !llvm.ptr
      %cap = func.call @nxsi_cap(%c2) : (i64) -> i64
      %at = llvm.getelementptr %buf[%ga] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %left = arith.subi %cap, %ga : i64
      %k = func.call @read(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
      %neg = arith.cmpi slt, %k, %c0 : i64
      %eof = arith.cmpi eq, %k, %c0 : i64
      %g2 = arith.addi %ga, %k : i64
      %big = arith.cmpi sgt, %g2, %cmax : i64
      %failed = arith.ori %neg, %big : i1
      %s1 = arith.select %eof, %c0, %c1 : i64
      %s2 = arith.select %failed, %m1, %s1 : i64
      %gn = arith.select %neg, %ga, %g2 : i64
      scf.yield %gn, %s2 : i64, i64
    }
    %rc = func.call @close(%fd) : (i32) -> i32
    %whole = arith.cmpi eq, %se, %c0 : i64
    %n = arith.select %whole, %ge, %m1 : i64
    scf.yield %n : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// an entry a pass has met, by its record
func.func private @nxsi_saw(%x: i64) {
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %cnt = func.call @nxsi_hg(%c8) : (i64) -> i64
  %cnt1 = arith.addi %cnt, %c1 : i64
  %bytes = arith.muli %cnt1, %c8 : i64
  %ep = func.call @nxsi_buf(%c5, %bytes) : (i64, i64) -> !llvm.ptr
  %ed = func.call @nxsi_d(%ep, %cnt1) : (!llvm.ptr, i64) -> !d
  %em = builtin.unrealized_conversion_cast %ed : !d to !m64
  %ci = arith.index_cast %cnt : i64 to index
  memref.store %x, %em[%ci] : !m64
  func.call @nxsi_hs(%c8, %cnt1) : (i64, i64) -> ()
  return
}

// One entry indexed (name, identity, the tn bytes of its info file at tp, or tn -1 when it has none to read): its record
// appended (the name, the text, zeros to a word: one combine drained once; the text left out, and the record marked not
// held, when it does not read as registerValidPath writes it: a narHash parseHash refuses, a narSize that is not a plain
// number, nothing to read), then a row for each of its references under the reference's key (baseNameOf's, as a
// query's), or one row under the key of all for a record not held, and last its own row under its name's key.
// The record's place; 0 when the heap has no room, -1 when the index is not sound.
func.func private @nxsi_index(%np: !llvm.ptr, %nn: i64, %ident: i64, %tp: !llvm.ptr, %tn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c19 = arith.constant 19 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c40 = arith.constant 40 : i64
  %c64 = arith.constant 64 : i64
  %cm8 = arith.constant -8 : i64
  %m1 = arith.constant -1 : i64
  %ch0 = arith.constant 48 : i8
  %ch9 = arith.constant 57 : i8
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %hash = llvm.alloca %c8 x i64 : (i64) -> !llvm.ptr
  %info = llvm.alloca %c3 x i64 : (i64) -> !llvm.ptr
  %readable = arith.cmpi sge, %tn, %c0 : i64
  %tn0 = arith.maxsi %tn, %c0 : i64
  %half = arith.shrui %tn0, %c1 : i64
  %recs0 = arith.addi %half, %c2 : i64
  %recw = arith.muli %recs0, %c3 : i64
  %recb = arith.muli %recw, %c8 : i64
  %sb0 = arith.addi %recb, %tn0 : i64
  %sb = arith.addi %sb0, %c64 : i64
  %sp = func.call @nxsi_buf(%c3, %sb) : (i64, i64) -> !llvm.ptr
  %scr = llvm.getelementptr %sp[%recb] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %td = func.call @nxsi_d(%tp, %tn0) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m
  %txt = builtin.unrealized_conversion_cast %tm : !m to !s
  %k = scf.if %readable -> (i64) {
    %k0 = func.call @nixstore_ts_infolines(%tp, %tn, %sp) : (!llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %k0 : i64
  } else {
    scf.yield %c0 : i64
  }
  %k3 = arith.muli %k, %c3 : i64
  %rd = func.call @nxsi_d(%sp, %k3) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rv = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %ki = arith.index_cast %k : i64 to index
  // a line that would not read: a hash parseHash refuses, a size that is not one to nineteen digits
  %bad = scf.for %i = %z to %ki step %one iter_args(%b = %c0) -> (i64) {
    %i3x = arith.muli %i, %i3 : index
    %i3a = arith.addi %i3x, %one : index
    %i3b = arith.addi %i3x, %i2 : index
    %code = trikeshed.at %rv[%i3x] : !s64, index -> i64
    %off = trikeshed.at %rv[%i3a] : !s64, index -> i64
    %len = trikeshed.at %rv[%i3b] : !s64, index -> i64
    %ishash = arith.cmpi eq, %code, %c0 : i64
    %b1 = scf.if %ishash -> (i64) {
      %vp = llvm.getelementptr %tp[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %rc = func.call @nixstore_ts_parsehash(%vp, %len, %m1, %hash, %scr, %info) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      %refused = arith.cmpi ne, %rc, %c0 : i64
      %rf = arith.extui %refused : i1 to i64
      scf.yield %rf : i64
    } else {
      %issize = arith.cmpi eq, %code, %c1 : i64
      %b2 = scf.if %issize -> (i64) {
        %offi = arith.index_cast %off : i64 to index
        %leni = arith.index_cast %len : i64 to index
        %digits = trikeshed.slice %txt[%offi, %leni] : !s -> !s
        %other = trikeshed.fold %digits, %c0 : !s, i64 -> i64 {
        ^bb0(%a: i64, %ch: i8):
          %lo = arith.cmpi ult, %ch, %ch0 : i8
          %hi = arith.cmpi ugt, %ch, %ch9 : i8
          %o = arith.ori %lo, %hi : i1
          %o64 = arith.extui %o : i1 to i64
          %a1 = arith.ori %a, %o64 : i64
          trikeshed.yield %a1 : i64
        }
        %l1 = arith.cmpi sge, %len, %c1 : i64
        %l2 = arith.cmpi sle, %len, %c19 : i64
        %alld = arith.cmpi eq, %other, %c0 : i64
        %p1 = arith.andi %l1, %l2 : i1
        %plain = arith.andi %p1, %alld : i1
        %np1 = arith.extui %plain : i1 to i64
        %notplain = arith.xori %np1, %c1 : i64
        scf.yield %notplain : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %b2 : i64
    }
    %bn = arith.ori %b, %b1 : i64
    scf.yield %bn : i64
  }
  %clean = arith.cmpi eq, %bad, %c0 : i64
  %regular = arith.andi %readable, %clean : i1
  %stl = arith.select %regular, %tn0, %c0 : i64
  %listed = func.call @nxsi_listed(%np, %nn) : (!llvm.ptr, i64) -> i64
  %irr = arith.select %regular, %c0, %c2 : i64
  %flags = arith.ori %listed, %irr : i64
  %by0 = arith.addi %nn, %stl : i64
  %by1 = arith.addi %by0, %c7 : i64
  %body = arith.andi %by1, %cm8 : i64
  %bytes = arith.addi %body, %c24 : i64
  %x = func.call @nxsi_room(%bytes) : (i64) -> i64
  %has = arith.cmpi ne, %x, %c0 : i64
  %r = scf.if %has -> (i64) {
    %nd = func.call @nxsi_d(%np, %nn) : (!llvm.ptr, i64) -> !d
    %nm = builtin.unrealized_conversion_cast %nd : !d to !m
    %name = builtin.unrealized_conversion_cast %nm : !m to !s
    %stli = arith.index_cast %stl : i64 to index
    %text = trikeshed.slice %txt[%z, %stli] : !s -> !s
    %padn = arith.subi %body, %by0 : i64
    %padi = arith.index_cast %padn : i64 to index
    %zeros = trikeshed.series %padi : !s {
    ^bb0(%q: index):
      %zb = arith.constant 0 : i8
      trikeshed.yield %zb : i8
    }
    %rec = trikeshed.combine %name, %text, %zeros : !s, !s, !s -> !s
    %x8 = arith.addi %x, %c8 : i64
    %x16 = arith.addi %x, %c16 : i64
    %x24 = arith.addi %x, %c24 : i64
    %bp = func.call @nxsi_p(%x24) : (i64) -> !llvm.ptr
    %bd = func.call @nxsi_d(%bp, %body) : (!llvm.ptr, i64) -> !d
    %bm = builtin.unrealized_conversion_cast %bd : !d to !m
    %e = trikeshed.drain %rec, %bm : !s, !m -> index
    %fs = arith.shli %flags, %c8 : i64
    %ns = arith.shli %nn, %c16 : i64
    %ts = arith.shli %stl, %c32 : i64
    %w0a = arith.ori %fs, %c1 : i64
    %w0b = arith.ori %w0a, %ns : i64
    %w0 = arith.ori %w0b, %ts : i64
    func.call @nxsi_ws(%x, %w0) : (i64, i64) -> ()
    func.call @nxsi_ws(%x8, %ident) : (i64, i64) -> ()
    %seed = arith.xori %w0, %ident : i64
    %bw = arith.shrui %body, %c3 : i64
    %sum = func.call @nxsi_sum(%bp, %bw, %seed) : (!llvm.ptr, i64, i64) -> i64
    func.call @nxsi_ws(%x16, %sum) : (i64, i64) -> ()
    %st1 = scf.if %regular -> (i64) {
      %s = scf.for %j = %z to %ki step %one iter_args(%st = %c1) -> (i64) {
        %j3 = arith.muli %j, %i3 : index
        %j3a = arith.addi %j3, %one : index
        %j3b = arith.addi %j3, %i2 : index
        %jcode = trikeshed.at %rv[%j3] : !s64, index -> i64
        %joff = trikeshed.at %rv[%j3a] : !s64, index -> i64
        %jlen = trikeshed.at %rv[%j3b] : !s64, index -> i64
        %isref = arith.cmpi eq, %jcode, %c2 : i64
        %going = arith.cmpi eq, %st, %c1 : i64
        %go = arith.andi %isref, %going : i1
        %sn = scf.if %go -> (i64) {
          %rp = llvm.getelementptr %tp[%joff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %bl = func.call @nixstore_ts_basename(%rp, %jlen, %scr) : (!llvm.ptr, i64, !llvm.ptr) -> i64
          %rkey = func.call @nxsi_key(%scr, %bl) : (!llvm.ptr, i64) -> i64
          %put = func.call @nxsi_put(%c1, %rkey, %x) : (i64, i64, i64) -> i64
          scf.yield %put : i64
        } else {
          scf.yield %st : i64
        }
        scf.yield %sn : i64
      }
      scf.yield %s : i64
    } else {
      %all = func.call @nxsi_put(%c1, %m1, %x) : (i64, i64, i64) -> i64
      scf.yield %all : i64
    }
    %ok1 = arith.cmpi eq, %st1, %c1 : i64
    %st2 = scf.if %ok1 -> (i64) {
      %key = func.call @nxsi_key(%np, %nn) : (!llvm.ptr, i64) -> i64
      %own = func.call @nxsi_put(%c0, %key, %x) : (i64, i64, i64) -> i64
      scf.yield %own : i64
    } else {
      scf.yield %st1 : i64
    }
    %ok2 = arith.cmpi eq, %st2, %c1 : i64
    scf.if %ok2 {
      func.call @nxsi_inc(%c40, %c1) : (i64, i64) -> ()
    }
    %rr = arith.select %ok2, %x, %st2 : i64
    scf.yield %rr : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}

// One entry of the directory met by a pass: seen, when the paths hold a record of its name with its identity; else the
// record of its name struck out, its file read (a regular file's: type 8; anything else is not opened, and its text
// not held) and it indexed anew.  1, 0 (no room) or -1 (not sound).
func.func private @nxsi_entry(%np: !llvm.ptr, %nn: i64, %dino: i64, %type: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c32 = arith.constant 32 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %i1 = arith.constant 1 : index
  %i4 = arith.constant 4 : index
  %i15 = arith.constant 15 : index
  %sbuf = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
  // the entry's path: the directory, a slash, the name, a NUL
  %dl = func.call @nxsi_hg(%c5) : (i64) -> i64
  %dp = func.call @nxsi_buf(%c10, %c0) : (i64, i64) -> !llvm.ptr
  %pb0 = arith.addi %dl, %nn : i64
  %pb = arith.addi %pb0, %c8 : i64
  %pp = func.call @nxsi_buf(%c6, %pb) : (i64, i64) -> !llvm.ptr
  %dd = func.call @nxsi_d(%dp, %dl) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %dir = builtin.unrealized_conversion_cast %dm : !m to !s
  %nd = func.call @nxsi_d(%np, %nn) : (!llvm.ptr, i64) -> !d
  %nm = builtin.unrealized_conversion_cast %nd : !d to !m
  %name = builtin.unrealized_conversion_cast %nm : !m to !s
  %wg = memref.get_global @nxsi_words : memref<16xi8>
  %words = trikeshed.text %wg : memref<16xi8> -> !s
  %sl = trikeshed.slice %words[%i15, %i1] : !s -> !s
  %nul = trikeshed.slice %words[%i4, %i1] : !s -> !s
  %path = trikeshed.combine %dir, %sl, %name, %nul : !s, !s, !s, !s -> !s
  %pl = arith.addi %pb0, %c2 : i64
  %pd = func.call @nxsi_d(%pp, %pl) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m
  %e = trikeshed.drain %path, %pm : !s, !m -> index
  %c11 = arith.constant 11 : i64
  %pol = func.call @nxsi_hg(%c11) : (i64) -> i64
  %timed = arith.cmpi ne, %pol, %c2 : i64
  %ident = scf.if %timed -> (i64) {
    %rc = func.call @nixsi_os_lstat(%pp, %sbuf) : (!llvm.ptr, !llvm.ptr) -> i32
    %ok = arith.cmpi eq, %rc, %z32 : i32
    %id = scf.if %ok -> (i64) {
      %i = func.call @nxsi_ident(%sbuf) : (!llvm.ptr) -> i64
      scf.yield %i : i64
    } else {
      scf.yield %dino : i64
    }
    scf.yield %id : i64
  } else {
    scf.yield %dino : i64
  }
  %x = func.call @nxsi_live(%np, %nn) : (!llvm.ptr, i64) -> i64
  %sound = arith.cmpi sge, %x, %c0 : i64
  %r = scf.if %sound -> (i64) {
    %held = arith.cmpi sgt, %x, %c0 : i64
    %same = scf.if %held -> (i1) {
      %x8 = arith.addi %x, %c8 : i64
      %was = func.call @nxsi_w(%x8) : (i64) -> i64
      %eq = arith.cmpi eq, %was, %ident : i64
      scf.yield %eq : i1
    } else {
      scf.yield %held : i1
    }
    %rr = scf.if %same -> (i64) {
      func.call @nxsi_saw(%x) : (i64) -> ()
      scf.yield %c1 : i64
    } else {
      %s0 = scf.if %held -> (i64) {
        %st = func.call @nxsi_strike(%x) : (i64) -> i64
        scf.yield %st : i64
      } else {
        scf.yield %c1 : i64
      }
      %ok0 = arith.cmpi eq, %s0, %c1 : i64
      %s1 = scf.if %ok0 -> (i64) {
        %isfile = arith.cmpi eq, %type, %c8 : i64
        %tn = scf.if %isfile -> (i64) {
          %got = func.call @nxsi_slurp(%pp) : (!llvm.ptr) -> i64
          scf.yield %got : i64
        } else {
          scf.yield %m1 : i64
        }
        %tp = func.call @nxsi_buf(%c2, %c0) : (i64, i64) -> !llvm.ptr
        %xn = func.call @nxsi_index(%np, %nn, %ident, %tp, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
        %made = arith.cmpi sgt, %xn, %c0 : i64
        scf.if %made {
          func.call @nxsi_saw(%xn) : (i64) -> ()
        }
        %s2 = arith.select %made, %c1, %xn : i64
        scf.yield %s2 : i64
      } else {
        scf.yield %s0 : i64
      }
      scf.yield %s1 : i64
    }
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The rows of entries the directory no longer has, struck out: every live row whose record is not among those the pass
// has seen (the seen ones sorted, a bisect for each live one).  1, 0 or -1.
func.func private @nxsi_sweep() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %c40 = arith.constant 40 : i64
  %m1 = arith.constant -1 : i64
  %z = arith.constant 0 : index
  %m = func.call @nxsi_live_rows() : () -> i64
  %have = arith.cmpi sge, %m, %c0 : i64
  %r = scf.if %have -> (i64) {
    %lp = func.call @nxsi_buf(%c8, %c0) : (i64, i64) -> !llvm.ptr
    %ld = func.call @nxsi_d(%lp, %m) : (!llvm.ptr, i64) -> !d
    %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
    %lv = builtin.unrealized_conversion_cast %lm : !m64 to !s64
    %s = func.call @nxsi_hg(%c8) : (i64) -> i64
    %ep = func.call @nxsi_buf(%c5, %c0) : (i64, i64) -> !llvm.ptr
    %ed = func.call @nxsi_d(%ep, %s) : (!llvm.ptr, i64) -> !d
    %em = builtin.unrealized_conversion_cast %ed : !d to !m64
    %ev = builtin.unrealized_conversion_cast %em : !m64 to !s64
    %seen = trikeshed.sorted %ev : !s64 -> !s64
    %st = trikeshed.fold %lv, %c1 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %x: i64):
      %going = arith.cmpi eq, %acc, %c1 : i64
      %next = scf.if %going -> (i64) {
        %j = trikeshed.bisect %seen, %x : !s64, i64 -> index
        %gone = arith.cmpi slt, %j, %z : index
        %n1 = scf.if %gone -> (i64) {
          %k = func.call @nxsi_strike(%x) : (i64) -> i64
          scf.yield %k : i64
        } else {
          scf.yield %c1 : i64
        }
        scf.yield %n1 : i64
      } else {
        scf.yield %acc : i64
      }
      trikeshed.yield %next : i64
    }
    %done = arith.cmpi eq, %st, %c1 : i64
    scf.if %done {
      func.call @nxsi_ws(%c40, %s) : (i64, i64) -> ()
    }
    scf.yield %st : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// One pass over the directory: each entry matched with its row or indexed anew (si_entry), then, when the entries seen
// are not as many as the paths the index holds, the rows of those gone struck out.  A directory that is not there has
// no entry.  1, 0 or -1.
func.func private @nxsi_pass() -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c40 = arith.constant 40 : i64
  %dot = arith.constant 46 : i8
  %nob = arith.constant 0 : i8
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  func.call @nxsi_hs(%c8, %c0) : (i64, i64) -> ()
  %dp = func.call @nxsi_buf(%c10, %c0) : (i64, i64) -> !llvm.ptr
  %dir = func.call @nixsi_os_opendir(%dp) : (!llvm.ptr) -> !llvm.ptr
  %db = llvm.ptrtoint %dir : !llvm.ptr to i64
  %open = arith.cmpi ne, %db, %c0 : i64
  %st = scf.if %open -> (i64) {
    %noff = func.call @nixsi_os_name() : () -> i64
    %e0 = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
    %e0b = llvm.ptrtoint %e0 : !llvm.ptr to i64
    %ee, %se = scf.while (%e = %e0b, %s = %c1) : (i64, i64) -> (i64, i64) {
      %more = arith.cmpi ne, %e, %c0 : i64
      %fine = arith.cmpi eq, %s, %c1 : i64
      %run = arith.andi %more, %fine : i1
      scf.condition(%run) %e, %s : i64, i64
    } do {
    ^bb0(%ea: i64, %sa: i64):
      %ep = llvm.inttoptr %ea : i64 to !llvm.ptr
      %np = llvm.getelementptr %ep[%noff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %nn = func.call @strlen(%np) : (!llvm.ptr) -> i64
      %ed = func.call @nxsi_d(%ep, %c1) : (!llvm.ptr, i64) -> !d
      %em = builtin.unrealized_conversion_cast %ed : !d to !m64
      %es = builtin.unrealized_conversion_cast %em : !m64 to !s64
      %dino = trikeshed.at %es[%z] : !s64, index -> i64
      %nd = func.call @nxsi_d(%np, %nn) : (!llvm.ptr, i64) -> !d
      %nm = builtin.unrealized_conversion_cast %nd : !d to !m
      %nb = builtin.unrealized_conversion_cast %nm : !m to !s
      %has1 = arith.cmpi sge, %nn, %c1 : i64
      %b0 = scf.if %has1 -> (i8) {
        %x0 = trikeshed.at %nb[%z] : !s, index -> i8
        scf.yield %x0 : i8
      } else {
        scf.yield %nob : i8
      }
      %has2 = arith.cmpi sge, %nn, %c2 : i64
      %b1 = scf.if %has2 -> (i8) {
        %x1 = trikeshed.at %nb[%i1] : !s, index -> i8
        scf.yield %x1 : i8
      } else {
        scf.yield %nob : i8
      }
      %d0 = arith.cmpi eq, %b0, %dot : i8
      %d1 = arith.cmpi eq, %b1, %dot : i8
      %one = arith.cmpi eq, %nn, %c1 : i64
      %two = arith.cmpi eq, %nn, %c2 : i64
      %self = arith.andi %one, %d0 : i1
      %up0 = arith.andi %two, %d0 : i1
      %up = arith.andi %up0, %d1 : i1
      %skip = arith.ori %self, %up : i1
      %r = scf.if %skip -> (i64) {
        scf.yield %c1 : i64
      } else {
        // the entry's type, the byte before its name: 8 a regular file
        %tp0 = arith.subi %noff, %c1 : i64
        %tpp = llvm.getelementptr %ep[%tp0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %tyd = func.call @nxsi_d(%tpp, %c1) : (!llvm.ptr, i64) -> !d
        %tym = builtin.unrealized_conversion_cast %tyd : !d to !m
        %tys = builtin.unrealized_conversion_cast %tym : !m to !s
        %ty8 = trikeshed.at %tys[%z] : !s, index -> i8
        %ty = arith.extui %ty8 : i8 to i64
        %k = func.call @nxsi_entry(%np, %nn, %dino, %ty) : (!llvm.ptr, i64, i64, i64) -> i64
        scf.yield %k : i64
      }
      %en = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
      %enb = llvm.ptrtoint %en : !llvm.ptr to i64
      scf.yield %enb, %r : i64, i64
    }
    %rc = func.call @closedir(%dir) : (!llvm.ptr) -> i32
    scf.yield %se : i64
  } else {
    scf.yield %c1 : i64
  }
  %ok = arith.cmpi eq, %st, %c1 : i64
  %r2 = scf.if %ok -> (i64) {
    %seen = func.call @nxsi_hg(%c8) : (i64) -> i64
    %lives = func.call @nxsi_w(%c40) : (i64) -> i64
    %differ = arith.cmpi ne, %seen, %lives : i64
    %sw = scf.if %differ -> (i64) {
      %w = func.call @nxsi_sweep() : () -> i64
      scf.yield %w : i64
    } else {
      scf.yield %c1 : i64
    }
    scf.yield %sw : i64
  } else {
    scf.yield %st : i64
  }
  return %r2 : i64
}

// The index made to hold the directory as it is.  Nothing to do when its token is the directory's (unless `force`: a
// query of every path reads the directory whatever the token says, as allValidPaths always did).  Else: the directory
// stamped, a pass, and the token again; a directory that changed under the pass is passed again (three times at most).
// Then the token written, when it is one to hold.  When the rows struck out are thousands more than the live ones the
// index is begun again first.  1 answered, 0 no room, -1 not sound.
func.func private @nxsi_sync(%force: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c40 = arith.constant 40 : i64
  %c64 = arith.constant 64 : i64
  %c4096 = arith.constant 4096 : i64
  %cur = func.call @nxsi_w(%c16) : (i64) -> i64
  %t0 = func.call @nxsi_token() : () -> i64
  %set = arith.cmpi ne, %cur, %c0 : i64
  %eq = arith.cmpi eq, %t0, %cur : i64
  %insync = arith.andi %set, %eq : i1
  %lazy = arith.cmpi eq, %force, %c0 : i64
  %quick = arith.andi %insync, %lazy : i1
  %r = scf.if %quick -> (i64) {
    scf.yield %c1 : i64
  } else {
    %dead = func.call @nxsi_w(%c64) : (i64) -> i64
    %lives = func.call @nxsi_w(%c40) : (i64) -> i64
    %lim = arith.addi %lives, %c4096 : i64
    %bloated = arith.cmpi sgt, %dead, %lim : i64
    scf.if %bloated {
      %again0 = func.call @nxsi_init() : () -> i1
    }
    %lean = arith.cmpi sle, %dead, %lim : i64
    %keep0 = arith.andi %insync, %lean : i1
    %pe, %te, %se = scf.while (%pass = %c0, %tok = %c0, %st = %c2) : (i64, i64, i64) -> (i64, i64, i64) {
      %again = arith.cmpi eq, %st, %c2 : i64
      scf.condition(%again) %pass, %tok, %st : i64, i64, i64
    } do {
    ^bb0(%pa: i64, %ta: i64, %sa: i64):
      %first = arith.cmpi eq, %pa, %c0 : i64
      %keep = arith.andi %first, %keep0 : i1
      %t = scf.if %keep -> (i64) {
        func.call @nxsi_hs(%c12, %c1) : (i64, i64) -> ()
        scf.yield %t0 : i64
      } else {
        %ts = func.call @nxsi_stamp() : () -> i64
        scf.yield %ts : i64
      }
      %p = func.call @nxsi_pass() : () -> i64
      %t2 = func.call @nxsi_token() : () -> i64
      %stable = arith.cmpi eq, %t2, %t : i64
      %last = arith.cmpi sge, %pa, %c2 : i64
      %okp = arith.cmpi eq, %p, %c1 : i64
      %s0 = arith.select %last, %c3, %c2 : i64
      %s1 = arith.select %stable, %c1, %s0 : i64
      %s2 = arith.select %okp, %s1, %p : i64
      %pn = arith.addi %pa, %c1 : i64
      scf.yield %pn, %t, %s2 : i64, i64, i64
    }
    %settled = arith.cmpi eq, %se, %c1 : i64
    %tokset = arith.cmpi ne, %te, %c0 : i64
    %hold = func.call @nxsi_hg(%c12) : (i64) -> i64
    %holds = arith.cmpi ne, %hold, %c0 : i64
    %pub0 = arith.andi %settled, %tokset : i1
    %pub = arith.andi %pub0, %holds : i1
    %okimg = func.call @nxsi_ok() : () -> i1
    %new = arith.select %pub, %te, %c0 : i64
    %was = func.call @nxsi_w(%c16) : (i64) -> i64
    %differs = arith.cmpi ne, %was, %new : i64
    %write = arith.andi %okimg, %differs : i1
    scf.if %write {
      func.call @nxsi_hw(%c16, %new) : (i64, i64) -> ()
    }
    %moved = arith.cmpi eq, %se, %c3 : i64
    %answered = arith.ori %settled, %moved : i1
    %rr = arith.select %answered, %c1, %se : i64
    scf.yield %rr : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// The answers
//===----------------------------------------------------------------------===//

// The records that may refer to a name: the rows of the references under the name's key and under the key of all, those
// whose record the paths still hold (alpha: each asked once; where: the held ones), drained into room 8.  Their count, -1
// when the index is not sound.
func.func private @nxsi_cands(%np: !llvm.ptr, %nn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %key = func.call @nxsi_key(%np, %nn) : (!llvm.ptr, i64) -> i64
  %n1 = func.call @nxsi_find(%c1, %key, %c1, %c0) : (i64, i64, i64, i64) -> i64
  %ok1 = arith.cmpi sge, %n1, %c0 : i64
  %n2 = scf.if %ok1 -> (i64) {
    %k = func.call @nxsi_find(%c1, %m1, %c1, %n1) : (i64, i64, i64, i64) -> i64
    scf.yield %k : i64
  } else {
    scf.yield %m1 : i64
  }
  %ok2 = arith.cmpi sge, %n2, %c0 : i64
  %r = scf.if %ok2 -> (i64) {
    %vp = func.call @nxsi_buf(%c1, %c0) : (i64, i64) -> !llvm.ptr
    %vd = func.call @nxsi_d(%vp, %n2) : (!llvm.ptr, i64) -> !d
    %vm = builtin.unrealized_conversion_cast %vd : !d to !m64
    %vs = builtin.unrealized_conversion_cast %vm : !m64 to !s64
    %held = trikeshed.alpha %vs : !s64 -> !s64 {
    ^bb0(%x: i64):
      %l = func.call @nxsi_is_live(%x) : (i64) -> i64
      trikeshed.yield %l : i64
    }
    %unsound = trikeshed.fold %held, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %l: i64):
      %neg = arith.cmpi slt, %l, %c0 : i64
      %a = arith.select %neg, %c1, %acc : i64
      trikeshed.yield %a : i64
    }
    %ni = arith.index_cast %n2 : i64 to index
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%i: index):
      %i64x = arith.index_cast %i : index to i64
      trikeshed.yield %i64x : i64
    }
    %live = trikeshed.where %idx : !s64 -> !s64 {
    ^bb0(%j: i64):
      %ji = arith.index_cast %j : i64 to index
      %h = trikeshed.at %held[%ji] : !s64, index -> i64
      %is = arith.cmpi eq, %h, %c1 : i64
      trikeshed.yield %is : i1
    }
    %m = trikeshed.size %live : !s64
    %m64x = arith.index_cast %m : index to i64
    %mb0 = arith.addi %m64x, %c1 : i64
    %mb = arith.muli %mb0, %c8 : i64
    %lp = func.call @nxsi_buf(%c8, %mb) : (i64, i64) -> !llvm.ptr
    %ld = func.call @nxsi_d(%lp, %m64x) : (!llvm.ptr, i64) -> !d
    %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
    %recs = trikeshed.series %m : !s64 {
    ^bb0(%q: index):
      %j2 = trikeshed.at %live[%q] : !s64, index -> i64
      %j2i = arith.index_cast %j2 : i64 to index
      %rx = trikeshed.at %vs[%j2i] : !s64, index -> i64
      trikeshed.yield %rx : i64
    }
    %e = trikeshed.drain %recs, %lm : !s64, !m64 -> index
    %bad = arith.cmpi ne, %unsound, %c0 : i64
    %rr = arith.select %bad, %m1, %m64x : i64
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// The names of n records (their places at offs), given to the store: the listed ones (a valid path's), in the order
// of their bytes (sorted, the comparison of two names), each once (where: unlike the one before), as one combineAll of
// the names drained once into room 9; the lock let go; then each name, by the combineAll's coordinates.
func.func private @nxsi_emit(%offs: !llvm.ptr, %n: i64, %ctx: !llvm.ptr, %ctx2: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c65535 = arith.constant 65535 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %some = arith.cmpi sgt, %n, %c0 : i64
  scf.if %some {
    %end = func.call @nxsi_w(%c8) : (i64) -> i64
    %base = func.call @nxsi_p(%c0) : (i64) -> !llvm.ptr
    %id = func.call @nxsi_d(%base, %end) : (!llvm.ptr, i64) -> !d
    %im = builtin.unrealized_conversion_cast %id : !d to !m
    %img = builtin.unrealized_conversion_cast %im : !m to !s
    %od = func.call @nxsi_d(%offs, %n) : (!llvm.ptr, i64) -> !d
    %om = builtin.unrealized_conversion_cast %od : !d to !m64
    %ov = builtin.unrealized_conversion_cast %om : !m64 to !s64
    %ni = arith.index_cast %n : i64 to index
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%i: index):
      %i64x = arith.index_cast %i : index to i64
      trikeshed.yield %i64x : i64
    }
    %lst = trikeshed.where %idx : !s64 -> !s64 {
    ^bb0(%j: i64):
      %ji = arith.index_cast %j : i64 to index
      %x = trikeshed.at %ov[%ji] : !s64, index -> i64
      %t = func.call @nxsi_rec(%x) : (i64) -> i64
      %fl = arith.shrui %t, %c8 : i64
      %l = arith.andi %fl, %c1 : i64
      %is = arith.cmpi eq, %l, %c1 : i64
      trikeshed.yield %is : i1
    }
    %srt = trikeshed.sorted %lst : !s64 -> !s64 by {
    ^bb0(%a: i64, %b: i64):
      %ai = arith.index_cast %a : i64 to index
      %bi = arith.index_cast %b : i64 to index
      %xa = trikeshed.at %ov[%ai] : !s64, index -> i64
      %xb = trikeshed.at %ov[%bi] : !s64, index -> i64
      %ta = func.call @nxsi_w(%xa) : (i64) -> i64
      %tb = func.call @nxsi_w(%xb) : (i64) -> i64
      %la0 = arith.shrui %ta, %c16 : i64
      %lb0 = arith.shrui %tb, %c16 : i64
      %la = arith.andi %la0, %c65535 : i64
      %lb = arith.andi %lb0, %c65535 : i64
      %oa = arith.addi %xa, %c24 : i64
      %ob = arith.addi %xb, %c24 : i64
      %oai = arith.index_cast %oa : i64 to index
      %obi = arith.index_cast %ob : i64 to index
      %lai = arith.index_cast %la : i64 to index
      %lbi = arith.index_cast %lb : i64 to index
      %na = trikeshed.slice %img[%oai, %lai] : !s -> !s
      %nb = trikeshed.slice %img[%obi, %lbi] : !s -> !s
      %c = trikeshed.compare %na, %nb unsigned : !s, !s
      trikeshed.yield %c : i32
    }
    %ms = trikeshed.size %srt : !s64
    %pos = trikeshed.series %ms : !s64 {
    ^bb0(%i: index):
      %i64y = arith.index_cast %i : index to i64
      trikeshed.yield %i64y : i64
    }
    %uniq = trikeshed.where %pos : !s64 -> !s64 {
    ^bb0(%k: i64):
      %first = arith.cmpi eq, %k, %c0 : i64
      %new = scf.if %first -> (i1) {
        scf.yield %first : i1
      } else {
        %ki = arith.index_cast %k : i64 to index
        %kp = arith.subi %ki, %i1 : index
        %ea = trikeshed.at %srt[%kp] : !s64, index -> i64
        %eb = trikeshed.at %srt[%ki] : !s64, index -> i64
        %eai = arith.index_cast %ea : i64 to index
        %ebi = arith.index_cast %eb : i64 to index
        %ya = trikeshed.at %ov[%eai] : !s64, index -> i64
        %yb = trikeshed.at %ov[%ebi] : !s64, index -> i64
        %ua = func.call @nxsi_w(%ya) : (i64) -> i64
        %ub = func.call @nxsi_w(%yb) : (i64) -> i64
        %ma0 = arith.shrui %ua, %c16 : i64
        %mb0 = arith.shrui %ub, %c16 : i64
        %ma = arith.andi %ma0, %c65535 : i64
        %mb = arith.andi %mb0, %c65535 : i64
        %pa = arith.addi %ya, %c24 : i64
        %pb = arith.addi %yb, %c24 : i64
        %pai = arith.index_cast %pa : i64 to index
        %pbi = arith.index_cast %pb : i64 to index
        %mai = arith.index_cast %ma : i64 to index
        %mbi = arith.index_cast %mb : i64 to index
        %sa = trikeshed.slice %img[%pai, %mai] : !s -> !s
        %sb = trikeshed.slice %img[%pbi, %mbi] : !s -> !s
        %cc = trikeshed.compare %sa, %sb unsigned : !s, !s
        %ne = arith.cmpi ne, %cc, %z32 : i32
        scf.yield %ne : i1
      }
      trikeshed.yield %new : i1
    }
    %mu = trikeshed.size %uniq : !s64
    %all, %where = trikeshed.combineAll %mu : !s, !sp {
    ^bb0(%k: index):
      %u = trikeshed.at %uniq[%k] : !s64, index -> i64
      %ui = arith.index_cast %u : i64 to index
      %ee = trikeshed.at %srt[%ui] : !s64, index -> i64
      %eei = arith.index_cast %ee : i64 to index
      %y = trikeshed.at %ov[%eei] : !s64, index -> i64
      %ty = func.call @nxsi_w(%y) : (i64) -> i64
      %ly0 = arith.shrui %ty, %c16 : i64
      %ly = arith.andi %ly0, %c65535 : i64
      %oy = arith.addi %y, %c24 : i64
      %oyi = arith.index_cast %oy : i64 to index
      %lyi = arith.index_cast %ly : i64 to index
      %nm = trikeshed.slice %img[%oyi, %lyi] : !s -> !s
      trikeshed.yield %nm : !s
    }
    %total = trikeshed.size %all : !s
    %total64 = arith.index_cast %total : index to i64
    %rb = arith.addi %total64, %c8 : i64
    %room = func.call @nxsi_buf(%c9, %rb) : (i64, i64) -> !llvm.ptr
    %rd = func.call @nxsi_d(%room, %total64) : (!llvm.ptr, i64) -> !d
    %rm = builtin.unrealized_conversion_cast %rd : !d to !m
    %e = trikeshed.drain %all, %rm : !s, !m -> index
    func.call @nxsi_unlock() : () -> ()
    scf.for %k = %z to %mu step %i1 {
      %co = trikeshed.at %where[%k] : !sp, index -> !tp
      %st32 = trikeshed.first %co : !tp -> i32
      %ln32 = trikeshed.second %co : !tp -> i32
      %st = arith.extui %st32 : i32 to i64
      %ln = arith.extui %ln32 : i32 to i64
      %p = llvm.getelementptr %room[%st] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      func.call @nixsi_name(%ctx, %ctx2, %p, %ln) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> ()
    }
  } else {
    func.call @nxsi_unlock() : () -> ()
  }
  return
}

//===----------------------------------------------------------------------===//
// The store's calls (lib/Store/LocalStore.cpp); f is a path's info file, `<stateDir>/info/<name>`
//===----------------------------------------------------------------------===//

// The text of the record at x, when the record reads back whole, holds its text and has the name asked for: the record's
// name and text copied into room 4 and summed there (what is given is what was checked, whatever another process
// writes meanwhile).  The text's bytes, at *out; -1 when the record does not answer.
func.func private @nxsi_take(%x: i64, %np: !llvm.ptr, %nn: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c24 = arith.constant 24 : i64
  %c32 = arith.constant 32 : i64
  %c255 = arith.constant 255 : i64
  %c65535 = arith.constant 65535 : i64
  %cm8 = arith.constant -8 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %t = func.call @nxsi_tag(%x) : (i64) -> i64
  %kind = arith.andi %t, %c255 : i64
  %fl = arith.shrui %t, %c8 : i64
  %nh = arith.andi %fl, %c2 : i64
  %nl0 = arith.shrui %t, %c16 : i64
  %nl = arith.andi %nl0, %c65535 : i64
  %tl = arith.shrui %t, %c32 : i64
  %by0 = arith.addi %nl, %tl : i64
  %by1 = arith.addi %by0, %c7 : i64
  %body = arith.andi %by1, %cm8 : i64
  %end = func.call @nxsi_w(%c8) : (i64) -> i64
  %x24 = arith.addi %x, %c24 : i64
  %past = arith.addi %x24, %body : i64
  %isrec = arith.cmpi eq, %kind, %c1 : i64
  %kept = arith.cmpi eq, %nh, %c0 : i64
  %fits = arith.cmpi sle, %past, %end : i64
  %named = arith.cmpi eq, %nl, %nn : i64
  %a = arith.andi %isrec, %kept : i1
  %b = arith.andi %a, %fits : i1
  %may = arith.andi %b, %named : i1
  %r = scf.if %may -> (i64) {
    %x8 = arith.addi %x, %c8 : i64
    %x16 = arith.addi %x, %c16 : i64
    %id = func.call @nxsi_w(%x8) : (i64) -> i64
    %stamp = func.call @nxsi_w(%x16) : (i64) -> i64
    %ob = arith.addi %body, %c8 : i64
    %op = func.call @nxsi_buf(%c4, %ob) : (i64, i64) -> !llvm.ptr
    %sp = func.call @nxsi_p(%x24) : (i64) -> !llvm.ptr
    %sd = func.call @nxsi_d(%sp, %body) : (!llvm.ptr, i64) -> !d
    %sm = builtin.unrealized_conversion_cast %sd : !d to !m
    %src = builtin.unrealized_conversion_cast %sm : !m to !s
    %dd = func.call @nxsi_d(%op, %body) : (!llvm.ptr, i64) -> !d
    %dm = builtin.unrealized_conversion_cast %dd : !d to !m
    %e = trikeshed.drain %src, %dm : !s, !m -> index
    %seed = arith.xori %t, %id : i64
    %bw = arith.shrui %body, %c3 : i64
    %got = func.call @nxsi_sum(%op, %bw, %seed) : (!llvm.ptr, i64, i64) -> i64
    %whole = arith.cmpi eq, %got, %stamp : i64
    %copy = builtin.unrealized_conversion_cast %dm : !m to !s
    %nli = arith.index_cast %nl : i64 to index
    %mine = trikeshed.slice %copy[%z, %nli] : !s -> !s
    %nd = func.call @nxsi_d(%np, %nn) : (!llvm.ptr, i64) -> !d
    %nm = builtin.unrealized_conversion_cast %nd : !d to !m
    %name = builtin.unrealized_conversion_cast %nm : !m to !s
    %cmp = trikeshed.compare %mine, %name unsigned : !s, !s
    %same = arith.cmpi eq, %cmp, %z32 : i32
    %ok = arith.andi %whole, %same : i1
    %tp = llvm.getelementptr %op[%nl] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    scf.if %ok {
      llvm.store %tp, %out : !llvm.ptr, !llvm.ptr
    }
    %rr = arith.select %ok, %tl, %m1 : i64
    scf.yield %rr : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// queryPathInfo: the info text the index holds for f's name, a copy the next call may overwrite, at *out; its bytes, or
// -1 when the index does not answer (there is none, it has not read the directory as it is now, it holds no record of
// the name or does not hold the record's text): the store then reads the file, as before.  Never makes or mends an
// index, and takes no lock: the index is read as it stands (HashTrie's readers take none either), what it gives is
// checked after it is copied (nxsi_take), and anything a writer was in the middle of reads as no answer.
func.func @nixsi_info(%f: !llvm.ptr, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c11 = arith.constant 11 : i64
  %c256 = arith.constant 256 : i64
  %m1 = arith.constant -1 : i64
  %end32 = arith.constant 2 : i32
  %start = func.call @nxsi_use(%f, %c0) : (!llvm.ptr, i64) -> i64
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %pol = func.call @nxsi_hg(%c11) : (i64) -> i64
  %none = arith.cmpi eq, %kind, %c0 : i64
  %untrusted = arith.cmpi eq, %pol, %c0 : i64
  %skip = arith.ori %none, %untrusted : i1
  %r = scf.if %skip -> (i64) {
    scf.yield %m1 : i64
  } else {
    // the file's length, asked again when it is not known to hold the first words or the heap the first words tell of
    %own = arith.cmpi eq, %kind, %c3 : i64
    %size0 = func.call @nxsi_hg(%c4) : (i64) -> i64
    %has0 = arith.cmpi sge, %size0, %c256 : i64
    %end0 = scf.if %has0 -> (i64) {
      %e0 = func.call @nxsi_w(%c8) : (i64) -> i64
      scf.yield %e0 : i64
    } else {
      scf.yield %c256 : i64
    }
    %behind = arith.cmpi sgt, %end0, %size0 : i64
    %yes = arith.constant 1 : i1
    %isfile = arith.xori %own, %yes : i1
    %ask = arith.andi %behind, %isfile : i1
    scf.if %ask {
      %fd64 = func.call @nxsi_hg(%c2) : (i64) -> i64
      %fd = arith.trunci %fd64 : i64 to i32
      %size = func.call @lseek(%fd, %c0, %end32) : (i32, i64, i32) -> i64
      func.call @nxsi_hs(%c4, %size) : (i64, i64) -> ()
    }
    %fresh = func.call @nxsi_fresh() : () -> i1
    %rr = scf.if %fresh -> (i64) {
      %n = func.call @strlen(%f) : (!llvm.ptr) -> i64
      %np = llvm.getelementptr %f[%start] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %nn = arith.subi %n, %start : i64
      %x = func.call @nxsi_live(%np, %nn) : (!llvm.ptr, i64) -> i64
      %held = arith.cmpi sgt, %x, %c0 : i64
      %r1 = scf.if %held -> (i64) {
        %tl = func.call @nxsi_take(%x, %np, %nn, %out) : (i64, !llvm.ptr, i64, !llvm.ptr) -> i64
        scf.yield %tl : i64
      } else {
        scf.yield %m1 : i64
      }
      scf.yield %r1 : i64
    } else {
      scf.yield %m1 : i64
    }
    scf.yield %rr : i64
  }
  return %r : i64
}

// allValidPaths (referring 0) and queryReferrers' candidates (referring 1): the index made to hold the directory (made
// when there is none; begun again when it is not sound; one of this process's own when the file cannot be written or
// locked, begun again for every query where the file system is not trusted to tell its changes), then every listed
// name in byte order, or the listed names of the records that may refer to f's name (the store keeps the ones whose
// info does).  Each name is given to nixsi_name(st, res, bytes, length) after the lock is let go.  A process that
// cannot have even an index of its own stops: no answer is better than a wrong one.
func.func @nixsi_names(%f: !llvm.ptr, %referring: i64, %ctx: !llvm.ptr, %ctx2: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %c11 = arith.constant 11 : i64
  %m1 = arith.constant -1 : i64
  %yes = arith.constant 1 : i1
  %start = func.call @nxsi_use(%f, %c1) : (!llvm.ptr, i64) -> i64
  %n = func.call @strlen(%f) : (!llvm.ptr) -> i64
  %np = llvm.getelementptr %f[%start] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %nn = arith.subi %n, %start : i64
  %lazy = arith.cmpi ne, %referring, %c0 : i64
  %force = arith.select %lazy, %c0, %c1 : i64
  %kind0 = func.call @nxsi_hg(%c1) : (i64) -> i64
  // a file that can only be read is used as it is when it holds the directory and the query is not of every path
  %isro = arith.cmpi eq, %kind0, %c2 : i64
  scf.if %isro {
    %locked = func.call @nxsi_lock(%c1) : (i64) -> i1
    %fresh = scf.if %locked -> (i1) {
      %fr = func.call @nxsi_fresh() : () -> i1
      scf.yield %fr : i1
    } else {
      scf.yield %locked : i1
    }
    %usable = arith.andi %lazy, %fresh : i1
    %not = arith.xori %usable, %yes : i1
    scf.if %not {
      func.call @nxsi_unlock() : () -> ()
      func.call @nxsi_anon() : () -> ()
    }
  }
  %isnone = arith.cmpi eq, %kind0, %c0 : i64
  scf.if %isnone {
    func.call @nxsi_anon() : () -> ()
  }
  %isfile = arith.cmpi eq, %kind0, %c1 : i64
  scf.if %isfile {
    %locked = func.call @nxsi_lock(%c2) : (i64) -> i1
    %not = arith.xori %locked, %yes : i1
    scf.if %not {
      func.call @nxsi_anon() : () -> ()
    }
  }
  %kind1 = func.call @nxsi_hg(%c1) : (i64) -> i64
  %pol = func.call @nxsi_hg(%c11) : (i64) -> i64
  %own = arith.cmpi eq, %kind1, %c3 : i64
  %untrusted = arith.cmpi eq, %pol, %c0 : i64
  %anew = arith.andi %own, %untrusted : i1
  scf.if %anew {
    %made = func.call @nxsi_init() : () -> i1
  }
  %te, %me = scf.while (%try = %c0, %m = %m1) : (i64, i64) -> (i64, i64) {
    %open = arith.cmpi eq, %m, %m1 : i64
    %left = arith.cmpi slt, %try, %c3 : i64
    %run = arith.andi %open, %left : i1
    scf.condition(%run) %try, %m : i64, i64
  } do {
  ^bb0(%ta: i64, %ma: i64):
    // a second try begins the index again; a third answers from one of this process's own
    %second = arith.cmpi eq, %ta, %c1 : i64
    %third = arith.cmpi eq, %ta, %c2 : i64
    scf.if %third {
      func.call @nxsi_unlock() : () -> ()
      func.call @nxsi_anon() : () -> ()
    }
    %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
    %k1 = arith.cmpi eq, %kind, %c1 : i64
    %k3 = arith.cmpi eq, %kind, %c3 : i64
    %writable = arith.ori %k1, %k3 : i1
    %ro = arith.cmpi eq, %kind, %c2 : i64
    %ready = scf.if %writable -> (i1) {
      %sound = func.call @nxsi_ok() : () -> i1
      %unsound = arith.xori %sound, %yes : i1
      %again = arith.ori %second, %third : i1
      %need = arith.ori %unsound, %again : i1
      %rd = scf.if %need -> (i1) {
        %made = func.call @nxsi_init() : () -> i1
        scf.yield %made : i1
      } else {
        scf.yield %sound : i1
      }
      scf.yield %rd : i1
    } else {
      scf.yield %ro : i1
    }
    %mn = scf.if %ready -> (i64) {
      %s = scf.if %writable -> (i64) {
        %sy = func.call @nxsi_sync(%force) : (i64) -> i64
        scf.yield %sy : i64
      } else {
        scf.yield %c1 : i64
      }
      %ok = arith.cmpi eq, %s, %c1 : i64
      %g = scf.if %ok -> (i64) {
        %g1 = scf.if %lazy -> (i64) {
          %cn = func.call @nxsi_cands(%np, %nn) : (!llvm.ptr, i64) -> i64
          scf.yield %cn : i64
        } else {
          %ln = func.call @nxsi_live_rows() : () -> i64
          scf.yield %ln : i64
        }
        scf.yield %g1 : i64
      } else {
        scf.yield %m1 : i64
      }
      scf.yield %g : i64
    } else {
      scf.yield %m1 : i64
    }
    %failed = arith.cmpi eq, %mn, %m1 : i64
    %rofail = arith.andi %ro, %failed : i1
    scf.if %rofail {
      func.call @nxsi_unlock() : () -> ()
      func.call @nxsi_anon() : () -> ()
    }
    %tn = arith.addi %ta, %c1 : i64
    scf.yield %tn, %mn : i64, i64
  }
  %none = arith.cmpi slt, %me, %c0 : i64
  scf.if %none {
    func.call @abort() : () -> ()
  }
  %lp = func.call @nxsi_buf(%c8, %c0) : (i64, i64) -> !llvm.ptr
  func.call @nxsi_emit(%lp, %me, %ctx, %ctx2) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
  return
}

// The index told of a change this process made to the directory, when it held the directory as it was before (keep):
// the record of the name struck out if there was one, and, when there are bytes (tn at least 0), the entry indexed from
// them under the identity given; then the token cleared.  The directory may have been changed by another at the same
// moment, by one that takes no lock: only a pass says, and the next query makes one, reading no file it has read.
func.func private @nxsi_told(%np: !llvm.ptr, %nn: i64, %ident: i64, %tp: !llvm.ptr, %tn: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c16 = arith.constant 16 : i64
  %cmax = arith.constant 1048576 : i64
  %m1 = arith.constant -1 : i64
  %x = func.call @nxsi_live(%np, %nn) : (!llvm.ptr, i64) -> i64
  %had = arith.cmpi sgt, %x, %c0 : i64
  %s0 = scf.if %had -> (i64) {
    %sk = func.call @nxsi_strike(%x) : (i64) -> i64
    scf.yield %sk : i64
  } else {
    %nothing = arith.cmpi eq, %x, %c0 : i64
    %s = arith.select %nothing, %c1, %m1 : i64
    scf.yield %s : i64
  }
  %ok0 = arith.cmpi eq, %s0, %c1 : i64
  %bytes = arith.cmpi sge, %tn, %c0 : i64
  %add = arith.andi %ok0, %bytes : i1
  scf.if %add {
    %small = arith.cmpi sle, %tn, %cmax : i64
    %tlen = arith.select %small, %tn, %m1 : i64
    %xn = func.call @nxsi_index(%np, %nn, %ident, %tp, %tlen) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  }
  func.call @nxsi_hw(%c16, %c0) : (i64, i64) -> ()
  return
}

// The file's lock taken alone for a change of the directory, when there is a file to write: whether the index holds the
// directory as it is (and is to be told of the change).
func.func private @nxsi_keep() -> i1 {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %kind = func.call @nxsi_hg(%c1) : (i64) -> i64
  %isfile = arith.cmpi eq, %kind, %c1 : i64
  %keep = scf.if %isfile -> (i1) {
    %locked = func.call @nxsi_lock(%c2) : (i64) -> i1
    %fresh = scf.if %locked -> (i1) {
      %fr = func.call @nxsi_fresh() : () -> i1
      scf.yield %fr : i1
    } else {
      scf.yield %locked : i1
    }
    scf.yield %fresh : i1
  } else {
    scf.yield %isfile : i1
  }
  return %keep : i1
}

// registerValidPath's write: the n bytes at tp written to `f.tmp` and that renamed to f, exactly as before (0; 1 when
// the file cannot be made, 2 when it cannot be written: errno says why).  The index is told (nxsi_told).
func.func @nixsi_register(%f: !llvm.ptr, %tp: !llvm.ptr, %tn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c32 = arith.constant 32 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i5 = arith.constant 5 : index
  %sbuf = llvm.alloca %c32 x i64 : (i64) -> !llvm.ptr
  %start = func.call @nxsi_use(%f, %c2) : (!llvm.ptr, i64) -> i64
  %keep = func.call @nxsi_keep() : () -> i1
  %n = func.call @strlen(%f) : (!llvm.ptr) -> i64
  %tb = arith.addi %n, %c8 : i64
  %tmp = func.call @nxsi_buf(%c6, %tb) : (i64, i64) -> !llvm.ptr
  %fd0 = func.call @nxsi_d(%f, %n) : (!llvm.ptr, i64) -> !d
  %fm = builtin.unrealized_conversion_cast %fd0 : !d to !m
  %fs = builtin.unrealized_conversion_cast %fm : !m to !s
  %wg = memref.get_global @nxsi_words : memref<16xi8>
  %words = trikeshed.text %wg : memref<16xi8> -> !s
  %ext = trikeshed.slice %words[%z, %i5] : !s -> !s
  %tpath = trikeshed.combine %fs, %ext : !s, !s -> !s
  %tl = arith.addi %n, %c5 : i64
  %td = func.call @nxsi_d(%tmp, %tl) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m
  %e = trikeshed.drain %tpath, %tm : !s, !m -> index
  %fd = func.call @nixsi_os_open(%tmp, %c3) : (!llvm.ptr, i64) -> i32
  %made = arith.cmpi sge, %fd, %z32 : i32
  %rc = scf.if %made -> (i64) {
    %oe, %se = scf.while (%off = %c0, %st = %c1) : (i64, i64) -> (i64, i64) {
      %more = arith.cmpi slt, %off, %tn : i64
      %fine = arith.cmpi eq, %st, %c1 : i64
      %run = arith.andi %more, %fine : i1
      scf.condition(%run) %off, %st : i64, i64
    } do {
    ^bb0(%oa: i64, %sa: i64):
      %at = llvm.getelementptr %tp[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %left = arith.subi %tn, %oa : i64
      %k = func.call @write(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
      %neg = arith.cmpi slt, %k, %c0 : i64
      %o2 = arith.addi %oa, %k : i64
      %on = arith.select %neg, %oa, %o2 : i64
      %sn = arith.select %neg, %c2, %c1 : i64
      scf.yield %on, %sn : i64, i64
    }
    %failed = arith.cmpi eq, %se, %c2 : i64
    %r1 = scf.if %failed -> (i64) {
      %rcc = func.call @close(%fd) : (i32) -> i32
      scf.yield %c2 : i64
    } else {
      %rs = func.call @nixsi_os_fstat(%fd, %sbuf) : (i32, !llvm.ptr) -> i32
      %ident = func.call @nxsi_ident(%sbuf) : (!llvm.ptr) -> i64
      %rcc = func.call @close(%fd) : (i32) -> i32
      %rr = func.call @rename(%tmp, %f) : (!llvm.ptr, !llvm.ptr) -> i32
      scf.if %keep {
        %np = llvm.getelementptr %f[%start] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %nn = arith.subi %n, %start : i64
        func.call @nxsi_told(%np, %nn, %ident, %tp, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
      }
      scf.yield %c0 : i64
    }
    scf.yield %r1 : i64
  } else {
    scf.yield %c1 : i64
  }
  func.call @nxsi_unlock() : () -> ()
  return %rc : i64
}

// deletePath's unlink of f.  The index is told (nxsi_told): the name's row struck out.
func.func @nixsi_unlink(%f: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %m1 = arith.constant -1 : i64
  %start = func.call @nxsi_use(%f, %c2) : (!llvm.ptr, i64) -> i64
  %keep = func.call @nxsi_keep() : () -> i1
  %ru = func.call @unlink(%f) : (!llvm.ptr) -> i32
  scf.if %keep {
    %n = func.call @strlen(%f) : (!llvm.ptr) -> i64
    %np = llvm.getelementptr %f[%start] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nn = arith.subi %n, %start : i64
    func.call @nxsi_told(%np, %nn, %c0, %np, %m1) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
  }
  func.call @nxsi_unlock() : () -> ()
  return
}
