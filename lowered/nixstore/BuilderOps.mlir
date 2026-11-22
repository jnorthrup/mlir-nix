// lib/Store/LocalStore.cpp's builder, the algorithms of it (the fork, the exec, the directory walks and the file reads
// stay C++: they are the system's calls).  In order:
//
//   nixstore_ts_cstrs     runBuilder's environment and argv: each row's `first=second` (a SortedMap<Text>'s rows) or
//                         `first` (a series of Text) and its NUL, one combineAll of the pieces drained once into one room;
//                         the pointer table is the combineAll's coordinates (where each piece starts) plus the null.
//   nixstore_ts_refindex  scanForReferences' table: the candidates' hash parts sorted (stable); of equal ones the last is
//                         kept, as the map byHash[hash] = candidate over the candidates in order kept the last.
//   nixstore_ts_refscan   scanForReferences' scan of one file's bytes: every window of 32 nix32 digits (one ends at each
//                         byte from the 32nd of a run on, so a longer run gives overlapping windows) looked up in the table
//                         (trikeshed.bisect), its candidate marked found.
//   nixstore_ts_infotext  registerValidPath's info file: path, narHash, narSize, a `ref:` line per reference, deriver and
//                         ca when there are, one combine of the lines (the refs a combineAll) drained once into one room.
//
// A Text row is {char *p, uint32 n, uint32 cap} (16 bytes; p is null in a Text that never held a byte, whose window is
// empty); a SortedMap<Text> row two of them.  A window (GWin) is {const char *p, int64 n}.  The rooms are the bridge's
// (nixbo_room: n bytes of a Text, alive as long as it).  Helper names are module-unique (nx_bo_*).
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the bridge's room: n bytes of the Text t (resized to n), returned
func.func private @nixbo_room(!llvm.ptr, i64) -> !llvm.ptr

// '=' and NUL
memref.global "private" constant @bo_eqnul : memref<2xi8> = dense<[61, 0]>
// the nix32 digits (0123456789abcdfghijklmnpqrsvwxyz): 1 at each
memref.global "private" constant @bo_nix32 : memref<256xi8> = dense<"0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000010101010001010101010101010100010101010000010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000">
// the info file's words: "path: " "\nnarHash: " "\nnarSize: " "\n" "ref: " "deriver: " "ca: "
memref.global "private" constant @bo_info : memref<45xi8> = dense<"0x706174683a200a6e6172486173683a200a6e617253697a653a200a7265663a20646572697665723a2063613a20">

