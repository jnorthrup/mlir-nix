// End to end: the default pipeline of `mlnix` produces continent-dialect IR
// for ordinary Nix code, and `true`/`false`/`null` are real constants.
// RUN: mlnix emit-mlir -E 'let xs = [1 2 3]; in { n = builtins.length xs; u = builtins.map (x: x * 2) xs; t = true; z = null; }' | FileCheck %s

// CHECK: nix.null
// CHECK: nix.bool true
// CHECK: nixlist.length(
// CHECK: nixlist.map(
// CHECK-NOT: nix.builtin "builtins"
