// Composite/Rows.h's row algorithms (neutral C ABI; Rows.h is the bridge).  Rows of any width are bytes at a stride:
// keyed rows (Attr, an attrs shape's symbol: a leading u32 key, alignof >= 4) are w = rowBytes / 4 words each, so a row
// set of n rows is a !trikeshed.series<i32> of n * w words, and a row is the slice [r * w, w) of it -- what
// ReifiedSplitSeries2's reify/take/splitSelect state for a row of width w.  The keys are the series `n j {r -> words[r * w]}`,
// pure, so trikeshed-lower-cursors reads it where the rows lie: a bisect over it reads log n keys, never a buffer of n.
//   find          findRow's branchless search over the key series (trikeshed.at probes; the loop's trip count is n's alone,
//                 so it stays as fast as the llvm port -- a bisect, whose exit depends on the keys, measured 2-5x slower
//                 on Bindings::get's path): the last row whose key is <= k, if its key is k, or 0
//   uniqueFirst   trikeshed.zipnext of the keys: row i + 1 is kept where its pair differs, drained to the front as a slice
//                 of the words; zipnext's sides are slices of the key series, read in place, so nothing is allocated
//   union         y winning on an equal key.  When y is a sixteenth of x or less, each y row's lower bound in x is a
//                 bisect over a slice of x's keys from where the last one ended, and the run of x before it is ONE drain
//                 of a slice; else a merge walk over the two key series, a row drained at a time, then the tails.
//                 union_size is the same walks, counting.
// Keys compare unsigned (u32).  The sorts (sortRows' comparator calls in the template's order, a throw unwinding
// through these frames; sortRowsByKey's u32 form) stay scf/arith/llvm below: the comparator's call order is the contract.
// Helper names are module-unique (rows_*, nx_rows_*): the pipeline exports func.func private as global symbols.
!w = !trikeshed.series<i32>
!z = !trikeshed.series2<i32, i32>
!s = !trikeshed.series<i64>
!m = memref<?xi32, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the descriptor of n i32 words at p (a struct: returning it allocates nothing and clones nothing)
func.func private @rows_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

