// The NAR byte emission and reading of lib/Store/StorePaths.cpp's NarWriter / restorePath, in the TrikeShed dialect.
//
// Writer (nixstore_ts_nardump).  The 14 NAR tokens are one constant blob of FRAMED tokens (each as the NAR frames it: u64
// length, the bytes, zero pad to 8), so a token is a constant slice of that blob and a node's header is one combine of
// slices drained once into the framing buffer.  A regular file's u64(size) is a series of 8 shifted bytes (a combine
// part), its contents go to the Sink through the file callback, and its pad + close one combine.  A directory's entries
// are read from the listing's windows and the sorted order words through trikeshed.at over i64 views made once per node;
// an entry's header (entry ( name str(name) node) is one combine, drained once; its close one slice.  StorePaths.cpp keeps,
// as callbacks on ctx (its NarWriter): the lstat, opendir/readdir, the file's bytes, readlink, the PathFilter, the
// prefetch notes, the Sink and the error wording.  The framing of a node goes to out and is flushed to the Sink before
// each call that may throw, as the tokens went one by one before: what a Sink saw before an error (`store --dump` writes
// it to stdout) is unchanged.  A callback reads the path as pb's first len bytes (a NUL after them); nothing here
// allocates except a series of a u64 part, so an error unwinds through these frames.
//
// Reader (nixstore_ts_narrestore): see the section below.  Both use the same callbacks' names as before.
!b = !trikeshed.series<i8>
!i32s = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @nar_zeros : memref<8xi8> = dense<0>
// the constant NAR tokens, one blob (the reader compares their raw bytes); nar_toff/nar_tlen give each id's slice (id 4 is the empty string)
memref.global "private" constant @nar_tokens : memref<79xi8> =
  dense<"0x2874797065726567756c617265786563757461626c65636f6e74656e74736469726563746f7279656e7472796e616d656e6f646573796d6c696e6b746172676574296e69782d617263686976652d31">
memref.global "private" constant @nar_toff : memref<14xi32> = dense<[0, 1, 5, 12, 22, 22, 30, 39, 44, 48, 52, 59, 65, 66]>
memref.global "private" constant @nar_tlen : memref<14xi32> = dense<[1, 4, 7, 10, 0, 8, 9, 5, 4, 4, 7, 6, 1, 13]>
// the framed tokens in id order: "(" 0 @0/16, "type" 1 @16/16, "regular" 2 @32/16, "executable" 3 @48/24, "" 4 @72/8 (3 and
// 4 are the executable pair: one slice of 32 bytes), "contents" 5 @80/16, "directory" 6 @96/24, "entry" 7 @120/16,
// "name" 8 @136/16, "node" 9 @152/16, "symlink" 10 @168/16, "target" 11 @184/16, ")" 12 @200/16, "nix-archive-1" 13 @216/24
// (lowered/nixstore/NarFraming.mlir's generator: scripts/gen-framed.py; 240 bytes)
memref.global "private" constant @nar_framed : memref<240xi8> =
  dense<"0x01000000000000002800000000000000040000000000000074797065000000000700000000000000726567756c6172000a0000000000000065786563757461626c6500000000000000000000000000000800000000000000636f6e74656e747309000000000000006469726563746f7279000000000000000500000000000000656e74727900000004000000000000006e616d650000000004000000000000006e6f646500000000070000000000000073796d6c696e6b0006000000000000007461726765740000010000000000000029000000000000000d000000000000006e69782d617263686976652d31000000">

// the descriptor of n i8 cells at p (a struct, not a memref: returning it allocates nothing and clones nothing)
func.func private @nar_desc(%p: !llvm.ptr, %n: i64) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %bb = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %bb[2] : !d
  %e = llvm.insertvalue %n, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

