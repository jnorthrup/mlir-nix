// What the store gains (lib/Store/LocalStore.cpp's addToStore, addTextToStore, addPermRoot and realise are gone;
// LocalStore.cpp names these entries and keeps the error one returns with).
//
//   nixsb_add      addToStore and addTextToStore: a file, a tree or a text hashed as its method says, held against the
//                  hash the caller expects, named by it (makeFixedOutputPath), and, unless the store only reads or has
//                  the path already, written at its place, made canonical and registered with its NAR's hash.
//   nixsb_root     addPermRoot: a link to a store path, and under <stateDir>/gcroots/auto a link to that link named by
//                  the hash of where it is.
//   nixsb_realise  realise: a derivation's outputs by name, built when one is not valid: its input derivations realised
//                  first and its sources there, its builder run (StoreRun.mlir), then each output made canonical, held
//                  against its hash when it is fixed, scanned for the references among its inputs' closure and
//                  registered.
//
// Each is a chain of steps, a step skipped once one before it failed; a walk over a derivation's rows (outputs, input
// derivations, sources) is a fold over their numbers with that status carried.  A derivation, a set and a map are read
// where they lie (a Text is a pointer and 32 bits of length, a row of a map of Texts two of them, a row of the outputs
// 120 bytes: its name, then kind at 16, path at 24, method at 40, hash at 48); LocalStore.cpp holds each place read here
// against the headers.  What belongs to the store's other parts is called by name and does not throw here: the hashes
// (hashFile, hashPath, hashString) and their text, the path a hash names, the sets and maps that are C++'s, the
// derivation read, the closure, the info written.  The trees' walks are StoreWalks.mlir's, the messages StoreWords.mlir's;
// the constant texts are one blob (store-lits.py, kept with the module's proofs, writes it and their places).
// Lowered by --trikeshed-lower-cursors and the stock buffer pipeline (lib/CMakeLists.txt mlnix_lower_trikeshed).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// lits @sba_lits
memref.global "private" constant @sba_lits : memref<61xi8> =
  dense<"0x0866697865643a723a0005746578743a000666697865643a000d2f6763726f6f74732f6175746f00012f00106275696c74696e3a666574636875726c00">
memref.global "private" constant @sba_zero : memref<2xi64> = dense<0>

