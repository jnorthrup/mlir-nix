// The store's files: lib/Store/StorePaths.cpp's readFile, writeFile, pathExists, createDirs and deletePathRecursive.
// The C++ keeps a forward each (the path made a C string, the message thrown); the system calls are made here, through
// the C library, and the errors are worded here, Nix's wording byte for byte.
//
//   nixstore_fs_read(path, n, out)                 a file's bytes into the Text at out.  The Text is given once the room
//                                                  the file says it holds (fstat) and the reads fill it where the
//                                                  bytes stay; what the file holds past that (it grew, or it said
//                                                  nothing: a pipe, a device) is read into pages that are never moved
//                                                  and drained once, one combineAll, after the Text is sized to the whole
//   nixstore_fs_write(path, n, data, dn, mode, err)  a file made (or cut) and written
//   nixstore_fs_exists(path)                       1 when lstat finds it (a dangling link is there)
//   nixstore_fs_mkdirs(path, n, err)               the directory and its parents made (dirOf, PathOps.mlir), a link to a
//                                                  directory taken for one
//   nixstore_fs_delete(path, n, err)               the tree at path removed: a directory's names are filled into pages
//                                                  first, then walked (a fold over the pages, and in each over the
//                                                  parts between the names' NULs), each entry's path one combine
//                                                  drained once, the first failure kept
//   nixstore_fs_note(kind, path)                   nixprefetch::note: a file access told to the recorder, when one records
//
// path is a C string (n its bytes: the forward's nixsys::CStr).  An entry that can fail answers 0, or 1 with the message
// in the Text at err (read: at out), which the forward throws; nothing made here outlives the call.  errno is read where
// the C++ read it (after the close for a failed write, before it for a failed read).  A file read or looked at is told
// to the recorder of file accesses when one records.
//
// What loops here: the calls whose order is the effect, each a small scf.while of its own (fs_readinto: read; fs_readpages:
// a page made, then filled; fs_writeall: write; fs_names: readdir).  The bytes those calls leave are views made once
// (a page, a name, a path), read by at, compare, parts and slices, and copied by drains.  The rooms made here are
// malloc's under the system module's names (nixfs_os_room, nixfs_os_done): a module whose ops allocate (parts does)
// cannot declare malloc and free as functions of its own.
//
// The system's words (a stat record's mode and size, errno, a file made with a mode) are FileOsDarwin.mlir.in and
// FileOsLinux.mlir.in, beside the store index's (nixsi_os_*: open, fstat, lstat, opendir, readdir, a directory entry's
// name), which are called as they are.
//
// Written as FileOps.mlir.t and expanded by gen.py (both kept outside the repository, with the lane's harnesses: the
// literals are spans of one blob).  Lowered by --trikeshed-lower-cursors and the stock buffer pipeline
// (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @fs_words : memref<115xi8> =
  dense<"0x6f70656e696e672066696c652027273a2072656164696e672066696c6520276372656174696e672066696c65202777726974696e672066696c65202727206973206e6f742061206469726563746f72796372656174696e67206469726563746f727920272f002e2e2e72656d6f76696e672027">

// the C library
func.func private @close(i32) -> i32
func.func private @read(i32, !llvm.ptr, i64) -> i64
func.func private @write(i32, !llvm.ptr, i64) -> i64
func.func private @unlink(!llvm.ptr) -> i32
func.func private @rmdir(!llvm.ptr) -> i32
func.func private @mkdir(!llvm.ptr, i32) -> i32
func.func private @chmod(!llvm.ptr, i32) -> i32
func.func private @closedir(!llvm.ptr) -> i32
func.func private @strerror(i32) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @abort()
// the system's words: the store index's, and this module's
func.func private @nixsi_os_open(!llvm.ptr, i64) -> i32
func.func private @nixsi_os_fstat(i32, !llvm.ptr) -> i32
func.func private @nixsi_os_lstat(!llvm.ptr, !llvm.ptr) -> i32
func.func private @nixsi_os_opendir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsi_os_readdir(!llvm.ptr) -> !llvm.ptr
func.func private @nixsi_os_name() -> i64
func.func private @nixfs_os_errno() -> i32
func.func private @nixfs_os_create(!llvm.ptr, i32) -> i32
func.func private @nixfs_os_stat(!llvm.ptr, !llvm.ptr) -> i32
func.func private @nixfs_os_mode(!llvm.ptr) -> i32
func.func private @nixfs_os_size(!llvm.ptr) -> i64
func.func private @nixfs_os_room(i64) -> !llvm.ptr
func.func private @nixfs_os_done(!llvm.ptr)
// the Text at t made n bytes long (what it held is kept, a NUL follows): where its bytes are (StorePaths.cpp)
func.func private @nixstore_text_sized(!llvm.ptr, i64) -> !llvm.ptr
// the recorder of file accesses (Prefetch.cpp): whether it records, and a path told to it
llvm.mlir.global external @_ZN11nixprefetch9recordingE() : i8
func.func private @_ZN11nixprefetch8noteSlowEcPKc(i32, !llvm.ptr)
// dirOf (PathOps.mlir)
func.func private @nixstore_ts_dirname(!llvm.ptr, i64, !llvm.ptr) -> i64

