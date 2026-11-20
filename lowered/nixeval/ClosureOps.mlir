// __genericClosure hollowed into MLIR: the worklist walk and the set of keys already met.  lib/Eval/Builtins.cpp keeps
// the forcing of the argument set and its startSet/operator lookups (Nix's error order and wording) and calls
// nixev_ts_genericClosure; the walk is here: the queue (the start set's cells, then each operator result's cells drained
// after them), the keys met, and the result list (the elements whose key was new, in walk order, drained into the arena
// cells mkList made).
//
// The keys met are kept as the std::set<Value *, lessThan> the C++ used kept them: a red-black tree whose shape and
// comparison sequence are libc++'s (__tree's __count_unique, __find_equal, __insert_node_at, __tree_balance_after_insert
// and the two rotations), because a comparison is a Nix lessThan, which may force list elements and may throw ("cannot
// compare"): which keys are compared, in which order and with which operand first is observable, so it must stay the
// one the C++ made.  As the C++ did, a new key walks the tree twice (count, then insert), each comparison k < node then
// node < k.  A node is six i64 words in the bridge's buffer: left, right, parent, black, key cell, element cell; node 0 is
// libc++'s end node (its left is the root), null is -1.
//
// Every evaluator interaction is a callback, at the point the C++ loop made it: an element forced to a set and its key
// looked up and forced (nixev_gc_key), a comparison (nixev_gc_lt), the operator applied to a new element and its result
// forced to a list (nixev_gc_next).  The queue and the tree live in the bridge's growable buffers (nixev_gc_room hands
// back where they are, having room for the words asked), so a throw frees them as the C++ did.  Value: VType u8@0, aux
// u32@4 (a list's size), list.elems@8.
!s = !trikeshed.series<i64>
!m = memref<?xi64, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

