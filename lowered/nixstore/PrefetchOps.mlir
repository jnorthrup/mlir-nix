// The prefetch list's row and order algebra (lib/Store/Prefetch.cpp) hollowed into the TrikeShed dialect.  The C++ keeps
// the file I/O (reading and writing the list, the directory listers, the io_uring ring and its requests), the threads,
// getcwd/getenv/system and the owning Texts the evaluator reads; the algebra is here:
//   nixstore_pf_count     the list's lines (trikeshed.parts at '\n'): the bound of its records
//   nixstore_pf_parse     each line read into a record (kind, the path's window, a value), in the list's order; an entry's
//                         line end becomes a NUL (the path is then a C string in the list)
//   nixstore_pf_mints     the minted bodies grouped by file: sorted (stable: minting order within a file) + where (a run per
//                         file), as columns (path window | first | count) and the rows in that order
//   nixstore_pf_find      a file's group: bisect over the path column
//   nixstore_pf_split     the entries to read ahead split into the directories to list and the rest (where)
//   nixstore_pf_warm      the ring's slot driver: W slots, a stack of free ones, each entry submitted to the next free slot,
//                         completions counted down per slot (submit and reap are the bridge's io_uring calls)
//   nixstore_pf_line      a recorded line: kind ' ' [cwd '/'] path [' ' row], one combine drained (fill-drain)
//   nixstore_pf_join      the recorded list: a combineAll of the lines and their '\n's, drained once
//   nixstore_pf_listname  auto's list name: FNV-1a over cwd and the arguments (each followed by 0xff) as a fold over a
//                         combineAll, then "/" 16 hex digits ".list"
//
// A record is 24 bytes {i64 cls, i64 at, i64 val}; at = start << 32 | length, the path's window in the list text.
//   cls 1 an entry to read ahead (`K path`): val = the kind byte, | 256 when it is a .nix file (F, a line of more than
//         6 bytes ending ".nix")
//   cls 2 a minted body (`M path row`: the path ends at the last ' ', after the third byte): val = the row (what follows
//         that ' ' read as strtoull reads it, kept to 32 bits)
//   cls 3 a hashed tree (`H root`), cls 4 a filtered one (`G root`)
//   cls 5 an entry a filter kept (`g path`, after a G with none but g lines between): val = that G's ordinal among the
//         H and G records
// A line of two bytes or fewer, or whose second byte is not ' ', is no record (nor is an `M` line with no ' ' after its
// third byte, nor a `g` line not after a G).
!s = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m32 = memref<?xi32, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @nxpf_nix : memref<4xi8> = dense<"0x2e6e6978">
memref.global "private" constant @nxpf_nl : memref<1xi8> = dense<10>
memref.global "private" constant @nxpf_ff : memref<1xi8> = dense<-1>
memref.global "private" constant @nxpf_slash : memref<1xi8> = dense<47>
memref.global "private" constant @nxpf_list : memref<5xi8> = dense<"0x2e6c697374">
memref.global "private" constant @nxpf_hex : memref<16xi8> = dense<"0x30313233343536373839616263646566">
memref.global "private" constant @nxpf_pow : memref<10xi64> = dense<[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000]>

//===----------------------------------------------------------------------===//
// Windows and records
//===----------------------------------------------------------------------===//

