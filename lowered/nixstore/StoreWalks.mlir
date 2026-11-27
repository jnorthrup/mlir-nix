// The walks of the store's build and add path (lib/Store/LocalStore.cpp's bodies are gone; what calls them names
// the entries): trees read and made through the C library.
//
//   nixsb_canon   canonicalisePathMetaData: a tree made a store object's.  Each entry read-only (r-x where its owner
//                 could run it, and a directory), its times 1; a link keeps its bits and gets the time.  A directory's
//                 entries first, then itself.
//   nixsb_copy    copyRecursive: a tree copied (addToStore).  A regular file's bytes go through the store's readFile
//                 and writeFile (rwxr-xr-x where its owner could run it, else rw-r--r--); a directory is made, then its
//                 entries, each asked of the store's filter first; a link is made again.
//   nixsb_refs    scanForReferences: the candidates whose hash part occurs in a tree's files or its links' targets.
//                 The candidates' hash parts are sorted once and each file's 32-digit windows bisected into them
//                 (BuilderOps.mlir's refindex and refscan); here are the hash parts, the walk, and the candidates found,
//                 in their order (a where over the marks).
//   nixsb_roots   collectGarbage's roots: the store paths the links under the roots' directory lead to, a link to a
//                 link followed once; a link that leads nowhere is removed.
//
// A walk holds a handle of 16 words on its entry's stack: 0 the store's context (what its callbacks take); 1 to 6 three
// rooms (a pointer and its bytes each: 0 the path walked, 1 the path written or the hash parts, 2 the names); 7 the
// names' top; 8 to 12 the walk's own.  A path is a room's first bytes with a NUL after them, an entry's path its
// directory's with "/" and the name drained at its end (one combine); the room grows by doubling and the bytes stay.
// A directory's names are read whole, in the order the system gives them, before the first entry is walked (the
// directory is closed by then), and lie on the names' room as a stack: a length word, the bytes, a NUL, zeros to a word.
// An error is said once (nixsb_say, StoreWords.mlir), the walk returns 1 through every level, and the entry frees the
// rooms: nothing is left allocated.  The store's callbacks do not throw (LocalStore.cpp keeps what they caught).
// The system's words are StoreBuildDarwin.mlir.in / StoreBuildLinux.mlir.in (lstat's answer, errno, the times, PATH_MAX,
// the allocator) and the store index's (a directory entry's name, opendir and readdir under the system's names).
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// "/", a NUL, "..", "/gcroots"
memref.global "private" constant @sbw_bytes : memref<12xi8> = dense<[47, 0, 46, 46, 47, 103, 99, 114, 111, 111, 116, 115]>
memref.global "private" constant @sbw_zero : memref<16xi64> = dense<0>

