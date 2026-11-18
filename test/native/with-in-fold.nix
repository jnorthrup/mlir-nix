# `with` in a fold's step
builtins.foldl' (acc: i: acc + (with { k = i; }; k)) 0 (builtins.genList (i: i) 5)
