// The store's files: lib/Store/StorePaths.cpp's readFile, writeFile, pathExists, createDirs and deletePathRecursive.
// The C++ keeps a forward each (the path made a C string, the message thrown); the system calls are made here, through
// the C library, and the errors are worded here, Nix's wording byte for byte.
//
//   nixstore_fs_read(path, n, out)                 a file's bytes into the Text at out, read where they stay: the Text
//                                                  is sized once to what the file says it holds (fstat), and again only
//                                                  when the file holds more or less than it said
//   nixstore_fs_write(path, n, data, dn, mode, err)  a file made (or cut) and written
//   nixstore_fs_exists(path)                       1 when lstat finds it (a dangling link is there)
//   nixstore_fs_mkdirs(path, n, err)               the directory and its parents made (dirOf, PathOps.mlir), a link to a
//                                                  directory taken for one
//   nixstore_fs_delete(path, n, err)               the tree at path removed: a directory's names are filled first
//                                                  (their bytes and each name's coordinates), then folded over, each
//                                                  entry's path one combine drained once, the first failure kept
//   nixstore_fs_note(kind, path)                   nixprefetch::note: a file access told to the recorder, when one records
//
// path is a C string (n its bytes: the forward's nixsys::CStr).  An entry that can fail answers 0, or 1 with the message
// in the Text at err (read: at out), which the forward throws; nothing made here outlives the call.  errno is read where
// the C++ read it (after the close for a failed write, before it for a failed read).  A file read or looked at is told
// to the recorder of file accesses when one records.  No op here allocates (the rooms are malloc's, named below: a
// module whose ops allocate cannot declare malloc and free as functions of its own).
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
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

memref.global "private" constant @fs_words : memref<112xi8> =
  dense<"0x6f70656e696e672066696c652027273a2072656164696e672066696c6520276372656174696e672066696c65202777726974696e672066696c65202727206973206e6f742061206469726563746f72796372656174696e67206469726563746f7279202772656d6f76696e6720272f00">

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
func.func private @malloc(i64) -> !llvm.ptr
func.func private @realloc(!llvm.ptr, i64) -> !llvm.ptr
func.func private @free(!llvm.ptr)
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
  %words_g = memref.get_global @fs_words : memref<112xi8>
  %words = trikeshed.text %words_g : memref<112xi8> -> !s
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

