// The NAR framing byte emission of lib/Store/StorePaths.cpp's NarWriter hollowed into the TrikeShed dialect: the
// 8-byte little-endian length prefix (u64), the zero padding to a multiple of 8 (pad), the length-prefix + bytes + pad
// composition (str), and the constant NAR tokens ("(", "type", "regular", ...).  StorePaths.cpp keeps the filesystem
// walk (lstat/open/read recursion, the PathFilter, the sink I/O, the throw wording); its u64/pad/str bodies are gone,
// replaced by bridges that reserve a stack buffer, call these neutral C-ABI entries and flush the bytes to the Sink.
// The framing algebra is here, in trikeshed.series / slice / text / at / combine / drain over byte series, lowered by
// --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
//
// Each entry drains into the caller's buffer and returns how many bytes it wrote.  Nothing throws: the framing is pure.
// The NAR byte stream must stay byte-identical (it is hashed for store paths): u64 is little-endian, pad is 8 - n%8
// zero bytes when n%8 != 0 and nothing otherwise, str is u64(n) then the n bytes then the pad.
!b = !trikeshed.series<i8>
!i32s = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @nar_zeros : memref<8xi8> = dense<0>
// the constant NAR tokens, one blob; nar_toff/nar_tlen give each id's slice (id 4 is the empty string)
memref.global "private" constant @nar_tokens : memref<79xi8> =
  dense<"0x2874797065726567756c617265786563757461626c65636f6e74656e74736469726563746f7279656e7472796e616d656e6f646573796d6c696e6b746172676574296e69782d617263686976652d31">
memref.global "private" constant @nar_toff : memref<14xi32> = dense<[0, 1, 5, 12, 22, 22, 30, 39, 44, 48, 52, 59, 65, 66]>
memref.global "private" constant @nar_tlen : memref<14xi32> = dense<[1, 4, 7, 10, 0, 8, 9, 5, 4, 4, 7, 6, 1, 13]>

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

