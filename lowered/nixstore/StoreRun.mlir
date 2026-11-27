// The processes of the store's build path (lib/Store/LocalStore.cpp's runBuilder and builtinFetchurl and
// lib/Store/StorePaths.cpp's runProgram are gone; LocalStore.cpp names these entries and keeps the error one returns
// with).
//
//   nixsb_run     runProgram: a program run to its end with the caller's arguments, its standard output read into a
//                 Text, its standard input a Text's bytes or /dev/null, in a directory of the caller's choosing.  Its
//                 exit code, or 128 and the signal that ended it; -1 with the error said when no process could be made.
//   nixsb_build   runBuilder: a derivation's builder run in a directory of its own with the environment Nix gives it.
//                 The environment is a fill of (name, value) rows in the order they are set (Nix's, the store's
//                 directory and the build's, the variables a fixed-output derivation lets in, the derivation's own with
//                 the outputs' placeholders rewritten, the structured attributes' two files), drained once in name order
//                 with the last of equal names kept (sorted, where, one combineAll of the kept rows), then one room of
//                 `name=value` strings (BuilderOps.mlir's cstrs); the arguments likewise.  The builder's end decides:
//                 its directory removed, or its outputs removed and the failure said.
//   nixsb_fetch   builtin:fetchurl: the derivation's url (or the first of its urls) fetched by curl into the output's
//                 path, unpacked as a NAR or made executable when the derivation says so.
//
// A derivation and the outputs' paths are read where they lie: a Text is a pointer and 32 bits of length (16 bytes), a
// SortedMap<Text> row two of them, a series a pointer and a count; LocalStore.cpp holds each place read here against the
// headers.  The constant texts are one blob (store-lits.py, kept with the module's proofs, writes it and their places).
// What the store does for a builder that is not a system's call is a callback that does not throw: the placeholders'
// rewrite, the structured attributes' files, readFile, writeFile, createDirs, deletePathRecursive, restorePath.
// The system's words (errno, /dev/null, waitpid's status, the allocator) are StoreBuildDarwin.mlir.in /
// StoreBuildLinux.mlir.in; an error is said once (StoreWords.mlir) and every room is given back before the entry returns.
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!tp = !trikeshed.twinpacked<i32>
!pieces = !trikeshed.series<!tp>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// lits @sbr_lits
memref.global "private" constant @sbr_lits : memref<364xi8> =
  dense<"0x06544d5044495200042f746d70000b2f6e69782d6275696c642d00072d585858585858000450415448000d2f706174682d6e6f742d7365740004484f4d4500112f686f6d656c6573732d7368656c74657200094e49585f53544f5245000f4e49585f4255494c445f434f524553000d4e49585f4255494c445f544f50000754454d504449520003544d50000454454d500003505744000a4e49585f4c4f475f464400013200045445524d000e787465726d2d323536636f6c6f72001244594c445f5348415245445f524547494f4e000d696d70757265456e765661727300036f7574000c2f2e61747472732e6a736f6e000a2f2e61747472732e736800134e49585f41545452535f4a534f4e5f46494c4500114e49585f41545452535f53485f46494c450000000375726c000475726c7300042e746d7000046375726c00052d6673534c00072d2d726574727900013300022d6f0006756e7061636b000a65786563757461626c6500013100">
memref.global "private" constant @sbr_zero : memref<16xi64> = dense<0>

