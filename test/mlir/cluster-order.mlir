// A cluster orders at most 23 keys. It writes a stable permutation, not copies
// of the payload. These are buffer effects: CSE must keep both writes.
// RUN: mlnix-opt %s -cse | FileCheck %s
// CHECK-LABEL: nix.expr @cluster
// CHECK-COUNT-2: "trikeshed.cluster_order"
// CHECK: nix.return
nix.expr @cluster {
^bb0(%keys: memref<?xi64>, %out: memref<?xi64>):
  %a = "trikeshed.cluster_order"(%keys, %out) : (memref<?xi64>, memref<?xi64>) -> i1
  %b = "trikeshed.cluster_order"(%keys, %out) : (memref<?xi64>, memref<?xi64>) -> i1
  %zero = nix.int 0
  nix.return %zero
}
