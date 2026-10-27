# Not upstream.  Probes the free-name analysis of the demand schedule (MLNIX_DEFER=1): a lambda body
# is minted on its first call, so what the lambda reads from outside has to be captured when the lambda
# is lowered.  Each element names the rule it exercises.  The expected output is Nix 2.35.4's.
let
  a = 5;
  s = { k = 3; };
  d = 10;
in [
  # `inherit x;` reads outside the group it defines
  (let f = y: let inherit a; in a + y; in f 1)
  (let f = y: rec { inherit a; b = a + y; }; in (f 1).b)
  (let f = y: let inherit (s) k; in k + y; in f 1)

  # the free names of a lambda nested in a lambda are the outer lambda's too
  (let f = y: (z: a + z) y; in f 1)
  (let f = y: let g = z: z + y; in g 1; in f 10)

  # formal defaults read names from outside, and earlier formals
  (let f = { x, w ? d }: x + w; in f { x = 1; })
  (let f = { x, w ? x + 1 }: x + w; in f { x = 1; })

  # `with` is captured as a chain, innermost first, and a lexical binding beats every `with`
  (with { z = 10; }; (y: z + y) 5)
  (with { p = 1; q = 2; }; with { p = 10; }; (y: p + q + y) 100)
  (let z = 1; in with { z = 2; }; (y: z + y) 10)

  # a `with` inside the body: its names are dynamic, not undefined
  (let f = y: with { z = y; }; (w: z + w); in (f 1) 2)
  (let f = y: with { z = y; }; z; in f 7)

  # base names and lexical names together
  (let g = x: x; in (y: g y + builtins.length [ y ]) 3)

  # the names a `rec` set binds are its own
  (let f = y: rec { p = q + y; q = a; }; in (f 1).p)

  # a lambda that is never called still has its free names resolved when it is lowered
  (let unused = x: x + a; in 0)
]
