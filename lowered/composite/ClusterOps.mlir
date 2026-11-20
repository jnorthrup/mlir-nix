// The btrfs ordering cluster's algorithms (include/Composite/MinMaxHeap.h, Funnel.h) hollowed into MLIR: the min-max
// heap's push / climb / sift and its edge pops, the peg bag's argMin, the cluster's insert routing, min race, find and
// drain, clusterOrder's fill-then-drain, and Krapivin's funnel (the salted splitmix slot, the put/get level walk with
// its rerouting and early exit).  The C++ headers are drop-in bridges: a row crosses as rs opaque bytes (the Inline
// body's cells and its u32 count are the ABI), and Row's `<` / `==` cross as neutral C callbacks
// int(const void *, const void *), so any Row with those operators works unchanged (a null `<` is clusterOrder's
// (i64 key, u32 index) order, built in).  The walks are scf.while / scf.for
// over the caller's arrays: nothing allocates (the heap and the pegs are inline bodies, as in the C++).  Helpers are
// module-unique (mmx_*): the pipeline exports them.
//
// The funnel's bucket layout crosses as byte offsets (the heap's cells at 0, its count at hnOff, the pegs' cells at
// pOff, their count at pnOff, a bucket stride bytes); level l starts at bucket 2*(top - (top>>l)) and holds top>>l.

