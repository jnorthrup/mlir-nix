# a set pattern applied in a fold's step
builtins.foldl' (acc: i: acc + ({ a, b ? 2 }: a * b) { a = i; }) 0 (builtins.genList (i: i) 10)
