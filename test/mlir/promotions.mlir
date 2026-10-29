// What each value is promoted to is one decision of the dialect (NixDialect::promotionOf), read by the evaluator (which cell the
// value gets), the JITs (what they may read back or replay) and the optimizer (what may be merged).  `nix-promotions` prints it:
//   in_place  one strict or tail use in the same body: evaluated into its consumer, no cell
//   fixed     a literal or a builtin: the same value in every frame, one cell for all of them, no frame cell
//   shared    any other value of an op with no memory effect: a cell per frame, made lazily; equal ones may be merged
//   distinct  every evaluation is its own (an allocation with observable identity, or a call that may run user code): never merged
//   closure   a lambda: a cell per frame, made at its first touch
//
// RUN: mlnix-opt %s -nix-promotions | FileCheck %s

// CHECK-LABEL: nix.expr @promotions
nix.expr @promotions {
  // a literal and a builtin read lazily (a list element, a call's argument): fixed, whatever reads them
  // CHECK: nix.int 1 {nix.promote = "fixed"}
  %one = nix.int 1
  // CHECK: nix.builtin "toString" {nix.promote = "fixed"}
  %f = nix.builtin "toString"
  // a call may run user code: distinct, even with equal operands
  // CHECK: nix.apply %{{.*}}(%{{.*}}) {nix.promote = "distinct"}
  %call = nix.apply %f(%one)
  // a list has observable identity: distinct
  // CHECK: nix.list[%{{.*}}] {nix.promote = "distinct"}
  %inner = nix.list [%one]
  // CHECK: nix.lambda attributes {arg_name = "x", nix.promote = "closure"}
  %lam = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    // the one strict operand of eq, used once, in the same body: in place
    // CHECK: nix.int 2 {nix.promote = "in_place"}
    %two = nix.int 2
    // a pure value read lazily (a list element): shared
    // CHECK: nix.eq %{{.*}}, %{{.*}} {nix.promote = "shared"}
    %e = nix.eq %x, %two
    // CHECK: nix.select %{{.*}}["a"] {nix.promote = "shared"}
    %s = nix.select %x ["a"]
    // the body's result is its tail operand: in place
    // CHECK: nix.list[%{{.*}}, %{{.*}}] {nix.promote = "in_place"}
    %r = nix.list [%e, %s]
    nix.return %r
  }
  // the expression's result: a tail use
  // CHECK: nix.list[%{{.*}}, %{{.*}}, %{{.*}}] {nix.promote = "in_place"}
  %res = nix.list [%call, %inner, %lam]
  nix.return %res
}
