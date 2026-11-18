// The faceted query of mini-luci, in TrikeShed's cursor ops.  Compiled when mini-luci is built: trikeshed-lower-cursors
// (mlnix-opt) takes it to scf/arith/memref, the stock MLIR pipeline to LLVM, and the object links into the server, which
// calls it as `_mlir_ciface_corpus_query` (memref descriptors: src/api.mlir, test/facet_check.py).
//
// The corpus is a cursor of six dictionary-coded columns, one row an option:
//   0 section   the first segment of the option's path
//   1 kind      the name of its type
//   2 state     set (a module defines it), default, none (no value), template (a path through attrsOf)
//   3 module    the directory of the module that declares it
//   4 what-if   whether the what-if overlay changed it (0 no, 1 yes)
//   5 match     whether it matches the text searched for (0 no, 1 yes)
// A selection is a series per column, indexed by code: nonzero where the code is selected (all ones: no selection).
// A row passes column f when its code there is selected; the hits are the rows passing every column.  The count of code
// v in column f is the number of rows with v there that pass every OTHER column: what checking v would add to the hits,
// the usual counts of a faceted search.
//
// Out: the hits (row numbers, in order) into `rows`, each column's counts into its `out`; the result is the hit count.

!s = !trikeshed.series<i32>
!k = !trikeshed.colkey<"Corpus">
!corpus = !trikeshed.cursor<"Corpus", [i32, i32, i32, i32, i32, i32]>

// `bit` where the row's code in `col` is selected, else 0.
func.func private @pass(%col: !s, %sel: !s, %bit: i32) -> !s {
  %p = trikeshed.alpha %col : !s -> !s {
  ^bb0(%v: i32):
    %zero = arith.constant 0 : i32
    %s = trikeshed.at %sel[%v] : !s, i32 -> i32
    %on = arith.cmpi ne, %s, %zero : i32
    %b = arith.select %on, %bit, %zero : i32
    trikeshed.yield %b : i32
  }
  return %p : !s
}

// The counts of a column's codes over the rows that pass every other column: those whose mask, with this column's bit
// set, is `all`.
func.func private @counts(%col: !s, %mask: !s, %bit: i32, %all: i32, %codes: index) -> !s {
  %n = trikeshed.size %col : !s
  %ids = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %others = trikeshed.where %ids : !s -> !s {
  ^bb0(%r: i32):
    %m = trikeshed.at %mask[%r] : !s, i32 -> i32
    %with = arith.ori %m, %bit : i32
    %ok = arith.cmpi eq, %with, %all : i32
    trikeshed.yield %ok : i1
  }
  %vs = trikeshed.project %col[%others] : !s, !s -> !s
  %counts = trikeshed.series %codes : !s {
  ^bb0(%v: index):
    %code = arith.index_cast %v : index to i32
    %zero = arith.constant 0 : i32
    %k = trikeshed.fold %vs, %zero : !s, i32 -> i32 {
    ^bb0(%acc: i32, %x: i32):
      %eq = arith.cmpi eq, %x, %code : i32
      %one = arith.extui %eq : i1 to i32
      %next = arith.addi %acc, %one : i32
      trikeshed.yield %next : i32
    }
    trikeshed.yield %k : i32
  }
  return %counts : !s
}

