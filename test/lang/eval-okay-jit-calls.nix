# A reached call may inline its Boolean graph, but its target and captures
# belong to the current closure. Unused callees, arguments and fields stay lazy.
let
  dead = throw "call JIT forced an unused value";
  warm = f: builtins.foldl' (acc: x: builtins.seq (f x) acc) 0
    (builtins.genList (i: i < 40) 80);
  wrap = callee: x: !(callee x);
  isFunction = x:
    builtins.isFunction x || (x ? __functor && isFunction (x.__functor x));
  f = wrap isFunction;
  pred = flag: x: flag && builtins.isBool x;
  yes = pred true;
  no = pred false;
  yesWrapper = wrap yes;
  noWrapper = wrap no;
  different = x: false;
  changed = wrap different;
  functor = { __functor = self: x: false; };
  dynamic = wrap functor;
  guarded = callee: x: x || !(callee x);
  liveGuard = guarded yes;
  deadGuard = guarded dead;
  fields = x: x ? field;
  missing = wrap fields;
  formal = { value ? false }: value;
  formalWrapper = wrap formal;
  bool = x: builtins.isBool x;
  boolWrapper = wrap bool;
  localArgument = x: !(bool (if x then true else false));
  recursive = x: if builtins.isBool x then x else recursive x;
  recursiveWrapper = wrap recursive;
  c0 = x: builtins.isBool x;
  c1 = x: !(c0 x);
  c2 = x: !(c1 x);
  c3 = x: !(c2 x);
  c4 = x: !(c3 x);
  c5 = x: !(c4 x);
  c6 = x: !(c5 x);
in
assert warm f == 0;
assert f { field = dead; };
assert !(f (x: x));
assert !(f builtins.add);
assert !(f (builtins.add 1));
assert !(f { __functor = self: x: x; unused = dead; });
assert warm yesWrapper == 0;
assert builtins.seq no (noWrapper dead);
assert !(yesWrapper true);
assert noWrapper false;
assert builtins.seq different (changed dead);
assert builtins.seq functor (dynamic dead);
assert (wrap builtins.isBool) 42;
assert warm liveGuard == 0;
assert deadGuard true;
assert warm missing == 0;
assert !(missing { field = dead; });
assert missing { absent = dead; };
assert formalWrapper {};
assert !(formalWrapper { value = true; });
assert warm boolWrapper == 0;
assert builtins.tryEval (boolWrapper dead) == { success = false; value = false; };
assert !(boolWrapper false);
assert builtins.tryEval ((wrap dead) dead) == { success = false; value = false; };
assert !(boolWrapper true);
assert warm localArgument == 0;
assert !(localArgument false);
assert warm recursiveWrapper == 0;
assert recursiveWrapper false;
assert !(recursiveWrapper true);
assert warm c6 == 0;
assert c6 true;
assert !(c6 42);
true
