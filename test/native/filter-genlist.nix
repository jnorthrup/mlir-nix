# filter over a series: the predicate written in the region, the kept elements in order
builtins.filter (x: x > 1) (builtins.genList (i: i) 4)
