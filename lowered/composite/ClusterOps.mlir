// The btrfs ordering cluster's algorithms (include/Composite/MinMaxHeap.h, Funnel.h) in trikeshed forms: the min-max
// heap's push / climb / sift and edge pops, the peg bag's argMin, the cluster's insert routing, min race, find and
// drain, clusterOrder's fill-then-drain, and Krapivin's funnel (the salted splitmix slot, the put/get level walk with
// its rerouting and early exit).  The C++ headers are drop-in bridges: a row crosses as rs opaque bytes (the Inline
// body's cells and its u32 count are the ABI), and Row's `<` / `==` cross as neutral C callbacks
// int(const void *, const void *), so any Row with those operators works unchanged (a null `<` is clusterOrder's
// (i64 key, u32 index) order, built in).  Nothing allocates: the heap and the pegs are inline bodies, as in the C++.
//
// The shapes:
//   rows     a row is rs bytes at base + i*rs (mmx_row, the callbacks' C boundary).  A copy of a row is a drain of its
//            descriptor: a series of i64 words when rs and both addresses are 8-aligned (a 16-byte row is a constant
//            two-word drain), else a series of i8.  A swap is three drains through a stack row (two words for 16 B).
//   indices  the walks over a bag, a cluster, a level or a fill are folds over a slice of one table of the indices
//            0..255 (a constant, `mmx_ids`): fold(slice(ids, from, count), seed) visits them in order, so the
//            callbacks run in the same order as the loops they replace.  N + P <= 256 and n <= 256 (the headers assert).
//   walks    what must stop early (first equal row, the funnel's level walk) is an scf.while over the same slice;
//            folds run every element, so a short-circuit keeps its scf.while.  The heap's climb and sift stay scf.while.
//   choices  the min race is nested scf.if yielding the side (its argMin is computed only where the C++ computed it).
//
// The funnel's bucket layout crosses as byte offsets (the heap's cells at 0, its count at hnOff, the pegs' cells at
// pOff, their count at pnOff, a bucket stride bytes); level l starts at bucket 2*(top - (top>>l)) and holds top>>l.

// The index table: 0..255, the slices every fold and walk here reads.  Private: each lowered object has its own.
memref.global "private" constant @mmx_ids : memref<256xi32> = dense<[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255]>

!b = !trikeshed.series<i8>
!h = !trikeshed.series<i64>
!x = !trikeshed.series<i32>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>
!mb = memref<?xi8, strided<[1], offset: ?>>
!mh = memref<?xi64, strided<[1], offset: ?>>

