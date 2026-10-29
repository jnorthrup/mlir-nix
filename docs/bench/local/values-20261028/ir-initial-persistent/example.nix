# With --json: [42,7,2,9,2]
# Exactly one stderr trace: selected persistent list
let
  makeGetter = enabled: fallback: item:
    if enabled then item.value else fallback;
  getterOn = makeGetter true (throw "unused captured fallback");
  getterOff = makeGetter false [ 9 (throw "unforced fallback element") ];
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
    (builtins.head skipped)
    (builtins.length skipped)
  ]
))
