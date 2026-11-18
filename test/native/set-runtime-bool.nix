# a set's Boolean known only at run time
{ t = builtins.foldl' (a: x: a + x) 0 (builtins.genList (i: i) 4) < 7; }
