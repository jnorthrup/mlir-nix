# length does not force the elements: the second one's overflow never happens
builtins.length (builtins.map (x: x * 4611686018427387904) [ 1 2 ])