// the descriptor of n bytes (or n i64 cells) at p
func.func private @nx_bo_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the Text at byte offset off of rows: its pointer and length
func.func private @nx_bo_textat(%rows: !llvm.ptr, %off: i64) -> (!llvm.ptr, i64) {
  %c8 = arith.constant 8 : i64
  %r = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %r : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %r[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %n = arith.extui %n32 : i32 to i64
  return %p, %n : !llvm.ptr, i64
}

// window i of an array of windows
func.func private @nx_bo_win(%w: !llvm.ptr, %i: i64) -> (!llvm.ptr, i64) {
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %off = arith.muli %i, %c16 : i64
  %wp = llvm.getelementptr %w[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %wp : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %wp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n = llvm.load %np : !llvm.ptr -> i64
  return %p, %n : !llvm.ptr, i64
}

// the byte order of windows i and j (Text's operator<: unsigned bytes, then the shorter first)
func.func private @nx_bo_cmpwin(%w: !llvm.ptr, %i: i64, %j: i64) -> i32 {
  %ip, %in = func.call @nx_bo_win(%w, %i) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %jp, %jn = func.call @nx_bo_win(%w, %j) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
  %a_d = func.call @nx_bo_desc(%ip, %in) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @nx_bo_desc(%jp, %jn) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c = trikeshed.compare %a, %b unsigned : !s, !s
  return %c : i32
}

//===----------------------------------------------------------------------===//
// The exec blocks
//===----------------------------------------------------------------------===//

// rows: n Text rows (pairs 0: 16 bytes each, `first` NUL) or SortedMap<Text> rows (pairs 1: 32 bytes, `first=second`
// NUL), in their order.  The strings are drained into one room of the Text at t; ptrs[k] is string k, ptrs[n] null.
// Returns the room's size.
func.func @nixstore_ts_cstrs(%t: !llvm.ptr, %rows: !llvm.ptr, %n: i64, %pairs: i64, %ptrs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %ispair = arith.cmpi ne, %pairs, %c0 : i64
  %sh = arith.select %ispair, %c1, %c0 : i64
  %stride0 = arith.shli %c16, %sh : i64
  %eg = memref.get_global @bo_eqnul : memref<2xi8>
  %eqnul = trikeshed.text %eg : memref<2xi8> -> !s
  %eqn = arith.select %ispair, %one, %z : index
  %eq = trikeshed.slice %eqnul[%z, %eqn] : !s -> !s
  %nul = trikeshed.slice %eqnul[%one, %one] : !s -> !s
  %ni = arith.index_cast %n : i64 to index
  %all, %where = trikeshed.combineAll %ni : !s, !pieces {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %off = arith.muli %k64, %stride0 : i64
    %fp, %fn = func.call @nx_bo_textat(%rows, %off) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %first_d = func.call @nx_bo_desc(%fp, %fn) : (!llvm.ptr, i64) -> !d
    %first_m = builtin.unrealized_conversion_cast %first_d : !d to !m
    %first = builtin.unrealized_conversion_cast %first_m : !m to !s
    // a pair's second Text; a single Text row has none (an empty window at the first's bytes, nothing read)
    %sp, %sn = scf.if %ispair -> (!llvm.ptr, i64) {
      %off2 = arith.addi %off, %c16 : i64
      %p2, %n2 = func.call @nx_bo_textat(%rows, %off2) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
      scf.yield %p2, %n2 : !llvm.ptr, i64
    } else {
      scf.yield %fp, %c0 : !llvm.ptr, i64
    }
    %second_d = func.call @nx_bo_desc(%sp, %sn) : (!llvm.ptr, i64) -> !d
    %second_m = builtin.unrealized_conversion_cast %second_d : !d to !m
    %second = builtin.unrealized_conversion_cast %second_m : !m to !s
    %piece = trikeshed.combine %first, %eq, %second, %nul : !s, !s, !s, !s -> !s
    trikeshed.yield %piece : !s
  }
  %size = trikeshed.size %all : !s
  %size64 = arith.index_cast %size : index to i64
  %room = func.call @nixbo_room(%t, %size64) : (!llvm.ptr, i64) -> !llvm.ptr
  %rd = func.call @nx_bo_desc(%room, %size64) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %end = trikeshed.drain %all, %rm : !s, !m -> index
  scf.for %k = %z to %ni step %one {
    %c = trikeshed.at %where[%k] : !pieces, index -> !tp
    %at32 = trikeshed.first %c : !tp -> i32
    %at = arith.extui %at32 : i32 to i64
    %sptr = llvm.getelementptr %room[%at] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %k64 = arith.index_cast %k : index to i64
    %slot = arith.muli %k64, %c8 : i64
    %dst = llvm.getelementptr %ptrs[%slot] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %sptr, %dst : !llvm.ptr, !llvm.ptr
  }
  %null = llvm.mlir.zero : !llvm.ptr
  %lo = arith.muli %n, %c8 : i64
  %ldst = llvm.getelementptr %ptrs[%lo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %null, %ldst : !llvm.ptr, !llvm.ptr
  return %size64 : i64
}

//===----------------------------------------------------------------------===//
// The references of an output
//===----------------------------------------------------------------------===//

// w: the n candidates' hash parts (windows), in the candidates' (sorted) order.  order gets the indices of the kept
// ones, in their hash parts' order; returns how many.
func.func @nixstore_ts_refindex(%w: !llvm.ptr, %n: i64, %order: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i32
  %one = arith.constant 1 : i64
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %c = func.call @nx_bo_cmpwin(%w, %x, %y) : (!llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  // the last of each run of equal hash parts
  %last = arith.subi %n, %one : i64
  %kept = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%k: i64):
    %end = arith.cmpi eq, %k, %last : i64
    %r = scf.if %end -> (i1) {
      %t = arith.constant 1 : i1
      scf.yield %t : i1
    } else {
      %ki = arith.index_cast %k : i64 to index
      %k1 = arith.addi %k, %one : i64
      %k1i = arith.index_cast %k1 : i64 to index
      %e1 = trikeshed.at %srt[%ki] : !s64, index -> i64
      %e2 = trikeshed.at %srt[%k1i] : !s64, index -> i64
      %c = func.call @nx_bo_cmpwin(%w, %e1, %e2) : (!llvm.ptr, i64, i64) -> i32
      %ne = arith.cmpi ne, %c, %c0 : i32
      scf.yield %ne : i1
    }
    trikeshed.yield %r : i1
  }
  %m = trikeshed.size %kept : !s64
  %z = arith.constant 0 : index
  %s1 = arith.constant 1 : index
  %c8 = arith.constant 8 : i64
  scf.for %j = %z to %m step %s1 {
    %k = trikeshed.at %kept[%j] : !s64, index -> i64
    %ki = arith.index_cast %k : i64 to index
    %e = trikeshed.at %srt[%ki] : !s64, index -> i64
    %j64 = arith.index_cast %j : index to i64
    %slot = arith.muli %j64, %c8 : i64
    %dst = llvm.getelementptr %order[%slot] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %e, %dst : i64, !llvm.ptr
  }
  %m64 = arith.index_cast %m : index to i64
  return %m64 : i64
}

// the n bytes at p scanned: each window of 32 nix32 digits looked up among the nu kept hash parts (w's windows by
// order's indices, in byte order); a hit sets found[its candidate] to 1.  Returns the hits.
func.func @nixstore_ts_refscan(%p: !llvm.ptr, %n: i64, %w: !llvm.ptr, %order: !llvm.ptr, %nu: i64,
                               %found: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c32 = arith.constant 32 : i64
  %b0 = arith.constant 0 : i8
  %b1 = arith.constant 1 : i8
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %i31 = arith.constant 31 : index
  %i32 = arith.constant 32 : index
  %data_d = func.call @nx_bo_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %data_m = builtin.unrealized_conversion_cast %data_d : !d to !m
  %data = builtin.unrealized_conversion_cast %data_m : !m to !s
  %tg = memref.get_global @bo_nix32 : memref<256xi8>
  %digit = trikeshed.text %tg : memref<256xi8> -> !s
  %od = func.call @nx_bo_desc(%order, %nu) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m64
  %kept = builtin.unrealized_conversion_cast %om : !m64 to !s64
  %ni = arith.index_cast %n : i64 to index
  %r:2 = scf.for %i = %z to %ni step %one iter_args(%run = %c0, %hits = %c0) -> (i64, i64) {
    %b = trikeshed.at %data[%i] : !s, index -> i8
    %bi = arith.index_castui %b : i8 to index
    %isd = trikeshed.at %digit[%bi] : !s, index -> i8
    %in = arith.cmpi ne, %isd, %b0 : i8
    %run1 = arith.addi %run, %c1 : i64
    %run2 = arith.select %in, %run1, %c0 : i64
    %full = arith.cmpi sge, %run2, %c32 : i64
    %h = scf.if %full -> (i64) {
      %from = arith.subi %i, %i31 : index
      %win = trikeshed.slice %data[%from, %i32] : !s -> !s
      %j = trikeshed.bisect %kept, %c0 : !s64, i64 -> index by {
      ^bb0(%e: i64, %key: i64):
        %ep, %en = func.call @nx_bo_win(%w, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        %es_d = func.call @nx_bo_desc(%ep, %en) : (!llvm.ptr, i64) -> !d
        %es_m = builtin.unrealized_conversion_cast %es_d : !d to !m
        %es = builtin.unrealized_conversion_cast %es_m : !m to !s
        %c = trikeshed.compare %es, %win unsigned : !s, !s
        trikeshed.yield %c : i32
      }
      %hit = arith.cmpi sge, %j, %z : index
      %h1 = scf.if %hit -> (i64) {
        %cand = trikeshed.at %kept[%j] : !s64, index -> i64
        %fp = llvm.getelementptr %found[%cand] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        llvm.store %b1, %fp : i8, !llvm.ptr
        %hn = arith.addi %hits, %c1 : i64
        scf.yield %hn : i64
      } else {
        scf.yield %hits : i64
      }
      scf.yield %h1 : i64
    } else {
      scf.yield %hits : i64
    }
    scf.yield %run2, %h : i64, i64
  }
  return %r#1 : i64
}

//===----------------------------------------------------------------------===//
// The info file
//===----------------------------------------------------------------------===//

// "path: " path "\nnarHash: " hash "\nnarSize: " size "\n", then "ref: " r "\n" for each of the nrefs Text rows at
// refs, then "deriver: " deriver "\n" and "ca: " ca "\n" when they are not empty: one combine drained once into the
// room of the Text at t.  size is narSize's decimal digits (a series of them, most significant first).
func.func @nixstore_ts_infotext(%t: !llvm.ptr, %pp: !llvm.ptr, %pn: i64, %hp: !llvm.ptr, %hn: i64, %narSize: i64,
                                %refs: !llvm.ptr, %nrefs: i64, %dp: !llvm.ptr, %dn: i64, %cp: !llvm.ptr,
                                %cn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c10 = arith.constant 10 : i64
  %c16 = arith.constant 16 : i64
  %c48 = arith.constant 48 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %i9 = arith.constant 9 : index
  %i10 = arith.constant 10 : index
  %i4 = arith.constant 4 : index
  %i16 = arith.constant 16 : index
  %i26 = arith.constant 26 : index
  %i27 = arith.constant 27 : index
  %i32 = arith.constant 32 : index
  %i41 = arith.constant 41 : index
  %ig = memref.get_global @bo_info : memref<45xi8>
  %words = trikeshed.text %ig : memref<45xi8> -> !s
  %wpath = trikeshed.slice %words[%z, %i6] : !s -> !s
  %whash = trikeshed.slice %words[%i6, %i10] : !s -> !s
  %wsize = trikeshed.slice %words[%i16, %i10] : !s -> !s
  %nl = trikeshed.slice %words[%i26, %i1] : !s -> !s
  %wref = trikeshed.slice %words[%i27, %i5] : !s -> !s
  %wder = trikeshed.slice %words[%i32, %i9] : !s -> !s
  %wca = trikeshed.slice %words[%i41, %i4] : !s -> !s
  %path_d = func.call @nx_bo_desc(%pp, %pn) : (!llvm.ptr, i64) -> !d
  %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
  %path = builtin.unrealized_conversion_cast %path_m : !m to !s
  %hash_d = func.call @nx_bo_desc(%hp, %hn) : (!llvm.ptr, i64) -> !d
  %hash_m = builtin.unrealized_conversion_cast %hash_d : !d to !m
  %hash = builtin.unrealized_conversion_cast %hash_m : !m to !s
  // narSize's digits: how many (1 for 0), then digit k = (narSize / 10^(nd-1-k)) % 10, unsigned
  %nd:2 = scf.while (%v = %narSize, %d = %i1) : (i64, index) -> (i64, index) {
    %more = arith.cmpi uge, %v, %c10 : i64
    scf.condition(%more) %v, %d : i64, index
  } do {
  ^bb0(%v1: i64, %d1: index):
    %q = arith.divui %v1, %c10 : i64
    %dn1 = arith.addi %d1, %i1 : index
    scf.yield %q, %dn1 : i64, index
  }
  %digits = trikeshed.series %nd#1 : !s {
  ^bb0(%k: index):
    %last = arith.subi %nd#1, %i1 : index
    %pw = arith.subi %last, %k : index
    %q = scf.for %s = %z to %pw step %i1 iter_args(%v = %narSize) -> (i64) {
      %v2 = arith.divui %v, %c10 : i64
      scf.yield %v2 : i64
    }
    %dig = arith.remui %q, %c10 : i64
    %ch = arith.addi %dig, %c48 : i64
    %ch8 = arith.trunci %ch : i64 to i8
    trikeshed.yield %ch8 : i8
  }
  %nri = arith.index_cast %nrefs : i64 to index
  %reflines, %where = trikeshed.combineAll %nri : !s, !pieces {
  ^bb0(%k: index):
    %k64 = arith.index_cast %k : index to i64
    %off = arith.muli %k64, %c16 : i64
    %rp, %rn = func.call @nx_bo_textat(%refs, %off) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
    %r_d = func.call @nx_bo_desc(%rp, %rn) : (!llvm.ptr, i64) -> !d
    %r_m = builtin.unrealized_conversion_cast %r_d : !d to !m
    %r = builtin.unrealized_conversion_cast %r_m : !m to !s
    %line = trikeshed.combine %wref, %r, %nl : !s, !s, !s -> !s
    trikeshed.yield %line : !s
  }
  // an empty deriver or ca writes no line: its word, its text and its newline all cut to nothing
  %hasd = arith.cmpi ne, %dn, %c0 : i64
  %dk = arith.select %hasd, %i9, %z : index
  %dl = arith.select %hasd, %i1, %z : index
  %wder1 = trikeshed.slice %wder[%z, %dk] : !s -> !s
  %nld = trikeshed.slice %nl[%z, %dl] : !s -> !s
  %der_d = func.call @nx_bo_desc(%dp, %dn) : (!llvm.ptr, i64) -> !d
  %der_m = builtin.unrealized_conversion_cast %der_d : !d to !m
  %der = builtin.unrealized_conversion_cast %der_m : !m to !s
  %hasc = arith.cmpi ne, %cn, %c0 : i64
  %ck = arith.select %hasc, %i4, %z : index
  %cl = arith.select %hasc, %i1, %z : index
  %wca1 = trikeshed.slice %wca[%z, %ck] : !s -> !s
  %nlc = trikeshed.slice %nl[%z, %cl] : !s -> !s
  %ca_d = func.call @nx_bo_desc(%cp, %cn) : (!llvm.ptr, i64) -> !d
  %ca_m = builtin.unrealized_conversion_cast %ca_d : !d to !m
  %ca = builtin.unrealized_conversion_cast %ca_m : !m to !s
  %all = trikeshed.combine %wpath, %path, %whash, %hash, %wsize, %digits, %nl, %reflines, %wder1, %der, %nld, %wca1,
                           %ca, %nlc : !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s, !s -> !s
  %size = trikeshed.size %all : !s
  %size64 = arith.index_cast %size : index to i64
  %room = func.call @nixbo_room(%t, %size64) : (!llvm.ptr, i64) -> !llvm.ptr
  %rd = func.call @nx_bo_desc(%room, %size64) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %end = trikeshed.drain %all, %rm : !s, !m -> index
  return %size64 : i64
}