// the C library: what is the same wherever mlnix is built
func.func private @strlen(!llvm.ptr) -> i64
func.func private @closedir(!llvm.ptr) -> i32
func.func private @chmod(!llvm.ptr, i32) -> i32
func.func private @mkdir(!llvm.ptr, i32) -> i32
func.func private @readlink(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @symlink(!llvm.ptr, !llvm.ptr) -> i32
func.func private @unlink(!llvm.ptr) -> i32
func.func private @abort()
// the system's words: the store index's (StoreIndexDarwin.mlir.in, StoreIndexLinux.mlir) and this path's
func.func private @nixsi_os_name() -> i64
func.func private @nixsi_os_opendir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsi_os_readdir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsb_os_lstat(!llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_os_errno() -> i64
func.func private @nixsb_os_mtime1(!llvm.ptr) -> i64
func.func private @nixsb_os_pathmax() -> i64
func.func private @nixsb_os_grow(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_os_free(!llvm.ptr)
// the store's words (StoreWords.mlir): 0 getting attributes, 1 getting status, 2 creating directory, 3 opening
// directory, 4 reading symlink, 5 creating symlink, 6 an unsupported type
func.func private @nixsb_say(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
// the store's (lib/Store/LocalStore.cpp), none of which throws: a file copied by readFile and writeFile (1 when that
// failed); the filter asked of a path (1 kept, 0 not, -1 it failed); a file read (its bytes, their count at the last
// argument, -1 when that failed); a path put into a set; whether a path is there (pathExists)
func.func private @nixsb_copyfile(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
func.func private @nixsb_keep(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_read(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_ref(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixsb_exists(!llvm.ptr, i64) -> i64
// a store path's hash part (StoreName.mlir), the references' table and scan (BuilderOps.mlir), isInStore (IsInStore.mlir)
func.func private @nixstore_ts_storehash(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_refindex(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_refscan(!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @mlnix_isInStore(!llvm.ptr, i64, !llvm.ptr, i64) -> i1

//===----------------------------------------------------------------------===//
// The handle, its rooms, a path, a directory's names
//===----------------------------------------------------------------------===//

// the descriptor of n cells at p
func.func private @sbw_d(%p: !llvm.ptr, %n: i64) -> !d {
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

// word i of the handle, read and written
func.func private @sbw_g(%h: !llvm.ptr, %i: i64) -> i64 {
  %c16 = arith.constant 16 : i64
  %hd = func.call @sbw_d(%h, %c16) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
  %hs = builtin.unrealized_conversion_cast %hm : !m64 to !s64
  %ii = arith.index_cast %i : i64 to index
  %v = trikeshed.at %hs[%ii] : !s64, index -> i64
  return %v : i64
}
func.func private @sbw_s(%h: !llvm.ptr, %i: i64, %v: i64) {
  %c16 = arith.constant 16 : i64
  %hd = func.call @sbw_d(%h, %c16) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
  %ii = arith.index_cast %i : i64 to index
  memref.store %v, %hm[%ii] : !m64
  return
}
// word i of the handle as an address
func.func private @sbw_p(%h: !llvm.ptr, %i: i64) -> !llvm.ptr {
  %v = func.call @sbw_g(%h, %i) : (!llvm.ptr, i64) -> i64
  %p = llvm.inttoptr %v : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// a handle begun (its words zero, then the context) and ended (its rooms given back)
func.func private @sbw_open(%h: !llvm.ptr, %ctx: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %zg = memref.get_global @sbw_zero : memref<16xi64>
  %zeros = trikeshed.text %zg : memref<16xi64> -> !s64
  %hd = func.call @sbw_d(%h, %c16) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
  %e = trikeshed.drain %zeros, %hm : !s64, !m64 -> index
  %cb = llvm.ptrtoint %ctx : !llvm.ptr to i64
  func.call @sbw_s(%h, %c0, %cb) : (!llvm.ptr, i64, i64) -> ()
  return
}
func.func private @sbw_close(%h: !llvm.ptr) {
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %r0 = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %r1 = func.call @sbw_p(%h, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %r2 = func.call @sbw_p(%h, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  func.call @nixsb_os_free(%r0) : (!llvm.ptr) -> ()
  func.call @nixsb_os_free(%r1) : (!llvm.ptr) -> ()
  func.call @nixsb_os_free(%r2) : (!llvm.ptr) -> ()
  return
}

// Room k of the handle (0 the path walked, 1 the path written, 2 the names), `need` bytes at least: what it held is
// kept, and it may have moved.
func.func private @sbw_room(%h: !llvm.ptr, %k: i64, %need: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c256 = arith.constant 256 : i64
  %k2 = arith.muli %k, %c2 : i64
  %pi = arith.addi %k2, %c1 : i64
  %ci = arith.addi %k2, %c2 : i64
  %p0 = func.call @sbw_g(%h, %pi) : (!llvm.ptr, i64) -> i64
  %cap = func.call @sbw_g(%h, %ci) : (!llvm.ptr, i64) -> i64
  %enough = arith.cmpi sge, %cap, %need : i64
  %bits = scf.if %enough -> (i64) {
    scf.yield %p0 : i64
  } else {
    %twice = arith.muli %cap, %c2 : i64
    %w0 = arith.maxsi %need, %twice : i64
    %want = arith.maxsi %w0, %c256 : i64
    %old = llvm.inttoptr %p0 : i64 to !llvm.ptr
    %new = func.call @nixsb_os_grow(%old, %want) : (!llvm.ptr, i64) -> !llvm.ptr
    %nb = llvm.ptrtoint %new : !llvm.ptr to i64
    %none = arith.cmpi eq, %nb, %c0 : i64
    scf.if %none {
      func.call @abort() : () -> ()
    }
    func.call @sbw_s(%h, %pi, %nb) : (!llvm.ptr, i64, i64) -> ()
    func.call @sbw_s(%h, %ci, %want) : (!llvm.ptr, i64, i64) -> ()
    scf.yield %nb : i64
  }
  %p = llvm.inttoptr %bits : i64 to !llvm.ptr
  return %p : !llvm.ptr
}

// Room k's bytes from `from` on := the first `pre` (0 or 1) bytes of "/", the n bytes at p, a NUL: one combine drained
// once.  The path of an entry is its directory's with this at its end.  Returns the room.
func.func private @sbw_put(%h: !llvm.ptr, %k: i64, %from: i64, %pre: i64, %p: !llvm.ptr, %n: i64) -> !llvm.ptr {
  %c1 = arith.constant 1 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %w0 = arith.addi %pre, %n : i64
  %w = arith.addi %w0, %c1 : i64
  %need = arith.addi %from, %w : i64
  %base = func.call @sbw_room(%h, %k, %need) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %bg = memref.get_global @sbw_bytes : memref<12xi8>
  %bytes = trikeshed.text %bg : memref<12xi8> -> !s
  %prei = arith.index_cast %pre : i64 to index
  %lead = trikeshed.slice %bytes[%z, %prei] : !s -> !s
  %nul = trikeshed.slice %bytes[%i1, %i1] : !s -> !s
  %name_d = func.call @sbw_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
  %name = builtin.unrealized_conversion_cast %name_m : !m to !s
  %all = trikeshed.combine %lead, %name, %nul : !s, !s, !s -> !s
  %at = llvm.getelementptr %base[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %od = func.call @sbw_d(%at, %w) : (!llvm.ptr, i64) -> !d
  %om = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %all, %om : !s, !m -> index
  return %base : !llvm.ptr
}

// room k's path cut back to its first len bytes: the NUL after them again
func.func private @sbw_cut(%h: !llvm.ptr, %k: i64, %len: i64) {
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %nul = arith.constant 0 : i8
  %k2 = arith.muli %k, %c2 : i64
  %pi = arith.addi %k2, %c1 : i64
  %base = func.call @sbw_p(%h, %pi) : (!llvm.ptr, i64) -> !llvm.ptr
  %at = llvm.getelementptr %base[%len] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  llvm.store %nul, %at : i8, !llvm.ptr
  return
}

// The entries of the directory at `path` but "." and "..", pushed on the names in the order the system gives them: a
// fill, read back by sbw_name from where the top was.  0, or -1 when the directory cannot be opened (errno says why).
func.func private @sbw_list(%h: !llvm.ptr, %path: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %cm8 = arith.constant -8 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %dir = func.call @nixsi_os_opendir(%path) : (!llvm.ptr) -> !llvm.ptr
  %db = llvm.ptrtoint %dir : !llvm.ptr to i64
  %open = arith.cmpi ne, %db, %c0 : i64
  %r = scf.if %open -> (i64) {
    %noff = func.call @nixsi_os_name() : () -> i64
    %bg = memref.get_global @sbw_bytes : memref<12xi8>
    %bytes = trikeshed.text %bg : memref<12xi8> -> !s
    %nul = trikeshed.slice %bytes[%i1, %i1] : !s -> !s
    %dot = trikeshed.slice %bytes[%i2, %i1] : !s -> !s
    %dotdot = trikeshed.slice %bytes[%i2, %i2] : !s -> !s
    %e0 = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
    %e0b = llvm.ptrtoint %e0 : !llvm.ptr to i64
    %ee = scf.while (%e = %e0b) : (i64) -> (i64) {
      %more = arith.cmpi ne, %e, %c0 : i64
      scf.condition(%more) %e : i64
    } do {
    ^bb0(%ea: i64):
      %ep = llvm.inttoptr %ea : i64 to !llvm.ptr
      %np = llvm.getelementptr %ep[%noff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %nn = func.call @strlen(%np) : (!llvm.ptr) -> i64
      %nd = func.call @sbw_d(%np, %nn) : (!llvm.ptr, i64) -> !d
      %nm = builtin.unrealized_conversion_cast %nd : !d to !m
      %name = builtin.unrealized_conversion_cast %nm : !m to !s
      %cd = trikeshed.compare %name, %dot unsigned : !s, !s
      %cdd = trikeshed.compare %name, %dotdot unsigned : !s, !s
      %self = arith.cmpi eq, %cd, %z32 : i32
      %up = arith.cmpi eq, %cdd, %z32 : i32
      %skip = arith.ori %self, %up : i1
      scf.if %skip {
      } else {
        %top = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
        %need0 = arith.addi %top, %nn : i64
        %need = arith.addi %need0, %c16 : i64
        %base = func.call @sbw_room(%h, %c2, %need) : (!llvm.ptr, i64, i64) -> !llvm.ptr
        %lp = llvm.getelementptr %base[%top] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %ld = func.call @sbw_d(%lp, %c1) : (!llvm.ptr, i64) -> !d
        %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
        memref.store %nn, %lm[%z] : !m64
        %bo = arith.addi %top, %c8 : i64
        %bp = llvm.getelementptr %base[%bo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %nn1 = arith.addi %nn, %c1 : i64
        %bd = func.call @sbw_d(%bp, %nn1) : (!llvm.ptr, i64) -> !d
        %bm = builtin.unrealized_conversion_cast %bd : !d to !m
        %both = trikeshed.combine %name, %nul : !s, !s -> !s
        %end = trikeshed.drain %both, %bm : !s, !m -> index
        %a0 = arith.addi %nn, %c8 : i64
        %adv = arith.andi %a0, %cm8 : i64
        %top2 = arith.addi %bo, %adv : i64
        func.call @sbw_s(%h, %c7, %top2) : (!llvm.ptr, i64, i64) -> ()
      }
      %en = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
      %enb = llvm.ptrtoint %en : !llvm.ptr to i64
      scf.yield %enb : i64
    }
    %rc = func.call @closedir(%dir) : (!llvm.ptr) -> i32
    scf.yield %c0 : i64
  } else {
    scf.yield %m1 : i64
  }
  return %r : i64
}

// the name at the names' byte off: its bytes, its length, and where the next one lies
func.func private @sbw_name(%h: !llvm.ptr, %off: i64) -> (!llvm.ptr, i64, i64) {
  %c1 = arith.constant 1 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %cm8 = arith.constant -8 : i64
  %z = arith.constant 0 : index
  %base = func.call @sbw_p(%h, %c5) : (!llvm.ptr, i64) -> !llvm.ptr
  %lp = llvm.getelementptr %base[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ld = func.call @sbw_d(%lp, %c1) : (!llvm.ptr, i64) -> !d
  %lm = builtin.unrealized_conversion_cast %ld : !d to !m64
  %ls = builtin.unrealized_conversion_cast %lm : !m64 to !s64
  %n = trikeshed.at %ls[%z] : !s64, index -> i64
  %bo = arith.addi %off, %c8 : i64
  %np = llvm.getelementptr %base[%bo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %a0 = arith.addi %n, %c8 : i64
  %adv = arith.andi %a0, %cm8 : i64
  %next = arith.addi %bo, %adv : i64
  return %np, %n, %next : !llvm.ptr, i64, i64
}

//===----------------------------------------------------------------------===//
// canonicalisePathMetaData
//===----------------------------------------------------------------------===//

// The tree whose path is room 0's first len bytes.  0, or 1 with the error said: an entry lstat refuses.
func.func private @sbw_canon(%h: !llvm.ptr, %len: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c16 = arith.constant 16 : i64
  %c64 = arith.constant 64 : i64
  %m1 = arith.constant -1 : i64
  %rx = arith.constant 365 : i32
  %ro = arith.constant 292 : i32
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %path0 = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %mode = func.call @nixsb_os_lstat(%path0, %cell) : (!llvm.ptr, !llvm.ptr) -> i64
  %bad = arith.cmpi slt, %mode, %c0 : i64
  %st = scf.if %bad -> (i64) {
    %ctx = func.call @sbw_p(%h, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
    %said = func.call @nixsb_say(%ctx, %c0, %c0, %path0, %len, %path0, %c0, %path0, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %said : i64
  } else {
    %kind = arith.shrui %mode, %c16 : i64
    %isdir = arith.cmpi eq, %kind, %c2 : i64
    %s1 = scf.if %isdir -> (i64) {
      %mark = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
      %l = func.call @sbw_list(%h, %path0) : (!llvm.ptr, !llvm.ptr) -> i64
      %listed = arith.cmpi eq, %l, %c0 : i64
      %s2 = scf.if %listed -> (i64) {
        %end = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
        %oe, %se = scf.while (%off = %mark, %s = %c0) : (i64, i64) -> (i64, i64) {
          %in = arith.cmpi slt, %off, %end : i64
          %fine = arith.cmpi eq, %s, %c0 : i64
          %go = arith.andi %in, %fine : i1
          scf.condition(%go) %off, %s : i64, i64
        } do {
        ^bb0(%oa: i64, %sa: i64):
          %np, %nn, %next = func.call @sbw_name(%h, %oa) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
          %pb = func.call @sbw_put(%h, %c0, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
          %l1 = arith.addi %len, %c1 : i64
          %clen = arith.addi %l1, %nn : i64
          %sn = func.call @sbw_canon(%h, %clen) : (!llvm.ptr, i64) -> i64
          scf.yield %next, %sn : i64, i64
        }
        func.call @sbw_s(%h, %c7, %mark) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbw_cut(%h, %c0, %len) : (!llvm.ptr, i64, i64) -> ()
        scf.yield %se : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %s2 : i64
    } else {
      scf.yield %c0 : i64
    }
    %ok = arith.cmpi eq, %s1, %c0 : i64
    scf.if %ok {
      %path1 = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
      %islnk = arith.cmpi eq, %kind, %c3 : i64
      scf.if %islnk {
      } else {
        %x = arith.andi %mode, %c64 : i64
        %runs = arith.cmpi ne, %x, %c0 : i64
        %wide = arith.ori %runs, %isdir : i1
        %bits = arith.select %wide, %rx, %ro : i32
        %rc = func.call @chmod(%path1, %bits) : (!llvm.ptr, i32) -> i32
      }
      %tc = func.call @nixsb_os_mtime1(%path1) : (!llvm.ptr) -> i64
    }
    scf.yield %s1 : i64
  }
  return %st : i64
}

func.func @nixsb_canon(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  func.call @sbw_open(%h, %ctx) : (!llvm.ptr, !llvm.ptr) -> ()
  %pb = func.call @sbw_put(%h, %c0, %c0, %c0, %p, %n) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
  %st = func.call @sbw_canon(%h, %n) : (!llvm.ptr, i64) -> i64
  func.call @sbw_close(%h) : (!llvm.ptr) -> ()
  return %st : i64
}

//===----------------------------------------------------------------------===//
// copyRecursive
//===----------------------------------------------------------------------===//

// A link made again: the one at room 0's path read (PATH_MAX bytes of it at most) and made at room 1's path.
func.func private @sbw_copy_link(%h: !llvm.ptr, %flen: i64, %tlen: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %nul = arith.constant 0 : i8
  %pm = func.call @nixsb_os_pathmax() : () -> i64
  %pm1 = arith.addi %pm, %c1 : i64
  %buf = llvm.alloca %pm1 x i8 : (i64) -> !llvm.ptr
  %ctx = func.call @sbw_p(%h, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %from = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %to = func.call @sbw_p(%h, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %k = func.call @readlink(%from, %buf, %pm) : (!llvm.ptr, !llvm.ptr, i64) -> i64
  %unread = arith.cmpi slt, %k, %c0 : i64
  %st = scf.if %unread -> (i64) {
    %said = func.call @nixsb_say(%ctx, %c0, %c4, %from, %flen, %from, %c0, %from, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %said : i64
  } else {
    %end = llvm.getelementptr %buf[%k] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %nul, %end : i8, !llvm.ptr
    %rc = func.call @symlink(%buf, %to) : (!llvm.ptr, !llvm.ptr) -> i32
    %unmade = arith.cmpi ne, %rc, %z32 : i32
    %s1 = scf.if %unmade -> (i64) {
      %e = func.call @nixsb_os_errno() : () -> i64
      %said2 = func.call @nixsb_say(%ctx, %c0, %c5, %to, %tlen, %to, %c0, %to, %c0, %e, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %said2 : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %s1 : i64
  }
  return %st : i64
}

// The tree at room 0's first flen bytes copied to room 1's first tlen bytes.  0, or 1 with the error said (or kept by
// the store's callback).
func.func private @sbw_copy(%h: !llvm.ptr, %flen: i64, %tlen: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c64 = arith.constant 64 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %rwx = arith.constant 493 : i64
  %rw = arith.constant 420 : i64
  %dmode = arith.constant 493 : i32
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %ctx = func.call @sbw_p(%h, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
  %from = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %to = func.call @sbw_p(%h, %c3) : (!llvm.ptr, i64) -> !llvm.ptr
  %mode = func.call @nixsb_os_lstat(%from, %cell) : (!llvm.ptr, !llvm.ptr) -> i64
  %bad = arith.cmpi slt, %mode, %c0 : i64
  %st = scf.if %bad -> (i64) {
    %e = func.call @nixsb_os_errno() : () -> i64
    %said = func.call @nixsb_say(%ctx, %c0, %c1, %from, %flen, %from, %c0, %from, %c0, %e, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %said : i64
  } else {
    %kind = arith.shrui %mode, %c16 : i64
    %isreg = arith.cmpi eq, %kind, %c1 : i64
    %s1 = scf.if %isreg -> (i64) {
      %x = arith.andi %mode, %c64 : i64
      %runs = arith.cmpi ne, %x, %c0 : i64
      %bits = arith.select %runs, %rwx, %rw : i64
      %cs = func.call @nixsb_copyfile(%ctx, %from, %flen, %to, %tlen, %bits) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
      scf.yield %cs : i64
    } else {
      %isdir = arith.cmpi eq, %kind, %c2 : i64
      %s2 = scf.if %isdir -> (i64) {
        %rc = func.call @mkdir(%to, %dmode) : (!llvm.ptr, i32) -> i32
        %unmade = arith.cmpi ne, %rc, %z32 : i32
        %s3 = scf.if %unmade -> (i64) {
          %e2 = func.call @nixsb_os_errno() : () -> i64
          %said2 = func.call @nixsb_say(%ctx, %c0, %c2, %to, %tlen, %to, %c0, %to, %c0, %e2, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
          scf.yield %said2 : i64
        } else {
          %mark = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
          %l = func.call @sbw_list(%h, %from) : (!llvm.ptr, !llvm.ptr) -> i64
          %closed = arith.cmpi ne, %l, %c0 : i64
          %s4 = scf.if %closed -> (i64) {
            %said3 = func.call @nixsb_say(%ctx, %c0, %c3, %from, %flen, %from, %c0, %from, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
            scf.yield %said3 : i64
          } else {
            %filtered = func.call @sbw_g(%h, %c8) : (!llvm.ptr, i64) -> i64
            %asks = arith.cmpi ne, %filtered, %c0 : i64
            %end = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
            %oe, %se = scf.while (%off = %mark, %s = %c0) : (i64, i64) -> (i64, i64) {
              %in = arith.cmpi slt, %off, %end : i64
              %fine = arith.cmpi eq, %s, %c0 : i64
              %go = arith.andi %in, %fine : i1
              scf.condition(%go) %off, %s : i64, i64
            } do {
            ^bb0(%oa: i64, %sa: i64):
              %np, %nn, %next = func.call @sbw_name(%h, %oa) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
              %fb = func.call @sbw_put(%h, %c0, %flen, %c1, %np, %nn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
              %f1 = arith.addi %flen, %c1 : i64
              %cf = arith.addi %f1, %nn : i64
              %keep = scf.if %asks -> (i64) {
                %kk = func.call @nixsb_keep(%ctx, %fb, %cf) : (!llvm.ptr, !llvm.ptr, i64) -> i64
                scf.yield %kk : i64
              } else {
                scf.yield %c1 : i64
              }
              %kept = arith.cmpi eq, %keep, %c1 : i64
              %sn = scf.if %kept -> (i64) {
                %tb = func.call @sbw_put(%h, %c1, %tlen, %c1, %np, %nn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
                %t1 = arith.addi %tlen, %c1 : i64
                %ct = arith.addi %t1, %nn : i64
                %sc = func.call @sbw_copy(%h, %cf, %ct) : (!llvm.ptr, i64, i64) -> i64
                scf.yield %sc : i64
              } else {
                %failed = arith.cmpi slt, %keep, %c0 : i64
                %sf = arith.extui %failed : i1 to i64
                scf.yield %sf : i64
              }
              scf.yield %next, %sn : i64, i64
            }
            func.call @sbw_s(%h, %c7, %mark) : (!llvm.ptr, i64, i64) -> ()
            func.call @sbw_cut(%h, %c0, %flen) : (!llvm.ptr, i64, i64) -> ()
            func.call @sbw_cut(%h, %c1, %tlen) : (!llvm.ptr, i64, i64) -> ()
            scf.yield %se : i64
          }
          scf.yield %s4 : i64
        }
        scf.yield %s3 : i64
      } else {
        %islnk = arith.cmpi eq, %kind, %c3 : i64
        %s5 = scf.if %islnk -> (i64) {
          %ls = func.call @sbw_copy_link(%h, %flen, %tlen) : (!llvm.ptr, i64, i64) -> i64
          scf.yield %ls : i64
        } else {
          %said4 = func.call @nixsb_say(%ctx, %c0, %c6, %from, %flen, %from, %c0, %from, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
          scf.yield %said4 : i64
        }
        scf.yield %s5 : i64
      }
      scf.yield %s2 : i64
    }
    scf.yield %s1 : i64
  }
  return %st : i64
}

// filtered: whether the store's filter is asked about each entry (nixsb_keep)
func.func @nixsb_copy(%ctx: !llvm.ptr, %fp: !llvm.ptr, %fn: i64, %tp: !llvm.ptr, %tn: i64, %filtered: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  func.call @sbw_open(%h, %ctx) : (!llvm.ptr, !llvm.ptr) -> ()
  func.call @sbw_s(%h, %c8, %filtered) : (!llvm.ptr, i64, i64) -> ()
  %fb = func.call @sbw_put(%h, %c0, %c0, %c0, %fp, %fn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
  %tb = func.call @sbw_put(%h, %c1, %c0, %c0, %tp, %tn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
  %st = func.call @sbw_copy(%h, %fn, %tn) : (!llvm.ptr, i64, i64) -> i64
  func.call @sbw_close(%h) : (!llvm.ptr) -> ()
  return %st : i64
}

//===----------------------------------------------------------------------===//
// scanForReferences
//===----------------------------------------------------------------------===//

// a link's target scanned (PATH_MAX bytes of it at most; one that cannot be read has none)
func.func private @sbw_scan_link(%h: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %pm = func.call @nixsb_os_pathmax() : () -> i64
  %pm1 = arith.addi %pm, %c1 : i64
  %buf = llvm.alloca %pm1 x i8 : (i64) -> !llvm.ptr
  %path = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %k = func.call @readlink(%path, %buf, %pm) : (!llvm.ptr, !llvm.ptr, i64) -> i64
  %n = arith.maxsi %k, %c0 : i64
  %w = func.call @sbw_p(%h, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
  %order = func.call @sbw_p(%h, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
  %nu = func.call @sbw_g(%h, %c10) : (!llvm.ptr, i64) -> i64
  %found = func.call @sbw_p(%h, %c11) : (!llvm.ptr, i64) -> !llvm.ptr
  %hits = func.call @nixstore_ts_refscan(%buf, %n, %w, %order, %nu, %found) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
  return
}

// The tree at room 0's first len bytes scanned: a file's bytes (read by the store), a link's target, a directory's
// entries.  What lstat refuses or a directory that cannot be opened has nothing.  0, or 1 when a file could not be read.
func.func private @sbw_scan(%h: !llvm.ptr, %len: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c16 = arith.constant 16 : i64
  %z = arith.constant 0 : index
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %path = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %mode = func.call @nixsb_os_lstat(%path, %cell) : (!llvm.ptr, !llvm.ptr) -> i64
  %bad = arith.cmpi slt, %mode, %c0 : i64
  %st = scf.if %bad -> (i64) {
    scf.yield %c0 : i64
  } else {
    %kind = arith.shrui %mode, %c16 : i64
    %isreg = arith.cmpi eq, %kind, %c1 : i64
    %s1 = scf.if %isreg -> (i64) {
      %ctx = func.call @sbw_p(%h, %c0) : (!llvm.ptr, i64) -> !llvm.ptr
      %data = func.call @nixsb_read(%ctx, %path, %len, %cell) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
      %cd = func.call @sbw_d(%cell, %c1) : (!llvm.ptr, i64) -> !d
      %cm = builtin.unrealized_conversion_cast %cd : !d to !m64
      %cs = builtin.unrealized_conversion_cast %cm : !m64 to !s64
      %n = trikeshed.at %cs[%z] : !s64, index -> i64
      %unread = arith.cmpi slt, %n, %c0 : i64
      %s2 = scf.if %unread -> (i64) {
        scf.yield %c1 : i64
      } else {
        %w = func.call @sbw_p(%h, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
        %order = func.call @sbw_p(%h, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
        %nu = func.call @sbw_g(%h, %c10) : (!llvm.ptr, i64) -> i64
        %found = func.call @sbw_p(%h, %c11) : (!llvm.ptr, i64) -> !llvm.ptr
        %hits = func.call @nixstore_ts_refscan(%data, %n, %w, %order, %nu, %found) : (!llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
        scf.yield %c0 : i64
      }
      scf.yield %s2 : i64
    } else {
      %islnk = arith.cmpi eq, %kind, %c3 : i64
      %isdir = arith.cmpi eq, %kind, %c2 : i64
      scf.if %islnk {
        func.call @sbw_scan_link(%h) : (!llvm.ptr) -> ()
      }
      %s3 = scf.if %isdir -> (i64) {
        %mark = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
        %l = func.call @sbw_list(%h, %path) : (!llvm.ptr, !llvm.ptr) -> i64
        %listed = arith.cmpi eq, %l, %c0 : i64
        %s4 = scf.if %listed -> (i64) {
          %end = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
          %oe, %se = scf.while (%off = %mark, %s = %c0) : (i64, i64) -> (i64, i64) {
            %in = arith.cmpi slt, %off, %end : i64
            %fine = arith.cmpi eq, %s, %c0 : i64
            %go = arith.andi %in, %fine : i1
            scf.condition(%go) %off, %s : i64, i64
          } do {
          ^bb0(%oa: i64, %sa: i64):
            %np, %nn, %next = func.call @sbw_name(%h, %oa) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
            %pb = func.call @sbw_put(%h, %c0, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
            %l1 = arith.addi %len, %c1 : i64
            %clen = arith.addi %l1, %nn : i64
            %sn = func.call @sbw_scan(%h, %clen) : (!llvm.ptr, i64) -> i64
            scf.yield %next, %sn : i64, i64
          }
          func.call @sbw_s(%h, %c7, %mark) : (!llvm.ptr, i64, i64) -> ()
          func.call @sbw_cut(%h, %c0, %len) : (!llvm.ptr, i64, i64) -> ()
          scf.yield %se : i64
        } else {
          scf.yield %c0 : i64
        }
        scf.yield %s4 : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %s3 : i64
    }
    scf.yield %s1 : i64
  }
  return %st : i64
}

// cands: the nc candidates (Text rows, sorted).  Room 1 holds, for the walk: each candidate's hash part (32 bytes of
// room each), the hash parts' windows, the table's order and the marks.  refs gets each candidate found (nixsb_ref), in
// the candidates' order.  0, or 1 when a file could not be read (the store keeps why).
func.func @nixsb_refs(%ctx: !llvm.ptr, %p: !llvm.ptr, %n: i64, %cands: !llvm.ptr, %nc: i64, %refs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c56 = arith.constant 56 : i64
  %c57 = arith.constant 57 : i64
  %c2x = arith.constant 2 : i64
  %low32 = arith.constant 4294967295 : i64
  %b0 = arith.constant 0 : i8
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  func.call @sbw_open(%h, %ctx) : (!llvm.ptr, !llvm.ptr) -> ()
  %bytes0 = arith.muli %nc, %c57 : i64
  %bytes = arith.addi %bytes0, %c8 : i64
  %room = func.call @sbw_room(%h, %c1, %bytes) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %wo = arith.muli %nc, %c32 : i64
  %oo = arith.muli %nc, %c48 : i64
  %fo = arith.muli %nc, %c56 : i64
  %w = llvm.getelementptr %room[%wo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %order = llvm.getelementptr %room[%oo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %found = llvm.getelementptr %room[%fo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // the candidates' rows (a pointer and a length of 32 bits, then the capacity), the windows (a pointer and a length)
  %nc2 = arith.muli %nc, %c2x : i64
  %cd = func.call @sbw_d(%cands, %nc2) : (!llvm.ptr, i64) -> !d
  %cm = builtin.unrealized_conversion_cast %cd : !d to !m64
  %crows = builtin.unrealized_conversion_cast %cm : !m64 to !s64
  %wd = func.call @sbw_d(%w, %nc2) : (!llvm.ptr, i64) -> !d
  %wm = builtin.unrealized_conversion_cast %wd : !d to !m64
  %nci = arith.index_cast %nc : i64 to index
  scf.for %i = %z to %nci step %i1 {
    %i64 = arith.index_cast %i : index to i64
    %r0 = arith.muli %i, %i2 : index
    %r1 = arith.addi %r0, %i1 : index
    %cpb = trikeshed.at %crows[%r0] : !s64, index -> i64
    %cnw = trikeshed.at %crows[%r1] : !s64, index -> i64
    %cn = arith.andi %cnw, %low32 : i64
    %cp = llvm.inttoptr %cpb : i64 to !llvm.ptr
    %ho = arith.muli %i64, %c32 : i64
    %hp = llvm.getelementptr %room[%ho] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %hn = func.call @nixstore_ts_storehash(%cp, %cn, %hp) : (!llvm.ptr, i64, !llvm.ptr) -> i64
    %hb = llvm.ptrtoint %hp : !llvm.ptr to i64
    memref.store %hb, %wm[%r0] : !m64
    memref.store %hn, %wm[%r1] : !m64
  }
  %fd = func.call @sbw_d(%found, %nc) : (!llvm.ptr, i64) -> !d
  %fm = builtin.unrealized_conversion_cast %fd : !d to !m
  %marks = builtin.unrealized_conversion_cast %fm : !m to !s
  %none = trikeshed.series %nci : !s {
  ^bb0(%k: index):
    trikeshed.yield %b0 : i8
  }
  %fe = trikeshed.drain %none, %fm : !s, !m -> index
  %nu = func.call @nixstore_ts_refindex(%w, %nc, %order) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %wb = llvm.ptrtoint %w : !llvm.ptr to i64
  %ob = llvm.ptrtoint %order : !llvm.ptr to i64
  %fb = llvm.ptrtoint %found : !llvm.ptr to i64
  func.call @sbw_s(%h, %c8, %wb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c9, %ob) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c10, %nu) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c11, %fb) : (!llvm.ptr, i64, i64) -> ()
  %pb = func.call @sbw_put(%h, %c0, %c0, %c0, %p, %n) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
  %st = func.call @sbw_scan(%h, %n) : (!llvm.ptr, i64) -> i64
  %ok = arith.cmpi eq, %st, %c0 : i64
  scf.if %ok {
    // the candidates found, in their order: a where over the marks
    %idx = trikeshed.series %nci : !s64 {
    ^bb0(%k: index):
      %k64 = arith.index_cast %k : index to i64
      trikeshed.yield %k64 : i64
    }
    %hit = trikeshed.where %idx : !s64 -> !s64 {
    ^bb0(%j: i64):
      %ji = arith.index_cast %j : i64 to index
      %mk = trikeshed.at %marks[%ji] : !s, index -> i8
      %is = arith.cmpi ne, %mk, %b0 : i8
      trikeshed.yield %is : i1
    }
    %nh = trikeshed.size %hit : !s64
    scf.for %q = %z to %nh step %i1 {
      %j = trikeshed.at %hit[%q] : !s64, index -> i64
      %ji = arith.index_cast %j : i64 to index
      %r0 = arith.muli %ji, %i2 : index
      %r1 = arith.addi %r0, %i1 : index
      %cpb = trikeshed.at %crows[%r0] : !s64, index -> i64
      %cnw = trikeshed.at %crows[%r1] : !s64, index -> i64
      %cn = arith.andi %cnw, %low32 : i64
      %cp = llvm.inttoptr %cpb : i64 to !llvm.ptr
      func.call @nixsb_ref(%refs, %cp, %cn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  func.call @sbw_close(%h) : (!llvm.ptr) -> ()
  return %st : i64
}

//===----------------------------------------------------------------------===//
// collectGarbage's roots
//===----------------------------------------------------------------------===//

// One link under the roots, at room 0's path: its target (a link to a link: that one's), the store's physical root cut
// from its front, is a root when it lies in the store (the store path it lies in: its bytes up to the first "/" past the
// store directory's, the first part of what follows); a link that is not to a link and leads nowhere is removed.
// Handle words: 8 the set of the roots, 9 and 10 the store directory, 11 and 12 the store's physical root.
func.func private @sbw_root_link(%h: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %z32 = arith.constant 0 : i32
  %nul = arith.constant 0 : i8
  %slash = arith.constant 47 : i8
  %z = arith.constant 0 : index
  %pm = func.call @nixsb_os_pathmax() : () -> i64
  %pm1 = arith.addi %pm, %c1 : i64
  %buf1 = llvm.alloca %pm1 x i8 : (i64) -> !llvm.ptr
  %buf2 = llvm.alloca %pm1 x i8 : (i64) -> !llvm.ptr
  %path = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %k1 = func.call @readlink(%path, %buf1, %pm) : (!llvm.ptr, !llvm.ptr, i64) -> i64
  %read = arith.cmpi sgt, %k1, %c0 : i64
  scf.if %read {
    %e1 = llvm.getelementptr %buf1[%k1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    llvm.store %nul, %e1 : i8, !llvm.ptr
    %k2 = func.call @readlink(%buf1, %buf2, %pm) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    %indirect = arith.cmpi sgt, %k2, %c0 : i64
    %tp, %tn = scf.if %indirect -> (!llvm.ptr, i64) {
      %e2 = llvm.getelementptr %buf2[%k2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store %nul, %e2 : i8, !llvm.ptr
      scf.yield %buf2, %k2 : !llvm.ptr, i64
    } else {
      scf.yield %buf1, %k1 : !llvm.ptr, i64
    }
    // the physical root cut from the front
    %rp = func.call @sbw_p(%h, %c11) : (!llvm.ptr, i64) -> !llvm.ptr
    %rn = func.call @sbw_g(%h, %c12) : (!llvm.ptr, i64) -> i64
    %hasroot = arith.cmpi ne, %rn, %c0 : i64
    %long = arith.cmpi sge, %tn, %rn : i64
    %may = arith.andi %hasroot, %long : i1
    %under = scf.if %may -> (i1) {
      %t_d = func.call @sbw_d(%tp, %rn) : (!llvm.ptr, i64) -> !d
      %t_m = builtin.unrealized_conversion_cast %t_d : !d to !m
      %front = builtin.unrealized_conversion_cast %t_m : !m to !s
      %r_d = func.call @sbw_d(%rp, %rn) : (!llvm.ptr, i64) -> !d
      %r_m = builtin.unrealized_conversion_cast %r_d : !d to !m
      %real = builtin.unrealized_conversion_cast %r_m : !m to !s
      %c = trikeshed.compare %front, %real unsigned : !s, !s
      %same = arith.cmpi eq, %c, %z32 : i32
      scf.yield %same : i1
    } else {
      %no = arith.constant 0 : i1
      scf.yield %no : i1
    }
    %skip = arith.select %under, %rn, %c0 : i64
    %lp = llvm.getelementptr %tp[%skip] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %ln = arith.subi %tn, %skip : i64
    %sp = func.call @sbw_p(%h, %c9) : (!llvm.ptr, i64) -> !llvm.ptr
    %sn = func.call @sbw_g(%h, %c10) : (!llvm.ptr, i64) -> i64
    %in = func.call @mlnix_isInStore(%sp, %sn, %lp, %ln) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i1
    scf.if %in {
      %from = arith.addi %sn, %c1 : i64
      %rest_n = arith.subi %ln, %from : i64
      %rest_p = llvm.getelementptr %lp[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %rest_d = func.call @sbw_d(%rest_p, %rest_n) : (!llvm.ptr, i64) -> !d
      %rest_m = builtin.unrealized_conversion_cast %rest_d : !d to !m
      %rest = builtin.unrealized_conversion_cast %rest_m : !m to !s
      %ps = trikeshed.parts %rest, %slash : !s, i8 -> !sp
      %first = trikeshed.at %ps[%z] : !sp, index -> !tp
      %fl32 = trikeshed.second %first : !tp -> i32
      %fl = arith.extui %fl32 : i32 to i64
      %cut = arith.addi %from, %fl : i64
      %set = func.call @sbw_p(%h, %c8) : (!llvm.ptr, i64) -> !llvm.ptr
      func.call @nixsb_ref(%set, %lp, %cut) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    } else {
      scf.if %indirect {
      } else {
        %there = func.call @nixsb_exists(%lp, %ln) : (!llvm.ptr, i64) -> i64
        %gone = arith.cmpi eq, %there, %c0 : i64
        scf.if %gone {
          %rc = func.call @unlink(%path) : (!llvm.ptr) -> i32
        }
      }
    }
  }
  return
}

// The directory of roots at room 0's first len bytes: its entries in the order read, a directory among them walked in
// its turn, a link taken (sbw_root_link); one that cannot be opened has none.
func.func private @sbw_roots(%h: !llvm.ptr, %len: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c16 = arith.constant 16 : i64
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %dirp = func.call @sbw_p(%h, %c1) : (!llvm.ptr, i64) -> !llvm.ptr
  %mark = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
  %l = func.call @sbw_list(%h, %dirp) : (!llvm.ptr, !llvm.ptr) -> i64
  %listed = arith.cmpi eq, %l, %c0 : i64
  scf.if %listed {
    %end = func.call @sbw_g(%h, %c7) : (!llvm.ptr, i64) -> i64
    %oe = scf.while (%off = %mark) : (i64) -> (i64) {
      %in = arith.cmpi slt, %off, %end : i64
      scf.condition(%in) %off : i64
    } do {
    ^bb0(%oa: i64):
      %np, %nn, %next = func.call @sbw_name(%h, %oa) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
      %pb = func.call @sbw_put(%h, %c0, %len, %c1, %np, %nn) : (!llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> !llvm.ptr
      %l1 = arith.addi %len, %c1 : i64
      %clen = arith.addi %l1, %nn : i64
      %mode = func.call @nixsb_os_lstat(%pb, %cell) : (!llvm.ptr, !llvm.ptr) -> i64
      %kind = arith.shrsi %mode, %c16 : i64
      %isdir = arith.cmpi eq, %kind, %c2 : i64
      %islnk = arith.cmpi eq, %kind, %c3 : i64
      scf.if %isdir {
        func.call @sbw_roots(%h, %clen) : (!llvm.ptr, i64) -> ()
      }
      scf.if %islnk {
        func.call @sbw_root_link(%h) : (!llvm.ptr) -> ()
      }
      scf.yield %next : i64
    }
    func.call @sbw_s(%h, %c7, %mark) : (!llvm.ptr, i64, i64) -> ()
    func.call @sbw_cut(%h, %c0, %len) : (!llvm.ptr, i64, i64) -> ()
  }
  return
}

// settings: the store's (StoreSettings begins with three Texts, a pointer and 32 bits of length each: the store
// directory, the store's physical root, the state directory); set: where the roots go (nixsb_ref).  The roots'
// directory is the state directory's "gcroots": one combine drained once into room 0.
func.func @nixsb_roots(%settings: !llvm.ptr, %set: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %low32 = arith.constant 4294967295 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i8 = arith.constant 8 : index
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  %ctx = llvm.mlir.zero : !llvm.ptr
  func.call @sbw_open(%h, %ctx) : (!llvm.ptr, !llvm.ptr) -> ()
  %sd = func.call @sbw_d(%settings, %c6) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m64
  %sw = builtin.unrealized_conversion_cast %sm : !m64 to !s64
  %spb = trikeshed.at %sw[%z] : !s64, index -> i64
  %snw = trikeshed.at %sw[%i1] : !s64, index -> i64
  %rpb = trikeshed.at %sw[%i2] : !s64, index -> i64
  %rnw = trikeshed.at %sw[%i3] : !s64, index -> i64
  %tpb = trikeshed.at %sw[%i4] : !s64, index -> i64
  %tnw = trikeshed.at %sw[%i5] : !s64, index -> i64
  %sn = arith.andi %snw, %low32 : i64
  %rn = arith.andi %rnw, %low32 : i64
  %tn = arith.andi %tnw, %low32 : i64
  %setb = llvm.ptrtoint %set : !llvm.ptr to i64
  func.call @sbw_s(%h, %c8, %setb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c9, %spb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c10, %sn) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c11, %rpb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbw_s(%h, %c12, %rn) : (!llvm.ptr, i64, i64) -> ()
  %dn = arith.addi %tn, %c8 : i64
  %need = arith.addi %dn, %c8 : i64
  %base = func.call @sbw_room(%h, %c0, %need) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %tp = llvm.inttoptr %tpb : i64 to !llvm.ptr
  %t_d = func.call @sbw_d(%tp, %tn) : (!llvm.ptr, i64) -> !d
  %t_m = builtin.unrealized_conversion_cast %t_d : !d to !m
  %state = builtin.unrealized_conversion_cast %t_m : !m to !s
  %bg = memref.get_global @sbw_bytes : memref<12xi8>
  %bytes = trikeshed.text %bg : memref<12xi8> -> !s
  %gcroots = trikeshed.slice %bytes[%i4, %i8] : !s -> !s
  %nul = trikeshed.slice %bytes[%i1, %i1] : !s -> !s
  %dir = trikeshed.combine %state, %gcroots, %nul : !s, !s, !s -> !s
  %bd = func.call @sbw_d(%base, %need) : (!llvm.ptr, i64) -> !d
  %bm = builtin.unrealized_conversion_cast %bd : !d to !m
  %end = trikeshed.drain %dir, %bm : !s, !m -> index
  func.call @sbw_roots(%h, %dn) : (!llvm.ptr, i64) -> ()
  func.call @sbw_close(%h) : (!llvm.ptr) -> ()
  return
}
