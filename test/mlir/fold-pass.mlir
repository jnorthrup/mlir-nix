// `nix-fold` is the greedy canonicalization stage: op folders (here: constant
// string concatenation) and identity forwarding. Folding *primops* needs the
// evaluator's implementation (Dialect::primFolder), which mlnix-opt does not
// have; test/mlir/fold.mlir and driver.mlir cover that through `mlnix`.
//
// RUN: mlnix-opt %s --nix-fold | FileCheck %s

// CHECK-LABEL: nix.expr @concat
nix.expr @concat {
  %a = nix.str "foo"
  %b = nix.str "bar"
  %ab = nix.concat_strings %a, %b
  nix.return %ab
}
// CHECK: nix.str "foobar"
// CHECK-NOT: nix.concat_strings

// A zero-argument application only gives its operand a value identity; when
// nothing else uses the operand it is forwarded.
// CHECK-LABEL: nix.expr @identity
nix.expr @identity {
  %v = nix.int 5
  %i = nix.apply %v()
  nix.return %i
}
// CHECK-NOT: nix.apply
// CHECK: nix.return
