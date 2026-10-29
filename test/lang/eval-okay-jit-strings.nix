# Generic byte comparisons and bounded Select paths preserve lazy demand order.
let
  dead = throw "string comparison JIT forced an unused value";
  warm = f: builtins.foldl' (acc: unused: builtins.seq (f "match") acc) 0
    (builtins.genList (i: i) 80);
  equal = x: x == "match";
  unequal = x: "match" != x;
  pair = left: right: left == right;
  make = captured: x: x == captured;
  old = make "old";
  new = make "new";
  conditional = condition: left: right: if condition then left == right else false;
  context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; };
  contextual = builtins.appendContext "match" context;
  text = "a\nb";
  otherText = "a\nc";
  projected = set: set.a.b.c == "match";
  dynamic = set: key: set.${key} == "match";
  helper = left: right: left == right;
  middle = left: right: helper left right;
  outer = left: right: middle left right;
  three = a: b: c: a == b;
  four = a: b: c: d: a == b;
  shared = [ dead ];
  local = x: builtins.substring 0 5 x == "match";
  fallback = set: (set.a.b or "match") == "match";
  alias = captured: choose: pred: arg:
    if choose then (x: x == captured) else pred arg;
  oldStage = alias "old" true (x: false);
  oldClosure = oldStage null;
in
assert warm equal == 0;
assert warm unequal == 0;
assert equal "match" && !equal "other" && !unequal "match" && unequal "other";
assert pair text text && !pair text otherText && !pair text "a";
assert pair "λ雪" "λ雪" && !pair "λ雪" "雪λ";
assert equal contextual && builtins.getContext contextual == context;
assert conditional false dead dead == false;
assert pair 7 7.0 && pair null null && !pair false "false";
assert pair [ 1 2 ] [ 1 2 ] && pair { answer = 42; } { answer = 42; };
assert pair shared shared;
assert !pair (x: x) (x: x);
assert warm old == 0;
assert new "new" && !old "new" && !new "old";
assert projected { a.b.c = "match"; unused = dead; };
assert dynamic { field = "match"; unused = dead; } "field";
assert outer "same" "same";
assert three "same" "same" dead;
assert four "same" "same" dead dead;
assert local "match rest" && fallback {};
assert builtins.seq oldClosure (alias "new" false oldClosure "old");
assert builtins.tryEval (pair "match" dead) == { success = false; value = false; };
assert pair "after" "after";
true