// the descriptor of n cells at p
func.func private @fs_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the evaluation touches the file at cp, in the way `kind` names ('F' read, 'L' looked at, 'D' listed): told to the
// recorder when one records (the other modules of the store's files and hashes call it too)
func.func @nixstore_fs_note(%kind: i32, %cp: !llvm.ptr) {
  %z8 = arith.constant 0 : i8
  %g = llvm.mlir.addressof @_ZN11nixprefetch9recordingE : !llvm.ptr
  %on8 = llvm.load %g : !llvm.ptr -> i8
  %on = arith.cmpi ne, %on8, %z8 : i8
  scf.if %on {
    func.call @_ZN11nixprefetch8noteSlowEcPKc(%kind, %cp) : (i32, !llvm.ptr) -> ()
  }
  return
}

// A failure's message put in the Text at err: the words at [ao, an), the path, the words at [bo, bn), and what the
// system says of error e (strerror) unless e is negative.  One combine, drained once into the Text sized to it.  Answers 1.
func.func private @fs_fail(%err: !llvm.ptr, %ao: index, %an: index, %p: !llvm.ptr, %n: i64, %bo: index, %bn: index, %e: i32) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %z32 = arith.constant 0 : i32
  %words_g = memref.get_global @fs_words : memref<115xi8>
  %words = trikeshed.text %words_g : memref<115xi8> -> !s
  %a = trikeshed.slice %words[%ao, %an] : !s -> !s
  %b = trikeshed.slice %words[%bo, %bn] : !s -> !s
  %path_d = func.call @fs_desc(%p, %n) : (!llvm.ptr, i64) -> !d
  %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
  %path = builtin.unrealized_conversion_cast %path_m : !m to !s
  %said = arith.cmpi sge, %e, %z32 : i32
  %wp, %wn = scf.if %said -> (!llvm.ptr, i64) {
    %t = func.call @strerror(%e) : (i32) -> !llvm.ptr
    %tn = func.call @strlen(%t) : (!llvm.ptr) -> i64
    scf.yield %t, %tn : !llvm.ptr, i64
  } else {
    scf.yield %p, %c0 : !llvm.ptr, i64
  }
  %why_d = func.call @fs_desc(%wp, %wn) : (!llvm.ptr, i64) -> !d
  %why_m = builtin.unrealized_conversion_cast %why_d : !d to !m
  %why = builtin.unrealized_conversion_cast %why_m : !m to !s
  %msg = trikeshed.combine %a, %path, %b, %why : !s, !s, !s, !s -> !s
  %sz = trikeshed.size %msg : !s
  %sz64 = arith.index_cast %sz : index to i64
  %room = func.call @nixstore_text_sized(%err, %sz64) : (!llvm.ptr, i64) -> !llvm.ptr
  %into_d = func.call @fs_desc(%room, %sz64) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %into_d : !d to !m
  %end = trikeshed.drain %msg, %into : !s, !m -> index
  return %c1 : i64
}

// a stat record's kind: its mode's type bits (S_IFMT)
func.func private @fs_kind(%st: !llvm.ptr) -> i32 {
  %mask = arith.constant 61440 : i32
  %mode = func.call @nixfs_os_mode(%st) : (!llvm.ptr) -> i32
  %k = arith.andi %mode, %mask : i32
  return %k : i32
}

//===----------------------------------------------------------------------===//
// Pages: a fill whose size is not known ahead
//===----------------------------------------------------------------------===//
// Page k of a fill holds `unit << k` bytes; it is filled before the next is made and is never moved, so nothing is
// copied until the one drain (or walk) that follows the fill.  A fill has 48 pages at most; the caller's two tables of
// 48 words get each page's address and how many bytes it holds.

// the room of page k of `unit`-byte pages: `first` when it is page 0 and the caller has one of its own, else a room of malloc's
func.func private @fs_page(%first: !llvm.ptr, %unit: i64, %k: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %fb = llvm.ptrtoint %first : !llvm.ptr to i64
  %has = arith.cmpi ne, %fb, %c0 : i64
  %is0 = arith.cmpi eq, %k, %c0 : i64
  %own = arith.andi %has, %is0 : i1
  %p = scf.if %own -> (!llvm.ptr) {
    scf.yield %first : !llvm.ptr
  } else {
    %cap = arith.shli %unit, %k : i64
    %q = func.call @nixfs_os_room(%cap) : (i64) -> !llvm.ptr
    %qb = llvm.ptrtoint %q : !llvm.ptr to i64
    %gone = arith.cmpi eq, %qb, %c0 : i64
    scf.if %gone {
      func.call @abort() : () -> ()
    }
    scf.yield %q : !llvm.ptr
  }
  return %p : !llvm.ptr
}

