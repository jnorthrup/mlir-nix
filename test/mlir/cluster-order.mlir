// A cluster orders at most 23 keys. It writes a stable permutation, not copies
// of the payload. These are buffer effects: CSE must keep both writes.
// RUN: mlnix-opt %s -cse | FileCheck %s
// RUN: ext=so; if [ "$(uname -s)" = Darwin ]; then ext=dylib; fi; mlnix-opt %S/inputs/cluster-order-async.mlir -trikeshed-lower-clusters | mlir-opt -expand-strided-metadata -async-to-async-runtime -async-runtime-ref-counting -convert-async-to-llvm -convert-scf-to-cf -convert-arith-to-llvm -finalize-memref-to-llvm -convert-func-to-llvm -convert-cf-to-llvm -reconcile-unrealized-casts | mlir-runner -O2 -e main -entry-point-result=i32 -shared-libs=%S/../../build/lib/libTrikeShedRuntime.${ext},$(llvm-config --libdir)/libmlir_async_runtime.${ext} | FileCheck %s --check-prefix=EXEC
// EXEC: 0
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
