# With --json: [false,true,false]
# Exactly these stderr traces, in order: projection key, projection base, projection field.
let
  makePredicate = enabled: name: value:
    if enabled then builtins.isBool value else false;
  enabledPredicate = makePredicate true;
  disabledPredicate = makePredicate false;
  apply = pred: name: set: !(pred name set.${name});
  warm = builtins.genList (_: apply enabledPredicate "k" { k = true; }) 4;
in
builtins.seq enabledPredicate (builtins.seq disabledPredicate (
  builtins.deepSeq warm [
    (apply enabledPredicate
      (builtins.trace "projection key" "k")
      (builtins.trace "projection base" {
        k = builtins.trace "projection field" true;
      }))
    (apply disabledPredicate
      (throw "ignored projected key")
      (throw "ignored projected base"))
    (apply enabledPredicate "k" { k = false; })
  ]
))
