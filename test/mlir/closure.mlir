// trikeshed.adjacency (a counting sort: each node's (first, count) into the far ends, in edge order; an edge from no node
// left out) and trikeshed.closure (ClosureIndex's ancestor sets: the node itself never among them, a self edge adding
// nothing, a cycle cut where it is met), lowered by trikeshed-lower-cursors and run.
//
// RUN: mlnix-opt %s | mlnix-opt | FileCheck %s --check-prefix=ROUND
// RUN: mlnix-opt %s --trikeshed-lower-cursors | mlir-opt --ownership-based-buffer-deallocation --canonicalize --buffer-deallocation-simplification --bufferization-lower-deallocations --convert-scf-to-cf --expand-strided-metadata --lower-affine --finalize-memref-to-llvm --convert-arith-to-llvm --convert-index-to-llvm --convert-cf-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts | mlir-runner -e main -entry-point-result=i32 -shared-libs=$(ls $(dirname $(which mlir-runner))/../lib/libmlir_runner_utils.* | head -1) | FileCheck %s
//
// Edges 2->10 0->11 2->12 5->13 -1->14 1->15 2->16 over nodes 0..3: node 0 has (0, 1), node 1 (1, 1), node 2 (2, 3) in
// edge order, node 3 none; 5 and -1 are no node.  The graph 0->1 1->2 2->0 3->3 3->4 over 0..4: 0 reaches 1, 2 (the
// cycle back to 0 cut), 1 reaches 2, 0, 2 reaches 0, 1, 3 reaches 4 (its self edge adds nothing), 4 none; each set in
// the order the walk meets it.

// ROUND: trikeshed.adjacency %{{.*}}, %{{.*}} over %{{.*}} : <i32>, <i32> -> <!trikeshed.twinpacked<i32>>, <i32>
// ROUND: trikeshed.closure %{{.*}}, %{{.*}} : <!trikeshed.twinpacked<i32>>, <i32> -> <!trikeshed.twinpacked<i32>>, <i32>

// adjacency: firsts, counts, ends
// CHECK: [0,  1,  2,  5]
// CHECK: [1,  1,  3,  0]
// CHECK: [11,  15,  10,  12,  16]
// closure: firsts, counts, members
// CHECK: [0,  2,  4,  6,  7]
// CHECK: [2,  2,  2,  1,  0]
// CHECK: [1,  2,  2,  0,  0,  1,  4]
// CHECK: 0

!s32 = !trikeshed.series<i32>
!tp = !trikeshed.twinpacked<i32>
!sp = !trikeshed.series<!tp>
!buf = memref<?xi32, strided<[1], offset: ?>>

memref.global "private" constant @from : memref<7xi32> = dense<[2, 0, 2, 5, -1, 1, 2]>
memref.global "private" constant @to : memref<7xi32> = dense<[10, 11, 12, 13, 14, 15, 16]>
memref.global "private" constant @child : memref<5xi32> = dense<[0, 1, 2, 3, 3]>
memref.global "private" constant @parent : memref<5xi32> = dense<[1, 2, 0, 3, 4]>
func.func private @printMemrefI32(memref<*xi32>) attributes {llvm.emit_c_interface}

// a series of i32 printed: its elements drained into a buffer of its size
func.func private @show(%xs: !s32) {
  %n = trikeshed.size %xs : !s32
  %out = memref.alloc(%n) : memref<?xi32>
  %end = trikeshed.drain %xs, %out : !s32, memref<?xi32> -> index
  %u = memref.cast %out : memref<?xi32> to memref<*xi32>
  func.call @printMemrefI32(%u) : (memref<*xi32>) -> ()
  return
}

// each (first, count) of a series of them, printed as the firsts, then the counts
func.func private @show_pairs(%ps: !sp) {
  %firsts = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%p: !tp):
    %f = trikeshed.first %p : !tp -> i32
    trikeshed.yield %f : i32
  }
  %counts = trikeshed.alpha %ps : !sp -> !s32 {
  ^bb0(%p: !tp):
    %c = trikeshed.second %p : !tp -> i32
    trikeshed.yield %c : i32
  }
  func.call @show(%firsts) : (!s32) -> ()
  func.call @show(%counts) : (!s32) -> ()
  return
}

func.func @main() -> i32 {
  %gf = memref.get_global @from : memref<7xi32>
  %gt = memref.get_global @to : memref<7xi32>
  %gc = memref.get_global @child : memref<5xi32>
  %gp = memref.get_global @parent : memref<5xi32>
  %df = memref.cast %gf : memref<7xi32> to !buf
  %dt = memref.cast %gt : memref<7xi32> to !buf
  %dc = memref.cast %gc : memref<5xi32> to !buf
  %dp = memref.cast %gp : memref<5xi32> to !buf
  %from = builtin.unrealized_conversion_cast %df : !buf to !s32
  %to = builtin.unrealized_conversion_cast %dt : !buf to !s32
  %child = builtin.unrealized_conversion_cast %dc : !buf to !s32
  %parent = builtin.unrealized_conversion_cast %dp : !buf to !s32
  %four = arith.constant 4 : index
  %five = arith.constant 5 : index
  %index, %ends = trikeshed.adjacency %from, %to over %four : !s32, !s32 -> !sp, !s32
  func.call @show_pairs(%index) : (!sp) -> ()
  func.call @show(%ends) : (!s32) -> ()
  %up, %ps = trikeshed.adjacency %child, %parent over %five : !s32, !s32 -> !sp, !s32
  %ancestors, %members = trikeshed.closure %up, %ps : !sp, !s32 -> !sp, !s32
  func.call @show_pairs(%ancestors) : (!sp) -> ()
  func.call @show(%members) : (!s32) -> ()
  %ok = arith.constant 0 : i32
  return %ok : i32
}
