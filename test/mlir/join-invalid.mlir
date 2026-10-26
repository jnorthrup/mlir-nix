// A join of something with no fixed width (index is as wide as the host) cannot be collapsed
// to an integer, and the conversion names the op it could not legalize.
//
// RUN: mlnix-opt %s -join-densify -verify-diagnostics

func.func @no_width(%a: index, %b: i32) -> i32 {
  // expected-error@+1 {{failed to legalize operation 'join.make'}}
  %j = join.make %a, %b : !join.pair<index, i32>
  %r = join.second %j : !join.pair<index, i32>
  return %r : i32
}
