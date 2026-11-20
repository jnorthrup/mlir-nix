// Composite/Rows.h's row algorithms (neutral C ABI; Rows.h is the bridge).  The keyed family -- findRow's
// branchless search, uniqueFirst, unionSize/unionInto (a merge walk, or a lower-bound search per y row when
// y is a sixteenth of x or less) -- reads each row's leading u32 as its key (Attr::name, an attrs shape's
// symbol); the row width is an operand.  sortRows is the kRun=24 insertion sort + bottom-up stable merge
// (the right run only when strictly less) in two forms: mlnix_rows_sort calls the C++ comparator back for
// each comparison in the order the template did (a throw unwinds through these frames; the bridge's RAII
// temp is freed), mlnix_rows_sort_u32 compares the leading u32 keys itself.  The bridge owns the merge's
// temp run (::operator new/delete); this module allocates nothing on the heap.  Plain scf/arith/llvm: rows
// of any width are bytes at a stride, not a series of scalars.  Generated (scratch gen_rows.py).

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

func.func @mlnix_rows_find(%rows: !llvm.ptr, %rb: i64, %n: i64, %k: i64) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 2 : i64
  %is01 = arith.cmpi eq, %n, %k0 : i64
  %r2 = scf.if %is01 -> i64 {
    scf.yield %k0 : i64
  } else {
    %b03 = llvm.ptrtoint %rows : !llvm.ptr to i64
    %w4:3 = scf.while (%base = %b03, %nn = %n) : (i64, i64) -> (i64, i64, i64) {
      %half5 = arith.divui %nn, %k1 : i64
      %go6 = arith.cmpi ne, %half5, %k0 : i64
      scf.condition(%go6) %base, %nn, %half5 : i64, i64, i64
    } do {
    ^bb0(%base: i64, %nn: i64, %half: i64):
      %bp7 = llvm.inttoptr %base : i64 to !llvm.ptr
  %off8 = arith.muli %half, %rb : i64
  %p9 = llvm.getelementptr %bp7[%off8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3210 = llvm.load %p9 : !llvm.ptr -> i32
  %key11 = arith.extui %k3210 : i32 to i64
      %le12 = arith.cmpi ule, %key11, %k : i64
      %adv13 = arith.muli %half, %rb : i64
      %nb14 = arith.addi %base, %adv13 : i64
      %b215 = arith.select %le12, %nb14, %base : i64
      %nn216 = arith.subi %nn, %half : i64
      scf.yield %b215, %nn216 : i64, i64
    }
    %bp17 = llvm.inttoptr %w4#0 : i64 to !llvm.ptr
  %k3218 = llvm.load %bp17 : !llvm.ptr -> i32
  %key19 = arith.extui %k3218 : i32 to i64
    %eq20 = arith.cmpi eq, %key19, %k : i64
    %ri21 = arith.select %eq20, %w4#0, %k0 : i64
    scf.yield %ri21 : i64
  }
  return %r2 : i64
}

