let
  f = x: builtins.isFunction x || (x ? __functor && f (x.__functor x));
  warm = builtins.seq (f false) (builtins.seq (f {}) (builtins.seq (f "warm") (f null)));
in builtins.seq warm [
  (f (builtins.trace "native argument once" (x: x)))
  (f { unused = throw "unused field"; })
  (f { __functor = self: x: x; })
]
