# length of a filter over a series
builtins.length (builtins.filter (x: x > 1) (builtins.genList (i: i) 4))
