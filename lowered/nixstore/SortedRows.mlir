// include/Nix/Store.h's sorted rows (SortedSet, SortedMap<V>): the search and the moves, for rows of any width.  A row
// starts with its key, a Text {char *p, uint32 n, uint32 cap} (p null in a Text that never held a byte); the rest of it
// (a SortedMap's value) is bytes moved with it.  The headers keep the storage, the append and the pop.
//   nixstore_ts_rowfind    the key's row (the halving over the rows, the keys compared by trikeshed.compare unsigned,
//                          as Text's operator< does: unsigned bytes, then the shorter first), or -(where it sorts) - 1
//   nixstore_ts_rowrotate  rows [a, b) turned left by s: the rows from a + s on, then the s before them, one combine of
//                          two slices of the rows' bytes drained into a room, the room drained back (an insert puts the
//                          row it appended at its place, an erase moves its row to the end before the pop)
//   nixstore_ts_rowsort    n rows put in their keys' order (trikeshed.sorted over the row indices, stable), then one
//                          combineAll of the rows in that order drained into a room and the room drained back: each row
//                          moves once (allValidPaths' paths)
// Helper names are module-unique (nx_sr_*).
!s = !trikeshed.series<i8>
!s64 = !trikeshed.series<i64>
!m = memref<?xi8, strided<[1], offset: ?>>
!d = !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)>

