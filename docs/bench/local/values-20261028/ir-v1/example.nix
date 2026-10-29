# Expected with --json: [42,7,2,0]
# Expected exactly one stderr trace: selected persistent list
# The initial persistent-only example is saved beside this file.
let
  makeGetter = enabled: item:
    if enabled then item.value else [];
  getterOn = makeGetter true;
  getterOff = makeGetter false;
  hop = getter: item: getter item;
  outer = getter: item: hop getter item;
  warm = builtins.genList (_: outer getterOn { value = 0; }) 4;
  chosenClosure = outer getterOn {
    value = x: x + 1;
    ignored = throw "unselected closure field";
  };
  chosenList = outer getterOn {
    value = builtins.trace "selected persistent list" [ 7 (throw "unforced selected element") ];
    ignored = throw "unselected list field";
  };
  skipped = outer getterOff (throw "ignored projected argument");
in
builtins.seq getterOn (builtins.seq getterOff (
  builtins.deepSeq warm [
    (chosenClosure 41)
    (builtins.head chosenList)
    (builtins.length chosenList)
    (builtins.length skipped)
  ]
))
