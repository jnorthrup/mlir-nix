# a nested set's value known only at run time
{ x = { y = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4); }; }
