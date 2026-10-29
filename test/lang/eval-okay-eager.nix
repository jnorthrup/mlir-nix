# A value whose first touch is a strict use is evaluated straight into its cell, never made a thunk.  The order, the sharing, recursion
# detection and the retry of a failed value must be what they were.
let
  f = n: let v = n * 2; in v + v;                         # shared, first touch strict
  t = throw "boom";
  retried = [ (builtins.tryEval t).success (builtins.tryEval t).success ];
  d = { a ? 5 }: a + a;                                     # a formal default, shared
  s = { };
  orDefault = let x = s.missing or 7; in x + x;
  g = x: x;
  callee = let h = g; in h 1 + h 2;                         # a callee evaluated at its first touch
  r = n: if n == 0 then 0 else let p = r (n - 1); in p + 1;
  asserted = builtins.tryEval (let e = assert 1 == 2; 1; in e + e);   # a failed assert is retried, and caught
in {
  inherit retried orDefault callee;
  shared = f 3;
  default = d { };
  deep = r 3000;
  assertSuccess = asserted.success;
}