// the C library: what is the same wherever mlnix is built
func.func private @pipe(!llvm.ptr) -> i32
func.func private @fork() -> i32
func.func private @chdir(!llvm.ptr) -> i32
func.func private @dup2(i32, i32) -> i32
func.func private @close(i32) -> i32
func.func private @read(i32, !llvm.ptr, i64) -> i64
func.func private @write(i32, !llvm.ptr, i64) -> i64
func.func private @waitpid(i32, !llvm.ptr, i32) -> i32
func.func private @execvp(!llvm.ptr, !llvm.ptr) -> i32
func.func private @execve(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
func.func private @_exit(i32)
func.func private @setsid() -> i32
func.func private @getenv(!llvm.ptr) -> !llvm.ptr
func.func private @mkdtemp(!llvm.ptr) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @unlink(!llvm.ptr) -> i32
func.func private @rename(!llvm.ptr, !llvm.ptr) -> i32
func.func private @chmod(!llvm.ptr, i32) -> i32
func.func private @abort()
// the system's words (StoreBuildDarwin.mlir.in, StoreBuildLinux.mlir.in)
func.func private @nixsb_os_errno() -> i64
func.func private @nixsb_os_devnull() -> i32
func.func private @nixsb_os_wait(i64) -> i64
func.func private @nixsb_os_grow(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_os_free(!llvm.ptr)
// the store's words (StoreWords.mlir): 16 creating build directory, 17 fork failed, 18 failed with exit code, 19 killed
// by signal, 20 keeping build directory, 21 executing, 22 no URL, 23 curl exited, 24 pipe failed, 27 no entry
func.func private @nixsb_say(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
// the store's (lib/Store/LocalStore.cpp), none of which throws: bytes put at a Text's end; a string with the outputs'
// placeholders rewritten (its bytes, their count at the last argument); an output's placeholder noted; the structured
// attributes' two files made (their bytes and counts at the last argument: four words); writeFile, deletePathRecursive,
// createDirs and restorePath (1 when they failed); pathExists; readFile (its bytes, -1 at the last argument when it failed)
func.func private @nixsb_put(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixsb_rewrite(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_placeholder(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64)
func.func private @nixsb_sattrs(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_write(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
func.func private @nixsb_delete(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_mkdirs(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_restore(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixsb_exists(!llvm.ptr, i64) -> i64
func.func private @nixsb_read(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
// runProgram's argument pointers (StorePathOps.mlir), a room of NUL-ended strings and their pointers (BuilderOps.mlir),
// baseNameOf (PathOps.mlir), a sorted row by its key (SortedRows.mlir)
func.func private @nixstore_ts_argv(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_cstrs(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_basename(!llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_rowfind(!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64

//===----------------------------------------------------------------------===//
// Words, texts, rooms
//===----------------------------------------------------------------------===//

// the descriptor of n cells at p
func.func private @sbr_d(%p: !llvm.ptr, %n: i64) -> !d {
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

// word i of the words at p, read and written
func.func private @sbr_w(%p: !llvm.ptr, %i: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %n = arith.addi %i, %c1 : i64
  %pd = func.call @sbr_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m64
  %ps = builtin.unrealized_conversion_cast %pm : !m64 to !s64
  %ii = arith.index_cast %i : i64 to index
  %v = trikeshed.at %ps[%ii] : !s64, index -> i64
  return %v : i64
}
func.func private @sbr_ws(%p: !llvm.ptr, %i: i64, %v: i64) {
  %c1 = arith.constant 1 : i64
  %n = arith.addi %i, %c1 : i64
  %pd = func.call @sbr_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m64
  %ii = arith.index_cast %i : i64 to index
  memref.store %v, %pm[%ii] : !m64
  return
}

// the constant text at `off` of the blob (a length byte, then its bytes and a NUL): its bytes and its length
func.func private @sbr_lit(%off: i64) -> (!llvm.ptr, i64) {
  %c1 = arith.constant 1 : i64
  %g = memref.get_global @sbr_lits : memref<364xi8> // lits
  %lits = trikeshed.text %g : memref<364xi8> -> !s // lits
  %oi = arith.index_cast %off : i64 to index
  %n8 = trikeshed.at %lits[%oi] : !s, index -> i8
  %n = arith.extui %n8 : i8 to i64
  %bi = memref.extract_aligned_pointer_as_index %g : memref<364xi8> -> index // lits
  %b64 = arith.index_cast %bi : index to i64
  %base = llvm.inttoptr %b64 : i64 to !llvm.ptr
  %o1 = arith.addi %off, %c1 : i64
  %p = llvm.getelementptr %base[%o1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p, %n : !llvm.ptr, i64
}

// the Text at t (a pointer, then 32 bits of length): its bytes and its length; a Text that never held a byte has none
func.func private @sbr_text(%t: !llvm.ptr) -> (!llvm.ptr, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %low32 = arith.constant 4294967295 : i64
  %pb = func.call @sbr_w(%t, %c0) : (!llvm.ptr, i64) -> i64
  %nw = func.call @sbr_w(%t, %c1) : (!llvm.ptr, i64) -> i64
  %n = arith.andi %nw, %low32 : i64
  %p = llvm.inttoptr %pb : i64 to !llvm.ptr
  return %p, %n : !llvm.ptr, i64
}

// a room of n bytes, the caller's to give back
func.func private @sbr_room(%n: i64) -> !llvm.ptr {
  %c0 = arith.constant 0 : i64
  %c8 = arith.constant 8 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %want = arith.maxsi %n, %c8 : i64
  %p = func.call @nixsb_os_grow(%null, %want) : (!llvm.ptr, i64) -> !llvm.ptr
  %pb = llvm.ptrtoint %p : !llvm.ptr to i64
  %none = arith.cmpi eq, %pb, %c0 : i64
  scf.if %none {
    func.call @abort() : () -> ()
  }
  return %p : !llvm.ptr
}

// Four texts one after another and a NUL, in a room of their own: one combine drained once.  The room and the bytes
// before the NUL.
func.func private @sbr_cat(%ap: !llvm.ptr, %an: i64, %bp: !llvm.ptr, %bn: i64, %cp: !llvm.ptr, %cn: i64,
                           %dp: !llvm.ptr, %dn: i64) -> (!llvm.ptr, i64) {
  %c1 = arith.constant 1 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %n0 = arith.addi %an, %bn : i64
  %n1 = arith.addi %n0, %cn : i64
  %n = arith.addi %n1, %dn : i64
  %cap = arith.addi %n, %c1 : i64
  %room = func.call @sbr_room(%cap) : (i64) -> !llvm.ptr
  %a_d = func.call @sbr_d(%ap, %an) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sbr_d(%bp, %bn) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c_d = func.call @sbr_d(%cp, %cn) : (!llvm.ptr, i64) -> !d
  %c_m = builtin.unrealized_conversion_cast %c_d : !d to !m
  %c = builtin.unrealized_conversion_cast %c_m : !m to !s
  %d_d = func.call @sbr_d(%dp, %dn) : (!llvm.ptr, i64) -> !d
  %d_m = builtin.unrealized_conversion_cast %d_d : !d to !m
  %dd = builtin.unrealized_conversion_cast %d_m : !m to !s
  %zg = memref.get_global @sbr_zero : memref<16xi64>
  %zi = memref.extract_aligned_pointer_as_index %zg : memref<16xi64> -> index
  %z64 = arith.index_cast %zi : index to i64
  %zp = llvm.inttoptr %z64 : i64 to !llvm.ptr
  %z_d = func.call @sbr_d(%zp, %c1) : (!llvm.ptr, i64) -> !d
  %z_m = builtin.unrealized_conversion_cast %z_d : !d to !m
  %nul = builtin.unrealized_conversion_cast %z_m : !m to !s
  %all = trikeshed.combine %a, %b, %c, %dd, %nul : !s, !s, !s, !s, !s -> !s
  %rd = func.call @sbr_d(%room, %cap) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %end = trikeshed.drain %all, %rm : !s, !m -> index
  return %room, %n : !llvm.ptr, i64
}

// the 16 rooms a call holds (a handle of words on its entry's stack): none at first, all given back at its end
func.func private @sbr_open(%h: !llvm.ptr) {
  %c16 = arith.constant 16 : i64
  %zg = memref.get_global @sbr_zero : memref<16xi64>
  %zeros = trikeshed.text %zg : memref<16xi64> -> !s64
  %hd = func.call @sbr_d(%h, %c16) : (!llvm.ptr, i64) -> !d
  %hm = builtin.unrealized_conversion_cast %hd : !d to !m64
  %e = trikeshed.drain %zeros, %hm : !s64, !m64 -> index
  return
}
func.func private @sbr_close(%h: !llvm.ptr) {
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %i16 = arith.constant 16 : index
  scf.for %i = %z to %i16 step %i1 {
    %i64 = arith.index_cast %i : index to i64
    %pb = func.call @sbr_w(%h, %i64) : (!llvm.ptr, i64) -> i64
    %p = llvm.inttoptr %pb : i64 to !llvm.ptr
    func.call @nixsb_os_free(%p) : (!llvm.ptr) -> ()
  }
  return
}
// room p kept as the handle's i-th
func.func private @sbr_keep(%h: !llvm.ptr, %i: i64, %p: !llvm.ptr) {
  %pb = llvm.ptrtoint %p : !llvm.ptr to i64
  func.call @sbr_ws(%h, %i, %pb) : (!llvm.ptr, i64, i64) -> ()
  return
}

// Whether byte i of the n bytes at p is one a word ends at (' ', or \t to \r), as a stream's >> splits; none past n.
func.func private @sbr_space(%p: !llvm.ptr, %n: i64, %i: i64) -> i1 {
  %sp = arith.constant 32 : i8
  %tab = arith.constant 9 : i8
  %cr = arith.constant 13 : i8
  %in = arith.cmpi slt, %i, %n : i64
  %r = scf.if %in -> (i1) {
    %t_d = func.call @sbr_d(%p, %n) : (!llvm.ptr, i64) -> !d
    %t_m = builtin.unrealized_conversion_cast %t_d : !d to !m
    %text = builtin.unrealized_conversion_cast %t_m : !m to !s
    %ii = arith.index_cast %i : i64 to index
    %ch = trikeshed.at %text[%ii] : !s, index -> i8
    %is = arith.cmpi eq, %ch, %sp : i8
    %ge = arith.cmpi uge, %ch, %tab : i8
    %le = arith.cmpi ule, %ch, %cr : i8
    %ctl = arith.andi %ge, %le : i1
    %sp1 = arith.ori %is, %ctl : i1
    scf.yield %sp1 : i1
  } else {
    %no = arith.constant 0 : i1
    scf.yield %no : i1
  }
  return %r : i1
}
// The word of the n bytes at p that begins at or after k: where it begins and where it ends; it begins at n when there
// is none.
func.func private @sbr_word(%p: !llvm.ptr, %n: i64, %k: i64) -> (i64, i64) {
  %c1 = arith.constant 1 : i64
  %b = scf.while (%i = %k) : (i64) -> (i64) {
    %sp = func.call @sbr_space(%p, %n, %i) : (!llvm.ptr, i64, i64) -> i1
    scf.condition(%sp) %i : i64
  } do {
  ^bb0(%ia: i64):
    %i1 = arith.addi %ia, %c1 : i64
    scf.yield %i1 : i64
  }
  %e = scf.while (%j = %b) : (i64) -> (i64) {
    %in = arith.cmpi slt, %j, %n : i64
    %sp2 = func.call @sbr_space(%p, %n, %j) : (!llvm.ptr, i64, i64) -> i1
    %t = arith.constant 1 : i1
    %ns = arith.xori %sp2, %t : i1
    %go = arith.andi %in, %ns : i1
    scf.condition(%go) %j : i64
  } do {
  ^bb0(%ja: i64):
    %j1 = arith.addi %ja, %c1 : i64
    scf.yield %j1 : i64
  }
  return %b, %e : i64, i64
}

// whether the n bytes at p are the constant text at off
func.func private @sbr_is(%p: !llvm.ptr, %n: i64, %off: i64) -> i1 {
  %z32 = arith.constant 0 : i32
  %lp, %ln = func.call @sbr_lit(%off) : (i64) -> (!llvm.ptr, i64)
  %a_d = func.call @sbr_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sbr_d(%lp, %ln) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c = trikeshed.compare %a, %b unsigned : !s, !s
  %same = arith.cmpi eq, %c, %z32 : i32
  return %same : i1
}

// The value of the constant name at off in a map of Texts (its rows at the map's first word, their count the 32 bits
// after): its bytes and length; none when the map has no such name (`found` 0).
func.func private @sbr_get(%map: !llvm.ptr, %off: i64) -> (!llvm.ptr, i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %rows, %n = func.call @sbr_text(%map) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %kp, %kn = func.call @sbr_lit(%off) : (i64) -> (!llvm.ptr, i64)
  %i = func.call @nixstore_ts_rowfind(%rows, %n, %c32, %kp, %kn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %has = arith.cmpi sge, %i, %c0 : i64
  %vp, %vn, %f = scf.if %has -> (!llvm.ptr, i64, i64) {
    %ro = arith.muli %i, %c32 : i64
    %vo = arith.addi %ro, %c16 : i64
    %vt = llvm.getelementptr %rows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %p, %pn = func.call @sbr_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    scf.yield %p, %pn, %c1 : !llvm.ptr, i64, i64
  } else {
    scf.yield %rows, %c0, %c0 : !llvm.ptr, i64, i64
  }
  return %vp, %vn, %f : !llvm.ptr, i64, i64
}

//===----------------------------------------------------------------------===//
// runProgram
//===----------------------------------------------------------------------===//

// prog, args (n Text rows), out (a Text, or null: what the program writes is read and dropped), input (a Text, or null:
// the program reads /dev/null), cwd (empty: the caller's).  The strings the child needs are made before the fork: the
// program's name and the directory with their NULs (one combine drained once) and the room of the argument pointers.
func.func @nixsb_run(%c: !llvm.ptr, %prog: !llvm.ptr, %pn: i64, %args: !llvm.ptr, %na: i64, %out: !llvm.ptr,
                     %input: !llvm.ptr, %cwd: !llvm.ptr, %cn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c8 = arith.constant 8 : i64
  %c17 = arith.constant 17 : i64
  %c24 = arith.constant 24 : i64
  %c128 = arith.constant 128 : i64
  %c255 = arith.constant 255 : i64
  %c256 = arith.constant 256 : i64
  %c65536 = arith.constant 65536 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %one32 = arith.constant 1 : i32
  %x127 = arith.constant 127 : i32
  %pipes = llvm.alloca %c4 x i32 : (i64) -> !llvm.ptr
  %status = llvm.alloca %c1 x i32 : (i64) -> !llvm.ptr
  %buf = llvm.alloca %c65536 x i8 : (i64) -> !llvm.ptr
  %inpipe = llvm.getelementptr %pipes[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %ib = llvm.ptrtoint %input : !llvm.ptr to i64
  %hasin = arith.cmpi ne, %ib, %c0 : i64
  %ob = llvm.ptrtoint %out : !llvm.ptr to i64
  %hasout = arith.cmpi ne, %ob, %c0 : i64
  %rc1 = func.call @pipe(%pipes) : (!llvm.ptr) -> i32
  %bad1 = arith.cmpi ne, %rc1, %z32 : i32
  %res = scf.if %bad1 -> (i64) {
    %said = func.call @nixsb_say(%c, %c0, %c24, %prog, %c0, %prog, %c0, %prog, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %m1 : i64
  } else {
    %rc2 = scf.if %hasin -> (i32) {
      %r = func.call @pipe(%inpipe) : (!llvm.ptr) -> i32
      scf.yield %r : i32
    } else {
      scf.yield %z32 : i32
    }
    %bad2 = arith.cmpi ne, %rc2, %z32 : i32
    %res1 = scf.if %bad2 -> (i64) {
      %said2 = func.call @nixsb_say(%c, %c0, %c24, %prog, %c0, %prog, %c0, %prog, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %m1 : i64
    } else {
      // the program's name and the directory, a NUL after each; then the argument pointers, at a word
      %null = llvm.mlir.zero : !llvm.ptr
      %names, %nn = func.call @sbr_cat(%prog, %pn, %null, %c0, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      %dir, %dn = func.call @sbr_cat(%cwd, %cn, %null, %c0, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      %na2 = arith.addi %na, %c2 : i64
      %ab = arith.muli %na2, %c8 : i64
      %argv = func.call @sbr_room(%ab) : (i64) -> !llvm.ptr
      %pid = func.call @fork() : () -> i32
      %nofork = arith.cmpi slt, %pid, %z32 : i32
      %res2 = scf.if %nofork -> (i64) {
        %said3 = func.call @nixsb_say(%c, %c0, %c17, %prog, %c0, %prog, %c0, %prog, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
        scf.yield %m1 : i64
      } else {
        %o0 = llvm.load %pipes : !llvm.ptr -> i32
        %o1p = llvm.getelementptr %pipes[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %o1 = llvm.load %o1p : !llvm.ptr -> i32
        %child = arith.cmpi eq, %pid, %z32 : i32
        %res3 = scf.if %child -> (i64) {
          // the child: its directory, its standard output the pipe, its standard input the caller's bytes or nothing
          %goes = arith.cmpi ne, %cn, %c0 : i64
          scf.if %goes {
            %cd = func.call @chdir(%dir) : (!llvm.ptr) -> i32
            %nocd = arith.cmpi ne, %cd, %z32 : i32
            scf.if %nocd {
              func.call @_exit(%x127) : (i32) -> ()
            }
          }
          %d1 = func.call @dup2(%o1, %one32) : (i32, i32) -> i32
          %x1 = func.call @close(%o0) : (i32) -> i32
          %x2 = func.call @close(%o1) : (i32) -> i32
          scf.if %hasin {
            %i0 = llvm.load %inpipe : !llvm.ptr -> i32
            %i1p = llvm.getelementptr %inpipe[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %i1 = llvm.load %i1p : !llvm.ptr -> i32
            %d2 = func.call @dup2(%i0, %z32) : (i32, i32) -> i32
            %x3 = func.call @close(%i0) : (i32) -> i32
            %x4 = func.call @close(%i1) : (i32) -> i32
          } else {
            %nul = func.call @nixsb_os_devnull() : () -> i32
            %d3 = func.call @dup2(%nul, %z32) : (i32, i32) -> i32
          }
          %cnt = func.call @nixstore_ts_argv(%names, %args, %na, %argv) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> i64
          %ex = func.call @execvp(%names, %argv) : (!llvm.ptr, !llvm.ptr) -> i32
          func.call @_exit(%x127) : (i32) -> ()
          scf.yield %m1 : i64
        } else {
          // the parent: the caller's bytes written, then what the program writes read to its end, then its end awaited
          %x5 = func.call @close(%o1) : (i32) -> i32
          scf.if %hasin {
            %i0 = llvm.load %inpipe : !llvm.ptr -> i32
            %i1p = llvm.getelementptr %inpipe[%c4] : (!llvm.ptr, i64) -> !llvm.ptr, i8
            %i1 = llvm.load %i1p : !llvm.ptr -> i32
            %x6 = func.call @close(%i0) : (i32) -> i32
            %ip, %in = func.call @sbr_text(%input) : (!llvm.ptr) -> (!llvm.ptr, i64)
            %we:2 = scf.while (%off = %c0, %go = %c1) : (i64, i64) -> (i64, i64) {
              %left = arith.cmpi slt, %off, %in : i64
              %on = arith.cmpi eq, %go, %c1 : i64
              %more = arith.andi %left, %on : i1
              scf.condition(%more) %off, %go : i64, i64
            } do {
            ^bb0(%offa: i64, %goa: i64):
              %at = llvm.getelementptr %ip[%offa] : (!llvm.ptr, i64) -> !llvm.ptr, i8
              %rest = arith.subi %in, %offa : i64
              %k = func.call @write(%i1, %at, %rest) : (i32, !llvm.ptr, i64) -> i64
              %wrote = arith.cmpi sgt, %k, %c0 : i64
              %k0 = arith.select %wrote, %k, %c0 : i64
              %off2 = arith.addi %offa, %k0 : i64
              %go2 = arith.extui %wrote : i1 to i64
              scf.yield %off2, %go2 : i64, i64
            }
            %x7 = func.call @close(%i1) : (i32) -> i32
          }
          %first = func.call @read(%o0, %buf, %c65536) : (i32, !llvm.ptr, i64) -> i64
          %re = scf.while (%k = %first) : (i64) -> (i64) {
            %got = arith.cmpi sgt, %k, %c0 : i64
            scf.condition(%got) %k : i64
          } do {
          ^bb0(%ka: i64):
            scf.if %hasout {
              func.call @nixsb_put(%out, %buf, %ka) : (!llvm.ptr, !llvm.ptr, i64) -> ()
            }
            %next = func.call @read(%o0, %buf, %c65536) : (i32, !llvm.ptr, i64) -> i64
            scf.yield %next : i64
          }
          %x8 = func.call @close(%o0) : (i32) -> i32
          llvm.store %z32, %status : i32, !llvm.ptr
          %wp = func.call @waitpid(%pid, %status, %z32) : (i32, !llvm.ptr, i32) -> i32
          %st32 = llvm.load %status : !llvm.ptr -> i32
          %st = arith.extui %st32 : i32 to i64
          %w = func.call @nixsb_os_wait(%st) : (i64) -> i64
          %exited = arith.cmpi slt, %w, %c256 : i64
          %sigbit = arith.andi %w, %c65536 : i64
          %signaled = arith.cmpi ne, %sigbit, %c0 : i64
          %sig0 = arith.andi %w, %c255 : i64
          %sig = arith.select %signaled, %sig0, %c0 : i64
          %killed = arith.addi %c128, %sig : i64
          %code = arith.select %exited, %w, %killed : i64
          scf.yield %code : i64
        }
        scf.yield %res3 : i64
      }
      func.call @nixsb_os_free(%names) : (!llvm.ptr) -> ()
      func.call @nixsb_os_free(%dir) : (!llvm.ptr) -> ()
      func.call @nixsb_os_free(%argv) : (!llvm.ptr) -> ()
      scf.yield %res2 : i64
    }
    scf.yield %res1 : i64
  }
  return %res : i64
}

//===----------------------------------------------------------------------===//
// runBuilder
//===----------------------------------------------------------------------===//

// row i of the environment (a name and a value: four words) set; the next row's number
func.func private @sbr_row(%rows: !llvm.ptr, %i: i64, %kp: !llvm.ptr, %kn: i64, %vp: !llvm.ptr, %vn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c32 = arith.constant 32 : i64
  %ro = arith.muli %i, %c32 : i64
  %r = llvm.getelementptr %rows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %kb = llvm.ptrtoint %kp : !llvm.ptr to i64
  %vb = llvm.ptrtoint %vp : !llvm.ptr to i64
  func.call @sbr_ws(%r, %c0, %kb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbr_ws(%r, %c1, %kn) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbr_ws(%r, %c2, %vb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbr_ws(%r, %c3, %vn) : (!llvm.ptr, i64, i64) -> ()
  %next = arith.addi %i, %c1 : i64
  return %next : i64
}
// the same, the name the constant text at koff; and the value the one at voff too
func.func private @sbr_rowk(%rows: !llvm.ptr, %i: i64, %koff: i64, %vp: !llvm.ptr, %vn: i64) -> i64 {
  %kp, %kn = func.call @sbr_lit(%koff) : (i64) -> (!llvm.ptr, i64)
  %next = func.call @sbr_row(%rows, %i, %kp, %kn, %vp, %vn) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
  return %next : i64
}
func.func private @sbr_rowkv(%rows: !llvm.ptr, %i: i64, %koff: i64, %voff: i64) -> i64 {
  %vp, %vn = func.call @sbr_lit(%voff) : (i64) -> (!llvm.ptr, i64)
  %next = func.call @sbr_rowk(%rows, %i, %koff, %vp, %vn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  return %next : i64
}

// the names of rows x and y in byte order (Text's operator<: unsigned bytes, then the shorter first)
func.func private @sbr_cmpkey(%rows: !llvm.ptr, %x: i64, %y: i64) -> i32 {
  %c4 = arith.constant 4 : i64
  %c1 = arith.constant 1 : i64
  %x4 = arith.muli %x, %c4 : i64
  %y4 = arith.muli %y, %c4 : i64
  %x41 = arith.addi %x4, %c1 : i64
  %y41 = arith.addi %y4, %c1 : i64
  %xpb = func.call @sbr_w(%rows, %x4) : (!llvm.ptr, i64) -> i64
  %xn = func.call @sbr_w(%rows, %x41) : (!llvm.ptr, i64) -> i64
  %ypb = func.call @sbr_w(%rows, %y4) : (!llvm.ptr, i64) -> i64
  %yn = func.call @sbr_w(%rows, %y41) : (!llvm.ptr, i64) -> i64
  %xp = llvm.inttoptr %xpb : i64 to !llvm.ptr
  %yp = llvm.inttoptr %ypb : i64 to !llvm.ptr
  %a_d = func.call @sbr_d(%xp, %xn) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sbr_d(%yp, %yn) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c = trikeshed.compare %a, %b unsigned : !s, !s
  return %c : i32
}

// The environment drained: the n rows at rows, in the order they were set, into `into` in name order, of equal names
// the last set (a map's `env[name] = value`): the rows' numbers sorted by name (stable), the last of each run of equal
// names kept (where), the kept rows one combineAll of four-word slices drained once.  Returns how many.
func.func private @sbr_drain_env(%rows: !llvm.ptr, %n: i64, %into: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %z32 = arith.constant 0 : i32
  %i4 = arith.constant 4 : index
  %ni = arith.index_cast %n : i64 to index
  %idx = trikeshed.series %ni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
  ^bb0(%x: i64, %y: i64):
    %c = func.call @sbr_cmpkey(%rows, %x, %y) : (!llvm.ptr, i64, i64) -> i32
    trikeshed.yield %c : i32
  }
  %last = arith.subi %n, %c1 : i64
  %kept = trikeshed.where %idx : !s64 -> !s64 {
  ^bb0(%k: i64):
    %end = arith.cmpi eq, %k, %last : i64
    %r = scf.if %end -> (i1) {
      %t = arith.constant 1 : i1
      scf.yield %t : i1
    } else {
      %ki = arith.index_cast %k : i64 to index
      %k1 = arith.addi %k, %c1 : i64
      %k1i = arith.index_cast %k1 : i64 to index
      %e1 = trikeshed.at %srt[%ki] : !s64, index -> i64
      %e2 = trikeshed.at %srt[%k1i] : !s64, index -> i64
      %c = func.call @sbr_cmpkey(%rows, %e1, %e2) : (!llvm.ptr, i64, i64) -> i32
      %ne = arith.cmpi ne, %c, %z32 : i32
      scf.yield %ne : i1
    }
    trikeshed.yield %r : i1
  }
  %m = trikeshed.size %kept : !s64
  %n4 = arith.muli %n, %c4 : i64
  %rd = func.call @sbr_d(%rows, %n4) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %words = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %all, %where = trikeshed.combineAll %m : !s64, !pieces {
  ^bb0(%j: index):
    %k = trikeshed.at %kept[%j] : !s64, index -> i64
    %ki = arith.index_cast %k : i64 to index
    %e = trikeshed.at %srt[%ki] : !s64, index -> i64
    %ei = arith.index_cast %e : i64 to index
    %at = arith.muli %ei, %i4 : index
    %row = trikeshed.slice %words[%at, %i4] : !s64 -> !s64
    trikeshed.yield %row : !s64
  }
  %id = func.call @sbr_d(%into, %n4) : (!llvm.ptr, i64) -> !d
  %im = builtin.unrealized_conversion_cast %id : !d to !m64
  %end = trikeshed.drain %all, %im : !s64, !m64 -> index
  %m64 = arith.index_cast %m : index to i64
  return %m64 : i64
}

// The build's directory: `nix-build-<name>-XXXXXX` under TMPDIR (/tmp when there is none), made by mkdtemp: one combine
// drained once into a room, the handle's 0th.  Its length; -1 with the error said when it cannot be made.
func.func private @sbr_top(%c: !llvm.ptr, %h: !llvm.ptr, %drv: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %m1 = arith.constant -1 : i64
  %b0 = arith.constant 0 : i8
  %z = arith.constant 0 : index
  %o_tmpdir = arith.constant 0 : i64 // lit "TMPDIR"
  %o_tmp = arith.constant 8 : i64 // lit "/tmp"
  %o_pre = arith.constant 14 : i64 // lit "/nix-build-"
  %o_xs = arith.constant 27 : i64 // lit "-XXXXXX"
  %np, %nn = func.call @sbr_text(%drv) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %tk, %tkn = func.call @sbr_lit(%o_tmpdir) : (i64) -> (!llvm.ptr, i64)
  %dp, %dn = func.call @sbr_lit(%o_tmp) : (i64) -> (!llvm.ptr, i64)
  %pp, %pn = func.call @sbr_lit(%o_pre) : (i64) -> (!llvm.ptr, i64)
  %xp, %xn = func.call @sbr_lit(%o_xs) : (i64) -> (!llvm.ptr, i64)
  %tv = func.call @getenv(%tk) : (!llvm.ptr) -> !llvm.ptr
  %tb = llvm.ptrtoint %tv : !llvm.ptr to i64
  %set = arith.cmpi ne, %tb, %c0 : i64
  %bp, %bn = scf.if %set -> (!llvm.ptr, i64) {
    %tn = func.call @strlen(%tv) : (!llvm.ptr) -> i64
    %some = arith.cmpi ne, %tn, %c0 : i64
    %p1, %n1 = scf.if %some -> (!llvm.ptr, i64) {
      scf.yield %tv, %tn : !llvm.ptr, i64
    } else {
      scf.yield %dp, %dn : !llvm.ptr, i64
    }
    scf.yield %p1, %n1 : !llvm.ptr, i64
  } else {
    scf.yield %dp, %dn : !llvm.ptr, i64
  }
  %room, %len = func.call @sbr_cat(%bp, %bn, %pp, %pn, %np, %nn, %xp, %xn) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
  func.call @sbr_keep(%h, %c0, %room) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %made = func.call @mkdtemp(%room) : (!llvm.ptr) -> !llvm.ptr
  %mb = llvm.ptrtoint %made : !llvm.ptr to i64
  %none = arith.cmpi eq, %mb, %c0 : i64
  %r = scf.if %none -> (i64) {
    %e = func.call @nixsb_os_errno() : () -> i64
    %said = func.call @nixsb_say(%c, %c0, %c16, %room, %c0, %room, %c0, %room, %c0, %e, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %m1 : i64
  } else {
    scf.yield %len : i64
  }
  return %r : i64
}

// The environment's rows filled, in the order Nix sets them, into a room that is the handle's 1st: how many, or -1 when
// the structured attributes' files could not be made (the store keeps why).  top: the build's directory.
// Derivation: name 0, outputs 16, builder 80, args 96, env 112, structuredAttrs 128 (a byte, then the Text at 136).
// Store: settings at 16 (storeDir 0, realRoot 16, cores 32 bits at 52, keepFailed a byte at 56).
func.func private @sbr_env(%c: !llvm.ptr, %h: !llvm.ptr, %drv: !llvm.ptr, %outputs: !llvm.ptr, %top: !llvm.ptr,
                           %tn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c10 = arith.constant 10 : i64
  %c15 = arith.constant 15 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c112 = arith.constant 112 : i64
  %c128 = arith.constant 128 : i64
  %c136 = arith.constant 136 : i64
  %c420 = arith.constant 420 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %b0 = arith.constant 0 : i8
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %o_path = arith.constant 36 : i64 // lit "PATH"
  %o_nopath = arith.constant 42 : i64 // lit "/path-not-set"
  %o_home = arith.constant 57 : i64 // lit "HOME"
  %o_nohome = arith.constant 63 : i64 // lit "/homeless-shelter"
  %o_store = arith.constant 82 : i64 // lit "NIX_STORE"
  %o_cores = arith.constant 93 : i64 // lit "NIX_BUILD_CORES"
  %o_top = arith.constant 110 : i64 // lit "NIX_BUILD_TOP"
  %o_tmpdir = arith.constant 0 : i64 // lit "TMPDIR"
  %o_tempdir = arith.constant 125 : i64 // lit "TEMPDIR"
  %o_tmp = arith.constant 134 : i64 // lit "TMP"
  %o_temp = arith.constant 139 : i64 // lit "TEMP"
  %o_pwd = arith.constant 145 : i64 // lit "PWD"
  %o_logfd = arith.constant 150 : i64 // lit "NIX_LOG_FD"
  %o_two = arith.constant 162 : i64 // lit "2"
  %o_term = arith.constant 165 : i64 // lit "TERM"
  %o_xterm = arith.constant 171 : i64 // lit "xterm-256color"
  %o_dyld = arith.constant 187 : i64 // lit "DYLD_SHARED_REGION"
  %o_impure = arith.constant 207 : i64 // lit "impureEnvVars"
  %o_out = arith.constant 222 : i64 // lit "out"
  %o_json = arith.constant 227 : i64 // lit "/.attrs.json"
  %o_sh = arith.constant 241 : i64 // lit "/.attrs.sh"
  %o_jsonfile = arith.constant 253 : i64 // lit "NIX_ATTRS_JSON_FILE"
  %o_shfile = arith.constant 274 : i64 // lit "NIX_ATTRS_SH_FILE"
  %cell = llvm.alloca %c8 x i64 : (i64) -> !llvm.ptr
  %c24 = arith.constant 24 : i64
  %digits = func.call @sbr_room(%c24) : (i64) -> !llvm.ptr
  func.call @sbr_keep(%h, %c6, %digits) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %null = llvm.mlir.zero : !llvm.ptr
  %st = func.call @sbr_w(%c, %c0) : (!llvm.ptr, i64) -> i64
  %stp = llvm.inttoptr %st : i64 to !llvm.ptr
  %settings = llvm.getelementptr %stp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sdp, %sdn = func.call @sbr_text(%settings) : (!llvm.ptr) -> (!llvm.ptr, i64)
  // the cores, in decimal: a series of the digits drained into a room the rows may point into (the handle's 6th)
  %cw = func.call @sbr_w(%settings, %c6) : (!llvm.ptr, i64) -> i64
  %cs = arith.shrui %cw, %c32 : i64
  %cores = arith.andi %cs, %low32 : i64
  %nd:2 = scf.while (%v = %cores, %k0 = %i1) : (i64, index) -> (i64, index) {
    %more = arith.cmpi uge, %v, %c10 : i64
    scf.condition(%more) %v, %k0 : i64, index
  } do {
  ^bb0(%v1: i64, %k1: index):
    %q = arith.divui %v1, %c10 : i64
    %k2 = arith.addi %k1, %i1 : index
    scf.yield %q, %k2 : i64, index
  }
  %ds = trikeshed.series %nd#1 : !s {
  ^bb0(%k: index):
    %lastd = arith.subi %nd#1, %i1 : index
    %pw = arith.subi %lastd, %k : index
    %q = scf.for %j = %z to %pw step %i1 iter_args(%v = %cores) -> (i64) {
      %v2 = arith.divui %v, %c10 : i64
      scf.yield %v2 : i64
    }
    %dig = arith.remui %q, %c10 : i64
    %ch = arith.addi %dig, %c48 : i64
    %ch8 = arith.trunci %ch : i64 to i8
    trikeshed.yield %ch8 : i8
  }
  %dd = func.call @sbr_d(%digits, %c24) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %dd : !d to !m
  %de = trikeshed.drain %ds, %dm : !s, !m -> index
  %ndn = arith.index_cast %nd#1 : index to i64
  // a fixed-output derivation (one output, "out", fixed) lets the variables its impureEnvVars names in
  %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %orows, %on = func.call @sbr_text(%outs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %one = arith.cmpi eq, %on, %c1 : i64
  %fixed = scf.if %one -> (i1) {
    %kp, %kn = func.call @sbr_text(%orows) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %isout = func.call @sbr_is(%kp, %kn, %o_out) : (!llvm.ptr, i64, i64) -> i1
    %kw = func.call @sbr_w(%orows, %c2) : (!llvm.ptr, i64) -> i64
    %kind = arith.andi %kw, %low32 : i64
    %cafixed = arith.cmpi eq, %kind, %c1 : i64
    %f = arith.andi %isout, %cafixed : i1
    scf.yield %f : i1
  } else {
    %no = arith.constant 0 : i1
    scf.yield %no : i1
  }
  %envmap = llvm.getelementptr %drv[%c112] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %erows, %en = func.call @sbr_text(%envmap) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %ip, %in = scf.if %fixed -> (!llvm.ptr, i64) {
    %vp, %vn, %found = func.call @sbr_get(%envmap, %o_impure) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
    scf.yield %vp, %vn : !llvm.ptr, i64
  } else {
    scf.yield %null, %c0 : !llvm.ptr, i64
  }
  // the room: Nix's twelve, the shared region's one, a word of impureEnvVars each, the derivation's own, the two files
  %words0 = arith.addi %in, %c1 : i64
  %words = arith.shrui %words0, %c1 : i64
  %b1 = arith.addi %words, %en : i64
  %bound = arith.addi %b1, %c15 : i64
  %rb = arith.muli %bound, %c32 : i64
  %rows = func.call @sbr_room(%rb) : (i64) -> !llvm.ptr
  func.call @sbr_keep(%h, %c1, %rows) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %r1 = func.call @sbr_rowkv(%rows, %c0, %o_path, %o_nopath) : (!llvm.ptr, i64, i64, i64) -> i64
  %r2 = func.call @sbr_rowkv(%rows, %r1, %o_home, %o_nohome) : (!llvm.ptr, i64, i64, i64) -> i64
  %r3 = func.call @sbr_rowk(%rows, %r2, %o_store, %sdp, %sdn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r4 = func.call @sbr_rowk(%rows, %r3, %o_cores, %digits, %ndn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r5 = func.call @sbr_rowk(%rows, %r4, %o_top, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r6 = func.call @sbr_rowk(%rows, %r5, %o_tmpdir, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r7 = func.call @sbr_rowk(%rows, %r6, %o_tempdir, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r8 = func.call @sbr_rowk(%rows, %r7, %o_tmp, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r9 = func.call @sbr_rowk(%rows, %r8, %o_temp, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r10 = func.call @sbr_rowk(%rows, %r9, %o_pwd, %top, %tn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
  %r11 = func.call @sbr_rowkv(%rows, %r10, %o_logfd, %o_two) : (!llvm.ptr, i64, i64, i64) -> i64
  %r12 = func.call @sbr_rowkv(%rows, %r11, %o_term, %o_xterm) : (!llvm.ptr, i64, i64, i64) -> i64
  // dyld's shared region, where the builder's parent has it set (a chroot on a Mac)
  %dk, %dkn = func.call @sbr_lit(%o_dyld) : (i64) -> (!llvm.ptr, i64)
  %dv = func.call @getenv(%dk) : (!llvm.ptr) -> !llvm.ptr
  %dvb = llvm.ptrtoint %dv : !llvm.ptr to i64
  %hasd = arith.cmpi ne, %dvb, %c0 : i64
  %r13 = scf.if %hasd -> (i64) {
    %dvn = func.call @strlen(%dv) : (!llvm.ptr) -> i64
    %rn = func.call @sbr_row(%rows, %r12, %dk, %dkn, %dv, %dvn) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %rn : i64
  } else {
    scf.yield %r12 : i64
  }
  // the variables impureEnvVars names: each word, where the store's own environment has it
  %wb0, %we0 = func.call @sbr_word(%ip, %in, %c0) : (!llvm.ptr, i64, i64) -> (i64, i64)
  %wbe, %wee, %r14 = scf.while (%wb = %wb0, %we = %we0, %ri = %r13) : (i64, i64, i64) -> (i64, i64, i64) {
    %isword = arith.cmpi slt, %wb, %in : i64
    scf.condition(%isword) %wb, %we, %ri : i64, i64, i64
  } do {
  ^bb0(%wba: i64, %wea: i64, %ria: i64):
    %wp = llvm.getelementptr %ip[%wba] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wn = arith.subi %wea, %wba : i64
    %name, %nlen = func.call @sbr_cat(%wp, %wn, %null, %c0, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %val = func.call @getenv(%name) : (!llvm.ptr) -> !llvm.ptr
    func.call @nixsb_os_free(%name) : (!llvm.ptr) -> ()
    %valb = llvm.ptrtoint %val : !llvm.ptr to i64
    %hasv = arith.cmpi ne, %valb, %c0 : i64
    %rin = scf.if %hasv -> (i64) {
      %valn = func.call @strlen(%val) : (!llvm.ptr) -> i64
      %rn2 = func.call @sbr_row(%rows, %ria, %wp, %wn, %val, %valn) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      scf.yield %rn2 : i64
    } else {
      scf.yield %ria : i64
    }
    %nb, %ne = func.call @sbr_word(%ip, %in, %wea) : (!llvm.ptr, i64, i64) -> (i64, i64)
    scf.yield %nb, %ne, %rin : i64, i64, i64
  }
  // the outputs' placeholders, noted with the paths they stand for
  %prows, %pcount = func.call @sbr_text(%outputs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %pci = arith.index_cast %pcount : i64 to index
  scf.for %j = %z to %pci step %i1 {
    %j64 = arith.index_cast %j : index to i64
    %ro = arith.muli %j64, %c32 : i64
    %vo = arith.addi %ro, %c16 : i64
    %kt = llvm.getelementptr %prows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vt = llvm.getelementptr %prows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %op, %onn = func.call @sbr_text(%kt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %pp, %pn = func.call @sbr_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    func.call @nixsb_placeholder(%c, %op, %onn, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
  }
  // the derivation's own variables, the placeholders in their values rewritten
  %eni = arith.index_cast %en : i64 to index
  %r15 = scf.for %j = %z to %eni step %i1 iter_args(%ri = %r14) -> (i64) {
    %j64 = arith.index_cast %j : index to i64
    %ro = arith.muli %j64, %c32 : i64
    %vo = arith.addi %ro, %c16 : i64
    %kt = llvm.getelementptr %erows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %vt = llvm.getelementptr %erows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %kp, %kn = func.call @sbr_text(%kt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %vp, %vn = func.call @sbr_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %wp = func.call @nixsb_rewrite(%c, %vp, %vn, %cell) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
    %wn = func.call @sbr_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    %rn = func.call @sbr_row(%rows, %ri, %kp, %kn, %wp, %wn) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %rn : i64
  }
  // the structured attributes: .attrs.json and .attrs.sh in the build's directory, and the two variables that name them
  %hasp = llvm.getelementptr %drv[%c128] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %has8 = llvm.load %hasp : !llvm.ptr -> i8
  %structured = arith.cmpi ne, %has8, %b0 : i8
  %res = scf.if %structured -> (i64) {
    %jt = llvm.getelementptr %drv[%c136] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %jp, %jn = func.call @sbr_text(%jt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %s1 = func.call @nixsb_sattrs(%c, %jp, %jn, %outputs, %cell) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
    %ok1 = arith.cmpi eq, %s1, %c0 : i64
    %res1 = scf.if %ok1 -> (i64) {
      %jb = func.call @sbr_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
      %jl = func.call @sbr_w(%cell, %c1) : (!llvm.ptr, i64) -> i64
      %sb = func.call @sbr_w(%cell, %c2) : (!llvm.ptr, i64) -> i64
      %sl = func.call @sbr_w(%cell, %c3) : (!llvm.ptr, i64) -> i64
      %jbytes = llvm.inttoptr %jb : i64 to !llvm.ptr
      %sbytes = llvm.inttoptr %sb : i64 to !llvm.ptr
      %lj, %ljn = func.call @sbr_lit(%o_json) : (i64) -> (!llvm.ptr, i64)
      %ls, %lsn = func.call @sbr_lit(%o_sh) : (i64) -> (!llvm.ptr, i64)
      %jpath, %jpn = func.call @sbr_cat(%top, %tn, %lj, %ljn, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @sbr_keep(%h, %c7, %jpath) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %spath, %spn = func.call @sbr_cat(%top, %tn, %ls, %lsn, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @sbr_keep(%h, %c8, %spath) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %s2 = func.call @nixsb_write(%c, %jpath, %jpn, %jbytes, %jl, %c420) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
      %ok2 = arith.cmpi eq, %s2, %c0 : i64
      %res2 = scf.if %ok2 -> (i64) {
        %s3 = func.call @nixsb_write(%c, %spath, %spn, %sbytes, %sl, %c420) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
        %ok3 = arith.cmpi eq, %s3, %c0 : i64
        %res3 = scf.if %ok3 -> (i64) {
          %ra = func.call @sbr_rowk(%rows, %r15, %o_jsonfile, %jpath, %jpn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
          %rb2 = func.call @sbr_rowk(%rows, %ra, %o_shfile, %spath, %spn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
          scf.yield %rb2 : i64
        } else {
          scf.yield %m1 : i64
        }
        scf.yield %res3 : i64
      } else {
        scf.yield %m1 : i64
      }
      scf.yield %res2 : i64
    } else {
      scf.yield %m1 : i64
    }
    scf.yield %res1 : i64
  } else {
    scf.yield %r15 : i64
  }
  return %res : i64
}

// The arguments' rows (a pointer and a length each, as a Text's first words): the builder's base name, then the
// derivation's arguments with the placeholders rewritten.  The rows are the handle's 4th room, the base name its 9th.
// Returns how many.
func.func private @sbr_args(%c: !llvm.ptr, %h: !llvm.ptr, %drv: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c80 = arith.constant 80 : i64
  %c96 = arith.constant 96 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %bt = llvm.getelementptr %drv[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %bp, %bn = func.call @sbr_text(%bt) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %at = llvm.getelementptr %drv[%c96] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %arows, %na = func.call @sbr_text(%at) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %na1 = arith.addi %na, %c1 : i64
  %rb = arith.muli %na1, %c16 : i64
  %rows = func.call @sbr_room(%rb) : (i64) -> !llvm.ptr
  func.call @sbr_keep(%h, %c4, %rows) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %bn1 = arith.addi %bn, %c1 : i64
  %base = func.call @sbr_room(%bn1) : (i64) -> !llvm.ptr
  func.call @sbr_keep(%h, %c9, %base) : (!llvm.ptr, i64, !llvm.ptr) -> ()
  %bl = func.call @nixstore_ts_basename(%bp, %bn, %base) : (!llvm.ptr, i64, !llvm.ptr) -> i64
  %bb = llvm.ptrtoint %base : !llvm.ptr to i64
  func.call @sbr_ws(%rows, %c0, %bb) : (!llvm.ptr, i64, i64) -> ()
  func.call @sbr_ws(%rows, %c1, %bl) : (!llvm.ptr, i64, i64) -> ()
  %nai = arith.index_cast %na : i64 to index
  scf.for %j = %z to %nai step %i1 {
    %j64 = arith.index_cast %j : index to i64
    %ro = arith.muli %j64, %c16 : i64
    %t = llvm.getelementptr %arows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %ap, %an = func.call @sbr_text(%t) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %wp = func.call @nixsb_rewrite(%c, %ap, %an, %cell) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
    %wn = func.call @sbr_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    %wb = llvm.ptrtoint %wp : !llvm.ptr to i64
    %j1 = arith.addi %j64, %c1 : i64
    %w0 = arith.muli %j1, %c2 : i64
    %w1 = arith.addi %w0, %c1 : i64
    func.call @sbr_ws(%rows, %w0, %wb) : (!llvm.ptr, i64, i64) -> ()
    func.call @sbr_ws(%rows, %w1, %wn) : (!llvm.ptr, i64, i64) -> ()
  }
  return %na1 : i64
}

// What follows a builder that did not end well: its outputs removed (each at the store's physical root), then its
// directory removed, or kept and said so where the store keeps failed builds, then the failure said: 1 in any case
// (an entry that could not be removed is the error instead).  w: what nixsb_os_wait made of the builder's status.
func.func private @sbr_failed(%c: !llvm.ptr, %settings: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %outputs: !llvm.ptr,
                              %top: !llvm.ptr, %tn: i64, %w: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c16 = arith.constant 16 : i64
  %c18 = arith.constant 18 : i64
  %c19 = arith.constant 19 : i64
  %c20 = arith.constant 20 : i64
  %c32 = arith.constant 32 : i64
  %c56 = arith.constant 56 : i64
  %c255 = arith.constant 255 : i64
  %c256 = arith.constant 256 : i64
  %m1 = arith.constant -1 : i64
  %b0 = arith.constant 0 : i8
  %null = llvm.mlir.zero : !llvm.ptr
  %rt = llvm.getelementptr %settings[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %rp, %rn = func.call @sbr_text(%rt) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %prows, %pcount = func.call @sbr_text(%outputs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %je, %s1 = scf.while (%j = %c0, %s = %c0) : (i64, i64) -> (i64, i64) {
    %in = arith.cmpi slt, %j, %pcount : i64
    %fine = arith.cmpi eq, %s, %c0 : i64
    %go = arith.andi %in, %fine : i1
    scf.condition(%go) %j, %s : i64, i64
  } do {
  ^bb0(%ja: i64, %sa: i64):
    %ro = arith.muli %ja, %c32 : i64
    %vo = arith.addi %ro, %c16 : i64
    %vt = llvm.getelementptr %prows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pp, %pn = func.call @sbr_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %real, %realn = func.call @sbr_cat(%rp, %rn, %pp, %pn, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %there = func.call @nixsb_exists(%real, %realn) : (!llvm.ptr, i64) -> i64
    %is = arith.cmpi ne, %there, %c0 : i64
    %sn = scf.if %is -> (i64) {
      %ds = func.call @nixsb_delete(%c, %real, %realn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      scf.yield %ds : i64
    } else {
      scf.yield %c0 : i64
    }
    func.call @nixsb_os_free(%real) : (!llvm.ptr) -> ()
    %j1 = arith.addi %ja, %c1 : i64
    scf.yield %j1, %sn : i64, i64
  }
  %ok1 = arith.cmpi eq, %s1, %c0 : i64
  %res = scf.if %ok1 -> (i64) {
    %kp = llvm.getelementptr %settings[%c56] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %k8 = llvm.load %kp : !llvm.ptr -> i8
    %keeps = arith.cmpi ne, %k8, %b0 : i8
    %s2 = scf.if %keeps -> (i64) {
      %line = func.call @nixsb_say(%c, %c2, %c20, %top, %tn, %top, %c0, %top, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %c0 : i64
    } else {
      %ds2 = func.call @nixsb_delete(%c, %top, %tn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      scf.yield %ds2 : i64
    }
    %ok2 = arith.cmpi eq, %s2, %c0 : i64
    scf.if %ok2 {
      %exited = arith.cmpi slt, %w, %c256 : i64
      %sig = arith.andi %w, %c255 : i64
      %id = arith.select %exited, %c18, %c19 : i64
      %num = arith.select %exited, %w, %sig : i64
      %said = func.call @nixsb_say(%c, %c0, %id, %drvp, %drvn, %drvp, %c0, %drvp, %c0, %m1, %num) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    }
    scf.yield %c1 : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

// c: the store's context (its first word the store; the Texts at its 16 and 32 the rooms of the environment's and the
// arguments' strings); drv: the derivation; outputs: its outputs' paths by name.  0, or 1 with the error said or kept.
func.func @nixsb_build(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %drv: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %c17 = arith.constant 17 : i64
  %c21 = arith.constant 21 : i64
  %c32 = arith.constant 32 : i64
  %c80 = arith.constant 80 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %one32 = arith.constant 1 : i32
  %two32 = arith.constant 2 : i32
  %x127 = arith.constant 127 : i32
  %eintr = arith.constant 4 : i64
  %o_empty = arith.constant 293 : i64 // lit ""
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  %status = llvm.alloca %c1 x i32 : (i64) -> !llvm.ptr
  func.call @sbr_open(%h) : (!llvm.ptr) -> ()
  %st = func.call @sbr_w(%c, %c0) : (!llvm.ptr, i64) -> i64
  %stp = llvm.inttoptr %st : i64 to !llvm.ptr
  %settings = llvm.getelementptr %stp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tn = func.call @sbr_top(%c, %h, %drv) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
  %notop = arith.cmpi slt, %tn, %c0 : i64
  %res = scf.if %notop -> (i64) {
    scf.yield %c1 : i64
  } else {
    %top = func.call @sbr_w(%h, %c0) : (!llvm.ptr, i64) -> i64
    %topp = llvm.inttoptr %top : i64 to !llvm.ptr
    %n = func.call @sbr_env(%c, %h, %drv, %outputs, %topp, %tn) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
    %noenv = arith.cmpi slt, %n, %c0 : i64
    %res1 = scf.if %noenv -> (i64) {
      scf.yield %c1 : i64
    } else {
      // the environment in name order, and its strings; the arguments and theirs
      %rowsb = func.call @sbr_w(%h, %c1) : (!llvm.ptr, i64) -> i64
      %rows = llvm.inttoptr %rowsb : i64 to !llvm.ptr
      %fb = arith.muli %n, %c32 : i64
      %final = func.call @sbr_room(%fb) : (i64) -> !llvm.ptr
      func.call @sbr_keep(%h, %c2, %final) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %m = func.call @sbr_drain_env(%rows, %n, %final) : (!llvm.ptr, i64, !llvm.ptr) -> i64
      %m1x = arith.addi %m, %c1 : i64
      %eb = arith.muli %m1x, %c8 : i64
      %envp = func.call @sbr_room(%eb) : (i64) -> !llvm.ptr
      func.call @sbr_keep(%h, %c3, %envp) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %na = func.call @sbr_args(%c, %h, %drv) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      %argrowsb = func.call @sbr_w(%h, %c4) : (!llvm.ptr, i64) -> i64
      %argrows = llvm.inttoptr %argrowsb : i64 to !llvm.ptr
      %na1 = arith.addi %na, %c1 : i64
      %ab = arith.muli %na1, %c8 : i64
      %argv = func.call @sbr_room(%ab) : (i64) -> !llvm.ptr
      func.call @sbr_keep(%h, %c5, %argv) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %envroom = llvm.getelementptr %c[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %argroom = llvm.getelementptr %c[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %es = func.call @nixstore_ts_cstrs(%envroom, %final, %m, %c1, %envp) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> i64
      %as = func.call @nixstore_ts_cstrs(%argroom, %argrows, %na, %c0, %argv) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> i64
      // the builder: its path as a C string (a Text that never held a byte has none of its own)
      %bt = llvm.getelementptr %drv[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %bp0, %bn = func.call @sbr_text(%bt) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %ep, %en = func.call @sbr_lit(%o_empty) : (i64) -> (!llvm.ptr, i64)
      %some = arith.cmpi ne, %bn, %c0 : i64
      %bp = scf.if %some -> (!llvm.ptr) {
        scf.yield %bp0 : !llvm.ptr
      } else {
        scf.yield %ep : !llvm.ptr
      }
      %pid = func.call @fork() : () -> i32
      %nofork = arith.cmpi slt, %pid, %z32 : i32
      %res2 = scf.if %nofork -> (i64) {
        %said = func.call @nixsb_say(%c, %c0, %c17, %bp, %c0, %bp, %c0, %bp, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
        scf.yield %c1 : i64
      } else {
        %child = arith.cmpi eq, %pid, %z32 : i32
        %res3 = scf.if %child -> (i64) {
          // the child: in the build's directory, reading nothing, its output where the store's errors go, a session
          // of its own; a builder that cannot be run says so itself
          %cd = func.call @chdir(%topp) : (!llvm.ptr) -> i32
          %nocd = arith.cmpi ne, %cd, %z32 : i32
          scf.if %nocd {
            func.call @_exit(%x127) : (i32) -> ()
          }
          %nul = func.call @nixsb_os_devnull() : () -> i32
          %d0 = func.call @dup2(%nul, %z32) : (i32, i32) -> i32
          %d1 = func.call @dup2(%two32, %one32) : (i32, i32) -> i32
          %sid = func.call @setsid() : () -> i32
          %ex = func.call @execve(%bp, %argv, %envp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
          %e = func.call @nixsb_os_errno() : () -> i64
          %line = func.call @nixsb_say(%c, %c3, %c21, %bp, %bn, %bp, %c0, %bp, %c0, %e, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
          func.call @_exit(%x127) : (i32) -> ()
          scf.yield %c1 : i64
        } else {
          // the parent: the builder's end awaited (again when a signal breaks the wait)
          llvm.store %z32, %status : i32, !llvm.ptr
          %we = scf.while (%go = %c1) : (i64) -> (i64) {
            %on = arith.cmpi eq, %go, %c1 : i64
            scf.condition(%on) %go : i64
          } do {
          ^bb0(%goa: i64):
            %wp = func.call @waitpid(%pid, %status, %z32) : (i32, !llvm.ptr, i32) -> i32
            %neg = arith.cmpi slt, %wp, %z32 : i32
            %er = func.call @nixsb_os_errno() : () -> i64
            %broken = arith.cmpi eq, %er, %eintr : i64
            %again = arith.andi %neg, %broken : i1
            %g2 = arith.extui %again : i1 to i64
            scf.yield %g2 : i64
          }
          %st32 = llvm.load %status : !llvm.ptr -> i32
          %stw = arith.extui %st32 : i32 to i64
          %w = func.call @nixsb_os_wait(%stw) : (i64) -> i64
          %well = arith.cmpi eq, %w, %c0 : i64
          %res4 = scf.if %well -> (i64) {
            %ds = func.call @nixsb_delete(%c, %topp, %tn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
            scf.yield %ds : i64
          } else {
            %fs = func.call @sbr_failed(%c, %settings, %drvp, %drvn, %outputs, %topp, %tn, %w) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, i64) -> i64
            scf.yield %fs : i64
          }
          scf.yield %res4 : i64
        }
        scf.yield %res3 : i64
      }
      scf.yield %res2 : i64
    }
    scf.yield %res1 : i64
  }
  func.call @sbr_close(%h) : (!llvm.ptr) -> ()
  return %res : i64
}

//===----------------------------------------------------------------------===//
// builtin:fetchurl
//===----------------------------------------------------------------------===//

// c: the store's context; drv: the derivation (its env the map at 112); outputs: its outputs' paths by name.
func.func @nixsb_fetch(%c: !llvm.ptr, %drv: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c7 = arith.constant 7 : i64
  %c8 = arith.constant 8 : i64
  %c9 = arith.constant 9 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c22 = arith.constant 22 : i64
  %c23 = arith.constant 23 : i64
  %c27 = arith.constant 27 : i64
  %c112 = arith.constant 112 : i64
  %m1 = arith.constant -1 : i64
  %rwx = arith.constant 493 : i32
  %o_url = arith.constant 295 : i64 // lit "url"
  %o_urls = arith.constant 300 : i64 // lit "urls"
  %o_out = arith.constant 222 : i64 // lit "out"
  %o_dottmp = arith.constant 306 : i64 // lit ".tmp"
  %o_curl = arith.constant 312 : i64 // lit "curl"
  %o_f = arith.constant 318 : i64 // lit "-fsSL"
  %o_retry = arith.constant 325 : i64 // lit "--retry"
  %o_three = arith.constant 334 : i64 // lit "3"
  %o_o = arith.constant 337 : i64 // lit "-o"
  %o_unpack = arith.constant 341 : i64 // lit "unpack"
  %o_exec = arith.constant 349 : i64 // lit "executable"
  %o_one = arith.constant 361 : i64 // lit "1"
  %h = llvm.alloca %c16 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %argrows = llvm.alloca %c12 x i64 : (i64) -> !llvm.ptr
  %null = llvm.mlir.zero : !llvm.ptr
  func.call @sbr_open(%h) : (!llvm.ptr) -> ()
  %st = func.call @sbr_w(%c, %c0) : (!llvm.ptr, i64) -> i64
  %stp = llvm.inttoptr %st : i64 to !llvm.ptr
  %settings = llvm.getelementptr %stp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %envmap = llvm.getelementptr %drv[%c112] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  // the url, or the first word of the urls
  %u1, %u1n, %f1 = func.call @sbr_get(%envmap, %o_url) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
  %hasurl = arith.cmpi ne, %u1n, %c0 : i64
  %up, %un = scf.if %hasurl -> (!llvm.ptr, i64) {
    scf.yield %u1, %u1n : !llvm.ptr, i64
  } else {
    %lp, %ln, %f2 = func.call @sbr_get(%envmap, %o_urls) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
    %wb, %we = func.call @sbr_word(%lp, %ln, %c0) : (!llvm.ptr, i64, i64) -> (i64, i64)
    %wp = llvm.getelementptr %lp[%wb] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wn = arith.subi %we, %wb : i64
    scf.yield %wp, %wn : !llvm.ptr, i64
  }
  %nourl = arith.cmpi eq, %un, %c0 : i64
  %res = scf.if %nourl -> (i64) {
    %said = func.call @nixsb_say(%c, %c0, %c22, %null, %c0, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %c1 : i64
  } else {
    %op, %on, %hasout = func.call @sbr_get(%outputs, %o_out) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
    %noout = arith.cmpi eq, %hasout, %c0 : i64
    %res1 = scf.if %noout -> (i64) {
      %kp, %kn = func.call @sbr_lit(%o_out) : (i64) -> (!llvm.ptr, i64)
      %said1 = func.call @nixsb_say(%c, %c1, %c27, %kp, %kn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %c1 : i64
    } else {
      // the output's place, the store's directory made, and the place the download lands first
      %sdp, %sdn = func.call @sbr_text(%settings) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %rt = llvm.getelementptr %settings[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %rp, %rn = func.call @sbr_text(%rt) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %real, %realn = func.call @sbr_cat(%rp, %rn, %op, %on, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @sbr_keep(%h, %c0, %real) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %sroot, %srootn = func.call @sbr_cat(%rp, %rn, %sdp, %sdn, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @sbr_keep(%h, %c1, %sroot) : (!llvm.ptr, i64, !llvm.ptr) -> ()
      %s0 = func.call @nixsb_mkdirs(%c, %sroot, %srootn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      %made = arith.cmpi eq, %s0, %c0 : i64
      %res2 = scf.if %made -> (i64) {
        %tl, %tln = func.call @sbr_lit(%o_dottmp) : (i64) -> (!llvm.ptr, i64)
        %tmp, %tmpn = func.call @sbr_cat(%real, %realn, %tl, %tln, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
        func.call @sbr_keep(%h, %c2, %tmp) : (!llvm.ptr, i64, !llvm.ptr) -> ()
        %url, %urln = func.call @sbr_cat(%up, %un, %null, %c0, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
        func.call @sbr_keep(%h, %c3, %url) : (!llvm.ptr, i64, !llvm.ptr) -> ()
        // curl -fsSL --retry 3 -o tmp url: the arguments as rows of a pointer and a length
        %a0, %a0n = func.call @sbr_lit(%o_f) : (i64) -> (!llvm.ptr, i64)
        %a1, %a1n = func.call @sbr_lit(%o_retry) : (i64) -> (!llvm.ptr, i64)
        %a2, %a2n = func.call @sbr_lit(%o_three) : (i64) -> (!llvm.ptr, i64)
        %a3, %a3n = func.call @sbr_lit(%o_o) : (i64) -> (!llvm.ptr, i64)
        %a0b = llvm.ptrtoint %a0 : !llvm.ptr to i64
        %a1b = llvm.ptrtoint %a1 : !llvm.ptr to i64
        %a2b = llvm.ptrtoint %a2 : !llvm.ptr to i64
        %a3b = llvm.ptrtoint %a3 : !llvm.ptr to i64
        %a4b = llvm.ptrtoint %tmp : !llvm.ptr to i64
        %a5b = llvm.ptrtoint %url : !llvm.ptr to i64
        func.call @sbr_ws(%argrows, %c0, %a0b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c1, %a0n) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c2, %a1b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c3, %a1n) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c4, %a2b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c5, %a2n) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c6, %a3b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c7, %a3n) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c8, %a4b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c9, %tmpn) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c10, %a5b) : (!llvm.ptr, i64, i64) -> ()
        func.call @sbr_ws(%argrows, %c11, %urln) : (!llvm.ptr, i64, i64) -> ()
        %cp, %cn = func.call @sbr_lit(%o_curl) : (i64) -> (!llvm.ptr, i64)
        %rc = func.call @nixsb_run(%c, %cp, %cn, %argrows, %c6, %null, %null, %null, %c0) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
        %norun = arith.cmpi slt, %rc, %c0 : i64
        %res3 = scf.if %norun -> (i64) {
          scf.yield %c1 : i64
        } else {
          %bad = arith.cmpi ne, %rc, %c0 : i64
          %res4 = scf.if %bad -> (i64) {
            %ul = func.call @unlink(%tmp) : (!llvm.ptr) -> i32
            %said2 = func.call @nixsb_say(%c, %c0, %c23, %url, %urln, %null, %c0, %null, %c0, %m1, %rc) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
            scf.yield %c1 : i64
          } else {
            %xp, %xn, %fx = func.call @sbr_get(%envmap, %o_unpack) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
            %unpack = func.call @sbr_is(%xp, %xn, %o_one) : (!llvm.ptr, i64, i64) -> i1
            %res5 = scf.if %unpack -> (i64) {
              %nar = func.call @nixsb_read(%c, %tmp, %tmpn, %cell) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
              %nn = func.call @sbr_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
              %unread = arith.cmpi slt, %nn, %c0 : i64
              %res6 = scf.if %unread -> (i64) {
                scf.yield %c1 : i64
              } else {
                %ul2 = func.call @unlink(%tmp) : (!llvm.ptr) -> i32
                %rs = func.call @nixsb_restore(%c, %real, %realn, %nar, %nn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
                scf.yield %rs : i64
              }
              scf.yield %res6 : i64
            } else {
              %mv = func.call @rename(%tmp, %real) : (!llvm.ptr, !llvm.ptr) -> i32
              %ep, %en, %fe = func.call @sbr_get(%envmap, %o_exec) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64)
              %exec = func.call @sbr_is(%ep, %en, %o_one) : (!llvm.ptr, i64, i64) -> i1
              scf.if %exec {
                %cm = func.call @chmod(%real, %rwx) : (!llvm.ptr, i32) -> i32
              }
              scf.yield %c0 : i64
            }
            scf.yield %res5 : i64
          }
          scf.yield %res4 : i64
        }
        scf.yield %res3 : i64
      } else {
        scf.yield %c1 : i64
      }
      scf.yield %res2 : i64
    }
    scf.yield %res1 : i64
  }
  func.call @sbr_close(%h) : (!llvm.ptr) -> ()
  return %res : i64
}
