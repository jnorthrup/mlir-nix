# kif-trikeshed.mlir's oracle: sumo-nix's sumo.nix over the KIF files, counted as sumo-bench's onto.nix counts sumo.full.
#   mlnix eval --strict --json --arg sumo <sumo-nix> --arg files '[ ./a.kif ./b.kif ]' test/kif/taxonomy-oracle.nix
{ sumo, files }:
let
  inherit (builtins) attrNames attrValues concatMap foldl' length;
  kif = import (sumo + "/kif.nix");
  forms = concatMap (f: kif.parse (builtins.readFile f)) files;
  o = import (sumo + "/sumo.nix") { inherit forms; };
  sum = foldl' (a: b: a + b) 0;
in [
  # forms classes withParent ancestorLinks things relations humanAncestors
  [
    (length forms)
    (length (attrNames o.classes))
    (length (attrNames o.parents))
    (sum (map length (attrValues o.ancestors)))
    (length (attrNames o.classOf))
    (length (attrNames o.domains))
    (length (o.ancestors.Human or [ ]))
  ]
  # each class with a parent, in the order of its name: its number of ancestors
  (map (c: length o.ancestors.${c}) (attrNames o.ancestors))
]