func.func private @_ZN5nixev9EvalState6mkListERNS_5ValueEm(!llvm.ptr, !llvm.ptr, i64)
func.func private @nixev_gc_key(!llvm.ptr, !llvm.ptr) -> !llvm.ptr
func.func private @nixev_gc_lt(!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
func.func private @nixev_gc_next(!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
func.func private @nixev_gc_room(!llvm.ptr, i64, i64) -> !llvm.ptr

// the descriptor of n i64 cells at p (module-unique)
func.func private @gc_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// field f of node x (0 left, 1 right, 2 parent, 3 black, 4 key, 5 element)
func.func private @gc_ld(%t: !m, %x: i64, %f: i64) -> i64 {
  %c6 = arith.constant 6 : i64
  %b = arith.muli %x, %c6 : i64
  %o = arith.addi %b, %f : i64
  %i = arith.index_cast %o : i64 to index
  %v = memref.load %t[%i] : !m
  return %v : i64
}
func.func private @gc_st(%t: !m, %x: i64, %f: i64, %v: i64) {
  %c6 = arith.constant 6 : i64
  %b = arith.muli %x, %c6 : i64
  %o = arith.addi %b, %f : i64
  %i = arith.index_cast %o : i64 to index
  memref.store %v, %t[%i] : !m
  return
}

// __tree_is_left_child: x is its parent's left (the root is the end node's left)
func.func private @gc_isleft(%t: !m, %x: i64) -> i1 {
  %c0 = arith.constant 0 : i64
  %c2 = arith.constant 2 : i64
  %p = func.call @gc_ld(%t, %x, %c2) : (!m, i64, i64) -> i64
  %l = func.call @gc_ld(%t, %p, %c0) : (!m, i64, i64) -> i64
  %r = arith.cmpi eq, %l, %x : i64
  return %r : i1
}

// __tree_left_rotate (a = 0, b = 1) and __tree_right_rotate (a = 1, b = 0): y = x's b child takes x's place, x becomes
// y's a child, y's a child becomes x's b child.
func.func private @gc_rotate(%t: !m, %x: i64, %a: i64, %b: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %nil = arith.constant -1 : i64
  %y = func.call @gc_ld(%t, %x, %b) : (!m, i64, i64) -> i64
  %ya = func.call @gc_ld(%t, %y, %a) : (!m, i64, i64) -> i64
  func.call @gc_st(%t, %x, %b, %ya) : (!m, i64, i64, i64) -> ()
  %has = arith.cmpi ne, %ya, %nil : i64
  scf.if %has {
    func.call @gc_st(%t, %ya, %c2, %x) : (!m, i64, i64, i64) -> ()
  }
  %xp = func.call @gc_ld(%t, %x, %c2) : (!m, i64, i64) -> i64
  func.call @gc_st(%t, %y, %c2, %xp) : (!m, i64, i64, i64) -> ()
  %left = func.call @gc_isleft(%t, %x) : (!m, i64) -> i1
  %side = arith.select %left, %c0, %c1 : i64
  func.call @gc_st(%t, %xp, %side, %y) : (!m, i64, i64, i64) -> ()
  func.call @gc_st(%t, %y, %a, %x) : (!m, i64, i64, i64) -> ()
  func.call @gc_st(%t, %x, %c2, %y) : (!m, i64, i64, i64) -> ()
  return
}

// __tree_balance_after_insert(root, x): the red-black fix-up, recolouring up the tree and at most two rotations.  `l`
// is the side of x's parent (0 when the parent is a left child), so one body serves both mirrored cases.
func.func private @gc_balance(%t: !m, %root: i64, %x0: i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %nil = arith.constant -1 : i64
  %f = arith.constant 0 : i1
  %isroot0 = arith.cmpi eq, %x0, %root : i64
  %b0 = arith.extui %isroot0 : i1 to i64
  func.call @gc_st(%t, %x0, %c3, %b0) : (!m, i64, i64, i64) -> ()
  %r:2 = scf.while (%x = %x0, %done = %f) : (i64, i1) -> (i64, i1) {
    %notroot = arith.cmpi ne, %x, %root : i64
    %go0 = arith.cmpi eq, %done, %f : i1
    %go1 = arith.andi %notroot, %go0 : i1
    // the parent's colour is read only when x is not the root (the C++'s && short-circuits)
    %red = scf.if %go1 -> (i1) {
      %p = func.call @gc_ld(%t, %x, %c2) : (!m, i64, i64) -> i64
      %pb = func.call @gc_ld(%t, %p, %c3) : (!m, i64, i64) -> i64
      %isred = arith.cmpi eq, %pb, %c0 : i64
      scf.yield %isred : i1
    } else {
      scf.yield %f : i1
    }
    scf.condition(%red) %x, %done : i64, i1
  } do {
  ^bb0(%x: i64, %done: i1):
    %p = func.call @gc_ld(%t, %x, %c2) : (!m, i64, i64) -> i64
    %pl = func.call @gc_isleft(%t, %p) : (!m, i64) -> i1
    // l: the parent's side; u: the uncle's side
    %l = arith.select %pl, %c0, %c1 : i64
    %u = arith.select %pl, %c1, %c0 : i64
    %g = func.call @gc_ld(%t, %p, %c2) : (!m, i64, i64) -> i64
    %y = func.call @gc_ld(%t, %g, %u) : (!m, i64, i64) -> i64
    %ynil = arith.cmpi eq, %y, %nil : i64
    %yred = scf.if %ynil -> (i1) {
      scf.yield %f : i1
    } else {
      %yb = func.call @gc_ld(%t, %y, %c3) : (!m, i64, i64) -> i64
      %yr = arith.cmpi eq, %yb, %c0 : i64
      scf.yield %yr : i1
    }
    %next:2 = scf.if %yred -> (i64, i1) {
      func.call @gc_st(%t, %p, %c3, %c1) : (!m, i64, i64, i64) -> ()
      %gr = arith.cmpi eq, %g, %root : i64
      %gb = arith.extui %gr : i1 to i64
      func.call @gc_st(%t, %g, %c3, %gb) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t, %y, %c3, %c1) : (!m, i64, i64, i64) -> ()
      scf.yield %g, %f : i64, i1
    } else {
      // x on the inner side: rotate it out to the parent's side first (left_rotate under a left parent)
      %xl = func.call @gc_isleft(%t, %x) : (!m, i64) -> i1
      %xside = arith.select %xl, %c0, %c1 : i64
      %inner = arith.cmpi ne, %xside, %l : i64
      %x2 = scf.if %inner -> (i64) {
        func.call @gc_rotate(%t, %p, %l, %u) : (!m, i64, i64, i64) -> ()
        scf.yield %p : i64
      } else {
        scf.yield %x : i64
      }
      %x3 = func.call @gc_ld(%t, %x2, %c2) : (!m, i64, i64) -> i64
      func.call @gc_st(%t, %x3, %c3, %c1) : (!m, i64, i64, i64) -> ()
      %x4 = func.call @gc_ld(%t, %x3, %c2) : (!m, i64, i64) -> i64
      func.call @gc_st(%t, %x4, %c3, %c0) : (!m, i64, i64, i64) -> ()
      func.call @gc_rotate(%t, %x4, %u, %l) : (!m, i64, i64, i64) -> ()
      %tr = arith.constant 1 : i1
      scf.yield %x4, %tr : i64, i1
    }
    scf.yield %next#0, %next#1 : i64, i1
  }
  return
}

// The walk down from the root for key k (__count_unique's and __find_equal's: k < node goes left, node < k goes right,
// else found): (found, the node where it stopped, the side of the null child it stopped at: 0 left, 1 right).  An empty
// tree stops at the end node's left.
func.func private @gc_find(%c: !llvm.ptr, %t: !m, %k: !llvm.ptr) -> (i1, i64, i64) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %nil = arith.constant -1 : i64
  %f = arith.constant 0 : i1
  %tr = arith.constant 1 : i1
  %root = func.call @gc_ld(%t, %c0, %c0) : (!m, i64, i64) -> i64
  %empty = arith.cmpi eq, %root, %nil : i64
  // state: the node, stopped, found, side
  %r:4 = scf.while (%nd = %root, %stop = %empty, %found = %f, %side = %c0) : (i64, i1, i1, i64) -> (i64, i1, i1, i64) {
    %go = arith.cmpi eq, %stop, %f : i1
    scf.condition(%go) %nd, %stop, %found, %side : i64, i1, i1, i64
  } do {
  ^bb0(%nd: i64, %stop: i1, %found: i1, %side: i64):
    %kv = func.call @gc_ld(%t, %nd, %c4) : (!m, i64, i64) -> i64
    %kp = llvm.inttoptr %kv : i64 to !llvm.ptr
    %lt = func.call @nixev_gc_lt(%c, %k, %kp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
    %less = arith.cmpi ne, %lt, %c0 : i64
    %dir = scf.if %less -> (i64) {
      scf.yield %c0 : i64
    } else {
      %gt = func.call @nixev_gc_lt(%c, %kp, %k) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i64
      %greater = arith.cmpi ne, %gt, %c0 : i64
      %two = arith.constant 2 : i64
      %d2 = arith.select %greater, %c1, %two : i64
      scf.yield %d2 : i64
    }
    %two = arith.constant 2 : i64
    %eq = arith.cmpi eq, %dir, %two : i64
    %next:4 = scf.if %eq -> (i64, i1, i1, i64) {
      scf.yield %nd, %tr, %tr, %c0 : i64, i1, i1, i64
    } else {
      %child = func.call @gc_ld(%t, %nd, %dir) : (!m, i64, i64) -> i64
      %leaf = arith.cmpi eq, %child, %nil : i64
      %nd2 = arith.select %leaf, %nd, %child : i64
      scf.yield %nd2, %leaf, %f, %dir : i64, i1, i1, i64
    }
    scf.yield %next#0, %next#1, %next#2, %next#3 : i64, i1, i1, i64
  }
  // an empty tree: the end node, left
  %at = arith.select %empty, %c0, %r#0 : i64
  return %r#2, %at, %r#3 : i1, i64, i64
}

// the bridge's tree buffer as a memref of `words` words
func.func private @gc_tree(%c: !llvm.ptr, %words: i64) -> !d {
  %one = arith.constant 1 : i64
  %p = func.call @nixev_gc_room(%c, %one, %words) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %d = func.call @gc_desc(%p, %words) : (!llvm.ptr, i64) -> !d
  return %d : !d
}

func.func @nixev_ts_genericClosure(%c: !llvm.ptr, %start: !llvm.ptr, %st: !llvm.ptr, %v: !llvm.ptr) {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c2 = arith.constant 2 : i64
  %c3 = arith.constant 3 : i64
  %c4 = arith.constant 4 : i64
  %c5 = arith.constant 5 : i64
  %c6 = arith.constant 6 : i64
  %c8 = arith.constant 8 : i64
  %nil = arith.constant -1 : i64
  // the queue: the start set's cells
  %sp = llvm.getelementptr %start[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %selems = llvm.load %sp : !llvm.ptr -> !llvm.ptr
  %snp = llvm.getelementptr %start[4] : (!llvm.ptr) -> !llvm.ptr, i8
  %sn32 = llvm.load %snp : !llvm.ptr -> i32
  %sn = llvm.zext %sn32 : i32 to i64
  %q0 = func.call @nixev_gc_room(%c, %c0, %sn) : (!llvm.ptr, i64, i64) -> !llvm.ptr
  %sd = func.call @gc_desc(%selems, %sn) : (!llvm.ptr, i64) -> !d
  %sm = builtin.unrealized_conversion_cast %sd : !d to !m
  %ss = builtin.unrealized_conversion_cast %sm : !m to !s
  %qd = func.call @gc_desc(%q0, %sn) : (!llvm.ptr, i64) -> !d
  %qm = builtin.unrealized_conversion_cast %qd : !d to !m
  %e0 = trikeshed.drain %ss, %qm : !s, !m -> index
  // the end node: no root yet
  %t0d = func.call @gc_tree(%c, %c6) : (!llvm.ptr, i64) -> !d
  %t0 = builtin.unrealized_conversion_cast %t0d : !d to !m
  func.call @gc_st(%t0, %c0, %c0, %nil) : (!m, i64, i64, i64) -> ()
  %slots = llvm.alloca %c2 x i64 : (i64) -> !llvm.ptr
  %np = llvm.getelementptr %slots[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %r:3 = scf.while (%qi = %c0, %qn = %sn, %nn = %c0) : (i64, i64, i64) -> (i64, i64, i64) {
    %more = arith.cmpi ult, %qi, %qn : i64
    scf.condition(%more) %qi, %qn, %nn : i64, i64, i64
  } do {
  ^bb0(%qi: i64, %qn: i64, %nn: i64):
    %qb = func.call @nixev_gc_room(%c, %c0, %qn) : (!llvm.ptr, i64, i64) -> !llvm.ptr
    %qo = arith.muli %qi, %c8 : i64
    %ep = llvm.getelementptr %qb[%qo] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %e = llvm.load %ep : !llvm.ptr -> !llvm.ptr
    %k = func.call @nixev_gc_key(%c, %e) : (!llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %nodes = arith.addi %nn, %c1 : i64
    %words = arith.muli %nodes, %c6 : i64
    %td = func.call @gc_tree(%c, %words) : (!llvm.ptr, i64) -> !d
    %t = builtin.unrealized_conversion_cast %td : !d to !m
    %f:3 = func.call @gc_find(%c, %t, %k) : (!llvm.ptr, !m, !llvm.ptr) -> (i1, i64, i64)
    %qi2 = arith.addi %qi, %c1 : i64
    %next:2 = scf.if %f#0 -> (i64, i64) {
      scf.yield %qn, %nn : i64, i64
    } else {
      // insert: walk again (std::set::insert after count), then the node at the null child it stops at
      %g:3 = func.call @gc_find(%c, %t, %k) : (!llvm.ptr, !m, !llvm.ptr) -> (i1, i64, i64)
      %x = arith.addi %nn, %c1 : i64
      %nodes2 = arith.addi %x, %c1 : i64
      %words2 = arith.muli %nodes2, %c6 : i64
      %td2 = func.call @gc_tree(%c, %words2) : (!llvm.ptr, i64) -> !d
      %t2 = builtin.unrealized_conversion_cast %td2 : !d to !m
      %kb = llvm.ptrtoint %k : !llvm.ptr to i64
      %eb = llvm.ptrtoint %e : !llvm.ptr to i64
      func.call @gc_st(%t2, %x, %c0, %nil) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %x, %c1, %nil) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %x, %c2, %g#1) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %x, %c3, %c0) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %x, %c4, %kb) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %x, %c5, %eb) : (!m, i64, i64, i64) -> ()
      func.call @gc_st(%t2, %g#1, %g#2, %x) : (!m, i64, i64, i64) -> ()
      %root = func.call @gc_ld(%t2, %c0, %c0) : (!m, i64, i64) -> i64
      func.call @gc_balance(%t2, %root, %x) : (!m, i64, i64) -> ()
      // the operator's result's cells go after the queue
      func.call @nixev_gc_next(%c, %e, %slots, %np) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
      %relems = llvm.load %slots : !llvm.ptr -> !llvm.ptr
      %rn = llvm.load %np : !llvm.ptr -> i64
      %qn2 = arith.addi %qn, %rn : i64
      %qb2 = func.call @nixev_gc_room(%c, %c0, %qn2) : (!llvm.ptr, i64, i64) -> !llvm.ptr
      %rd = func.call @gc_desc(%relems, %rn) : (!llvm.ptr, i64) -> !d
      %rm = builtin.unrealized_conversion_cast %rd : !d to !m
      %rs = builtin.unrealized_conversion_cast %rm : !m to !s
      %qo2 = arith.muli %qn, %c8 : i64
      %qtail = llvm.getelementptr %qb2[%qo2] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %qtd = func.call @gc_desc(%qtail, %rn) : (!llvm.ptr, i64) -> !d
      %qtm = builtin.unrealized_conversion_cast %qtd : !d to !m
      %e1 = trikeshed.drain %rs, %qtm : !s, !m -> index
      scf.yield %qn2, %x : i64, i64
    }
    scf.yield %qi2, %next#0, %next#1 : i64, i64, i64
  }
  // the result: the elements whose key was new, in the order they were met (node 1, 2, ...)
  %n = arith.addi %r#2, %c0 : i64
  func.call @_ZN5nixev9EvalState6mkListERNS_5ValueEm(%st, %v, %n) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %ep = llvm.getelementptr %v[8] : (!llvm.ptr) -> !llvm.ptr, i8
  %elems = llvm.load %ep : !llvm.ptr -> !llvm.ptr
  %all = arith.addi %n, %c1 : i64
  %tw = arith.muli %all, %c6 : i64
  %tdf = func.call @gc_tree(%c, %tw) : (!llvm.ptr, i64) -> !d
  %tm = builtin.unrealized_conversion_cast %tdf : !d to !m
  %ts = builtin.unrealized_conversion_cast %tm : !m to !s
  %ni = arith.index_cast %n : i64 to index
  %c1i = arith.constant 1 : index
  %c5i = arith.constant 5 : index
  %c6i = arith.constant 6 : index
  %col = trikeshed.series %ni : !s {
  ^bb0(%i: index):
    %node = arith.addi %i, %c1i : index
    %w = arith.muli %node, %c6i : index
    %w5 = arith.addi %w, %c5i : index
    %x = trikeshed.at %ts[%w5] : !s, index -> i64
    trikeshed.yield %x : i64
  }
  %od = func.call @gc_desc(%elems, %n) : (!llvm.ptr, i64) -> !d
  %into = builtin.unrealized_conversion_cast %od : !d to !m
  %end = trikeshed.drain %col, %into : !s, !m -> index
  return
}
