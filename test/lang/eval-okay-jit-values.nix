# Native value tails may copy existing WHNF cells, preserving their contexts,
# captures and lazy children. Boolean consumers still require Boolean values.
let
  dead = throw "value JIT forced an unused value";
  warm = f: builtins.foldl' (acc: unused: builtins.seq (f { field = 7; }) acc) 0
    (builtins.genList (i: i) 80);
  select = set: set.field;
  dynamic = set: key: set.${key};
  set = { lazy = dead; };
  list = [ dead ];
  context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; };
  text = builtins.appendContext "retained" context;
  maker = captured: ignored: captured;
  old = maker 37;
  escaped = select { field = old; };
  choose = condition: left: right: if condition then left else right;
  mixed = condition: value: if condition then value else builtins.isBool value;
  first = a: ignored: a;
  middle = ignored: b: ignored2: b;
  last = ignored: ignored2: ignored3: d: d;
  identity = x: x;
  inner = x: identity x;
  outer = x: inner x;
  strict = x: !(inner x);
  alias = captured: condition: pred: arg:
    if condition then (ignored: captured) else pred arg;
  oldStage = alias "old" true identity;
  oldClosure = oldStage null;
  base = builtins.listToAttrs (builtins.genList
    (i: { name = "k${toString i}"; value = dead; }) 64);
  layered = base // { k31 = list; };
  optionalAttrs = condition: value: if condition then value else {};
  optionalList = condition: value: if condition then [] else value;
  optionalString = condition: value: if condition then value else "";
  empty = ignored: {};
  emptyInner = x: empty x;
  emptyOuter = x: emptyInner x;
in
assert warm select == 0;
assert select { field = null; } == null;
assert !(select { field = false; });
assert select { field = 42; } == 42;
assert select { field = 1.5; } == 1.5;
assert builtins.isPath (select { field = ./.; });
assert select { field = text; } == "retained";
assert builtins.getContext (select { field = text; }) == context;
assert select { field = set; } == set;
assert select { field = list; } == list;
assert builtins.attrNames (select { field = set; }) == [ "lazy" ];
assert builtins.length (select { field = list; }) == 1;
assert builtins.isFunction escaped;
assert escaped dead == 37;
assert (select { field = maker 91; }) dead == 91;
assert (select { field = builtins.add; }) 2 3 == 5;
assert (select { field = builtins.add 4; }) 5 == 9;
assert dynamic { a = 7; b = "new"; } "a" == 7;
assert dynamic { a = 7; b = "new"; } "b" == "new";
assert builtins.length (dynamic layered "k31") == 1;
assert choose true set dead == set;
assert choose false dead list == list;
assert mixed true set == set;
assert mixed false false;
assert !(mixed false 42);
assert first set dead == set;
assert middle dead list dead == list;
assert last dead dead dead text == text;
assert outer set == set;
assert !(strict true);
assert builtins.seq oldClosure (alias "new" false oldClosure dead) == "old";
assert builtins.tryEval (select { field = dead; }) == { success = false; value = false; };
assert select { field = "after"; } == "after";
assert optionalAttrs false dead == {};
assert optionalAttrs true set == set;
assert optionalList true dead == [];
assert optionalList false list == list;
assert optionalString false dead == "";
assert builtins.getContext (optionalString true text) == context;
assert builtins.getContext (optionalString false text) == {};
assert emptyOuter dead == {};
true
