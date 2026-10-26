// The Transform dialect drives the same passes: scripts are payload-agnostic
// data (here in the same file as the payload, run by `--transform-interpreter`).
// Each chunk shows one combinator.
// RUN: mlnix-opt %s --transform-interpreter --split-input-file | FileCheck %s

// foreach_match: a matcher/action pair of named sequences, applied to every
// nix.expr in the payload. (Applying a pass to the payload *root* would be
// rejected here: the root contains the script itself, see PIPELINE.md.)
module attributes {transform.with_named_sequence} {
  transform.named_sequence @match_expr(%op: !transform.any_op {transform.readonly}) -> !transform.any_op {
    transform.match.operation_name %op ["nix.expr"] : !transform.any_op
    transform.yield %op : !transform.any_op
  }
  transform.named_sequence @devirt(%e: !transform.any_op {transform.consumed}) {
    %0 = transform.apply_registered_pass "nix-prims" to %e : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.consumed}) {
    %r = transform.foreach_match in %root @match_expr -> @devirt : (!transform.any_op) -> !transform.any_op
    transform.yield
  }
  // CHECK-LABEL: nix.expr @foreach
  nix.expr @foreach {
    %add = nix.builtin "__add"
    %one = nix.int 1
    %x = nix.apply %add(%one, %one)
    nix.return %x
  }
  // CHECK: nixnum.add(
  // CHECK-NOT: nix.apply
}

// -----

// include + sequence + apply_cse/apply_dce on the expression handle.
module attributes {transform.with_named_sequence} {
  transform.named_sequence @match_expr(%op: !transform.any_op {transform.readonly}) -> !transform.any_op {
    transform.match.operation_name %op ["nix.expr"] : !transform.any_op
    transform.yield %op : !transform.any_op
  }
  transform.named_sequence @tidy(%exprs: !transform.any_op {transform.readonly}) {
    transform.apply_cse to %exprs : !transform.any_op
    transform.apply_dce to %exprs : !transform.any_op
    transform.yield
  }
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    %exprs = transform.collect_matching @match_expr in %root : (!transform.any_op) -> !transform.any_op
    transform.include @tidy failures(propagate) (%exprs) : (!transform.any_op) -> ()
    transform.yield
  }
  // CHECK-LABEL: nix.expr @cleanup
  nix.expr @cleanup {
    %a = nix.int 1
    %b = nix.int 1
    %dead = nix.str "unused"
    %r = nix.list [%a, %b]
    nix.return %r
  }
  // CHECK: [[ONE:%.*]] = nix.int 1
  // CHECK-NOT: nix.int
  // CHECK-NOT: nix.str
  // CHECK: nix.list[[[ONE]], [[ONE]]]
}

// -----

// alternatives: a failing (silenceable) alternative is reverted -- it ran on a
// clone -- and the next one is tried.
module attributes {transform.with_named_sequence} {
  transform.named_sequence @match_expr(%op: !transform.any_op {transform.readonly}) -> !transform.any_op {
    transform.match.operation_name %op ["nix.expr"] : !transform.any_op
    transform.yield %op : !transform.any_op
  }
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    %exprs = transform.collect_matching @match_expr in %root : (!transform.any_op) -> !transform.any_op
    transform.alternatives %exprs : !transform.any_op {
    ^bb0(%scope: !transform.any_op):
      %r = transform.apply_registered_pass "nix-prims" to %scope : (!transform.any_op) -> !transform.any_op
      transform.match.operation_name %r ["no.such.op"] : !transform.any_op
    }, {
    ^bb0(%scope: !transform.any_op):
      transform.yield
    }
    transform.yield
  }
  // CHECK-LABEL: nix.expr @reverted
  nix.expr @reverted {
    %add = nix.builtin "__add"
    %one = nix.int 1
    %x = nix.apply %add(%one, %one)
    nix.return %x
  }
  // The first alternative devirtualized its clone, then failed: nothing stuck.
  // CHECK: nix.apply
  // CHECK-NOT: nixnum.add
}

// -----

// failures(suppress): a silenceable failure ends the sequence quietly, and the
// interpreter still succeeds.
module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    transform.sequence %root : !transform.any_op failures(suppress) {
    ^bb0(%m: !transform.any_op):
      transform.match.operation_name %m ["no.such.op"] : !transform.any_op
    }
    transform.yield
  }
  // CHECK-LABEL: nix.expr @suppressed
  nix.expr @suppressed {
    %one = nix.int 1
    nix.return %one
  }
}
