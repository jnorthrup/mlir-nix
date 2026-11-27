// The system's words for lowered/nixstore/StoreIndex.mlir, on Linux (the 64-bit layouts the kernel gives x86_64, aarch64
// and the other asm-generic machines; glibc and musl alike): what the C library does not give under one name and one
// layout everywhere.  Each word is held against the system's headers by the index's harness (StoreIndex.mlir).
//   nixsi_os_name      where a directory entry's name begins (struct dirent's d_name; its type is the byte before)
//   nixsi_os_atime     where a file's times begin in what stat fills (st_atim; the modification time is 16 bytes on,
//                      the change time 32); the file's number is the second word on every system
//   nixsi_os_anon      mmap's flags for memory of the process's own: MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
//   nixsi_os_open      a file opened, never kept across an exec (O_CLOEXEC): how 0 to read, 1 to read and write, 2 the
//                      same and made when it is not there, 3 written anew (made or cut); a file made is rw-r--r--
//   nixsi_os_fstat, nixsi_os_lstat, nixsi_os_opendir, nixsi_os_readdir   the calls whose records have these layouts
//   nixsi_os_local     what the file system of an open directory is trusted with: 1 (a file's number may be given to a
//                      later file: an entry is its number and its time) on ext2/3/4, XFS, btrfs, tmpfs, ZFS, F2FS,
//                      bcachefs and overlayfs, 0 anywhere else (no index is kept beside it)
//   nixsi_os_boot      this boot's name (/proc/sys/kernel/random/boot_id) into the cap bytes at buf: its bytes, 0 when
//                      there is none to read
module {
  llvm.func @open(!llvm.ptr, i32, ...) -> i32
  llvm.func @read(i32, !llvm.ptr, i64) -> i64
  llvm.func @close(i32) -> i32
  llvm.func @fstat(i32, !llvm.ptr) -> i32
  llvm.func @lstat(!llvm.ptr, !llvm.ptr) -> i32
  llvm.func @opendir(!llvm.ptr) -> !llvm.ptr
  llvm.func @readdir(!llvm.ptr) -> !llvm.ptr
  llvm.func @fstatfs(i32, !llvm.ptr) -> i32
  llvm.mlir.global internal constant @nixsi_os_bootname("/proc/sys/kernel/random/boot_id\00") : !llvm.array<32 x i8>

  llvm.func @nixsi_os_name() -> i64 {
    %c = llvm.mlir.constant(19 : i64) : i64
    llvm.return %c : i64
  }
  llvm.func @nixsi_os_atime() -> i64 {
    %c = llvm.mlir.constant(72 : i64) : i64
    llvm.return %c : i64
  }
  llvm.func @nixsi_os_anon() -> i64 {
    %c = llvm.mlir.constant(16418 : i64) : i64
    llvm.return %c : i64
  }
  llvm.func @nixsi_os_open(%path: !llvm.ptr, %how: i64) -> i32 {
    %c1 = llvm.mlir.constant(1 : i64) : i64
    %c2 = llvm.mlir.constant(2 : i64) : i64
    %c3 = llvm.mlir.constant(3 : i64) : i64
    // O_CLOEXEC 0x80000 with: O_RDONLY 0; O_RDWR 2; O_RDWR | O_CREAT 0x42; O_WRONLY | O_CREAT | O_TRUNC 0x241
    %f0 = llvm.mlir.constant(524288 : i32) : i32
    %f1 = llvm.mlir.constant(524290 : i32) : i32
    %f2 = llvm.mlir.constant(524354 : i32) : i32
    %f3 = llvm.mlir.constant(524865 : i32) : i32
    %mode = llvm.mlir.constant(420 : i32) : i32
    %is1 = llvm.icmp "eq" %how, %c1 : i64
    %is2 = llvm.icmp "eq" %how, %c2 : i64
    %is3 = llvm.icmp "eq" %how, %c3 : i64
    %a = llvm.select %is1, %f1, %f0 : i1, i32
    %b = llvm.select %is2, %f2, %a : i1, i32
    %c = llvm.select %is3, %f3, %b : i1, i32
    %fd = llvm.call @open(%path, %c, %mode) vararg(!llvm.func<i32 (ptr, i32, ...)>) : (!llvm.ptr, i32, i32) -> i32
    llvm.return %fd : i32
  }
  llvm.func @nixsi_os_fstat(%fd: i32, %buf: !llvm.ptr) -> i32 {
    %r = llvm.call @fstat(%fd, %buf) : (i32, !llvm.ptr) -> i32
    llvm.return %r : i32
  }
  llvm.func @nixsi_os_lstat(%path: !llvm.ptr, %buf: !llvm.ptr) -> i32 {
    %r = llvm.call @lstat(%path, %buf) : (!llvm.ptr, !llvm.ptr) -> i32
    llvm.return %r : i32
  }
  llvm.func @nixsi_os_opendir(%path: !llvm.ptr) -> !llvm.ptr {
    %r = llvm.call @opendir(%path) : (!llvm.ptr) -> !llvm.ptr
    llvm.return %r : !llvm.ptr
  }
  llvm.func @nixsi_os_readdir(%dir: !llvm.ptr) -> !llvm.ptr {
    %r = llvm.call @readdir(%dir) : (!llvm.ptr) -> !llvm.ptr
    llvm.return %r : !llvm.ptr
  }
  // struct statfs is 120 bytes and begins with f_type, a word: the file system's magic
  llvm.func @nixsi_os_local(%fd: i32) -> i64 {
    %n = llvm.mlir.constant(32 : i64) : i64
    %c0 = llvm.mlir.constant(0 : i64) : i64
    %c1 = llvm.mlir.constant(1 : i64) : i64
    %z32 = llvm.mlir.constant(0 : i32) : i32
    %ext = llvm.mlir.constant(61267 : i64) : i64
    %xfs = llvm.mlir.constant(1481003842 : i64) : i64
    %btrfs = llvm.mlir.constant(2435016766 : i64) : i64
    %tmpfs = llvm.mlir.constant(16914836 : i64) : i64
    %zfs = llvm.mlir.constant(801189825 : i64) : i64
    %f2fs = llvm.mlir.constant(4076150800 : i64) : i64
    %bcachefs = llvm.mlir.constant(3393526350 : i64) : i64
    %overlay = llvm.mlir.constant(2035054128 : i64) : i64
    %buf = llvm.alloca %n x i64 : (i64) -> !llvm.ptr
    %rc = llvm.call @fstatfs(%fd, %buf) : (i32, !llvm.ptr) -> i32
    %ok = llvm.icmp "eq" %rc, %z32 : i32
    llvm.cond_br %ok, ^read, ^none
  ^read:
    %type = llvm.load %buf : !llvm.ptr -> i64
    %t0 = llvm.icmp "eq" %type, %ext : i64
    %t1 = llvm.icmp "eq" %type, %xfs : i64
    %t2 = llvm.icmp "eq" %type, %btrfs : i64
    %t3 = llvm.icmp "eq" %type, %tmpfs : i64
    %t4 = llvm.icmp "eq" %type, %zfs : i64
    %t5 = llvm.icmp "eq" %type, %f2fs : i64
    %t6 = llvm.icmp "eq" %type, %bcachefs : i64
    %t7 = llvm.icmp "eq" %type, %overlay : i64
    %a = llvm.or %t0, %t1 : i1
    %b = llvm.or %a, %t2 : i1
    %c = llvm.or %b, %t3 : i1
    %d = llvm.or %c, %t4 : i1
    %e = llvm.or %d, %t5 : i1
    %f = llvm.or %e, %t6 : i1
    %g = llvm.or %f, %t7 : i1
    %r = llvm.select %g, %c1, %c0 : i1, i64
    llvm.return %r : i64
  ^none:
    llvm.return %c0 : i64
  }
  llvm.func @nixsi_os_boot(%buf: !llvm.ptr, %cap: i64) -> i64 {
    %c0 = llvm.mlir.constant(0 : i64) : i64
    %z32 = llvm.mlir.constant(0 : i32) : i32
    %flags = llvm.mlir.constant(524288 : i32) : i32
    %name = llvm.mlir.addressof @nixsi_os_bootname : !llvm.ptr
    %fd = llvm.call @open(%name, %flags) vararg(!llvm.func<i32 (ptr, i32, ...)>) : (!llvm.ptr, i32) -> i32
    %ok = llvm.icmp "sge" %fd, %z32 : i32
    llvm.cond_br %ok, ^read, ^none
  ^read:
    %n = llvm.call @read(%fd, %buf, %cap) : (i32, !llvm.ptr, i64) -> i64
    %rc = llvm.call @close(%fd) : (i32) -> i32
    %got = llvm.icmp "sgt" %n, %c0 : i64
    %r = llvm.select %got, %n, %c0 : i1, i64
    llvm.return %r : i64
  ^none:
    llvm.return %c0 : i64
  }
}
