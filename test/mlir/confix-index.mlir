// confix.index and confix.columns: a JSON text's index as TrikeShed's cursor and series, its Columns facet, and the
// series ops that read it (slice, compare, sorted, bisect, first, second, j), lowered by trikeshed-lower-cursors (the two
// confix ops into calls of their bodies, lowered/confix/ConfixIndex.mlir's functions), taken to LLVM by the stock pipeline
// and run with those bodies and confix.ll's scanner (build/lib's TrikeShedRuntime carries both).  The text is
//   {"options":[{"path":["a","b"],"kind":"bool x","state":"set"},{"state":"none","path":["c"]},7,{"kind":"str","kind":"int"}],"etc":{"p":1}}
// The expected values come from a separate reader of the text (rows in the order they open, a span's close inclusive,
// an object's children its keys and values alternating), not from the scanner:
//   rows 28, kids 27; the root's options at row 2, its etc at row 25
//   the options' elements: rows 3, 12, 18 (the number 7), 19
//   path [5, 16, -1, -1]   kind [9, -1, -1, 23] (the second "kind" of row 19 wins)   state [11, 14, -1, -1]   missing: none
//   the 18 strings sorted by their text, ties in row order: a b "bool x" c etc int kind kind kind none options p path
//   path set state state str; bisect: none 9, q -15 (before set), "" -1, zzz -19, kind 7 (the search meets the middle one)
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | FileCheck %s --check-prefix=LOWERED
// RUN: ext=so; if [ "$(uname -s)" = Darwin ]; then ext=dylib; fi; mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1),%S/../../build/lib/libTrikeShedRuntime.${ext} | FileCheck %s
// the same answers with the pairs routed first (trikeshed-route-twins): the index's columns keep the scanner's layout
// RUN: ext=so; if [ "$(uname -s)" = Darwin ]; then ext=dylib; fi; mlnix-opt %s --trikeshed-route-twins --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=void -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1),%S/../../build/lib/libTrikeShedRuntime.${ext} | FileCheck %s

// ROUND: confix.index json %{{.*}} : !trikeshed.series<i8> -> !trikeshed.cursor<"ConfixIndex", [!trikeshed.twin<i32>, i8, !trikeshed.twinpacked<i32>]>, !trikeshed.series<i32>
// ROUND: confix.columns json %{{.*}} ["path", "kind", "state", "missing"]
// ROUND: trikeshed.sorted %{{.*}} : <i32> -> <i32> by {
// ROUND: trikeshed.bisect %{{.*}}, %{{.*}} : <i32>, !trikeshed.twinpacked<i32> -> index by {

// fault, rows, kids
// CHECK: data =
// CHECK-NEXT: [0,  28,  27]
// opens
// CHECK: data =
// CHECK-NEXT: [0,  1,  11,  12,  13,  20,  21,  25,  30,  37,  46,  54,  61,  62,  70,  77,  84,  85,  91,  93,  94,  101,  107,  114,  122,  128,  129,  133]
// closes
// CHECK: data =
// CHECK-NEXT: [135,  9,  120,  59,  18,  28,  23,  27,  35,  44,  52,  58,  89,  68,  75,  82,  88,  87,  91,  119,  99,  105,  112,  118,  126,  134,  131,  133]
// tags
// CHECK: data =
// CHECK-NEXT: [5,  4,  6,  5,  4,  6,  4,  4,  4,  4,  4,  4,  5,  4,  4,  4,  6,  4,  3,  5,  4,  4,  4,  4,  4,  5,  4,  3]
// first child
// CHECK: data =
// CHECK-NEXT: [0,  4,  4,  8,  14,  14,  16,  16,  16,  16,  16,  16,  16,  20,  20,  20,  20,  21,  21,  21,  25,  25,  25,  25,  25,  25,  27,  27]
// child count
// CHECK: data =
// CHECK-NEXT: [4,  0,  4,  6,  0,  2,  0,  0,  0,  0,  0,  0,  4,  0,  0,  0,  1,  0,  0,  4,  0,  0,  0,  0,  0,  2,  0,  0]
// kids
// CHECK: data =
// CHECK-NEXT: [1,  2,  24,  25,  3,  12,  18,  19,  4,  5,  8,  9,  10,  11,  6,  7,  13,  14,  15,  16,  17,  20,  21,  22,  23,  26,  27]
// options
// CHECK: data =
// CHECK-NEXT: [2]
// etc
// CHECK: data =
// CHECK-NEXT: [25]
// the options' elements
// CHECK: data =
// CHECK-NEXT: [3,  12,  18,  19]
// path
// CHECK: data =
// CHECK-NEXT: [5,  16,  -1,  -1]
// kind
// CHECK: data =
// CHECK-NEXT: [9,  -1,  -1,  23]
// state
// CHECK: data =
// CHECK-NEXT: [11,  14,  -1,  -1]
// missing
// CHECK: data =
// CHECK-NEXT: [-1,  -1,  -1,  -1]
// the strings sorted
// CHECK: data =
// CHECK-NEXT: [6,  7,  9,  17,  24,  23,  8,  20,  22,  14,  1,  26,  4,  15,  11,  10,  13,  21]
// bisect
// CHECK: data =
// CHECK-NEXT: [9,  -15,  -1,  -19,  7]

