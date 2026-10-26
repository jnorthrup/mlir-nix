// The default optimization pipeline of mlnix, as a Transform-dialect script:
// the equivalent of the textual pipeline `builtin.module(nix-prims)`.
//
// The evaluator runs this once per lowered file.  The payload root %root is a
// builtin.module that holds exactly the freshly lowered `nix.expr`.
// `apply_registered_pass` consumes its operand handle and returns a new handle
// to the same op, so a chain threads the result of each step.
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.consumed}) {
    %r = transform.apply_registered_pass "nix-prims" to %root
        : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
}
