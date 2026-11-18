# a branch that fails, not taken
if builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) > 100 then { }.x else 5
