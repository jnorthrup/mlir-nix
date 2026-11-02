// A defer binds as many captures as its body takes, and names a body.
// RUN: mlnix-opt %s --split-input-file --verify-diagnostics

son.pool @bodies {
  son.body @row0 captures 1 lambda {arg_name = "x"} {
  ^bb0(%k: !nix.value, %x: !nix.value):
    nix.return %x
  }
}
nix.expr @a {
  %k = nix.int 1
  // expected-error @+1 {{binds 2 captures, the body takes 1}}
  %f = son.defer @bodies::@row0(%k, %k)
  nix.return %f
}

// -----

nix.expr @b {
  %k = nix.int 1
  // expected-error @+1 {{which is no son.body}}
  %f = son.defer @bodies::@nowhere(%k)
  nix.return %f
}

// -----

son.pool @bodies {
  // expected-error @+1 {{takes its captures and then the lambda's argument: 2 block arguments}}
  son.body @row0 captures 1 lambda {arg_name = "x"} {
  ^bb0(%x: !nix.value):
    nix.return %x
  }
}
