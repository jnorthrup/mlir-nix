// A variable starts with ?, and a sumo op lives in a theory.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

kif.theory @v {
  // expected-error @+1 {{a variable's name starts with ?}}
  %x = kif.var "x"
}

// -----

// expected-error @+1 {{expects parent op 'kif.theory'}}
sumo.subclass "A" "B"
