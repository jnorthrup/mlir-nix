// Values with observable identity are declared as allocations, so the stock passes
// stay sound without any Nix-specific code:
//   * `(x: x) == (x: x)` is false in Nix, so two identical lambdas must not be merged
//     (merging them broke eval-okay-equal-function-*-distinct-similar and eval-okay-sort);
//   * lists and attribute sets are compared and printed by identity in places;
//   * a primop that returns a fresh list / attribute set (nix.fresh) is pure but
//     equal calls are kept;
//   * an unused fresh value is still dead, but a call that may run user code is not.
//
// RUN: mlnix-opt %s -cse | FileCheck %s
// RUN: mlnix-opt %s -canonicalize | FileCheck %s --check-prefix=DEAD

// CHECK-LABEL: nix.expr @functions
// DEAD-LABEL: nix.expr @functions
nix.expr @functions {
  %f = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    nix.return %x
  }
  %g = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    nix.return %x
  }
  %r = nix.list [%f, %g]
  nix.return %r
}
// CHECK-COUNT-2: nix.lambda
// CHECK: nix.list

// CHECK-LABEL: nix.expr @containers
// DEAD-LABEL: nix.expr @containers
nix.expr @containers {
  %a = nix.int 1
  %l1 = nix.list [%a]
  %l2 = nix.list [%a]
  %s = nix.attrs [](  )
  %n1 = nixattr.attr_names(%s)
  %n2 = nixattr.attr_names(%s)
  %r = nix.list [%l1, %l2, %n1, %n2]
  nix.return %r
}
// CHECK: nix.list
// CHECK: nix.list
// CHECK: nixattr.attr_names(
// CHECK: nixattr.attr_names(

// A pure, non-fresh primop is still merged (see effects.mlir).
// CHECK-LABEL: nix.expr @still_merged
nix.expr @still_merged {
  %a = nix.int 1
  %l = nix.list [%a]
  %x = nixlist.length(%l)
  %y = nixlist.length(%l)
  %r = nix.list [%x, %y]
  nix.return %r
}
// CHECK: nixlist.length(
// CHECK-NOT: nixlist.length(

// DEAD-LABEL: nix.expr @dead
nix.expr @dead {
  %s = nix.attrs [](  )
  %unused = nixattr.attr_names(%s)
  %f = nix.builtin "toString"
  %call = nix.apply %f(%s)
  %r = nix.int 1
  nix.return %r
}
// An unused fresh value is dead; a call (may run user code) is kept.
// DEAD-NOT: nixattr.attr_names
// DEAD: nix.apply
