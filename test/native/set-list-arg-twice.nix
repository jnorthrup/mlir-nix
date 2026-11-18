# an argument's list used twice is one cell: «repeated»
(l: { a = l; b = l; }) (builtins.genList (i: i) 3)
