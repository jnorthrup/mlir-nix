let
  make = label:
    let captured = builtins.trace label { answer = 42; };
    in item: [ captured item captured ];
  hop = getter: item: getter item;
  outer = getter: item: hop getter item;
  first = make "unused first capture";
  second = make "selected capture once";
  warm = builtins.seq (outer first null)
    (builtins.seq (outer first null)
      (builtins.seq (outer first null) (outer first null)));
  result = outer second (throw "unused middle element");
in builtins.seq warm (builtins.seq second [
  (builtins.length result)
  (builtins.head result).answer
  (builtins.elemAt result 2).answer
])