func.func private @nixstore_nar_room(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixstore_nw_sink(!llvm.ptr, i64)
func.func private @nixstore_nw_stat(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_nw_file(!llvm.ptr, i64, i64)
func.func private @nixstore_nw_dir(!llvm.ptr, i64, i64, !llvm.ptr) -> i64
func.func private @nixstore_nw_keep(!llvm.ptr, i64) -> i64
func.func private @nixstore_nw_link(!llvm.ptr, i64) -> i64
func.func private @nixstore_nw_odd(!llvm.ptr, i64)
func.func private @nixstore_ts_sortwins(!llvm.ptr, i64, !llvm.ptr)

memref.global "private" constant @narw_sep : memref<2xi8> = dense<[47, 0]>

// `at` past the n bytes at p
func.func private @narw_skip(%p: !llvm.ptr, %n: i64) -> !llvm.ptr {
  %q = llvm.getelementptr %p[%n] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %q : !llvm.ptr
}

// the path buffer's bytes [from, from + |piece| + 1) := piece then a NUL (one combine, drained once); the buffer is
// grown first, so the bytes before `from` are kept
func.func private @narw_put(%pb: !llvm.ptr, %from: i64, %pre: i64, %p: !llvm.ptr, %n: i64) {
  %c1 = arith.constant 1 : i64
  %c0i = arith.constant 0 : index
  %one = arith.constant 1 : index
  %len = arith.addi %pre, %n : i64
  %w = arith.addi %len, %c1 : i64
  %need = arith.addi %from, %w : i64
  %base = func.call @nixstore_nar_room(%pb, %need) : (!llvm.ptr, i64) -> !llvm.ptr
  %sg = memref.get_global @narw_sep : memref<2xi8>
  %sep = trikeshed.text %sg : memref<2xi8> -> !b
  %pre_i = arith.index_cast %pre : i64 to index
  %lead = trikeshed.slice %sep[%c0i, %pre_i] : !b -> !b
  %name_d = func.call @nar_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
  %name = builtin.unrealized_conversion_cast %name_m : !m to !b
  %nul = trikeshed.slice %sep[%one, %one] : !b -> !b
  %all = trikeshed.combine %lead, %name, %nul : !b, !b, !b -> !b
  %at = func.call @narw_skip(%base, %from) : (!llvm.ptr, i64) -> !llvm.ptr
  %od = func.call @nar_desc(%at, %w) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %all, %om : !b, !m -> index
  return
}

// The node whose path is pb's first len bytes; depth names the callback's listing buffer for a directory.
func.func private @narw_node(%ctx: !llvm.ptr, %pb: !llvm.ptr, %out: !llvm.ptr, %lk: !llvm.ptr, %len: i64, %depth: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c3 = arith.constant 3 : i64
  %c8i = arith.constant 8 : index
  %c64z = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i16 = arith.constant 16 : index
  %i24 = arith.constant 24 : index
  %i32 = arith.constant 32 : index
  %i48 = arith.constant 48 : index
  %i80 = arith.constant 80 : index
  %i96 = arith.constant 96 : index
  %i120 = arith.constant 120 : index
  %i136 = arith.constant 136 : index
  %i152 = arith.constant 152 : index
  %i168 = arith.constant 168 : index
  %i184 = arith.constant 184 : index
  %i200 = arith.constant 200 : index
  %cell = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
  // the framed tokens and the zeros, as constant slices of the one blob (spans in the @nar_framed comment)
  %fg = memref.get_global @nar_framed : memref<240xi8>
  %fr = trikeshed.text %fg : memref<240xi8> -> !b
  %zg = memref.get_global @nar_zeros : memref<8xi8>
  %zeros = trikeshed.text %zg : memref<8xi8> -> !b
  %t_open = trikeshed.slice %fr[%i0, %i16] : !b -> !b
  %t_type = trikeshed.slice %fr[%i16, %i16] : !b -> !b
  %t_reg = trikeshed.slice %fr[%i32, %i16] : !b -> !b
  %t_contents = trikeshed.slice %fr[%i80, %i16] : !b -> !b
  %t_dir = trikeshed.slice %fr[%i96, %i24] : !b -> !b
  %t_entry = trikeshed.slice %fr[%i120, %i16] : !b -> !b
  %t_name = trikeshed.slice %fr[%i136, %i16] : !b -> !b
  %t_node = trikeshed.slice %fr[%i152, %i16] : !b -> !b
  %t_sym = trikeshed.slice %fr[%i168, %i16] : !b -> !b
  %t_target = trikeshed.slice %fr[%i184, %i16] : !b -> !b
  %t_close = trikeshed.slice %fr[%i200, %i16] : !b -> !b
  %kind = func.call @nixstore_nw_stat(%ctx, %len, %cell) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %cv = func.call @nar_desc(%cell, %c2) : (!llvm.ptr, i64) -> !d
  %cm = builtin.unrealized_conversion_cast %cv : !d to !m64
  %cs = builtin.unrealized_conversion_cast %cm : !m64 to !s64
  %size = trikeshed.at %cs[%i0] : !s64, index -> i64
  %isreg = arith.cmpi ule, %kind, %c1 : i64
  scf.if %isreg {
    // regular: (, type, regular, [executable ""], contents, u64(size) -- one drain; then the bytes; then the pad and )
    %exec = arith.cmpi eq, %kind, %c1 : i64
    %pair_n = arith.select %exec, %i32, %i0 : index
    %t_pair = trikeshed.slice %fr[%i48, %pair_n] : !b -> !b
    %len8 = trikeshed.series %c8i : !b {
    ^bb0(%i: index):
      %i64 = arith.index_cast %i : index to i64
      %sh = arith.muli %i64, %c8 : i64
      %v = arith.shrui %size, %sh : i64
      %byte = arith.trunci %v : i64 to i8
      trikeshed.yield %byte : i8
    }
    %head = trikeshed.combine %t_open, %t_type, %t_reg, %t_pair, %t_contents, %len8 : !b, !b, !b, !b, !b, !b -> !b
    %hn = trikeshed.size %head : !b
    %hn64 = arith.index_cast %hn : index to i64
    %hd = func.call @nar_desc(%out, %hn64) : (!llvm.ptr, i64) -> !d
    %hm = builtin.unrealized_conversion_cast %hd : !d to !m
    %he = trikeshed.drain %head, %hm : !b, !m -> index
    %k6 = arith.index_cast %he : index to i64
    func.call @nixstore_nw_sink(%ctx, %k6) : (!llvm.ptr, i64) -> ()
    func.call @nixstore_nw_file(%ctx, %len, %size) : (!llvm.ptr, i64, i64) -> ()
    // the pad (8 - size%8 zero bytes when size%8 != 0) then ")"
    %rem = arith.remui %size, %c8 : i64
    %need = arith.subi %c8, %rem : i64
    %nz = arith.cmpi ne, %rem, %c64z : i64
    %k = arith.select %nz, %need, %c64z : i64
    %ki = arith.index_cast %k : i64 to index
    %pad = trikeshed.slice %zeros[%i0, %ki] : !b -> !b
    %tail = trikeshed.combine %pad, %t_close : !b, !b -> !b
    %tn = trikeshed.size %tail : !b
    %tn64 = arith.index_cast %tn : index to i64
    %td = func.call @nar_desc(%out, %tn64) : (!llvm.ptr, i64) -> !d
    %tm = builtin.unrealized_conversion_cast %td : !d to !m
    %te = trikeshed.drain %tail, %tm : !b, !m -> index
    %k7 = arith.index_cast %te : index to i64
    func.call @nixstore_nw_sink(%ctx, %k7) : (!llvm.ptr, i64) -> ()
  } else {
    %isdir = arith.cmpi eq, %kind, %c2 : i64
    scf.if %isdir {
      // directory: type directory, then each kept entry in byte order: entry ( name str(name) node <node> ) ... )
      %dhead = trikeshed.combine %t_open, %t_type, %t_dir : !b, !b, !b -> !b
      %dn = trikeshed.size %dhead : !b
      %dn64 = arith.index_cast %dn : index to i64
      %dd = func.call @nar_desc(%out, %dn64) : (!llvm.ptr, i64) -> !d
      %dm = builtin.unrealized_conversion_cast %dd : !d to !m
      %de = trikeshed.drain %dhead, %dm : !b, !m -> index
      %k2 = arith.index_cast %de : index to i64
      func.call @nixstore_nw_sink(%ctx, %k2) : (!llvm.ptr, i64) -> ()
      %n = func.call @nixstore_nw_dir(%ctx, %depth, %len, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
      %wins = trikeshed.at %cs[%i0] : !s64, index -> i64
      %orderw = trikeshed.at %cs[%i1] : !s64, index -> i64
      %wp = llvm.inttoptr %wins : i64 to !llvm.ptr
      %op = llvm.inttoptr %orderw : i64 to !llvm.ptr
      func.call @nixstore_ts_sortwins(%wp, %n, %op) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %n2 = arith.muli %n, %c2 : i64
      %wd = func.call @nar_desc(%wp, %n2) : (!llvm.ptr, i64) -> !d
      %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
      %ws = builtin.unrealized_conversion_cast %wm : !m64 to !s64
      %od = func.call @nar_desc(%op, %n) : (!llvm.ptr, i64) -> !d
      %om = builtin.unrealized_conversion_cast %od : !d to !m64
      %os = builtin.unrealized_conversion_cast %om : !m64 to !s64
      %ni = arith.index_cast %n : i64 to index
      %next = arith.addi %depth, %c1 : i64
      %nl = arith.addi %len, %c1 : i64
      scf.for %j = %i0 to %ni step %i1 {
        %e = trikeshed.at %os[%j] : !s64, index -> i64
        %ei = arith.index_cast %e : i64 to index
        %wi = arith.muli %ei, %i2 : index
        %wi1 = arith.addi %wi, %i1 : index
        %np64 = trikeshed.at %ws[%wi] : !s64, index -> i64
        %nn = trikeshed.at %ws[%wi1] : !s64, index -> i64
        %np = llvm.inttoptr %np64 : i64 to !llvm.ptr
        func.call @narw_put(%pb, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
        %clen = arith.addi %nl, %nn : i64
        %keep = func.call @nixstore_nw_keep(%ctx, %clen) : (!llvm.ptr, i64) -> i64
        %kept = arith.cmpi ne, %keep, %c64z : i64
        scf.if %kept {
          // entry ( name str(name) node: one combine drained at out; the name's u64 is a series, its bytes a view
          %nlen8 = trikeshed.series %c8i : !b {
          ^bb0(%i: index):
            %i64 = arith.index_cast %i : index to i64
            %sh = arith.muli %i64, %c8 : i64
            %v = arith.shrui %nn, %sh : i64
            %byte = arith.trunci %v : i64 to i8
            trikeshed.yield %byte : i8
          }
          %nd = func.call @nar_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
          %nm = builtin.unrealized_conversion_cast %nd : !d to !m
          %nbytes = builtin.unrealized_conversion_cast %nm : !m to !b
          %nni = arith.index_cast %nn : i64 to index
          %rem = arith.remui %nn, %c8 : i64
          %need = arith.subi %c8, %rem : i64
          %nz = arith.cmpi ne, %rem, %c64z : i64
          %k = arith.select %nz, %need, %c64z : i64
          %ki = arith.index_cast %k : i64 to index
          %npad = trikeshed.slice %zeros[%i0, %ki] : !b -> !b
          %ehead = trikeshed.combine %t_entry, %t_open, %t_name, %nlen8, %nbytes, %npad, %t_node : !b, !b, !b, !b, !b, !b, !b -> !b
          %en = trikeshed.size %ehead : !b
          %en64 = arith.index_cast %en : index to i64
          %ed = func.call @nar_desc(%out, %en64) : (!llvm.ptr, i64) -> !d
          %em = builtin.unrealized_conversion_cast %ed : !d to !m
          %ee = trikeshed.drain %ehead, %em : !b, !m -> index
          %e5 = arith.index_cast %ee : index to i64
          func.call @nixstore_nw_sink(%ctx, %e5) : (!llvm.ptr, i64) -> ()
          func.call @narw_node(%ctx, %pb, %out, %lk, %clen, %next) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> ()
          %ecd = func.call @nar_desc(%out, %c16) : (!llvm.ptr, i64) -> !d
          %ecm = builtin.unrealized_conversion_cast %ecd : !d to !m
          %ce = trikeshed.drain %t_close, %ecm : !b, !m -> index
          %e6 = arith.index_cast %ce : index to i64
          func.call @nixstore_nw_sink(%ctx, %e6) : (!llvm.ptr, i64) -> ()
        }
      }
      %kdd = func.call @nar_desc(%out, %c16) : (!llvm.ptr, i64) -> !d
      %kdm = builtin.unrealized_conversion_cast %kdd : !d to !m
      %kde = trikeshed.drain %t_close, %kdm : !b, !m -> index
      %k3 = arith.index_cast %kde : index to i64
      func.call @nixstore_nw_sink(%ctx, %k3) : (!llvm.ptr, i64) -> ()
    } else {
      %islnk = arith.cmpi eq, %kind, %c3 : i64
      scf.if %islnk {
        // symlink: type symlink target str(target) ), the link read before the str
        %lhead = trikeshed.combine %t_open, %t_type, %t_sym, %t_target : !b, !b, !b, !b -> !b
        %lhn = trikeshed.size %lhead : !b
        %lhn64 = arith.index_cast %lhn : index to i64
        %lhd = func.call @nar_desc(%out, %lhn64) : (!llvm.ptr, i64) -> !d
        %lhm = builtin.unrealized_conversion_cast %lhd : !d to !m
        %lhe = trikeshed.drain %lhead, %lhm : !b, !m -> index
        %k3 = arith.index_cast %lhe : index to i64
        func.call @nixstore_nw_sink(%ctx, %k3) : (!llvm.ptr, i64) -> ()
        %tn = func.call @nixstore_nw_link(%ctx, %len) : (!llvm.ptr, i64) -> i64
        %tlen8 = trikeshed.series %c8i : !b {
        ^bb0(%i: index):
          %i64 = arith.index_cast %i : index to i64
          %sh = arith.muli %i64, %c8 : i64
          %v = arith.shrui %tn, %sh : i64
          %byte = arith.trunci %v : i64 to i8
          trikeshed.yield %byte : i8
        }
        %ld = func.call @nar_desc(%lk, %tn) : (!llvm.ptr, i64) -> !d
        %lm = builtin.unrealized_conversion_cast %ld : !d to !m
        %lbytes = builtin.unrealized_conversion_cast %lm : !m to !b
        %tni = arith.index_cast %tn : i64 to index
        %trem = arith.remui %tn, %c8 : i64
        %tneed = arith.subi %c8, %trem : i64
        %tnz = arith.cmpi ne, %trem, %c64z : i64
        %tk = arith.select %tnz, %tneed, %c64z : i64
        %tki = arith.index_cast %tk : i64 to index
        %tpad = trikeshed.slice %zeros[%i0, %tki] : !b -> !b
        %ttail = trikeshed.combine %tlen8, %lbytes, %tpad, %t_close : !b, !b, !b, !b -> !b
        %tcn = trikeshed.size %ttail : !b
        %tcn64 = arith.index_cast %tcn : index to i64
        %tcd = func.call @nar_desc(%out, %tcn64) : (!llvm.ptr, i64) -> !d
        %tcm = builtin.unrealized_conversion_cast %tcd : !d to !m
        %tce = trikeshed.drain %ttail, %tcm : !b, !m -> index
        %k4 = arith.index_cast %tce : index to i64
        func.call @nixstore_nw_sink(%ctx, %k4) : (!llvm.ptr, i64) -> ()
      } else {
        // any other type: "(" was written, then the error
        %ohd = func.call @nar_desc(%out, %c16) : (!llvm.ptr, i64) -> !d
        %ohm = builtin.unrealized_conversion_cast %ohd : !d to !m
        %ohe = trikeshed.drain %t_open, %ohm : !b, !m -> index
        %k0 = arith.index_cast %ohe : index to i64
        func.call @nixstore_nw_sink(%ctx, %k0) : (!llvm.ptr, i64) -> ()
        func.call @nixstore_nw_odd(%ctx, %len) : (!llvm.ptr, i64) -> ()
      }
    }
  }
  return
}

func.func @nixstore_ts_nardump(%ctx: !llvm.ptr, %pb: !llvm.ptr, %out: !llvm.ptr, %lk: !llvm.ptr, %root: !llvm.ptr, %rn: i64) {
  %c0 = arith.constant 0 : i64
  %i0 = arith.constant 0 : index
  %i216 = arith.constant 216 : index
  %i24 = arith.constant 24 : index
  func.call @narw_put(%pb, %c0, %c0, %root, %rn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
  // the magic: str("nix-archive-1"), a framed token of the blob
  %fg = memref.get_global @nar_framed : memref<240xi8>
  %fr = trikeshed.text %fg : memref<240xi8> -> !b
  %magic = trikeshed.slice %fr[%i216, %i24] : !b -> !b
  %mn = trikeshed.size %magic : !b
  %mn64 = arith.index_cast %mn : index to i64
  %md = func.call @nar_desc(%out, %mn64) : (!llvm.ptr, i64) -> !d
  %mm = builtin.unrealized_conversion_cast %md : !d to !m
  %me = trikeshed.drain %magic, %mm : !b, !m -> index
  %k = arith.index_cast %me : index to i64
  func.call @nixstore_nw_sink(%ctx, %k) : (!llvm.ptr, i64) -> ()
  func.call @narw_node(%ctx, %pb, %out, %lk, %rn, %c0) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> ()
  return
}

//===----------------------------------------------------------------------===//
// The reader: restorePath
//===----------------------------------------------------------------------===//
//
// nixstore_ts_narrestore(pb, nar, size, root, rn) reads a NAR and makes its tree at root: the strings are read here (the
// u64 length, the bounds, the pad; the length added as the old size_t arithmetic added it, wrapping, and the string cut
// at the NAR's end as string_view::substr cut it), each one compared with the token the structure expects
// (trikeshed.compare against the token blob), an entry's name checked (empty, ".", "..", a '/' in it) and `dst/name`
// composed into the path buffer pb as the walk above composes it.  StorePaths.cpp keeps, as callbacks on pb: writeFile,
// symlink, mkdir and the error wording (nixstore_nr_fail: 0 truncated, 1 an expected token, 2 a bad tag, 3 an invalid
// name, 4 an unknown type), each called where the C++ walk threw or wrote.

func.func private @nixstore_nr_fail(!llvm.ptr, i64, !llvm.ptr, i64)
func.func private @nixstore_nr_file(!llvm.ptr, i64, !llvm.ptr, i64, i64)
func.func private @nixstore_nr_link(!llvm.ptr, i64, !llvm.ptr, i64)
func.func private @nixstore_nr_dir(!llvm.ptr, i64)

memref.global "private" constant @narr_dots : memref<2xi8> = dense<[46, 46]>

// the token id's address in the blob and its length
func.func private @narr_tok(%id: i64) -> (!llvm.ptr, i64) {
  %idi = arith.index_cast %id : i64 to index
  %og = memref.get_global @nar_toff : memref<14xi32>
  %offs = trikeshed.text %og : memref<14xi32> -> !i32s
  %off32 = trikeshed.at %offs[%idi] : !i32s, index -> i32
  %off = arith.index_cast %off32 : i32 to index
  %lg = memref.get_global @nar_tlen : memref<14xi32>
  %lens = trikeshed.text %lg : memref<14xi32> -> !i32s
  %len32 = trikeshed.at %lens[%idi] : !i32s, index -> i32
  %len64 = arith.extui %len32 : i32 to i64
  %tg = memref.get_global @nar_tokens : memref<79xi8>
  %base = memref.extract_aligned_pointer_as_index %tg : memref<79xi8> -> index
  %at = arith.addi %base, %off : index
  %at64 = arith.index_cast %at : index to i64
  %p = llvm.inttoptr %at64 : i64 to !llvm.ptr
  return %p, %len64 : !llvm.ptr, i64
}

// are the n bytes at nar + s the token id
func.func private @narr_is(%nar: !llvm.ptr, %s: i64, %n: i64, %id: i64) -> i1 {
  %at = func.call @narw_skip(%nar, %s) : (!llvm.ptr, i64) -> !llvm.ptr
  %xs_d = func.call @nar_desc(%at, %n) : (!llvm.ptr, i64) -> !d
  %xs_m = builtin.unrealized_conversion_cast %xs_d : !d to !m
  %xs = builtin.unrealized_conversion_cast %xs_m : !m to !b
  %tp, %tn = func.call @narr_tok(%id) : (i64) -> (!llvm.ptr, i64)
  %tok_d = func.call @nar_desc(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %tok_m = builtin.unrealized_conversion_cast %tok_d : !d to !m
  %tok = builtin.unrealized_conversion_cast %tok_m : !m to !b
  %c = trikeshed.compare %xs, %tok unsigned : !b, !b
  %z = arith.constant 0 : i32
  %eq = arith.cmpi eq, %c, %z : i32
  return %eq : i1
}

// the little-endian u64 at nar + p (its 8 shifted bytes or-folded; the series is freed before the caller goes on)
func.func private @narr_word(%nar: !llvm.ptr, %p: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %c8i = arith.constant 8 : index
  %at = func.call @narw_skip(%nar, %p) : (!llvm.ptr, i64) -> !llvm.ptr
  %xs_d = func.call @nar_desc(%at, %c8) : (!llvm.ptr, i64) -> !d
  %xs_m = builtin.unrealized_conversion_cast %xs_d : !d to !m
  %xs = builtin.unrealized_conversion_cast %xs_m : !m to !b
  %w = trikeshed.series %c8i : !s64 {
  ^bb0(%i: index):
    %b = trikeshed.at %xs[%i] : !b, index -> i8
    %b64 = arith.extui %b : i8 to i64
    %i64 = arith.index_cast %i : index to i64
    %e8 = arith.constant 8 : i64
    %sh = arith.muli %i64, %e8 : i64
    %v = arith.shli %b64, %sh : i64
    trikeshed.yield %v : i64
  }
  %n = trikeshed.fold %w, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %x: i64):
    %o = arith.ori %acc, %x : i64
    trikeshed.yield %o : i64
  }
  return %n : i64
}

// str(): the string at p as (start, length) and the position after its pad
func.func private @narr_str(%pb: !llvm.ptr, %nar: !llvm.ptr, %size: i64, %p: i64) -> (i64, i64, i64) {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %p8 = arith.addi %p, %c8 : i64
  %short = arith.cmpi ugt, %p8, %size : i64
  scf.if %short {
    func.call @nixstore_nr_fail(%pb, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  %n = func.call @narr_word(%nar, %p) : (!llvm.ptr, i64) -> i64
  %end = arith.addi %p8, %n : i64
  %over = arith.cmpi ugt, %end, %size : i64
  scf.if %over {
    func.call @nixstore_nr_fail(%pb, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  %avail = arith.subi %size, %p8 : i64
  %cnt = arith.minui %n, %avail : i64
  %rem = arith.remui %n, %c8 : i64
  %need = arith.subi %c8, %rem : i64
  %nz = arith.cmpi ne, %rem, %c0 : i64
  %k = arith.select %nz, %need, %c0 : i64
  %q = arith.addi %end, %k : i64
  return %p8, %cnt, %q : i64, i64, i64
}

// expect(token id) at p: the position after it
func.func private @narr_expect(%pb: !llvm.ptr, %nar: !llvm.ptr, %size: i64, %p: i64, %id: i64) -> i64 {
  %true = arith.constant true
  %s, %n, %q = func.call @narr_str(%pb, %nar, %size, %p) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
  %eq = func.call @narr_is(%nar, %s, %n, %id) : (!llvm.ptr, i64, i64, i64) -> i1
  %ne = arith.xori %eq, %true : i1
  scf.if %ne {
    %tp, %tn = func.call @narr_tok(%id) : (i64) -> (!llvm.ptr, i64)
    %c1 = arith.constant 1 : i64
    func.call @nixstore_nr_fail(%pb, %c1, %tp, %tn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  return %q : i64
}

// the node at p, made at pb's first len bytes: the position after it
func.func private @narr_node(%pb: !llvm.ptr, %nar: !llvm.ptr, %size: i64, %p: i64, %len: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %true = arith.constant true
  %null = llvm.inttoptr %c0 : i64 to !llvm.ptr
  %t_open = arith.constant 0 : i64
  %t_type = arith.constant 1 : i64
  %t_close = arith.constant 12 : i64
  %p1 = func.call @narr_expect(%pb, %nar, %size, %p, %t_open) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
  %p2 = func.call @narr_expect(%pb, %nar, %size, %p1, %t_type) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
  %ts, %tn, %p3 = func.call @narr_str(%pb, %nar, %size, %p2) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
  %t_reg = arith.constant 2 : i64
  %isreg = func.call @narr_is(%nar, %ts, %tn, %t_reg) : (!llvm.ptr, i64, i64, i64) -> i1
  %r = scf.if %isreg -> (i64) {
    // regular: [executable ""] contents str, the file written, then ")"
    %gs, %gn, %q1 = func.call @narr_str(%pb, %nar, %size, %p3) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
    %t_exec = arith.constant 3 : i64
    %exec = func.call @narr_is(%nar, %gs, %gn, %t_exec) : (!llvm.ptr, i64, i64, i64) -> i1
    %hs, %hn, %q2 = scf.if %exec -> (i64, i64, i64) {
      %xs, %xn, %x1 = func.call @narr_str(%pb, %nar, %size, %q1) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
      %ys, %yn, %y1 = func.call @narr_str(%pb, %nar, %size, %x1) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
      scf.yield %ys, %yn, %y1 : i64, i64, i64
    } else {
      scf.yield %gs, %gn, %q1 : i64, i64, i64
    }
    %t_contents = arith.constant 5 : i64
    %isc = func.call @narr_is(%nar, %hs, %hn, %t_contents) : (!llvm.ptr, i64, i64, i64) -> i1
    %notc = arith.xori %isc, %true : i1
    scf.if %notc {
      func.call @nixstore_nr_fail(%pb, %c2, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
    }
    %cs, %cn, %q3 = func.call @narr_str(%pb, %nar, %size, %q2) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
    %cp = func.call @narw_skip(%nar, %cs) : (!llvm.ptr, i64) -> !llvm.ptr
    %ex = arith.extui %exec : i1 to i64
    func.call @nixstore_nr_file(%pb, %len, %cp, %cn, %ex) : (!llvm.ptr, i64, !llvm.ptr, i64, i64) -> ()
    %q4 = func.call @narr_expect(%pb, %nar, %size, %q3, %t_close) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %q4 : i64
  } else {
    %t_sym = arith.constant 10 : i64
    %issym = func.call @narr_is(%nar, %ts, %tn, %t_sym) : (!llvm.ptr, i64, i64, i64) -> i1
    %r2 = scf.if %issym -> (i64) {
      // symlink: target str, the link made, then ")"
      %t_target = arith.constant 11 : i64
      %s1 = func.call @narr_expect(%pb, %nar, %size, %p3, %t_target) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
      %ls, %ln, %s2 = func.call @narr_str(%pb, %nar, %size, %s1) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
      %lp = func.call @narw_skip(%nar, %ls) : (!llvm.ptr, i64) -> !llvm.ptr
      func.call @nixstore_nr_link(%pb, %len, %lp, %ln) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
      %s3 = func.call @narr_expect(%pb, %nar, %size, %s2, %t_close) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %s3 : i64
    } else {
      %t_dir = arith.constant 6 : i64
      %isdir = func.call @narr_is(%nar, %ts, %tn, %t_dir) : (!llvm.ptr, i64, i64, i64) -> i1
      %notdir = arith.xori %isdir, %true : i1
      scf.if %notdir {
        %c4 = arith.constant 4 : i64
        func.call @nixstore_nr_fail(%pb, %c4, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
      }
      // directory: the directory made, then (entry ( name str node <node> ))* up to ")"
      func.call @nixstore_nr_dir(%pb, %len) : (!llvm.ptr, i64) -> ()
      %d:3 = scf.while (%q = %p3) : (i64) -> (i64, i64, i64) {
        %gs, %gn, %q1 = func.call @narr_str(%pb, %nar, %size, %q) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
        %isclose = func.call @narr_is(%nar, %gs, %gn, %t_close) : (!llvm.ptr, i64, i64, i64) -> i1
        %go = arith.xori %isclose, %true : i1
        scf.condition(%go) %q1, %gs, %gn : i64, i64, i64
      } do {
      ^bb0(%q1: i64, %gs: i64, %gn: i64):
        %t_entry = arith.constant 7 : i64
        %ise = func.call @narr_is(%nar, %gs, %gn, %t_entry) : (!llvm.ptr, i64, i64, i64) -> i1
        %note = arith.xori %ise, %true : i1
        scf.if %note {
          func.call @nixstore_nr_fail(%pb, %c2, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
        }
        %t_name = arith.constant 8 : i64
        %t_node = arith.constant 9 : i64
        %e1 = func.call @narr_expect(%pb, %nar, %size, %q1, %t_open) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
        %e2 = func.call @narr_expect(%pb, %nar, %size, %e1, %t_name) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
        %ns, %nn, %e3 = func.call @narr_str(%pb, %nar, %size, %e2) : (!llvm.ptr, !llvm.ptr, i64, i64) -> (i64, i64, i64)
        %np = func.call @narw_skip(%nar, %ns) : (!llvm.ptr, i64) -> !llvm.ptr
        %name_d = func.call @nar_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
        %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
        %name = builtin.unrealized_conversion_cast %name_m : !m to !b
        // the name is empty, ".", "..", or holds a '/'
        %dg = memref.get_global @narr_dots : memref<2xi8>
        %dots = trikeshed.text %dg : memref<2xi8> -> !b
        %i0 = arith.constant 0 : index
        %i1 = arith.constant 1 : index
        %i2 = arith.constant 2 : index
        %dot = trikeshed.slice %dots[%i0, %i1] : !b -> !b
        %dotdot = trikeshed.slice %dots[%i0, %i2] : !b -> !b
        %cd = trikeshed.compare %name, %dot unsigned : !b, !b
        %cdd = trikeshed.compare %name, %dotdot unsigned : !b, !b
        %f = arith.constant false
        %slashes = trikeshed.fold %name, %f : !b, i1 -> i1 {
        ^bb0(%acc: i1, %x: i8):
          %c47 = arith.constant 47 : i8
          %is = arith.cmpi eq, %x, %c47 : i8
          %o = arith.ori %acc, %is : i1
          trikeshed.yield %o : i1
        }
        %z32 = arith.constant 0 : i32
        %empty = arith.cmpi eq, %nn, %c0 : i64
        %isdot = arith.cmpi eq, %cd, %z32 : i32
        %isdd = arith.cmpi eq, %cdd, %z32 : i32
        %b1 = arith.ori %empty, %isdot : i1
        %b2 = arith.ori %b1, %isdd : i1
        %bad = arith.ori %b2, %slashes : i1
        scf.if %bad {
          %c3 = arith.constant 3 : i64
          func.call @nixstore_nr_fail(%pb, %c3, %np, %nn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> ()
        }
        %e4 = func.call @narr_expect(%pb, %nar, %size, %e3, %t_node) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
        func.call @narw_put(%pb, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
        %cl0 = arith.addi %len, %c1 : i64
        %clen = arith.addi %cl0, %nn : i64
        %e5 = func.call @narr_node(%pb, %nar, %size, %e4, %clen) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
        %e6 = func.call @narr_expect(%pb, %nar, %size, %e5, %t_close) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
        scf.yield %e6 : i64
      }
      scf.yield %d#0 : i64
    }
    scf.yield %r2 : i64
  }
  return %r : i64
}

func.func @nixstore_ts_narrestore(%pb: !llvm.ptr, %nar: !llvm.ptr, %size: i64, %root: !llvm.ptr, %rn: i64) {
  %c0 = arith.constant 0 : i64
  func.call @narw_put(%pb, %c0, %c0, %root, %rn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
  %t_magic = arith.constant 13 : i64
  %p = func.call @narr_expect(%pb, %nar, %size, %c0, %t_magic) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
  %q = func.call @narr_node(%pb, %nar, %size, %p, %rn) : (!llvm.ptr, !llvm.ptr, i64, i64, i64) -> i64
  return
}
