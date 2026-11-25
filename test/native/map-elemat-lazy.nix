# elemAt forces only the element it is asked for: the first one, which does not overflow
builtins.elemAt (builtins.map (x: x * 4611686018427387904) [ 1 2 ]) 0
