let
  predicate = x: builtins.isFunction x || (x ? __functor && predicate (x.__functor x));
  wrap = callee: value: !(callee value);
  warm = builtins.seq (wrap predicate false) (builtins.seq (wrap predicate {})
    (builtins.seq (wrap predicate "warm") (wrap predicate null)));
in builtins.seq warm [
  (wrap predicate (builtins.trace "inlined argument once" (x: x)))
  (wrap predicate { unused = throw "unused field"; })
  (wrap predicate { __functor = self: x: x; })
  (wrap builtins.isBool (builtins.trace "guarded argument once" true))
]