// The pages' bytes one after the other: ONE combineAll (page k's filled bytes, a view of the page), drained once into
// the `total` bytes at `into`.
func.func private @fs_drainpages(%pages: !llvm.ptr, %fills: !llvm.ptr, %npages: i64, %into: !llvm.ptr, %total: i64) {
  %ps_d = func.call @fs_desc(%pages, %npages) : (!llvm.ptr, i64) -> !d
  %ps_m = builtin.unrealized_conversion_cast %ps_d : !d to !m64
  %ps = builtin.unrealized_conversion_cast %ps_m : !m64 to !s64
  %fs_d = func.call @fs_desc(%fills, %npages) : (!llvm.ptr, i64) -> !d
  %fs_m = builtin.unrealized_conversion_cast %fs_d : !d to !m64
  %fs = builtin.unrealized_conversion_cast %fs_m : !m64 to !s64
  %ni = arith.index_cast %npages : i64 to index
  %all, %coords = trikeshed.combineAll %ni : !s, !sp {
  ^bb0(%k: index):
    %p64 = trikeshed.at %ps[%k] : !s64, index -> i64
    %n = trikeshed.at %fs[%k] : !s64, index -> i64
    %p = llvm.inttoptr %p64 : i64 to !llvm.ptr
    %page_d = func.call @fs_desc(%p, %n) : (!llvm.ptr, i64) -> !d
    %page_m = builtin.unrealized_conversion_cast %page_d : !d to !m
    %page = builtin.unrealized_conversion_cast %page_m : !m to !s
    trikeshed.yield %page : !s
  }
  %room_d = func.call @fs_desc(%into, %total) : (!llvm.ptr, i64) -> !d
  %room = builtin.unrealized_conversion_cast %room_d : !d to !m
  %end = trikeshed.drain %all, %room : !s, !m -> index
  return
}

// the pages from page `from` on given back: a walk over the table
func.func private @fs_freepages(%pages: !llvm.ptr, %npages: i64, %from: i64) {
  %c0 = arith.constant 0 : i64
  %ps_d = func.call @fs_desc(%pages, %npages) : (!llvm.ptr, i64) -> !d
  %ps_m = builtin.unrealized_conversion_cast %ps_d : !d to !m64
  %ps = builtin.unrealized_conversion_cast %ps_m : !m64 to !s64
  %fi = arith.index_cast %from : i64 to index
  %ni = arith.index_cast %npages : i64 to index
  %capped = arith.minui %fi, %ni : index
  %left = arith.subi %ni, %capped : index
  %rest = trikeshed.slice %ps[%capped, %left] : !s64 -> !s64
  %done = trikeshed.fold %rest, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %p64: i64):
    %p = llvm.inttoptr %p64 : i64 to !llvm.ptr
    func.call @nixfs_os_done(%p) : (!llvm.ptr) -> ()
    trikeshed.yield %acc : i64
  }
  return
}

//===----------------------------------------------------------------------===//
// readFile
//===----------------------------------------------------------------------===//

// What readFile says of a file that could not be opened (e: the system's error): `opening file '<path>': <what the
// system says>`.  The one place that wording is made.
func.func private @fs_read_notopened(%err: !llvm.ptr, %cp: !llvm.ptr, %n: i64, %e: i32) -> i64 {
  %opening_o = arith.constant 0 : index  // "opening file '"
  %opening_n = arith.constant 14 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %f = func.call @fs_fail(%err, %opening_o, %opening_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
  return %f : i64
}

// The cap bytes at p filled from the file: read after read (their order is the effect, so an scf.while) until the room
// is full, the file ends or a read fails.  The bytes read; then 0 the room is full, 1 the file ended, 2 a read failed;
// and for a read that failed what the system said (-1 otherwise).
func.func private @fs_readinto(%fd: i32, %p: !llvm.ptr, %cap: i64) -> (i64, i64, i32) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %m1 = arith.constant -1 : i32
  %got, %state, %e = scf.while (%g = %c0, %s = %c0, %x = %m1) : (i64, i64, i32) -> (i64, i64, i32) {
    %room = arith.cmpi ult, %g, %cap : i64
    %reading = arith.cmpi eq, %s, %c0 : i64
    %go = arith.andi %room, %reading : i1
    scf.condition(%go) %g, %s, %x : i64, i64, i32
  } do {
  ^bb0(%ga: i64, %sa: i64, %xa: i32):
    %at = llvm.getelementptr %p[%ga] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %left = arith.subi %cap, %ga : i64
    %k = func.call @read(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
    %neg = arith.cmpi slt, %k, %c0 : i64
    %end = arith.cmpi eq, %k, %c0 : i64
    %xn = scf.if %neg -> (i32) {
      %e1 = func.call @nixfs_os_errno() : () -> i32
      scf.yield %e1 : i32
    } else {
      scf.yield %xa : i32
    }
    %g2 = arith.addi %ga, %k : i64
    %gn = arith.select %neg, %ga, %g2 : i64
    %s1 = arith.select %end, %c1, %c0 : i64
    %sn = arith.select %neg, %c2, %s1 : i64
    scf.yield %gn, %sn, %xn : i64, i64, i32
  }
  return %got, %state, %e : i64, i64, i32
}

// The rest of a file read into pages of 65536 << k bytes, the first the caller's: a page is made and filled (fs_readinto)
// while the one before it was filled to its end.  The pages made, the bytes they hold in all, and what the system said
// of a read that failed (-1 when none did).  A page made and then the reads into it, in that order: an scf.while.
func.func private @fs_readpages(%fd: i32, %first: !llvm.ptr, %pages: !llvm.ptr, %fills: !llvm.ptr) -> (i64, i64, i32) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c48 = arith.constant 48 : i64
  %c65536 = arith.constant 65536 : i64
  %m1 = arith.constant -1 : i32
  %ptab_d = func.call @fs_desc(%pages, %c48) : (!llvm.ptr, i64) -> !d
  %ptab = builtin.unrealized_conversion_cast %ptab_d : !d to !m64
  %ftab_d = func.call @fs_desc(%fills, %c48) : (!llvm.ptr, i64) -> !d
  %ftab = builtin.unrealized_conversion_cast %ftab_d : !d to !m64
  %np, %total, %state, %e = scf.while (%k = %c0, %t = %c0, %s = %c0, %x = %m1) : (i64, i64, i64, i32) -> (i64, i64, i64, i32) {
    %go = arith.cmpi eq, %s, %c0 : i64
    scf.condition(%go) %k, %t, %s, %x : i64, i64, i64, i32
  } do {
  ^bb0(%ka: i64, %ta: i64, %sa: i64, %xa: i32):
    %p = func.call @fs_page(%first, %c65536, %ka) : (!llvm.ptr, i64, i64) -> !llvm.ptr
    %cap = arith.shli %c65536, %ka : i64
    %got, %s2, %x2 = func.call @fs_readinto(%fd, %p, %cap) : (i32, !llvm.ptr, i64) -> (i64, i64, i32)
    %ki = arith.index_cast %ka : i64 to index
    %pb = llvm.ptrtoint %p : !llvm.ptr to i64
    memref.store %pb, %ptab[%ki] : !m64
    memref.store %got, %ftab[%ki] : !m64
    %k2 = arith.addi %ka, %c1 : i64
    %t2 = arith.addi %ta, %got : i64
    scf.yield %k2, %t2, %s2, %x2 : i64, i64, i64, i32
  }
  return %np, %total, %e : i64, i64, i32
}

