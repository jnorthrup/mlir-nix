# a set's value known only at run time
{ s = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4); }
