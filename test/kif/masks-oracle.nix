# sumo-masks.mlir's oracle: SumoClassifier's INSTANCES and DISJOINT masks over sumo-nix's sumo.nix, with sumo.nix's reading of
# an argument (anything but a list).
#   mlnix eval --strict --json --arg sumo <sumo-nix> --arg files '[ ./a.kif ./b.kif ]' test/kif/masks-oracle.nix
# instance types: a thing's classes (classOf) and their ancestors, each once (sumo.nix's isInstance x c holds for exactly
# these c).  disjoint: a class's mask is every class declared disjoint from it or from one of its ancestors ((disjoint A B),
# and the parts of a (partition W P1 .. Pn) or (disjointDecomposition W P1 .. Pn), n >= 2, pairwise), with their
# descendants, each once.
{ sumo, files }:
let
  inherit (builtins) all attrNames attrValues concatLists concatMap elemAt filter foldl' genList genericClosure head isList isString
    length listToAttrs tail zipAttrsWith;
  kif = import (sumo + "/kif.nix");
  forms = concatMap (f: kif.parse (builtins.readFile f)) files;
  o = import (sumo + "/sumo.nix") { inherit forms; };
  sum = foldl' (a: b: a + b) 0;
  unique = xs: attrNames (listToAttrs (map (name: { inherit name; value = null; }) xs));
  top = name: filter (f: isList f && f != [ ] && head f == name) forms;
  closed = start: step: map (e: e.key) (filter (e: !e.start) (genericClosure {
    startSet = map (k: { key = k; start = false; }) start;
    operator = e: map (k: { key = k; start = false; }) (step e.key);
  }));
  types = x: unique (concatMap (k: [ k ] ++ (o.ancestors.${k} or [ ])) o.classOf.${x});
  children = zipAttrsWith (_: concatLists) (concatMap (c: map (p: { ${p} = [ c ]; }) (o.parents.${c} or [ ])) (attrNames o.parents));
  belowMemo = listToAttrs (map (d: { name = d; value = closed [ d ] (c: children.${c} or [ ]); }) (attrNames o.classes));
  below = d: belowMemo.${d} or (closed [ d ] (c: children.${c} or [ ]));
  pairs = concatMap (f: if length f == 3 && isString (elemAt f 1) && isString (elemAt f 2) then [ [ (elemAt f 1) (elemAt f 2) ] [ (elemAt f 2) (elemAt f 1) ] ] else [ ]) (top "disjoint")
    ++ concatMap (f:
      let parts = tail (tail f); n = length parts; in
      if length f >= 4 && all isString (tail f) then
        concatMap (i: concatMap (j: if i == j then [ ] else [ [ (elemAt parts i) (elemAt parts j) ] ]) (genList (j: j) n)) (genList (i: i) n)
      else [ ]) (top "partition" ++ top "disjointDecomposition");
  declared = zipAttrsWith (_: concatLists) (map (p: { ${head p} = [ (elemAt p 1) ]; }) pairs);
  mask = c: unique (concatMap (a: concatMap (d: [ d ] ++ below d) (declared.${a} or [ ])) ([ c ] ++ (o.ancestors.${c} or [ ])));
  things = attrNames o.classOf;
  classes = attrNames o.classes;
in [
  # things, instance-type links, classes, disjoint links
  [ (length things) (sum (map (x: length (types x)) things)) (length classes) (sum (map (c: length (mask c)) classes)) ]
  # each thing, by name: its number of classes
  (map (x: length (types x)) things)
  # each class, by name: the number of classes disjoint from it
  (map (c: length (mask c)) classes)
]