func.func @corpus_query(%c: !corpus, %s0: !s, %s1: !s, %s2: !s, %s3: !s, %s4: !s, %s5: !s,
                        %o0: memref<?xi32>, %o1: memref<?xi32>, %o2: memref<?xi32>, %o3: memref<?xi32>,
                        %o4: memref<?xi32>, %o5: memref<?xi32>, %rows: memref<?xi32>) -> index
    attributes {llvm.emit_c_interface} {
  %k0 = trikeshed.key 0 : !k
  %k1 = trikeshed.key 1 : !k
  %k2 = trikeshed.key 2 : !k
  %k3 = trikeshed.key 3 : !k
  %k4 = trikeshed.key 4 : !k
  %k5 = trikeshed.key 5 : !k
  %b0 = arith.constant 1 : i32
  %b1 = arith.constant 2 : i32
  %b2 = arith.constant 4 : i32
  %b3 = arith.constant 8 : i32
  %b4 = arith.constant 16 : i32
  %b5 = arith.constant 32 : i32
  %all = arith.constant 63 : i32

  // each column's pass bits, then a row's mask: the columns it passes
  %p0 = trikeshed.facet %c[%k0] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s0, %b0) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %p1 = trikeshed.facet %c[%k1] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s1, %b1) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %p2 = trikeshed.facet %c[%k2] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s2, %b2) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %p3 = trikeshed.facet %c[%k3] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s3, %b3) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %p4 = trikeshed.facet %c[%k4] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s4, %b4) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %p5 = trikeshed.facet %c[%k5] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %p = func.call @pass(%col, %s5, %b5) : (!s, !s, i32) -> !s
    trikeshed.yield %p : !s
  }
  %n = trikeshed.size %p0 : !s
  %ids = trikeshed.series %n : !s {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %mask = trikeshed.alpha %ids : !s -> !s {
  ^bb0(%r: i32):
    %x0 = trikeshed.at %p0[%r] : !s, i32 -> i32
    %x1 = trikeshed.at %p1[%r] : !s, i32 -> i32
    %x2 = trikeshed.at %p2[%r] : !s, i32 -> i32
    %x3 = trikeshed.at %p3[%r] : !s, i32 -> i32
    %x4 = trikeshed.at %p4[%r] : !s, i32 -> i32
    %x5 = trikeshed.at %p5[%r] : !s, i32 -> i32
    %m01 = arith.ori %x0, %x1 : i32
    %m23 = arith.ori %x2, %x3 : i32
    %m45 = arith.ori %x4, %x5 : i32
    %m03 = arith.ori %m01, %m23 : i32
    %m = arith.ori %m03, %m45 : i32
    trikeshed.yield %m : i32
  }

  // the hits
  %hits = trikeshed.where %ids : !s -> !s {
  ^bb0(%r: i32):
    %m = trikeshed.at %mask[%r] : !s, i32 -> i32
    %ok = arith.cmpi eq, %m, %all : i32
    trikeshed.yield %ok : i1
  }
  %total = trikeshed.drain %hits, %rows : !s, memref<?xi32> -> index

  // each column's counts
  %n0 = trikeshed.size %s0 : !s
  %c0 = trikeshed.facet %c[%k0] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b0, %all, %n0) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e0 = trikeshed.drain %c0, %o0 : !s, memref<?xi32> -> index
  %n1 = trikeshed.size %s1 : !s
  %c1 = trikeshed.facet %c[%k1] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b1, %all, %n1) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e1 = trikeshed.drain %c1, %o1 : !s, memref<?xi32> -> index
  %n2 = trikeshed.size %s2 : !s
  %c2 = trikeshed.facet %c[%k2] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b2, %all, %n2) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e2 = trikeshed.drain %c2, %o2 : !s, memref<?xi32> -> index
  %n3 = trikeshed.size %s3 : !s
  %c3 = trikeshed.facet %c[%k3] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b3, %all, %n3) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e3 = trikeshed.drain %c3, %o3 : !s, memref<?xi32> -> index
  %n4 = trikeshed.size %s4 : !s
  %c4 = trikeshed.facet %c[%k4] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b4, %all, %n4) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e4 = trikeshed.drain %c4, %o4 : !s, memref<?xi32> -> index
  %n5 = trikeshed.size %s5 : !s
  %c5 = trikeshed.facet %c[%k5] : !corpus, !k -> !s {
  ^bb0(%col: !s):
    %r = func.call @counts(%col, %mask, %b5, %all, %n5) : (!s, !s, i32, i32, index) -> !s
    trikeshed.yield %r : !s
  }
  %e5 = trikeshed.drain %c5, %o5 : !s, memref<?xi32> -> index
  return %total : index
}
