# elemAt forces the second element, which overflows
builtins.elemAt (builtins.map (x: x * 4611686018427387904) [ 1 2 ]) 1
