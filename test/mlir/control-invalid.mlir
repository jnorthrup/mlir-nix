// The verifier of a mlnix.session: one setting of each kind, and the ranges.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{holds at most one each of mlnix.schedule, pipeline, prelower and census}}
mlnix.session @twice {
  mlnix.schedule eager
  mlnix.schedule demand
}

// -----

mlnix.session @many {
  // expected-error @+1 {{attribute 'threads' failed to satisfy constraint}}
  mlnix.prelower threads 9
}
