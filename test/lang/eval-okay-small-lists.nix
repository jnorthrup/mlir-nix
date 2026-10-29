# Exercise small list sizes, shared element identity, shallow copies, and lazy elements.
let
  id = x: x;
  fail = throw "an unused list element was forced";
  one = [ id ];
  alias = id one;
  two = [ 1 2 ];
  three = two ++ [ 3 ];
in
assert alias == one;
assert [ id ] == [ id ];
assert !([ (x: x) ] == [ (x: x) ]);
assert builtins.tail [ 1 ] == [ ];
assert builtins.tail two == [ 2 ];
assert builtins.tail three == [ 2 3 ];
assert builtins.map (x: x + 1) two == [ 2 3 ];
assert builtins.concatLists [ [ ] [ 1 ] [ 2 ] [ 3 ] ] == three;
assert builtins.genList id 0 == [ ];
assert builtins.genList id 1 == [ 0 ];
assert builtins.genList id 2 == [ 0 1 ];
assert builtins.genList id 3 == [ 0 1 2 ];
assert builtins.fromJSON "[1,2]" == two;
assert builtins.fromJSON "[1,2,3]" == three;
assert builtins.length [ fail fail ] == 2;
assert builtins.head [ 7 fail ] == 7;
assert builtins.head (builtins.tail [ fail 8 ]) == 8;
assert builtins.elemAt (builtins.map id [ fail 9 ]) 1 == 9;
assert builtins.tryEval (builtins.head [ fail ]) == { success = false; value = false; };
true
