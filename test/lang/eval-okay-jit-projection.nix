# Projected arguments remain lazy across native callee guards and saturated
# calls. A reached selection preserves the owning set and current key.
let
  dead = throw "projection JIT forced an unused value";
  warm = f: builtins.foldl' (acc: unused: builtins.seq (f "field") acc) 0
    (builtins.genList (i: i) 80);
  pred = name: value: builtins.isBool value;
  make = set: name: !(pred name set.${name});
  yes = make { field = true; other = 42; };
  no = make { field = 42; other = false; };
  ignore = name: value: false;
  ignoreMake = set: name: !(ignore name set.${name});
  ignored = ignoreMake dead;
  nameOnly = name: value: builtins.isString name;
  named = set: name: !(nameOnly name set.${name});
  static = set: name: !(pred name set.field);
  defaulted = set: name: !(pred name (set.${name} or false));
  nested = set: name: !(pred name set.inner.${name});
  call = predicate: set: name: !(predicate name set.${name});
  changed = call ignore dead;
  bool = a: b: a && b;
  three = a: b: c: a && b && c;
  four = a: b: c: d: a && b && c && d;
  wrap2 = a: b: !(bool a b);
  wrap3 = a: b: c: !(three a b c);
  wrap4 = a: b: c: d: !(four a b c d);
  base = builtins.listToAttrs (builtins.genList
    (i: { name = "k${toString i}"; value = dead; }) 64);
  layered = base // { k31 = true; };
  layer = make layered;
  alias = key: choose: predicate: set:
    if choose then (name: value: builtins.isBool set.${key})
    else !(predicate key set.${key});
  factory = alias "old" true (n: v: false);
  old = factory { old = true; };
in
assert warm yes == 0;
assert !(yes "field");
assert yes "other";
assert no "field";
assert !(no "other");
assert warm (ignoreMake { field = true; }) == 0;
assert ignored dead;
assert !(named dead "field");
assert warm (static { field = false; }) == 0;
assert !(static { field = true; } dead);
assert make { field = { nested = dead; }; } "field";
assert !(defaulted {} "absent");
assert !(nested { inner.field = false; } "field");
assert warm (call pred { field = true; }) == 0;
assert changed dead;
assert wrap2 false dead;
assert wrap3 false dead dead;
assert wrap4 false dead dead dead;
assert !(layer "k31");
assert builtins.length (builtins.attrNames layered) == 64;
assert !(layer "k31");
assert builtins.seq old (!(alias dead false old dead));
assert builtins.tryEval (make { field = dead; } "field") == { success = false; value = false; };
assert !(yes "field");
true