// LOWERED-NOT: trikeshed.
// LOWERED-NOT: confix.
// the names are data: one text of them, and each one's (start, length) in it
// LOWERED-DAG: memref.global "private" constant @confix_names_{{[0-9]+}} : memref<10xi8> = dense<[111, 112, 116, 105, 111, 110, 115, 101, 116, 99]>
// LOWERED-DAG: memref.global "private" constant @confix_names_{{[0-9]+}} : memref<2xi64> = dense<[7, 30064771075]>
// LOWERED-DAG: func.func private @confix_index(memref<?xi8, strided<[1], offset: ?>>, i32) -> (memref<?xi64, strided<[1], offset: ?>>, memref<?xi8, strided<[1], offset: ?>>, memref<?xi64, strided<[1], offset: ?>>, memref<?xi32, strided<[1], offset: ?>>, i32, i32)
// LOWERED: call @confix_index(
// LOWERED: call @confix_columns(
// LOWERED: call @confix_column(%[[TOP:.*]], %{{.*}}, %{{.*}})
// LOWERED: call @confix_column(%[[TOP]], %{{.*}}, %{{.*}})
// LOWERED: call @confix_columns(
// LOWERED-COUNT-4: call @confix_column(

!text = !trikeshed.series<i8>
!s32 = !trikeshed.series<i32>
!tw = !trikeshed.twin<i32>
!tp = !trikeshed.twinpacked<i32>
!spans = !trikeshed.series<!tw>
!ix = !trikeshed.cursor<"ConfixIndex", [!tw, i8, !tp]>
!ik = !trikeshed.colkey<"ConfixIndex">
!top = !trikeshed.cursor<"Top", [i32, i32]>
!topk = !trikeshed.colkey<"Top">
!tab = !trikeshed.cursor<"Option", [i32, i32, i32, i32]>
!tabk = !trikeshed.colkey<"Option">

memref.global "private" constant @json : memref<136xi8> = dense<[123, 34, 111, 112, 116, 105, 111, 110, 115, 34, 58, 91, 123, 34, 112, 97, 116, 104, 34, 58, 91, 34, 97, 34, 44, 34, 98, 34, 93, 44, 34, 107, 105, 110, 100, 34, 58, 34, 98, 111, 111, 108, 32, 120, 34, 44, 34, 115, 116, 97, 116, 101, 34, 58, 34, 115, 101, 116, 34, 125, 44, 123, 34, 115, 116, 97, 116, 101, 34, 58, 34, 110, 111, 110, 101, 34, 44, 34, 112, 97, 116, 104, 34, 58, 91, 34, 99, 34, 93, 125, 44, 55, 44, 123, 34, 107, 105, 110, 100, 34, 58, 34, 115, 116, 114, 34, 44, 34, 107, 105, 110, 100, 34, 58, 34, 105, 110, 116, 34, 125, 93, 44, 34, 101, 116, 99, 34, 58, 123, 34, 112, 34, 58, 49, 125, 125]>
memref.global "private" constant @probe : memref<12xi8> = dense<[110, 111, 110, 101, 122, 122, 122, 113, 107, 105, 110, 100]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

// a series printed: drained into a buffer
func.func @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %buf = memref.alloc(%n) : memref<?xi32>
  %e = trikeshed.drain %xs, %buf : !s32, memref<?xi32> -> index
  %u = memref.cast %buf : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

