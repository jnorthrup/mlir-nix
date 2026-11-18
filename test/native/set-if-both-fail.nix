# both branches fail
if builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) > 100 then { }.x else { }.y