func.func private @nxpf_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// record i: (cls, at, val)
func.func private @nxpf_rec(%r: !llvm.ptr, %i: i64) -> (i64, i64, i64) {
  %c24 = arith.constant 24 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %off = arith.muli %i, %c24 : i64
  %rp = llvm.getelementptr %r[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %cls = llvm.load %rp : !llvm.ptr -> i64
  %ap = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %at = llvm.load %ap : !llvm.ptr -> i64
  %vp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %val = llvm.load %vp : !llvm.ptr -> i64
  return %cls, %at, %val : i64, i64, i64
}

func.func private @nxpf_put(%r: !llvm.ptr, %i: i64, %cls: i64, %at: i64, %val: i64) {
  %c24 = arith.constant 24 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %off = arith.muli %i, %c24 : i64
  %rp = llvm.getelementptr %r[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %cls, %rp : i64, !llvm.ptr
  %ap = llvm.getelementptr %rp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %at, %ap : i64, !llvm.ptr
  %vp = llvm.getelementptr %rp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %val, %vp : i64, !llvm.ptr
  return
}

// at = start << 32 | length
func.func private @nxpf_at(%start: index, %len: index) -> i64 {
  %c32 = arith.constant 32 : i64
  %s = arith.index_cast %start : index to i64
  %l = arith.index_cast %len : index to i64
  %hi = arith.shli %s, %c32 : i64
  %at = arith.ori %hi, %l : i64
  return %at : i64
}

func.func private @nxpf_unat(%at: i64) -> (index, index) {
  %c32 = arith.constant 32 : i64
  %mask = arith.constant 4294967295 : i64
  %s = arith.shrui %at, %c32 : i64
  %l = arith.andi %at, %mask : i64
  %si = arith.index_cast %s : i64 to index
  %li = arith.index_cast %l : i64 to index
  return %si, %li : index, index
}

// the byte order of the windows at a and b in the text (memcmp's sign, then the shorter first)
func.func private @nxpf_cmp(%tp: !llvm.ptr, %tn: i64, %a: i64, %b: i64) -> i32 {
  %dt = func.call @nxpf_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %mt = builtin.unrealized_conversion_cast %dt : !d to !m
  %text = builtin.unrealized_conversion_cast %mt : !m to !s
  %as, %al = func.call @nxpf_unat(%a) : (i64) -> (index, index)
  %bs, %bl = func.call @nxpf_unat(%b) : (i64) -> (index, index)
  %wa = trikeshed.slice %text[%as, %al] : !s -> !s
  %wb = trikeshed.slice %text[%bs, %bl] : !s -> !s
  %c = trikeshed.compare %wa, %wb unsigned : !s, !s
  return %c : i32
}

// what strtoull makes of the bytes (Nix/Numbers.h readUnsigned, CharSeries.h readInteger<10, false>): white space, a
// sign, the digits, saturating at 2^64 - 1; a '-' negates the magnitude (modulo 2^64) unless it saturated
func.func private @nxpf_readu(%xs: !s) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %max = arith.constant -1 : i64
  %b0 = arith.constant 48 : i8
  %b9 = arith.constant 57 : i8
  %bsp = arith.constant 32 : i8
  %btab = arith.constant 9 : i8
  %bcr = arith.constant 13 : i8
  %bplus = arith.constant 43 : i8
  %bminus = arith.constant 45 : i8
  %f = arith.constant false
  %t = arith.constant true
  %n = trikeshed.size %xs : !s
  // white space: ' ' and \t \n \v \f \r (9 to 13)
  %i0 = scf.while (%i = %c0) : (index) -> index {
    %in = arith.cmpi ult, %i, %n : index
    %ws = scf.if %in -> (i1) {
      %b = trikeshed.at %xs[%i] : !s, index -> i8
      %sp = arith.cmpi eq, %b, %bsp : i8
      %lo = arith.cmpi uge, %b, %btab : i8
      %hi = arith.cmpi ule, %b, %bcr : i8
      %ctl = arith.andi %lo, %hi : i1
      %w = arith.ori %sp, %ctl : i1
      scf.yield %w : i1
    } else {
      scf.yield %f : i1
    }
    scf.condition(%ws) %i : index
  } do {
  ^bb0(%i: index):
    %i1 = arith.addi %i, %c1 : index
    scf.yield %i1 : index
  }
  %in0 = arith.cmpi ult, %i0, %n : index
  %sg:2 = scf.if %in0 -> (index, i1) {
    %b = trikeshed.at %xs[%i0] : !s, index -> i8
    %pl = arith.cmpi eq, %b, %bplus : i8
    %mi = arith.cmpi eq, %b, %bminus : i8
    %sign = arith.ori %pl, %mi : i1
    %ip = arith.addi %i0, %c1 : index
    %at = arith.select %sign, %ip, %i0 : index
    scf.yield %at, %mi : index, i1
  } else {
    scf.yield %i0, %f : index, i1
  }
  %acc:3 = scf.while (%i = %sg#0, %v = %z, %over = %f) : (index, i64, i1) -> (index, i64, i1) {
    %in = arith.cmpi ult, %i, %n : index
    %dig = scf.if %in -> (i1) {
      %b = trikeshed.at %xs[%i] : !s, index -> i8
      %ge = arith.cmpi uge, %b, %b0 : i8
      %le = arith.cmpi ule, %b, %b9 : i8
      %dd = arith.andi %ge, %le : i1
      scf.yield %dd : i1
    } else {
      scf.yield %f : i1
    }
    scf.condition(%dig) %i, %v, %over : index, i64, i1
  } do {
  ^bb0(%i: index, %v: i64, %over: i1):
    %b = trikeshed.at %xs[%i] : !s, index -> i8
    %db = arith.subi %b, %b0 : i8
    %d = arith.extui %db : i8 to i64
    %room = arith.subi %max, %d : i64
    %lim = arith.divui %room, %ten : i64
    %big = arith.cmpi ugt, %v, %lim : i64
    %sat = arith.ori %over, %big : i1
    %v10 = arith.muli %v, %ten : i64
    %vd = arith.addi %v10, %d : i64
    %nv = arith.select %sat, %max, %vd : i64
    %i1 = arith.addi %i, %c1 : index
    scf.yield %i1, %nv, %sat : index, i64, i1
  }
  %negv = arith.subi %z, %acc#1 : i64
  %signed = arith.select %sg#1, %negv, %acc#1 : i64
  %val = arith.select %acc#2, %max, %signed : i64
  return %val : i64
}

//===----------------------------------------------------------------------===//
// Replay: the list read into records
//===----------------------------------------------------------------------===//

func.func @nixstore_pf_count(%p: !llvm.ptr, %n: i64) -> i64 {
  %dt = func.call @nxpf_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mt = builtin.unrealized_conversion_cast %dt : !d to !m
  %text = builtin.unrealized_conversion_cast %mt : !m to !s
  %nl = arith.constant 10 : i8
  %ls = trikeshed.parts %text, %nl : !s, i8 -> !sp
  %k = trikeshed.size %ls : !sp
  %k64 = arith.index_cast %k : index to i64
  return %k64 : i64
}

func.func @nixstore_pf_parse(%p: !llvm.ptr, %n: i64, %recs: !llvm.ptr) -> i64 {
  %dt = func.call @nxpf_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %mt = builtin.unrealized_conversion_cast %dt : !d to !m
  %text = builtin.unrealized_conversion_cast %mt : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c4 = arith.constant 4 : index
  %c6 = arith.constant 6 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 3 : i64
  %k4 = arith.constant 4 : i64
  %k5 = arith.constant 5 : i64
  %k256 = arith.constant 256 : i64
  %mask32 = arith.constant 4294967295 : i64
  %f = arith.constant false
  %nl = arith.constant 10 : i8
  %sp = arith.constant 32 : i8
  %bM = arith.constant 77 : i8
  %bH = arith.constant 72 : i8
  %bG = arith.constant 71 : i8
  %bg = arith.constant 103 : i8
  %bF = arith.constant 70 : i8
  %nul = arith.constant 0 : i8
  %ng = memref.get_global @nxpf_nix : memref<4xi8>
  %dotnix = trikeshed.text %ng : memref<4xi8> -> !s
  %ls = trikeshed.parts %text, %nl : !s, i8 -> !sp
  %nls = trikeshed.size %ls : !sp
  %res:3 = scf.for %j = %c0 to %nls step %c1 iter_args(%k = %z, %h = %z, %filt = %f) -> (i64, i64, i1) {
    %lc = trikeshed.at %ls[%j] : !sp, index -> !tp
    %s32 = trikeshed.first %lc : !tp -> i32
    %l32 = trikeshed.second %lc : !tp -> i32
    %st = arith.index_castui %s32 : i32 to index
    %ln = arith.index_castui %l32 : i32 to index
    %long = arith.cmpi ugt, %ln, %c2 : index
    %r:3 = scf.if %long -> (i64, i64, i1) {
      %st1 = arith.addi %st, %c1 : index
      %b1 = trikeshed.at %text[%st1] : !s, index -> i8
      %spaced = arith.cmpi eq, %b1, %sp : i8
      %r2:3 = scf.if %spaced -> (i64, i64, i1) {
        %c = trikeshed.at %text[%st] : !s, index -> i8
        %st2 = arith.addi %st, %c2 : index
        %ln2 = arith.subi %ln, %c2 : index
        %rest = func.call @nxpf_at(%st2, %ln2) : (index, index) -> i64
        %isM = arith.cmpi eq, %c, %bM : i8
        %r3:3 = scf.if %isM -> (i64, i64, i1) {
          // a minted body: the path runs to the last ' ', the row follows it
          %line = trikeshed.slice %text[%st, %ln] : !s -> !s
          %words = trikeshed.parts %line, %sp : !s, i8 -> !sp
          %nw = trikeshed.size %words : !sp
          %lastw = arith.subi %nw, %c1 : index
          %wl = trikeshed.at %words[%lastw] : !sp, index -> !tp
          %w32 = trikeshed.first %wl : !tp -> i32
          %wst = arith.index_castui %w32 : i32 to index
          %at = arith.subi %wst, %c1 : index
          %ok = arith.cmpi ugt, %at, %c2 : index
          %r4 = scf.if %ok -> (i64) {
            %pl = arith.subi %at, %c2 : index
            %path = func.call @nxpf_at(%st2, %pl) : (index, index) -> i64
            %nl0 = arith.subi %ln, %wst : index
            %num = trikeshed.slice %line[%wst, %nl0] : !s -> !s
            %v = func.call @nxpf_readu(%num) : (!s) -> i64
            %row = arith.andi %v, %mask32 : i64
            func.call @nxpf_put(%recs, %k, %k2, %path, %row) : (!llvm.ptr, i64, i64, i64, i64) -> ()
            %k1n = arith.addi %k, %one : i64
            scf.yield %k1n : i64
          } else {
            scf.yield %k : i64
          }
          scf.yield %r4, %h, %filt : i64, i64, i1
        } else {
          %isH = arith.cmpi eq, %c, %bH : i8
          %isG = arith.cmpi eq, %c, %bG : i8
          %tree = arith.ori %isH, %isG : i1
          %r5:3 = scf.if %tree -> (i64, i64, i1) {
            %cls = arith.select %isG, %k4, %k3 : i64
            func.call @nxpf_put(%recs, %k, %cls, %rest, %z) : (!llvm.ptr, i64, i64, i64, i64) -> ()
            %kn = arith.addi %k, %one : i64
            %hn = arith.addi %h, %one : i64
            scf.yield %kn, %hn, %isG : i64, i64, i1
          } else {
            %isg = arith.cmpi eq, %c, %bg : i8
            %r6 = scf.if %isg -> (i64) {
              // kept by the filter of the last tree, when that tree is filtered
              %any = arith.cmpi sgt, %h, %z : i64
              %owned = arith.andi %any, %filt : i1
              %r7 = scf.if %owned -> (i64) {
                %owner = arith.subi %h, %one : i64
                func.call @nxpf_put(%recs, %k, %k5, %rest, %owner) : (!llvm.ptr, i64, i64, i64, i64) -> ()
                %kn = arith.addi %k, %one : i64
                scf.yield %kn : i64
              } else {
                scf.yield %k : i64
              }
              scf.yield %r7 : i64
            } else {
              // an entry to read ahead; a .nix file is also one for the prelowering helpers
              %isF = arith.cmpi eq, %c, %bF : i8
              %big = arith.cmpi ugt, %ln, %c6 : index
              %maybe = arith.andi %isF, %big : i1
              %isNix = scf.if %maybe -> (i1) {
                %tail = arith.subi %ln, %c4 : index
                %ts = arith.addi %st, %tail : index
                %last4 = trikeshed.slice %text[%ts, %c4] : !s -> !s
                %cmp = trikeshed.compare %last4, %dotnix unsigned : !s, !s
                %z32 = arith.constant 0 : i32
                %eq = arith.cmpi eq, %cmp, %z32 : i32
                scf.yield %eq : i1
              } else {
                scf.yield %f : i1
              }
              %kind = arith.extui %c : i8 to i64
              %flag = arith.select %isNix, %k256, %z : i64
              %val = arith.ori %kind, %flag : i64
              func.call @nxpf_put(%recs, %k, %k1, %rest, %val) : (!llvm.ptr, i64, i64, i64, i64) -> ()
              // the line end (a '\n', or the end, where the list keeps a NUL) becomes a NUL: the path is a C string
              %end = arith.addi %st, %ln : index
              %inside = arith.cmpi ult, %end, %ni : index
              scf.if %inside {
                memref.store %nul, %mt[%end] : !m
              }
              %kn = arith.addi %k, %one : i64
              scf.yield %kn : i64
            }
            scf.yield %r6, %h, %filt : i64, i64, i1
          }
          scf.yield %r5#0, %r5#1, %r5#2 : i64, i64, i1
        }
        scf.yield %r3#0, %r3#1, %r3#2 : i64, i64, i1
      } else {
        scf.yield %k, %h, %filt : i64, i64, i1
      }
      scf.yield %r2#0, %r2#1, %r2#2 : i64, i64, i1
    } else {
      scf.yield %k, %h, %filt : i64, i64, i1
    }
    scf.yield %r#0, %r#1, %r#2 : i64, i64, i1
  }
  return %res#0 : i64
}

// The minted bodies by file.  groups is three columns of ng words: the path's window, the first row, the count; rows the
// rows (u32), a file's in minting order, the files in byte order.  Returns ng.
func.func @nixstore_pf_mints(%tp: !llvm.ptr, %tn: i64, %recs: !llvm.ptr, %k: i64, %groups: !llvm.ptr,
                             %rows: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %k2 = arith.constant 2 : i64
  %z32 = arith.constant 0 : i32
  %t = arith.constant true
  %ki = arith.index_cast %k : i64 to index
  %idx = trikeshed.series %ki : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %ms = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%i: i64):
    %cls, %at, %val = func.call @nxpf_rec(%recs, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %mint = arith.cmpi eq, %cls, %k2 : i64
    trikeshed.yield %mint : i1
  }
  %srt = trikeshed.sorted %ms : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %xc, %xa, %xv = func.call @nxpf_rec(%recs, %x) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %yc, %ya, %yv = func.call @nxpf_rec(%recs, %y) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %c = func.call @nxpf_cmp(%tp, %tn, %xa, %ya) : (!llvm.ptr, i64, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %nm = trikeshed.size %srt : !s64
  %pos = trikeshed.series %nm : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %starts = trikeshed.where %pos : !s64 -> !s64 {
  ^bb0(%j: i64):
    %first = arith.cmpi eq, %j, %z : i64
    %r = scf.if %first -> (i1) {
      scf.yield %t : i1
    } else {
      %one = arith.constant 1 : i64
      %jm = arith.subi %j, %one : i64
      %jmi = arith.index_cast %jm : i64 to index
      %ji = arith.index_cast %j : i64 to index
      %e1 = trikeshed.at %srt[%jmi] : !s64, index -> i64
      %e2 = trikeshed.at %srt[%ji] : !s64, index -> i64
      %c1c, %a1, %v1 = func.call @nxpf_rec(%recs, %e1) : (!llvm.ptr, i64) -> (i64, i64, i64)
      %c2c, %a2, %v2 = func.call @nxpf_rec(%recs, %e2) : (!llvm.ptr, i64) -> (i64, i64, i64)
      %c = func.call @nxpf_cmp(%tp, %tn, %a1, %a2) : (!llvm.ptr, i64, i64, i64) -> i32
      %ne = arith.cmpi ne, %c, %z32 : i32
      scf.yield %ne : i1
    }
    trikeshed.yield %r : i1
  }
  %ng = trikeshed.size %starts : !s64
  %ng64 = arith.index_cast %ng : index to i64
  %nm64 = arith.index_cast %nm : index to i64
  %c8 = arith.constant 8 : i64
  %firsts = llvm.getelementptr %groups[%ng64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  %twice = arith.addi %ng64, %ng64 : i64
  %counts = llvm.getelementptr %groups[%twice] : (!llvm.ptr, i64) -> !llvm.ptr, i64
  scf.for %g = %c0 to %ng step %c1 {
    %s = trikeshed.at %starts[%g] : !s64, index -> i64
    %g1 = arith.addi %g, %c1 : index
    %more = arith.cmpi ult, %g1, %ng : index
    %e = scf.if %more -> (i64) {
      %nx = trikeshed.at %starts[%g1] : !s64, index -> i64
      scf.yield %nx : i64
    } else {
      scf.yield %nm64 : i64
    }
    %si = arith.index_cast %s : i64 to index
    %r = trikeshed.at %srt[%si] : !s64, index -> i64
    %rc, %ra, %rv = func.call @nxpf_rec(%recs, %r) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %cnt = arith.subi %e, %s : i64
    %g64 = arith.index_cast %g : index to i64
    %ap = llvm.getelementptr %groups[%g64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    llvm.store %ra, %ap : i64, !llvm.ptr
    %fp = llvm.getelementptr %firsts[%g64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    llvm.store %s, %fp : i64, !llvm.ptr
    %cp = llvm.getelementptr %counts[%g64] : (!llvm.ptr, i64) -> !llvm.ptr, i64
    llvm.store %cnt, %cp : i64, !llvm.ptr
  }
  %vals = trikeshed.series %nm : !s32 {
  ^bb0(%j: index):
    %r = trikeshed.at %srt[%j] : !s64, index -> i64
    %rc, %ra, %rv = func.call @nxpf_rec(%recs, %r) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %v32 = arith.trunci %rv : i64 to i32
    trikeshed.yield %v32 : i32
  }
  %dr = func.call @nxpf_desc(%rows, %nm64) : (!llvm.ptr, i64) -> !d
  %mr = builtin.unrealized_conversion_cast %dr : !d to !m32
  %end = trikeshed.drain %vals, %mr : !s32, !m32 -> index
  return %ng64 : i64
}

// the group of the file at (kp, kn), or -1: bisect over the path column
func.func @nixstore_pf_find(%tp: !llvm.ptr, %tn: i64, %groups: !llvm.ptr, %ng: i64, %kp: !llvm.ptr,
                            %kn: i64) -> i64 {
  %dt = func.call @nxpf_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %mt = builtin.unrealized_conversion_cast %dt : !d to !m
  %text = builtin.unrealized_conversion_cast %mt : !m to !s
  %dk = func.call @nxpf_desc(%kp, %kn) : (!llvm.ptr, i64) -> !d
  %mk = builtin.unrealized_conversion_cast %dk : !d to !m
  %key = builtin.unrealized_conversion_cast %mk : !m to !s
  %dg = func.call @nxpf_desc(%groups, %ng) : (!llvm.ptr, i64) -> !d
  %mg = builtin.unrealized_conversion_cast %dg : !d to !m64
  %paths = builtin.unrealized_conversion_cast %mg : !m64 to !s64
  %zero = arith.constant 0 : i64
  %j = trikeshed.bisect %paths, %zero : !s64, i64 -> index by {
  ^bb0(%e: i64, %unused: i64):
    %es, %el = func.call @nxpf_unat(%e) : (i64) -> (index, index)
    %w = trikeshed.slice %text[%es, %el] : !s -> !s
    %c = trikeshed.compare %w, %key unsigned : !s, !s
    trikeshed.yield %c : i32
  }
  %c0 = arith.constant 0 : index
  %found = arith.cmpi sge, %j, %c0 : index
  %j64 = arith.index_cast %j : index to i64
  %m1 = arith.constant -1 : i64
  %r = arith.select %found, %j64, %m1 : i64
  return %r : i64
}

// the entries to read ahead: the directories (kind D) into dirs, the others into files (record indices, in the list's
// order); returns the directories' count, the others' into *nfiles
func.func @nixstore_pf_split(%recs: !llvm.ptr, %k: i64, %dirs: !llvm.ptr, %files: !llvm.ptr, %nfiles: !llvm.ptr) -> i64 {
  %k1 = arith.constant 1 : i64
  %bD = arith.constant 68 : i64
  %m255 = arith.constant 255 : i64
  %ki = arith.index_cast %k : i64 to index
  %idx = trikeshed.series %ki : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %ds = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%i: i64):
    %cls, %at, %val = func.call @nxpf_rec(%recs, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %entry = arith.cmpi eq, %cls, %k1 : i64
    %kind = arith.andi %val, %m255 : i64
    %dir = arith.cmpi eq, %kind, %bD : i64
    %both = arith.andi %entry, %dir : i1
    trikeshed.yield %both : i1
  }
  %fs = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%i: i64):
    %cls, %at, %val = func.call @nxpf_rec(%recs, %i) : (!llvm.ptr, i64) -> (i64, i64, i64)
    %entry = arith.cmpi eq, %cls, %k1 : i64
    %kind = arith.andi %val, %m255 : i64
    %file = arith.cmpi ne, %kind, %bD : i64
    %both = arith.andi %entry, %file : i1
    trikeshed.yield %both : i1
  }
  %nd = trikeshed.size %ds : !s64
  %nf = trikeshed.size %fs : !s64
  %nd64 = arith.index_cast %nd : index to i64
  %nf64 = arith.index_cast %nf : index to i64
  %dd = func.call @nxpf_desc(%dirs, %nd64) : (!llvm.ptr, i64) -> !d
  %md = builtin.unrealized_conversion_cast %dd : !d to !m64
  %e1 = trikeshed.drain %ds, %md : !s64, !m64 -> index
  %df = func.call @nxpf_desc(%files, %nf64) : (!llvm.ptr, i64) -> !d
  %mf = builtin.unrealized_conversion_cast %df : !d to !m64
  %e2 = trikeshed.drain %fs, %mf : !s64, !m64 -> index
  llvm.store %nf64, %nfiles : i64, !llvm.ptr
  return %nd64 : i64
}

// The ring's slot driver (warmFiles): w slots, free ones on a stack (the last freed taken first, slot w - 1 first of all);
// while entries are left and a slot is free, submit(ctx, slot, record) puts the entry's requests in the slot and says how
// many completions it waits for; then, while any are in flight, reap(ctx, done, cap) waits for completions and writes
// their slots into done, each counted down, a slot freed at 0.
func.func @nixstore_pf_warm(%ctx: !llvm.ptr, %files: !llvm.ptr, %nf: i64, %w: i64, %submit: !llvm.ptr,
                            %reap: !llvm.ptr) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %z = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %four = arith.constant 4 : i64
  %wi = arith.index_cast %w : i64 to index
  %cap = arith.muli %w, %four : i64
  %capi = arith.index_cast %cap : i64 to index
  %pending = memref.alloca(%wi) : memref<?xi64>
  %free = memref.alloca(%wi) : memref<?xi64>
  %done = memref.alloca(%capi) : memref<?xi64>
  scf.for %s = %c0 to %wi step %c1 {
    %s64 = arith.index_cast %s : index to i64
    memref.store %s64, %free[%s] : memref<?xi64>
    memref.store %z, %pending[%s] : memref<?xi64>
  }
  %dbase = memref.extract_aligned_pointer_as_index %done : memref<?xi64> -> index
  %dbase64 = arith.index_cast %dbase : index to i64
  %dptr = llvm.inttoptr %dbase64 : i64 to !llvm.ptr
  %out:3 = scf.while (%next = %z, %inflight = %z, %nfree = %w) : (i64, i64, i64) -> (i64, i64, i64) {
    %left = arith.cmpi slt, %next, %nf : i64
    %busy = arith.cmpi sgt, %inflight, %z : i64
    %go = arith.ori %left, %busy : i1
    scf.condition(%go) %next, %inflight, %nfree : i64, i64, i64
  } do {
  ^bb0(%next: i64, %inflight: i64, %nfree: i64):
    %sub:3 = scf.while (%n2 = %next, %i2 = %inflight, %f2 = %nfree) : (i64, i64, i64) -> (i64, i64, i64) {
      %has = arith.cmpi sgt, %f2, %z : i64
      %left = arith.cmpi slt, %n2, %nf : i64
      %go = arith.andi %has, %left : i1
      scf.condition(%go) %n2, %i2, %f2 : i64, i64, i64
    } do {
    ^bb0(%n2: i64, %i2: i64, %f2: i64):
      %rp = llvm.getelementptr %files[%n2] : (!llvm.ptr, i64) -> !llvm.ptr, i64
      %r = llvm.load %rp : !llvm.ptr -> i64
      %top = arith.subi %f2, %one : i64
      %topi = arith.index_cast %top : i64 to index
      %slot = memref.load %free[%topi] : memref<?xi64>
      %waits = llvm.call %submit(%ctx, %slot, %r) : !llvm.ptr, (!llvm.ptr, i64, i64) -> i64
      %si = arith.index_cast %slot : i64 to index
      memref.store %waits, %pending[%si] : memref<?xi64>
      %n3 = arith.addi %n2, %one : i64
      %i3 = arith.addi %i2, %one : i64
      scf.yield %n3, %i3, %top : i64, i64, i64
    }
    %busy = arith.cmpi sgt, %sub#1, %z : i64
    %after:2 = scf.if %busy -> (i64, i64) {
      %cnt = llvm.call %reap(%ctx, %dptr, %cap) : !llvm.ptr, (!llvm.ptr, !llvm.ptr, i64) -> i64
      %cnti = arith.index_cast %cnt : i64 to index
      %st:2 = scf.for %c = %c0 to %cnti step %c1 iter_args(%i4 = %sub#1, %f4 = %sub#2) -> (i64, i64) {
        %slot = memref.load %done[%c] : memref<?xi64>
        %si = arith.index_cast %slot : i64 to index
        %pv = memref.load %pending[%si] : memref<?xi64>
        %pv1 = arith.subi %pv, %one : i64
        memref.store %pv1, %pending[%si] : memref<?xi64>
        %fin = arith.cmpi eq, %pv1, %z : i64
        %res:2 = scf.if %fin -> (i64, i64) {
          %fi = arith.index_cast %f4 : i64 to index
          memref.store %slot, %free[%fi] : memref<?xi64>
          %f5 = arith.addi %f4, %one : i64
          %i5 = arith.subi %i4, %one : i64
          scf.yield %i5, %f5 : i64, i64
        } else {
          scf.yield %i4, %f4 : i64, i64
        }
        scf.yield %res#0, %res#1 : i64, i64
      }
      scf.yield %st#0, %st#1 : i64, i64
    } else {
      scf.yield %sub#1, %sub#2 : i64, i64
    }
    scf.yield %sub#0, %after#0, %after#1 : i64, i64, i64
  }
  return
}

