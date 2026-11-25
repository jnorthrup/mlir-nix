builtins.foldl' (a: b: a + b) 0 (builtins.genList (x: x) 2000000)
