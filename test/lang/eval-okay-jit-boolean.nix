# Boolean compilation may demand persistent inputs, but must retain short
# circuits, captured environments, lazy fields, and unsupported-branch fallback.
let
  dead = throw "Boolean JIT forced an unused value";
  inputs = builtins.genList (i: i < 40) 80;
  warm = f: builtins.foldl' (acc: x: builtins.seq (f x) acc) 0 inputs;
  isFunction = f:
    builtins.isFunction f || (f ? __functor && isFunction (f.__functor f));
  notFunction = x: !(builtins.isFunction x);
  choose = x: if builtins.isBool x then !x else builtins.isNull x;
  both = x: (builtins.isBool x && x) || builtins.isNull x;
  implies = x: builtins.isNull x -> !(builtins.isFunction x);
  make = captured: x: builtins.isBool x && captured;
  short = captured: x: x || captured;
  exists = x: x ? field;
  existsLayer = x: x ? k31;
  valueTail = x: if true then x else false;
  shared = { field = dead; };
  base = builtins.listToAttrs (builtins.genList
    (i: { name = "k${toString i}"; value = dead; }) 64);
  layered = base // { top = dead; };
in
assert warm isFunction == 0;
assert isFunction (x: x);
assert isFunction builtins.add;
assert isFunction (builtins.add 1);
assert !(isFunction { unused = dead; });
assert isFunction { __functor = self: x: x; unused = dead; };
assert warm notFunction == 0;
assert !(notFunction (x: x));
assert notFunction { __functor = dead; };
assert warm choose == 0;
assert !(choose true);
assert choose false;
assert choose null;
assert !(choose { unused = dead; });
assert warm both == 0;
assert both true;
assert !(both false);
assert both null;
assert !(both [ dead ]);
assert warm implies == 0;
assert implies null;
assert implies (x: x);
assert warm (make true) == 0;
assert !(make false true);
assert make true false;
assert !(make dead 1);
assert warm (short true) == 0;
assert short dead true;
assert !(short false false);
assert warm exists == 0;
assert exists shared;
assert !(exists { unused = dead; });
assert warm existsLayer == 0;
assert existsLayer layered;
assert warm valueTail == 0;
assert valueTail 42 == 42;
assert valueTail shared == shared;
assert builtins.tryEval (isFunction dead) == { success = false; value = false; };
assert builtins.tryEval (make dead true) == { success = false; value = false; };
true
