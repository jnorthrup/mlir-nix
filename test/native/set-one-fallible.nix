# a printed set with one value that may fail
{ a = 1; s = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4); }
