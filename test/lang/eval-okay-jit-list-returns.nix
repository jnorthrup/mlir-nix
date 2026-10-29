# Returned lists retain element cells; constructing them does not force their
# elements, including recursive values and computations in captured frames.
let
  dead = throw "list return JIT forced an element";
  warm = f: builtins.foldl' (acc: unused: builtins.seq (f dead) acc) 0
    (builtins.genList (i: i) 80);
  singleton = x: [ x ];
  duplicate = x: [ x x x x ];
  two = a: b: [ b a ];
  three = a: b: c: [ c a b ];
  four = a: b: c: d: [ d b a c ];
  optional = condition: value: if condition then [ value ] else [];
  make = seed: let delayed = seed + 1; in ignored: [ delayed ];
  old = make 6;
  new = make 8;
  inner = x: singleton x;
  outer = x: inner x;
  projected = set: singleton set.field;
  local = x: [ (x + 1) ];
  tooLong = x: [ x x x x x ];
  cycle = cycle;
  productive = singleton productive;
  maker = captured: ignored: captured;
  escaped = singleton (maker 37);
  alias = captured: choose: pred: arg:
    if choose then (ignored: [ captured ]) else pred arg;
  oldStage = alias "old" true (x: []);
  oldClosure = oldStage null;
in
assert warm singleton == 0;
assert builtins.length (singleton dead) == 1;
assert builtins.length (singleton cycle) == 1;
assert builtins.length productive == 1;
assert builtins.length (builtins.head productive) == 1;
assert builtins.head (singleton 42) == 42;
assert builtins.length (singleton { lazy = dead; }) == 1;
assert builtins.attrNames (builtins.head (singleton { lazy = dead; })) == [ "lazy" ];
assert warm duplicate == 0;
assert duplicate 7 == [ 7 7 7 7 ];
assert builtins.length (duplicate dead) == 4;
assert two 1 2 == [ 2 1 ];
assert three 1 2 3 == [ 3 1 2 ];
assert four 1 2 3 4 == [ 4 2 1 3 ];
assert builtins.length (optional true dead) == 1;
assert optional false dead == [];
assert warm old == 0;
assert builtins.head (new dead) == 9;
assert builtins.head (old dead) == 7;
assert warm outer == 0;
assert builtins.length (outer dead) == 1;
assert (builtins.head escaped) dead == 37;
assert builtins.length (projected dead) == 1;
assert builtins.head (projected { field = 9; }) == 9;
assert builtins.length (local dead) == 1;
assert builtins.head (local 41) == 42;
assert builtins.length (tooLong dead) == 5;
assert builtins.seq oldClosure (alias "new" false oldClosure dead) == [ "old" ];
assert builtins.tryEval (builtins.head (singleton dead)) == { success = false; value = false; };
assert builtins.head (singleton 42) == 42;
true
