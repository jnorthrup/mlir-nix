// `mlnix emit-mlir` prints a whole module, so it lowers eagerly even when MLNIX_DEFER=1 asks for the
// demand schedule: a deferred body would print as an empty shell, which is not the program.
//
// RUN: MLNIX_DEFER=1 mlnix emit-mlir -E '(x: x + 1) 2' | FileCheck %s

// CHECK: nix.lambda
// CHECK-NOT: body_index
// CHECK: nix.concat_strings
// CHECK: nix.return
