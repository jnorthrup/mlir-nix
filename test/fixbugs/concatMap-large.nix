builtins.length (builtins.concatMap (x: [ x ]) (builtins.genList (x: x) 1000000))
