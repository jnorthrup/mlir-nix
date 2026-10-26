// failures(propagate) turns a silenceable failure into an error of the pass.
// RUN: mlnix-opt %s --transform-interpreter --split-input-file --verify-diagnostics

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    transform.sequence %root : !transform.any_op failures(propagate) {
    ^bb0(%m: !transform.any_op):
      // expected-error @+1 {{wrong operation name}}
      transform.match.operation_name %m ["no.such.op"] : !transform.any_op
    }
    transform.yield
  }
  nix.expr @e {
    %one = nix.int 1
    nix.return %one
  }
}

// -----

// A pass cannot be applied to a payload root that contains the script itself.
// expected-note @below {{target payload op}}
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.consumed}) {
    // expected-error @+1 {{cannot apply transform to itself (or one of its ancestors)}}
    %0 = transform.apply_registered_pass "nix-prims" to %root : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
}