func.func @main() {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %one = arith.constant 1 : i32
  %gj = memref.get_global @json : memref<136xi8>
  %gp = memref.get_global @probe : memref<12xi8>
  // the two texts as series: the lowering takes these casts apart again
  %dj = memref.cast %gj : memref<136xi8> to memref<?xi8, strided<[1], offset: ?>>
  %dp = memref.cast %gp : memref<12xi8> to memref<?xi8, strided<[1], offset: ?>>
  %t = builtin.unrealized_conversion_cast %dj : memref<?xi8, strided<[1], offset: ?>> to !text
  %q = builtin.unrealized_conversion_cast %dp : memref<?xi8, strided<[1], offset: ?>> to !text

  %rows, %kids, %fault, %at = confix.index json %t : !text -> !ix, !s32
  %k0 = trikeshed.key 0 : !ik
  %k1 = trikeshed.key 1 : !ik
  %k2 = trikeshed.key 2 : !ik
  %spans = trikeshed.column %rows[%k0] : !ix, !ik -> !spans
  %tags = trikeshed.column %rows[%k1] : !ix, !ik -> !trikeshed.series<i8>
  %kc = trikeshed.column %rows[%k2] : !ix, !ik -> !trikeshed.series<!tp>
  %n = trikeshed.size %spans : !spans
  %nk = trikeshed.size %kids : !s32

  // fault, rows, kids
  %three = arith.constant 3 : index
  %head = trikeshed.series %three : !s32 {
  ^bb0(%i: index):
    %n32 = arith.index_cast %n : index to i32
    %nk32 = arith.index_cast %nk : index to i32
    %is0 = arith.cmpi eq, %i, %c0 : index
    %is1 = arith.cmpi eq, %i, %c1 : index
    %v12 = arith.select %is1, %n32, %nk32 : i32
    %v = arith.select %is0, %fault, %v12 : i32
    trikeshed.yield %v : i32
  }
  func.call @show(%head) : (!s32) -> ()

  // the columns: open and close of each span, the tag, first and count of each row's children; then the kids
  %opens = trikeshed.alpha %spans : !spans -> !s32 {
  ^bb0(%s: !tw):
    %o = trikeshed.first %s : !tw -> i32
    trikeshed.yield %o : i32
  }
  %closes = trikeshed.alpha %spans : !spans -> !s32 {
  ^bb0(%s: !tw):
    %c = trikeshed.second %s : !tw -> i32
    trikeshed.yield %c : i32
  }
  %tag32 = trikeshed.alpha %tags : !trikeshed.series<i8> -> !s32 {
  ^bb0(%x: i8):
    %w = arith.extui %x : i8 to i32
    trikeshed.yield %w : i32
  }
  %firsts = trikeshed.alpha %kc : !trikeshed.series<!tp> -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %counts = trikeshed.alpha %kc : !trikeshed.series<!tp> -> !s32 {
  ^bb0(%p: !tp):
    %c = trikeshed.second %p : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%opens) : (!s32) -> ()
  func.call @show(%closes) : (!s32) -> ()
  func.call @show(%tag32) : (!s32) -> ()
  func.call @show(%firsts) : (!s32) -> ()
  func.call @show(%counts) : (!s32) -> ()
  func.call @show(%kids) : (!s32) -> ()

  // the root's members, then the members of the options' elements: the Columns facet
  %root = trikeshed.series %c1 : !s32 {
  ^bb0(%i: index):
    %z = arith.constant 0 : i32
    trikeshed.yield %z : i32
  }
  %top = confix.columns json %rows, %kids, %t, %root ["options", "etc"] : !ix, !s32, !text, !s32 -> !top
  %t0 = trikeshed.key 0 : !topk
  %t1 = trikeshed.key 1 : !topk
  %optsCol = trikeshed.column %top[%t0] : !top, !topk -> !s32
  %etcCol = trikeshed.column %top[%t1] : !top, !topk -> !s32
  func.call @show(%optsCol) : (!s32) -> ()
  func.call @show(%etcCol) : (!s32) -> ()
  %opts = trikeshed.at %optsCol[%c0] : !s32, index -> i32
  %ofc = trikeshed.at %kc[%opts] : !trikeshed.series<!tp>, i32 -> !tp
  %of = trikeshed.first %ofc : !tp -> i32
  %on = trikeshed.second %ofc : !tp -> i32
  %ofi = arith.index_cast %of : i32 to index
  %oni = arith.index_cast %on : i32 to index
  %objs = trikeshed.slice %kids[%ofi, %oni] : !s32 -> !s32
  func.call @show(%objs) : (!s32) -> ()
  %tab = confix.columns json %rows, %kids, %t, %objs ["path", "kind", "state", "missing"] : !ix, !s32, !text, !s32 -> !tab
  %c0k = trikeshed.key 0 : !tabk
  %c1k = trikeshed.key 1 : !tabk
  %c2k = trikeshed.key 2 : !tabk
  %c3k = trikeshed.key 3 : !tabk
  %path = trikeshed.column %tab[%c0k] : !tab, !tabk -> !s32
  %kind = trikeshed.column %tab[%c1k] : !tab, !tabk -> !s32
  %state = trikeshed.column %tab[%c2k] : !tab, !tabk -> !s32
  %missing = trikeshed.column %tab[%c3k] : !tab, !tabk -> !s32
  func.call @show(%path) : (!s32) -> ()
  func.call @show(%kind) : (!s32) -> ()
  func.call @show(%state) : (!s32) -> ()
  func.call @show(%missing) : (!s32) -> ()

  // every string, sorted by its text (between its quotes): a slice of the text each, compared
  %all = trikeshed.series %n : !s32 {
  ^bb0(%i: index):
    %r = arith.index_cast %i : index to i32
    trikeshed.yield %r : i32
  }
  %strings = trikeshed.where %all : !s32 -> !s32 {
  ^bb0(%r: i32):
    %g = trikeshed.at %tags[%r] : !trikeshed.series<i8>, i32 -> i8
    %four = arith.constant 4 : i8
    %is = arith.cmpi eq, %g, %four : i8
    trikeshed.yield %is : i1
  }
  %sorted = trikeshed.sorted %strings : !s32 -> !s32 by {
  ^bb0(%a: i32, %b: i32):
    %sa = trikeshed.at %spans[%a] : !spans, i32 -> !tw
    %sb = trikeshed.at %spans[%b] : !spans, i32 -> !tw
    %oa = trikeshed.first %sa : !tw -> i32
    %ca = trikeshed.second %sa : !tw -> i32
    %ob = trikeshed.first %sb : !tw -> i32
    %cb = trikeshed.second %sb : !tw -> i32
    %ia = arith.addi %oa, %one : i32
    %ib = arith.addi %ob, %one : i32
    %na = arith.subi %ca, %ia : i32
    %nb = arith.subi %cb, %ib : i32
    %iai = arith.index_cast %ia : i32 to index
    %nai = arith.index_cast %na : i32 to index
    %ibi = arith.index_cast %ib : i32 to index
    %nbi = arith.index_cast %nb : i32 to index
    %ta = trikeshed.slice %t[%iai, %nai] : !text -> !text
    %tb = trikeshed.slice %t[%ibi, %nbi] : !text -> !text
    %c = trikeshed.compare %ta, %tb : !text, !text
    trikeshed.yield %c : i32
  }
  func.call @show(%sorted) : (!s32) -> ()

  // probes, as (start, len) in another text: none, q, "", zzz, kind
  %five = arith.constant 5 : index
  %probes = trikeshed.series %five : !trikeshed.series<!tp> {
  ^bb0(%i: index):
    %i32 = arith.index_cast %i : index to i32
    %s0 = arith.constant 0 : i32
    %s7 = arith.constant 7 : i32
    %s4 = arith.constant 4 : i32
    %s8 = arith.constant 8 : i32
    %l1 = arith.constant 1 : i32
    %l3 = arith.constant 3 : i32
    %e0 = arith.cmpi eq, %i32, %s0 : i32
    %e1 = arith.cmpi eq, %i32, %l1 : i32
    %two = arith.constant 2 : i32
    %e2 = arith.cmpi eq, %i32, %two : i32
    %e3 = arith.cmpi eq, %i32, %l3 : i32
    %st3 = arith.select %e3, %s4, %s8 : i32
    %st2 = arith.select %e2, %s0, %st3 : i32
    %st1 = arith.select %e1, %s7, %st2 : i32
    %start = arith.select %e0, %s0, %st1 : i32
    %ln3 = arith.select %e3, %l3, %s4 : i32
    %ln2 = arith.select %e2, %s0, %ln3 : i32
    %ln1 = arith.select %e1, %l1, %ln2 : i32
    %len = arith.select %e0, %s4, %ln1 : i32
    %p = trikeshed.j %start, %len : i32, i32 -> !tp
    trikeshed.yield %p : !tp
  }
  %found = trikeshed.alpha %probes : !trikeshed.series<!tp> -> !s32 {
  ^bb0(%k: !tp):
    %pos = trikeshed.bisect %sorted, %k : !s32, !tp -> index by {
    ^bb0(%x: i32, %key: !tp):
      %sx = trikeshed.at %spans[%x] : !spans, i32 -> !tw
      %ox = trikeshed.first %sx : !tw -> i32
      %cx = trikeshed.second %sx : !tw -> i32
      %ix = arith.addi %ox, %one : i32
      %nx = arith.subi %cx, %ix : i32
      %ixi = arith.index_cast %ix : i32 to index
      %nxi = arith.index_cast %nx : i32 to index
      %tx = trikeshed.slice %t[%ixi, %nxi] : !text -> !text
      %ks = trikeshed.first %key : !tp -> i32
      %kn = trikeshed.second %key : !tp -> i32
      %ksi = arith.index_cast %ks : i32 to index
      %kni = arith.index_cast %kn : i32 to index
      %tk = trikeshed.slice %q[%ksi, %kni] : !text -> !text
      %c = trikeshed.compare %tx, %tk : !text, !text
      trikeshed.yield %c : i32
    }
    %r = arith.index_cast %pos : index to i32
    trikeshed.yield %r : i32
  }
  func.call @show(%found) : (!s32) -> ()
  return
}
