let
  predicate = x: builtins.isFunction x || (x ? __functor && predicate (x.__functor x));
  make = captured: flag: pred: value: if flag then !captured else !(pred value);
  a = make true;
  b = make false;
  warm = builtins.seq (a false predicate false) (builtins.seq (a false predicate {})
    (builtins.seq (a false predicate "warm") (a false predicate null)));
in builtins.seq warm [
  (a true (throw "unused callee") (throw "unused argument"))
  (b true (throw "unused callee") (throw "unused argument"))
  (a false predicate (builtins.trace "curried argument once" (x: x)))
  (a false builtins.isBool (builtins.trace "changed callee argument once" true))
]
