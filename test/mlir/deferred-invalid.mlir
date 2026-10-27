// A deferred lambda (MLNIX_DEFER=1) is a shell that exists only in memory, between lowering and its
// first call: its block is empty, so the verifier refuses it whether or not it carries a body_index.
//
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

nix.expr @empty {
  // expected-error @+1 {{expects a non-empty block}}
  %f = "nix.lambda"() <{arg_name = "x"}> ({
  ^bb0(%arg0: !nix.value):
  }) : () -> !nix.value
  %0 = nix.int 1
  nix.return %0
}

// -----

nix.expr @shell {
  %v = nix.int 7
  // expected-error @+1 {{expects a non-empty block}}
  %f = "nix.lambda"(%v) <{arg_name = "x", body_index = 4294967296 : i64}> ({
  ^bb0(%arg0: !nix.value):
  }) : (!nix.value) -> !nix.value
  nix.return %f
}