// the C library
func.func private @unlink(!llvm.ptr) -> i32
func.func private @symlink(!llvm.ptr, !llvm.ptr) -> i32
func.func private @getcwd(!llvm.ptr, i64) -> !llvm.ptr
func.func private @strlen(!llvm.ptr) -> i64
func.func private @abort()
// the system's words (StoreBuildDarwin.mlir.in, StoreBuildLinux.mlir.in)
func.func private @nixsb_os_stat(!llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_os_errno() -> i64
func.func private @nixsb_os_pathmax() -> i64
func.func private @nixsb_os_grow(!llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_os_free(!llvm.ptr)
// the store's words (StoreWords.mlir): 5 creating symlink, 7 hash mismatch importing, 8 cycle, 9 content-addressed
// outputs, 10 read-only, 11 not physically accessible, 12 no such output, 13 building, 14 no output path, 15 hash
// mismatch in a fixed-output derivation, 27 no entry
func.func private @nixsb_say(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
// the trees (StoreWalks.mlir) and the builders (StoreRun.mlir)
func.func private @nixsb_canon(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_copy(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
func.func private @nixsb_refs(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixsb_build(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_fetch(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
// the store's (lib/Store/LocalStore.cpp), none of which throws; one that can fail answers 1, or no bytes, with the error
// kept.  A hash made (how 0 a file's, 1 a tree's NAR's under the call's filter, 2 a file's bytes' as text, 3 these
// bytes', 4 a tree's NAR's: the NAR's size at the last argument); a hash's text (format, with its algorithm's name or
// not; the length at the last argument); the path a hash names (method; its length at the last argument); whether a path
// is valid; a path registered (its NAR's hash and size, references, deriver, content address); a set's string put in
// (0: whether it was new; 3: 0), taken out (1), or the set emptied (2); a derivation read; an output's path noted by its
// name; an input derivation realised (its outputs by name); a source there or the error; a set's closure
func.func private @nixsb_hash(!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_hashtext(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_fixedpath(!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_valid(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_register(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixsb_set(!llvm.ptr, i64, !llvm.ptr, i64) -> i64
func.func private @nixsb_drv(!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
func.func private @nixsb_setout(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64)
func.func private @nixsb_input(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
func.func private @nixsb_ensure(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_closure(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixsb_put(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixsb_mkdirs(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_exists(!llvm.ptr, i64) -> i64
func.func private @nixsb_delete(!llvm.ptr, !llvm.ptr, i64) -> i64
func.func private @nixsb_copyfile(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
func.func private @nixsb_write(!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
// Hash::operator== (HashEq.mlir), outputPathName (StoreName.mlir), a sorted row by its key (SortedRows.mlir)
func.func private @_ZNK8nixstore4HasheqERKS0_(!llvm.ptr, !llvm.ptr) -> i1
func.func private @nixstore_ts_outputname(!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
func.func private @nixstore_ts_rowfind(!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64

//===----------------------------------------------------------------------===//
// Words, texts, rooms
//===----------------------------------------------------------------------===//

// the descriptor of n cells at p
func.func private @sba_d(%p: !llvm.ptr, %n: i64) -> !d {
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

// word i of the words at p
func.func private @sba_w(%p: !llvm.ptr, %i: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %n = arith.addi %i, %c1 : i64
  %pd = func.call @sba_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m64
  %ps = builtin.unrealized_conversion_cast %pm : !m64 to !s64
  %ii = arith.index_cast %i : i64 to index
  %v = trikeshed.at %ps[%ii] : !s64, index -> i64
  return %v : i64
}

// the Text at t (a pointer, then 32 bits of length): its bytes and its length; a set's or a map's rows and their count
func.func private @sba_text(%t: !llvm.ptr) -> (!llvm.ptr, i64) {
  %c2 = arith.constant 2 : i64
  %z = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %low32 = arith.constant 4294967295 : i64
  %td = func.call @sba_d(%t, %c2) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %td : !d to !m64
  %ts = builtin.unrealized_conversion_cast %tm : !m64 to !s64
  %pb = trikeshed.at %ts[%z] : !s64, index -> i64
  %nw = trikeshed.at %ts[%i1] : !s64, index -> i64
  %n = arith.andi %nw, %low32 : i64
  %p = llvm.inttoptr %pb : i64 to !llvm.ptr
  return %p, %n : !llvm.ptr, i64
}

// a room of n bytes, the caller's to give back
func.func private @sba_room(%n: i64) -> !llvm.ptr {
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

// the constant text at `off` of the blob (a length byte, then its bytes and a NUL): its bytes and its length
func.func private @sba_lit(%off: i64) -> (!llvm.ptr, i64) {
  %c1 = arith.constant 1 : i64
  %g = memref.get_global @sba_lits : memref<61xi8> // lits
  %lits = trikeshed.text %g : memref<61xi8> -> !s // lits
  %oi = arith.index_cast %off : i64 to index
  %n8 = trikeshed.at %lits[%oi] : !s, index -> i8
  %n = arith.extui %n8 : i8 to i64
  %bi = memref.extract_aligned_pointer_as_index %g : memref<61xi8> -> index // lits
  %b64 = arith.index_cast %bi : index to i64
  %base = llvm.inttoptr %b64 : i64 to !llvm.ptr
  %o1 = arith.addi %off, %c1 : i64
  %p = llvm.getelementptr %base[%o1] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p, %n : !llvm.ptr, i64
}

// Three texts one after another and a NUL, in a room of their own: one combine drained once.  The room and the bytes
// before the NUL.
func.func private @sba_cat(%ap: !llvm.ptr, %an: i64, %bp: !llvm.ptr, %bn: i64, %cp: !llvm.ptr, %cn: i64) -> (!llvm.ptr, i64) {
  %c1 = arith.constant 1 : i64
  %n0 = arith.addi %an, %bn : i64
  %n = arith.addi %n0, %cn : i64
  %cap = arith.addi %n, %c1 : i64
  %room = func.call @sba_room(%cap) : (i64) -> !llvm.ptr
  %a_d = func.call @sba_d(%ap, %an) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sba_d(%bp, %bn) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c_d = func.call @sba_d(%cp, %cn) : (!llvm.ptr, i64) -> !d
  %c_m = builtin.unrealized_conversion_cast %c_d : !d to !m
  %c = builtin.unrealized_conversion_cast %c_m : !m to !s
  %zg = memref.get_global @sba_zero : memref<2xi64>
  %zi = memref.extract_aligned_pointer_as_index %zg : memref<2xi64> -> index
  %z64 = arith.index_cast %zi : index to i64
  %zp = llvm.inttoptr %z64 : i64 to !llvm.ptr
  %z_d = func.call @sba_d(%zp, %c1) : (!llvm.ptr, i64) -> !d
  %z_m = builtin.unrealized_conversion_cast %z_d : !d to !m
  %nul = builtin.unrealized_conversion_cast %z_m : !m to !s
  %all = trikeshed.combine %a, %b, %c, %nul : !s, !s, !s, !s -> !s
  %rd = func.call @sba_d(%room, %cap) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %end = trikeshed.drain %all, %rm : !s, !m -> index
  return %room, %n : !llvm.ptr, i64
}

// whether the n bytes at p are the constant text at off
func.func private @sba_is(%p: !llvm.ptr, %n: i64, %off: i64) -> i1 {
  %z32 = arith.constant 0 : i32
  %lp, %ln = func.call @sba_lit(%off) : (i64) -> (!llvm.ptr, i64)
  %a_d = func.call @sba_d(%p, %n) : (!llvm.ptr, i64) -> !d
  %a_m = builtin.unrealized_conversion_cast %a_d : !d to !m
  %a = builtin.unrealized_conversion_cast %a_m : !m to !s
  %b_d = func.call @sba_d(%lp, %ln) : (!llvm.ptr, i64) -> !d
  %b_m = builtin.unrealized_conversion_cast %b_d : !d to !m
  %b = builtin.unrealized_conversion_cast %b_m : !m to !s
  %c = trikeshed.compare %a, %b unsigned : !s, !s
  %same = arith.cmpi eq, %c, %z32 : i32
  return %same : i1
}

// The store's settings (the store is the context's first word; its settings lie at 16): the store's directory, its
// physical root, and whether it only reads (a byte at 48).
func.func private @sba_settings(%c: !llvm.ptr) -> (!llvm.ptr, i64, !llvm.ptr, i64, i1) {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c64 = arith.constant 64 : i64
  %b0 = arith.constant 0 : i8
  %st = func.call @sba_w(%c, %c0) : (!llvm.ptr, i64) -> i64
  %stp = llvm.inttoptr %st : i64 to !llvm.ptr
  %settings = llvm.getelementptr %stp[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %root = llvm.getelementptr %stp[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %rop = llvm.getelementptr %stp[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %sdp, %sdn = func.call @sba_text(%settings) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %rp, %rn = func.call @sba_text(%root) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %ro8 = llvm.load %rop : !llvm.ptr -> i8
  %ro = arith.cmpi ne, %ro8, %b0 : i8
  return %sdp, %sdn, %rp, %rn, %ro : !llvm.ptr, i64, !llvm.ptr, i64, i1
}

// A content address: the constant text at off, then the hash in Nix's base 32 with its algorithm's name, in a room of
// its own.
func.func private @sba_ca(%c: !llvm.ptr, %off: i64, %h: !llvm.ptr) -> (!llvm.ptr, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %lp, %ln = func.call @sba_lit(%off) : (i64) -> (!llvm.ptr, i64)
  %tp = func.call @nixsb_hashtext(%c, %h, %c1, %c1, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
  %tn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
  %room, %n = func.call @sba_cat(%lp, %ln, %tp, %tn, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
  return %room, %n : !llvm.ptr, i64
}

// The object at `real` registered as the path: its NAR hashed, then its info written.  0, or 1 with the error kept.
func.func private @sba_register(%c: !llvm.ptr, %pp: !llvm.ptr, %pn: i64, %real: !llvm.ptr, %rn: i64, %refs: !llvm.ptr,
                                %dp: !llvm.ptr, %dn: i64, %cap: !llvm.ptr, %can: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c9 = arith.constant 9 : i64
  %nh = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %s1 = func.call @nixsb_hash(%c, %c4, %c2, %real, %rn, %nh, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  %ok = arith.cmpi eq, %s1, %c0 : i64
  %res = scf.if %ok -> (i64) {
    %size = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    %s2 = func.call @nixsb_register(%c, %pp, %pn, %nh, %size, %refs, %dp, %dn, %cap, %can) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %s2 : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

//===----------------------------------------------------------------------===//
// addToStore, addTextToStore
//===----------------------------------------------------------------------===//

// The hash a caller expects, held against the one made: 0, or 1 with the mismatch said (both in SRI form).
func.func private @sba_expected(%c: !llvm.ptr, %src: !llvm.ptr, %sn: i64, %expected: !llvm.ptr, %h: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %m1 = arith.constant -1 : i64
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %eb = llvm.ptrtoint %expected : !llvm.ptr to i64
  %given = arith.cmpi ne, %eb, %c0 : i64
  %res = scf.if %given -> (i64) {
    %same = func.call @_ZNK8nixstore4HasheqERKS0_(%expected, %h) : (!llvm.ptr, !llvm.ptr) -> i1
    %r = scf.if %same -> (i64) {
      scf.yield %c0 : i64
    } else {
      %ep = func.call @nixsb_hashtext(%c, %expected, %c3, %c1, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
      %en = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
      %gp = func.call @nixsb_hashtext(%c, %h, %c3, %c1, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
      %gn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
      %said = func.call @nixsb_say(%c, %c0, %c7, %src, %sn, %ep, %en, %gp, %gn, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %c1 : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c0 : i64
  }
  return %res : i64
}

// The object written at `real`: what is there removed, then a tree copied under the call's filter (method 1), the
// caller's bytes written (3), or a file's bytes written, to be run when its owner may run the file (0, 2); then made
// canonical.  0, or 1 with the error kept.
func.func private @sba_fill(%c: !llvm.ptr, %src: !llvm.ptr, %sn: i64, %method: i64, %filtered: i64, %real: !llvm.ptr,
                            %rn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c64 = arith.constant 64 : i64
  %rw = arith.constant 420 : i64
  %rwx = arith.constant 493 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %there = func.call @nixsb_exists(%real, %rn) : (!llvm.ptr, i64) -> i64
  %is = arith.cmpi ne, %there, %c0 : i64
  %s1 = scf.if %is -> (i64) {
    %ds = func.call @nixsb_delete(%c, %real, %rn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    scf.yield %ds : i64
  } else {
    scf.yield %c0 : i64
  }
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %s2 = scf.if %go1 -> (i64) {
    %tree = arith.cmpi eq, %method, %c1 : i64
    %r = scf.if %tree -> (i64) {
      %cs = func.call @nixsb_copy(%c, %src, %sn, %real, %rn, %filtered) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
      scf.yield %cs : i64
    } else {
      %bytes = arith.cmpi eq, %method, %c3 : i64
      %r2 = scf.if %bytes -> (i64) {
        %ws = func.call @nixsb_write(%c, %real, %rn, %src, %sn, %rw) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
        scf.yield %ws : i64
      } else {
        %srcz, %szn = func.call @sba_cat(%src, %sn, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
        %mode = func.call @nixsb_os_stat(%srcz, %cell) : (!llvm.ptr, !llvm.ptr) -> i64
        func.call @nixsb_os_free(%srcz) : (!llvm.ptr) -> ()
        %known = arith.cmpi sge, %mode, %c0 : i64
        %xbit = arith.andi %mode, %c64 : i64
        %runs0 = arith.cmpi ne, %xbit, %c0 : i64
        %runs = arith.andi %known, %runs0 : i1
        %perm = arith.select %runs, %rwx, %rw : i64
        %fs = func.call @nixsb_copyfile(%c, %src, %sn, %real, %rn, %perm) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, i64) -> i64
        scf.yield %fs : i64
      }
      scf.yield %r2 : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  %go2 = arith.cmpi eq, %s2, %c0 : i64
  %s3 = scf.if %go2 -> (i64) {
    %ks = func.call @nixsb_canon(%c, %real, %rn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    scf.yield %ks : i64
  } else {
    scf.yield %c1 : i64
  }
  return %s3 : i64
}

// The path made valid, unless the store only reads or has it: the store's directory made, the object written
// (sba_fill), its content address composed (its method's prefix and the hash), its info registered.
func.func private @sba_place(%c: !llvm.ptr, %src: !llvm.ptr, %sn: i64, %method: i64, %filtered: i64, %refs: !llvm.ptr,
                             %h: !llvm.ptr, %dp: !llvm.ptr, %dn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %o_fixedr = arith.constant 0 : i64 // lit "fixed:r:"
  %o_text = arith.constant 10 : i64 // lit "text:"
  %o_fixed = arith.constant 17 : i64 // lit "fixed:"
  %sdp, %sdn, %rp, %rn, %ro = func.call @sba_settings(%c) : (!llvm.ptr) -> (!llvm.ptr, i64, !llvm.ptr, i64, i1)
  %has = scf.if %ro -> (i1) {
    scf.yield %ro : i1
  } else {
    %v = func.call @nixsb_valid(%c, %dp, %dn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    %is = arith.cmpi ne, %v, %c0 : i64
    scf.yield %is : i1
  }
  %res = scf.if %has -> (i64) {
    scf.yield %c0 : i64
  } else {
    %real, %realn = func.call @sba_cat(%rp, %rn, %dp, %dn, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %sroot, %srootn = func.call @sba_cat(%rp, %rn, %sdp, %sdn, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %s1 = func.call @nixsb_mkdirs(%c, %sroot, %srootn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    func.call @nixsb_os_free(%sroot) : (!llvm.ptr) -> ()
    %go1 = arith.cmpi eq, %s1, %c0 : i64
    %s2 = scf.if %go1 -> (i64) {
      %fs = func.call @sba_fill(%c, %src, %sn, %method, %filtered, %real, %realn) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr, i64) -> i64
      scf.yield %fs : i64
    } else {
      scf.yield %c1 : i64
    }
    %go2 = arith.cmpi eq, %s2, %c0 : i64
    %s3 = scf.if %go2 -> (i64) {
      %tree = arith.cmpi eq, %method, %c1 : i64
      %flat = arith.cmpi eq, %method, %c0 : i64
      %off0 = arith.select %flat, %o_fixed, %o_text : i64
      %off = arith.select %tree, %o_fixedr, %off0 : i64
      %cap, %can = func.call @sba_ca(%c, %off, %h) : (!llvm.ptr, i64, !llvm.ptr) -> (!llvm.ptr, i64)
      %rs = func.call @sba_register(%c, %dp, %dn, %real, %realn, %refs, %null, %c0, %cap, %can) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      func.call @nixsb_os_free(%cap) : (!llvm.ptr) -> ()
      scf.yield %rs : i64
    } else {
      scf.yield %c1 : i64
    }
    func.call @nixsb_os_free(%real) : (!llvm.ptr) -> ()
    scf.yield %s3 : i64
  }
  return %res : i64
}

// c: the store's context; method 0 a file (its bytes' hash names it), 1 a tree (its NAR's), 2 a file as text, 3 the
// text itself (src its bytes); algo: the hash of 0 and 1; filtered: whether the context's filter is asked; refs: the
// path's references (a set); expected: the hash the caller holds it to, or none; dst: a Text the path is put at.
// 0, or 1 with the error said or kept.
func.func @nixsb_add(%c: !llvm.ptr, %name: !llvm.ptr, %nn: i64, %src: !llvm.ptr, %sn: i64, %method: i64, %algo: i64,
                     %filtered: i64, %refs: !llvm.ptr, %expected: !llvm.ptr, %dst: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c9 = arith.constant 9 : i64
  %h = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  // the hash that names the path: the method's own way of making it is its number, but a text's algorithm is SHA-256
  %bytes = arith.cmpi eq, %method, %c3 : i64
  %alg = arith.select %bytes, %c2, %algo : i64
  %s1 = func.call @nixsb_hash(%c, %method, %alg, %src, %sn, %h, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %s2 = scf.if %go1 -> (i64) {
    %es = func.call @sba_expected(%c, %src, %sn, %expected, %h) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %es : i64
  } else {
    scf.yield %c1 : i64
  }
  %go2 = arith.cmpi eq, %s2, %c0 : i64
  %s3 = scf.if %go2 -> (i64) {
    %pm = arith.select %bytes, %c2, %method : i64
    %dp = func.call @nixsb_fixedpath(%c, %name, %nn, %pm, %h, %refs, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %dn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    %named = arith.cmpi sge, %dn, %c0 : i64
    %r = scf.if %named -> (i64) {
      %ps = func.call @sba_place(%c, %src, %sn, %method, %filtered, %refs, %h, %dp, %dn) : (!llvm.ptr, !llvm.ptr, i64, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64) -> i64
      %placed = arith.cmpi eq, %ps, %c0 : i64
      scf.if %placed {
        func.call @nixsb_put(%dst, %dp, %dn) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      }
      scf.yield %ps : i64
    } else {
      scf.yield %c1 : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  return %s3 : i64
}

//===----------------------------------------------------------------------===//
// addPermRoot
//===----------------------------------------------------------------------===//

// link: where the root's link goes (what is there is replaced); the store keeps a link to it under
// <stateDir>/gcroots/auto, named by the first 32 digits of the hash of the link's absolute path.
func.func @nixsb_root(%c: !llvm.ptr, %sp: !llvm.ptr, %sn: i64, %link: !llvm.ptr, %ln: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c5 = arith.constant 5 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %m1 = arith.constant -1 : i64
  %z32 = arith.constant 0 : i32
  %slash8 = arith.constant 47 : i8
  %z = arith.constant 0 : index
  %null = llvm.mlir.zero : !llvm.ptr
  %o_auto = arith.constant 25 : i64 // lit "/gcroots/auto"
  %o_slash = arith.constant 40 : i64 // lit "/"
  %h = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %sdp, %sdn, %rp, %rn, %ro = func.call @sba_settings(%c) : (!llvm.ptr) -> (!llvm.ptr, i64, !llvm.ptr, i64, i1)
  %linkz, %lzn = func.call @sba_cat(%link, %ln, %null, %c0, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
  %real, %realn = func.call @sba_cat(%rp, %rn, %sp, %sn, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
  %u1 = func.call @unlink(%linkz) : (!llvm.ptr) -> i32
  %sl = func.call @symlink(%real, %linkz) : (!llvm.ptr, !llvm.ptr) -> i32
  func.call @nixsb_os_free(%real) : (!llvm.ptr) -> ()
  %nolink = arith.cmpi ne, %sl, %z32 : i32
  %res = scf.if %nolink -> (i64) {
    %e = func.call @nixsb_os_errno() : () -> i64
    %said = func.call @nixsb_say(%c, %c0, %c5, %link, %ln, %null, %c0, %null, %c0, %e, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %c1 : i64
  } else {
    // <stateDir>/gcroots/auto
    %st = func.call @sba_w(%c, %c0) : (!llvm.ptr, i64) -> i64
    %stp = llvm.inttoptr %st : i64 to !llvm.ptr
    %statet = llvm.getelementptr %stp[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %stdp, %stdn = func.call @sba_text(%statet) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %ap, %an = func.call @sba_lit(%o_auto) : (i64) -> (!llvm.ptr, i64)
    %dir, %dirn = func.call @sba_cat(%stdp, %stdn, %ap, %an, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
    %ms = func.call @nixsb_mkdirs(%c, %dir, %dirn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    %made = arith.cmpi eq, %ms, %c0 : i64
    %r = scf.if %made -> (i64) {
      // the link's absolute path: itself, or the directory the store runs in, "/" and it
      %some = arith.cmpi ne, %ln, %c0 : i64
      %isabs = scf.if %some -> (i1) {
        %l_d = func.call @sba_d(%link, %ln) : (!llvm.ptr, i64) -> !d
        %l_m = builtin.unrealized_conversion_cast %l_d : !d to !m
        %ls = builtin.unrealized_conversion_cast %l_m : !m to !s
        %first = trikeshed.at %ls[%z] : !s, index -> i8
        %sla = arith.cmpi eq, %first, %slash8 : i8
        scf.yield %sla : i1
      } else {
        %no = arith.constant 0 : i1
        scf.yield %no : i1
      }
      %pm = func.call @nixsb_os_pathmax() : () -> i64
      %cwd = func.call @sba_room(%pm) : (i64) -> !llvm.ptr
      %cn = scf.if %isabs -> (i64) {
        scf.yield %m1 : i64
      } else {
        %got = func.call @getcwd(%cwd, %pm) : (!llvm.ptr, i64) -> !llvm.ptr
        %gb = llvm.ptrtoint %got : !llvm.ptr to i64
        %known = arith.cmpi ne, %gb, %c0 : i64
        %n = scf.if %known -> (i64) {
          %k = func.call @strlen(%cwd) : (!llvm.ptr) -> i64
          scf.yield %k : i64
        } else {
          scf.yield %m1 : i64
        }
        scf.yield %n : i64
      }
      %rel = arith.cmpi sge, %cn, %c0 : i64
      %slp, %sln = func.call @sba_lit(%o_slash) : (i64) -> (!llvm.ptr, i64)
      %cn0 = arith.select %rel, %cn, %c0 : i64
      %sn0 = arith.select %rel, %sln, %c0 : i64
      %abs, %absn = func.call @sba_cat(%cwd, %cn0, %slp, %sn0, %link, %ln) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      func.call @nixsb_os_free(%cwd) : (!llvm.ptr) -> ()
      %hs = func.call @nixsb_hash(%c, %c3, %c2, %abs, %absn, %h, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
      %tp = func.call @nixsb_hashtext(%c, %h, %c1, %c0, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
      %tn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
      %tn32 = arith.minsi %tn, %c32 : i64
      %root, %rootn = func.call @sba_cat(%dir, %dirn, %slp, %sln, %tp, %tn32) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
      %u2 = func.call @unlink(%root) : (!llvm.ptr) -> i32
      %sl2 = func.call @symlink(%abs, %root) : (!llvm.ptr, !llvm.ptr) -> i32
      func.call @nixsb_os_free(%root) : (!llvm.ptr) -> ()
      func.call @nixsb_os_free(%abs) : (!llvm.ptr) -> ()
      scf.yield %c0 : i64
    } else {
      scf.yield %c1 : i64
    }
    func.call @nixsb_os_free(%dir) : (!llvm.ptr) -> ()
    scf.yield %r : i64
  }
  func.call @nixsb_os_free(%linkz) : (!llvm.ptr) -> ()
  return %res : i64
}

//===----------------------------------------------------------------------===//
// realise
//===----------------------------------------------------------------------===//

// The path of an output (its row of the derivation's outputs): the one it has, or, fixed with none written, the one
// its hash names (the output's name of the derivation's name, then makeFixedOutputPath).  Its bytes and length, the
// length -1 when the path cannot be named (the error kept).
func.func private @sba_outpath(%c: !llvm.ptr, %drv: !llvm.ptr, %row: !llvm.ptr) -> (!llvm.ptr, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c7 = arith.constant 7 : i64
  %c48 = arith.constant 48 : i64
  %low32 = arith.constant 4294967295 : i64
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %null = llvm.mlir.zero : !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %rd = func.call @sba_d(%row, %c7) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m64
  %rw = builtin.unrealized_conversion_cast %rm : !m64 to !s64
  %kw = trikeshed.at %rw[%i2] : !s64, index -> i64
  %pb = trikeshed.at %rw[%i3] : !s64, index -> i64
  %pw = trikeshed.at %rw[%i4] : !s64, index -> i64
  %mw = trikeshed.at %rw[%i5] : !s64, index -> i64
  %kind = arith.andi %kw, %low32 : i64
  %pn = arith.andi %pw, %low32 : i64
  %method = arith.andi %mw, %low32 : i64
  %pp = llvm.inttoptr %pb : i64 to !llvm.ptr
  %isfixed = arith.cmpi eq, %kind, %c1 : i64
  %nopath = arith.cmpi eq, %pn, %c0 : i64
  %named = arith.andi %isfixed, %nopath : i1
  %rp, %rn = scf.if %named -> (!llvm.ptr, i64) {
    %dp, %dn = func.call @sba_text(%drv) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %kp, %kn = func.call @sba_text(%row) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %n0 = arith.addi %dn, %kn : i64
    %cap = arith.addi %n0, %c2 : i64
    %room = func.call @sba_room(%cap) : (i64) -> !llvm.ptr
    %len = func.call @nixstore_ts_outputname(%dp, %dn, %kp, %kn, %room) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
    %hash = llvm.getelementptr %row[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %fp = func.call @nixsb_fixedpath(%c, %room, %len, %method, %hash, %null, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %fn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    func.call @nixsb_os_free(%room) : (!llvm.ptr) -> ()
    scf.yield %fp, %fn : !llvm.ptr, i64
  } else {
    scf.yield %pp, %pn : !llvm.ptr, i64
  }
  return %rp, %rn : !llvm.ptr, i64
}

// The outputs' paths by name, put in `outputs`: a fold over the derivation's outputs.  An output that is neither
// input-addressed (kind 0) nor fixed (1) cannot be built: 1 with that said.
func.func private @sba_outputs(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %drv: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c9 = arith.constant 9 : i64
  %c16 = arith.constant 16 : i64
  %c120 = arith.constant 120 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %orows, %on = func.call @sba_text(%outs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %oni = arith.index_cast %on : i64 to index
  %idx = trikeshed.series %oni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %res = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %ro = arith.muli %j, %c120 : i64
      %row = llvm.getelementptr %orows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %kindp = llvm.getelementptr %row[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %kw = func.call @sba_w(%kindp, %c0) : (!llvm.ptr, i64) -> i64
      %kind = arith.andi %kw, %low32 : i64
      %builds = arith.cmpi ule, %kind, %c1 : i64
      %s = scf.if %builds -> (i64) {
        %pp, %pn = func.call @sba_outpath(%c, %drv, %row) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> (!llvm.ptr, i64)
        %named = arith.cmpi sge, %pn, %c0 : i64
        %s2 = scf.if %named -> (i64) {
          %kp, %kn = func.call @sba_text(%row) : (!llvm.ptr) -> (!llvm.ptr, i64)
          func.call @nixsb_setout(%outputs, %kp, %kn, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> ()
          scf.yield %c0 : i64
        } else {
          scf.yield %c1 : i64
        }
        scf.yield %s2 : i64
      } else {
        %said = func.call @nixsb_say(%c, %c0, %c9, %drvp, %drvn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
        scf.yield %c1 : i64
      }
      scf.yield %s : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  return %res : i64
}

// Whether every path of a map of Texts is valid: a fold, each asked.
func.func private @sba_allvalid(%c: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c1 = arith.constant 1 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %prows, %pcount = func.call @sba_text(%outputs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %pci = arith.index_cast %pcount : i64 to index
  %idx = trikeshed.series %pci : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %res = trikeshed.fold %idx, %c1 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %ro = arith.muli %j, %c32 : i64
    %vo = arith.addi %ro, %c16 : i64
    %vt = llvm.getelementptr %prows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pp, %pn = func.call @sba_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %v = func.call @nixsb_valid(%c, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    %r = arith.andi %acc, %v : i64
    trikeshed.yield %r : i64
  }
  return %res : i64
}

// One input derivation realised and its outputs held against the ones the derivation takes (the row's set): a fold over
// their names, each sought among the realised outputs' rows.
func.func private @sba_input(%c: !llvm.ptr, %row: !llvm.ptr, %visiting: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c12 = arith.constant 12 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %ip, %ipn = func.call @sba_text(%row) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %got = func.call @nixsb_input(%c, %ip, %ipn, %visiting) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr) -> !llvm.ptr
  %gb = llvm.ptrtoint %got : !llvm.ptr to i64
  %built = arith.cmpi ne, %gb, %c0 : i64
  %res = scf.if %built -> (i64) {
    %rrows, %rn = func.call @sba_text(%got) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %set = llvm.getelementptr %row[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %orows, %on = func.call @sba_text(%set) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %oni = arith.index_cast %on : i64 to index
    %idx = trikeshed.series %oni : !s64 {
    ^bb0(%i: index):
      %i64 = arith.index_cast %i : index to i64
      trikeshed.yield %i64 : i64
    }
    %r = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %j: i64):
      %go = arith.cmpi eq, %acc, %c0 : i64
      %s = scf.if %go -> (i64) {
        %oo = arith.muli %j, %c16 : i64
        %ot = llvm.getelementptr %orows[%oo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %op, %opn = func.call @sba_text(%ot) : (!llvm.ptr) -> (!llvm.ptr, i64)
        %at = func.call @nixstore_ts_rowfind(%rrows, %rn, %c32, %op, %opn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
        %has = arith.cmpi sge, %at, %c0 : i64
        %s2 = scf.if %has -> (i64) {
          scf.yield %c0 : i64
        } else {
          %said = func.call @nixsb_say(%c, %c0, %c12, %ip, %ipn, %op, %opn, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
          scf.yield %c1 : i64
        }
        scf.yield %s2 : i64
      } else {
        scf.yield %acc : i64
      }
      trikeshed.yield %s : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

// The derivation's inputs: each input derivation realised (sba_input), then each source there (ensurePath): two folds.
func.func private @sba_inputs(%c: !llvm.ptr, %drv: !llvm.ptr, %visiting: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %ins = llvm.getelementptr %drv[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %irows, %in = func.call @sba_text(%ins) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %ini = arith.index_cast %in : i64 to index
  %idx = trikeshed.series %ini : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %s1 = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %ro = arith.muli %j, %c32 : i64
      %row = llvm.getelementptr %irows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %s = func.call @sba_input(%c, %row, %visiting) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %s : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  %srcs = llvm.getelementptr %drv[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %srows, %sn = func.call @sba_text(%srcs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %sni = arith.index_cast %sn : i64 to index
  %sidx = trikeshed.series %sni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %s2 = trikeshed.fold %sidx, %s1 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %so = arith.muli %j, %c16 : i64
      %t = llvm.getelementptr %srows[%so] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %sp, %spn = func.call @sba_text(%t) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %s = func.call @nixsb_ensure(%c, %sp, %spn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      scf.yield %s : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  return %s2 : i64
}

// The paths one input derivation gives (the outputs the derivation takes of it), put in the set: a fold over their
// names, each one's row sought in that derivation's outputs (SortedMap::at's error when there is none).
func.func private @sba_given(%c: !llvm.ptr, %row: !llvm.ptr, %inputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c16 = arith.constant 16 : i64
  %c27 = arith.constant 27 : i64
  %c120 = arith.constant 120 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %ip, %ipn = func.call @sba_text(%row) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %d = func.call @nixsb_drv(%c, %ip, %ipn) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
  %db = llvm.ptrtoint %d : !llvm.ptr to i64
  %read = arith.cmpi ne, %db, %c0 : i64
  %res = scf.if %read -> (i64) {
    %douts = llvm.getelementptr %d[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %drows, %dn = func.call @sba_text(%douts) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %set = llvm.getelementptr %row[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %orows, %on = func.call @sba_text(%set) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %oni = arith.index_cast %on : i64 to index
    %idx = trikeshed.series %oni : !s64 {
    ^bb0(%i: index):
      %i64 = arith.index_cast %i : index to i64
      trikeshed.yield %i64 : i64
    }
    %r = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
    ^bb0(%acc: i64, %j: i64):
      %go = arith.cmpi eq, %acc, %c0 : i64
      %s = scf.if %go -> (i64) {
        %oo = arith.muli %j, %c16 : i64
        %ot = llvm.getelementptr %orows[%oo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %op, %opn = func.call @sba_text(%ot) : (!llvm.ptr) -> (!llvm.ptr, i64)
        %at = func.call @nixstore_ts_rowfind(%drows, %dn, %c120, %op, %opn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
        %has = arith.cmpi sge, %at, %c0 : i64
        %s2 = scf.if %has -> (i64) {
          %ro = arith.muli %at, %c120 : i64
          %orow = llvm.getelementptr %drows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %pp, %pn = func.call @sba_outpath(%c, %d, %orow) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> (!llvm.ptr, i64)
          %named = arith.cmpi sge, %pn, %c0 : i64
          %s3 = scf.if %named -> (i64) {
            %put = func.call @nixsb_set(%inputs, %c3, %pp, %pn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
            scf.yield %put : i64
          } else {
            scf.yield %c1 : i64
          }
          scf.yield %s3 : i64
        } else {
          %said = func.call @nixsb_say(%c, %c1, %c27, %op, %opn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
          scf.yield %c1 : i64
        }
        scf.yield %s2 : i64
      } else {
        scf.yield %acc : i64
      }
      trikeshed.yield %s : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

// The candidates an output's references are sought among: the closure of the derivation's sources and of the paths its
// input derivations give, and the outputs themselves.  The context's sets: its 0th the inputs, its 1st the candidates.
func.func private @sba_candidates(%c: !llvm.ptr, %drv: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %c48 = arith.constant 48 : i64
  %c64 = arith.constant 64 : i64
  %inputs = llvm.getelementptr %c[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %cands = llvm.getelementptr %c[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %srcs = llvm.getelementptr %drv[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %srows, %sn = func.call @sba_text(%srcs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %sni = arith.index_cast %sn : i64 to index
  %sidx = trikeshed.series %sni : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %s0 = trikeshed.fold %sidx, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %so = arith.muli %j, %c16 : i64
    %t = llvm.getelementptr %srows[%so] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %sp, %spn = func.call @sba_text(%t) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %put = func.call @nixsb_set(%inputs, %c3, %sp, %spn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
    %r = arith.ori %acc, %put : i64
    trikeshed.yield %r : i64
  }
  %ins = llvm.getelementptr %drv[%c32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %irows, %in = func.call @sba_text(%ins) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %ini = arith.index_cast %in : i64 to index
  %idx = trikeshed.series %ini : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %s1 = trikeshed.fold %idx, %s0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %ro = arith.muli %j, %c32 : i64
      %row = llvm.getelementptr %irows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %s = func.call @sba_given(%c, %row, %inputs) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %s : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %s2 = scf.if %go1 -> (i64) {
    %cs = func.call @nixsb_closure(%c, %inputs, %cands) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %cs : i64
  } else {
    scf.yield %c1 : i64
  }
  %prows, %pcount = func.call @sba_text(%outputs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %pci = arith.index_cast %pcount : i64 to index
  %pidx = trikeshed.series %pci : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %s3 = trikeshed.fold %pidx, %s2 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %ro = arith.muli %j, %c32 : i64
      %vo = arith.addi %ro, %c16 : i64
      %vt = llvm.getelementptr %prows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %pp, %pn = func.call @sba_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %put = func.call @nixsb_set(%cands, %c3, %pp, %pn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
      scf.yield %put : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  return %s3 : i64
}

// A fixed output held against its hash: the object's hash made as the output's method says (a tree's NAR's, or a
// file's), with the hash's algorithm.  0 when it is the hash; else the object removed and the mismatch said.
func.func private @sba_fixed(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %orow: !llvm.ptr, %real: !llvm.ptr, %rn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c9 = arith.constant 9 : i64
  %c15 = arith.constant 15 : i64
  %c48 = arith.constant 48 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %got = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %mw = func.call @sba_w(%orow, %c5) : (!llvm.ptr, i64) -> i64
  %aw = func.call @sba_w(%orow, %c6) : (!llvm.ptr, i64) -> i64
  %method = arith.andi %mw, %low32 : i64
  %algo = arith.andi %aw, %low32 : i64
  %hash = llvm.getelementptr %orow[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %tree = arith.cmpi eq, %method, %c1 : i64
  %how = arith.select %tree, %c4, %c0 : i64
  %s1 = func.call @nixsb_hash(%c, %how, %algo, %real, %rn, %got, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %res = scf.if %go1 -> (i64) {
    %same = func.call @_ZNK8nixstore4HasheqERKS0_(%got, %hash) : (!llvm.ptr, !llvm.ptr) -> i1
    %r = scf.if %same -> (i64) {
      scf.yield %c0 : i64
    } else {
      %ds = func.call @nixsb_delete(%c, %real, %rn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
      %gone = arith.cmpi eq, %ds, %c0 : i64
      scf.if %gone {
        %sp = func.call @nixsb_hashtext(%c, %hash, %c3, %c1, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
        %sn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
        %gp = func.call @nixsb_hashtext(%c, %got, %c3, %c1, %cell) : (!llvm.ptr, !llvm.ptr, i64, i64, !llvm.ptr) -> !llvm.ptr
        %gn = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
        %said = func.call @nixsb_say(%c, %c0, %c15, %drvp, %drvn, %sp, %sn, %gp, %gn, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      }
      scf.yield %c1 : i64
    }
    scf.yield %r : i64
  } else {
    scf.yield %c1 : i64
  }
  return %res : i64
}

// One output after its builder: it must be there; made canonical; held against its hash when it is fixed; its NAR
// hashed; its references the candidates found in it (none sought for a fixed one); its content address the hash's when
// it is fixed; registered with the derivation as its deriver.  The context's 2nd set holds the references.
func.func private @sba_finish(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %drv: !llvm.ptr, %np: !llvm.ptr, %nn: i64,
                              %pp: !llvm.ptr, %pn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c5 = arith.constant 5 : i64
  %c14 = arith.constant 14 : i64
  %c16 = arith.constant 16 : i64
  %c27 = arith.constant 27 : i64
  %c48 = arith.constant 48 : i64
  %c64 = arith.constant 64 : i64
  %c80 = arith.constant 80 : i64
  %c120 = arith.constant 120 : i64
  %low32 = arith.constant 4294967295 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %o_fixedr = arith.constant 0 : i64 // lit "fixed:r:"
  %o_fixed = arith.constant 17 : i64 // lit "fixed:"
  %sdp, %sdn, %rp, %rn, %ro = func.call @sba_settings(%c) : (!llvm.ptr) -> (!llvm.ptr, i64, !llvm.ptr, i64, i1)
  %real, %realn = func.call @sba_cat(%rp, %rn, %pp, %pn, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> (!llvm.ptr, i64)
  %there = func.call @nixsb_exists(%real, %realn) : (!llvm.ptr, i64) -> i64
  %is = arith.cmpi ne, %there, %c0 : i64
  %res = scf.if %is -> (i64) {
    %s1 = func.call @nixsb_canon(%c, %real, %realn) : (!llvm.ptr, !llvm.ptr, i64) -> i64
    %outs = llvm.getelementptr %drv[%c16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %orows, %on = func.call @sba_text(%outs) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %go1 = arith.cmpi eq, %s1, %c0 : i64
    %at = scf.if %go1 -> (i64) {
      %i = func.call @nixstore_ts_rowfind(%orows, %on, %c120, %np, %nn) : (!llvm.ptr, i64, i64, !llvm.ptr, i64) -> i64
      %none = arith.cmpi slt, %i, %c0 : i64
      scf.if %none {
        %said = func.call @nixsb_say(%c, %c1, %c27, %np, %nn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      }
      scf.yield %i : i64
    } else {
      scf.yield %m1 : i64
    }
    %go2 = arith.cmpi sge, %at, %c0 : i64
    %r = scf.if %go2 -> (i64) {
      %ro2 = arith.muli %at, %c120 : i64
      %orow = llvm.getelementptr %orows[%ro2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %kw = func.call @sba_w(%orow, %c2) : (!llvm.ptr, i64) -> i64
      %kind = arith.andi %kw, %low32 : i64
      %fixed = arith.cmpi eq, %kind, %c1 : i64
      %s2 = scf.if %fixed -> (i64) {
        %fs = func.call @sba_fixed(%c, %drvp, %drvn, %orow, %real, %realn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64) -> i64
        scf.yield %fs : i64
      } else {
        scf.yield %c0 : i64
      }
      %go3 = arith.cmpi eq, %s2, %c0 : i64
      %s3 = scf.if %go3 -> (i64) {
        %s4 = scf.if %fixed -> (i64) {
          %mw = func.call @sba_w(%orow, %c5) : (!llvm.ptr, i64) -> i64
          %method = arith.andi %mw, %low32 : i64
          %tree = arith.cmpi eq, %method, %c1 : i64
          %off = arith.select %tree, %o_fixedr, %o_fixed : i64
          %hash = llvm.getelementptr %orow[%c48] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %cap, %can = func.call @sba_ca(%c, %off, %hash) : (!llvm.ptr, i64, !llvm.ptr) -> (!llvm.ptr, i64)
          %rs = func.call @sba_register(%c, %pp, %pn, %real, %realn, %null, %drvp, %drvn, %cap, %can) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
          func.call @nixsb_os_free(%cap) : (!llvm.ptr) -> ()
          scf.yield %rs : i64
        } else {
          // the info is the NAR's hash, then the references: sba_register hashes first, so the scan follows it there
          %rs = func.call @sba_scanned(%c, %drvp, %drvn, %pp, %pn, %real, %realn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
          scf.yield %rs : i64
        }
        scf.yield %s4 : i64
      } else {
        scf.yield %c1 : i64
      }
      scf.yield %s3 : i64
    } else {
      scf.yield %c1 : i64
    }
    scf.yield %r : i64
  } else {
    %said = func.call @nixsb_say(%c, %c0, %c14, %drvp, %drvn, %np, %nn, %pp, %pn, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %c1 : i64
  }
  func.call @nixsb_os_free(%real) : (!llvm.ptr) -> ()
  return %res : i64
}

// An output that is not fixed registered: its NAR hashed, then the candidates (the context's 1st set) sought in it,
// those found the context's 2nd set (emptied first), then its info written with no content address.
func.func private @sba_scanned(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %pp: !llvm.ptr, %pn: i64, %real: !llvm.ptr,
                               %rn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c4 = arith.constant 4 : i64
  %c9 = arith.constant 9 : i64
  %c64 = arith.constant 64 : i64
  %c80 = arith.constant 80 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %nh = llvm.alloca %c9 x i64 : (i64) -> !llvm.ptr
  %cell = llvm.alloca %c1 x i64 : (i64) -> !llvm.ptr
  %cands = llvm.getelementptr %c[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %refs = llvm.getelementptr %c[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %s1 = func.call @nixsb_hash(%c, %c4, %c2, %real, %rn, %nh, %cell) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %s2 = scf.if %go1 -> (i64) {
    %e = func.call @nixsb_set(%refs, %c2, %null, %c0) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
    %crows, %cn = func.call @sba_text(%cands) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %ss = func.call @nixsb_refs(%c, %real, %rn, %crows, %cn, %refs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %ss : i64
  } else {
    scf.yield %c1 : i64
  }
  %go2 = arith.cmpi eq, %s2, %c0 : i64
  %s3 = scf.if %go2 -> (i64) {
    %size = func.call @sba_w(%cell, %c0) : (!llvm.ptr, i64) -> i64
    %rs = func.call @nixsb_register(%c, %pp, %pn, %nh, %size, %refs, %drvp, %drvn, %null, %c0) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
    scf.yield %rs : i64
  } else {
    scf.yield %c1 : i64
  }
  return %s3 : i64
}

// Every output after the builder (sba_finish): a fold over the outputs' paths by name.
func.func private @sba_finished(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %drv: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c16 = arith.constant 16 : i64
  %c32 = arith.constant 32 : i64
  %prows, %pcount = func.call @sba_text(%outputs) : (!llvm.ptr) -> (!llvm.ptr, i64)
  %pci = arith.index_cast %pcount : i64 to index
  %idx = trikeshed.series %pci : !s64 {
  ^bb0(%i: index):
    %i64 = arith.index_cast %i : index to i64
    trikeshed.yield %i64 : i64
  }
  %res = trikeshed.fold %idx, %c0 : !s64, i64 -> i64 {
  ^bb0(%acc: i64, %j: i64):
    %go = arith.cmpi eq, %acc, %c0 : i64
    %r = scf.if %go -> (i64) {
      %ro = arith.muli %j, %c32 : i64
      %vo = arith.addi %ro, %c16 : i64
      %kt = llvm.getelementptr %prows[%ro] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %vt = llvm.getelementptr %prows[%vo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %np, %nn = func.call @sba_text(%kt) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %pp, %pn = func.call @sba_text(%vt) : (!llvm.ptr) -> (!llvm.ptr, i64)
      %s = func.call @sba_finish(%c, %drvp, %drvn, %drv, %np, %nn, %pp, %pn) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, i64) -> i64
      scf.yield %s : i64
    } else {
      scf.yield %acc : i64
    }
    trikeshed.yield %r : i64
  }
  return %res : i64
}

// The build of a derivation whose outputs are not all valid: refused where the store only reads or is not where its
// paths say; else the inputs realised, the building said, the builder run (builtin:fetchurl is the store's own), the
// candidates made, the outputs finished.
func.func private @sba_build(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %drv: !llvm.ptr, %visiting: !llvm.ptr,
                             %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c10 = arith.constant 10 : i64
  %c11 = arith.constant 11 : i64
  %c13 = arith.constant 13 : i64
  %c80 = arith.constant 80 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %o_fetchurl = arith.constant 43 : i64 // lit "builtin:fetchurl"
  %sdp, %sdn, %rp, %rn, %ro = func.call @sba_settings(%c) : (!llvm.ptr) -> (!llvm.ptr, i64, !llvm.ptr, i64, i1)
  %s0 = scf.if %ro -> (i64) {
    %said = func.call @nixsb_say(%c, %c0, %c10, %drvp, %drvn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %c1 : i64
  } else {
    %chroot = arith.cmpi ne, %rn, %c0 : i64
    %r = scf.if %chroot -> (i64) {
      %said = func.call @nixsb_say(%c, %c0, %c11, %drvp, %drvn, %sdp, %sdn, %rp, %rn, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
      scf.yield %c1 : i64
    } else {
      scf.yield %c0 : i64
    }
    scf.yield %r : i64
  }
  %go0 = arith.cmpi eq, %s0, %c0 : i64
  %s1 = scf.if %go0 -> (i64) {
    %is = func.call @sba_inputs(%c, %drv, %visiting) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %is : i64
  } else {
    scf.yield %c1 : i64
  }
  %go1 = arith.cmpi eq, %s1, %c0 : i64
  %s2 = scf.if %go1 -> (i64) {
    %line = func.call @nixsb_say(%c, %c2, %c13, %drvp, %drvn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    %bt = llvm.getelementptr %drv[%c80] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %bp, %bn = func.call @sba_text(%bt) : (!llvm.ptr) -> (!llvm.ptr, i64)
    %own = func.call @sba_is(%bp, %bn, %o_fetchurl) : (!llvm.ptr, i64, i64) -> i1
    %bs = scf.if %own -> (i64) {
      %fs = func.call @nixsb_fetch(%c, %drv, %outputs) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %fs : i64
    } else {
      %rs = func.call @nixsb_build(%c, %drvp, %drvn, %drv, %outputs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %rs : i64
    }
    scf.yield %bs : i64
  } else {
    scf.yield %c1 : i64
  }
  %go2 = arith.cmpi eq, %s2, %c0 : i64
  %s3 = scf.if %go2 -> (i64) {
    %cs = func.call @sba_candidates(%c, %drv, %outputs) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %cs : i64
  } else {
    scf.yield %c1 : i64
  }
  %go3 = arith.cmpi eq, %s3, %c0 : i64
  %s4 = scf.if %go3 -> (i64) {
    %fs = func.call @sba_finished(%c, %drvp, %drvn, %drv, %outputs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
    scf.yield %fs : i64
  } else {
    scf.yield %c1 : i64
  }
  return %s4 : i64
}

// c: the store's context; visiting: the derivations being realised above this one (a set: a derivation met again is a
// cycle); outputs: a map the outputs' paths are put in by name.  0, or 1 with the error said or kept; the derivation
// stays in `visiting` then.
func.func @nixsb_realise(%c: !llvm.ptr, %drvp: !llvm.ptr, %drvn: i64, %visiting: !llvm.ptr, %outputs: !llvm.ptr) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %m1 = arith.constant -1 : i64
  %null = llvm.mlir.zero : !llvm.ptr
  %new = func.call @nixsb_set(%visiting, %c0, %drvp, %drvn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
  %fresh = arith.cmpi ne, %new, %c0 : i64
  %res = scf.if %fresh -> (i64) {
    %drv = func.call @nixsb_drv(%c, %drvp, %drvn) : (!llvm.ptr, !llvm.ptr, i64) -> !llvm.ptr
    %db = llvm.ptrtoint %drv : !llvm.ptr to i64
    %read = arith.cmpi ne, %db, %c0 : i64
    %s1 = scf.if %read -> (i64) {
      %os = func.call @sba_outputs(%c, %drvp, %drvn, %drv, %outputs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> i64
      scf.yield %os : i64
    } else {
      scf.yield %c1 : i64
    }
    %go1 = arith.cmpi eq, %s1, %c0 : i64
    %s2 = scf.if %go1 -> (i64) {
      %valid = func.call @sba_allvalid(%c, %outputs) : (!llvm.ptr, !llvm.ptr) -> i64
      %all = arith.cmpi ne, %valid, %c0 : i64
      %r = scf.if %all -> (i64) {
        scf.yield %c0 : i64
      } else {
        %bs = func.call @sba_build(%c, %drvp, %drvn, %drv, %visiting, %outputs) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
        scf.yield %bs : i64
      }
      scf.yield %r : i64
    } else {
      scf.yield %c1 : i64
    }
    %done = arith.cmpi eq, %s2, %c0 : i64
    scf.if %done {
      %left = func.call @nixsb_set(%visiting, %c1, %drvp, %drvn) : (!llvm.ptr, i64, !llvm.ptr, i64) -> i64
    }
    scf.yield %s2 : i64
  } else {
    %said = func.call @nixsb_say(%c, %c0, %c8, %drvp, %drvn, %null, %c0, %null, %c0, %m1, %c0) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr, i64, !llvm.ptr, i64, i64, i64) -> i64
    scf.yield %c1 : i64
  }
  return %res : i64
}