//===----------------------------------------------------------------------===//
// Recording: the lines
//===----------------------------------------------------------------------===//

// kind ' ' [pre '/'] path [' ' row]: pre is the working directory of a relative path (slash 1), else empty (slash 0); row
// < 0 writes none.  Drained into `into` when it fits room; returns the size either way.
func.func @nixstore_pf_line(%kind: i64, %pre: !llvm.ptr, %pn: i64, %slash: i64, %p: !llvm.ptr, %pl: i64, %row: i64,
                            %into: !llvm.ptr, %room: i64) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c9 = arith.constant 9 : index
  %z = arith.constant 0 : i64
  %ten = arith.constant 10 : i64
  %sp = arith.constant 32 : i8
  %d0 = arith.constant 48 : i8
  %k8 = arith.trunci %kind : i64 to i8
  %head = trikeshed.series %c2 : !s {
  ^bb0(%i: index):
    %first = arith.cmpi eq, %i, %c0 : index
    %b = arith.select %first, %k8, %sp : i8
    trikeshed.yield %b : i8
  }
  %dpre = func.call @nxpf_desc(%pre, %pn) : (!llvm.ptr, i64) -> !d
  %mpre = builtin.unrealized_conversion_cast %dpre : !d to !m
  %cwd = builtin.unrealized_conversion_cast %mpre : !m to !s
  %sg = memref.get_global @nxpf_slash : memref<1xi8>
  %slashes = trikeshed.text %sg : memref<1xi8> -> !s
  %si = arith.index_cast %slash : i64 to index
  %sep = trikeshed.slice %slashes[%c0, %si] : !s -> !s
  %dp = func.call @nxpf_desc(%p, %pl) : (!llvm.ptr, i64) -> !d
  %mp = builtin.unrealized_conversion_cast %dp : !d to !m
  %path = builtin.unrealized_conversion_cast %mp : !m to !s
  // ' ' and the row's decimal digits (the count a fold over the powers of ten), none when row < 0
  %pg = memref.get_global @nxpf_pow : memref<10xi64>
  %powers = trikeshed.text %pg : memref<10xi64> -> !s64
  %above = trikeshed.slice %powers[%c1, %c9] : !s64 -> !s64
  %has = arith.cmpi sge, %row, %z : i64
  %digits = trikeshed.fold %above, %c1 : !s64, index -> index {
  ^bb0(%acc: index, %pw: i64):
    %reach = arith.cmpi uge, %row, %pw : i64
    %more = arith.addi %acc, %c1 : index
    %r = arith.select %reach, %more, %acc : index
    trikeshed.yield %r : index
  }
  %withsp = arith.addi %digits, %c1 : index
  %nt = arith.select %has, %withsp, %c0 : index
  %tail = trikeshed.series %nt : !s {
  ^bb0(%i: index):
    %first = arith.cmpi eq, %i, %c0 : index
    %e = arith.subi %withsp, %i : index
    %e1 = arith.subi %e, %c1 : index
    %top = arith.select %first, %c0, %e1 : index
    %pw = trikeshed.at %powers[%top] : !s64, index -> i64
    %q = arith.divui %row, %pw : i64
    %dd = arith.remui %q, %ten : i64
    %d8 = arith.trunci %dd : i64 to i8
    %ch = arith.addi %d8, %d0 : i8
    %b = arith.select %first, %sp, %ch : i8
    trikeshed.yield %b : i8
  }
  %all = trikeshed.combine %head, %cwd, %sep, %path, %tail : !s, !s, !s, !s, !s -> !s
  %size = trikeshed.size %all : !s
  %size64 = arith.index_cast %size : index to i64
  %fits = arith.cmpi sle, %size64, %room : i64
  scf.if %fits {
    %di = func.call @nxpf_desc(%into, %room) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m
    %end = trikeshed.drain %all, %mi : !s, !m -> index
  }
  return %size64 : i64
}

