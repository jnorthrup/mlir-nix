// The verifier of a mlnix.session: one setting of each kind, a tier that compiles for a threshold, and the ranges.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{holds at most one each of mlnix.schedule, pipeline, jit, prelower and census}}
mlnix.session @twice {
  mlnix.schedule eager
  mlnix.schedule demand
}

// -----

mlnix.session @off {
  // expected-error @+1 {{takes no threshold or opt with tier off}}
  mlnix.jit off threshold 8
}

// -----

mlnix.session @many {
  // expected-error @+1 {{attribute 'threads' failed to satisfy constraint}}
  mlnix.prelower threads 9
}