func.func @mlnix_rows_find(%rows: !llvm.ptr, %rb: i64, %n: i64, %k: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c4 = arith.constant 4 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %w = arith.divui %rb, %c4 : i64
  %nw = arith.muli %n, %w : i64
  %d = func.call @rows_desc(%rows, %nw) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %d : !d to !m
  %words = builtin.unrealized_conversion_cast %dm : !m to !w
  %wi = arith.index_cast %w : i64 to index
  %ni = arith.index_cast %n : i64 to index
  %keys = trikeshed.series %ni : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %words[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  // findRow's branchless search: the base moves by half while the key there is <= k (the trip count is n's alone)
  %k32 = arith.trunci %k : i64 to i32
  %none = arith.cmpi eq, %ni, %i0 : index
  %r = scf.if %none -> i64 {
    scf.yield %c0 : i64
  } else {
    %s:2 = scf.while (%base = %i0, %nn = %ni) : (index, index) -> (index, index) {
      %half = arith.shrui %nn, %i1 : index
      %go = arith.cmpi ne, %half, %i0 : index
      scf.condition(%go) %base, %nn : index, index
    } do {
    ^bb0(%base: index, %nn: index):
      %half = arith.shrui %nn, %i1 : index
      %probe = arith.addi %base, %half : index
      %key = trikeshed.at %keys[%probe] : !w, index -> i32
      %le = arith.cmpi ule, %key, %k32 : i32
      %b2 = arith.select %le, %probe, %base : index
      %n2 = arith.subi %nn, %half : index
      scf.yield %b2, %n2 : index, index
    }
    %key = trikeshed.at %keys[%s#0] : !w, index -> i32
    %eq = arith.cmpi eq, %key, %k32 : i32
    %l64 = arith.index_cast %s#0 : index to i64
    %off = arith.muli %l64, %rb : i64
    %p = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %pi = llvm.ptrtoint %p : !llvm.ptr to i64
    %v = arith.select %eq, %pi, %c0 : i64
    scf.yield %v : i64
  }
  return %r : i64
}

func.func @mlnix_rows_unique_first(%rows: !llvm.ptr, %rb: i64, %n: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %w = arith.divui %rb, %c4 : i64
  %nw = arith.muli %n, %w : i64
  %d = func.call @rows_desc(%rows, %nw) : (!llvm.ptr, i64) -> !d
  %dm = builtin.unrealized_conversion_cast %d : !d to !m
  %words = builtin.unrealized_conversion_cast %dm : !m to !w
  %wi = arith.index_cast %w : i64 to index
  %ni = arith.index_cast %n : i64 to index
  %keys = trikeshed.series %ni : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %words[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  %z = trikeshed.zipnext %keys : !w -> !z
  %l = trikeshed.leftOf %z : !z -> !w
  %rt = trikeshed.rightOf %z : !z -> !w
  %np = trikeshed.size %l : !w
  // row i + 1 opens a run where its key differs from row i's, and is drained to the front there.  A step reads rows i and
  // i + 1 before it writes, and a write lands at or before the row it copies, so every key read is its row's own.
  %m = scf.for %i = %i0 to %np step %i1 iter_args(%mm = %i1) -> (index) {
    %a = trikeshed.at %l[%i] : !w, index -> i32
    %b = trikeshed.at %rt[%i] : !w, index -> i32
    %ne = arith.cmpi ne, %a, %b : i32
    %mm2 = scf.if %ne -> index {
      %src = arith.addi %i, %i1 : index
      %from = arith.muli %src, %wi : index
      %to = arith.muli %mm, %wi : index
      %row = trikeshed.slice %words[%from, %wi] : !w -> !w
      %cells = memref.subview %dm[%to] [%wi] [1] : !m to !m
      %e = trikeshed.drain %row, %cells : !w, !m -> index
      %mp = arith.addi %mm, %i1 : index
      scf.yield %mp : index
    } else {
      scf.yield %mm : index
    }
    scf.yield %mm2 : index
  }
  %any = arith.cmpi ugt, %n, %c0 : i64
  %m64 = arith.index_cast %m : index to i64
  %r = arith.select %any, %m64, %c0 : i64
  return %r : i64
}

func.func @mlnix_rows_union_size(%x: !llvm.ptr, %rb: i64, %nx: i64, %y: !llvm.ptr, %ny: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %c4 = arith.constant 4 : i64
  %c16 = arith.constant 16 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %w = arith.divui %rb, %c4 : i64
  %wi = arith.index_cast %w : i64 to index
  %nwx = arith.muli %nx, %w : i64
  %nwy = arith.muli %ny, %w : i64
  %dx = func.call @rows_desc(%x, %nwx) : (!llvm.ptr, i64) -> !d
  %dy = func.call @rows_desc(%y, %nwy) : (!llvm.ptr, i64) -> !d
  %dxm = builtin.unrealized_conversion_cast %dx : !d to !m
  %dym = builtin.unrealized_conversion_cast %dy : !d to !m
  %xw = builtin.unrealized_conversion_cast %dxm : !m to !w
  %yw = builtin.unrealized_conversion_cast %dym : !m to !w
  %nxi = arith.index_cast %nx : i64 to index
  %nyi = arith.index_cast %ny : i64 to index
  %xk = trikeshed.series %nxi : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %xw[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  %yk = trikeshed.series %nyi : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %yw[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  %ny16 = arith.muli %ny, %c16 : i64
  %small = arith.cmpi ult, %ny16, %nx : i64
  %res = scf.if %small -> i64 {
    %sh:2 = scf.for %j = %i0 to %nyi step %i1 iter_args(%ii = %i0, %shared = %c0) -> (index, i64) {
      %ky = trikeshed.at %yk[%j] : !w, index -> i32
      %rest = arith.subi %nxi, %ii : index
      %tail = trikeshed.slice %xk[%ii, %rest] : !w -> !w
      %b = trikeshed.bisect %tail, %ky : !w, i32 -> index by {
      ^bb0(%e: i32, %kk: i32):
        %lt = arith.cmpi ult, %e, %kk : i32
        %m1 = arith.constant -1 : i32
        %p1 = arith.constant 1 : i32
        %o = arith.select %lt, %m1, %p1 : i32
        trikeshed.yield %o : i32
      }
      %neg = arith.subi %i0, %b : index
      %ins = arith.subi %neg, %i1 : index
      %lb = arith.addi %ii, %ins : index
      %inx = arith.cmpi ult, %lb, %nxi : index
      %eq = scf.if %inx -> i1 {
        %kx = trikeshed.at %xk[%lb] : !w, index -> i32
        %e = arith.cmpi eq, %kx, %ky : i32
        scf.yield %e : i1
      } else {
        %f = arith.constant false
        scf.yield %f : i1
      }
      %lb1 = arith.addi %lb, %i1 : index
      %s1 = arith.addi %shared, %c1 : i64
      %ii2 = arith.select %eq, %lb1, %lb : index
      %sh2 = arith.select %eq, %s1, %shared : i64
      scf.yield %ii2, %sh2 : index, i64
    }
    %t = arith.addi %nx, %ny : i64
    %r = arith.subi %t, %sh#1 : i64
    scf.yield %r : i64
  } else {
    %mw:3 = scf.while (%i = %i0, %j = %i0, %cnt = %c0) : (index, index, i64) -> (index, index, i64) {
      %ic = arith.cmpi ult, %i, %nxi : index
      %jc = arith.cmpi ult, %j, %nyi : index
      %both = arith.andi %ic, %jc : i1
      scf.condition(%both) %i, %j, %cnt : index, index, i64
    } do {
    ^bb0(%i: index, %j: index, %cnt: i64):
      %kx = trikeshed.at %xk[%i] : !w, index -> i32
      %ky = trikeshed.at %yk[%j] : !w, index -> i32
      %eq = arith.cmpi eq, %kx, %ky : i32
      %lt = arith.cmpi ult, %kx, %ky : i32
      %ip = arith.addi %i, %i1 : index
      %jp = arith.addi %j, %i1 : index
      %ieq = arith.select %eq, %ip, %i : index
      %jeq = arith.select %eq, %jp, %j : index
      %i2 = arith.select %lt, %ip, %ieq : index
      %j2 = arith.select %lt, %jeq, %jp : index
      %cn = arith.addi %cnt, %c1 : i64
      scf.yield %i2, %j2, %cn : index, index, i64
    }
    %i64 = arith.index_cast %mw#0 : index to i64
    %j64 = arith.index_cast %mw#1 : index to i64
    %ri = arith.subi %nx, %i64 : i64
    %rj = arith.subi %ny, %j64 : i64
    %s1 = arith.addi %mw#2, %ri : i64
    %s2 = arith.addi %s1, %rj : i64
    scf.yield %s2 : i64
  }
  return %res : i64
}

func.func @mlnix_rows_union_into(%x: !llvm.ptr, %rb: i64, %nx: i64, %y: !llvm.ptr, %ny: i64, %out: !llvm.ptr) -> i64 {
  %c4 = arith.constant 4 : i64
  %c16 = arith.constant 16 : i64
  %i0 = arith.constant 0 : index
  %i1 = arith.constant 1 : index
  %w = arith.divui %rb, %c4 : i64
  %wi = arith.index_cast %w : i64 to index
  %nwx = arith.muli %nx, %w : i64
  %nwy = arith.muli %ny, %w : i64
  %nwo = arith.addi %nwx, %nwy : i64
  %dx = func.call @rows_desc(%x, %nwx) : (!llvm.ptr, i64) -> !d
  %dy = func.call @rows_desc(%y, %nwy) : (!llvm.ptr, i64) -> !d
  %do = func.call @rows_desc(%out, %nwo) : (!llvm.ptr, i64) -> !d
  %dxm = builtin.unrealized_conversion_cast %dx : !d to !m
  %dym = builtin.unrealized_conversion_cast %dy : !d to !m
  %om = builtin.unrealized_conversion_cast %do : !d to !m
  %xw = builtin.unrealized_conversion_cast %dxm : !m to !w
  %yw = builtin.unrealized_conversion_cast %dym : !m to !w
  %nxi = arith.index_cast %nx : i64 to index
  %nyi = arith.index_cast %ny : i64 to index
  %xk = trikeshed.series %nxi : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %xw[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  %yk = trikeshed.series %nyi : !w {
  ^bb0(%r: index):
    %at = arith.muli %r, %wi : index
    %key = trikeshed.at %yw[%at] : !w, index -> i32
    trikeshed.yield %key : i32
  }
  %ny16 = arith.muli %ny, %c16 : i64
  %big = arith.cmpi uge, %ny16, %nx : i64
  %res = scf.if %big -> index {
    %uw:3 = scf.while (%i = %i0, %j = %i0, %k = %i0) : (index, index, index) -> (index, index, index) {
      %ic = arith.cmpi ult, %i, %nxi : index
      %jc = arith.cmpi ult, %j, %nyi : index
      %both = arith.andi %ic, %jc : i1
      scf.condition(%both) %i, %j, %k : index, index, index
    } do {
    ^bb0(%i: index, %j: index, %k: index):
      %kx = trikeshed.at %xk[%i] : !w, index -> i32
      %ky = trikeshed.at %yk[%j] : !w, index -> i32
      %eq = arith.cmpi eq, %kx, %ky : i32
      %lt = arith.cmpi ult, %kx, %ky : i32
      %to = arith.muli %k, %wi : index
      %cells = memref.subview %om[%to] [%wi] [1] : !m to !m
      // x's row only where its key is strictly less; y's on an equal key or a greater one
      scf.if %lt {
        %from = arith.muli %i, %wi : index
        %row = trikeshed.slice %xw[%from, %wi] : !w -> !w
        %e = trikeshed.drain %row, %cells : !w, !m -> index
      } else {
        %from = arith.muli %j, %wi : index
        %row = trikeshed.slice %yw[%from, %wi] : !w -> !w
        %e = trikeshed.drain %row, %cells : !w, !m -> index
      }
      %ip = arith.addi %i, %i1 : index
      %jp = arith.addi %j, %i1 : index
      %kp = arith.addi %k, %i1 : index
      %ieq = arith.select %eq, %ip, %i : index
      %jeq = arith.select %eq, %jp, %j : index
      %i2 = arith.select %lt, %ip, %ieq : index
      %j2 = arith.select %lt, %jeq, %jp : index
      scf.yield %i2, %j2, %kp : index, index, index
    }
    // the tails: what is left of x, then of y, one drain each
    %rx = arith.subi %nxi, %uw#0 : index
    %fx = arith.muli %uw#0, %wi : index
    %cx = arith.muli %rx, %wi : index
    %tx = arith.muli %uw#2, %wi : index
    %xt = trikeshed.slice %xw[%fx, %cx] : !w -> !w
    %ox = memref.subview %om[%tx] [%cx] [1] : !m to !m
    %ex = trikeshed.drain %xt, %ox : !w, !m -> index
    %k2 = arith.addi %uw#2, %rx : index
    %ry = arith.subi %nyi, %uw#1 : index
    %fy = arith.muli %uw#1, %wi : index
    %cy = arith.muli %ry, %wi : index
    %ty = arith.muli %k2, %wi : index
    %yt = trikeshed.slice %yw[%fy, %cy] : !w -> !w
    %oy = memref.subview %om[%ty] [%cy] [1] : !m to !m
    %ey = trikeshed.drain %yt, %oy : !w, !m -> index
    %k3 = arith.addi %k2, %ry : index
    scf.yield %k3 : index
  } else {
    %ik:2 = scf.for %j = %i0 to %nyi step %i1 iter_args(%ii = %i0, %kk = %i0) -> (index, index) {
      %ky = trikeshed.at %yk[%j] : !w, index -> i32
      %rest = arith.subi %nxi, %ii : index
      %tail = trikeshed.slice %xk[%ii, %rest] : !w -> !w
      %b = trikeshed.bisect %tail, %ky : !w, i32 -> index by {
      ^bb0(%e: i32, %kk2: i32):
        %lt = arith.cmpi ult, %e, %kk2 : i32
        %m1 = arith.constant -1 : i32
        %p1 = arith.constant 1 : i32
        %o = arith.select %lt, %m1, %p1 : i32
        trikeshed.yield %o : i32
      }
      %neg = arith.subi %i0, %b : index
      %run = arith.subi %neg, %i1 : index
      %lb = arith.addi %ii, %run : index
      // the run of x before it, one drain; then y's row
      %fx = arith.muli %ii, %wi : index
      %cx = arith.muli %run, %wi : index
      %tx = arith.muli %kk, %wi : index
      %xr = trikeshed.slice %xw[%fx, %cx] : !w -> !w
      %ox = memref.subview %om[%tx] [%cx] [1] : !m to !m
      %ex = trikeshed.drain %xr, %ox : !w, !m -> index
      %ky1 = arith.addi %kk, %run : index
      %fy = arith.muli %j, %wi : index
      %ty = arith.muli %ky1, %wi : index
      %yr = trikeshed.slice %yw[%fy, %wi] : !w -> !w
      %oy = memref.subview %om[%ty] [%wi] [1] : !m to !m
      %ey = trikeshed.drain %yr, %oy : !w, !m -> index
      %k1 = arith.addi %ky1, %i1 : index
      %inx = arith.cmpi ult, %lb, %nxi : index
      %eq = scf.if %inx -> i1 {
        %kx = trikeshed.at %xk[%lb] : !w, index -> i32
        %e = arith.cmpi eq, %kx, %ky : i32
        scf.yield %e : i1
      } else {
        %f = arith.constant false
        scf.yield %f : i1
      }
      %lb1 = arith.addi %lb, %i1 : index
      %ii2 = arith.select %eq, %lb1, %lb : index
      scf.yield %ii2, %k1 : index, index
    }
    %rx = arith.subi %nxi, %ik#0 : index
    %fx = arith.muli %ik#0, %wi : index
    %cx = arith.muli %rx, %wi : index
    %tx = arith.muli %ik#1, %wi : index
    %xt = trikeshed.slice %xw[%fx, %cx] : !w -> !w
    %ox = memref.subview %om[%tx] [%cx] [1] : !m to !m
    %ex = trikeshed.drain %xt, %ox : !w, !m -> index
    %k2 = arith.addi %ik#1, %rx : index
    scf.yield %k2 : index
  }
  %r = arith.index_cast %res : index to i64
  return %r : i64
}

// The sorts: kRun = 24 insertion-sorted runs merged bottom-up (stable: the right run only when strictly less),
// mlnix_rows_sort calling the C++ comparator back for each comparison in the template's order, mlnix_rows_sort_u32
// comparing the leading u32 keys itself; the bridge owns the merge's temp run.
func.func private @nx_rows_copy1(%dst: !llvm.ptr, %src: !llvm.ptr, %rb: i64) {
  %k0 = arith.constant 8 : i64
  %k1 = arith.constant 16 : i64
  %is161 = arith.cmpi eq, %rb, %k1 : i64
  scf.if %is161 {
    %w2 = llvm.load %src {alignment = 1 : i64} : !llvm.ptr -> i64
    %s83 = llvm.getelementptr %src[8] : (!llvm.ptr) -> !llvm.ptr, i8
    %w4 = llvm.load %s83 {alignment = 1 : i64} : !llvm.ptr -> i64
    %d85 = llvm.getelementptr %dst[8] : (!llvm.ptr) -> !llvm.ptr, i8
    llvm.store %w2, %dst {alignment = 1 : i64} : i64, !llvm.ptr
    llvm.store %w4, %d85 {alignment = 1 : i64} : i64, !llvm.ptr
  } else {
    %is86 = arith.cmpi eq, %rb, %k0 : i64
    scf.if %is86 {
      %w7 = llvm.load %src {alignment = 1 : i64} : !llvm.ptr -> i64
      llvm.store %w7, %dst {alignment = 1 : i64} : i64, !llvm.ptr
    } else {
      "llvm.intr.memcpy"(%dst, %src, %rb) <{isVolatile = false}> : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  return
}

// the leading u32 key of the row at p: a view of its one word
func.func private @nx_rows_key(%p: !llvm.ptr) -> i32 {
  %c1 = arith.constant 1 : i64
  %i0 = arith.constant 0 : index
  %d = func.call @rows_desc(%p, %c1) : (!llvm.ptr, i64) -> !d
  %m = builtin.unrealized_conversion_cast %d : !d to !m
  %w = builtin.unrealized_conversion_cast %m : !m to !w
  %k = trikeshed.at %w[%i0] : !w, index -> i32
  return %k : i32
}

func.func @mlnix_rows_sort(%src: !llvm.ptr, %dst: !llvm.ptr, %temp: !llvm.ptr, %n: i64, %rb: i64, %less: (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32, %ctx: !llvm.ptr) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 24 : i64
  %k4 = arith.constant 0 : index
  %k5 = arith.constant 1 : index
  %k6 = arith.constant 24 : index
  %k7 = arith.constant 0 : i1
  %k8 = arith.constant 0 : i32
  %xbuf1 = llvm.alloca %rb x i8 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  %pw2:2 = scf.while (%w = %k3, %p = %k0) : (i64, i64) -> (i64, i64) {
    %go3 = arith.cmpi ult, %w, %n : i64
    scf.condition(%go3) %w, %p : i64, i64
  } do {
  ^bb0(%w: i64, %p: i64):
    %w24 = arith.muli %w, %k2 : i64
    %p25 = arith.addi %p, %k1 : i64
    scf.yield %w24, %p25 : i64, i64
  }
  %odd6 = arith.andi %pw2#1, %k1 : i64
  %isodd7 = arith.cmpi ne, %odd6, %k0 : i64
  %a08 = arith.select %isodd7, %temp, %dst : !llvm.ptr
  %b09 = arith.select %isodd7, %dst, %temp : !llvm.ptr
  %ix10 = arith.index_cast %n : i64 to index
  scf.for %lo11 = %k4 to %ix10 step %k6 {
  %i612 = arith.index_cast %lo11 : index to i64
    %lo2413 = arith.addi %i612, %k3 : i64
  %mn14 = arith.minui %lo2413, %n : i64
  %ix15 = arith.index_cast %mn14 : i64 to index
    scf.for %i16 = %lo11 to %ix15 step %k5 {
  %i617 = arith.index_cast %i16 : index to i64
  %off18 = arith.muli %i617, %rb : i64
  %p19 = llvm.getelementptr %src[%off18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%xbuf1, %p19, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %kw20 = scf.while (%k = %i617) : (i64) -> (i64) {
        %kgt21 = arith.cmpi ugt, %k, %i612 : i64
        %cond22 = scf.if %kgt21 -> i1 {
          %km123 = arith.subi %k, %k1 : i64
  %off24 = arith.muli %km123, %rb : i64
  %p25 = llvm.getelementptr %a08[%off24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
          %c26 = func.call_indirect %less(%ctx, %xbuf1, %p25) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
          %cb27 = arith.cmpi ne, %c26, %k8 : i32
          scf.yield %cb27 : i1
        } else {
          scf.yield %k7 : i1
        }
        scf.condition(%cond22) %k : i64
      } do {
      ^bb0(%k: i64):
        %km128 = arith.subi %k, %k1 : i64
  %off29 = arith.muli %km128, %rb : i64
  %p30 = llvm.getelementptr %a08[%off29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off31 = arith.muli %k, %rb : i64
  %p32 = llvm.getelementptr %a08[%off31] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p32, %p30, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %k233 = arith.subi %k, %k1 : i64
        scf.yield %k233 : i64
      }
  %off34 = arith.muli %kw20, %rb : i64
  %p35 = llvm.getelementptr %a08[%off34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p35, %xbuf1, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  %mw36:3 = scf.while (%w = %k3, %a = %a08, %b = %b09) : (i64, !llvm.ptr, !llvm.ptr) -> (i64, !llvm.ptr, !llvm.ptr) {
    %go37 = arith.cmpi ult, %w, %n : i64
    scf.condition(%go37) %w, %a, %b : i64, !llvm.ptr, !llvm.ptr
  } do {
  ^bb0(%w: i64, %a: !llvm.ptr, %b: !llvm.ptr):
    %w238 = arith.muli %w, %k2 : i64
  %ix39 = arith.index_cast %w238 : i64 to index
    scf.for %mlo40 = %k4 to %ix10 step %ix39 {
  %i641 = arith.index_cast %mlo40 : index to i64
      %lw42 = arith.addi %i641, %w : i64
  %mn43 = arith.minui %lw42, %n : i64
      %l2w44 = arith.addi %i641, %w238 : i64
  %mn45 = arith.minui %l2w44, %n : i64
      %mg46:3 = scf.while (%i = %i641, %j = %mn43, %k = %i641) : (i64, i64, i64) -> (i64, i64, i64) {
        %ic47 = arith.cmpi ult, %i, %mn43 : i64
        %jc48 = arith.cmpi ult, %j, %mn45 : i64
        %both49 = arith.andi %ic47, %jc48 : i1
        scf.condition(%both49) %i, %j, %k : i64, i64, i64
      } do {
      ^bb0(%i: i64, %j: i64, %k: i64):
  %off50 = arith.muli %j, %rb : i64
  %p51 = llvm.getelementptr %a[%off50] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off52 = arith.muli %i, %rb : i64
  %p53 = llvm.getelementptr %a[%off52] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        %c54 = func.call_indirect %less(%ctx, %p51, %p53) : (!llvm.ptr, !llvm.ptr, !llvm.ptr) -> i32
        %cb55 = arith.cmpi ne, %c54, %k8 : i32
  %off56 = arith.muli %k, %rb : i64
  %p57 = llvm.getelementptr %b[%off56] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        scf.if %cb55 {
  func.call @nx_rows_copy1(%p57, %p51, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        } else {
  func.call @nx_rows_copy1(%p57, %p53, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        }
        %ip58 = arith.addi %i, %k1 : i64
        %jp59 = arith.addi %j, %k1 : i64
        %kp60 = arith.addi %k, %k1 : i64
        %jn61 = arith.select %cb55, %jp59, %j : i64
        %in62 = arith.select %cb55, %i, %ip58 : i64
        scf.yield %in62, %jn61, %kp60 : i64, i64, i64
      }
      %di63:2 = scf.while (%i = %mg46#0, %k = %mg46#2) : (i64, i64) -> (i64, i64) {
        %go64 = arith.cmpi ult, %i, %mn43 : i64
        scf.condition(%go64) %i, %k : i64, i64
      } do {
      ^bb0(%i: i64, %k: i64):
  %off65 = arith.muli %i, %rb : i64
  %p66 = llvm.getelementptr %a[%off65] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off67 = arith.muli %k, %rb : i64
  %p68 = llvm.getelementptr %b[%off67] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p68, %p66, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %ip69 = arith.addi %i, %k1 : i64
        %kp70 = arith.addi %k, %k1 : i64
        scf.yield %ip69, %kp70 : i64, i64
      }
      %dj71:2 = scf.while (%j = %mg46#1, %k = %di63#1) : (i64, i64) -> (i64, i64) {
        %go72 = arith.cmpi ult, %j, %mn45 : i64
        scf.condition(%go72) %j, %k : i64, i64
      } do {
      ^bb0(%j: i64, %k: i64):
  %off73 = arith.muli %j, %rb : i64
  %p74 = llvm.getelementptr %a[%off73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off75 = arith.muli %k, %rb : i64
  %p76 = llvm.getelementptr %b[%off75] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p76, %p74, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %jp77 = arith.addi %j, %k1 : i64
        %kp78 = arith.addi %k, %k1 : i64
        scf.yield %jp77, %kp78 : i64, i64
      }
    }
    scf.yield %w238, %b, %a : i64, !llvm.ptr, !llvm.ptr
  }
  return
}

func.func @mlnix_rows_sort_u32(%src: !llvm.ptr, %dst: !llvm.ptr, %temp: !llvm.ptr, %n: i64, %rb: i64) {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 2 : i64
  %k3 = arith.constant 24 : i64
  %k4 = arith.constant 0 : index
  %k5 = arith.constant 1 : index
  %k6 = arith.constant 24 : index
  %k7 = arith.constant 0 : i1
  %k8 = arith.constant 0 : i32
  %xbuf1 = llvm.alloca %rb x i8 {alignment = 16 : i64} : (i64) -> !llvm.ptr
  %pw2:2 = scf.while (%w = %k3, %p = %k0) : (i64, i64) -> (i64, i64) {
    %go3 = arith.cmpi ult, %w, %n : i64
    scf.condition(%go3) %w, %p : i64, i64
  } do {
  ^bb0(%w: i64, %p: i64):
    %w24 = arith.muli %w, %k2 : i64
    %p25 = arith.addi %p, %k1 : i64
    scf.yield %w24, %p25 : i64, i64
  }
  %odd6 = arith.andi %pw2#1, %k1 : i64
  %isodd7 = arith.cmpi ne, %odd6, %k0 : i64
  %a08 = arith.select %isodd7, %temp, %dst : !llvm.ptr
  %b09 = arith.select %isodd7, %dst, %temp : !llvm.ptr
  %ix10 = arith.index_cast %n : i64 to index
  scf.for %lo11 = %k4 to %ix10 step %k6 {
  %i612 = arith.index_cast %lo11 : index to i64
    %lo2413 = arith.addi %i612, %k3 : i64
  %mn14 = arith.minui %lo2413, %n : i64
  %ix15 = arith.index_cast %mn14 : i64 to index
    scf.for %i16 = %lo11 to %ix15 step %k5 {
  %i617 = arith.index_cast %i16 : index to i64
  %off18 = arith.muli %i617, %rb : i64
  %p19 = llvm.getelementptr %src[%off18] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%xbuf1, %p19, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %kw20 = scf.while (%k = %i617) : (i64) -> (i64) {
        %kgt21 = arith.cmpi ugt, %k, %i612 : i64
        %cond22 = scf.if %kgt21 -> i1 {
          %km123 = arith.subi %k, %k1 : i64
  %off24 = arith.muli %km123, %rb : i64
  %p25 = llvm.getelementptr %a08[%off24] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3226 = func.call @nx_rows_key(%xbuf1) : (!llvm.ptr) -> i32
  %k3228 = func.call @nx_rows_key(%p25) : (!llvm.ptr) -> i32
          %cb30 = arith.cmpi ult, %k3226, %k3228 : i32
          scf.yield %cb30 : i1
        } else {
          scf.yield %k7 : i1
        }
        scf.condition(%cond22) %k : i64
      } do {
      ^bb0(%k: i64):
        %km131 = arith.subi %k, %k1 : i64
  %off32 = arith.muli %km131, %rb : i64
  %p33 = llvm.getelementptr %a08[%off32] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off34 = arith.muli %k, %rb : i64
  %p35 = llvm.getelementptr %a08[%off34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p35, %p33, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %k236 = arith.subi %k, %k1 : i64
        scf.yield %k236 : i64
      }
  %off37 = arith.muli %kw20, %rb : i64
  %p38 = llvm.getelementptr %a08[%off37] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p38, %xbuf1, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    }
  }
  %mw39:3 = scf.while (%w = %k3, %a = %a08, %b = %b09) : (i64, !llvm.ptr, !llvm.ptr) -> (i64, !llvm.ptr, !llvm.ptr) {
    %go40 = arith.cmpi ult, %w, %n : i64
    scf.condition(%go40) %w, %a, %b : i64, !llvm.ptr, !llvm.ptr
  } do {
  ^bb0(%w: i64, %a: !llvm.ptr, %b: !llvm.ptr):
    %w241 = arith.muli %w, %k2 : i64
  %ix42 = arith.index_cast %w241 : i64 to index
    scf.for %mlo43 = %k4 to %ix10 step %ix42 {
  %i644 = arith.index_cast %mlo43 : index to i64
      %lw45 = arith.addi %i644, %w : i64
  %mn46 = arith.minui %lw45, %n : i64
      %l2w47 = arith.addi %i644, %w241 : i64
  %mn48 = arith.minui %l2w47, %n : i64
      %mg49:3 = scf.while (%i = %i644, %j = %mn46, %k = %i644) : (i64, i64, i64) -> (i64, i64, i64) {
        %ic50 = arith.cmpi ult, %i, %mn46 : i64
        %jc51 = arith.cmpi ult, %j, %mn48 : i64
        %both52 = arith.andi %ic50, %jc51 : i1
        scf.condition(%both52) %i, %j, %k : i64, i64, i64
      } do {
      ^bb0(%i: i64, %j: i64, %k: i64):
  %off53 = arith.muli %j, %rb : i64
  %p54 = llvm.getelementptr %a[%off53] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off55 = arith.muli %i, %rb : i64
  %p56 = llvm.getelementptr %a[%off55] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3257 = func.call @nx_rows_key(%p54) : (!llvm.ptr) -> i32
  %k3259 = func.call @nx_rows_key(%p56) : (!llvm.ptr) -> i32
        %cb61 = arith.cmpi ult, %k3257, %k3259 : i32
  %off62 = arith.muli %k, %rb : i64
  %p63 = llvm.getelementptr %b[%off62] : (!llvm.ptr, i64) -> !llvm.ptr, i8
        scf.if %cb61 {
  func.call @nx_rows_copy1(%p63, %p54, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        } else {
  func.call @nx_rows_copy1(%p63, %p56, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        }
        %ip64 = arith.addi %i, %k1 : i64
        %jp65 = arith.addi %j, %k1 : i64
        %kp66 = arith.addi %k, %k1 : i64
        %jn67 = arith.select %cb61, %jp65, %j : i64
        %in68 = arith.select %cb61, %i, %ip64 : i64
        scf.yield %in68, %jn67, %kp66 : i64, i64, i64
      }
      %di69:2 = scf.while (%i = %mg49#0, %k = %mg49#2) : (i64, i64) -> (i64, i64) {
        %go70 = arith.cmpi ult, %i, %mn46 : i64
        scf.condition(%go70) %i, %k : i64, i64
      } do {
      ^bb0(%i: i64, %k: i64):
  %off71 = arith.muli %i, %rb : i64
  %p72 = llvm.getelementptr %a[%off71] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off73 = arith.muli %k, %rb : i64
  %p74 = llvm.getelementptr %b[%off73] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p74, %p72, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %ip75 = arith.addi %i, %k1 : i64
        %kp76 = arith.addi %k, %k1 : i64
        scf.yield %ip75, %kp76 : i64, i64
      }
      %dj77:2 = scf.while (%j = %mg49#1, %k = %di69#1) : (i64, i64) -> (i64, i64) {
        %go78 = arith.cmpi ult, %j, %mn48 : i64
        scf.condition(%go78) %j, %k : i64, i64
      } do {
      ^bb0(%j: i64, %k: i64):
  %off79 = arith.muli %j, %rb : i64
  %p80 = llvm.getelementptr %a[%off79] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off81 = arith.muli %k, %rb : i64
  %p82 = llvm.getelementptr %b[%off81] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p82, %p80, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %jp83 = arith.addi %j, %k1 : i64
        %kp84 = arith.addi %k, %k1 : i64
        scf.yield %jp83, %kp84 : i64, i64
      }
    }
    scf.yield %w241, %b, %a : i64, !llvm.ptr, !llvm.ptr
  }
  return
}
