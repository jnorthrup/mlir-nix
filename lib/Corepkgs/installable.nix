# The installable of `nix build REF#ATTR`, `nix profile add REF#ATTR`, ...: a flake reference and an attribute path
# to a derivation, resolved the way the nix command resolves them.  Embedded as <nix/installable.nix>.
#
#   (import <nix/installable.nix>) { ref = "github:owner/repo"; attr = "pkg"; }
#
# With no attribute the flake's default package is taken (packages.<system>.default, then defaultPackage.<system>);
# with one, packages.<system>.ATTR, then legacyPackages.<system>.ATTR, then ATTR as written.
{ ref, attr ? null, system ? builtins.currentSystem }:
let
  flake = builtins.getFlake ref;

  # "a.b.\"c.d\"" as [ "a" "b" "c.d" ]
  components = s:
    let
      chars = builtins.genList (i: builtins.substring i 1 s) (builtins.stringLength s);
      go = acc: cur: quoted: cs:
        if cs == [ ] then acc ++ [ cur ]
        else
          let c = builtins.head cs; rest = builtins.tail cs; in
          if c == "\"" then go acc cur (!quoted) rest
          else if c == "." && !quoted then go (acc ++ [ cur ]) "" quoted rest
          else go acc (cur + c) quoted rest;
    in
    go [ ] "" false chars;

  has = set: path:
    if path == [ ] then true
    else builtins.isAttrs set && set ? ${builtins.head path} && has set.${builtins.head path} (builtins.tail path);
  get = set: path: if path == [ ] then set else get set.${builtins.head path} (builtins.tail path);

  candidates =
    if attr == null || attr == "" then
      [ [ "packages" system "default" ] [ "defaultPackage" system ] ]
    else
      let p = components attr; in [ ([ "packages" system ] ++ p) ([ "legacyPackages" system ] ++ p) p ];

  found = builtins.filter (p: has flake p) candidates;
in
if found == [ ] then
  throw "flake '${ref}' does not provide attribute ${builtins.concatStringsSep ", " (map (p: builtins.concatStringsSep "." p) candidates)}"
else
  get flake (builtins.head found)