func.func @nixstore_fs_read(%cp: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c20 = arith.constant 20 : i64
  %c48 = arith.constant 48 : i64
  %c65536 = arith.constant 65536 : i64
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %kF = arith.constant 70 : i32
  %regular = arith.constant 32768 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %reading_o = arith.constant 17 : index  // "reading file '"
  %reading_n = arith.constant 14 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  %page = llvm.alloca %c65536 x i8 : (i64) -> !llvm.ptr
  %pages = llvm.alloca %c48 x i64 : (i64) -> !llvm.ptr
  %fills = llvm.alloca %c48 x i64 : (i64) -> !llvm.ptr
  func.call @nixstore_fs_note(%kF, %cp) : (i32, !llvm.ptr) -> ()
  %fd = func.call @nixsi_os_open(%cp, %c0) : (!llvm.ptr, i64) -> i32
  %opened = arith.cmpi sge, %fd, %z32 : i32
  %r = scf.if %opened -> (i64) {
    // what a regular file says it holds: the Text is given that room once, and the reads fill it where the bytes stay
    %rc = func.call @nixsi_os_fstat(%fd, %st) : (i32, !llvm.ptr) -> i32
    %kind = func.call @fs_kind(%st) : (!llvm.ptr) -> i32
    %size = func.call @nixfs_os_size(%st) : (!llvm.ptr) -> i64
    %stok = arith.cmpi eq, %rc, %z32 : i32
    %reg = arith.cmpi eq, %kind, %regular : i32
    %some = arith.cmpi sgt, %size, %c0 : i64
    %k0 = arith.andi %stok, %reg : i1
    %known = arith.andi %k0, %some : i1
    %hint = arith.select %known, %size, %c0 : i64
    %p0 = scf.if %known -> (!llvm.ptr) {
      %q = func.call @nixstore_text_sized(%out, %size) : (!llvm.ptr, i64) -> !llvm.ptr
      scf.yield %q : !llvm.ptr
    } else {
      scf.yield %null : !llvm.ptr
    }
    %got0, %s0, %e0 = func.call @fs_readinto(%fd, %p0, %hint) : (i32, !llvm.ptr, i64) -> (i64, i64, i32)
    // what it holds past that room (all of it, when it said nothing of its size): pages, the first this stack's
    %full = arith.cmpi eq, %s0, %c0 : i64
    %np, %more, %e1 = scf.if %full -> (i64, i64, i32) {
      %a, %b, %c = func.call @fs_readpages(%fd, %page, %pages, %fills) : (i32, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (i64, i64, i32)
      scf.yield %a, %b, %c : i64, i64, i32
    } else {
      scf.yield %c0, %c0, %m1 : i64, i64, i32
    }
    %rcc = func.call @close(%fd) : (i32) -> i32
    %bad0 = arith.cmpi eq, %s0, %c2 : i64
    %e = arith.select %bad0, %e0, %e1 : i32
    %failed = arith.cmpi sge, %e, %z32 : i32
    %res = scf.if %failed -> (i64) {
      %f = func.call @fs_fail(%out, %reading_o, %reading_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      // the Text is what was read: sized once more when that is not what the file said, the pages' bytes drained once
      // after the bytes read in place
      %total = arith.addi %got0, %more : i64
      %same = arith.cmpi eq, %total, %hint : i64
      %room = scf.if %same -> (!llvm.ptr) {
        scf.yield %p0 : !llvm.ptr
      } else {
        %q3 = func.call @nixstore_text_sized(%out, %total) : (!llvm.ptr, i64) -> !llvm.ptr
        scf.yield %q3 : !llvm.ptr
      }
      %at = llvm.getelementptr %room[%got0] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      func.call @fs_drainpages(%pages, %fills, %np, %at, %more) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
      scf.yield %c0 : i64
    }
    func.call @fs_freepages(%pages, %np, %c1) : (!llvm.ptr, i64, i64) -> ()
    scf.yield %res : i64
  } else {
    %e0 = func.call @nixfs_os_errno() : () -> i32
    %f0 = func.call @fs_read_notopened(%out, %cp, %n, %e0) : (!llvm.ptr, !llvm.ptr, i64, i32) -> i64
    scf.yield %f0 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// writeFile
//===----------------------------------------------------------------------===//

// The n bytes at p written to the file: write after write (their order is the effect, so an scf.while), each given the
// bytes not yet written, until none is left or a write fails.  0, or 2 when a write failed.
func.func private @fs_writeall(%fd: i32, %p: !llvm.ptr, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %oe, %se = scf.while (%off = %c0, %state = %c0) : (i64, i64) -> (i64, i64) {
    %more = arith.cmpi ult, %off, %n : i64
    %fine = arith.cmpi eq, %state, %c0 : i64
    %go = arith.andi %more, %fine : i1
    scf.condition(%go) %off, %state : i64, i64
  } do {
  ^bb0(%oa: i64, %sa: i64):
    %at = llvm.getelementptr %p[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %left = arith.subi %n, %oa : i64
    %k = func.call @write(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
    %neg = arith.cmpi slt, %k, %c0 : i64
    %o2 = arith.addi %oa, %k : i64
    %on = arith.select %neg, %oa, %o2 : i64
    %sn = arith.select %neg, %c2, %c0 : i64
    scf.yield %on, %sn : i64, i64
  }
  return %se : i64
}

func.func @nixstore_fs_write(%cp: !llvm.ptr, %n: i64, %data: !llvm.ptr, %dn: i64, %mode: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %z32 = arith.constant 0 : i32
  %creating_o = arith.constant 31 : index  // "creating file '"
  %creating_n = arith.constant 15 : index
  %writing_o = arith.constant 46 : index  // "writing file '"
  %writing_n = arith.constant 14 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %mode32 = arith.trunci %mode : i64 to i32
  %fd = func.call @nixfs_os_create(%cp, %mode32) : (!llvm.ptr, i32) -> i32
  %made = arith.cmpi sge, %fd, %z32 : i32
  %r = scf.if %made -> (i64) {
    %state = func.call @fs_writeall(%fd, %data, %dn) : (i32, !llvm.ptr, i64) -> i64
    %rcc = func.call @close(%fd) : (i32) -> i32
    %failed = arith.cmpi ne, %state, %c0 : i64
    %res = scf.if %failed -> (i64) {
      // what the system says once the file is closed, as the C++ read it
      %e = func.call @nixfs_os_errno() : () -> i32
      %f = func.call @fs_fail(%err, %writing_o, %writing_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %res : i64
  } else {
    %e0 = func.call @nixfs_os_errno() : () -> i32
    %f0 = func.call @fs_fail(%err, %creating_o, %creating_n, %cp, %n, %why_o, %why_n, %e0) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
    scf.yield %f0 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// pathExists
//===----------------------------------------------------------------------===//

func.func @nixstore_fs_exists(%cp: !llvm.ptr) -> i64 {
  %c20 = arith.constant 20 : i64
  %z32 = arith.constant 0 : i32
  %kL = arith.constant 76 : i32
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  func.call @nixstore_fs_note(%kL, %cp) : (i32, !llvm.ptr) -> ()
  %rc = func.call @nixsi_os_lstat(%cp, %st) : (!llvm.ptr, !llvm.ptr) -> i32
  %there = arith.cmpi eq, %rc, %z32 : i32
  %r = arith.extui %there : i1 to i64
  return %r : i64
}

//===----------------------------------------------------------------------===//
// createDirs
//===----------------------------------------------------------------------===//

func.func @nixstore_fs_mkdirs(%cp: !llvm.ptr, %n: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c20 = arith.constant 20 : i64
  %z32 = arith.constant 0 : i32
  %m1 = arith.constant -1 : i32
  %false = arith.constant false
  %directory = arith.constant 16384 : i32
  %link = arith.constant 40960 : i32
  %all = arith.constant 511 : i32
  %exists = arith.constant 17 : i32
  %quote_o = arith.constant 13 : index  // "'"
  %quote_n = arith.constant 1 : index
  %notdir_o = arith.constant 60 : index  // "' is not a directory"
  %notdir_n = arith.constant 20 : index
  %creating_o = arith.constant 80 : index  // "creating directory '"
  %creating_n = arith.constant 20 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %words_g = memref.get_global @fs_words : memref<115xi8>
  %words = trikeshed.text %words_g : memref<115xi8> -> !s
  %slash_o = arith.constant 100 : index  // "/"
  %slash_n = arith.constant 1 : index
  %slash = trikeshed.slice %words[%slash_o, %slash_n] : !s -> !s
  %nul_o = arith.constant 101 : index  // "\u0000"
  %nul_n = arith.constant 1 : index
  %nul = trikeshed.slice %words[%nul_o, %nul_n] : !s -> !s
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  // nothing to make for no path and for the root
  %path_d = func.call @fs_desc(%cp, %n) : (!llvm.ptr, i64) -> !d
  %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
  %path = builtin.unrealized_conversion_cast %path_m : !m to !s
  %croot = trikeshed.compare %path, %slash unsigned : !s, !s
  %root = arith.cmpi eq, %croot, %z32 : i32
  %empty = arith.cmpi eq, %n, %c0 : i64
  %none = arith.ori %empty, %root : i1
  %r = scf.if %none -> (i64) {
    scf.yield %c0 : i64
  } else {
    %rc = func.call @nixsi_os_lstat(%cp, %st) : (!llvm.ptr, !llvm.ptr) -> i32
    %there = arith.cmpi eq, %rc, %z32 : i32
    %r1 = scf.if %there -> (i64) {
      %kind = func.call @fs_kind(%st) : (!llvm.ptr) -> i32
      %isdir = arith.cmpi eq, %kind, %directory : i32
      %islink = arith.cmpi eq, %kind, %link : i32
      // a link to a directory is one
      %through = scf.if %islink -> (i1) {
        %rc2 = func.call @nixfs_os_stat(%cp, %st) : (!llvm.ptr, !llvm.ptr) -> i32
        %kind2 = func.call @fs_kind(%st) : (!llvm.ptr) -> i32
        %ok2 = arith.cmpi eq, %rc2, %z32 : i32
        %dir2 = arith.cmpi eq, %kind2, %directory : i32
        %t = arith.andi %ok2, %dir2 : i1
        scf.yield %t : i1
      } else {
        scf.yield %false : i1
      }
      %fine = arith.ori %isdir, %through : i1
      %r2 = scf.if %fine -> (i64) {
        scf.yield %c0 : i64
      } else {
        %f = func.call @fs_fail(%err, %quote_o, %quote_n, %cp, %n, %notdir_o, %notdir_n, %m1) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
        scf.yield %f : i64
      }
      scf.yield %r2 : i64
    } else {
      // the parent first (dirOf's bytes, PathOps.mlir, then a NUL drained after them: a C string), then this one;
      // another's making it meanwhile is no failure
      %room = arith.addi %n, %c2 : i64
      %dp = func.call @nixfs_os_room(%room) : (i64) -> !llvm.ptr
      %dn = func.call @nixstore_ts_dirname(%cp, %n, %dp) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      %dend = llvm.getelementptr %dp[%dn] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %tail_d = func.call @fs_desc(%dend, %c1) : (!llvm.ptr, i64) -> !d
      %tail = builtin.unrealized_conversion_cast %tail_d : !d to !m
      %te = trikeshed.drain %nul, %tail : !s, !m -> index
      %up = func.call @nixstore_fs_mkdirs(%dp, %dn, %err) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      func.call @nixfs_os_done(%dp) : (!llvm.ptr) -> ()
      %upok = arith.cmpi eq, %up, %c0 : i64
      %r3 = scf.if %upok -> (i64) {
        %rc3 = func.call @mkdir(%cp, %all) : (!llvm.ptr, i32) -> i32
        %e = func.call @nixfs_os_errno() : () -> i32
        %notmade = arith.cmpi ne, %rc3, %z32 : i32
        %other = arith.cmpi ne, %e, %exists : i32
        %bad = arith.andi %notmade, %other : i1
        %r4 = scf.if %bad -> (i64) {
          %f = func.call @fs_fail(%err, %creating_o, %creating_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
          scf.yield %f : i64
        } else {
          scf.yield %c0 : i64
        }
        scf.yield %r4 : i64
      } else {
        scf.yield %up : i64
      }
      scf.yield %r3 : i64
    }
    scf.yield %r1 : i64
  }
  return %r : i64
}

//===----------------------------------------------------------------------===//
// deletePathRecursive
//===----------------------------------------------------------------------===//

// The names an open directory gives, but for "." and "..", in the order it gives them (readdir after readdir: their
// order is the effect, so an scf.while), each with its NUL, filled into pages of 4096 << k bytes: a page's first word is
// how many bytes of names follow it; a name is whole in its page (one that does not fit opens the next; none is longer
// than a page) and is copied there by one drain.  The caller's table gets each page's address.  The pages made.
func.func private @fs_names(%dir: !llvm.ptr, %pages: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c48 = arith.constant 48 : i64
  %c4096 = arith.constant 4096 : i64
  %z32 = arith.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %words_g = memref.get_global @fs_words : memref<115xi8>
  %words = trikeshed.text %words_g : memref<115xi8> -> !s
  %dot_o = arith.constant 102 : index  // "."
  %dot_n = arith.constant 1 : index
  %dot = trikeshed.slice %words[%dot_o, %dot_n] : !s -> !s
  %dotdot_o = arith.constant 103 : index  // ".."
  %dotdot_n = arith.constant 2 : index
  %dotdot = trikeshed.slice %words[%dotdot_o, %dotdot_n] : !s -> !s
  %nul_o = arith.constant 101 : index  // "\u0000"
  %nul_n = arith.constant 1 : index
  %nul = trikeshed.slice %words[%nul_o, %nul_n] : !s -> !s
  %noff = func.call @nixsi_os_name() : () -> i64
  %ptab_d = func.call @fs_desc(%pages, %c48) : (!llvm.ptr, i64) -> !d
  %ptab = builtin.unrealized_conversion_cast %ptab_d : !d to !m64
  %e0 = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
  %e0b = llvm.ptrtoint %e0 : !llvm.ptr to i64
  // k pages made; the last one, the bytes of names in it and the room it has left
  %ee, %ke, %pe, %fe, %le = scf.while (%e = %e0b, %k = %c0, %page = %c0, %fill = %c0, %left = %c0) : (i64, i64, i64, i64, i64) -> (i64, i64, i64, i64, i64) {
    %more = arith.cmpi ne, %e, %c0 : i64
    scf.condition(%more) %e, %k, %page, %fill, %left : i64, i64, i64, i64, i64
  } do {
  ^bb0(%ea: i64, %ka: i64, %pa: i64, %fa: i64, %la: i64):
    %ep = llvm.inttoptr %ea : i64 to !llvm.ptr
    %np = llvm.getelementptr %ep[%noff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nn = func.call @strlen(%np) : (!llvm.ptr) -> i64
    %name_d = func.call @fs_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
    %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
    %name = builtin.unrealized_conversion_cast %name_m : !m to !s
    %cself = trikeshed.compare %name, %dot unsigned : !s, !s
    %cup = trikeshed.compare %name, %dotdot unsigned : !s, !s
    %self = arith.cmpi eq, %cself, %z32 : i32
    %up = arith.cmpi eq, %cup, %z32 : i32
    %skip = arith.ori %self, %up : i1
    %kn, %pn, %fn, %ln = scf.if %skip -> (i64, i64, i64, i64) {
      scf.yield %ka, %pa, %fa, %la : i64, i64, i64, i64
    } else {
      // the name and its NUL: one combine, drained once where the open page's names end
      %entry = trikeshed.combine %name, %nul : !s, !s -> !s
      %need = trikeshed.size %entry : !s
      %need64 = arith.index_cast %need : index to i64
      %fits = arith.cmpi ule, %need64, %la : i64
      %k2, %p2, %f2, %l2 = scf.if %fits -> (i64, i64, i64, i64) {
        scf.yield %ka, %pa, %fa, %la : i64, i64, i64, i64
      } else {
        %q = func.call @fs_page(%null, %c4096, %ka) : (!llvm.ptr, i64, i64) -> !llvm.ptr
        %qb = llvm.ptrtoint %q : !llvm.ptr to i64
        %ki = arith.index_cast %ka : i64 to index
        memref.store %qb, %ptab[%ki] : !m64
        %cap = arith.shli %c4096, %ka : i64
        %room = arith.subi %cap, %c8 : i64
        %k3 = arith.addi %ka, %c1 : i64
        scf.yield %k3, %qb, %c0, %room : i64, i64, i64, i64
      }
      %pp = llvm.inttoptr %p2 : i64 to !llvm.ptr
      %from = arith.addi %f2, %c8 : i64
      %at = llvm.getelementptr %pp[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %into_d = func.call @fs_desc(%at, %need64) : (!llvm.ptr, i64) -> !d
      %into = builtin.unrealized_conversion_cast %into_d : !d to !m
      %end = trikeshed.drain %entry, %into : !s, !m -> index
      %f3 = arith.addi %f2, %need64 : i64
      llvm.store %f3, %pp : i64, !llvm.ptr
      %l3 = arith.subi %l2, %need64 : i64
      scf.yield %k2, %p2, %f3, %l3 : i64, i64, i64, i64
    }
    %en = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
    %enb = llvm.ptrtoint %en : !llvm.ptr to i64
    scf.yield %enb, %kn, %pn, %fn, %ln : i64, i64, i64, i64, i64
  }
  return %ke : i64
}

func.func @nixstore_fs_delete(%cp: !llvm.ptr, %n: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %c20 = arith.constant 20 : i64
  %c48 = arith.constant 48 : i64
  %z = arith.constant 0 : index
  %z32 = arith.constant 0 : i32
  %nul8 = arith.constant 0 : i8
  %directory = arith.constant 16384 : i32
  %mine = arith.constant 448 : i32
  %removing_o = arith.constant 105 : index  // "removing '"
  %removing_n = arith.constant 10 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %words_g = memref.get_global @fs_words : memref<115xi8>
  %words = trikeshed.text %words_g : memref<115xi8> -> !s
  %slash_o = arith.constant 100 : index  // "/"
  %slash_n = arith.constant 1 : index
  %slash = trikeshed.slice %words[%slash_o, %slash_n] : !s -> !s
  %nul_o = arith.constant 101 : index  // "\u0000"
  %nul_n = arith.constant 1 : index
  %nul = trikeshed.slice %words[%nul_o, %nul_n] : !s -> !s
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  %pages = llvm.alloca %c48 x i64 : (i64) -> !llvm.ptr
  %rc = func.call @nixsi_os_lstat(%cp, %st) : (!llvm.ptr, !llvm.ptr) -> i32
  %there = arith.cmpi eq, %rc, %z32 : i32
  %r = scf.if %there -> (i64) {
    %kind = func.call @fs_kind(%st) : (!llvm.ptr) -> i32
    %isdir = arith.cmpi eq, %kind, %directory : i32
    %r1 = scf.if %isdir -> (i64) {
      // the owner may read, write and search it, whatever it was
      %mode = func.call @nixfs_os_mode(%st) : (!llvm.ptr) -> i32
      %open = arith.ori %mode, %mine : i32
      %rcm = func.call @chmod(%cp, %open) : (!llvm.ptr, i32) -> i32
      %dir = func.call @nixsi_os_opendir(%cp) : (!llvm.ptr) -> !llvm.ptr
      %db = llvm.ptrtoint %dir : !llvm.ptr to i64
      %listed = arith.cmpi ne, %db, %c0 : i64
      %kids = scf.if %listed -> (i64) {
        // the names first, the directory closed, then each entry removed in the order the directory gave them: a fold
        // over the pages and in each a fold over its names (the parts between the NULs; after the last NUL there is
        // none), which keeps the first failure and removes nothing after it
        %np = func.call @fs_names(%dir, %pages) : (!llvm.ptr, !llvm.ptr) -> i64
        %rcd = func.call @closedir(%dir) : (!llvm.ptr) -> i32
        %path_d = func.call @fs_desc(%cp, %n) : (!llvm.ptr, i64) -> !d
        %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
        %path = builtin.unrealized_conversion_cast %path_m : !m to !s
        %ps_d = func.call @fs_desc(%pages, %np) : (!llvm.ptr, i64) -> !d
        %ps_m = builtin.unrealized_conversion_cast %ps_d : !d to !m64
        %ps = builtin.unrealized_conversion_cast %ps_m : !m64 to !s64
        %failed = trikeshed.fold %ps, %c0 : !s64, i64 -> i64 {
        ^bb0(%acc: i64, %p64: i64):
          // a page: how many bytes of names it holds, then the names
          %pp = llvm.inttoptr %p64 : i64 to !llvm.ptr
          %head_d = func.call @fs_desc(%pp, %c1) : (!llvm.ptr, i64) -> !d
          %head_m = builtin.unrealized_conversion_cast %head_d : !d to !m64
          %head = builtin.unrealized_conversion_cast %head_m : !m64 to !s64
          %fill = trikeshed.at %head[%z] : !s64, index -> i64
          %first = llvm.getelementptr %pp[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %page_d = func.call @fs_desc(%first, %fill) : (!llvm.ptr, i64) -> !d
          %page_m = builtin.unrealized_conversion_cast %page_d : !d to !m
          %page = builtin.unrealized_conversion_cast %page_m : !m to !s
          %names = trikeshed.parts %page, %nul8 : !s, i8 -> !sp
          %f2 = trikeshed.fold %names, %acc : !sp, i64 -> i64 {
          ^bb0(%a2: i64, %part: !tp):
            %s32 = trikeshed.first %part : !tp -> i32
            %l32 = trikeshed.second %part : !tp -> i32
            %start = arith.index_castui %s32 : i32 to index
            %len = arith.index_castui %l32 : i32 to index
            %clean = arith.cmpi eq, %a2, %c0 : i64
            %some = arith.cmpi ne, %l32, %z32 : i32
            %go = arith.andi %clean, %some : i1
            %res = scf.if %go -> (i64) {
              // the entry's path, `path/name` and a NUL: one combine drained once
              %name = trikeshed.slice %page[%start, %len] : !s -> !s
              %all = trikeshed.combine %path, %slash, %name, %nul : !s, !s, !s, !s -> !s
              %sz = trikeshed.size %all : !s
              %sz64 = arith.index_cast %sz : index to i64
              %kp = func.call @nixfs_os_room(%sz64) : (i64) -> !llvm.ptr
              %into_d = func.call @fs_desc(%kp, %sz64) : (!llvm.ptr, i64) -> !d
              %into = builtin.unrealized_conversion_cast %into_d : !d to !m
              %end = trikeshed.drain %all, %into : !s, !m -> index
              %kn = arith.subi %sz64, %c1 : i64
              %x = func.call @nixstore_fs_delete(%kp, %kn, %err) : (!llvm.ptr, i64, !llvm.ptr) -> i64
              func.call @nixfs_os_done(%kp) : (!llvm.ptr) -> ()
              scf.yield %x : i64
            } else {
              scf.yield %a2 : i64
            }
            trikeshed.yield %res : i64
          }
          trikeshed.yield %f2 : i64
        }
        func.call @fs_freepages(%pages, %np, %c0) : (!llvm.ptr, i64, i64) -> ()
        scf.yield %failed : i64
      } else {
        scf.yield %c0 : i64
      }
      %kidsok = arith.cmpi eq, %kids, %c0 : i64
      %r2 = scf.if %kidsok -> (i64) {
        %rcr = func.call @rmdir(%cp) : (!llvm.ptr) -> i32
        %bad = arith.cmpi ne, %rcr, %z32 : i32
        %r3 = scf.if %bad -> (i64) {
          %e = func.call @nixfs_os_errno() : () -> i32
          %f = func.call @fs_fail(%err, %removing_o, %removing_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
          scf.yield %f : i64
        } else {
          scf.yield %c0 : i64
        }
        scf.yield %r3 : i64
      } else {
        scf.yield %kids : i64
      }
      scf.yield %r2 : i64
    } else {
      %rcu = func.call @unlink(%cp) : (!llvm.ptr) -> i32
      %bad = arith.cmpi ne, %rcu, %z32 : i32
      %r4 = scf.if %bad -> (i64) {
        %e = func.call @nixfs_os_errno() : () -> i32
        %f = func.call @fs_fail(%err, %removing_o, %removing_n, %cp, %n, %why_o, %why_n, %e) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
        scf.yield %f : i64
      } else {
        scf.yield %c0 : i64
      }
      scf.yield %r4 : i64
    }
    scf.yield %r1 : i64
  } else {
    scf.yield %c0 : i64
  }
  return %r : i64
}