// the descriptor of n bytes at p
func.func private @nx_sr_desc(%p: !llvm.ptr, %n: i64) -> !d {
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

// the key of row e (its Text's window) compared with key
func.func private @nx_sr_cmp(%rows: !llvm.ptr, %stride: i64, %e: i64, %kd: !d) -> i32 {
  %c8 = arith.constant 8 : i64
  %off = arith.muli %e, %stride : i64
  %r = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %p = llvm.load %r : !llvm.ptr -> !llvm.ptr
  %np = llvm.getelementptr %r[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
  %n32 = llvm.load %np : !llvm.ptr -> i32
  %rn = arith.extui %n32 : i32 to i64
  %rd = func.call @nx_sr_desc(%p, %rn) : (!llvm.ptr, i64) -> !d
  %rm = builtin.unrealized_conversion_cast %rd : !d to !m
  %rk = builtin.unrealized_conversion_cast %rm : !m to !s
  %km = builtin.unrealized_conversion_cast %kd : !d to !m
  %key = builtin.unrealized_conversion_cast %km : !m to !s
  %c = trikeshed.compare %rk, %key unsigned : !s, !s
  return %c : i32
}

// rows: n rows of stride bytes; k: the key's kn bytes.  The halving is written out (scf.while) rather than as
// trikeshed.bisect over a trikeshed.series of the row indices: that lowering makes the index series (n words, a malloc)
// on every call, and a lookup is O(log n) or nothing.
func.func @nixstore_ts_rowfind(%rows: !llvm.ptr, %n: i64, %stride: i64, %k: !llvm.ptr, %kn: i64) -> i64 {
  %c0 = arith.constant 0 : i64
  %c1 = arith.constant 1 : i64
  %m1 = arith.constant -1 : i64
  %zero = arith.constant 0 : i32
  %kd = func.call @nx_sr_desc(%k, %kn) : (!llvm.ptr, i64) -> !d
  %r:3 = scf.while (%lo = %c0, %hi = %n, %hit = %m1) : (i64, i64, i64) -> (i64, i64, i64) {
    %open = arith.cmpi slt, %lo, %hi : i64
    %none = arith.cmpi slt, %hit, %c0 : i64
    %go = arith.andi %open, %none : i1
    scf.condition(%go) %lo, %hi, %hit : i64, i64, i64
  } do {
  ^bb0(%lo1: i64, %hi1: i64, %hit1: i64):
    %sum = arith.addi %lo1, %hi1 : i64
    %mid = arith.shrui %sum, %c1 : i64
    %c = func.call @nx_sr_cmp(%rows, %stride, %mid, %kd) : (!llvm.ptr, i64, i64, !d) -> i32
    %below = arith.cmpi slt, %c, %zero : i32
    %above = arith.cmpi sgt, %c, %zero : i32
    %mid1 = arith.addi %mid, %c1 : i64
    %lo2 = arith.select %below, %mid1, %lo1 : i64
    %hi2 = arith.select %above, %mid, %hi1 : i64
    %eq = arith.cmpi eq, %c, %zero : i32
    %hit2 = arith.select %eq, %mid, %hit1 : i64
    scf.yield %lo2, %hi2, %hit2 : i64, i64, i64
  }
  %found = arith.cmpi sge, %r#2, %c0 : i64
  %ins = arith.subi %m1, %r#0 : i64
  %res = arith.select %found, %r#2, %ins : i64
  return %res : i64
}

// rows [a, b) of stride bytes turned left by s (0 < s < b - a; anything else moves nothing)
func.func @nixstore_ts_rowrotate(%rows: !llvm.ptr, %a: i64, %b: i64, %s: i64, %stride: i64) {
  %c0 = arith.constant 0 : i64
  %span = arith.subi %b, %a : i64
  %pos = arith.cmpi sgt, %s, %c0 : i64
  %less = arith.cmpi slt, %s, %span : i64
  %moves = arith.andi %pos, %less : i1
  scf.if %moves {
    %bytes = arith.muli %span, %stride : i64
    %from = arith.muli %a, %stride : i64
    %at = llvm.getelementptr %rows[%from] : (!llvm.ptr, i64) -> !llvm.ptr, i8
    %wd = func.call @nx_sr_desc(%at, %bytes) : (!llvm.ptr, i64) -> !d
    %wm = builtin.unrealized_conversion_cast %wd : !d to !m
    %w = builtin.unrealized_conversion_cast %wm : !m to !s
    %head = arith.muli %s, %stride : i64
    %tail = arith.subi %bytes, %head : i64
    %z = arith.constant 0 : index
    %hi = arith.index_cast %head : i64 to index
    %ti = arith.index_cast %tail : i64 to index
    %after = trikeshed.slice %w[%hi, %ti] : !s -> !s
    %before = trikeshed.slice %w[%z, %hi] : !s -> !s
    %turned = trikeshed.combine %after, %before : !s, !s -> !s
    %bi = arith.index_cast %bytes : i64 to index
    // the room: on the stack when it is small (the usual insert into a derivation's environment), else the heap
    %c4096 = arith.constant 4096 : i64
    %small = arith.cmpi ule, %bytes, %c4096 : i64
    scf.if %small {
      %room = memref.alloca(%bi) : memref<?xi8>
      %e1 = trikeshed.drain %turned, %room : !s, memref<?xi8> -> index
      %back = trikeshed.text %room : memref<?xi8> -> !s
      %e2 = trikeshed.drain %back, %wm : !s, !m -> index
    } else {
      %room = memref.alloc(%bi) : memref<?xi8>
      %e1 = trikeshed.drain %turned, %room : !s, memref<?xi8> -> index
      %back = trikeshed.text %room : memref<?xi8> -> !s
      %e2 = trikeshed.drain %back, %wm : !s, !m -> index
    }
  }
  return
}

// n rows of stride bytes sorted by their keys, in place
func.func @nixstore_ts_rowsort(%rows: !llvm.ptr, %n: i64, %stride: i64) {
  %c1 = arith.constant 1 : i64
  %c8 = arith.constant 8 : i64
  %many = arith.cmpi sgt, %n, %c1 : i64
  scf.if %many {
    %ni = arith.index_cast %n : i64 to index
    %bytes = arith.muli %n, %stride : i64
    %wd = func.call @nx_sr_desc(%rows, %bytes) : (!llvm.ptr, i64) -> !d
    %wm = builtin.unrealized_conversion_cast %wd : !d to !m
    %w = builtin.unrealized_conversion_cast %wm : !m to !s
    %idx = trikeshed.series %ni : !s64 {
    ^bb0(%i: index):
      %i64 = arith.index_cast %i : index to i64
      trikeshed.yield %i64 : i64
    }
    %srt = trikeshed.sorted %idx : !s64 -> !s64 by {
    ^bb0(%x: i64, %y: i64):
      %off = arith.muli %y, %stride : i64
      %r = llvm.getelementptr %rows[%off] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %p = llvm.load %r : !llvm.ptr -> !llvm.ptr
      %np = llvm.getelementptr %r[%c8] : (!llvm.ptr, i64) -> !llvm.ptr, i8
      %n32 = llvm.load %np : !llvm.ptr -> i32
      %yn = arith.extui %n32 : i32 to i64
      %yd = func.call @nx_sr_desc(%p, %yn) : (!llvm.ptr, i64) -> !d
      %c = func.call @nx_sr_cmp(%rows, %stride, %x, %yd) : (!llvm.ptr, i64, i64, !d) -> i32
      trikeshed.yield %c : i32
    }
    %si = arith.index_cast %stride : i64 to index
    %all, %where = trikeshed.combineAll %ni : !s, !trikeshed.series<!trikeshed.twinpacked<i32>> {
    ^bb0(%k: index):
      %e = trikeshed.at %srt[%k] : !s64, index -> i64
      %ei = arith.index_cast %e : i64 to index
      %at = arith.muli %ei, %si : index
      %row = trikeshed.slice %w[%at, %si] : !s -> !s
      trikeshed.yield %row : !s
    }
    %bi = arith.index_cast %bytes : i64 to index
    %room = memref.alloc(%bi) : memref<?xi8>
    %e1 = trikeshed.drain %all, %room : !s, memref<?xi8> -> index
    %back = trikeshed.text %room : memref<?xi8> -> !s
    %e2 = trikeshed.drain %back, %wm : !s, !m -> index
  }
  return
}
