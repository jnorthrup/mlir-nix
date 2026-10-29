# Saturated chains may share one Boolean plan. Partial and escaping closures
# still carry their original captures, and each supplied argument stays lazy.
let
  dead = throw "curried JIT forced an unused value";
  warm = f: builtins.foldl' (acc: x: builtins.seq (f x x) acc) 0
    (builtins.genList (i: i < 40) 80);
  both = a: b: builtins.isBool a && builtins.isBool b;
  first = a: ignored: builtins.isBool a;
  last = ignored: b: builtins.isBool b;
  choose = a: b: c: if a then b else !c;
  four = a: b: c: d: (a && b) || (c && d);
  make = captured: a: b: builtins.isBool a && (captured || b);
  yes = make true;
  no = make false;
  isFunction = x:
    builtins.isFunction x || (x ? __functor && isFunction (x.__functor x));
  wrapper = unused: value: !(isFunction value);
  conjunction = a: b: a && b;
  partial = conjunction false;
  triple = a: b: c: a || b || c;
  underapplied = triple false false;
  escape = choose: captured: if choose then (x: captured && x) else builtins.isBool captured;
  escaped = escape true false;
  alias = flag: choose: pred: x: if choose then (y: flag) else !(pred x);
  oldStage = alias false true (x: false);
  old = oldStage 0;
  local = a: let needed = a; in b: if b then !needed else false;
  defaulted = { flag ? true }: b: flag && b;
  recursive = a: b: if builtins.isBool a then !b else recursive b a;
in
assert warm both == 0;
assert both true false;
assert !(both 42 dead);
assert warm first == 0;
assert first true dead;
assert warm last == 0;
assert last dead false;
assert !(choose true false dead);
assert choose false dead false;
assert four true true dead dead;
assert !(four false dead false dead);
assert warm no == 0;
assert yes true dead;
assert !(no true false);
assert warm wrapper == 0;
assert wrapper dead { unused = dead; };
assert !(wrapper dead (x: x));
assert !(wrapper dead { __functor = self: x: x; });
assert warm conjunction == 0;
assert builtins.isFunction partial;
assert builtins.functionArgs partial == {};
assert !(partial dead);
assert builtins.isFunction underapplied;
assert triple true false false;
assert !(triple false false false);
assert underapplied true;
assert warm escape == 0;
assert builtins.isFunction escaped;
assert !(escaped dead);
assert builtins.seq old (alias true false old true);
assert alias false false old true;
assert !(local true true);
assert !(local dead false);
assert defaulted {} true;
assert !(defaulted { flag = false; } dead);
assert warm recursive == 0;
assert recursive true false;
assert builtins.tryEval (both dead true) == { success = false; value = false; };
assert both true false;
true
