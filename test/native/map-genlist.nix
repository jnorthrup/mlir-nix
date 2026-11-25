# map over a list made by genList (a series): each element computed when the list is made
builtins.map (x: x * 2) (builtins.genList (i: i) 4)
