// The crit-bit (Patricia) trie of include/Composite/Patricia.h, in TrikeShed forms.  The leaf walk (one bit tested per node),
// the key compare at the leaf it reaches, set's plan (the first byte where the key and that leaf differ, the highest differing
// bit as the mask of the other bits, the new node's direction, the descent to the first node whose bit comes after it), the
// link of the new node, and prefix's descent, prefix check and byte-order subtree walk.  The walks are scf.while over the
// node and row words; every read of a record is trikeshed.at over a series, every write a drain into a memref slice.
// Patricia.h keeps what is generic in V: the Row/Node storage (MutableSeries, grown by the bridge), the value, copy, emit.
//
// The caller's arrays, read where they lie (the entries allocate nothing and never see a V).  Each entry builds its
// descriptors ONCE (pat_desc: pointer and length, the hand-off the ABI accepts), and the helpers view them as series:
//   nodes  Node {u32 child[2]; u32 byte; u32 other} = 16 bytes = four u32 words: word 4p+d the child on side d (a node's
//          index, or a row's index | kLeaf), 4p+2 the tested byte, 4p+3 the bit mask of the other bits.
//   rows   Row {const char *key; u32 len; V v}, rs bytes apart (rs a multiple of 8): the key pointer is the i64 word
//          i*rs/8, the len the u32 word i*rs/4 + 2.
//   k, n   the query key, read as if a 0 byte followed it (no key holds a 0 byte): pat_keybyte guards the end.
// A node's side for a key is (1 + (other | byte)) >> 8: other is the node's bit cleared out of 0xFF, so the sum carries into
// bit 8 exactly when the key has that bit.  Indices and bytes compare unsigned, as the C++'s uint32_t / uint8_t.
// Descriptor bounds are the index space the 31-bit encoding allows (a node or row index is below kLeaf = 2^31); at has no
// bounds check, so a walk reads exactly what the trie wrote, as the C++ did.
//
// Helper names are module-unique (pat_*): the pipeline exports func.func private as global symbols.
!s8 = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!s64 = !trikeshed.series<i64>
!m8 = memref<?xi8, strided<[1], offset: ?>>
!m32 = memref<?xi32, strided<[1], offset: ?>>
!m64 = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the descriptor of n elements at p (a struct: returning it clones nothing; the element type is the memref it is cast to)
func.func private @pat_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the entries' views of the node words, the row words (i64 and u32) and the u32 cells (stack, out): the index bounds
func.func private @pat_nodes(%nodes: !llvm.ptr) -> !d {
  %bound = arith.constant 8589934592 : i64
  %d = func.call @pat_desc(%nodes, %bound) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

func.func private @pat_rows64(%rows: !llvm.ptr, %rs: i64) -> !d {
  %c3 = arith.constant 3 : i64
  %c31 = arith.constant 2147483648 : i64
  %rs8 = arith.shrui %rs, %c3 : i64
  %bound = arith.muli %rs8, %c31 : i64
  %d = func.call @pat_desc(%rows, %bound) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

func.func private @pat_rows32(%rows: !llvm.ptr, %rs: i64) -> !d {
  %c2 = arith.constant 2 : i64
  %c31 = arith.constant 2147483648 : i64
  %rs4 = arith.shrui %rs, %c2 : i64
  %bound = arith.muli %rs4, %c31 : i64
  %d = func.call @pat_desc(%rows, %bound) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

func.func private @pat_cells(%p: !llvm.ptr) -> !d {
  %bound = arith.constant 4294967296 : i64
  %d = func.call @pat_desc(%p, %bound) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

// word i of the u32 / u64 words at d (at: no bounds check)
func.func private @pat_w32(%d: !d, %i: i64) -> i32 {
  %m = builtin.unrealized_conversion_cast %d : !d to !m32
  %s = trikeshed.text %m : !m32 -> !s32
  %ix = arith.index_cast %i : i64 to index
  %w = trikeshed.at %s[%ix] : !s32, index -> i32
  return %w : i32
}

func.func private @pat_w64(%d: !d, %i: i64) -> i64 {
  %m = builtin.unrealized_conversion_cast %d : !d to !m64
  %s = trikeshed.text %m : !m64 -> !s64
  %ix = arith.index_cast %i : i64 to index
  %w = trikeshed.at %s[%ix] : !s64, index -> i64
  return %w : i64
}

// the key's byte i (unsigned), or the 0 that follows it: the key is n bytes at d
func.func private @pat_keybyte(%d: !d, %n: i64, %i: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %i64 = arith.extui %i : i32 to i64
  %in = arith.cmpi ult, %i64, %n : i64
  %r = scf.if %in -> i32 {
    %m = builtin.unrealized_conversion_cast %d : !d to !m8
    %s = trikeshed.text %m : !m8 -> !s8
    %ix = arith.index_cast %i64 : i64 to index
    %b = trikeshed.at %s[%ix] : !s8, index -> i8
    %w = arith.extui %b : i8 to i32
    scf.yield %w : i32
  } else {
    scf.yield %c0 : i32
  }
  return %r : i32
}

// node p's tested byte and other mask
func.func private @pat_node(%nd: !d, %p: i32) -> (i32, i32) {
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %p64 = arith.extui %p : i32 to i64
  %base = arith.muli %p64, %c4 : i64
  %wb = arith.addi %base, %c2 : i64
  %byte = func.call @pat_w32(%nd, %wb) : (!d, i64) -> i32
  %wo = arith.addi %base, %c3 : i64
  %other = func.call @pat_w32(%nd, %wo) : (!d, i64) -> i32
  return %byte, %other : i32, i32
}

// the child of node p on side d (a node's index, or a row's index | kLeaf)
func.func private @pat_child(%nd: !d, %p: i32, %d: i32) -> i32 {
  %c4 = arith.constant 4 : i64
  %p64 = arith.extui %p : i32 to i64
  %d64 = arith.extui %d : i32 to i64
  %base = arith.muli %p64, %c4 : i64
  %w = arith.addi %base, %d64 : i64
  %q = func.call @pat_w32(%nd, %w) : (!d, i64) -> i32
  return %q : i32
}

// (1 + (other | byte)) >> 8
func.func private @pat_dir(%other: i32, %byte: i32) -> i32 {
  %c1 = arith.constant 1 : i32
  %c8 = arith.constant 8 : i32
  %o = arith.ori %other, %byte : i32
  %s = arith.addi %o, %c1 : i32
  %d = arith.shrui %s, %c8 : i32
  return %d : i32
}

// the side the key takes at node p, and the child there
func.func private @pat_step(%nd: !d, %p: i32, %kd: !d, %n: i64) -> (i32, i32) {
  %byte, %other = func.call @pat_node(%nd, %p) : (!d, i32) -> (i32, i32)
  %kb = func.call @pat_keybyte(%kd, %n, %byte) : (!d, i64, i32) -> i32
  %dir = func.call @pat_dir(%other, %kb) : (i32, i32) -> i32
  %q = func.call @pat_child(%nd, %p, %dir) : (!d, i32, i32) -> i32
  return %dir, %q : i32, i32
}

func.func private @pat_isnode(%p: i32) -> i1 {
  %c0 = arith.constant 0 : i32
  %leaf = arith.constant 0x80000000 : i32
  %t = arith.andi %p, %leaf : i32
  %r = arith.cmpi eq, %t, %c0 : i32
  return %r : i1
}

// leafOf(k, n): down from the root by the key's bits to the row it reaches
func.func private @pat_leaf(%nd: !d, %root: i32, %kd: !d, %n: i64) -> i32 {
  %mask = arith.constant 0x7FFFFFFF : i32
  %r = scf.while (%p = %root) : (i32) -> i32 {
    %go = func.call @pat_isnode(%p) : (i32) -> i1
    scf.condition(%go) %p : i32
  } do {
  ^bb0(%pl: i32):
    %dl, %ql = func.call @pat_step(%nd, %pl, %kd, %n) : (!d, i32, !d, i64) -> (i32, i32)
    scf.yield %ql : i32
  }
  %row = arith.andi %r, %mask : i32
  return %row : i32
}

// row i's key pointer and length (rs = the row's stride in bytes)
func.func private @pat_row(%r64: !d, %r32: !d, %rs: i64, %i: i32) -> (!llvm.ptr, i32) {
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %i64 = arith.extui %i : i32 to i64
  %rs8 = arith.shrui %rs, %c3 : i64
  %rs4 = arith.shrui %rs, %c2 : i64
  %kw = arith.muli %i64, %rs8 : i64
  %kbits = func.call @pat_w64(%r64, %kw) : (!d, i64) -> i64
  %lw0 = arith.muli %i64, %rs4 : i64
  %lw = arith.addi %lw0, %c2 : i64
  %len = func.call @pat_w32(%r32, %lw) : (!d, i64) -> i32
  %kp = llvm.inttoptr %kbits : i64 to !llvm.ptr
  return %kp, %len : !llvm.ptr, i32
}

// compare(row key kp[0, kn) with the key kd) unsigned: the trikeshed series order, 0 when the two are the same bytes
func.func private @pat_cmp(%kp: !llvm.ptr, %kn: i32, %kd: !d) -> i32 {
  %kn64 = arith.extui %kn : i32 to i64
  %rd = func.call @pat_desc(%kp, %kn64) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m8
  %rs = trikeshed.text %rm : !m8 -> !s8
  %km = builtin.unrealized_conversion_cast %kd : !d to !m8
  %ks = trikeshed.text %km : !m8 -> !s8
  %o = trikeshed.compare %rs, %ks unsigned : !s8, !s8
  return %o : i32
}

// the cell i of the u32 cells at d takes v (one drain of a one-element series into a slice of the cells)
func.func private @pat_put1(%d: !d, %i: i64, %v: i32) {
  %c1 = arith.constant 1 : index
  %m = builtin.unrealized_conversion_cast %d : !d to !m32
  %ix = arith.index_cast %i : i64 to index
  %sub = memref.subview %m[%ix] [1] [1] : !m32 to memref<1xi32, strided<[1], offset: ?>>
  %s0 = trikeshed.series %c1 : !s32 {
  ^bb0(%k0: index):
    trikeshed.yield %v : i32
  }
  %all = trikeshed.combine %s0 : !s32 -> !s32
  %e = trikeshed.drain %all, %sub : !s32, memref<1xi32, strided<[1], offset: ?>> -> index
  return
}

// the cells i and i + 1 of the u32 cells at d take v0 and v1 (one drain)
func.func private @pat_put2(%d: !d, %i: i64, %v0: i32, %v1: i32) {
  %c1 = arith.constant 1 : index
  %m = builtin.unrealized_conversion_cast %d : !d to !m32
  %ix = arith.index_cast %i : i64 to index
  %sub = memref.subview %m[%ix] [2] [1] : !m32 to memref<2xi32, strided<[1], offset: ?>>
  %s0 = trikeshed.series %c1 : !s32 {
  ^bb0(%k0: index):
    trikeshed.yield %v0 : i32
  }
  %s1 = trikeshed.series %c1 : !s32 {
  ^bb0(%k1: index):
    trikeshed.yield %v1 : i32
  }
  %all = trikeshed.combine %s0, %s1 : !s32, !s32 -> !s32
  %e = trikeshed.drain %all, %sub : !s32, memref<2xi32, strided<[1], offset: ?>> -> index
  return
}

// find: the row the key reaches, if its key is the key; else 0xFFFFFFFF.  The trie is not empty.
func.func @mlnix_patricia_find(%nodes: !llvm.ptr, %rows: !llvm.ptr, %rs: i64, %root: i32, %k: !llvm.ptr, %n: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %none = arith.constant -1 : i32
  %n64 = arith.extui %n : i32 to i64
  %nd = func.call @pat_nodes(%nodes) : (!llvm.ptr) -> !d
  %r64 = func.call @pat_rows64(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %r32 = func.call @pat_rows32(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %kd = func.call @pat_desc(%k, %n64) : (!llvm.ptr, i64) -> !d
  %bi = func.call @pat_leaf(%nd, %root, %kd, %n64) : (!d, i32, !d, i64) -> i32
  %bkp, %blen = func.call @pat_row(%r64, %r32, %rs, %bi) : (!d, !d, i64, i32) -> (!llvm.ptr, i32)
  %o = func.call @pat_cmp(%bkp, %blen, %kd) : (!llvm.ptr, i32, !d) -> i32
  %eq = arith.cmpi eq, %o, %c0 : i32
  %r = arith.select %eq, %bi, %none : i32
  return %r : i32
}

// set's plan.  The trie is not empty.  0: the key is stored at row plan[0] (the bridge replaces the value).  1: the key
// is new; plan = {leaf, byte b, other, dir, parent, side, p}: the new node tests bit `other` of byte b, the new row goes
// on side dir, and the node takes the place of p (parent's child on `side`, or the root when parent is 0xFFFFFFFF).
// The seven words are composed once and drained once in both cases; for a stored key only plan[0] is meaningful.
func.func @mlnix_patricia_set(%nodes: !llvm.ptr, %rows: !llvm.ptr, %rs: i64, %root: i32, %k: !llvm.ptr, %n: i32, %plan: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c4 = arith.constant 4 : i32
  %cff = arith.constant 255 : i32
  %none = arith.constant -1 : i32
  %n64 = arith.extui %n : i32 to i64
  %nd = func.call @pat_nodes(%nodes) : (!llvm.ptr) -> !d
  %r64 = func.call @pat_rows64(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %r32 = func.call @pat_rows32(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %kd = func.call @pat_desc(%k, %n64) : (!llvm.ptr, i64) -> !d
  %bi = func.call @pat_leaf(%nd, %root, %kd, %n64) : (!d, i32, !d, i64) -> i32
  %bkp, %blen = func.call @pat_row(%r64, %r32, %rs, %bi) : (!d, !d, i64, i32) -> (!llvm.ptr, i32)
  %blen64 = arith.extui %blen : i32 to i64
  %bkd = func.call @pat_desc(%bkp, %blen64) : (!llvm.ptr, i64) -> !d
  // the first byte b <= max(n, len) where the two differ (the 0 past either end counts), and x their xor there
  %m = arith.maxui %n, %blen : i32
  %scan:2 = scf.while (%b = %c0, %x = %c0) : (i32, i32) -> (i32, i32) {
    %in = arith.cmpi ule, %b, %m : i32
    %same = arith.cmpi eq, %x, %c0 : i32
    %go = arith.andi %in, %same : i1
    scf.condition(%go) %b, %x : i32, i32
  } do {
  ^bb0(%bs: i32, %xs: i32):
    %kb = func.call @pat_keybyte(%kd, %n64, %bs) : (!d, i64, i32) -> i32
    %lb = func.call @pat_keybyte(%bkd, %blen64, %bs) : (!d, i64, i32) -> i32
    %nx = arith.xori %kb, %lb : i32
    %hit = arith.cmpi ne, %nx, %c0 : i32
    %b1 = arith.addi %bs, %c1 : i32
    %nb = arith.select %hit, %bs, %b1 : i32
    scf.yield %nb, %nx : i32, i32
  }
  %exact = arith.cmpi eq, %scan#1, %c0 : i32
  %vals:7 = scf.if %exact -> (i32, i32, i32, i32, i32, i32, i32) {
    scf.yield %bi, %c0, %c0, %c0, %c0, %c0, %c0 : i32, i32, i32, i32, i32, i32, i32
  } else {
    // the highest bit that differs, as the mask of the other bits
    %s1 = arith.shrui %scan#1, %c1 : i32
    %x1 = arith.ori %scan#1, %s1 : i32
    %s2 = arith.shrui %x1, %c2 : i32
    %x2 = arith.ori %x1, %s2 : i32
    %s4 = arith.shrui %x2, %c4 : i32
    %x4 = arith.ori %x2, %s4 : i32
    %h = arith.shrui %x4, %c1 : i32
    %nh = arith.xori %h, %none : i32
    %top = arith.andi %x4, %nh : i32
    %other = arith.xori %top, %cff : i32
    %kbit = func.call @pat_keybyte(%kd, %n64, %scan#0) : (!d, i64, i32) -> i32
    %dir = func.call @pat_dir(%other, %kbit) : (i32, i32) -> i32
    // down from the root to the first node whose bit comes after the new one (a later byte, or a lower bit of the
    // same byte): the new node takes its place
    %false = arith.constant 0 : i1
    %true = arith.constant 1 : i1
    %walk:3 = scf.while (%parent = %none, %side = %c0, %p = %root) : (i32, i32, i32) -> (i32, i32, i32) {
      %isn = func.call @pat_isnode(%p) : (i32) -> i1
      %go = scf.if %isn -> i1 {
        %qb, %qo = func.call @pat_node(%nd, %p) : (!d, i32) -> (i32, i32)
        %later = arith.cmpi ugt, %qb, %scan#0 : i32
        %sameb = arith.cmpi eq, %qb, %scan#0 : i32
        %lower = arith.cmpi ugt, %qo, %other : i32
        %lowsame = arith.andi %sameb, %lower : i1
        %stop = arith.ori %later, %lowsame : i1
        %cont = arith.xori %stop, %true : i1
        scf.yield %cont : i1
      } else {
        scf.yield %false : i1
      }
      scf.condition(%go) %parent, %side, %p : i32, i32, i32
    } do {
    ^bb0(%wparent: i32, %wside: i32, %wp: i32):
      %wd, %wq = func.call @pat_step(%nd, %wp, %kd, %n64) : (!d, i32, !d, i64) -> (i32, i32)
      scf.yield %wp, %wd, %wq : i32, i32, i32
    }
    scf.yield %bi, %scan#0, %other, %dir, %walk#0, %walk#1, %walk#2 : i32, i32, i32, i32, i32, i32, i32
  }
  // the plan record: seven one-element series combined and drained once into the bridge's seven words
  %c1x = arith.constant 1 : index
  %c7 = arith.constant 7 : i64
  %pd = func.call @pat_desc(%plan, %c7) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m32
  %p0 = trikeshed.series %c1x : !s32 {
  ^bb0(%j0: index):
    trikeshed.yield %vals#0 : i32
  }
  %p1 = trikeshed.series %c1x : !s32 {
  ^bb0(%j1: index):
    trikeshed.yield %vals#1 : i32
  }
  %p2 = trikeshed.series %c1x : !s32 {
  ^bb0(%j2: index):
    trikeshed.yield %vals#2 : i32
  }
  %p3 = trikeshed.series %c1x : !s32 {
  ^bb0(%j3: index):
    trikeshed.yield %vals#3 : i32
  }
  %p4 = trikeshed.series %c1x : !s32 {
  ^bb0(%j4: index):
    trikeshed.yield %vals#4 : i32
  }
  %p5 = trikeshed.series %c1x : !s32 {
  ^bb0(%j5: index):
    trikeshed.yield %vals#5 : i32
  }
  %p6 = trikeshed.series %c1x : !s32 {
  ^bb0(%j6: index):
    trikeshed.yield %vals#6 : i32
  }
  %plan7 = trikeshed.combine %p0, %p1, %p2, %p3, %p4, %p5, %p6 : !s32, !s32, !s32, !s32, !s32, !s32, !s32 -> !s32
  %pe = trikeshed.drain %plan7, %pm : !s32, !m32 -> index
  %mode = arith.select %exact, %c0, %c1 : i32
  return %mode : i32
}

// set's link: node ni (appended by the bridge) tests bit `other` of byte b, row ri on side dir and p on the other; it
// takes p's place.  The answer is the root.  The new node's four words are one drain into its slot.
func.func @mlnix_patricia_link(%nodes: !llvm.ptr, %ni: i32, %root: i32, %ri: i32, %plan: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %leaf = arith.constant 0x80000000 : i32
  %none = arith.constant -1 : i32
  %i1 = arith.constant 1 : index
  %i2 = arith.constant 2 : index
  %i3 = arith.constant 3 : index
  %i4 = arith.constant 4 : index
  %i5 = arith.constant 5 : index
  %i6 = arith.constant 6 : index
  %c1x4 = arith.constant 1 : index
  %c4x = arith.constant 4 : i64
  %c7l = arith.constant 7 : i64
  %pd = func.call @pat_desc(%plan, %c7l) : (!llvm.ptr, i64) -> !d
  %pm = builtin.unrealized_conversion_cast %pd : !d to !m32
  %ps = trikeshed.text %pm : !m32 -> !s32
  %b = trikeshed.at %ps[%i1] : !s32, index -> i32
  %other = trikeshed.at %ps[%i2] : !s32, index -> i32
  %dir = trikeshed.at %ps[%i3] : !s32, index -> i32
  %parent = trikeshed.at %ps[%i4] : !s32, index -> i32
  %side = trikeshed.at %ps[%i5] : !s32, index -> i32
  %p = trikeshed.at %ps[%i6] : !s32, index -> i32
  %rl = arith.ori %ri, %leaf : i32
  %ni64 = arith.extui %ni : i32 to i64
  %base64 = arith.muli %ni64, %c4x : i64
  %base = arith.index_cast %base64 : i64 to index
  %nd = func.call @pat_nodes(%nodes) : (!llvm.ptr) -> !d
  %nm = builtin.unrealized_conversion_cast %nd : !d to !m32
  %slot = memref.subview %nm[%base] [4] [1] : !m32 to memref<4xi32, strided<[1], offset: ?>>
  %d0 = arith.cmpi eq, %dir, %c0 : i32
  %d1 = arith.cmpi eq, %dir, %c1 : i32
  %w0 = arith.select %d0, %rl, %p : i32
  %w1 = arith.select %d1, %rl, %p : i32
  %n0 = trikeshed.series %c1x4 : !s32 {
  ^bb0(%k0: index):
    trikeshed.yield %w0 : i32
  }
  %n1 = trikeshed.series %c1x4 : !s32 {
  ^bb0(%k1: index):
    trikeshed.yield %w1 : i32
  }
  %n2 = trikeshed.series %c1x4 : !s32 {
  ^bb0(%k2: index):
    trikeshed.yield %b : i32
  }
  %n3 = trikeshed.series %c1x4 : !s32 {
  ^bb0(%k3: index):
    trikeshed.yield %other : i32
  }
  %node = trikeshed.combine %n0, %n1, %n2, %n3 : !s32, !s32, !s32, !s32 -> !s32
  %ne = trikeshed.drain %node, %slot : !s32, memref<4xi32, strided<[1], offset: ?>> -> index
  // the parent's child on its side takes the new node; with no parent, the new node is the root
  %top = arith.cmpi eq, %parent, %none : i32
  %r = scf.if %top -> i32 {
    scf.yield %ni : i32
  } else {
    %par64 = arith.extui %parent : i32 to i64
    %side64 = arith.extui %side : i32 to i64
    %pbase = arith.muli %par64, %c4x : i64
    %cw = arith.addi %pbase, %side64 : i64
    func.call @pat_put1(%nd, %cw, %ni) : (!d, i64, i32) -> ()
    scf.yield %root : i32
  }
  return %r : i32
}

// prefix: the rows whose key starts with the prefix, in byte order, written to out; the answer is their count.  The trie
// is not empty; stack holds nnodes + 1 cells, out the count of rows.
func.func @mlnix_patricia_prefix(%nodes: !llvm.ptr, %rows: !llvm.ptr, %rs: i64, %root: i32, %k: !llvm.ptr, %n: i32, %stack: !llvm.ptr, %out: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %mask = arith.constant 0x7FFFFFFF : i32
  %false = arith.constant 0 : i1
  %n64 = arith.extui %n : i32 to i64
  %nd = func.call @pat_nodes(%nodes) : (!llvm.ptr) -> !d
  %r64 = func.call @pat_rows64(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %r32 = func.call @pat_rows32(%rows, %rs) : (!llvm.ptr, i64) -> !d
  %kd = func.call @pat_desc(%k, %n64) : (!llvm.ptr, i64) -> !d
  %sd = func.call @pat_cells(%stack) : (!llvm.ptr) -> !d
  %od = func.call @pat_cells(%out) : (!llvm.ptr) -> !d
  // down while a node tests a byte of the prefix: past it, every key of the subtree agrees on the prefix or none does
  %top = scf.while (%p = %root) : (i32) -> i32 {
    %isn = func.call @pat_isnode(%p) : (i32) -> i1
    %go = scf.if %isn -> i1 {
      %qb, %qo = func.call @pat_node(%nd, %p) : (!d, i32) -> (i32, i32)
      %in = arith.cmpi ult, %qb, %n : i32
      scf.yield %in : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%go) %p : i32
  } do {
  ^bb0(%pt: i32):
    %dt, %qt = func.call @pat_step(%nd, %pt, %kd, %n64) : (!d, i32, !d, i64) -> (i32, i32)
    scf.yield %qt : i32
  }
  // the first row of the subtree: its first n bytes are the prefix, or no key of the subtree starts with it
  %first = scf.while (%pf = %top) : (i32) -> i32 {
    %isnf = func.call @pat_isnode(%pf) : (i32) -> i1
    scf.condition(%isnf) %pf : i32
  } do {
  ^bb0(%pg: i32):
    %c0w = func.call @pat_child(%nd, %pg, %c0) : (!d, i32, i32) -> i32
    scf.yield %c0w : i32
  }
  %ai = arith.andi %first, %mask : i32
  %akp, %alen = func.call @pat_row(%r64, %r32, %rs, %ai) : (!d, !d, i64, i32) -> (!llvm.ptr, i32)
  %head = arith.minui %alen, %n : i32
  %o = func.call @pat_cmp(%akp, %head, %kd) : (!llvm.ptr, i32, !d) -> i32
  %agrees = arith.cmpi eq, %o, %c0 : i32
  %count = scf.if %agrees -> i32 {
    // the subtree in byte order: side 0 first, an explicit stack of the cells (the top node on it)
    %c0i = arith.constant 0 : i64
    func.call @pat_put1(%sd, %c0i, %top) : (!d, i64, i32) -> ()
    %w:2 = scf.while (%sp = %c1, %cnt = %c0) : (i32, i32) -> (i32, i32) {
      %more = arith.cmpi ne, %sp, %c0 : i32
      scf.condition(%more) %sp, %cnt : i32, i32
    } do {
    ^bb0(%sp2: i32, %cnt2: i32):
      %sp1 = arith.subi %sp2, %c1 : i32
      %sp64 = arith.extui %sp1 : i32 to i64
      %q = func.call @pat_w32(%sd, %sp64) : (!d, i64) -> i32
      %isnq = func.call @pat_isnode(%q) : (i32) -> i1
      %r:2 = scf.if %isnq -> (i32, i32) {
        %ch1 = func.call @pat_child(%nd, %q, %c1) : (!d, i32, i32) -> i32
        %ch0 = func.call @pat_child(%nd, %q, %c0) : (!d, i32, i32) -> i32
        func.call @pat_put2(%sd, %sp64, %ch1, %ch0) : (!d, i64, i32, i32) -> ()
        %sp3 = arith.addi %sp2, %c1 : i32
        scf.yield %sp3, %cnt2 : i32, i32
      } else {
        %row = arith.andi %q, %mask : i32
        %c64 = arith.extui %cnt2 : i32 to i64
        func.call @pat_put1(%od, %c64, %row) : (!d, i64, i32) -> ()
        %cnt3 = arith.addi %cnt2, %c1 : i32
        scf.yield %sp1, %cnt3 : i32, i32
      }
      scf.yield %r#0, %r#1 : i32, i32
    }
    scf.yield %w#1 : i32
  } else {
    scf.yield %c0 : i32
  }
  return %count : i32
}
