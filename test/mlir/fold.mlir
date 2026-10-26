// Primops flagged `foldable` in NixPrims.td are constant-folded by *one*
// generic folder that calls the evaluator's own implementation. Anything that
// would throw is left for run time, so errors keep their position and trace.
// RUN: MLNIX_PASSES=devirt,fold mlnix emit-mlir -E '[ (builtins.add 1 2) (builtins.substring 1 3 "hello") (builtins.isInt 5) (builtins.lessThan 1 2) (builtins.typeOf 1.5) (toString 42) (builtins.div 1 0) ]' | FileCheck %s

// CHECK: nix.expr
// CHECK-DAG: nix.int 3
// CHECK-DAG: nix.str "ell"
// CHECK-DAG: nix.str "float"
// CHECK-DAG: nix.str "42"
// CHECK-DAG: nix.bool true
// The failing call survives as an op:
// CHECK: nixnum.div(
// and nothing else of the primops does:
// CHECK-NOT: nixnum.add
// CHECK-NOT: nixty.is_int
// CHECK-NOT: nixstr.substring
