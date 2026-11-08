# Benchmark: all of sumo-nix/sumo.full in memory: every file parsed by kif.nix, then sumo.nix's ontology over all the forms,
# forced: every class's ancestors, every thing's classes, every relation's domains.
{ root ? /home/jim/work/sumo-nix, n ? null }:
let
  inherit (builtins) filter isString split substring elemAt length foldl' genList attrNames attrValues concatMap;
  kif = import (root + "/kif.nix");
  lines = filter (l: isString l && l != "" && substring 0 1 l != "#") (split "\n" (builtins.readFile (root + "/sumo.full/PINS")));
  all = map (l: elemAt (filter isString (split " +" l)) 1) lines;
  files = if n == null then all else genList (elemAt all) n;
  forms = concatMap (f: kif.parse (builtins.readFile (root + "/sumo.full/${f}"))) files;
  o = import (root + "/sumo.nix") { inherit forms; };
  sum = foldl' (a: b: a + b) 0;
in {
  files = length files;
  forms = length forms;
  classes = length (attrNames o.classes);
  withParent = length (attrNames o.parents);
  ancestorLinks = sum (map length (attrValues o.ancestors));
  things = length (attrNames o.classOf);
  relations = length (attrNames o.domains);
  humanAncestors = length (o.ancestors.Human or [ ]);
}
