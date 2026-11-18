# refused: an if whose branches are a set and a set
# (a set is known while writing; one chosen at run time is not)
if builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) > 1 then { a = 1; } else { a = 2; }