// the recorded lines, each followed by '\n': n Texts (16 bytes each: the bytes' pointer, then their count, a u32), one
// combineAll drained into `into` when it fits room; returns the size either way
func.func @nixstore_pf_join(%cells: !llvm.ptr, %n: i64, %into: !llvm.ptr, %room: i64) -> i64 {
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c0 = arith.constant 0 : index
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %nlg = memref.get_global @nxpf_nl : memref<1xi8>
  %newline = trikeshed.text %nlg : memref<1xi8> -> !s
  %ni = arith.index_cast %n : i64 to index
  %parts = arith.muli %ni, %c2 : index
  %all, %where = trikeshed.combineAll %parts : !s, !sp {
  ^bb0(%k: index):
    %line = arith.divui %k, %c2 : index
    %odd = arith.remui %k, %c2 : index
    %isnl = arith.cmpi eq, %odd, %c1 : index
    %l64 = arith.index_cast %line : index to i64
    %off = arith.muli %l64, %c16 : i64
    %cp = llvm.getelementptr %cells[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %bp = llvm.load %cp : !llvm.ptr -> !llvm.ptr
    %np = llvm.getelementptr %cp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %n32 = llvm.load %np : !llvm.ptr -> i32
    %bn = arith.extui %n32 : i32 to i64
    %db = func.call @nxpf_desc(%bp, %bn) : (!llvm.ptr, i64) -> !d
    %mb = builtin.unrealized_conversion_cast %db : !d to !m
    %bytes = builtin.unrealized_conversion_cast %mb : !m to !s
    %bni = arith.index_cast %bn : i64 to index
    %ln = arith.select %isnl, %c1, %bni : index
    %src = arith.select %isnl, %newline, %bytes : !s
    %part = trikeshed.slice %src[%c0, %ln] : !s -> !s
    trikeshed.yield %part : !s
  }
  %size = trikeshed.size %all : !s
  %size64 = arith.index_cast %size : index to i64
  %fits = arith.cmpi sle, %size64, %room : i64
  scf.if %fits {
    %di = func.call @nxpf_desc(%into, %room) : (!llvm.ptr, i64) -> !d
    %mi = builtin.unrealized_conversion_cast %di : !d to !m
    %end = trikeshed.drain %all, %mi : !s, !m -> index
  }
  return %size64 : i64
}

// auto's list name for n windows (16 bytes each: pointer, count): "/" then the 16 hex digits of FNV-1a over the windows,
// each followed by a 0xff byte (basis 1469598103934665603, prime 1099511628211), then ".list"; 22 bytes into `into`
func.func @nixstore_pf_listname(%wins: !llvm.ptr, %n: i64, %into: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  %c16 = arith.constant 16 : index
  %w8 = arith.constant 8 : i64
  %w16 = arith.constant 16 : i64
  %basis = arith.constant 1469598103934665603 : i64
  %prime = arith.constant 1099511628211 : i64
  %ffg = memref.get_global @nxpf_ff : memref<1xi8>
  %ff = trikeshed.text %ffg : memref<1xi8> -> !s
  %ni = arith.index_cast %n : i64 to index
  %parts = arith.muli %ni, %c2 : index
  %bytes, %where = trikeshed.combineAll %parts : !s, !sp {
  ^bb0(%k: index):
    %wi = arith.divui %k, %c2 : index
    %odd = arith.remui %k, %c2 : index
    %issep = arith.cmpi eq, %odd, %c1 : index
    %w64 = arith.index_cast %wi : index to i64
    %off = arith.muli %w64, %w16 : i64
    %wp = llvm.getelementptr %wins[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p = llvm.load %wp : !llvm.ptr -> !llvm.ptr
    %np = llvm.getelementptr %wp[%w8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %len = llvm.load %np : !llvm.ptr -> i64
    %dw = func.call @nxpf_desc(%p, %len) : (!llvm.ptr, i64) -> !d
    %mw = builtin.unrealized_conversion_cast %dw : !d to !m
    %win = builtin.unrealized_conversion_cast %mw : !m to !s
    %li = arith.index_cast %len : i64 to index
    %ln = arith.select %issep, %c1, %li : index
    %src = arith.select %issep, %ff, %win : !s
    %part = trikeshed.slice %src[%c0, %ln] : !s -> !s
    trikeshed.yield %part : !s
  }
  %h = trikeshed.fold %bytes, %basis : !s, i64 -> i64 {
  ^bb0(%acc: i64, %b: i8):
    %bu = arith.extui %b : i8 to i64
    %x = arith.xori %acc, %bu : i64
    %m = arith.muli %x, %prime : i64
    trikeshed.yield %m : i64
  }
  %hexg = memref.get_global @nxpf_hex : memref<16xi8>
  %hex = trikeshed.text %hexg : memref<16xi8> -> !s
  %digits = trikeshed.series %c16 : !s {
  ^bb0(%i: index):
    %c15 = arith.constant 15 : index
    %e = arith.subi %c15, %i : index
    %e64 = arith.index_cast %e : index to i64
    %four = arith.constant 4 : i64
    %sh = arith.muli %e64, %four : i64
    %q = arith.shrui %h, %sh : i64
    %f = arith.constant 15 : i64
    %nib = arith.andi %q, %f : i64
    %ni2 = arith.index_cast %nib : i64 to index
    %ch = trikeshed.at %hex[%ni2] : !s, index -> i8
    trikeshed.yield %ch : i8
  }
  %sg = memref.get_global @nxpf_slash : memref<1xi8>
  %slash = trikeshed.text %sg : memref<1xi8> -> !s
  %lg = memref.get_global @nxpf_list : memref<5xi8>
  %list = trikeshed.text %lg : memref<5xi8> -> !s
  %all = trikeshed.combine %slash, %digits, %list : !s, !s, !s -> !s
  %c22 = arith.constant 22 : i64
  %di = func.call @nxpf_desc(%into, %c22) : (!llvm.ptr, i64) -> !d
  %mi = builtin.unrealized_conversion_cast %di : !d to !m
  %end = trikeshed.drain %all, %mi : !s, !m -> index
  %e64 = arith.index_cast %end : index to i64
  return %e64 : i64
}
