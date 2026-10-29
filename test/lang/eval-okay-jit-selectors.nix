# Generic native returns must preserve WHNF strictness, captured environments,
# and sharing while leaving unselected branches and collection elements lazy.
let
  inputs = builtins.genList (x: x) 80;
  warm = f: builtins.foldl'
    (acc: x: builtins.seq (f x) acc) 0 inputs;
  id = x: x;
  constant = captured: ignored: captured;
  attrs = condition: value: if condition then value else {};
  list = condition: value: if condition then value else [];
  string = condition: value: if condition then value else "";
  reverse = condition: value: if condition then [] else value;
  dead = throw "JIT forced an unselected value";
  cycle = cycle;
  sharedSet = { unused = dead; };
  sharedList = [ dead ];
  function = { answer, ... }: answer;
in
assert warm id == 0;
assert id sharedSet == sharedSet;
assert id sharedList == sharedList;
assert builtins.length (id sharedList) == 1;
assert builtins.functionArgs (id function) == { answer = false; };
assert (id function) { answer = 42; } == 42;
assert warm (constant true) == 0;
assert constant "new capture" dead == "new capture";
assert constant sharedSet cycle == sharedSet;
assert constant sharedList dead == sharedList;
assert warm (attrs true) == 0;
assert attrs false dead == {};
assert attrs true sharedSet == sharedSet;
assert attrs false cycle == {};
assert attrs true { answer = 42; } == { answer = 42; };
assert builtins.attrNames (attrs true sharedSet) == [ "unused" ];
assert warm (list true) == 0;
assert list false dead == [];
assert builtins.length (list true sharedList) == 1;
assert list false cycle == [];
assert list true [ 1 2 ] == [ 1 2 ];
assert warm (string true) == 0;
assert string false dead == "";
assert string true "new capture" == "new capture";
assert string false cycle == "";
assert warm (reverse false) == 0;
assert reverse true dead == [];
assert reverse false sharedList == sharedList;
assert builtins.tryEval (attrs (throw "condition") dead) == { success = false; value = false; };
assert builtins.tryEval (attrs true dead) == { success = false; value = false; };
assert builtins.tryEval (id dead) == { success = false; value = false; };
assert builtins.tryEval (constant dead cycle) == { success = false; value = false; };
true
