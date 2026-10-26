// Effects are declared, so the stock CSE pass is sound on Nix IR without any
// Nix-specific code: pure primops are merged, ops that may run user code or
// emit diagnostics are not.
// RUN: mlnix-opt %s -cse | FileCheck %s

// CHECK-LABEL: nix.expr @pure
nix.expr @pure {
  %a = nix.int 1
  %b = nix.int 2
  %x = nixnum.add(%a, %b)
  %y = nixnum.add(%a, %b)
  %r = nix.list [%x, %y]
  nix.return %r
}
// CHECK: [[S:%.*]] = nixnum.add(
// CHECK-NOT: nixnum.add
// CHECK: nix.list[[[S]], [[S]]]

// CHECK-LABEL: nix.expr @user_code
nix.expr @user_code {
  %f = nix.builtin "toString"
  %l = nix.list []
  %x = nixlist.map(%f, %l)
  %y = nixlist.map(%f, %l)
  %r = nix.list [%x, %y]
  nix.return %r
}
// CHECK: nixlist.map(
// CHECK: nixlist.map(

// CHECK-LABEL: nix.expr @diagnostics
nix.expr @diagnostics {
  %m = nix.str "hi"
  %v = nix.int 1
  %x = nixctl.trace(%m, %v)
  %y = nixctl.trace(%m, %v)
  %r = nix.list [%x, %y]
  nix.return %r
}
// CHECK: nixctl.trace(
// CHECK: nixctl.trace(