func.func @nixstore_fs_read(%cp: !llvm.ptr, %n: i64, %out: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c20 = arith.constant 20 : i64
  %c65536 = arith.constant 65536 : i64
  %most = arith.constant 4294967294 : i64
  %z32 = arith.constant 0 : i32
  %kF = arith.constant 70 : i32
  %regular = arith.constant 32768 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %reading_o = arith.constant 17 : index  // "reading file '"
  %reading_n = arith.constant 14 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i8 : (i64) -> !llvm.ptr
  func.call @nixstore_fs_note(%kF, %cp) : (i32, !llvm.ptr) -> ()
  %fd = func.call @nixsi_os_open(%cp, %c0) : (!llvm.ptr, i64) -> i32
  %opened = arith.cmpi sge, %fd, %z32 : i32
  %r = scf.if %opened -> (i64) {
    // what a regular file says it holds: the Text is sized to it once and the bytes are read where they stay
    %rc = func.call @nixsi_os_fstat(%fd, %st) : (i32, !llvm.ptr) -> i32
    %kind = func.call @fs_kind(%st) : (!llvm.ptr) -> i32
    %size = func.call @nixfs_os_size(%st) : (!llvm.ptr) -> i64
    %stok = arith.cmpi eq, %rc, %z32 : i32
    %reg = arith.cmpi eq, %kind, %regular : i32
    %some = arith.cmpi sgt, %size, %c0 : i64
    %k0 = arith.andi %stok, %reg : i1
    %known = arith.andi %k0, %some : i1
    %want0 = arith.select %known, %size, %c0 : i64
    %p0 = scf.if %known -> (!llvm.ptr) {
      %q = func.call @nixstore_text_sized(%out, %size) : (!llvm.ptr, i64) -> !llvm.ptr
      scf.yield %q : !llvm.ptr
    } else {
      scf.yield %null : !llvm.ptr
    }
    %pb0 = llvm.ptrtoint %p0 : !llvm.ptr to i64
    // state 0 reading, 1 the file's end, 2 a read failed (e what the system said)
    %pe, %we, %te, %se, %ee = scf.while (%p = %pb0, %want = %want0, %total = %c0, %state = %c0, %e = %z32) : (i64, i64, i64, i64, i32) -> (i64, i64, i64, i64, i32) {
      %go = arith.cmpi eq, %state, %c0 : i64
      scf.condition(%go) %p, %want, %total, %state, %e : i64, i64, i64, i64, i32
    } do {
    ^bb0(%pa: i64, %wa: i64, %ta: i64, %sa: i64, %ea: i32):
      %full = arith.cmpi eq, %ta, %wa : i64
      %pn, %wn, %tn, %sn, %en = scf.if %full -> (i64, i64, i64, i64, i32) {
        // the room is used up: one byte more says whether the file ends here; when it does not, the room doubles
        // (64 KiB at least, and to a Text's most before past it)
        %k = func.call @read(%fd, %cell, %c1) : (i32, !llvm.ptr, i64) -> i64
        %neg = arith.cmpi slt, %k, %c0 : i64
        %x1, %x2, %x3, %x4, %x5 = scf.if %neg -> (i64, i64, i64, i64, i32) {
          %er = func.call @nixfs_os_errno() : () -> i32
          scf.yield %pa, %wa, %ta, %c2, %er : i64, i64, i64, i64, i32
        } else {
          %end = arith.cmpi eq, %k, %c0 : i64
          %y1, %y2, %y3, %y4 = scf.if %end -> (i64, i64, i64, i64) {
            scf.yield %pa, %wa, %ta, %c1 : i64, i64, i64, i64
          } else {
            %tw = arith.muli %wa, %c2 : i64
            %w1 = arith.maxsi %tw, %c65536 : i64
            %over = arith.cmpi sgt, %w1, %most : i64
            %under = arith.cmpi slt, %wa, %most : i64
            %clamp = arith.andi %over, %under : i1
            %w2 = arith.select %clamp, %most, %w1 : i64
            %q2 = func.call @nixstore_text_sized(%out, %w2) : (!llvm.ptr, i64) -> !llvm.ptr
            %at = llvm.getelementptr %q2[%ta] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %byte = llvm.load %cell : !llvm.ptr -> i8
            llvm.store %byte, %at : i8, !llvm.ptr
            %t2 = arith.addi %ta, %c1 : i64
            %q2b = llvm.ptrtoint %q2 : !llvm.ptr to i64
            scf.yield %q2b, %w2, %t2, %c0 : i64, i64, i64, i64
          }
          scf.yield %y1, %y2, %y3, %y4, %ea : i64, i64, i64, i64, i32
        }
        scf.yield %x1, %x2, %x3, %x4, %x5 : i64, i64, i64, i64, i32
      } else {
        %base = llvm.inttoptr %pa : i64 to !llvm.ptr
        %at = llvm.getelementptr %base[%ta] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %left = arith.subi %wa, %ta : i64
        %k = func.call @read(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
        %neg = arith.cmpi slt, %k, %c0 : i64
        %end = arith.cmpi eq, %k, %c0 : i64
        %er = scf.if %neg -> (i32) {
          %e1 = func.call @nixfs_os_errno() : () -> i32
          scf.yield %e1 : i32
        } else {
          scf.yield %ea : i32
        }
        %t2 = arith.addi %ta, %k : i64
        %t3 = arith.select %neg, %ta, %t2 : i64
        %s1 = arith.select %end, %c1, %c0 : i64
        %s2 = arith.select %neg, %c2, %s1 : i64
        scf.yield %pa, %wa, %t3, %s2, %er : i64, i64, i64, i64, i32
      }
      scf.yield %pn, %wn, %tn, %sn, %en : i64, i64, i64, i64, i32
    }
    %rcc = func.call @close(%fd) : (i32) -> i32
    %failed = arith.cmpi eq, %se, %c2 : i64
    %res = scf.if %failed -> (i64) {
      %f = func.call @fs_fail(%out, %reading_o, %reading_n, %cp, %n, %why_o, %why_n, %ee) : (!llvm.ptr, index, index, !llvm.ptr, i64, index, index, i32) -> i64
      scf.yield %f : i64
    } else {
      // the Text is the bytes read: cut where the file held fewer than the room
      %cut = arith.cmpi ne, %te, %we : i64
      scf.if %cut {
        %q3 = func.call @nixstore_text_sized(%out, %te) : (!llvm.ptr, i64) -> !llvm.ptr
      }
      scf.yield %c0 : i64
    }
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

func.func @nixstore_fs_write(%cp: !llvm.ptr, %n: i64, %data: !llvm.ptr, %dn: i64, %mode: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
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
    // state 0 writing, 2 a write failed
    %oe, %se = scf.while (%off = %c0, %state = %c0) : (i64, i64) -> (i64, i64) {
      %more = arith.cmpi ult, %off, %dn : i64
      %fine = arith.cmpi eq, %state, %c0 : i64
      %go = arith.andi %more, %fine : i1
      scf.condition(%go) %off, %state : i64, i64
    } do {
    ^bb0(%oa: i64, %sa: i64):
      %at = llvm.getelementptr %data[%oa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %left = arith.subi %dn, %oa : i64
      %k = func.call @write(%fd, %at, %left) : (i32, !llvm.ptr, i64) -> i64
      %neg = arith.cmpi slt, %k, %c0 : i64
      %o2 = arith.addi %oa, %k : i64
      %on = arith.select %neg, %oa, %o2 : i64
      %sn = arith.select %neg, %c2, %c0 : i64
      scf.yield %on, %sn : i64, i64
    }
    %rcc = func.call @close(%fd) : (i32) -> i32
    %failed = arith.cmpi eq, %se, %c2 : i64
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
  %z8 = arith.constant 0 : i8
  %slash = arith.constant 47 : i8
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
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
  %empty = arith.cmpi eq, %n, %c0 : i64
  %one = arith.cmpi eq, %n, %c1 : i64
  %b0 = scf.if %one -> (i8) {
    %x = llvm.load %cp : !llvm.ptr -> i8
    scf.yield %x : i8
  } else {
    scf.yield %z8 : i8
  }
  %isslash = arith.cmpi eq, %b0, %slash : i8
  %root = arith.andi %one, %isslash : i1
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
      // the parent first (dirOf), then this one; another's making it meanwhile is no failure
      %room = arith.addi %n, %c2 : i64
      %dp = func.call @malloc(%room) : (i64) -> !llvm.ptr
      %dn = func.call @nixstore_ts_dirname(%cp, %n, %dp) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      %dend = llvm.getelementptr %dp[%dn] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      llvm.store %z8, %dend : i8, !llvm.ptr
      %up = func.call @nixstore_fs_mkdirs(%dp, %dn, %err) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      func.call @free(%dp) : (!llvm.ptr) -> ()
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

// room for `need` cells of `width` bytes at the block p (cap cells now; what it holds is kept): the block and its cells
func.func private @fs_grow(%p: i64, %cap: i64, %need: i64, %width: i64) -> (i64, i64) {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %c64 = arith.constant 64 : i64
  %enough = arith.cmpi sge, %cap, %need : i64
  %rp, %rc = scf.if %enough -> (i64, i64) {
    scf.yield %p, %cap : i64, i64
  } else {
    %twice = arith.muli %cap, %c2 : i64
    %w0 = arith.maxsi %need, %twice : i64
    %want = arith.maxsi %w0, %c64 : i64
    %bytes = arith.muli %want, %width : i64
    %old = llvm.inttoptr %p : i64 to !llvm.ptr
    %new = func.call @realloc(%old, %bytes) : (!llvm.ptr, i64) -> !llvm.ptr
    %nb = llvm.ptrtoint %new : !llvm.ptr to i64
    %gone = arith.cmpi eq, %nb, %c0 : i64
    scf.if %gone {
      func.call @abort() : () -> ()
    }
    scf.yield %nb, %want : i64, i64
  }
  return %rp, %rc : i64, i64
}

// The names an open directory gives, but for "." and "..", in the order it gives them: their bytes one after another,
// and each name's coordinates (start << 32 | length).  A fill: the two blocks grow by doubling and are the caller's to free.
func.func private @fs_list(%dir: !llvm.ptr) -> (!llvm.ptr, !llvm.ptr, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c8 = arith.constant 8 : i64
  %c32 = arith.constant 32 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %dot = arith.constant 46 : i8
  %nob = arith.constant 0 : i8
  %noff = func.call @nixsi_os_name() : () -> i64
  %e0 = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
  %e0b = llvm.ptrtoint %e0 : !llvm.ptr to i64
  %ee, %be, %bce, %ue, %ce, %cce, %ke = scf.while (%e = %e0b, %b = %c0, %bcap = %c0, %used = %c0, %c = %c0, %ccap = %c0, %k = %c0) : (i64, i64, i64, i64, i64, i64, i64) -> (i64, i64, i64, i64, i64, i64, i64) {
    %more = arith.cmpi ne, %e, %c0 : i64
    scf.condition(%more) %e, %b, %bcap, %used, %c, %ccap, %k : i64, i64, i64, i64, i64, i64, i64
  } do {
  ^bb0(%ea: i64, %ba: i64, %bca: i64, %ua: i64, %ca: i64, %cca: i64, %ka: i64):
    %ep = llvm.inttoptr %ea : i64 to !llvm.ptr
    %np = llvm.getelementptr %ep[%noff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %nn = func.call @strlen(%np) : (!llvm.ptr) -> i64
    %name_d = func.call @fs_desc(%np, %nn) : (!llvm.ptr, i64) -> !d
    %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
    %name = builtin.unrealized_conversion_cast %name_m : !m to !s
    %has1 = arith.cmpi sge, %nn, %c1 : i64
    %b0 = scf.if %has1 -> (i8) {
      %x0 = trikeshed.at %name[%z] : !s, index -> i8
      scf.yield %x0 : i8
    } else {
      scf.yield %nob : i8
    }
    %has2 = arith.cmpi sge, %nn, %c2 : i64
    %b1 = scf.if %has2 -> (i8) {
      %x1 = trikeshed.at %name[%i1] : !s, index -> i8
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
    %bn, %bcn, %un, %cn, %ccn, %kn = scf.if %skip -> (i64, i64, i64, i64, i64, i64) {
      scf.yield %ba, %bca, %ua, %ca, %cca, %ka : i64, i64, i64, i64, i64, i64
    } else {
      %u2 = arith.addi %ua, %nn : i64
      %k2 = arith.addi %ka, %c1 : i64
      %b2, %bc2 = func.call @fs_grow(%ba, %bca, %u2, %c1) : (i64, i64, i64, i64) -> (i64, i64)
      %c2x, %cc2 = func.call @fs_grow(%ca, %cca, %k2, %c8) : (i64, i64, i64, i64) -> (i64, i64)
      %bp = llvm.inttoptr %b2 : i64 to !llvm.ptr
      %at = llvm.getelementptr %bp[%ua] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %into_d = func.call @fs_desc(%at, %nn) : (!llvm.ptr, i64) -> !d
      %into = builtin.unrealized_conversion_cast %into_d : !d to !m
      %end = trikeshed.drain %name, %into : !s, !m -> index
      %cpp = llvm.inttoptr %c2x : i64 to !llvm.ptr
      %cells_d = func.call @fs_desc(%cpp, %k2) : (!llvm.ptr, i64) -> !d
      %cells = builtin.unrealized_conversion_cast %cells_d : !d to !m64
      %hi = arith.shli %ua, %c32 : i64
      %co = arith.ori %hi, %nn : i64
      %ki = arith.index_cast %ka : i64 to index
      memref.store %co, %cells[%ki] : !m64
      scf.yield %b2, %bc2, %u2, %c2x, %cc2, %k2 : i64, i64, i64, i64, i64, i64
    }
    %en = func.call @nixsi_os_readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
    %enb = llvm.ptrtoint %en : !llvm.ptr to i64
    scf.yield %enb, %bn, %bcn, %un, %cn, %ccn, %kn : i64, i64, i64, i64, i64, i64, i64
  }
  %names = llvm.inttoptr %be : i64 to !llvm.ptr
  %coords = llvm.inttoptr %ce : i64 to !llvm.ptr
  return %names, %coords, %ke : !llvm.ptr, !llvm.ptr, i64
}

func.func @nixstore_fs_delete(%cp: !llvm.ptr, %n: i64, %err: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %low = arith.constant 4294967295 : i64
  %z32 = arith.constant 0 : i32
  %directory = arith.constant 16384 : i32
  %mine = arith.constant 448 : i32
  %removing_o = arith.constant 100 : index  // "removing '"
  %removing_n = arith.constant 10 : index
  %why_o = arith.constant 14 : index  // "': "
  %why_n = arith.constant 3 : index
  %words_g = memref.get_global @fs_words : memref<112xi8>
  %words = trikeshed.text %words_g : memref<112xi8> -> !s
  %slash_o = arith.constant 110 : index  // "/"
  %slash_n = arith.constant 1 : index
  %slash = trikeshed.slice %words[%slash_o, %slash_n] : !s -> !s
  %nul_o = arith.constant 111 : index  // "\u0000"
  %nul_n = arith.constant 1 : index
  %nul = trikeshed.slice %words[%nul_o, %nul_n] : !s -> !s
  %st = llvm.alloca %c20 x i64 : (i64) -> !llvm.ptr
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
        // that keeps the first failure and removes nothing after it
        %names, %coords, %count = func.call @fs_list(%dir) : (!llvm.ptr) -> (!llvm.ptr, !llvm.ptr, i64)
        %rcd = func.call @closedir(%dir) : (!llvm.ptr) -> i32
        %path_d = func.call @fs_desc(%cp, %n) : (!llvm.ptr, i64) -> !d
        %path_m = builtin.unrealized_conversion_cast %path_d : !d to !m
        %path = builtin.unrealized_conversion_cast %path_m : !m to !s
        %cs_d = func.call @fs_desc(%coords, %count) : (!llvm.ptr, i64) -> !d
        %cs_m = builtin.unrealized_conversion_cast %cs_d : !d to !m64
        %cs = builtin.unrealized_conversion_cast %cs_m : !m64 to !s64
        %failed = trikeshed.fold %cs, %c0 : !s64, i64 -> i64 {
        ^bb0(%acc: i64, %co: i64):
          %clean = arith.cmpi eq, %acc, %c0 : i64
          %res = scf.if %clean -> (i64) {
            // the entry's path, `path/name` and a NUL: one combine drained once
            %start = arith.shrui %co, %c32 : i64
            %len = arith.andi %co, %low : i64
            %np = llvm.getelementptr %names[%start] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %name_d = func.call @fs_desc(%np, %len) : (!llvm.ptr, i64) -> !d
            %name_m = builtin.unrealized_conversion_cast %name_d : !d to !m
            %name = builtin.unrealized_conversion_cast %name_m : !m to !s
            %all = trikeshed.combine %path, %slash, %name, %nul : !s, !s, !s, !s -> !s
            %sz = trikeshed.size %all : !s
            %sz64 = arith.index_cast %sz : index to i64
            %kp = func.call @malloc(%sz64) : (i64) -> !llvm.ptr
            %into_d = func.call @fs_desc(%kp, %sz64) : (!llvm.ptr, i64) -> !d
            %into = builtin.unrealized_conversion_cast %into_d : !d to !m
            %end = trikeshed.drain %all, %into : !s, !m -> index
            %kn = arith.subi %sz64, %c1 : i64
            %x = func.call @nixstore_fs_delete(%kp, %kn, %err) : (!llvm.ptr, i64, !llvm.ptr) -> i64
            func.call @free(%kp) : (!llvm.ptr) -> ()
            scf.yield %x : i64
          } else {
            scf.yield %acc : i64
          }
          trikeshed.yield %res : i64
        }
        func.call @free(%names) : (!llvm.ptr) -> ()
        func.call @free(%coords) : (!llvm.ptr) -> ()
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
