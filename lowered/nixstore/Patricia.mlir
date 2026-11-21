// The crit-bit (Patricia) trie of include/Composite/Patricia.h, hollowed: the leaf walk (one bit tested a node), the key
// compare at the leaf it reaches, set's plan (the first byte where the key and that leaf differ, the highest differing bit
// as the mask of the other bits, the new node's direction, the descent to the first node whose bit comes after it), the
// link of the new node, and prefix's descent, prefix check and byte-order subtree walk.  Patricia.h keeps only what is
// generic in V: the Row/Node storage (MutableSeries, grown by the bridge), the value store, copy() and emit().
//
// The caller's arrays, read where they lie (the entries allocate nothing and never see a V):
//   nodes: Node {u32 child[2]; u32 byte; u8 other} = !node, 16 bytes; a child is a node's index, or a row's index | kLeaf.
//   rows:  Row {const char *key; u32 len; V v}, rs bytes apart (sizeof(Row)); key@0, len@8.
//   k, n:  the query key, read as if a 0 byte followed it (no key holds a 0 byte).
// A node's direction for a key is (1 + (other | byte)) >> 8: other is the node's bit cleared out of 0xFF, so the sum
// carries into bit 8 exactly when the key has that bit.  Every comparison of indices and bytes is unsigned, as the C++'s
// uint32_t/uint8_t.  The key checks are trikeshed.compare over byte series (len == n && memcmp == 0 is compare == 0).
!s = !trikeshed.series<i8>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!node = !llvm.struct<(array<2 x i32>, i32, i8)>

// the descriptor of n i8 cells at p (a struct: returning it clones nothing)
func.func private @pat_desc8(%p: !llvm.ptr, %n: i32) -> !d {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %n64 = arith.extui %n : i32 to i64
  %u = llvm.mlir.undef : !d
  %a = llvm.insertvalue %p, %u[0] : !d
  %b = llvm.insertvalue %p, %a[1] : !d
  %c = llvm.insertvalue %c0, %b[2] : !d
  %e = llvm.insertvalue %n64, %c[3, 0] : !d
  %f = llvm.insertvalue %c1, %e[4, 0] : !d
  return %f : !d
}

