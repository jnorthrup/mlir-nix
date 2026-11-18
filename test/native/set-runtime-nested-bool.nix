# a nested set's Boolean known only at run time
{ a = { b = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) == 6; }; }