// The address of row i: base + i*rs bytes.
func.func private @mmx_row(%base: !llvm.ptr, %rs: i64, %i: i32) -> !llvm.ptr {
  %i64 = arith.extui %i : i32 to i64
  %off = arith.muli %i64, %rs : i64
  %p = llvm.getelementptr %base[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p : !llvm.ptr
}

// Copy one row: a 16- or 8-byte row as words, any other size by memmove (a row may be copied onto itself).
func.func private @mmx_copy(%dst: !llvm.ptr, %src: !llvm.ptr, %rs: i64) {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %is16 = arith.cmpi eq, %rs, %c16 : i64
  %is8 = arith.cmpi eq, %rs, %c8 : i64
  scf.if %is16 {
    %s1 = llvm.getelementptr %src[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %d1 = llvm.getelementptr %dst[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %w0 = llvm.load %src {alignment = 1 : i64} : !llvm.ptr -> i64
    %w1 = llvm.load %s1 {alignment = 1 : i64} : !llvm.ptr -> i64
    llvm.store %w0, %dst {alignment = 1 : i64} : i64, !llvm.ptr
    llvm.store %w1, %d1 {alignment = 1 : i64} : i64, !llvm.ptr
  } else {
    scf.if %is8 {
      %w = llvm.load %src {alignment = 1 : i64} : !llvm.ptr -> i64
      llvm.store %w, %dst {alignment = 1 : i64} : i64, !llvm.ptr
    } else {
      "llvm.intr.memmove"(%dst, %src, %rs) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  return
}

// Swap rows x and y (x != y): word-wise for 16/8-byte rows, else a byte at a time.
func.func private @mmx_swap(%base: !llvm.ptr, %rs: i64, %x: i32, %y: i32) {
  %c8 = arith.constant 8 : i64
  %c16 = arith.constant 16 : i64
  %xp = func.call @mmx_row(%base, %rs, %x) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %yp = func.call @mmx_row(%base, %rs, %y) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %is16 = arith.cmpi eq, %rs, %c16 : i64
  %is8 = arith.cmpi eq, %rs, %c8 : i64
  scf.if %is16 {
    %x1 = llvm.getelementptr %xp[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %y1 = llvm.getelementptr %yp[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %a0 = llvm.load %xp {alignment = 1 : i64} : !llvm.ptr -> i64
    %a1 = llvm.load %x1 {alignment = 1 : i64} : !llvm.ptr -> i64
    %b0 = llvm.load %yp {alignment = 1 : i64} : !llvm.ptr -> i64
    %b1 = llvm.load %y1 {alignment = 1 : i64} : !llvm.ptr -> i64
    llvm.store %b0, %xp {alignment = 1 : i64} : i64, !llvm.ptr
    llvm.store %b1, %x1 {alignment = 1 : i64} : i64, !llvm.ptr
    llvm.store %a0, %yp {alignment = 1 : i64} : i64, !llvm.ptr
    llvm.store %a1, %y1 {alignment = 1 : i64} : i64, !llvm.ptr
  } else {
    scf.if %is8 {
      %a = llvm.load %xp {alignment = 1 : i64} : !llvm.ptr -> i64
      %b = llvm.load %yp {alignment = 1 : i64} : !llvm.ptr -> i64
      llvm.store %b, %xp {alignment = 1 : i64} : i64, !llvm.ptr
      llvm.store %a, %yp {alignment = 1 : i64} : i64, !llvm.ptr
    } else {
      %z = arith.constant 0 : index
      %one = arith.constant 1 : index
      %n = arith.index_cast %rs : i64 to index
      scf.for %k = %z to %n step %one {
        %k64 = arith.index_cast %k : index to i64
        %xk = llvm.getelementptr %xp[%k64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %yk = llvm.getelementptr %yp[%k64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %bx = llvm.load %xk : !llvm.ptr -> i8
        %by = llvm.load %yk : !llvm.ptr -> i8
        llvm.store %by, %xk : i8, !llvm.ptr
        llvm.store %bx, %yk : i8, !llvm.ptr
      }
    }
  }
  return
}

// Row's operator< or operator== as a callback, 0/1.  A null fn is clusterOrder's row order, monomorphized: (i64 key at
// 0 signed, then u32 index at 8).
func.func private @mmx_cmp(%fn: !llvm.ptr, %x: !llvm.ptr, %y: !llvm.ptr) -> i1 {
  %z = arith.constant 0 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %builtin = llvm.icmp "eq" %fn, %null : !llvm.ptr
  %b = scf.if %builtin -> (i1) {
    %kx = llvm.load %x : !llvm.ptr -> i64
    %ky = llvm.load %y : !llvm.ptr -> i64
    %ix8 = llvm.getelementptr %x[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %iy8 = llvm.getelementptr %y[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %ix = llvm.load %ix8 : !llvm.ptr -> i32
    %iy = llvm.load %iy8 : !llvm.ptr -> i32
    %kne = arith.cmpi ne, %kx, %ky : i64
    %klt = arith.cmpi slt, %kx, %ky : i64
    %ilt = arith.cmpi ult, %ix, %iy : i32
    %lt = arith.select %kne, %klt, %ilt : i1
    scf.yield %lt : i1
  } else {
    %c = llvm.call %fn(%x, %y) : !llvm.ptr, (!llvm.ptr, !llvm.ptr) -> i32
    %nz = arith.cmpi ne, %c, %z : i32
    scf.yield %nz : i1
  }
  return %b : i1
}

// before(rows x, y): row x belongs nearer the edge than row y.  mf=0 is the min levels' order (x < y), mf=1 the max
// levels' (y < x).
func.func private @mmx_before(%base: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %mf: i1, %x: i32, %y: i32) -> i1 {
  %xp = func.call @mmx_row(%base, %rs, %x) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %yp = func.call @mmx_row(%base, %rs, %y) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %a = llvm.select %mf, %yp, %xp : i1, !llvm.ptr
  %b = llvm.select %mf, %xp, %yp : i1, !llvm.ptr
  %c = func.call @mmx_cmp(%less, %a, %b) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
  return %c : i1
}

// The grandparent walk upward: while the row is nearer the edge than its grandparent, swap with it.  The walk stops
// below index 3 (the root's grandchildren are the first rows with a grandparent).
func.func private @mmx_climb(%base: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %mf: i1, %from: i32) {
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %c3 = arith.constant 3 : i32
  %c4 = arith.constant 4 : i32
  %w:2 = scf.while (%i = %from, %live = %t) : (i32, i1) -> (i32, i1) {
    %ge = arith.cmpi uge, %i, %c3 : i32
    %go = arith.andi %ge, %live : i1
    scf.condition(%go) %i, %live : i32, i1
  } do {
  ^bb0(%j: i32, %lv: i1):
    %jm3 = arith.subi %j, %c3 : i32
    %g = arith.divui %jm3, %c4 : i32
    %b = func.call @mmx_before(%base, %rs, %less, %mf, %j, %g) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
    %ni, %nl = scf.if %b -> (i32, i1) {
      func.call @mmx_swap(%base, %rs, %j, %g) : (!llvm.ptr, i64, i32, i32) -> ()
      scf.yield %g, %t : i32, i1
    } else {
      scf.yield %j, %f : i32, i1
    }
    scf.yield %ni, %nl : i32, i1
  }
  return
}

// The walk downward: the nearest-the-edge of the two children then the four grandchildren (in index order, the first
// of equals kept) replaces the row if it is nearer the edge.  A child swap stops (the child is on the opposite level);
// a grandchild swap repairs against its parent and goes on.
func.func private @mmx_sift(%base: !llvm.ptr, %n: i32, %rs: i64, %less: !llvm.ptr, %mf: i1, %from: i32) {
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %c4 = arith.constant 4 : i32
  %c7 = arith.constant 7 : i32
  %step = arith.constant 1 : index
  %w:2 = scf.while (%i = %from, %live = %t) : (i32, i1) -> (i32, i1) {
    %l0 = arith.muli %i, %c2 : i32
    %l = arith.addi %l0, %c1 : i32
    %has = arith.cmpi ult, %l, %n : i32
    %go = arith.andi %has, %live : i1
    scf.condition(%go) %i, %live : i32, i1
  } do {
  ^bb0(%j: i32, %lv: i1):
    %l0b = arith.muli %j, %c2 : i32
    %lc = arith.addi %l0b, %c1 : i32
    %rc = arith.addi %lc, %c1 : i32
    %hasR = arith.cmpi ult, %rc, %n : i32
    %m0 = scf.if %hasR -> (i32) {
      %br = func.call @mmx_before(%base, %rs, %less, %mf, %rc, %lc) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
      %sel = arith.select %br, %rc, %lc : i32
      scf.yield %sel : i32
    } else {
      scf.yield %lc : i32
    }
    %g4 = arith.muli %j, %c4 : i32
    %gs = arith.addi %g4, %c3 : i32
    %g7 = arith.addi %g4, %c7 : i32
    %ge = arith.minui %g7, %n : i32
    %gsI = arith.index_cast %gs : i32 to index
    %geI = arith.index_cast %ge : i32 to index
    %m = scf.for %gi = %gsI to %geI step %step iter_args(%best = %m0) -> (i32) {
      %g = arith.index_cast %gi : index to i32
      %bg = func.call @mmx_before(%base, %rs, %less, %mf, %g, %best) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
      %nb = arith.select %bg, %g, %best : i32
      scf.yield %nb : i32
    }
    %bm = func.call @mmx_before(%base, %rs, %less, %mf, %m, %j) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
    %ri, %rl = scf.if %bm -> (i32, i1) {
      func.call @mmx_swap(%base, %rs, %j, %m) : (!llvm.ptr, i64, i32, i32) -> ()
      %isChild = arith.cmpi ult, %m, %gs : i32
      %ci, %cl = scf.if %isChild -> (i32, i1) {
        scf.yield %m, %f : i32, i1
      } else {
        %mm1 = arith.subi %m, %c1 : i32
        %p = arith.divui %mm1, %c2 : i32
        %bp = func.call @mmx_before(%base, %rs, %less, %mf, %p, %m) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
        scf.if %bp {
          func.call @mmx_swap(%base, %rs, %m, %p) : (!llvm.ptr, i64, i32, i32) -> ()
        }
        scf.yield %m, %t : i32, i1
      }
      scf.yield %ci, %cl : i32, i1
    } else {
      scf.yield %j, %f : i32, i1
    }
    scf.yield %ri, %rl : i32, i1
  }
  return
}

// The max edge's index: the root when there is one row, else the larger of the root's two children (the first when
// they are equal).
func.func @mmx_max_at(%base: !llvm.ptr, %n: i32, %rs: i64, %less: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %is1 = arith.cmpi eq, %n, %c1 : i32
  %r = scf.if %is1 -> (i32) {
    scf.yield %c0 : i32
  } else {
    %gt2 = arith.cmpi ugt, %n, %c2 : i32
    %r2 = scf.if %gt2 -> (i32) {
      %p1 = func.call @mmx_row(%base, %rs, %c1) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      %p2 = func.call @mmx_row(%base, %rs, %c2) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      %lt = func.call @mmx_cmp(%less, %p1, %p2) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
      %s = arith.select %lt, %c2, %c1 : i32
      scf.yield %s : i32
    } else {
      scf.yield %c1 : i32
    }
    scf.yield %r2 : i32
  }
  return %r : i32
}

// push: append the row, settle it against its parent edge, then climb the grandparent chain.  level(i) =
// floor(log2(i+1)); an even level is a min level.
func.func @mmx_heap_push(%base: !llvm.ptr, %np: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %r: !llvm.ptr) {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c31 = arith.constant 31 : i32
  %t = arith.constant 1 : i1
  %i = llvm.load %np : !llvm.ptr -> i32
  %ip = func.call @mmx_row(%base, %rs, %i) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  func.call @mmx_copy(%ip, %r, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %i1 = arith.addi %i, %c1 : i32
  llvm.store %i1, %np : i32, !llvm.ptr
  %some = arith.cmpi ne, %i, %c0 : i32
  scf.if %some {
    %lz = "llvm.intr.ctlz"(%i1) <{is_zero_poison = false}> : (i32) -> i32
    %lvl = arith.subi %c31, %lz : i32
    %bit = arith.andi %lvl, %c1 : i32
    %minLevel = arith.cmpi eq, %bit, %c0 : i32
    %im1 = arith.subi %i, %c1 : i32
    %p = arith.divui %im1, %c2 : i32
    // a min level asks a[p] < a[i] (the max levels' before(i, p)); a max level a[i] < a[p] (the min levels')
    %out = func.call @mmx_before(%base, %rs, %less, %minLevel, %i, %p) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
    scf.if %out {
      func.call @mmx_swap(%base, %rs, %i, %p) : (!llvm.ptr, i64, i32, i32) -> ()
      func.call @mmx_climb(%base, %rs, %less, %minLevel, %p) : (!llvm.ptr, i64, !llvm.ptr, i1, i32) -> ()
    } else {
      %maxLevel = arith.xori %minLevel, %t : i1
      func.call @mmx_climb(%base, %rs, %less, %maxLevel, %i) : (!llvm.ptr, i64, !llvm.ptr, i1, i32) -> ()
    }
  }
  return
}

// popMin: the root leaves, the last row takes its place and sifts down the min levels.
func.func @mmx_heap_pop_min(%base: !llvm.ptr, %np: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %out: !llvm.ptr) {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %f = arith.constant 0 : i1
  %n = llvm.load %np : !llvm.ptr -> i32
  func.call @mmx_copy(%out, %base, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %nm1 = arith.subi %n, %c1 : i32
  %last = func.call @mmx_row(%base, %rs, %nm1) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  func.call @mmx_copy(%base, %last, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  llvm.store %nm1, %np : i32, !llvm.ptr
  %gt1 = arith.cmpi ugt, %nm1, %c1 : i32
  scf.if %gt1 {
    func.call @mmx_sift(%base, %nm1, %rs, %less, %f, %c0) : (!llvm.ptr, i32, i64, !llvm.ptr, i1, i32) -> ()
  }
  return
}

// popMax: the max edge leaves, the last row takes its place and sifts down the max levels when rows remain below it.
func.func @mmx_heap_pop_max(%base: !llvm.ptr, %np: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %out: !llvm.ptr) {
  %c1 = arith.constant 1 : i32
  %t = arith.constant 1 : i1
  %n = llvm.load %np : !llvm.ptr -> i32
  %is1 = arith.cmpi eq, %n, %c1 : i32
  scf.if %is1 {
    func.call @mmx_heap_pop_min(%base, %np, %rs, %less, %out) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
  } else {
    %m = func.call @mmx_max_at(%base, %n, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
    %mp = func.call @mmx_row(%base, %rs, %m) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    func.call @mmx_copy(%out, %mp, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %nm1 = arith.subi %n, %c1 : i32
    %last = func.call @mmx_row(%base, %rs, %nm1) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    func.call @mmx_copy(%mp, %last, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    llvm.store %nm1, %np : i32, !llvm.ptr
    %below = arith.cmpi ult, %m, %nm1 : i32
    scf.if %below {
      func.call @mmx_sift(%base, %nm1, %rs, %less, %t, %m) : (!llvm.ptr, i32, i64, !llvm.ptr, i1, i32) -> ()
    }
  }
  return
}

// The peg bag's least: argMin, a fold over the indices 1..n-1 seeded with 0, the first of equals kept (0 when empty).
// An scf.for, not a trikeshed.fold over an index series: the series lowering materializes the indices in a malloc'd
// buffer, and nothing in the cluster allocates.
func.func @mmx_arg_min(%base: !llvm.ptr, %n: i32, %rs: i64, %less: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %one = arith.constant 1 : index
  %nI = arith.index_cast %n : i32 to index
  %m = scf.for %k = %one to %nI step %one iter_args(%best = %c0) -> (i32) {
    %k32 = arith.index_cast %k : index to i32
    %bp = func.call @mmx_row(%base, %rs, %best) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %kp = func.call @mmx_row(%base, %rs, %k32) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %lt = func.call @mmx_cmp(%less, %kp, %bp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
    %r = arith.select %lt, %k32, %best : i32
    scf.yield %r : i32
  }
  return %m : i32
}

// A peg leaves: the least row out, the last peg fills its hole (the bag's removeSwap).
func.func @mmx_peg_pop(%pb: !llvm.ptr, %pnp: !llvm.ptr, %rs: i64, %less: !llvm.ptr, %out: !llvm.ptr) {
  %c1 = arith.constant 1 : i32
  %pn = llvm.load %pnp : !llvm.ptr -> i32
  %m = func.call @mmx_arg_min(%pb, %pn, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
  %mp = func.call @mmx_row(%pb, %rs, %m) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  func.call @mmx_copy(%out, %mp, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  %nm1 = arith.subi %pn, %c1 : i32
  %last = func.call @mmx_row(%pb, %rs, %nm1) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  func.call @mmx_copy(%mp, %last, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  llvm.store %nm1, %pnp : i32, !llvm.ptr
  return
}

// insert: 0 the heap took the row, 1 it parked on a peg (the slop path), 2 the cluster is full and stays intact.  A
// full heap whose max edge is not below the row settles that edge out to a peg and takes the row; a row beyond the
// edge parks on a peg without touching the heap.
func.func @mmx_cluster_insert(%hb: !llvm.ptr, %hnp: !llvm.ptr, %capN: i32, %pb: !llvm.ptr, %pnp: !llvm.ptr, %capP: i32,
    %rs: i64, %less: !llvm.ptr, %r: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %hn = llvm.load %hnp : !llvm.ptr -> i32
  %pn = llvm.load %pnp : !llvm.ptr -> i32
  %hf = arith.cmpi eq, %hn, %capN : i32
  %pf = arith.cmpi eq, %pn, %capP : i32
  %full = arith.andi %hf, %pf : i1
  %res = scf.if %full -> (i32) {
    scf.yield %c2 : i32
  } else {
    %r1 = scf.if %hf -> (i32) {
      %m = func.call @mmx_max_at(%hb, %hn, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
      %mp = func.call @mmx_row(%hb, %rs, %m) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      %beyond = func.call @mmx_cmp(%less, %mp, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
      %pp = func.call @mmx_row(%pb, %rs, %pn) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      scf.if %beyond {
        func.call @mmx_copy(%pp, %r, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      } else {
        func.call @mmx_heap_pop_max(%hb, %hnp, %rs, %less, %pp) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
        func.call @mmx_heap_push(%hb, %hnp, %rs, %less, %r) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
      }
      %pn1 = arith.addi %pn, %c1 : i32
      llvm.store %pn1, %pnp : i32, !llvm.ptr
      scf.yield %c1 : i32
    } else {
      func.call @mmx_heap_push(%hb, %hnp, %rs, %less, %r) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
      scf.yield %c0 : i32
    }
    scf.yield %r1 : i32
  }
  return %res : i32
}

// The cluster's min edge: the heap's root (1) or the least peg (0).  With an empty heap it is the pegs; with no pegs
// the heap; else the root and the least peg race and the peg wins unless the root is strictly smaller.
func.func private @mmx_heap_side(%hb: !llvm.ptr, %hn: i32, %pb: !llvm.ptr, %pn: i32, %rs: i64, %less: !llvm.ptr) -> i1 {
  %c0 = arith.constant 0 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %h0 = arith.cmpi eq, %hn, %c0 : i32
  %side = scf.if %h0 -> (i1) {
    scf.yield %f : i1
  } else {
    %p0 = arith.cmpi eq, %pn, %c0 : i32
    %s2 = scf.if %p0 -> (i1) {
      scf.yield %t : i1
    } else {
      %mi = func.call @mmx_arg_min(%pb, %pn, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
      %mp = func.call @mmx_row(%pb, %rs, %mi) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      %lt = func.call @mmx_cmp(%less, %hb, %mp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
      scf.yield %lt : i1
    }
    scf.yield %s2 : i1
  }
  return %side : i1
}

// The cluster's min edge, copied to out (the least peg is taken again when it wins, as the C++ read it twice).
func.func @mmx_cluster_min(%hb: !llvm.ptr, %hn: i32, %pb: !llvm.ptr, %pn: i32, %rs: i64, %less: !llvm.ptr, %out: !llvm.ptr) {
  %side = func.call @mmx_heap_side(%hb, %hn, %pb, %pn, %rs, %less) : (!llvm.ptr, i32, !llvm.ptr, i32, i64, !llvm.ptr) -> i1
  scf.if %side {
    func.call @mmx_copy(%out, %hb, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  } else {
    %mi = func.call @mmx_arg_min(%pb, %pn, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
    %mp = func.call @mmx_row(%pb, %rs, %mi) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    func.call @mmx_copy(%out, %mp, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
  return
}

// The cluster's popMin: the same race, the winning side's pop.
func.func @mmx_cluster_pop_min(%hb: !llvm.ptr, %hnp: !llvm.ptr, %pb: !llvm.ptr, %pnp: !llvm.ptr, %rs: i64,
    %less: !llvm.ptr, %out: !llvm.ptr) {
  %hn = llvm.load %hnp : !llvm.ptr -> i32
  %pn = llvm.load %pnp : !llvm.ptr -> i32
  %side = func.call @mmx_heap_side(%hb, %hn, %pb, %pn, %rs, %less) : (!llvm.ptr, i32, !llvm.ptr, i32, i64, !llvm.ptr) -> i1
  scf.if %side {
    func.call @mmx_heap_pop_min(%hb, %hnp, %rs, %less, %out) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
  } else {
    func.call @mmx_peg_pop(%pb, %pnp, %rs, %less, %out) : (!llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
  }
  return
}

// firstWhere(rows, == r) over n rows: the first equal row, or null.
func.func private @mmx_first_eq(%base: !llvm.ptr, %n: i32, %rs: i64, %eq: !llvm.ptr, %r: !llvm.ptr) -> !llvm.ptr {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %w:2 = scf.while (%k = %c0, %acc = %null) : (i32, !llvm.ptr) -> (i32, !llvm.ptr) {
    %lt = arith.cmpi ult, %k, %n : i32
    %none = llvm.icmp "eq" %acc, %null : !llvm.ptr
    %go = arith.andi %lt, %none : i1
    scf.condition(%go) %k, %acc : i32, !llvm.ptr
  } do {
  ^bb0(%j: i32, %a: !llvm.ptr):
    %jp = func.call @mmx_row(%base, %rs, %j) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %e = func.call @mmx_cmp(%eq, %jp, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
    %na = llvm.select %e, %jp, %a : i1, !llvm.ptr
    %j1 = arith.addi %j, %c1 : i32
    scf.yield %j1, %na : i32, !llvm.ptr
  }
  return %w#1 : !llvm.ptr
}

// find: a key outside the heap's [min, max] edges skips the heap search (the min edge read first, the max only when
// the key is not below the min); the pegs are unordered and always searched.  The stored row equal to r, or null.
func.func @mmx_cluster_find(%hb: !llvm.ptr, %hn: i32, %pb: !llvm.ptr, %pn: i32, %rs: i64, %less: !llvm.ptr,
    %eq: !llvm.ptr, %r: !llvm.ptr) -> !llvm.ptr {
  %c0 = arith.constant 0 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %null = llvm.mlir.zero : !llvm.ptr
  %hne = arith.cmpi ne, %hn, %c0 : i32
  %inRange = scf.if %hne -> (i1) {
    %below = func.call @mmx_cmp(%less, %r, %hb) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
    %in = scf.if %below -> (i1) {
      scf.yield %f : i1
    } else {
      %m = func.call @mmx_max_at(%hb, %hn, %rs, %less) : (!llvm.ptr, i32, i64, !llvm.ptr) -> i32
      %mp = func.call @mmx_row(%hb, %rs, %m) : (!llvm.ptr, i64, i32) -> !llvm.ptr
      %above = func.call @mmx_cmp(%less, %mp, %r) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
      %notAbove = arith.xori %above, %t : i1
      scf.yield %notAbove : i1
    }
    scf.yield %in : i1
  } else {
    scf.yield %f : i1
  }
  %inHeap = scf.if %inRange -> (!llvm.ptr) {
    %h = func.call @mmx_first_eq(%hb, %hn, %rs, %eq, %r) : (!llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    scf.yield %h : !llvm.ptr
  } else {
    scf.yield %null : !llvm.ptr
  }
  %miss = llvm.icmp "eq" %inHeap, %null : !llvm.ptr
  %res = scf.if %miss -> (!llvm.ptr) {
    %p = func.call @mmx_first_eq(%pb, %pn, %rs, %eq, %r) : (!llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    scf.yield %p : !llvm.ptr
  } else {
    scf.yield %inHeap : !llvm.ptr
  }
  return %res : !llvm.ptr
}

// drain: one popMin a row, the min edges racing until the cluster is empty; each row emitted, in key order, to
// emit(ctx, row).
func.func @mmx_cluster_drain(%hb: !llvm.ptr, %hnp: !llvm.ptr, %pb: !llvm.ptr, %pnp: !llvm.ptr, %rs: i64,
    %less: !llvm.ptr, %ctx: !llvm.ptr, %emit: !llvm.ptr) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %hn = llvm.load %hnp : !llvm.ptr -> i32
  %pn = llvm.load %pnp : !llvm.ptr -> i32
  %total = arith.addi %hn, %pn : i32
  %totalI = arith.index_cast %total : i32 to index
  %tmp = llvm.alloca %rs x i8 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  scf.for %k = %z to %totalI step %one {
    func.call @mmx_cluster_pop_min(%hb, %hnp, %pb, %pnp, %rs, %less, %tmp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
    llvm.call %emit(%ctx, %tmp) : !llvm.ptr, (!llvm.ptr, !llvm.ptr) -> ()
  }
  return
}

// clusterOrder's fill-then-drain: every one of the n rows inserted (the caller keeps n within the cluster), then the
// cluster drained to emit.
func.func @mmx_order(%hb: !llvm.ptr, %hnp: !llvm.ptr, %capN: i32, %pb: !llvm.ptr, %pnp: !llvm.ptr, %capP: i32,
    %rs: i64, %less: !llvm.ptr, %rows: !llvm.ptr, %n: i32, %ctx: !llvm.ptr, %emit: !llvm.ptr) {
  %z = arith.constant 0 : index
  %one = arith.constant 1 : index
  %nI = arith.index_cast %n : i32 to index
  scf.for %k = %z to %nI step %one {
    %k32 = arith.index_cast %k : index to i32
    %rp = func.call @mmx_row(%rows, %rs, %k32) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %st = func.call @mmx_cluster_insert(%hb, %hnp, %capN, %pb, %pnp, %capP, %rs, %less, %rp) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr) -> i32
  }
  func.call @mmx_cluster_drain(%hb, %hnp, %pb, %pnp, %rs, %less, %ctx, %emit) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
  return
}

// The bucket of hash h at level l: splitmix64's finalizer over h salted by the level, so a collision at one level
// does not repeat at the next, masked to the level's top>>l buckets.  The bucket's address.
func.func private @mmx_bucket(%cells: !llvm.ptr, %top: i32, %l: i32, %h: i64, %stride: i64) -> !llvm.ptr {
  %salt = arith.constant 0xD6E8FEB86659FD93 : i64
  %g = arith.constant 0x9E3779B97F4A7C15 : i64
  %k1 = arith.constant 0xBF58476D1CE4E5B9 : i64
  %k2 = arith.constant 0x94D049BB133111EB : i64
  %c30 = arith.constant 30 : i64
  %c27 = arith.constant 27 : i64
  %c31 = arith.constant 31 : i64
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %l64 = arith.extui %l : i32 to i64
  %ls = arith.muli %l64, %salt : i64
  %x0 = arith.xori %h, %ls : i64
  %a = arith.addi %x0, %g : i64
  %s30 = arith.shrui %a, %c30 : i64
  %x1 = arith.xori %a, %s30 : i64
  %m1 = arith.muli %x1, %k1 : i64
  %s27 = arith.shrui %m1, %c27 : i64
  %x2 = arith.xori %m1, %s27 : i64
  %m2 = arith.muli %x2, %k2 : i64
  %s31 = arith.shrui %m2, %c31 : i64
  %mix = arith.xori %m2, %s31 : i64
  %cnt = arith.shrui %top, %l : i32
  %mask = arith.subi %cnt, %c1 : i32
  %m32 = arith.trunci %mix : i64 to i32
  %slot = arith.andi %m32, %mask : i32
  %above = arith.subi %top, %cnt : i32
  %off = arith.muli %above, %c2 : i32
  %bi = arith.addi %off, %slot : i32
  %b = func.call @mmx_row(%cells, %stride, %bi) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  return %b : !llvm.ptr
}

// put: walk the levels, the row's bucket at each; a stored key refuses (0xFF), a bucket with room takes the row and
// its level is the answer (the row count bumped), a full bucket reroutes one level down.  Every level full: 0xFE.
func.func @mmx_funnel_put(%cells: !llvm.ptr, %top: i32, %levels: i32, %rowsp: !llvm.ptr, %rs: i64, %capN: i32,
    %capP: i32, %hnOff: i64, %pOff: i64, %pnOff: i64, %stride: i64, %less: !llvm.ptr, %eq: !llvm.ptr,
    %r: !llvm.ptr, %h: i64) -> i32 {
  %undecided = arith.constant -1 : i32
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %cff = arith.constant 255 : i32
  %cfe = arith.constant 254 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %w:2 = scf.while (%l = %c0, %ret = %undecided) : (i32, i32) -> (i32, i32) {
    %lt = arith.cmpi ult, %l, %levels : i32
    %und = arith.cmpi eq, %ret, %undecided : i32
    %go = arith.andi %lt, %und : i1
    scf.condition(%go) %l, %ret : i32, i32
  } do {
  ^bb0(%lv: i32, %rv: i32):
    %b = func.call @mmx_bucket(%cells, %top, %lv, %h, %stride) : (!llvm.ptr, i32, i32, i64, i64) -> !llvm.ptr
    %hnp = llvm.getelementptr %b[%hnOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pb = llvm.getelementptr %b[%pOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pnp = llvm.getelementptr %b[%pnOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %hn = llvm.load %hnp : !llvm.ptr -> i32
    %pn = llvm.load %pnp : !llvm.ptr -> i32
    %fp = func.call @mmx_cluster_find(%b, %hn, %pb, %pn, %rs, %less, %eq, %r) : (!llvm.ptr, i32, !llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %found = llvm.icmp "ne" %fp, %null : !llvm.ptr
    %r1 = scf.if %found -> (i32) {
      scf.yield %cff : i32
    } else {
      %st = func.call @mmx_cluster_insert(%b, %hnp, %capN, %pb, %pnp, %capP, %rs, %less, %r) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr) -> i32
      %isFull = arith.cmpi eq, %st, %c2 : i32
      %r2 = scf.if %isFull -> (i32) {
        scf.yield %undecided : i32
      } else {
        %rows = llvm.load %rowsp : !llvm.ptr -> i32
        %rows1 = arith.addi %rows, %c1 : i32
        llvm.store %rows1, %rowsp : i32, !llvm.ptr
        scf.yield %lv : i32
      }
      scf.yield %r2 : i32
    }
    %l1 = arith.addi %lv, %c1 : i32
    scf.yield %l1, %r1 : i32, i32
  }
  %still = arith.cmpi eq, %w#1, %undecided : i32
  %res = arith.select %still, %cfe, %w#1 : i32
  return %res : i32
}

// get: the same walk, counting probes (when probesp is not null); a bucket with room that does not hold the key
// proves it absent (no deletes), so the walk stops there.  The stored row, or null.
func.func @mmx_funnel_get(%cells: !llvm.ptr, %top: i32, %levels: i32, %rs: i64, %capN: i32, %capP: i32,
    %hnOff: i64, %pOff: i64, %pnOff: i64, %stride: i64, %less: !llvm.ptr, %eq: !llvm.ptr, %r: !llvm.ptr,
    %h: i64, %probesp: !llvm.ptr) -> !llvm.ptr {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %null = llvm.mlir.zero : !llvm.ptr
  %counting = llvm.icmp "ne" %probesp, %null : !llvm.ptr
  %w:3 = scf.while (%l = %c0, %fr = %null, %stop = %f) : (i32, !llvm.ptr, i1) -> (i32, !llvm.ptr, i1) {
    %lt = arith.cmpi ult, %l, %levels : i32
    %none = llvm.icmp "eq" %fr, %null : !llvm.ptr
    %more = arith.xori %stop, %t : i1
    %a1 = arith.andi %lt, %none : i1
    %go = arith.andi %a1, %more : i1
    scf.condition(%go) %l, %fr, %stop : i32, !llvm.ptr, i1
  } do {
  ^bb0(%lv: i32, %fv: !llvm.ptr, %sv: i1):
    %b = func.call @mmx_bucket(%cells, %top, %lv, %h, %stride) : (!llvm.ptr, i32, i32, i64, i64) -> !llvm.ptr
    %hnp = llvm.getelementptr %b[%hnOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pb = llvm.getelementptr %b[%pOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pnp = llvm.getelementptr %b[%pnOff] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    scf.if %counting {
      %pr = llvm.load %probesp : !llvm.ptr -> i32
      %pr1 = arith.addi %pr, %c1 : i32
      llvm.store %pr1, %probesp : i32, !llvm.ptr
    }
    %hn = llvm.load %hnp : !llvm.ptr -> i32
    %pn = llvm.load %pnp : !llvm.ptr -> i32
    %ff = func.call @mmx_cluster_find(%b, %hn, %pb, %pn, %rs, %less, %eq, %r) : (!llvm.ptr, i32, !llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> !llvm.ptr
    %hf = arith.cmpi eq, %hn, %capN : i32
    %pf = arith.cmpi eq, %pn, %capP : i32
    %full = arith.andi %hf, %pf : i1
    %room = arith.xori %full, %t : i1
    %l1 = arith.addi %lv, %c1 : i32
    scf.yield %l1, %ff, %room : i32, !llvm.ptr, i1
  }
  return %w#1 : !llvm.ptr
}
