let optional = cond: elem: if cond then [ elem ] else [ ];
    optionalAttrs = cond: as: if cond then as else { };
    t = builtins.trace;
    lazyElem = optional true (throw "never forced");         # the element stays lazy
    thunkCond = optional (1 < 2) 7;                          # the condition is forced
    partial = optional true;                                 # partial application: not saturated
    over = (optionalAttrs true { f = x: x; }).f 5;           # the result is used
    oc = optionalAttrs false (throw "unused");                # the else branch never forces the argument
    many = builtins.map (optional true) [ 1 2 3 ];           # partial application through map
in { inherit thunkCond over oc; n = builtins.length lazyElem; p = (partial 3); m = many;
     both = optional true 1 ++ optional false 2 ++ optional true 3; s = optionalAttrs true { a = 1; } // optionalAttrs false { b = 2; }; }