// The descriptor of n elements at p, any element type (the struct carries none): built inline, no allocation.
func.func private @mmx_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// The address of row i: base + i*rs bytes.
func.func private @mmx_row(%base: !llvm.ptr, %rs: i64, %i: i32) -> !llvm.ptr {
  %i64 = arith.extui %i : i32 to i64
  %off = arith.muli %i64, %rs : i64
  %p = llvm.getelementptr %base[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  return %p : !llvm.ptr
}

// Copy one row: a drain of the row's series into the destination's, as words when rs is a whole number of words (the
// cluster's 16 B rows are a constant two-word drain), else bytes.  A row whole in words is 8-aligned: the C++ rows are
// (MinMaxHeap.h asserts alignof >= 8 for them), so the word lane needs no test per copy.  A row is never copied onto
// itself: the callers that could do so skip it (LLVM would turn the byte drain into a memcpy, undefined for overlap).
func.func private @mmx_copy(%dst: !llvm.ptr, %src: !llvm.ptr, %rs: i64) {
  %c0 = arith.constant 0 : i64
  %c3 = arith.constant 3 : i64
  %c7 = arith.constant 7 : i64
  %c16 = arith.constant 16 : i64
  %rm = arith.andi %rs, %c7 : i64
  %whole = arith.cmpi eq, %rm, %c0 : i64
  scf.if %whole {
    // the cluster's rows are 16 B: a constant two-word drain, unrolled; other whole-word rows take their word count from rs
    %is16 = arith.cmpi eq, %rs, %c16 : i64
    scf.if %is16 {
      %two = arith.constant 2 : i64
      %sd = func.call @mmx_desc(%src, %two) : (!llvm.ptr, i64) -> !d
      %dd = func.call @mmx_desc(%dst, %two) : (!llvm.ptr, i64) -> !d
      %sm = builtin.unrealized_conversion_cast %sd : !d to !mh
      %dm = builtin.unrealized_conversion_cast %dd : !d to !mh
      %ss = builtin.unrealized_conversion_cast %sm : !mh to !h
      %end = trikeshed.drain %ss, %dm : !h, !mh -> index
    } else {
      %nw = arith.shrui %rs, %c3 : i64
      %sd = func.call @mmx_desc(%src, %nw) : (!llvm.ptr, i64) -> !d
      %dd = func.call @mmx_desc(%dst, %nw) : (!llvm.ptr, i64) -> !d
      %sm = builtin.unrealized_conversion_cast %sd : !d to !mh
      %dm = builtin.unrealized_conversion_cast %dd : !d to !mh
      %ss = builtin.unrealized_conversion_cast %sm : !mh to !h
      %end = trikeshed.drain %ss, %dm : !h, !mh -> index
    }
  } else {
    %sd = func.call @mmx_desc(%src, %rs) : (!llvm.ptr, i64) -> !d
    %dd = func.call @mmx_desc(%dst, %rs) : (!llvm.ptr, i64) -> !d
    %sm = builtin.unrealized_conversion_cast %sd : !d to !mb
    %dm = builtin.unrealized_conversion_cast %dd : !d to !mb
    %ss = builtin.unrealized_conversion_cast %sm : !mb to !b
    %end = trikeshed.drain %ss, %dm : !b, !mb -> index
  }
  return
}

// Swap rows x and y (distinct: every caller swaps a row with its parent, child or grandchild).  A 16-byte row swaps
// through a two-word stack temporary of constant size: three two-word drains.  Other rows go through mmx_swap_rows.
func.func private @mmx_swap(%base: !llvm.ptr, %rs: i64, %x: i32, %y: i32) {
  %c2 = arith.constant 2 : i64
  %c16 = arith.constant 16 : i64
  %xp = func.call @mmx_row(%base, %rs, %x) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %yp = func.call @mmx_row(%base, %rs, %y) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %is16 = arith.cmpi eq, %rs, %c16 : i64
  scf.if %is16 {
    %tmp = llvm.alloca %c2 x i64 {alignment = 8 : i64} : (i64) -> !llvm.ptr
    %xd = func.call @mmx_desc(%xp, %c2) : (!llvm.ptr, i64) -> !d
    %yd = func.call @mmx_desc(%yp, %c2) : (!llvm.ptr, i64) -> !d
    %td = func.call @mmx_desc(%tmp, %c2) : (!llvm.ptr, i64) -> !d
    %xm = builtin.unrealized_conversion_cast %xd : !d to !mh
    %ym = builtin.unrealized_conversion_cast %yd : !d to !mh
    %tm = builtin.unrealized_conversion_cast %td : !d to !mh
    %xs = builtin.unrealized_conversion_cast %xm : !mh to !h
    %ys = builtin.unrealized_conversion_cast %ym : !mh to !h
    %ts = builtin.unrealized_conversion_cast %tm : !mh to !h
    %e1 = trikeshed.drain %xs, %tm : !h, !mh -> index
    %e2 = trikeshed.drain %ys, %xm : !h, !mh -> index
    %e3 = trikeshed.drain %ts, %ym : !h, !mh -> index
  } else {
    func.call @mmx_swap_rows(%xp, %yp, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
  return
}

// The other rows' swap, a chunk at a time through one 256-byte stack temporary (a static alloca: a dynamic one in a helper
// that is inlined into a loop would grow the stack on every iteration).  Each chunk is three drains of slices of the rows.
func.func private @mmx_swap_rows(%xp: !llvm.ptr, %yp: !llvm.ptr, %rs: i64) {
  %z = arith.constant 0 : index
  %c256 = arith.constant 256 : index
  %c256_64 = arith.constant 256 : i64
  %tmp = llvm.alloca %c256_64 x i8 {alignment = 8 : i64} : (i64) -> !llvm.ptr
  %n = arith.index_cast %rs : i64 to index
  scf.for %c = %z to %n step %c256 {
    %left = arith.subi %n, %c : index
    %cnt = arith.minui %left, %c256 : index
    %c64 = arith.index_cast %c : index to i64
    %cnt64 = arith.index_cast %cnt : index to i64
    %xc = llvm.getelementptr %xp[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %yc = llvm.getelementptr %yp[%c64] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %xd = func.call @mmx_desc(%xc, %cnt64) : (!llvm.ptr, i64) -> !d
    %yd = func.call @mmx_desc(%yc, %cnt64) : (!llvm.ptr, i64) -> !d
    %td = func.call @mmx_desc(%tmp, %cnt64) : (!llvm.ptr, i64) -> !d
    %xm = builtin.unrealized_conversion_cast %xd : !d to !mb
    %ym = builtin.unrealized_conversion_cast %yd : !d to !mb
    %tm = builtin.unrealized_conversion_cast %td : !d to !mb
    %xs = builtin.unrealized_conversion_cast %xm : !mb to !b
    %ys = builtin.unrealized_conversion_cast %ym : !mb to !b
    %ts = builtin.unrealized_conversion_cast %tm : !mb to !b
    %e1 = trikeshed.drain %xs, %tm : !b, !mb -> index
    %e2 = trikeshed.drain %ys, %xm : !b, !mb -> index
    %e3 = trikeshed.drain %ts, %ym : !b, !mb -> index
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
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %c4 = arith.constant 4 : i32
  %c7 = arith.constant 7 : i32
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
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
    // the grandchildren gs ..< ge: a slice of the index table, none when gs >= ge, folded in index order
    %has4 = arith.cmpi ult, %gs, %ge : i32
    %cnt32 = arith.subi %ge, %gs : i32
    %cnt0 = arith.select %has4, %cnt32, %c0 : i32
    %off0 = arith.select %has4, %gs, %c0 : i32
    %cnt = arith.index_cast %cnt0 : i32 to index
    %off = arith.index_cast %off0 : i32 to index
    %grand = trikeshed.slice %idsS[%off, %cnt] : !x -> !x
    %m = trikeshed.fold %grand, %m0 : !x, i32 -> i32 {
    ^bb0(%best: i32, %g: i32):
      %bg = func.call @mmx_before(%base, %rs, %less, %mf, %g, %best) : (!llvm.ptr, i64, !llvm.ptr, i1, i32, i32) -> i1
      %nb = arith.select %bg, %g, %best : i32
      trikeshed.yield %nb : i32
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
  %moved = arith.cmpi ne, %nm1, %c0 : i32
  scf.if %moved {
    func.call @mmx_copy(%base, %last, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
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
    %moved = arith.cmpi ne, %m, %nm1 : i32
    scf.if %moved {
      func.call @mmx_copy(%mp, %last, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
    llvm.store %nm1, %np : i32, !llvm.ptr
    %below = arith.cmpi ult, %m, %nm1 : i32
    scf.if %below {
      func.call @mmx_sift(%base, %nm1, %rs, %less, %t, %m) : (!llvm.ptr, i32, i64, !llvm.ptr, i1, i32) -> ()
    }
  }
  return
}

// The peg bag's least: argMin, a fold over the indices 1..n-1 of the index table seeded with 0, the first of equals kept
// (0 when empty).  The fold runs every element in order, so the comparator sees the pairs the scf.for did.
func.func @mmx_arg_min(%base: !llvm.ptr, %n: i32, %rs: i64, %less: !llvm.ptr) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %one = arith.constant 1 : index
  %more = arith.cmpi ugt, %n, %c1 : i32
  %nm1 = arith.subi %n, %c1 : i32
  %cnt0 = arith.select %more, %nm1, %c0 : i32
  %cnt = arith.index_cast %cnt0 : i32 to index
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
  %rest = trikeshed.slice %idsS[%one, %cnt] : !x -> !x
  %m = trikeshed.fold %rest, %c0 : !x, i32 -> i32 {
  ^bb0(%best: i32, %k: i32):
    %bp = func.call @mmx_row(%base, %rs, %best) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %kp = func.call @mmx_row(%base, %rs, %k) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %lt = func.call @mmx_cmp(%less, %kp, %bp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i1
    %r = arith.select %lt, %k, %best : i32
    trikeshed.yield %r : i32
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
  %lastRow = func.call @mmx_row(%pb, %rs, %nm1) : (!llvm.ptr, i64, i32) -> !llvm.ptr
  %moved = arith.cmpi ne, %m, %nm1 : i32
  scf.if %moved {
    func.call @mmx_copy(%mp, %lastRow, %rs) : (!llvm.ptr, !llvm.ptr, i64) -> ()
  }
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

// firstWhere(rows, == r) over n rows: the first equal row, or null.  A short-circuit: the rows after a match are never
// compared, so this is an scf.while over the positions, not a fold.
func.func @mmx_first_eq(%base: !llvm.ptr, %n: i32, %rs: i64, %eq: !llvm.ptr, %r: !llvm.ptr) -> !llvm.ptr {
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
// emit(ctx, row).  The emits are a fold over the first hn+pn indices of the table.
func.func @mmx_cluster_drain(%hb: !llvm.ptr, %hnp: !llvm.ptr, %pb: !llvm.ptr, %pnp: !llvm.ptr, %rs: i64,
    %less: !llvm.ptr, %ctx: !llvm.ptr, %emit: !llvm.ptr) {
  %z = arith.constant 0 : index
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %hn = llvm.load %hnp : !llvm.ptr -> i32
  %pn = llvm.load %pnp : !llvm.ptr -> i32
  %total = arith.addi %hn, %pn : i32
  %totalI = arith.index_cast %total : i32 to index
  %tmp = llvm.alloca %rs x i8 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
  %all = trikeshed.slice %idsS[%z, %totalI] : !x -> !x
  %emitted = trikeshed.fold %all, %c0 : !x, i32 -> i32 {
  ^bb0(%acc: i32, %k: i32):
    func.call @mmx_cluster_pop_min(%hb, %hnp, %pb, %pnp, %rs, %less, %tmp) : (!llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr, i64, !llvm.ptr, !llvm.ptr) -> ()
    llvm.call %emit(%ctx, %tmp) : !llvm.ptr, (!llvm.ptr, !llvm.ptr) -> ()
    %a1 = arith.addi %acc, %c1 : i32
    trikeshed.yield %a1 : i32
  }
  return
}

// clusterOrder's fill-then-drain: every one of the n rows inserted (the caller keeps n within the cluster), then the
// cluster drained to emit.  The fill is a fold over the first n indices.
func.func @mmx_order(%hb: !llvm.ptr, %hnp: !llvm.ptr, %capN: i32, %pb: !llvm.ptr, %pnp: !llvm.ptr, %capP: i32,
    %rs: i64, %less: !llvm.ptr, %rows: !llvm.ptr, %n: i32, %ctx: !llvm.ptr, %emit: !llvm.ptr) {
  %z = arith.constant 0 : index
  %c0 = arith.constant 0 : i32
  %nI = arith.index_cast %n : i32 to index
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
  %all = trikeshed.slice %idsS[%z, %nI] : !x -> !x
  %filled = trikeshed.fold %all, %c0 : !x, i32 -> i32 {
  ^bb0(%acc: i32, %k: i32):
    %rp = func.call @mmx_row(%rows, %rs, %k) : (!llvm.ptr, i64, i32) -> !llvm.ptr
    %st = func.call @mmx_cluster_insert(%hb, %hnp, %capN, %pb, %pnp, %capP, %rs, %less, %rp) : (!llvm.ptr, !llvm.ptr, i32, !llvm.ptr, !llvm.ptr, i32, i64, !llvm.ptr, !llvm.ptr) -> i32
    trikeshed.yield %acc : i32
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

// put: walk the levels (a slice of the index table: level l at position l), the row's bucket at each; a stored key
// refuses (0xFF), a bucket with room takes the row and its level is the answer (the row count bumped), a full bucket
// reroutes one level down.  Every level full: 0xFE.
func.func @mmx_funnel_put(%cells: !llvm.ptr, %top: i32, %levels: i32, %rowsp: !llvm.ptr, %rs: i64, %capN: i32,
    %capP: i32, %hnOff: i64, %pOff: i64, %pnOff: i64, %stride: i64, %less: !llvm.ptr, %eq: !llvm.ptr,
    %r: !llvm.ptr, %h: i64) -> i32 {
  %undecided = arith.constant -1 : i32
  %c0 = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c1 = arith.constant 1 : i32
  %c2 = arith.constant 2 : i32
  %cff = arith.constant 255 : i32
  %cfe = arith.constant 254 : i32
  %null = llvm.mlir.zero : !llvm.ptr
  %levelsI = arith.index_cast %levels : i32 to index
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
  %lvls = trikeshed.slice %idsS[%c0, %levelsI] : !x -> !x
  %w:2 = scf.while (%p = %c0, %ret = %undecided) : (index, i32) -> (index, i32) {
    %lt = arith.cmpi ult, %p, %levelsI : index
    %und = arith.cmpi eq, %ret, %undecided : i32
    %go = arith.andi %lt, %und : i1
    scf.condition(%go) %p, %ret : index, i32
  } do {
  ^bb0(%pp: index, %rv: i32):
    %lv = trikeshed.at %lvls[%pp] : !x, index -> i32
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
    %p1 = arith.addi %pp, %one : index
    scf.yield %p1, %r1 : index, i32
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
  %c0i = arith.constant 0 : index
  %one = arith.constant 1 : index
  %c1 = arith.constant 1 : i32
  %t = arith.constant 1 : i1
  %f = arith.constant 0 : i1
  %null = llvm.mlir.zero : !llvm.ptr
  %counting = llvm.icmp "ne" %probesp, %null : !llvm.ptr
  %levelsI = arith.index_cast %levels : i32 to index
  %ids = memref.get_global @mmx_ids : memref<256xi32>
  %idsS = trikeshed.text %ids : memref<256xi32> -> !x
  %lvls = trikeshed.slice %idsS[%c0i, %levelsI] : !x -> !x
  %w:3 = scf.while (%p = %c0i, %fr = %null, %stop = %f) : (index, !llvm.ptr, i1) -> (index, !llvm.ptr, i1) {
    %lt = arith.cmpi ult, %p, %levelsI : index
    %none = llvm.icmp "eq" %fr, %null : !llvm.ptr
    %more = arith.xori %stop, %t : i1
    %a1 = arith.andi %lt, %none : i1
    %go = arith.andi %a1, %more : i1
    scf.condition(%go) %p, %fr, %stop : index, !llvm.ptr, i1
  } do {
  ^bb0(%pp: index, %fv: !llvm.ptr, %sv: i1):
    %lv = trikeshed.at %lvls[%pp] : !x, index -> i32
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
    %p1 = arith.addi %pp, %one : index
    scf.yield %p1, %ff, %room : index, !llvm.ptr, i1
  }
  return %w#1 : !llvm.ptr
}
