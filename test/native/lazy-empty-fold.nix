# foldl' over nothing is its first accumulator
builtins.foldl' (a: x: a + x) 7 (builtins.genList (i: i) 0)
