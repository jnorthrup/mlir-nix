// Operand modalities are declared with the NixModes trait in NixOps.td (strict / tail
// operand indices; everything else is lazy).  `nix-inline-values` marks the values the
// evaluator evaluates in place: exactly one use, in the same region, by a strict or tail
// operand.  The evaluator asks the same question (NixDialect::evaluatesInPlace) per value.
//
// RUN: mlnix-opt %s -nix-inline-values | FileCheck %s

// CHECK-LABEL: nix.expr @strict_and_tail
nix.expr @strict_and_tail {
  // The lambda is returned: a tail use.
  // CHECK: %{{.*}} = nix.lambda attributes {arg_name = "x", nix.inline}
  %0 = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%arg0: !nix.value):
    // operands of eq / neq / and / not / update are strict; the if condition is strict
    // CHECK: nix.int 1 {nix.inline}
    %1 = nix.int 1
    // CHECK: nix.eq %{{.*}}, %{{.*}} {nix.inline}
    %2 = nix.eq %arg0, %1
    %3 = nix.int 2
    %4 = nix.neq %arg0, %3
    // CHECK: nix.and %{{.*}}, %{{.*}} {nix.inline}
    %5 = nix.and %2, %4
    // attribute values are lazy: not marked
    // CHECK: %[[V:.*]] = nix.int 1{{$}}
    %6 = nix.int 1
    // the attribute set itself is the right operand of //: strict
    // CHECK: nix.attrs ["a"](%[[V]]) {nix.inline
    %7 = nix.attrs ["a"](%6)
    // CHECK: nix.update %{{.*}}, %{{.*}} {nix.inline}
    %8 = nix.update %arg0, %7
    %9 = nix.int 2
    %10 = nix.attrs ["b"](%9)
    %11 = nix.update %8, %10
    %12 = nix.not %arg0
    %13 = nix.not %12
    // both branches are tail operands; the if is the lambda's result
    // CHECK: nix.if %{{.*}} then %{{.*}} else %{{.*}} {nix.inline}
    %14 = nix.if %5 then %11 else %13
    nix.return %14
  }
  nix.return %0
}

// CHECK-LABEL: nix.expr @not_in_place
nix.expr @not_in_place {
  // used twice: the first use must not recompute it
  // CHECK: %[[C:.*]] = nix.int 5{{$}}
  %c = nix.int 5
  // CHECK: nix.eq %[[C]], %[[C]]{{$}}
  %e = nix.eq %c, %c
  // a list element is lazy: neither the 7 nor the list holding it is marked
  // CHECK: nix.int 7{{$}}
  %d = nix.int 7
  // CHECK: nix.list[%{{.*}}]{{$}}
  %l = nix.list [%d]
  // used in another region (the lambda may run many times; the value is shared)
  // CHECK: %[[G:.*]] = nix.int 9{{$}}
  %g = nix.int 9
  // CHECK: nix.lambda attributes {arg_name = "y"} {
  %lam = nix.lambda attributes {arg_name = "y"} {
  ^bb0(%y: !nix.value):
    // CHECK: nix.eq %{{.*}}, %[[G]] {nix.inline}
    %r = nix.eq %y, %g
    nix.return %r
  }
  // list elements are lazy, so %e, %l and %lam stay thunks; the list itself is the
  // expression's result: a tail use, marked
  // CHECK: nix.list[{{.*}}] {nix.inline}
  %res = nix.list [%e, %l, %lam]
  nix.return %res
}