// byteAt: the key's byte i, or the 0 that follows it
func.func private @pat_byte(%k: !llvm.ptr, %n: i32, %i: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %in = arith.cmpi ult, %i, %n : i32
  %r = scf.if %in -> i32 {
    %i64 = arith.extui %i : i32 to i64
    %at = llvm.getelementptr %k[%i64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %b = llvm.load %at : !llvm.ptr -> i8
    %w = arith.extui %b : i8 to i32
    scf.yield %w : i32
  } else {
    scf.yield %c0 : i32
  }
  return %r : i32
}

// node p's tested byte and other mask
func.func private @pat_node(%nodes: !llvm.ptr, %p: i32) -> (i32, i32) {
  %p64 = arith.extui %p : i32 to i64
  %bp = llvm.getelementptr %nodes[%p64, 1] : (!llvm.ptr, i64) -> !llvm.ptr, !node
  %byte = llvm.load %bp : !llvm.ptr -> i32
  %op = llvm.getelementptr %nodes[%p64, 2] : (!llvm.ptr, i64) -> !llvm.ptr, !node
  %o8 = llvm.load %op : !llvm.ptr -> i8
  %other = arith.extui %o8 : i8 to i32
  return %byte, %other : i32, i32
}

// the address of node p's child d
func.func private @pat_childp(%nodes: !llvm.ptr, %p: i32, %d: i32) -> !llvm.ptr {
  %p64 = arith.extui %p : i32 to i64
  %d64 = arith.extui %d : i32 to i64
  %cp = llvm.getelementptr %nodes[%p64, 0, %d64] : (!llvm.ptr, i64, i64) -> !llvm.ptr, !node
  return %cp : !llvm.ptr
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
func.func private @pat_step(%nodes: !llvm.ptr, %p: i32, %k: !llvm.ptr, %n: i32) -> (i32, i32) {
  %byte, %other = func.call @pat_node(%nodes, %p) : (!llvm.ptr, i32) -> (i32, i32)
  %kb = func.call @pat_byte(%k, %n, %byte) : (!llvm.ptr, i32, i32) -> i32
  %d = func.call @pat_dir(%other, %kb) : (i32, i32) -> i32
  %cp = func.call @pat_childp(%nodes, %p, %d) : (!llvm.ptr, i32, i32) -> !llvm.ptr
  %q = llvm.load %cp : !llvm.ptr -> i32
  return %d, %q : i32, i32
}

func.func private @pat_isnode(%p: i32) -> i1 {
  %c0 = arith.constant 0 : i32
  %leaf = arith.constant 0x80000000 : i32
  %t = arith.andi %p, %leaf : i32
  %r = arith.cmpi eq, %t, %c0 : i32
  return %r : i1
}

// leafOf(k, n): down from the root by the key's bits to the row it reaches
func.func private @pat_leaf(%nodes: !llvm.ptr, %root: i32, %k: !llvm.ptr, %n: i32) -> i32 {
  %mask = arith.constant 0x7FFFFFFF : i32
  %r = scf.while (%p = %root) : (i32) -> i32 {
    %go = func.call @pat_isnode(%p) : (i32) -> i1
    scf.condition(%go) %p : i32
  } do {
  ^bb0(%p: i32):
    %d, %q = func.call @pat_step(%nodes, %p, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> (i32, i32)
    scf.yield %q : i32
  }
  %row = arith.andi %r, %mask : i32
  return %row : i32
}

// row i's key and length
func.func private @pat_row(%rows: !llvm.ptr, %rs: i64, %i: i32) -> (!llvm.ptr, i32) {
  %i64 = arith.extui %i : i32 to i64
  %off = arith.muli %i64, %rs : i64
  %kp = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %key = llvm.load %kp : !llvm.ptr -> !llvm.ptr
  %lp = llvm.getelementptr %kp[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %len = llvm.load %lp : !llvm.ptr -> i32
  return %key, %len : !llvm.ptr, i32
}

// compare(an bytes at a, bn bytes at b): the trikeshed series order, 0 when the two are the same bytes
func.func private @pat_cmp(%a: !llvm.ptr, %an: i32, %b: !llvm.ptr, %bn: i32) -> i32 {
  %da = func.call @pat_desc8(%a, %an) : (!llvm.ptr, i32) -> !d
  %ma = builtin.unrealized_conversion_cast %da : !d to !m
  %sa = builtin.unrealized_conversion_cast %ma : !m to !s
  %db = func.call @pat_desc8(%b, %bn) : (!llvm.ptr, i32) -> !d
  %mb = builtin.unrealized_conversion_cast %db : !d to !m
  %sb = builtin.unrealized_conversion_cast %mb : !m to !s
  %o = trikeshed.compare %sa, %sb unsigned : !s, !s
  return %o : i32
}

// find: the row the key reaches, if its key is the key; else 0xFFFFFFFF.  The trie is not empty.
func.func @mlnix_patricia_find(%nodes: !llvm.ptr, %rows: !llvm.ptr, %rs: i64, %root: i32, %k: !llvm.ptr, %n: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %none = arith.constant -1 : i32
  %bi = func.call @pat_leaf(%nodes, %root, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> i32
  %key, %len = func.call @pat_row(%rows, %rs, %bi) : (!llvm.ptr, i64, i32) -> (!llvm.ptr, i32)
  %o = func.call @pat_cmp(%key, %len, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> i32
  %eq = arith.cmpi eq, %o, %c0 : i32
  %r = arith.select %eq, %bi, %none : i32
  return %r : i32
}

// set's plan.  The trie is not empty.  0: the key is stored at row plan[0] (the bridge replaces the value).  1: the key
// is new; plan = {leaf, byte b, other, dir, parent, side, p}: the new node tests bit `other` of byte b, the new row goes
// on side dir, and the node takes the place of p (parent's child on `side`, or the root when parent is 0xFFFFFFFF).
func.func @mlnix_patricia_set(%nodes: !llvm.ptr, %rows: !llvm.ptr, %rs: i64, %root: i32, %k: !llvm.ptr, %n: i32, %plan: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c4 = arith.constant 4 : i32
  %cff = arith.constant 255 : i32
  %none = arith.constant -1 : i32
  %bi = func.call @pat_leaf(%nodes, %root, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> i32
  llvm.store %bi, %plan : i32, !llvm.ptr
  %bkey, %blen = func.call @pat_row(%rows, %rs, %bi) : (!llvm.ptr, i64, i32) -> (!llvm.ptr, i32)
  // the first byte b <= max(n, len) where the two differ (the 0 past either end counts), and x their xor there
  %m = arith.maxui %n, %blen : i32
  %scan:2 = scf.while (%b = %c0, %x = %c0) : (i32, i32) -> (i32, i32) {
    %in = arith.cmpi ule, %b, %m : i32
    %same = arith.cmpi eq, %x, %c0 : i32
    %go = arith.andi %in, %same : i1
    scf.condition(%go) %b, %x : i32, i32
  } do {
  ^bb0(%b: i32, %x: i32):
    %kb = func.call @pat_byte(%k, %n, %b) : (!llvm.ptr, i32, i32) -> i32
    %lb = func.call @pat_byte(%bkey, %blen, %b) : (!llvm.ptr, i32, i32) -> i32
    %nx = arith.xori %kb, %lb : i32
    %hit = arith.cmpi ne, %nx, %c0 : i32
    %b1 = arith.addi %b, %c1 : i32
    %nb = arith.select %hit, %b, %b1 : i32
    scf.yield %nb, %nx : i32, i32
  }
  %exact = arith.cmpi eq, %scan#1, %c0 : i32
  %mode = scf.if %exact -> i32 {
    scf.yield %c0 : i32
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
    %kb = func.call @pat_byte(%k, %n, %scan#0) : (!llvm.ptr, i32, i32) -> i32
    %dir = func.call @pat_dir(%other, %kb) : (i32, i32) -> i32
    // down from the root to the first node whose bit comes after the new one (a later byte, or a lower bit of the
    // same byte): the new node takes its place
    %false = arith.constant 0 : i1
    %true = arith.constant 1 : i1
    %walk:3 = scf.while (%parent = %none, %side = %c0, %p = %root) : (i32, i32, i32) -> (i32, i32, i32) {
      %isn = func.call @pat_isnode(%p) : (i32) -> i1
      %go = scf.if %isn -> i1 {
        %qb, %qo = func.call @pat_node(%nodes, %p) : (!llvm.ptr, i32) -> (i32, i32)
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
    ^bb0(%parent: i32, %side: i32, %p: i32):
      %d, %q = func.call @pat_step(%nodes, %p, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> (i32, i32)
      scf.yield %p, %d, %q : i32, i32, i32
    }
    %f1 = llvm.getelementptr %plan[1] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %scan#0, %f1 : i32, !llvm.ptr
    %f2 = llvm.getelementptr %plan[2] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %other, %f2 : i32, !llvm.ptr
    %f3 = llvm.getelementptr %plan[3] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %dir, %f3 : i32, !llvm.ptr
    %f4 = llvm.getelementptr %plan[4] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %walk#0, %f4 : i32, !llvm.ptr
    %f5 = llvm.getelementptr %plan[5] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %walk#1, %f5 : i32, !llvm.ptr
    %f6 = llvm.getelementptr %plan[6] : (!llvm.ptr) -> !llvm.ptr, i32
    llvm.store %walk#2, %f6 : i32, !llvm.ptr
    scf.yield %c1 : i32
  }
  return %mode : i32
}

// set's link: node ni (appended by the bridge) tests bit `other` of byte b, row ri on side dir and p on the other; it
// takes p's place.  The answer is the root.
func.func @mlnix_patricia_link(%nodes: !llvm.ptr, %ni: i32, %root: i32, %ri: i32, %plan: !llvm.ptr) -> i32 {
  %c1 = arith.constant 1 : i32
  %leaf = arith.constant 0x80000000 : i32
  %none = arith.constant -1 : i32
  %f1 = llvm.getelementptr %plan[1] : (!llvm.ptr) -> !llvm.ptr, i32
  %b = llvm.load %f1 : !llvm.ptr -> i32
  %f2 = llvm.getelementptr %plan[2] : (!llvm.ptr) -> !llvm.ptr, i32
  %other = llvm.load %f2 : !llvm.ptr -> i32
  %f3 = llvm.getelementptr %plan[3] : (!llvm.ptr) -> !llvm.ptr, i32
  %dir = llvm.load %f3 : !llvm.ptr -> i32
  %f4 = llvm.getelementptr %plan[4] : (!llvm.ptr) -> !llvm.ptr, i32
  %parent = llvm.load %f4 : !llvm.ptr -> i32
  %f5 = llvm.getelementptr %plan[5] : (!llvm.ptr) -> !llvm.ptr, i32
  %side = llvm.load %f5 : !llvm.ptr -> i32
  %f6 = llvm.getelementptr %plan[6] : (!llvm.ptr) -> !llvm.ptr, i32
  %p = llvm.load %f6 : !llvm.ptr -> i32
  %rl = arith.ori %ri, %leaf : i32
  %cd = func.call @pat_childp(%nodes, %ni, %dir) : (!llvm.ptr, i32, i32) -> !llvm.ptr
  llvm.store %rl, %cd : i32, !llvm.ptr
  %odir = arith.subi %c1, %dir : i32
  %co = func.call @pat_childp(%nodes, %ni, %odir) : (!llvm.ptr, i32, i32) -> !llvm.ptr
  llvm.store %p, %co : i32, !llvm.ptr
  %ni64 = arith.extui %ni : i32 to i64
  %bp = llvm.getelementptr %nodes[%ni64, 1] : (!llvm.ptr, i64) -> !llvm.ptr, !node
  llvm.store %b, %bp : i32, !llvm.ptr
  %op = llvm.getelementptr %nodes[%ni64, 2] : (!llvm.ptr, i64) -> !llvm.ptr, !node
  %o8 = arith.trunci %other : i32 to i8
  llvm.store %o8, %op : i8, !llvm.ptr
  %top = arith.cmpi eq, %parent, %none : i32
  %r = scf.if %top -> i32 {
    scf.yield %ni : i32
  } else {
    %cp = func.call @pat_childp(%nodes, %parent, %side) : (!llvm.ptr, i32, i32) -> !llvm.ptr
    llvm.store %ni, %cp : i32, !llvm.ptr
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
  // down while a node tests a byte of the prefix: past it, every key of the subtree agrees on the prefix or none does
  %top = scf.while (%p = %root) : (i32) -> i32 {
    %isn = func.call @pat_isnode(%p) : (i32) -> i1
    %go = scf.if %isn -> i1 {
      %qb, %qo = func.call @pat_node(%nodes, %p) : (!llvm.ptr, i32) -> (i32, i32)
      %in = arith.cmpi ult, %qb, %n : i32
      scf.yield %in : i1
    } else {
      scf.yield %false : i1
    }
    scf.condition(%go) %p : i32
  } do {
  ^bb0(%p: i32):
    %d, %q = func.call @pat_step(%nodes, %p, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> (i32, i32)
    scf.yield %q : i32
  }
  // the first row of the subtree: its first n bytes are the prefix, or no key of the subtree starts with it
  %first = scf.while (%p = %top) : (i32) -> i32 {
    %isn = func.call @pat_isnode(%p) : (i32) -> i1
    scf.condition(%isn) %p : i32
  } do {
  ^bb0(%p: i32):
    %c0p = func.call @pat_childp(%nodes, %p, %c0) : (!llvm.ptr, i32, i32) -> !llvm.ptr
    %q = llvm.load %c0p : !llvm.ptr -> i32
    scf.yield %q : i32
  }
  %ai = arith.andi %first, %mask : i32
  %akey, %alen = func.call @pat_row(%rows, %rs, %ai) : (!llvm.ptr, i64, i32) -> (!llvm.ptr, i32)
  %head = arith.minui %alen, %n : i32
  %o = func.call @pat_cmp(%akey, %head, %k, %n) : (!llvm.ptr, i32, !llvm.ptr, i32) -> i32
  %agrees = arith.cmpi eq, %o, %c0 : i32
  %count = scf.if %agrees -> i32 {
    // the subtree in byte order: side 0 first, an explicit stack
    llvm.store %top, %stack : i32, !llvm.ptr
    %w:2 = scf.while (%sp = %c1, %cnt = %c0) : (i32, i32) -> (i32, i32) {
      %more = arith.cmpi ne, %sp, %c0 : i32
      scf.condition(%more) %sp, %cnt : i32, i32
    } do {
    ^bb0(%sp: i32, %cnt: i32):
      %sp1 = arith.subi %sp, %c1 : i32
      %sp64 = arith.extui %sp1 : i32 to i64
      %qp = llvm.getelementptr %stack[%sp64] : (!llvm.ptr, i64) -> !llvm.ptr, i32
      %q = llvm.load %qp : !llvm.ptr -> i32
      %isn = func.call @pat_isnode(%q) : (i32) -> i1
      %r:2 = scf.if %isn -> (i32, i32) {
        %h1 = func.call @pat_childp(%nodes, %q, %c1) : (!llvm.ptr, i32, i32) -> !llvm.ptr
        %ch1 = llvm.load %h1 : !llvm.ptr -> i32
        %h0 = func.call @pat_childp(%nodes, %q, %c0) : (!llvm.ptr, i32, i32) -> !llvm.ptr
        %ch0 = llvm.load %h0 : !llvm.ptr -> i32
        llvm.store %ch1, %qp : i32, !llvm.ptr
        %np = llvm.getelementptr %qp[1] : (!llvm.ptr) -> !llvm.ptr, i32
        llvm.store %ch0, %np : i32, !llvm.ptr
        %sp2 = arith.addi %sp, %c1 : i32
        scf.yield %sp2, %cnt : i32, i32
      } else {
        %row = arith.andi %q, %mask : i32
        %c64 = arith.extui %cnt : i32 to i64
        %rp = llvm.getelementptr %out[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i32
        llvm.store %row, %rp : i32, !llvm.ptr
        %cnt1 = arith.addi %cnt, %c1 : i32
        scf.yield %sp1, %cnt1 : i32, i32
      }
      scf.yield %r#0, %r#1 : i32, i32
    }
    scf.yield %w#1 : i32
  } else {
    scf.yield %c0 : i32
  }
  return %count : i32
}
