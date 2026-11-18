# A seven-option corpus (options.nix, etc.nix) for mini-luci's tests, in the same row form as nixos/eval.nix; given a
# `request`, the facets it asks for (answer.nix).
{ lib ? import ./lib, settings ? ./settings.json, overlay ? null, request ? null, ... }:
let
  json = f: { _file = toString f; config = builtins.fromJSON (builtins.readFile f); };
  # A what-if wins over the configuration: each value of the overlay at mkForce's priority.
  force = v: if builtins.isAttrs v then builtins.mapAttrs (_: force) v else { _type = "override"; priority = 50; content = v; };
  # named, so that an option's adhesion (answer.nix) says which values the what-if gives
  forced = f: { _file = "mini-luci what-if"; config = force (builtins.fromJSON (builtins.readFile f)); };
  evaluated = lib.evalModules {
    modules = [ ./options.nix ./etc.nix (json settings) ] ++ (if overlay == null then [ ] else [ (forced overlay) ]);
  };
in
if request == null then import ../corpus.nix { inherit lib evaluated; root = toString ./.; etc = evaluated.config.etc; }
else import ../answer.nix { inherit lib evaluated overlay request; root = toString ./.; target = toString ./eval.nix; }