// u64: n as 8 little-endian bytes (byte i is bits [8i, 8i+8) of n), drained into `into` (room for 8).
func.func @mlnix_nar_u64(%n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : index
  %bytes = trikeshed.series %c8 : !b {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c8i = arith.constant 8 : i64
    %sh = arith.muli %i64, %c8i : i64
    %v = arith.shrui %n, %sh : i64
    %byte = arith.trunci %v : i64 to i8
    trikeshed.yield %byte : i8
  }
  %c864 = arith.constant 8 : i64
  %od = func.call @nar_desc(%into, %c864) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %bytes, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// pad: the 8 - n%8 zero bytes when n%8 != 0, nothing otherwise, drained into `into` (room for 8); returns the count.
func.func @mlnix_nar_pad(%n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : i64
  %c0 = arith.constant 0 : i64
  %rem = arith.remui %n, %c8 : i64
  %need = arith.subi %c8, %rem : i64
  %nz = arith.cmpi ne, %rem, %c0 : i64
  %k = arith.select %nz, %need, %c0 : i64
  %ki = arith.index_cast %k : i64 to index
  %c0i = arith.constant 0 : index
  %zg = memref.get_global @nar_zeros : memref<8xi8>
  %zeros = trikeshed.text %zg : memref<8xi8> -> !b
  %part = trikeshed.slice %zeros[%c0i, %ki] : !b -> !b
  %od = func.call @nar_desc(%into, %k) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %part, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// str: the length prefix u64(n), the n bytes at p, then the pad -- one combine of the three lazy parts, one drain into
// `into` (room for 8 + n + pad).  Returns 8 + n + pad.
func.func @mlnix_nar_str(%p: !llvm.ptr, %n: i64, %into: !llvm.ptr) -> i64 {
  %c8 = arith.constant 8 : index
  %len8 = trikeshed.series %c8 : !b {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    %c8i = arith.constant 8 : i64
    %sh = arith.muli %i64, %c8i : i64
    %v = arith.shrui %n, %sh : i64
    %byte = arith.trunci %v : i64 to i8
    trikeshed.yield %byte : i8
  }
  %ds = func.call @nar_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %ms = builtin.unrealized_conversion_cast %ds : !d to !m
  %xs = builtin.unrealized_conversion_cast %ms : !m to !b
  %ni = arith.index_cast %n : i64 to index
  %c0 = arith.constant 0 : index
  %body = trikeshed.slice %xs[%c0, %ni] : !b -> !b
  %c864 = arith.constant 8 : i64
  %c064 = arith.constant 0 : i64
  %rem = arith.remui %n, %c864 : i64
  %need = arith.subi %c864, %rem : i64
  %nz = arith.cmpi ne, %rem, %c064 : i64
  %k = arith.select %nz, %need, %c064 : i64
  %ki = arith.index_cast %k : i64 to index
  %zg = memref.get_global @nar_zeros : memref<8xi8>
  %zeros = trikeshed.text %zg : memref<8xi8> -> !b
  %pad = trikeshed.slice %zeros[%c0, %ki] : !b -> !b
  %head = trikeshed.combine %len8, %body : !b, !b -> !b
  %all = trikeshed.combine %head, %pad : !b, !b -> !b
  %total = arith.addi %ni, %c8 : index
  %totalp = arith.addi %total, %ki : index
  %total64 = arith.index_cast %totalp : index to i64
  %od = func.call @nar_desc(%into, %total64) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %all, %om : !b, !m -> index
  %r = arith.index_cast %end : index to i64
  return %r : i64
}

// tok: the constant token `id` framed as str would frame it.  The token's bytes are a slice of the constant blob; its
// address goes to the str entry beside it, so the framing composition is written once.
func.func @mlnix_nar_tok(%id: i64, %into: !llvm.ptr) -> i64 {
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
  %r = func.call @mlnix_nar_str(%p, %len64, %into) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  return %r : i64
}

//===----------------------------------------------------------------------===//
// The walk: dumpPath / hashPath / the prehash helper (NarWriter::dump)
//===----------------------------------------------------------------------===//
//
// nixstore_ts_nardump(ctx, pb, out, lk, root, rn) writes the NAR of the tree at root: the magic, then each node framed in
// the tokens above.  The walk is here: the node's type decides its framing, a directory's names are put in byte order
// (nixstore_ts_sortwins, StoreGraph.mlir's trikeshed.sorted), each entry's path is `path/name` composed into the path
// buffer pb (one combine of the parent's length, "/", the name and a NUL, drained at the parent's end), the filter is asked
// about it and a kept entry is framed and walked.  StorePaths.cpp keeps, as callbacks on ctx (its NarWriter): the lstat,
// opendir/readdir, the file's bytes, readlink, the PathFilter, the prefetch notes, the Sink and the error wording.  The
// framing of a node goes to out and is flushed to the Sink before each call that may throw, as the tokens went one by one
// before: what a Sink saw before an error (`store --dump` writes it to stdout) is unchanged.  A callback reads the path as
// pb's first len bytes (a NUL after them); nothing here allocates, so an error unwinds through these frames leaking nothing.

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

// token id framed at out + k: the new k
func.func private @narw_tok(%out: !llvm.ptr, %k: i64, %id: i64) -> i64 {
  %at = func.call @narw_skip(%out, %k) : (!llvm.ptr, i64) -> !llvm.ptr
  %w = func.call @mlnix_nar_tok(%id, %at) : (i64, !llvm.ptr) -> i64
  %r = arith.addi %k, %w : i64
  return %r : i64
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

// window i of an array of {ptr, i64} windows, and the i64 at i of an array
func.func private @narw_win(%w: !llvm.ptr, %i: i64) -> (!llvm.ptr, i64) {
  %c16 = arith.constant 16 : i64
  %c8 = arith.constant 8 : i64
  %off = arith.muli %i, %c16 : i64
  %wp = llvm.getelementptr %w[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %wp : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %wp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n = llvm.load %np : !llvm.ptr -> i64
  return %p, %n : !llvm.ptr, i64
}

// The node whose path is pb's first len bytes; depth names the callback's listing buffer for a directory.
func.func private @narw_node(%ctx: !llvm.ptr, %pb: !llvm.ptr, %out: !llvm.ptr, %lk: !llvm.ptr, %len: i64, %depth: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c8 = arith.constant 8 : i64
  %cell = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
  %kind = func.call @nixstore_nw_stat(%ctx, %len, %cell) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %size = llvm.load %cell : !llvm.ptr -> i64
  %t_open = arith.constant 0 : i64
  %t_type = arith.constant 1 : i64
  %t_close = arith.constant 12 : i64
  %k0 = func.call @narw_tok(%out, %c0, %t_open) : (!llvm.ptr, i64, i64) -> i64
  %isreg = arith.cmpi ule, %kind, %c1 : i64
  scf.if %isreg {
    // regular: type regular [executable ""] contents u64(size), the bytes, the pad
    %k1 = func.call @narw_tok(%out, %k0, %t_type) : (!llvm.ptr, i64, i64) -> i64
    %t_reg = arith.constant 2 : i64
    %k2 = func.call @narw_tok(%out, %k1, %t_reg) : (!llvm.ptr, i64, i64) -> i64
    %exec = arith.cmpi eq, %kind, %c1 : i64
    %k4 = scf.if %exec -> (i64) {
      %t_exec = arith.constant 3 : i64
      %t_empty = arith.constant 4 : i64
      %ka = func.call @narw_tok(%out, %k2, %t_exec) : (!llvm.ptr, i64, i64) -> i64
      %kb = func.call @narw_tok(%out, %ka, %t_empty) : (!llvm.ptr, i64, i64) -> i64
      scf.yield %kb : i64
    } else {
      scf.yield %k2 : i64
    }
    %t_contents = arith.constant 5 : i64
    %k5 = func.call @narw_tok(%out, %k4, %t_contents) : (!llvm.ptr, i64, i64) -> i64
    %at = func.call @narw_skip(%out, %k5) : (!llvm.ptr, i64) -> !llvm.ptr
    %w = func.call @mlnix_nar_u64(%size, %at) : (i64, !llvm.ptr) -> i64
    %k6 = arith.addi %k5, %w : i64
    func.call @nixstore_nw_sink(%ctx, %k6) : (!llvm.ptr, i64) -> ()
    func.call @nixstore_nw_file(%ctx, %len, %size) : (!llvm.ptr, i64, i64) -> ()
    %pw = func.call @mlnix_nar_pad(%size, %out) : (i64, !llvm.ptr) -> i64
    %k7 = func.call @narw_tok(%out, %pw, %t_close) : (!llvm.ptr, i64, i64) -> i64
    func.call @nixstore_nw_sink(%ctx, %k7) : (!llvm.ptr, i64) -> ()
  } else {
    %isdir = arith.cmpi eq, %kind, %c2 : i64
    scf.if %isdir {
      // directory: type directory, then each kept entry in byte order: entry ( name str(name) node <node> )
      %k1 = func.call @narw_tok(%out, %k0, %t_type) : (!llvm.ptr, i64, i64) -> i64
      %t_dir = arith.constant 6 : i64
      %k2 = func.call @narw_tok(%out, %k1, %t_dir) : (!llvm.ptr, i64, i64) -> i64
      func.call @nixstore_nw_sink(%ctx, %k2) : (!llvm.ptr, i64) -> ()
      %n = func.call @nixstore_nw_dir(%ctx, %depth, %len, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr) -> i64
      %wins = llvm.load %cell : !llvm.ptr -> !llvm.ptr
      %op = llvm.getelementptr %cell[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %order = llvm.load %op : !llvm.ptr -> !llvm.ptr
      func.call @nixstore_ts_sortwins(%wins, %n, %order) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %ni = arith.index_cast %n : i64 to index
      %z = arith.constant 0 : index
      %s1 = arith.constant 1 : index
      %next = arith.addi %depth, %c1 : i64
      scf.for %j = %z to %ni step %s1 {
        %j64 = arith.index_cast %j : index to i64
        %ix = arith.muli %j64, %c8 : i64
        %ixp = llvm.getelementptr %order[%ix] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %e = llvm.load %ixp : !llvm.ptr -> i64
        %np, %nn = func.call @narw_win(%wins, %e) : (!llvm.ptr, i64) -> (!llvm.ptr, i64)
        func.call @narw_put(%pb, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
        %cl0 = arith.addi %len, %c1 : i64
        %clen = arith.addi %cl0, %nn : i64
        %keep = func.call @nixstore_nw_keep(%ctx, %clen) : (!llvm.ptr, i64) -> i64
        %kept = arith.cmpi ne, %keep, %c0 : i64
        scf.if %kept {
          %t_entry = arith.constant 7 : i64
          %t_name = arith.constant 8 : i64
          %t_node = arith.constant 9 : i64
          %e1 = func.call @narw_tok(%out, %c0, %t_entry) : (!llvm.ptr, i64, i64) -> i64
          %e2 = func.call @narw_tok(%out, %e1, %t_open) : (!llvm.ptr, i64, i64) -> i64
          %e3 = func.call @narw_tok(%out, %e2, %t_name) : (!llvm.ptr, i64, i64) -> i64
          %at = func.call @narw_skip(%out, %e3) : (!llvm.ptr, i64) -> !llvm.ptr
          %w = func.call @mlnix_nar_str(%np, %nn, %at) : (!llvm.ptr, i64, !llvm.ptr) -> i64
          %e4 = arith.addi %e3, %w : i64
          %e5 = func.call @narw_tok(%out, %e4, %t_node) : (!llvm.ptr, i64, i64) -> i64
          func.call @nixstore_nw_sink(%ctx, %e5) : (!llvm.ptr, i64) -> ()
          func.call @narw_node(%ctx, %pb, %out, %lk, %clen, %next) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, i64) -> ()
          %e6 = func.call @narw_tok(%out, %c0, %t_close) : (!llvm.ptr, i64, i64) -> i64
          func.call @nixstore_nw_sink(%ctx, %e6) : (!llvm.ptr, i64) -> ()
        }
      }
      %k3 = func.call @narw_tok(%out, %c0, %t_close) : (!llvm.ptr, i64, i64) -> i64
      func.call @nixstore_nw_sink(%ctx, %k3) : (!llvm.ptr, i64) -> ()
    } else {
      %islnk = arith.cmpi eq, %kind, %c3 : i64
      scf.if %islnk {
        // symlink: type symlink target str(target)
        %k1 = func.call @narw_tok(%out, %k0, %t_type) : (!llvm.ptr, i64, i64) -> i64
        %t_sym = arith.constant 10 : i64
        %t_target = arith.constant 11 : i64
        %k2 = func.call @narw_tok(%out, %k1, %t_sym) : (!llvm.ptr, i64, i64) -> i64
        %k3 = func.call @narw_tok(%out, %k2, %t_target) : (!llvm.ptr, i64, i64) -> i64
        func.call @nixstore_nw_sink(%ctx, %k3) : (!llvm.ptr, i64) -> ()
        %tn = func.call @nixstore_nw_link(%ctx, %len) : (!llvm.ptr, i64) -> i64
        %w = func.call @mlnix_nar_str(%lk, %tn, %out) : (!llvm.ptr, i64, !llvm.ptr) -> i64
        %k4 = func.call @narw_tok(%out, %w, %t_close) : (!llvm.ptr, i64, i64) -> i64
        func.call @nixstore_nw_sink(%ctx, %k4) : (!llvm.ptr, i64) -> ()
      } else {
        // any other type: "(" was written, then the error
        func.call @nixstore_nw_sink(%ctx, %k0) : (!llvm.ptr, i64) -> ()
        func.call @nixstore_nw_odd(%ctx, %len) : (!llvm.ptr, i64) -> ()
      }
    }
  }
  return
}

func.func @nixstore_ts_nardump(%ctx: !llvm.ptr, %pb: !llvm.ptr, %out: !llvm.ptr, %lk: !llvm.ptr, %root: !llvm.ptr, %rn: i64) {
  %c0 = arith.constant 0 : i64
  func.call @narw_put(%pb, %c0, %c0, %root, %rn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> ()
  %t_magic = arith.constant 13 : i64
  %k = func.call @narw_tok(%out, %c0, %t_magic) : (!llvm.ptr, i64, i64) -> i64
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
