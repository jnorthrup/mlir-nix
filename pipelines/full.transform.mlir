// A pipeline that uses every Transform-dialect combinator the experiment tried
// (see experiments/PIPELINE.md); run it with
//
//   MLNIX_TRANSFORM=pipelines/full.transform.mlir mlnix ...
//   mlnix-opt payload.mlir \
//       --transform-preload-library=transform-library-paths=pipelines/full.transform.mlir \
//       --transform-interpreter
//
// What it does to the payload module (one lowered `nix.expr` when run by the
// evaluator):
//   1. nix-prims                                   must work: failures(propagate)
//   2. on a clone of each expression, try: nix-fold, nix-dce, stock CSE + DCE;
//      if any step fails (silenceable), keep the unoptimized original
//      (transform.alternatives = try / else)
//   3. the optional part runs under failures(suppress), so it can never fail
//      the evaluation.
module attributes {transform.with_named_sequence} {

  // -- reusable stages (transform.include) ----------------------------------

  // Consumes the handle (a pass may rewrite anything below it) and returns a
  // fresh handle to the same op.
  transform.named_sequence @devirtualize(%root: !transform.any_op {transform.consumed})
      -> !transform.any_op {
    %r = transform.apply_registered_pass "nix-prims" to %root
        : (!transform.any_op) -> !transform.any_op
    transform.yield %r : !transform.any_op
  }

  // The stock cleanups, which only read the handle and rewrite the payload.
  transform.named_sequence @tidy(%exprs: !transform.any_op {transform.readonly}) {
    transform.apply_cse to %exprs : !transform.any_op
    transform.apply_dce to %exprs : !transform.any_op
    transform.yield
  }

  // -- a matcher: the nix.expr ops below the payload root --------------------
  transform.named_sequence @match_expr(%op: !transform.any_op {transform.readonly})
      -> !transform.any_op {
    transform.match.operation_name %op ["nix.expr"] : !transform.any_op
    transform.yield %op : !transform.any_op
  }

  // -- the entry point -------------------------------------------------------
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.consumed}) {
    %devirted = transform.include @devirtualize failures(propagate) (%root)
        : (!transform.any_op) -> !transform.any_op

    transform.sequence %devirted : !transform.any_op failures(suppress) {
    ^bb0(%module: !transform.any_op):
      %exprs = transform.collect_matching @match_expr in %module
          : (!transform.any_op) -> !transform.any_op
      transform.alternatives %exprs : !transform.any_op {
      ^bb0(%scope: !transform.any_op):
        %folded = transform.apply_registered_pass "nix-fold" to %scope
            : (!transform.any_op) -> !transform.any_op
        %clean = transform.apply_registered_pass "nix-dce" to %folded
            : (!transform.any_op) -> !transform.any_op
        transform.include @tidy failures(propagate) (%clean) : (!transform.any_op) -> ()
      }, {
      ^bb0(%scope: !transform.any_op):
        // Nothing worked: keep the devirtualized expression as it is.
        transform.yield
      }
    }
    transform.yield
  }
}