func.func @mlnix_rows_unique_first(%rows: !llvm.ptr, %rb: i64, %n: i64) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 0 : index
  %k3 = arith.constant 1 : index
  %k4 = arith.constant 0 : i1
  %ix1 = arith.index_cast %n : i64 to index
  %m2 = scf.for %i = %k2 to %ix1 step %k3 iter_args(%mm = %k0) -> i64 {
  %i63 = arith.index_cast %i : index to i64
    %mgt4 = arith.cmpi ugt, %mm, %k0 : i64
    %eq5 = scf.if %mgt4 -> i1 {
      %mm16 = arith.subi %mm, %k1 : i64
  %off7 = arith.muli %mm16, %rb : i64
  %p8 = llvm.getelementptr %rows[%off7] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off9 = arith.muli %i63, %rb : i64
  %p10 = llvm.getelementptr %rows[%off9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3211 = llvm.load %p8 : !llvm.ptr -> i32
  %key12 = arith.extui %k3211 : i32 to i64
  %k3213 = llvm.load %p10 : !llvm.ptr -> i32
  %key14 = arith.extui %k3213 : i32 to i64
      %e15 = arith.cmpi eq, %key12, %key14 : i64
      scf.yield %e15 : i1
    } else {
      scf.yield %k4 : i1
    }
    %nm16 = scf.if %eq5 -> i64 {
      scf.yield %mm : i64
    } else {
  %off17 = arith.muli %mm, %rb : i64
  %p18 = llvm.getelementptr %rows[%off17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off19 = arith.muli %i63, %rb : i64
  %p20 = llvm.getelementptr %rows[%off19] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p18, %p20, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %mp21 = arith.addi %mm, %k1 : i64
      scf.yield %mp21 : i64
    }
    scf.yield %nm16 : i64
  }
  return %m2 : i64
}

func.func @mlnix_rows_union_size(%x: !llvm.ptr, %rb: i64, %nx: i64, %y: !llvm.ptr, %ny: i64) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 16 : i64
  %k3 = arith.constant 0 : index
  %k4 = arith.constant 1 : index
  %k5 = arith.constant 0 : i1
  %k6 = arith.constant 2 : i64
  %ny161 = arith.muli %ny, %k2 : i64
  %small2 = arith.cmpi ult, %ny161, %nx : i64
  %res3 = scf.if %small2 -> i64 {
  %ix4 = arith.index_cast %ny : i64 to index
    %sh5:2 = scf.for %j = %k3 to %ix4 step %k4 iter_args(%ii = %k0, %shared = %k0) -> (i64, i64) {
  %i66 = arith.index_cast %j : index to i64
  %off7 = arith.muli %i66, %rb : i64
  %p8 = llvm.getelementptr %y[%off7] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k329 = llvm.load %p8 : !llvm.ptr -> i32
  %key10 = arith.extui %k329 : i32 to i64
      %lb11:2 = scf.while (%lo = %ii, %hh = %nx) : (i64, i64) -> (i64, i64) {
        %go12 = arith.cmpi ult, %lo, %hh : i64
        scf.condition(%go12) %lo, %hh : i64, i64
      } do {
      ^bb0(%lo: i64, %hh: i64):
        %d13 = arith.subi %hh, %lo : i64
        %hd14 = arith.divui %d13, %k6 : i64
        %mid15 = arith.addi %lo, %hd14 : i64
  %off16 = arith.muli %mid15, %rb : i64
  %p17 = llvm.getelementptr %x[%off16] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3218 = llvm.load %p17 : !llvm.ptr -> i32
  %key19 = arith.extui %k3218 : i32 to i64
        %lt20 = arith.cmpi ult, %key19, %key10 : i64
        %mp121 = arith.addi %mid15, %k1 : i64
        %nlo22 = arith.select %lt20, %mp121, %lo : i64
        %nhi23 = arith.select %lt20, %hh, %mid15 : i64
        scf.yield %nlo22, %nhi23 : i64, i64
      }
      %inx24 = arith.cmpi ult, %lb11#0, %nx : i64
      %eqsh25 = scf.if %inx24 -> i1 {
  %off26 = arith.muli %lb11#0, %rb : i64
  %p27 = llvm.getelementptr %x[%off26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3228 = llvm.load %p27 : !llvm.ptr -> i32
  %key29 = arith.extui %k3228 : i32 to i64
        %e30 = arith.cmpi eq, %key29, %key10 : i64
        scf.yield %e30 : i1
      } else {
        scf.yield %k5 : i1
      }
      %shn31:2 = scf.if %eqsh25 -> (i64, i64) {
        %sp32 = arith.addi %shared, %k1 : i64
        %ip33 = arith.addi %lb11#0, %k1 : i64
        scf.yield %sp32, %ip33 : i64, i64
      } else {
        scf.yield %shared, %lb11#0 : i64, i64
      }
      scf.yield %shn31#1, %shn31#0 : i64, i64
    }
    %t134 = arith.addi %nx, %ny : i64
    %r135 = arith.subi %t134, %sh5#1 : i64
    scf.yield %r135 : i64
  } else {
    %mw36:3 = scf.while (%i = %k0, %j = %k0, %cnt = %k0) : (i64, i64, i64) -> (i64, i64, i64) {
      %ic37 = arith.cmpi ult, %i, %nx : i64
      %jc38 = arith.cmpi ult, %j, %ny : i64
      %both39 = arith.andi %ic37, %jc38 : i1
      scf.condition(%both39) %i, %j, %cnt : i64, i64, i64
    } do {
    ^bb0(%i: i64, %j: i64, %cnt: i64):
  %off40 = arith.muli %i, %rb : i64
  %p41 = llvm.getelementptr %x[%off40] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3242 = llvm.load %p41 : !llvm.ptr -> i32
  %key43 = arith.extui %k3242 : i32 to i64
  %off44 = arith.muli %j, %rb : i64
  %p45 = llvm.getelementptr %y[%off44] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3246 = llvm.load %p45 : !llvm.ptr -> i32
  %key47 = arith.extui %k3246 : i32 to i64
      %eq48 = arith.cmpi eq, %key43, %key47 : i64
      %lt49 = arith.cmpi ult, %key43, %key47 : i64
      %ip50 = arith.addi %i, %k1 : i64
      %jp51 = arith.addi %j, %k1 : i64
      %ieq52 = arith.select %eq48, %ip50, %i : i64
      %jeq53 = arith.select %eq48, %jp51, %j : i64
      %ilt54 = arith.select %lt49, %ip50, %ieq52 : i64
      %jlt55 = arith.select %lt49, %jeq53, %jp51 : i64
      %cn56 = arith.addi %cnt, %k1 : i64
      scf.yield %ilt54, %jlt55, %cn56 : i64, i64, i64
    }
    %ri57 = arith.subi %nx, %mw36#0 : i64
    %rj58 = arith.subi %ny, %mw36#1 : i64
    %s159 = arith.addi %mw36#2, %ri57 : i64
    %s260 = arith.addi %s159, %rj58 : i64
    scf.yield %s260 : i64
  }
  return %res3 : i64
}

func.func private @nx_rows_union_walk(%x: !llvm.ptr, %rb: i64, %nx: i64, %y: !llvm.ptr, %ny: i64, %out: !llvm.ptr) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %uw1:3 = scf.while (%i = %k0, %j = %k0, %k = %k0) : (i64, i64, i64) -> (i64, i64, i64) {
    %ic2 = arith.cmpi ult, %i, %nx : i64
    %jc3 = arith.cmpi ult, %j, %ny : i64
    %both4 = arith.andi %ic2, %jc3 : i1
    scf.condition(%both4) %i, %j, %k : i64, i64, i64
  } do {
  ^bb0(%i: i64, %j: i64, %k: i64):
  %off5 = arith.muli %i, %rb : i64
  %p6 = llvm.getelementptr %x[%off5] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k327 = llvm.load %p6 : !llvm.ptr -> i32
  %key8 = arith.extui %k327 : i32 to i64
  %off9 = arith.muli %j, %rb : i64
  %p10 = llvm.getelementptr %y[%off9] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3211 = llvm.load %p10 : !llvm.ptr -> i32
  %key12 = arith.extui %k3211 : i32 to i64
    %eq13 = arith.cmpi eq, %key8, %key12 : i64
    %lt14 = arith.cmpi ult, %key8, %key12 : i64
  %off15 = arith.muli %k, %rb : i64
  %p16 = llvm.getelementptr %out[%off15] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    scf.if %eq13 {
  func.call @nx_rows_copy1(%p16, %p10, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    } else {
      scf.if %lt14 {
  func.call @nx_rows_copy1(%p16, %p6, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      } else {
  func.call @nx_rows_copy1(%p16, %p10, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      }
    }
    %ip17 = arith.addi %i, %k1 : i64
    %jp18 = arith.addi %j, %k1 : i64
    %kp19 = arith.addi %k, %k1 : i64
    %ieq20 = arith.select %eq13, %ip17, %i : i64
    %jeq21 = arith.select %eq13, %jp18, %j : i64
    %ilt22 = arith.select %lt14, %ip17, %ieq20 : i64
    %jlt23 = arith.select %lt14, %jeq21, %jp18 : i64
    scf.yield %ilt22, %jlt23, %kp19 : i64, i64, i64
  }
  %dx24:2 = scf.while (%i = %uw1#0, %k = %uw1#2) : (i64, i64) -> (i64, i64) {
    %go25 = arith.cmpi ult, %i, %nx : i64
    scf.condition(%go25) %i, %k : i64, i64
  } do {
  ^bb0(%i: i64, %k: i64):
  %off26 = arith.muli %i, %rb : i64
  %p27 = llvm.getelementptr %x[%off26] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off28 = arith.muli %k, %rb : i64
  %p29 = llvm.getelementptr %out[%off28] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p29, %p27, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %ip30 = arith.addi %i, %k1 : i64
    %kp31 = arith.addi %k, %k1 : i64
    scf.yield %ip30, %kp31 : i64, i64
  }
  %dy32:2 = scf.while (%j = %uw1#1, %k = %dx24#1) : (i64, i64) -> (i64, i64) {
    %go33 = arith.cmpi ult, %j, %ny : i64
    scf.condition(%go33) %j, %k : i64, i64
  } do {
  ^bb0(%j: i64, %k: i64):
  %off34 = arith.muli %j, %rb : i64
  %p35 = llvm.getelementptr %y[%off34] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off36 = arith.muli %k, %rb : i64
  %p37 = llvm.getelementptr %out[%off36] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p37, %p35, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
    %jp38 = arith.addi %j, %k1 : i64
    %kp39 = arith.addi %k, %k1 : i64
    scf.yield %jp38, %kp39 : i64, i64
  }
  return %dy32#1 : i64
}

func.func @mlnix_rows_union_into(%x: !llvm.ptr, %rb: i64, %nx: i64, %y: !llvm.ptr, %ny: i64, %out: !llvm.ptr) -> i64 {
  %k0 = arith.constant 0 : i64
  %k1 = arith.constant 1 : i64
  %k2 = arith.constant 16 : i64
  %k3 = arith.constant 0 : index
  %k4 = arith.constant 1 : index
  %k5 = arith.constant 0 : i1
  %k6 = arith.constant 2 : i64
  %ny161 = arith.muli %ny, %k2 : i64
  %big2 = arith.cmpi uge, %ny161, %nx : i64
  %res3 = scf.if %big2 -> i64 {
    %ur4 = func.call @nx_rows_union_walk(%x, %rb, %nx, %y, %ny, %out) : (!llvm.ptr, i64, i64, !llvm.ptr, i64, !llvm.ptr) -> i64
    scf.yield %ur4 : i64
  } else {
  %ix5 = arith.index_cast %ny : i64 to index
    %ik6:2 = scf.for %j = %k3 to %ix5 step %k4 iter_args(%ii = %k0, %kk = %k0) -> (i64, i64) {
  %i67 = arith.index_cast %j : index to i64
  %off8 = arith.muli %i67, %rb : i64
  %p9 = llvm.getelementptr %y[%off8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3210 = llvm.load %p9 : !llvm.ptr -> i32
  %key11 = arith.extui %k3210 : i32 to i64
      %lb12:2 = scf.while (%lo = %ii, %hh = %nx) : (i64, i64) -> (i64, i64) {
        %go13 = arith.cmpi ult, %lo, %hh : i64
        scf.condition(%go13) %lo, %hh : i64, i64
      } do {
      ^bb0(%lo: i64, %hh: i64):
        %d14 = arith.subi %hh, %lo : i64
        %hd15 = arith.divui %d14, %k6 : i64
        %mid16 = arith.addi %lo, %hd15 : i64
  %off17 = arith.muli %mid16, %rb : i64
  %p18 = llvm.getelementptr %x[%off17] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3219 = llvm.load %p18 : !llvm.ptr -> i32
  %key20 = arith.extui %k3219 : i32 to i64
        %lt21 = arith.cmpi ult, %key20, %key11 : i64
        %mp122 = arith.addi %mid16, %k1 : i64
        %nlo23 = arith.select %lt21, %mp122, %lo : i64
        %nhi24 = arith.select %lt21, %hh, %mid16 : i64
        scf.yield %nlo23, %nhi24 : i64, i64
      }
      %dr25:2 = scf.while (%i = %ii, %k = %kk) : (i64, i64) -> (i64, i64) {
        %go26 = arith.cmpi ult, %i, %lb12#0 : i64
        scf.condition(%go26) %i, %k : i64, i64
      } do {
      ^bb0(%i: i64, %k: i64):
  %off27 = arith.muli %i, %rb : i64
  %p28 = llvm.getelementptr %x[%off27] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off29 = arith.muli %k, %rb : i64
  %p30 = llvm.getelementptr %out[%off29] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p30, %p28, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
        %ip31 = arith.addi %i, %k1 : i64
        %kp32 = arith.addi %k, %k1 : i64
        scf.yield %ip31, %kp32 : i64, i64
      }
  %off33 = arith.muli %dr25#1, %rb : i64
  %p34 = llvm.getelementptr %out[%off33] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p34, %p9, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %k135 = arith.addi %dr25#1, %k1 : i64
      %inx36 = arith.cmpi ult, %dr25#0, %nx : i64
      %eq37 = scf.if %inx36 -> i1 {
  %off38 = arith.muli %dr25#0, %rb : i64
  %p39 = llvm.getelementptr %x[%off38] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %k3240 = llvm.load %p39 : !llvm.ptr -> i32
  %key41 = arith.extui %k3240 : i32 to i64
        %e42 = arith.cmpi eq, %key41, %key11 : i64
        scf.yield %e42 : i1
      } else {
        scf.yield %k5 : i1
      }
      %ip243 = arith.addi %dr25#0, %k1 : i64
      %inew44 = arith.select %eq37, %ip243, %dr25#0 : i64
      scf.yield %inew44, %k135 : i64, i64
    }
    %dt45:2 = scf.while (%i = %ik6#0, %k = %ik6#1) : (i64, i64) -> (i64, i64) {
      %go46 = arith.cmpi ult, %i, %nx : i64
      scf.condition(%go46) %i, %k : i64, i64
    } do {
    ^bb0(%i: i64, %k: i64):
  %off47 = arith.muli %i, %rb : i64
  %p48 = llvm.getelementptr %x[%off47] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %off49 = arith.muli %k, %rb : i64
  %p50 = llvm.getelementptr %out[%off49] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  func.call @nx_rows_copy1(%p50, %p48, %rb) : (!llvm.ptr, !llvm.ptr, i64) -> ()
      %ip51 = arith.addi %i, %k1 : i64
      %kp52 = arith.addi %k, %k1 : i64
      scf.yield %ip51, %kp52 : i64, i64
    }
    scf.yield %dt45#1 : i64
  }
  return %res3 : i64
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
  %k3226 = llvm.load %xbuf1 : !llvm.ptr -> i32
  %key27 = arith.extui %k3226 : i32 to i64
  %k3228 = llvm.load %p25 : !llvm.ptr -> i32
  %key29 = arith.extui %k3228 : i32 to i64
          %cb30 = arith.cmpi ult, %key27, %key29 : i64
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
  %k3257 = llvm.load %p54 : !llvm.ptr -> i32
  %key58 = arith.extui %k3257 : i32 to i64
  %k3259 = llvm.load %p56 : !llvm.ptr -> i32
  %key60 = arith.extui %k3259 : i32 to i64
        %cb61 = arith.cmpi ult, %key58, %key60 : i64
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
