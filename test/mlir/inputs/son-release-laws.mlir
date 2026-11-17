// son.release's laws (Son.td), each broken once; son-release.mlir runs this file with --verify-diagnostics.

// A cell passed on (the list's element %2) reads %1; the release lets %1 go.
nix.expr @releases_a_read {
  %0 = nix.int 1
  // expected-note @+1 {{this value}}
  %1 = nix.int 2
  %2 = nix.eq %0, %1
  %3 = nix.list[%2]
  // expected-error @+1 {{'son.release' op releases a value a cell passed on can still read}}
  son.release(%0, %2)
  nix.return %2
}

// -----

// A lambda not deferred yet captures %0: the closure is a cell that reads it.
nix.expr @captured {
  // expected-note @+1 {{this value}}
  %0 = nix.int 1
  %1 = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%arg0: !nix.value):
    nix.return %0
  }
  // expected-error @+1 {{'son.release' op releases a value a cell passed on can still read}}
  son.release()
  nix.return %1 : (!nix.value) -> !nix.value
}

// -----

nix.expr @released_twice {
  %0 = nix.int 1
  son.release()
  // expected-error @+1 {{'son.release' op follows another in its frame: a frame is released once}}
  son.release()
  nix.return %0
}

// -----

// A lambda's body is not a frame until it is deferred: the frame is its son.body.
nix.expr @in_a_lambda {
  %0 = nix.lambda attributes {arg_name = "x"} {
  ^bb0(%arg0: !nix.value):
    // expected-error @+1 {{'son.release' op expects parent op to be one of}}
    son.release()
    nix.return %arg0
  }
  nix.return %0 : (!nix.value) -> !nix.value
}

// -----

// Keeping more than the cells read is sound: here, the whole frame.
nix.expr @keeps_more {
  %0 = nix.int 1
  %1 = nix.list[%0]
  son.release(%0, %1 : !trikeshed.series<!nix.value>)
  nix.return %1 : !trikeshed.series<!nix.value>
}
